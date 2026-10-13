import CryptoKit
import XCTest
import SimiGoRuntimeContract
@testable import SimiGo2Experimental

/// DCC-1 durable session baseline. Evidence classes are kept EXPLICITLY
/// separate: the spawn-self + SIGKILL tests are PROCESS-crash evidence; they
/// make no claim about power loss (no fsync-on-rename power-fail proof is
/// possible in tests) or storage media failure.
final class EngineSessionBaselineTests: XCTestCase {
    private var workRoot: URL!
    private var storeRoot: URL!
    private var modelRoot: URL!

    override func setUpWithError() throws {
        workRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dcc1-\(UUID().uuidString)", isDirectory: true)
        storeRoot = workRoot.appendingPathComponent("store", isDirectory: true)
        modelRoot = workRoot.appendingPathComponent("model", isDirectory: true)
        try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        DurableFileWriter.debugFailingDirectorySyncPhases = []
        try? FileManager.default.removeItem(at: workRoot)
    }

    private func makeModelIdentityFiles() throws {
        // A small tokenizer file so the identity digest is content-derived
        // and detectably different across model roots.
        try Data("tokenizer-v1".utf8).write(
            to: modelRoot.appendingPathComponent("tokenizer.json"))
    }

    private func makeStore() -> EngineSessionBaselineStore {
        EngineSessionBaselineStore(root: storeRoot)
    }

    private func makeRecord(uuid: UUID) -> EngineSessionBaselineRecord {
        let identity = EngineModelIdentity.compute(modelDirectory: modelRoot)
        return EngineSessionBaselineRecord(
            sessionUUID: uuid,
            executionID: "S",
            weightsIdentity: identity.weights,
            tokenizerIdentity: identity.tokenizer,
            position: 0,
            continuationNextInput: "",
            continuationID: "cont-0",
            prefixTokens: [1, 2, 3])
    }

    // MARK: - Model identity binds WEIGHT CONTENT, not path+size

    /// The acceptance-critical attack: same weight path, SAME file size,
    /// different content. The content-level digest must reject the old
    /// baseline at recovery.
    func testWeightContentSwapSameSizeRejectedAtRecovery() async throws {
        try makeModelIdentityFiles()
        try Data("AAAA".utf8).write(
            to: modelRoot.appendingPathComponent("model.safetensors"))
        let deadEngine = makeEngine(baselineRoot: storeRoot)
        deadEngine.debugReleaseAllOverride = {}
        _ = try await deadEngine.debugEnsureSession(prefix: [1, 2, 3])
        // Crash analog: abandon the engine WITHOUT a teardown — the pointer
        // stays live and names the baseline of the OLD weights.
        try Data("AAAB".utf8).write(  // same size, different content
            to: modelRoot.appendingPathComponent("model.safetensors"))
        let restarted = makeEngine(baselineRoot: storeRoot)
        let outcome = try await restarted.recoverDurableSession()
        guard case .coldStart(let reason) = outcome else {
            return XCTFail("swapped weights must cold-start, got \(outcome)")
        }
        XCTAssertTrue(reason.contains("identity"), reason)
    }

    // MARK: - Commit-outcome semantics at every injectable failure stage

    func testPayloadDirectorySyncFailureIsDeterministicallyUncommitted() throws {
        let record = makeRecord(uuid: UUID())
        DurableFileWriter.debugFailingDirectorySyncPhases = ["payload"]
        XCTAssertThrowsError(try makeStore().commitBaseline(record)) { error in
            XCTAssertTrue(
                String(describing: error).contains("payload"), "\(error)")
        }
        // Deterministic not-committed: the pointer was never written, so
        // recovery cannot reach the orphan payload files.
        guard case .absent = makeStore().loadCurrentValidated(
            expectedWeightsIdentity: record.weightsIdentity,
            expectedTokenizerIdentity: record.tokenizerIdentity)
        else {
            return XCTFail("expected absent")
        }
    }

    func testDigestDirectorySyncFailureIsDeterministicallyUncommitted() throws {
        let record = makeRecord(uuid: UUID())
        DurableFileWriter.debugFailingDirectorySyncPhases = ["digest"]
        XCTAssertThrowsError(try makeStore().commitBaseline(record)) { error in
            XCTAssertTrue(
                String(describing: error).contains("digest"), "\(error)")
        }
        guard case .absent = makeStore().loadCurrentValidated(
            expectedWeightsIdentity: record.weightsIdentity,
            expectedTokenizerIdentity: record.tokenizerIdentity)
        else {
            return XCTFail("expected absent")
        }
    }

    func testPointerDirectorySyncFailureIsStillCommitted() throws {
        // The rename already PUBLISHED the pointer: reporting not-committed
        // here would contradict what recovery honors. The sync failure is
        // accepted as a committed-with-caveat (power-loss dimension stays
        // NOT VERIFIED globally).
        let record = makeRecord(uuid: UUID())
        DurableFileWriter.debugFailingDirectorySyncPhases = ["pointer"]
        XCTAssertNoThrow(try makeStore().commitBaseline(record))
        guard case .valid(let loaded) = makeStore().loadCurrentValidated(
            expectedWeightsIdentity: record.weightsIdentity,
            expectedTokenizerIdentity: record.tokenizerIdentity)
        else {
            return XCTFail("the published pointer must validate")
        }
        XCTAssertEqual(loaded.sessionUUID, record.sessionUUID)
    }

    // MARK: - Store protocol

    func testCommitThenLoadRoundTrips() throws {
        let record = makeRecord(uuid: UUID())
        try makeStore().commitBaseline(record)
        guard case .valid(let loaded) = makeStore().loadCurrentValidated(
            expectedWeightsIdentity: record.weightsIdentity,
            expectedTokenizerIdentity: record.tokenizerIdentity)
        else {
            return XCTFail("expected a valid baseline")
        }
        XCTAssertEqual(loaded, record)
    }

    func testCorruptedPayloadDegradesToInvalid() throws {
        let record = makeRecord(uuid: UUID())
        try makeStore().commitBaseline(record)
        let payloadURL = storeRoot
            .appendingPathComponent("sessions/\(record.sessionUUID.uuidString)")
            .appendingPathComponent("baseline.json")
        var bytes = try Data(contentsOf: payloadURL)
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: payloadURL)
        guard case .invalid(let reason) = makeStore().loadCurrentValidated(
            expectedWeightsIdentity: record.weightsIdentity,
            expectedTokenizerIdentity: record.tokenizerIdentity)
        else {
            return XCTFail("expected invalid")
        }
        XCTAssertTrue(reason.contains("checksum"), reason)
    }

    func testUnknownFormatVersionDegradesToInvalid() throws {
        var record = makeRecord(uuid: UUID())
        record.formatVersion = 999
        try makeStore().commitBaseline(record)
        guard case .invalid(let reason) = makeStore().loadCurrentValidated(
            expectedWeightsIdentity: record.weightsIdentity,
            expectedTokenizerIdentity: record.tokenizerIdentity)
        else {
            return XCTFail("expected invalid")
        }
        XCTAssertTrue(reason.contains("format version"), reason)
    }

    func testGenerationMismatchDegradesToInvalid() throws {
        // A readable baseline whose generation does not match the pointer
        // must never validate (the stale-baseline confusion the contract
        // forbids).
        let record = makeRecord(uuid: UUID())
        let store = makeStore()
        try store.commitBaseline(record)
        let strayGeneration = UUID()
        let payload = try JSONEncoder().encode(record)
        let strayDirectory = storeRoot
            .appendingPathComponent("sessions/\(strayGeneration.uuidString)")
        try FileManager.default.createDirectory(at: strayDirectory, withIntermediateDirectories: true)
        try payload.write(to: strayDirectory.appendingPathComponent("baseline.json"))
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        try Data(digest.utf8).write(
            to: strayDirectory.appendingPathComponent("baseline.sha256"))
        let strayPointer = EngineSessionBaselineStore.Pointer(
            sessionUUID: strayGeneration, retired: false)
        try JSONEncoder().encode(strayPointer).write(
            to: storeRoot.appendingPathComponent("current.json"))
        guard case .invalid(let reason) = store.loadCurrentValidated(
            expectedWeightsIdentity: record.weightsIdentity,
            expectedTokenizerIdentity: record.tokenizerIdentity)
        else {
            return XCTFail("expected invalid")
        }
        XCTAssertTrue(reason.contains("generation"), reason)
    }

    func testIdentityMismatchDegradesToInvalid() throws {
        let record = makeRecord(uuid: UUID())
        try makeStore().commitBaseline(record)
        guard case .invalid(let reason) = makeStore().loadCurrentValidated(
            expectedWeightsIdentity: "different-weights",
            expectedTokenizerIdentity: record.tokenizerIdentity)
        else {
            return XCTFail("expected invalid")
        }
        XCTAssertTrue(reason.contains("identity"), reason)
    }

    func testTornPayloadDegradesToInvalid() throws {
        let record = makeRecord(uuid: UUID())
        try makeStore().commitBaseline(record)
        let payloadURL = storeRoot
            .appendingPathComponent("sessions/\(record.sessionUUID.uuidString)")
            .appendingPathComponent("baseline.json")
        let full = try Data(contentsOf: payloadURL)
        try full.prefix(upTo: full.count / 2).write(to: payloadURL)
        try? FileManager.default.removeItem(
            at: payloadURL.deletingLastPathComponent()
                .appendingPathComponent("baseline.sha256"))
        guard case .invalid = makeStore().loadCurrentValidated(
            expectedWeightsIdentity: record.weightsIdentity,
            expectedTokenizerIdentity: record.tokenizerIdentity)
        else {
            return XCTFail("expected invalid")
        }
    }

    func testAbsentAndRetiredPointersDegradeToAbsent() throws {
        guard case .absent = makeStore().loadCurrentValidated(
            expectedWeightsIdentity: "w", expectedTokenizerIdentity: "t")
        else {
            return XCTFail("expected absent")
        }
        try makeStore().retireCurrent()
        guard case .absent(let reason) = makeStore().loadCurrentValidated(
            expectedWeightsIdentity: "w", expectedTokenizerIdentity: "t")
        else {
            return XCTFail("expected absent")
        }
        XCTAssertTrue(reason.contains("retired"), reason)
    }

    func testUnwritableRootThrowsAndCommitsNothing() throws {
        let notADirectory = workRoot.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: notADirectory)
        let store = EngineSessionBaselineStore(
            root: notADirectory.appendingPathComponent("store"))
        XCTAssertThrowsError(try store.commitBaseline(makeRecord(uuid: UUID())))
        guard case .absent = store.loadCurrentValidated(
            expectedWeightsIdentity: "w", expectedTokenizerIdentity: "t")
        else {
            return XCTFail("expected absent")
        }
    }

    // MARK: - Engine integration

    /// Engine fixture path with a baseline directory. The fixture-style
    /// bootstrap (debugEnsureSession) exercises the engine's own private
    /// session path, so the baseline write happens inside the engine.
    private func makeEngine(baselineRoot: URL?) -> OversizedSegmentedEngine {
        OversizedSegmentedEngine(
            modelDirectory: modelRoot,
            sessionBaselineDirectory: baselineRoot)
    }

    func testBootstrapCommitsBaselineAndTeardownRetiresIt() async throws {
        try makeModelIdentityFiles()
        let engine = makeEngine(baselineRoot: storeRoot)
        engine.debugReleaseAllOverride = {}
        _ = try await engine.debugEnsureSession(prefix: [1, 2, 3])
        guard case .committed(let uuid) = engine.durableBaselineState else {
            return XCTFail("expected a committed baseline")
        }
        guard case .valid(let record) = makeStore().loadCurrentValidated(
            expectedWeightsIdentity: EngineModelIdentity.compute(modelDirectory: modelRoot).weights,
            expectedTokenizerIdentity: EngineModelIdentity.compute(modelDirectory: modelRoot).tokenizer)
        else {
            return XCTFail("expected a valid durable pointer")
        }
        XCTAssertEqual(record.sessionUUID, uuid)
        XCTAssertEqual(record.prefixTokens, [1, 2, 3])

        try await engine.newSession()
        XCTAssertEqual(engine.durableBaselineState, .absent)
        guard case .absent(let reason) = makeStore().loadCurrentValidated(
            expectedWeightsIdentity: EngineModelIdentity.compute(modelDirectory: modelRoot).weights,
            expectedTokenizerIdentity: EngineModelIdentity.compute(modelDirectory: modelRoot).tokenizer)
        else {
            return XCTFail("expected retired pointer")
        }
        XCTAssertTrue(reason.contains("retired"), reason)
    }

    func testRecoveryRebuildsSessionAtBaseline() async throws {
        try makeModelIdentityFiles()
        // Crash analog: the process dies WITHOUT an orderly teardown — the
        // engine instance is simply abandoned, so the durable pointer was
        // never retired. (After an orderly newSession() the pointer is
        // retired and recovery is unavailable BY DESIGN.)
        let deadEngine = makeEngine(baselineRoot: storeRoot)
        deadEngine.debugReleaseAllOverride = {}
        _ = try await deadEngine.debugEnsureSession(prefix: [1, 2, 3])

        // The restarted process: a fresh engine over the same store.
        let engine = makeEngine(baselineRoot: storeRoot)
        let outcome = try await engine.recoverDurableSession()
        guard case .recovered(let uuid, let position) = outcome else {
            return XCTFail("expected recovery, got \(outcome)")
        }
        XCTAssertEqual(position, ExecutionPosition(0))
        XCTAssertEqual(engine.durableBaselineState, .committed(sessionUUID: uuid))
        XCTAssertEqual(engine.sessionInfo?.position, 0)
        // The rebuilt session's ledger starts from the recovery bootstrap
        // entry: its successful append doubles as the I-L3 proof that the
        // physical binding was rebuilt from the baseline prefix (length 3).
        XCTAssertEqual(engine.tokenLedger?.count, 1)
        let entries = try XCTUnwrap(engine.tokenLedger?.entries(for: ExecutionID("S")))
        XCTAssertEqual(entries.map(\.kind), [.bootstrap])
        XCTAssertEqual(entries.map(\.prefixLength), [3])
    }

    func testBaselineReplacementCommitsNewGeneration() async throws {
        try makeModelIdentityFiles()
        // Generation 1 in a first process instance (abandoned without a
        // teardown: the crash analog keeps the pointer live).
        let firstEngine = makeEngine(baselineRoot: storeRoot)
        firstEngine.debugReleaseAllOverride = {}
        _ = try await firstEngine.debugEnsureSession(prefix: [1, 2, 3])
        guard case .committed(let first) = firstEngine.durableBaselineState else {
            return XCTFail("expected first generation")
        }
        // Generation 2 committed by a fresh process over the SAME store: the
        // replacement overwrites the pointer (the commit boundary).
        let secondEngine = makeEngine(baselineRoot: storeRoot)
        _ = try await secondEngine.debugEnsureSession(prefix: [4, 5, 6, 7])
        guard case .committed(let second) = secondEngine.durableBaselineState else {
            return XCTFail("expected second generation")
        }
        XCTAssertNotEqual(first, second)
        // A restarted process resolves to the CURRENT generation, never the
        // stale one. The rebuilt bootstrap ledger entry (prefixLength 4)
        // also proves the physical binding was rebuilt from the NEW
        // session's prefix.
        let restarted = makeEngine(baselineRoot: storeRoot)
        let outcome = try await restarted.recoverDurableSession()
        guard case .recovered(let uuid, let position) = outcome else {
            return XCTFail("expected recovery, got \(outcome)")
        }
        XCTAssertEqual(uuid, second)
        XCTAssertEqual(position, ExecutionPosition(0))
        let entries = try XCTUnwrap(restarted.tokenLedger?.entries(for: ExecutionID("S")))
        XCTAssertEqual(entries.map(\.prefixLength), [4])
    }

    func testBaselineCommitFailureNeverClaimsDurability() async throws {
        // The baseline root sits UNDER a regular file: every write fails.
        let blocker = workRoot.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        let engine = makeEngine(
            baselineRoot: blocker.appendingPathComponent("store"))
        let state = try await engine.debugEnsureSession(prefix: [1, 2, 3])
        XCTAssertEqual(engine.durableBaselineState, .absent)
        // The session itself is alive — only durability is absent. A second
        // bootstrap attempt is rejected by the one-session guard, which is
        // the public proof that a live session exists.
        do {
            _ = try await engine.debugEnsureSession(prefix: [1])
            XCTFail("a live session must block a second bootstrap")
        } catch {
            guard case OversizedEngineError.notLoaded = error else {
                return XCTFail("expected notLoaded, got \(error)")
            }
        }
        XCTAssertEqual(state.id, ExecutionID("S"))
    }

    func testRetirementFailureFailsClosedWithSessionIntact() async throws {
        try makeModelIdentityFiles()
        let engine = makeEngine(baselineRoot: storeRoot)
        engine.debugReleaseAllOverride = {}
        _ = try await engine.debugEnsureSession(prefix: [1, 2, 3])
        guard case .committed = engine.durableBaselineState else {
            return XCTFail("expected committed baseline")
        }
        // Make the store root read-only: retirement cannot commit.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: storeRoot.path)
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: storeRoot.path)
        }
        do {
            try await engine.newSession()
            XCTFail("newSession must fail when the baseline cannot be retired")
        } catch {
            XCTAssertTrue(
                String(describing: error).contains("baseline retirement"),
                "\(error)")
        }
        // Fail-closed: NOTHING was torn down — the live session is intact
        // (a second bootstrap is rejected by the one-session guard) and the
        // committed baseline still stands.
        do {
            _ = try await engine.debugEnsureSession(prefix: [1])
            XCTFail("a live session must block a second bootstrap")
        } catch {
            guard case OversizedEngineError.notLoaded = error else {
                return XCTFail("expected notLoaded, got \(error)")
            }
        }
        guard case .committed = engine.durableBaselineState else {
            return XCTFail("baseline must survive a failed teardown")
        }
    }

    func testIdentityMismatchRecoversAsColdStart() async throws {
        try makeModelIdentityFiles()
        let deadEngine = makeEngine(baselineRoot: storeRoot)
        deadEngine.debugReleaseAllOverride = {}
        _ = try await deadEngine.debugEnsureSession(prefix: [1, 2, 3])
        // A different model directory (different tokenizer content) must
        // never load the old baseline.
        let otherModelRoot = workRoot.appendingPathComponent("model-v2", isDirectory: true)
        try FileManager.default.createDirectory(at: otherModelRoot, withIntermediateDirectories: true)
        try Data("tokenizer-v2-different".utf8).write(
            to: otherModelRoot.appendingPathComponent("tokenizer.json"))
        let otherEngine = OversizedSegmentedEngine(
            modelDirectory: otherModelRoot,
            sessionBaselineDirectory: storeRoot)
        let outcome = try await otherEngine.recoverDurableSession()
        guard case .coldStart(let reason) = outcome else {
            return XCTFail("expected cold start, got \(outcome)")
        }
        XCTAssertTrue(reason.contains("identity"), reason)
    }

    func testRecoveryWithoutConfiguredBaselineIsColdStart() async throws {
        let engine = makeEngine(baselineRoot: nil)
        let outcome = try await engine.recoverDurableSession()
        XCTAssertEqual(outcome, .coldStart(reason: "baseline persistence not configured"))
    }

    // MARK: - Process-level crash evidence (SIGKILL; not power-loss proof)

    private var labRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Tests/SimiGo2ExperimentalTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // simigo2-experimental
            .deletingLastPathComponent()  // repo root
    }

    private var crashChild: URL {
        labRoot.appendingPathComponent("simigo2-experimental/.build/debug/EngineBaselineCrashChild")
    }

    private func runChild(stage: String, store: URL, model: URL, report: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = crashChild
        process.arguments = [
            "--stage", stage,
            "--store", store.path,
            "--model", model.path,
            "--report", report.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func runVerify(store: URL, model: URL) throws -> (outcome: String, uuid: String?, position: Int64?) {
        let verdictFile = workRoot.appendingPathComponent("verdict.json")
        try? FileManager.default.removeItem(at: verdictFile)
        let process = Process()
        process.executableURL = crashChild
        process.arguments = [
            "--stage", "verify",
            "--store", store.path,
            "--model", model.path,
            "--report", verdictFile.path,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let verdict = try XCTUnwrap(JSONDecoder().decode(Verdict.self, from: data))
        _ = verdictFile
        return (verdict.outcome, verdict.sessionUUID, verdict.position)
    }

    private struct Verdict: Codable {
        let outcome: String
        let sessionUUID: String?
        let reason: String?
        let position: Int64?
    }

    /// PROCESS CRASH: SIGKILL after the baseline commit. The restarted
    /// process must recover the session at the baseline.
    func testProcessKillAfterBaselineCommitRecoversSession() async throws {
        try makeModelIdentityFiles()
        let report = workRoot.appendingPathComponent("bootstrap-report.json")
        let status = try runChild(
            stage: "bootstrap", store: storeRoot, model: modelRoot, report: report)
        XCTAssertEqual(status, Int32(SIGKILL))
        let reportData = try Data(contentsOf: report)
        struct Report: Codable { let sessionUUID: String }
        let childUUID = try JSONDecoder().decode(Report.self, from: reportData).sessionUUID
        let verdict = try runVerify(store: storeRoot, model: modelRoot)
        XCTAssertEqual(verdict.outcome, "recovered")
        XCTAssertEqual(verdict.uuid, childUUID)
        XCTAssertEqual(verdict.position, 0)
    }

    /// PROCESS CRASH: SIGKILL after a durable teardown. Recovery must NOT
    /// resurrect the discarded session — the pointer was retired first.
    func testProcessKillAfterTeardownColdStarts() async throws {
        try makeModelIdentityFiles()
        let report = workRoot.appendingPathComponent("teardown-report.json")
        let status = try runChild(
            stage: "teardown", store: storeRoot, model: modelRoot, report: report)
        XCTAssertEqual(status, Int32(SIGKILL))
        let verdict = try runVerify(store: storeRoot, model: modelRoot)
        XCTAssertEqual(verdict.outcome, "coldStart")
    }

    /// PROCESS CRASH equivalent of a torn write: a truncated payload with a
    /// live pointer degrades to cold start (checksum gate).
    func testProcessTornBaselineColdStarts() async throws {
        try makeModelIdentityFiles()
        let status = try runChild(
            stage: "torn", store: storeRoot, model: modelRoot,
            report: workRoot.appendingPathComponent("torn-report.json"))
        XCTAssertEqual(status, 0)
        let verdict = try runVerify(store: storeRoot, model: modelRoot)
        XCTAssertEqual(verdict.outcome, "coldStart")
    }

    /// PROCESS CRASH: SIGKILL with the payload durable but the digest and
    /// pointer never written. Recovery must treat the incomplete baseline as
    /// NOTHING — verified against the real recovery result.
    func testProcessKillAfterPayloadSyncColdStarts() async throws {
        try makeModelIdentityFiles()
        let status = try runChild(
            stage: "crash-after-payload", store: storeRoot, model: modelRoot,
            report: workRoot.appendingPathComponent("mid-payload-report.json"))
        XCTAssertEqual(status, Int32(SIGKILL))
        let verdict = try runVerify(store: storeRoot, model: modelRoot)
        XCTAssertEqual(verdict.outcome, "coldStart")
        XCTAssertNil(verdict.uuid)
    }

    /// PROCESS CRASH: SIGKILL with payload+digest durable but the pointer
    /// never committed. The un-published baseline must not be recovered.
    func testProcessKillAfterDigestSyncColdStarts() async throws {
        try makeModelIdentityFiles()
        let status = try runChild(
            stage: "crash-after-digest", store: storeRoot, model: modelRoot,
            report: workRoot.appendingPathComponent("mid-digest-report.json"))
        XCTAssertEqual(status, Int32(SIGKILL))
        let verdict = try runVerify(store: storeRoot, model: modelRoot)
        XCTAssertEqual(verdict.outcome, "coldStart")
        XCTAssertNil(verdict.uuid)
    }
}
