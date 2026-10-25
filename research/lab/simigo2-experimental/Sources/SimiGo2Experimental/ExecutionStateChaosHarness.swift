import Foundation
import SimiGoRuntimeContract

/// Process-level chaos acceptance harness for the durable Execution State
/// line: multi-process identity allocation, SIGKILL-during-growth with exact
/// committed-prefix verification, successive crash→restore generations, and
/// physical representation rehydration into a fresh backend. Spawned by
/// ExecutionStateChaosAcceptanceTests through the ExecutionStateChaosChild
/// executable; NOT a user-facing tool.
///
/// All stages are PROCESS-crash evidence (SIGKILL); none of them is
/// power-loss or storage-media durability evidence, and none of them
/// establishes a governance closure for G-5 / G-7 / G-8 / G-10.
public enum ExecutionStateChaosHarness {
    /// Deterministic growth script: the semantic root execution and the
    /// physical prefix bound at each position. Position p binds
    /// `Array(1...(p+3))`, so a verifier can recompute every expected prefix
    /// from the committed position alone.
    public static let rootExecutionRawID = "E0"
    public static let payloadCodecIdentity = "mlx-token-prefix-v1"

    public static func expectedPrefix(at position: Int64) -> [Int] {
        Array(1...(Int(position) + 3))
    }

    public static func expectedLifecycle(at position: Int64) -> ExecutionBranchLifecycle {
        position == 0 ? .attached : .active
    }

    static func makeStore(directory: URL) -> DurableExecutionStateStore {
        DurableExecutionStateStore(
            directory: directory,
            payloadCodec: MLXPrefixPayloadPersistence(
                backendIdentity: payloadCodecIdentity))
    }

    static func killSelf() -> Never {
        kill(getpid(), SIGKILL)
        exit(9)
    }

    // MARK: - Reports

    public struct AllocateReport: Codable {
        public let stage: String
        public let conflict: Bool
        public let allocatedIDs: [String]
        public let count: Int
    }

    public struct GrowReport: Codable {
        public let stage: String
        public let startPosition: Int64
        public let completedOps: Int
    }

    public struct VerifyStateReport: Codable {
        public let status: String
        public let records: Int
        public let position: Int64
        public let representations: Int
        public let failures: [String]
    }

    public struct VerifyIdentityReport: Codable {
        public let status: String
        public let reservations: Int
        public let ledgerLines: Int
        public let failures: [String]
    }

    /// Ready/go barrier: the child announces its allocator (or store) view is
    /// open by writing `ready`, then parks until `go` exists. This forces the
    /// stale-view interleaving that a same-host multi-process race otherwise
    /// only exhibits under scheduling luck.
    public struct Barrier {
        public let ready: URL
        public let go: URL

        public init(ready: URL, go: URL) {
            self.ready = ready
            self.go = go
        }
    }

    static func writeReport(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
    }

    static func encodeReport<T: Encodable>(_ report: T, to url: URL) {
        writeReport(try! JSONEncoder().encode(report), to: url)
    }

    // MARK: - Stages

    /// Reserve identities against one durable ledger. With `requestedID`,
    /// reserve exactly that ID (exit 3 + conflict report when another
    /// process already committed it); otherwise reserve `count` generated
    /// IDs under `namespace`-scoped tokens. Exit 0 on success.
    public static func allocateIdentities(
        root: URL,
        namespace: String,
        count: Int,
        requestedID: String?,
        barrier: Barrier?,
        reportURL: URL
    ) async -> Never {
        let allocator: DurableExecutionIdentityAllocator
        do {
            allocator = try DurableExecutionIdentityAllocator(directory: root)
        } catch {
            fputs("harness allocator open failed: \(error)\n", stderr)
            exit(3)
        }
        if let barrier {
            writeReport(Data("ready".utf8), to: barrier.ready)
            let deadline = Date().addingTimeInterval(30)
            while !FileManager.default.fileExists(atPath: barrier.go.path) {
                guard Date() < deadline else {
                    fputs("harness barrier timeout\n", stderr)
                    exit(5)
                }
                usleep(5_000)
            }
        }

        func finish(_ report: AllocateReport, exitCode: Int32) -> Never {
            encodeReport(report, to: reportURL)
            exit(exitCode)
        }

        if let requestedID {
            do {
                let id = try allocator.reserve(
                    token: "\(namespace):requested",
                    requestedID: ExecutionID(requestedID))
                finish(
                    AllocateReport(
                        stage: "allocate", conflict: false,
                        allocatedIDs: [id.rawValue], count: 1),
                    exitCode: 0)
            } catch let error as ExecutionIdentityAllocatorError {
                guard case .executionIDReserved = error else {
                    fputs("harness allocate failed: \(error)\n", stderr)
                    exit(3)
                }
                finish(
                    AllocateReport(
                        stage: "allocate", conflict: true, allocatedIDs: [], count: 0),
                    exitCode: 3)
            } catch {
                fputs("harness allocate failed: \(error)\n", stderr)
                exit(3)
            }
        }

        var ids: [String] = []
        do {
            for index in 0..<count {
                let id = try allocator.reserve(
                    token: "\(namespace):\(index)", requestedID: nil)
                ids.append(id.rawValue)
            }
        } catch {
            fputs("harness allocate failed: \(error)\n", stderr)
            exit(3)
        }
        finish(
            AllocateReport(
                stage: "allocate", conflict: false, allocatedIDs: ids, count: ids.count),
            exitCode: 0)
    }

    /// Grow semantic state through the coordinator: bootstrap the root
    /// execution on a fresh store (create + bind position 0) or restore the
    /// persisted root, then perform `ops` continue+bind transitions. With
    /// `crash`, SIGKILL self after `killAfter` completed transitions
    /// (`killAfter` 0 crashes right after bootstrap; `killAfter == ops`
    /// crashes after the final transition) — the kill lands only between
    /// fully committed transitions, so the persisted state must equal the
    /// exact committed prefix.
    public static func growSemanticState(
        stateRoot: URL,
        ops: Int,
        killAfter: Int,
        crash: Bool,
        reportURL: URL
    ) async -> Never {
        precondition(killAfter >= 0 && killAfter <= ops, "killAfter out of range")
        let rootID = ExecutionID(rootExecutionRawID)
        let coordinator: ExecutionContinuityCoordinator
        var handle: ExecutionStateHandle
        do {
            coordinator = try ExecutionContinuityCoordinator(
                backend: MLXExecutionStateBackend(),
                identityAllocator: nil,
                stateStore: makeStore(directory: stateRoot))
            if let existing = coordinator.handle(rootID) {
                handle = existing
            } else {
                handle = try await coordinator.create(
                    id: rootID,
                    position: ExecutionPosition(0),
                    continuation: ExecutionContinuation(
                        nextInput: "next-0", continuationID: "cont-0"))
                try await coordinator.bindRepresentation(
                    executionID: rootID,
                    position: ExecutionPosition(0),
                    payload: MLXPrefixPayload(tokenPrefix: expectedPrefix(at: 0)))
            }
        } catch {
            fputs("harness growth bootstrap failed: \(error)\n", stderr)
            exit(3)
        }

        func finish(startPosition: Int64, completedOps: Int, exitCode: Int32) -> Never {
            encodeReport(
                GrowReport(
                    stage: "grow", startPosition: startPosition,
                    completedOps: completedOps),
                to: reportURL)
            if exitCode == Int32(SIGKILL) {
                killSelf()
            }
            exit(exitCode)
        }

        let startPosition = handle.position.value
        if crash && killAfter == 0 {
            finish(startPosition: startPosition, completedOps: 0, exitCode: Int32(SIGKILL))
        }
        if ops > 0 {
            do {
                for offset in 1...ops {
                    let position = startPosition + Int64(offset)
                    handle = try await coordinator.continueExecution(
                        handle,
                        continuation: ExecutionContinuation(
                            nextInput: "next-\(position)",
                            continuationID: "cont-\(position)"))
                    try await coordinator.bindRepresentation(
                        executionID: rootID,
                        position: ExecutionPosition(position),
                        payload: MLXPrefixPayload(tokenPrefix: expectedPrefix(at: position)))
                    if crash && offset == killAfter {
                        finish(
                            startPosition: startPosition, completedOps: offset,
                            exitCode: Int32(SIGKILL))
                    }
                }
            } catch {
                fputs("harness growth failed: \(error)\n", stderr)
                exit(3)
            }
        }
        finish(startPosition: startPosition, completedOps: ops, exitCode: 0)
    }

    /// Independent verifier: reload the durable store in THIS process,
    /// rehydrate every persisted representation into a fresh backend, and
    /// check the full deterministic script — lifecycle sequence contiguity,
    /// handle position, one representation per position with the expected
    /// token prefix, and physical rehydration verified through the backend's
    /// position-checked binding. Exits 0 on pass, 4 on any failure, 3 on a
    /// store/coordinator open error (fail-closed corruption lands here).
    public static func verifySemanticState(
        stateRoot: URL,
        expectRecords: Int,
        expectPosition: Int64,
        reportURL: URL
    ) async -> Never {
        var failures: [String] = []
        var records = 0
        var representations = 0

        func fail(_ message: String) {
            if failures.count < 10 {
                failures.append(message)
            }
        }

        let rootID = ExecutionID(rootExecutionRawID)
        do {
            let store = makeStore(directory: stateRoot)
            let loaded = try store.load()
            records = loaded.lifecycleRecords.count
            representations = loaded.representations.count

            if records != expectRecords {
                fail("records \(records) != expected \(expectRecords)")
            }
            for (index, record) in loaded.lifecycleRecords.enumerated()
            where record.sequence != index + 1 {
                fail("lifecycle sequence \(record.sequence) at index \(index)")
                break
            }

            var byID: [ExecutionID: ExecutionStateHandle] = [:]
            for handle in loaded.handles {
                if byID[handle.id] != nil {
                    fail("duplicate handle \(handle.id.rawValue)")
                }
                byID[handle.id] = handle
            }
            guard let root = byID[rootID] else {
                fail("missing root execution \(rootExecutionRawID)")
                encodeReport(
                    VerifyStateReport(
                        status: "fail", records: records, position: -1,
                        representations: representations, failures: failures),
                    to: reportURL)
                exit(4)
            }
            if root.position.value != expectPosition {
                fail("position \(root.position.value) != expected \(expectPosition)")
            }
            if root.lifecycle != expectedLifecycle(at: expectPosition) {
                fail("lifecycle \(root.lifecycle.rawValue) at position \(expectPosition)")
            }

            var representationsByPosition: [Int64: ExecutionRepresentation] = [:]
            for representation in loaded.representations {
                guard representation.executionID == rootID else {
                    fail("representation for unknown execution \(representation.executionID.rawValue)")
                    continue
                }
                if representationsByPosition[representation.position.value] != nil {
                    fail("duplicate representation at position \(representation.position.value)")
                }
                representationsByPosition[representation.position.value] = representation
            }
            let expectedPositions = Array(Int64(0)...expectPosition)
            if representationsByPosition.count != expectedPositions.count {
                fail("representations \(representationsByPosition.count) != expected \(expectedPositions.count)")
            }
            for position in expectedPositions {
                guard let representation = representationsByPosition[position] else {
                    fail("missing representation at position \(position)")
                    continue
                }
                guard let payload = representation.payload as? MLXPrefixPayload else {
                    fail("foreign payload at position \(position)")
                    continue
                }
                if payload.tokenPrefix != expectedPrefix(at: position) {
                    fail("prefix mismatch at position \(position)")
                }
            }

            // Physical rehydration into a fresh backend: each persisted
            // representation must rebind and verify at its own position.
            let freshBackend = MLXExecutionStateBackend()
            for position in expectedPositions {
                guard let representation = representationsByPosition[position] else { continue }
                try await freshBackend.restoreRepresentation(representation)
                let probe = ExecutionStateHandle(
                    id: rootID,
                    lineage: ExecutionLineage(root: rootID, parent: nil),
                    position: ExecutionPosition(position),
                    continuation: ExecutionContinuation(nextInput: "", continuationID: ""),
                    lifecycle: .active)
                let (prefix, bound) = try freshBackend.boundPrefix(for: probe)
                if bound.value != position {
                    fail("rehydrated binding at \(bound.value), expected \(position)")
                }
                if prefix != expectedPrefix(at: position) {
                    fail("rehydrated prefix mismatch at position \(position)")
                }
            }

            // Coordinator composition over the same store must reconstruct
            // the same semantic view.
            let coordinator = try ExecutionContinuityCoordinator(
                backend: MLXExecutionStateBackend(),
                identityAllocator: nil,
                stateStore: store)
            if coordinator.recordCount != expectRecords {
                fail("coordinator records \(coordinator.recordCount) != expected \(expectRecords)")
            }
            if let handle = coordinator.handle(rootID) {
                if handle.position.value != expectPosition {
                    fail("coordinator position \(handle.position.value) != expected \(expectPosition)")
                }
            } else {
                fail("coordinator missing root execution")
            }
        } catch {
            fail("store or coordinator open failed: \(String(describing: error))")
        }

        let status = failures.isEmpty ? "pass" : "fail"
        encodeReport(
            VerifyStateReport(
                status: status, records: records, position: expectPosition,
                representations: representations, failures: failures),
            to: reportURL)
        exit(failures.isEmpty ? 0 : 4)
    }

    private static func verifyStateReport(
        failures: [String], records: Int, position: Int64, representations: Int
    ) -> VerifyStateReport {
        VerifyStateReport(
            status: "fail", records: records, position: position,
            representations: representations, failures: failures)
    }

    /// Independent verifier for the identity ledger: a clean reopen proves
    /// the ledger replays without corruption; the reservation count and the
    /// raw line count must agree with the expectation.
    public static func verifyIdentityLedger(
        root: URL,
        expectedReservations: Int,
        reportURL: URL
    ) async -> Never {
        var failures: [String] = []
        var reservations = 0
        var ledgerLines = 0

        func fail(_ message: String) {
            if failures.count < 10 {
                failures.append(message)
            }
        }

        do {
            let allocator = try DurableExecutionIdentityAllocator(directory: root)
            reservations = allocator.reservationCount
            let ledgerURL = root.appendingPathComponent("execution-ids.jsonl")
            if let text = try? String(contentsOf: ledgerURL, encoding: .utf8) {
                ledgerLines = text
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .count
            }
            if reservations != expectedReservations {
                fail("reservations \(reservations) != expected \(expectedReservations)")
            }
            if ledgerLines != reservations {
                fail("ledger lines \(ledgerLines) != reservations \(reservations)")
            }
        } catch {
            fail("allocator open failed: \(String(describing: error))")
        }

        let status = failures.isEmpty ? "pass" : "fail"
        encodeReport(
            VerifyIdentityReport(
                status: status, reservations: reservations,
                ledgerLines: ledgerLines, failures: failures),
            to: reportURL)
        exit(failures.isEmpty ? 0 : 4)
    }
}
