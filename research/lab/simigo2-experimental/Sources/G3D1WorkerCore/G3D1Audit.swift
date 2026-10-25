import Foundation

// AUDIT RECORD — what a D1 worker writes so a supervisor (and a later reviewer)
// can see, per process, exactly which gates fired and which facts are NOT claimed.
//
// The record is deliberately structured so a Phase 1 run can never be misread as a
// bound delivery: `claimsSettledDelivery` is a hard false, and the execution axis
// reports the gate's actual refusal (zero generation calls, no settlement, binding
// not consumed). Those fields are the evidence that the constrained entry refused
// before a model call and before binding consumption — the thing Phase 1 must prove.

public struct G3D1AuditRecord: Codable {
    public static let schema = "simigo.g3.d1.worker-audit/v1"

    public struct Identity: Codable {
        public let status: String        // verified | missing_expectation | mismatch | unreadable
        public let verifiedExecSHA256: String?
        public let execPath: String?
        public let expectedEnvPresent: Bool
    }

    public struct Authorization: Codable {
        public let status: String        // accepted | missing_or_replayed | binding_mismatch | malformed | env_absent | not_reached
        public let markerPath: String?
        public let consumedPathExists: Bool
        public let detail: String?
    }

    public struct Execution: Codable {
        public let reached: Bool
        public let totalGenerationCallCount: Int
        public let eachArmSettled: Bool
        public let esGenerateBodyRuns: Int
        public let isGenerateBodyRuns: Int
        public let arms: [Arm]
    }

    public struct Arm: Codable {
        public let armID: String
        public let routedVia: String
        public let gateStage: String
        public let gatePassed: Bool
        public let generationCallCount: Int
        public let settleEntered: Bool
        public let bindingConsumed: Bool
        public let settled: Bool
        public let reason: String
    }

    public let schema: String
    public let pid: Int32
    public let slotID: String
    public let runID: String
    public let identity: Identity
    public let authorization: Authorization
    public let execution: Execution
    public let exitCode: Int32
    /// Always false. A Phase 1 worker records a gate refusal, never a settled or
    /// bound delivery; this field exists so a reader cannot accidentally infer one.
    public let claimsSettledDelivery: Bool

    public init(
        pid: Int32, slotID: String, runID: String, identity: Identity,
        authorization: Authorization, execution: Execution, exitCode: Int32
    ) {
        self.schema = G3D1AuditRecord.schema
        self.pid = pid
        self.slotID = slotID
        self.runID = runID
        self.identity = identity
        self.authorization = authorization
        self.execution = execution
        self.exitCode = exitCode
        self.claimsSettledDelivery = false
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    /// Write the record to `path` (creating parent directories), atomically.
    public func write(to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoded()
        let tmp = path + ".tmp.\(getpid())"
        try data.write(to: URL(fileURLWithPath: tmp), options: .atomic)
        try FileManager.default.moveItem(
            atPath: tmp, toPath: path)  // overwrite not allowed by move; caller uses fresh path
    }
}
