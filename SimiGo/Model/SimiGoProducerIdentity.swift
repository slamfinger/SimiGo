import Foundation
import SimiGoRuntimeContract

/// Canonical producer/consumer identity for ES/IS settlement bindings.
///
/// This is the SINGLE source of the fingerprint formula (identity-bearing model
/// fields — repo id / revision / root id — plus content digests of the snapshot
/// tokenizer artifacts). The headless G1/G3 driver derives its producer and
/// consumer identities the same way, so a real model's settle -> admit
/// round-trip resolves to an identical `Identity` and verifies instead of
/// spuriously mismatching.
///
/// It is a pure re-derivation from the model snapshot on disk: it does NOT
/// rebind, re-freeze, or re-run any existing batch or experiment, and it opens
/// no second settlement authority — it only produces the `Identity` value that
/// `SimiGoSettlementIdentityBinding` and `SimiGoISAdmission` already consume.
enum SimiGoProducerIdentity {

    /// SHA-256 (production digest) over canonical sorted-key JSON.
    static func canonicalFingerprint(_ value: Any) -> String {
        let canonical = (try? JSONSerialization.data(
            withJSONObject: value, options: [.sortedKeys])) ?? Data()
        return SimiGoSettlementAuthority.payloadDigest(canonical)
    }

    /// Stable model binding fingerprint: only identity-bearing fields (repo id,
    /// revision, root id), never the filesystem path, so relocating a snapshot
    /// does not change identity while a different model or revision does.
    static func modelBindingFingerprint(_ identity: [String: Any]) -> String {
        canonicalFingerprint([
            "model_repo_id": identity["model_repo_id"] ?? NSNull(),
            "model_revision": identity["model_revision"] ?? NSNull(),
            "model_root_id": identity["model_root_id"] ?? NSNull(),
        ])
    }

    /// Resolve durable model identity (repoID + revision=snapshot hash) via the
    /// PRODUCTION SimiGoModelDiscovery, matching the resolved weight file under
    /// the given snapshot path. Records model instance + revision, not a path.
    static func modelIdentity(fromPath path: String) -> [String: Any] {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let match = SimiGoModelDiscovery.discover().first {
            $0.fileURL.standardizedFileURL.path.hasPrefix(url.path)
        }
        var out: [String: Any] = ["model_path": path]
        if let m = match {
            out["model_repo_id"] = m.repoID
            out["model_revision"] = m.revision ?? NSNull()
            out["model_root_id"] = m.rootID
        } else {
            out["model_repo_id"] = NSNull(); out["model_revision"] = NSNull()
        }
        return out
    }

    /// Tokenizer identity: content SHA-256 (production digest) of each tokenizer
    /// artifact present in the snapshot. Content-addressed, so identity is
    /// auditable, not just a filename.
    static func tokenizerIdentity(fromPath path: String) -> [[String: Any]] {
        let dir = URL(fileURLWithPath: path).standardizedFileURL
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.lastPathComponent.lowercased().contains("tokenizer")
                       || $0.lastPathComponent.lowercased().contains("vocab") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { f in
                guard let data = try? Data(contentsOf: f) else { return nil }
                return ["file": f.lastPathComponent,
                        "sha256": SimiGoSettlementAuthority.payloadDigest(data)]
            }
    }

    /// The `Identity` used for BOTH the producer side of a settlement and the
    /// consumer side of a continuation admission for the model resolved at
    /// `path`. Kept identical so a real settle -> admit round-trip verifies.
    static func identity(fromPath path: String) -> SimiGoSettlementIdentityBinding.Identity {
        SimiGoSettlementIdentityBinding.Identity(
            model: modelBindingFingerprint(modelIdentity(fromPath: path)),
            tokenizer: canonicalFingerprint(tokenizerIdentity(fromPath: path)))
    }

    /// Drive the authoritative store's IS admission for a live continuation:
    /// recover the verified settled value for `stateID` under the consumer
    /// identity of the model resolved at `modelPath`, or throw a typed,
    /// fail-closed refusal. It returns ONLY a product `String` and throws only
    /// the product `ContinuationAdmissionFailure`, so the MLX-bearing inference
    /// layer needs no contract-type import of its own. Reuses the existing
    /// `ExecutionStateGraphStore.admitContinuation` -> native `SimiGoISAdmission`
    /// authority; it opens no second settlement gate or database.
    @MainActor
    static func recoverForContinuation(
        stateID: String,
        modelPath: String
    ) throws -> String {
        let store = ExecutionStateGraphStore()
        let consumer = identity(fromPath: modelPath)
        do {
            return try store.admitContinuation(
                stateID: stateID, consumer: consumer).recoveredValue
        } catch let refusal as SimiGoISAdmission.Refusal {
            // Known, typed IS semantic refusal -> business input refusal (422).
            throw ContinuationAdmissionFailure.refused(String(describing: refusal))
        } catch let failure as ContinuationAdmissionFailure {
            // Already-typed terminal (e.g. `unavailable`) passes through unchanged.
            throw failure
        } catch {
            // Contract fix B: an UNEXPECTED internal fault (authority/store
            // unavailable, SQLite/IO failure, unclassified engine error) is NOT a
            // business input refusal. Rethrow it as-is so the route's
            // `continuationAdmissionTerminal` maps it to 500 ADMISSION_ENGINE_ERROR
            // instead of silently downgrading it to 422 INPUT_ADMISSION_REFUSED.
            throw error
        }
    }
}
