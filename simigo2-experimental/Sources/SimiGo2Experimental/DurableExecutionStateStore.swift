import Foundation
import SimiGoRuntimeContract

public struct PersistedRepresentationPayload: Codable, Sendable, Equatable {
    public let backendIdentity: String
    public let data: Data

    public init(backendIdentity: String, data: Data) {
        self.backendIdentity = backendIdentity
        self.data = data
    }
}

public protocol ExecutionRepresentationPayloadPersisting: Sendable {
    var backendIdentity: String { get }
    func encode(_ payload: any ExecutionRepresentationPayload) throws -> Data
    func decode(_ data: Data) throws -> any ExecutionRepresentationPayload
}

/// P-layer durable composition for semantic handles, lifecycle audit, and
/// backend-supplied persisted representation descriptors. The store never
/// interprets an opaque payload; a host injects a codec for the backend it owns.
///
/// ponytail: one atomic JSON snapshot; move to incremental journaling if
/// lifecycle volume or multi-process writers make rewrite cost real.
public final class DurableExecutionStateStore: @unchecked Sendable {
    enum StoreError: Error, Equatable {
        case unsupportedVersion(Int)
        case malformedState(String)
    }

    struct LifecycleState: Codable, Equatable {
        let sequence: Int
        let operation: String
        let executionID: String
        let relatedID: String?
        let resultLifecycle: String
        let resultPosition: Int64
        let resultContinuationNextInput: String
        let resultContinuationID: String
    }

    struct RepresentationState: Codable, Equatable {
        let executionID: String
        let position: Int64
        let payload: PersistedRepresentationPayload
    }

    struct Snapshot: Codable, Equatable {
        let version: Int
        let handles: [HandleState]
        let lifecycle: [LifecycleState]
        let representations: [RepresentationState]?
    }

    struct HandleState: Codable, Equatable {
        let executionID: String
        let rootExecutionID: String
        let parentExecutionID: String?
        let position: Int64
        let continuationNextInput: String
        let continuationID: String
        let lifecycle: String
    }

    public struct LoadedState {
        public let handles: [ExecutionStateHandle]
        public let lifecycleRecords: [ExecutionContinuityCoordinator.LifecycleRecord]
        public let representations: [ExecutionRepresentation]
    }

    public static let currentVersion = 1
    public let fileURL: URL
    private let payloadCodec: (any ExecutionRepresentationPayloadPersisting)?
    private let lock = NSLock()

    public init(
        directory: URL,
        payloadCodec: (any ExecutionRepresentationPayloadPersisting)? = nil
    ) {
        self.fileURL = directory.appendingPathComponent("execution-state.json")
        self.payloadCodec = payloadCodec
    }

    public func load() throws -> LoadedState {
        lock.lock()
        defer { lock.unlock() }
        return try loadUnlocked()
    }

    private func loadUnlocked() throws -> LoadedState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LoadedState(handles: [], lifecycleRecords: [], representations: [])
        }
        let data = try Data(contentsOf: fileURL)
        let snapshot: Snapshot
        do {
            snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
        } catch {
            throw StoreError.malformedState(String(describing: error))
        }
        guard snapshot.version == Self.currentVersion else {
            throw StoreError.unsupportedVersion(snapshot.version)
        }

        var handles: [ExecutionID: ExecutionStateHandle] = [:]
        let decodedHandles = try snapshot.handles.map { state throws -> ExecutionStateHandle in
            let id = ExecutionID(state.executionID)
            guard handles[id] == nil else {
                throw StoreError.malformedState("duplicate execution id \(state.executionID)")
            }
            let handle = ExecutionStateHandle(
                id: id,
                lineage: ExecutionLineage(
                    root: ExecutionID(state.rootExecutionID),
                    parent: state.parentExecutionID.map(ExecutionID.init)),
                position: ExecutionPosition(state.position),
                continuation: ExecutionContinuation(
                    nextInput: state.continuationNextInput,
                    continuationID: state.continuationID),
                lifecycle: try decodeLifecycle(state.lifecycle))
            handles[id] = handle
            return handle
        }

        var sequence = 0
        let records = try snapshot.lifecycle.map { state throws -> ExecutionContinuityCoordinator.LifecycleRecord in
            sequence += 1
            guard state.sequence == sequence else {
                throw StoreError.malformedState("lifecycle sequence expected \(sequence), got \(state.sequence)")
            }
            guard let operation = ExecutionContinuityCoordinator.LifecycleRecord.Operation(
                rawValue: state.operation) else {
                throw StoreError.malformedState("unknown lifecycle operation \(state.operation)")
            }
            guard let resultLifecycle = ExecutionBranchLifecycle(
                rawValue: state.resultLifecycle) else {
                throw StoreError.malformedState(
                    "unknown lifecycle result \(state.resultLifecycle)")
            }
            return ExecutionContinuityCoordinator.LifecycleRecord(
                sequence: state.sequence,
                operation: operation,
                executionID: ExecutionID(state.executionID),
                relatedID: state.relatedID.map(ExecutionID.init),
                resultLifecycle: resultLifecycle,
                resultPosition: ExecutionPosition(state.resultPosition),
                resultContinuation: ExecutionContinuation(
                    nextInput: state.resultContinuationNextInput,
                    continuationID: state.resultContinuationID))
        }

        let representations = try (snapshot.representations ?? []).map { state throws -> ExecutionRepresentation in
            guard let codec = payloadCodec else {
                throw StoreError.malformedState("representation payload present without codec")
            }
            guard state.payload.backendIdentity == codec.backendIdentity else {
                throw StoreError.malformedState(
                    "representation payload backend mismatch \(state.payload.backendIdentity)")
            }
            let payload = try codec.decode(state.payload.data)
            return ExecutionRepresentation(
                executionID: ExecutionID(state.executionID),
                position: ExecutionPosition(state.position),
                payload: payload)
        }

        return LoadedState(
            handles: decodedHandles,
            lifecycleRecords: records,
            representations: representations)
    }

    public func replace(
        handles: [ExecutionStateHandle],
        lifecycleRecords: [ExecutionContinuityCoordinator.LifecycleRecord],
        representations: [ExecutionRepresentation] = []
    ) throws {
        guard representations.isEmpty || payloadCodec != nil else {
            throw StoreError.malformedState("representation codec required")
        }
        let encodedRepresentations = try representations.map { representation throws -> RepresentationState in
            guard let codec = payloadCodec else {
                throw StoreError.malformedState("representation codec required")
            }
            return RepresentationState(
                executionID: representation.executionID.rawValue,
                position: representation.position.value,
                payload: PersistedRepresentationPayload(
                    backendIdentity: codec.backendIdentity,
                    data: try codec.encode(representation.payload)))
        }
        let snapshot = Snapshot(
            version: Self.currentVersion,
            handles: handles.map { handle in
                HandleState(
                    executionID: handle.id.rawValue,
                    rootExecutionID: handle.lineage.root.rawValue,
                    parentExecutionID: handle.lineage.parent?.rawValue,
                    position: handle.position.value,
                    continuationNextInput: handle.continuation.nextInput,
                    continuationID: handle.continuation.continuationID,
                    lifecycle: handle.lifecycle.rawValue)
            },
            lifecycle: lifecycleRecords.map { record in
                LifecycleState(
                    sequence: record.sequence,
                    operation: record.operation.rawValue,
                    executionID: record.executionID.rawValue,
                    relatedID: record.relatedID?.rawValue,
                    resultLifecycle: record.resultLifecycle.rawValue,
                    resultPosition: record.resultPosition.value,
                    resultContinuationNextInput: record.resultContinuation.nextInput,
                    resultContinuationID: record.resultContinuation.continuationID)
            },
            representations: encodedRepresentations)
        let data = try JSONEncoder.outputFormatting(.sortedKeys).encode(snapshot)
        lock.lock()
        defer { lock.unlock() }
        try DurableFileWriter.writeDurable(data, to: fileURL, phase: .payload)
    }

    /// Prepare an empty semantic snapshot for a new DCC-1 baseline session.
    /// Existing snapshots are validated and archived so stale handles can never
    /// leak into the recovered coordinator; malformed snapshots fail closed.
    func prepareForFreshBaseline() throws {
        lock.lock()
        defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        _ = try loadUnlocked()
        let archiveDirectory = fileURL.deletingLastPathComponent()
            .appendingPathComponent("archive", isDirectory: true)
        try FileManager.default.createDirectory(
            at: archiveDirectory, withIntermediateDirectories: true)
        let destination = archiveDirectory.appendingPathComponent(
            "execution-state-\(UUID().uuidString).json")
        try FileManager.default.moveItem(at: fileURL, to: destination)
    }

    private func decodeLifecycle(_ value: String) throws -> ExecutionBranchLifecycle {
        guard let lifecycle = ExecutionBranchLifecycle(rawValue: value) else {
            throw StoreError.malformedState("unknown handle lifecycle \(value)")
        }
        return lifecycle
    }
}

private extension JSONEncoder {
    static func outputFormatting(_ formatting: JSONEncoder.OutputFormatting) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = formatting
        return encoder
    }
}
