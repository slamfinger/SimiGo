import Foundation

// G7a AUTHORIZATION — a one-shot marker bound to a specific execution input.
//
// The contract the supervisor and worker share:
//   * ISSUANCE is atomic and exclusive. `issue` creates the marker with
//     O_CREAT|O_EXCL, so a second live marker for the same slot cannot exist —
//     an authorization identity is unique by construction.
//   * The marker CONTENT binds the execution inputs: the run ID, the expected
//     executable digest, and the slot. The worker verifies this binding; a marker
//     minted for a different run/exec cannot authorize this run.
//   * CONSUMPTION is atomic and one-way. `consume` renames the marker to a
//     `.consumed` sibling via rename(2). Exactly one caller can win: the loser
//     sees ENOENT and is refused. There is no read-then-delete window.
//   * REPLAY is refused. A consumed (or absent) marker cannot be re-consumed, so
//     an authorization is good for at most one worker, one time.
//   * On any failure the worker FAILS CLOSED: it never reaches the gated run and
//     therefore never calls a model or consumes a binding.

public enum G3D1Authorization {
    public static let markerEnvKey = "G3_AUTHORIZATION_MARKER"
    public static let runIDEnvKey = "G3D1_RUN_ID"
    /// Set by an external research harness (g3_execution_identity.py) that issues
    /// its OWN one-shot marker (O_CREAT|O_EXCL claim) before exec'ing the worker
    /// and passes the marker id, not a path. Their presence, together with the
    /// `G3_AUTHORIZATION_MARKER` id, is an externally-issued authorization.
    public static let manifestSourceEnvKey = "G3_MANIFEST_SOURCE_SHA256"
    public static let manifestRunnerEnvKey = "G3_MANIFEST_RUNNER_SHA256"

    /// The bound execution inputs written into the marker at issuance.
    public struct Binding: Codable, Equatable, Sendable {
        public let slotID: String
        public let runID: String
        public let expectedExecSHA256: String
        public init(slotID: String, runID: String, expectedExecSHA256: String) {
            self.slotID = slotID
            self.runID = runID
            self.expectedExecSHA256 = expectedExecSHA256
        }
    }

    public enum IssueError: Error, Equatable {
        case alreadyIssued(path: String)
        case ioFailure(String)
    }

    public enum ConsumeResult: Equatable, Sendable {
        /// The marker existed, matched the binding, and was atomically consumed.
        case accepted(binding: Binding)
        /// No live marker at the path (absent or already consumed) — replay refused.
        case missingOrReplayed(path: String)
        /// The marker existed but did not bind this run / executable.
        case bindingMismatch(reason: String)
        /// The marker could not be read or parsed.
        case malformed(String)
    }

    /// Atomically issue a one-shot marker at `path`. Refuses if a marker already
    /// exists (O_CREAT|O_EXCL), so two live authorizations cannot share a path.
    public static func issue(binding: Binding, to path: String) throws {
        let data = try JSONEncoder().encode(binding)
        let fd = path.withCString { open($0, O_WRONLY | O_CREAT | O_EXCL, 0o600) }
        if fd < 0 {
            if errno == EEXIST { throw IssueError.alreadyIssued(path: path) }
            throw IssueError.ioFailure("open failed errno=\(errno) path=\(path)")
        }
        defer { close(fd) }
        data.withUnsafeBytes { raw in
            _ = write(fd, raw.baseAddress, raw.count)
        }
    }

    /// The consumed sibling path for a marker. Renaming to it is the atomic,
    /// one-way consumption record; its existence proves the marker was used.
    public static func consumedPath(for path: String) -> String { path + ".consumed" }

    /// Atomically consume the marker at `path`, verifying it binds `expected`.
    /// One-shot: a second call finds no live marker and returns `.missingOrReplayed`.
    public static func consume(at path: String, expecting expected: Binding) -> ConsumeResult {
        guard let raw = FileManager.default.contents(atPath: path) else {
            return .missingOrReplayed(path: path)
        }
        let binding: Binding
        do {
            binding = try JSONDecoder().decode(Binding.self, from: raw)
        } catch {
            return .malformed("decode failed: \(error)")
        }
        // Execution-input binding check before any consumption side effect.
        if binding.slotID != expected.slotID {
            return .bindingMismatch(reason: "slot \(binding.slotID) != \(expected.slotID)")
        }
        if binding.runID != expected.runID {
            return .bindingMismatch(reason: "run \(binding.runID) != \(expected.runID)")
        }
        if binding.expectedExecSHA256 != expected.expectedExecSHA256 {
            return .bindingMismatch(reason: "exec digest does not match the armed binary")
        }
        // Atomic one-way consumption: rename to the .consumed sibling. Exactly one
        // racer wins; the loser gets ENOENT and cannot re-consume.
        let consumed = consumedPath(for: path)
        let ok = path.withCString { src in
            consumed.withCString { dst in rename(src, dst) == 0 }
        }
        if !ok {
            // Another worker consumed it between the read and the rename (or it
            // vanished). Refuse — never treat a lost race as acceptance.
            return .missingOrReplayed(path: path)
        }
        return .accepted(binding: binding)
    }

    /// Whether a marker for this slot has already been consumed (replay evidence).
    public static func isConsumed(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: consumedPath(for: path))
    }

    /// True when the environment carries an EXTERNAL one-shot authorization: a
    /// harness (not a path) marker id plus both frozen-manifest digests. The
    /// harness consumed its own O_EXCL claim before launching us, so this is a
    /// valid authorization the worker did not itself consume. It is reported with
    /// a distinct status so it is never confused with the worker's own file-path
    /// one-shot consumption.
    public static func isExternallyAuthorized(env: [String: String]) -> Bool {
        let id = (env[markerEnvKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let src = (env[manifestSourceEnvKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let runner = (env[manifestRunnerEnvKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !id.isEmpty && !src.isEmpty && !runner.isEmpty
    }

    /// Build the expected binding from a worker's environment. The run ID comes
    /// from G3D1_RUN_ID; the exec digest from the already-verified identity check.
    public static func expectedBindingFromEnv(runID: String, verifiedExecSHA256: String, slotID: String) -> Binding {
        Binding(slotID: slotID, runID: runID, expectedExecSHA256: verifiedExecSHA256)
    }
}
