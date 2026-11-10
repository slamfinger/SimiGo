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
/// `SettlementIdentityBinding` and `ISAdmission` already consume.
enum ProducerIdentity {

    /// SHA-256 (production digest) over canonical sorted-key JSON.
    static func canonicalFingerprint(_ value: Any) -> String {
        let canonical = (try? JSONSerialization.data(
            withJSONObject: value, options: [.sortedKeys])) ?? Data()
        return SettlementAuthority.payloadDigest(canonical)
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
    /// PRODUCTION ModelDiscovery, matching the resolved weight file under
    /// the given snapshot path. Records model instance + revision, not a path.
    static func modelIdentity(fromPath path: String) -> [String: Any] {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let match = ModelDiscovery.discover().first {
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
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory)
        else { return [] }
        if !isDirectory.boolValue {
            // A GGUF checkpoint is a single weight file with the tokenizer
            // embedded, so its identity is the file's content digest — resolved
            // once per file stamp and shared (GGUFModelIdentity caches the hash).
            let attributes = try? FileManager.default.attributesOfItem(atPath: dir.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            guard let gguf = try? GGUFModelIdentity.resolve(path: dir.path) else {
                // Unreadable is not "the same as the name": it is its own
                // answer, and it can never match a hashable file.
                return [[
                    "file": dir.lastPathComponent, "size": size,
                    "content": GGUFModelIdentity.unreadableMarker,
                ]]
            }
            return [[
                "file": dir.lastPathComponent, "sha256": gguf.contentSHA256,
                "size": size,
            ]]
        }
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.lastPathComponent.lowercased().contains("tokenizer")
                       || $0.lastPathComponent.lowercased().contains("vocab") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { f in
                guard let data = try? Data(contentsOf: f) else { return nil }
                return ["file": f.lastPathComponent,
                        "sha256": SettlementAuthority.payloadDigest(data)]
            }
    }

    /// The `Identity` used for BOTH the producer side of a settlement and the
    /// consumer side of a continuation admission for the model resolved at
    /// `path`. Kept identical so a real settle -> admit round-trip verifies.
    ///
    /// A single-file GGUF resolves through `GGUFModelIdentity`: its content
    /// digest IS the identity. The snapshot fingerprint above cannot serve that
    /// case, because for a file outside the hub layout repo/revision are both
    /// null — two checkpoints with the same name and size would bind to the same
    /// producer and admit each other's settlements.
    ///
    /// Both values a runtime needs — the durable model identity and the
    /// producer identity — come from ONE resolution: resolving them separately
    /// let an unreadable checkpoint answer "unreadable" to the producer path and
    /// a name+size fallback to the model-identity path, so the two halves of the
    /// same runtime disagreed about the same file.
    static func identities(
        fromPath path: String
    ) -> (model: String, producer: SettlementIdentityBinding.Identity) {
        if let gguf = ggufModelIdentity(fromPath: path) {
            return (gguf.modelIdentity, gguf.producer)
        }
        if isRegularFile(path) {
            // A checkpoint whose bytes cannot be read must not fall back to
            // name+size — that is the collision this identity exists to remove.
            // The marker is used on both sides, so the pair stays consistent.
            let marker = GGUFModelIdentity.unreadableMarker
            let model = GGUFModelIdentity.contentFingerprint(
                sha256: marker, byteCount: byteCount(of: path))
            return (
                model,
                SettlementIdentityBinding.Identity(
                    model: model,
                    tokenizer: GGUFModelIdentity.tokenizerFingerprint(
                        modelContentSHA256: marker)))
        }
        let model = modelBindingFingerprint(modelIdentity(fromPath: path))
        return (
            model,
            SettlementIdentityBinding.Identity(
                model: model,
                tokenizer: canonicalFingerprint(tokenizerIdentity(fromPath: path))))
    }

    static func identity(fromPath path: String) -> SettlementIdentityBinding.Identity {
        identities(fromPath: path).producer
    }

    /// A single durable identity string for an execution state: the model
    /// binding fingerprint, never the snapshot path. Two states of the same
    /// model revision carry the same value; a different model or revision does
    /// not.
    static func canonicalModelIdentity(fromPath path: String) -> String {
        identities(fromPath: path).model
    }

    /// The content identity of a single-file checkpoint, or nil for a directory
    /// (an MLX snapshot keeps its repo/revision identity) and for a file whose
    /// bytes cannot be read.
    static func ggufModelIdentity(fromPath path: String) -> GGUFModelIdentity? {
        try? GGUFModelIdentity.resolve(path: path)
    }

    private static func isRegularFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return false
        }
        return !isDirectory.boolValue
    }

    private static func byteCount(of path: String) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Drive the authoritative store's IS admission for a live continuation:
    /// recover the verified settled value for `stateID` under the consumer
    /// identity of the model resolved at `modelPath`, or throw a typed,
    /// fail-closed refusal. It returns the FULL `Admitted` record — the value
    /// alone would drop the bindings the settlement gate is required to use —
    /// and throws only the product `ContinuationAdmissionFailure`. Reuses the
    /// existing `ExecutionStateGraphStore.admitContinuation` -> native
    /// `ISAdmission` authority; it opens no second settlement gate or
    /// database.
    @MainActor
    static func recoverForContinuation(
        stateID: String,
        modelPath: String
    ) throws -> ISAdmission.Admitted {
        let store = ExecutionStateGraphStore()
        let consumer = identity(fromPath: modelPath)
        do {
            return try store.admitContinuation(
                stateID: stateID, consumer: consumer)
        } catch let refusal as ISAdmission.Refusal {
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

    /// Drive the product's single zero-call consumption transaction for an
    /// explicitly named settled result. The consumer identity is re-derived from
    /// THIS runtime's model snapshot (a request assertion is only compared, never
    /// trusted), the consumer Execution State is fresh, and every refusal is a
    /// typed failure — nothing falls back to generation here.
    @MainActor
    static func consumeSettlement(
        entry: SettlementConsumptionEntry,
        modelPath: String
    ) throws -> SettlementConsumptionOutcome {
        let identity = identity(fromPath: modelPath)
        if let asserted = entry.identityAssertion, asserted != identity {
            throw SettlementConsumptionFailure.identityMismatch
        }
        let store = ExecutionStateGraphStore()
        let request = SettlementConsumption.Request(
            sourceSettlementID: entry.sourceSettlementID,
            consumerStateID: "es-" + UUID().uuidString.lowercased(),
            consumerParentStateID: nil,
            consumerPosition: 1,
            consumerModelIdentity: identity.model,
            consumerIdentity: identity,
            contractID: entry.contractID,
            demandClass: entry.demandClass,
            contractVersion: entry.contractVersion,
            extractField: entry.extractField,
            query: entry.query,
            rootIDs: entry.rootIDs,
            allowRecompute: entry.allowRecompute,
            resultContractJSON: InformationLoop.chatResultContractJSON,
            consumedAt: Date())
        do {
            switch try store.consumeSettlement(request) {
            case .consumed(let consumed):
                return .consumed(SettlementConsumptionReceipt(
                    consumptionID: consumed.consumptionID,
                    sourceSettlementID: consumed.sourceSettlementID,
                    consumerESStateID: consumed.consumerStateID,
                    consumerSettlementID: consumed.consumerSettlementID,
                    demandID: consumed.demandID,
                    canonicalDigest: consumed.canonicalDigest,
                    value: consumed.value,
                    modelCalls: consumed.modelCalls,
                    reusedExisting: consumed.reusedExisting,
                    contractID: entry.contractID,
                    demandClass: entry.demandClass,
                    contractVersion: entry.contractVersion,
                    extractField: entry.extractField))
            case .recompute(let reason):
                return .recompute(reason: reason)
            }
        } catch let refusal as SettlementConsumption.Refusal {
            throw SettlementConsumptionFailure.refused(
                code: refusal.reasonCode, detail: String(describing: refusal))
        } catch let refusal as ISAdmission.Refusal {
            // Known, typed IS admission verdict -> business refusal (422). Only
            // the enumerated denial reasons are classified here; store and IO
            // faults do not surface as this type and stay 500 below.
            throw Self.consumptionRefusal(refusal)
        } catch ExecutionGraphError.storeUnavailable {
            throw SettlementConsumptionFailure.unavailable
        } catch let failure as SettlementConsumptionFailure {
            throw failure
        } catch {
            throw SettlementConsumptionFailure.engine(
                "authoritative settlement consumption unavailable")
        }
    }

    /// Stable HTTP reason codes for native admission denials. Each case names
    /// WHICH precondition failed, so a consumer can distinguish a tampered
    /// source from an invalidated one or a broken dependency.
    private static func consumptionRefusal(
        _ refusal: ISAdmission.Refusal
    ) -> SettlementConsumptionFailure {
        let code: String
        switch refusal {
        case .noSettlement, .unknownSettlement:
            code = "unknown_source"
        case .digestMismatch:
            code = "source_tampered"
        case .invalidated:
            code = "source_not_valid"
        case .dependencyMissing:
            code = "dependency_missing"
        case .dependencyInvalid:
            code = "dependency_invalid"
        case .producerBinding(let verdict):
            code = verdict.code ?? "identity_binding_refused"
        case .emptyValue:
            code = "empty_value"
        }
        return .refused(code: code, detail: String(describing: refusal))
    }
}
