import Foundation
import CryptoKit
import Darwin
import SimiGoRuntimeContract

/// DCC-1 — durable session baseline for the oversized engine (design:
/// docs/02-evidence/restore-atomicity-dcc-20261013). Tier 1 ONLY: a single
/// durable baseline per engine session. Restores and turns stay in-memory;
/// after any crash the recovery decision is always "resume at the baseline"
/// or "cold start" — never a partially durable transaction.

/// Whether the live engine session has a committed durable baseline. `.absent`
/// means the session has NO durable recovery capability — either baseline
/// persistence is not configured or its commit failed; the session must never
/// be reported as durably recoverable in that state.
public enum EngineDurableBaselineState: Equatable, Sendable {
    case absent
    case committed(sessionUUID: UUID)
}

/// Outcome of the explicit DCC-1 recovery entry point. Recovery always lands
/// AT THE BASELINE (the most recent durable starting point) — never at the
/// pre-crash live position; every validation failure degrades to a defined
/// cold start.
public enum EngineSessionRecoveryOutcome: Equatable, Sendable {
    case recovered(sessionUUID: UUID, position: ExecutionPosition)
    case coldStart(reason: String)
}

/// Deterministic per-model location for DCC-1 baseline and G-7 identity state.
public struct OversizedEnginePersistenceDirectories: Equatable, Sendable {
    public let sessionBaseline: URL
    public let identity: URL
}

public enum OversizedEnginePersistence {
    public static func defaultBaseDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true)
        return applicationSupport.appendingPathComponent("SimiGo-Lab", isDirectory: true)
    }

    /// Key by standardized model path; identity/baseline validation still binds
    /// records to model content, so a path collision can only cause a cold start.
    public static func directories(
        modelDirectory: URL,
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> OversizedEnginePersistenceDirectories {
        let root = try baseDirectory ?? defaultBaseDirectory(fileManager: fileManager)
        let key = SHA256.hash(data: Data(
            modelDirectory.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let modelRoot = root
            .appendingPathComponent("engines", isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
        return OversizedEnginePersistenceDirectories(
            sessionBaseline: modelRoot.appendingPathComponent("baseline", isDirectory: true),
            identity: modelRoot.appendingPathComponent("identity", isDirectory: true))
    }
}

/// Canonical, self-describing bootstrap state. Everything needed to
/// deterministically rebuild the engine session's initial (position-0-style)
/// state: identity bindings, the generation UUID, and the canonical token
/// prefix. The fixed execution ID "S" is recorded but NEVER used as the
/// generation identifier — `sessionUUID` is.
public struct EngineSessionBaselineRecord: Codable, Equatable, Sendable {
    /// Bumped on incompatible payload changes. Records with an unknown
    /// version are treated as invalid (cold start), never best-effort parsed.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var sessionUUID: UUID
    public var executionID: String
    /// Content digest over the model directory's weight files (streaming
    /// full-file SHA-256 per .safetensors — binds CONTENT, not just
    /// path+size).
    public var weightsIdentity: String
    /// Content digest over the model directory's tokenizer/config files.
    public var tokenizerIdentity: String
    public var position: Int64
    public var continuationNextInput: String
    public var continuationID: String
    public var prefixTokens: [Int]

    public init(
        sessionUUID: UUID,
        executionID: String,
        weightsIdentity: String,
        tokenizerIdentity: String,
        position: Int64,
        continuationNextInput: String,
        continuationID: String,
        prefixTokens: [Int]
    ) {
        self.formatVersion = Self.currentFormatVersion
        self.sessionUUID = sessionUUID
        self.executionID = executionID
        self.weightsIdentity = weightsIdentity
        self.tokenizerIdentity = tokenizerIdentity
        self.position = position
        self.continuationNextInput = continuationNextInput
        self.continuationID = continuationID
        self.prefixTokens = prefixTokens
    }
}

/// Outcome of reading and validating the durable pointer + baseline.
public enum EngineSessionBaselineReadOutcome: Equatable, Sendable {
    /// No pointer, tombstoned pointer, or unreadable pointer: nothing to
    /// recover — the caller cold-starts.
    case absent(reason: String)
    /// A baseline exists but fails validation (checksum, version, identity,
    /// generation mismatch): the caller cold-starts; the stale data is never
    /// loaded.
    case invalid(reason: String)
    case valid(record: EngineSessionBaselineRecord)
}

/// Durability note (honest boundary, carried into every test report): the
/// writer performs tmp-file write → F_FULLFSYNC on the file → rename →
/// F_FULLFSYNC on the parent directory. That is process-crash-safe and
/// best-effort for power loss on Apple platforms (F_FULLFSYNC is the strong
/// form of fsync there); it is NOT a guarantee against storage media
/// failure. Records carry checksums, and EVERY unreadable or mismatching
/// record degrades to a defined cold start — durability failure is never on
/// the session-continuation path.
enum DurableFileWriter {
    enum Phase: String {
        case payload, digest, pointer
    }

#if DEBUG
    /// DEBUG-only injection: the listed phases fail their directory sync
    /// AFTER the rename has landed, so tests can exercise every reachable
    /// failure stage of the commit sequence deterministically.
    nonisolated(unsafe) static var debugFailingDirectorySyncPhases: Set<String> = []
#endif

    /// Write `data` durably to `finalURL`.
    ///
    /// Failure semantics per reachable stage (the caller's commit outcome
    /// MUST mirror these):
    /// - tmp create / file sync / rename failures: the destination was
    ///   never replaced → deterministic NOT-COMMITTED.
    /// - directory sync failure AFTER the rename landed: the new content IS
    ///   visible to every reader from that point. For payload/digest this
    ///   still throws — the commit sequence aborts before the pointer, so
    ///   recovery can never reach the orphan files (deterministic
    ///   not-committed). For the POINTER phase the rename already published
    ///   the commit: throwing would claim "not committed" while recovery
    ///   honors the pointer, so the sync is re-attempted once and then
    ///   accepted (power-loss durability remains the globally documented
    ///   NOT VERIFIED dimension — identical for a clean sync).
    static func writeDurable(_ data: Data, to finalURL: URL, phase: Phase) throws {
        let directory = finalURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let tmpURL = directory.appendingPathComponent(
            ".tmp-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: tmpURL.path, contents: data) else {
            throw OversizedEngineError.residencyDivergence(
                "durable writer: cannot create temp file \(tmpURL.path)")
        }
        do {
            let handle = try FileHandle(forReadingFrom: tmpURL)
            // F_FULLFSYNC is the strong sync on Darwin; plain fsync is the
            // fallback. A failed sync throws — "called fsync" without
            // success is not treated as durability.
            let fd = handle.fileDescriptor
            if fcntl(fd, F_FULLFSYNC) != 0 {
                if fsync(fd) != 0 {
                    let reason = String(cString: strerror(errno))
                    try? handle.close()
                    throw OversizedEngineError.residencyDivergence(
                        "durable writer: file sync failed (\(reason))")
                }
            }
            try handle.close()
            guard rename(tmpURL.path, finalURL.path) == 0 else {
                let reason = String(cString: strerror(errno))
                throw OversizedEngineError.residencyDivergence(
                    "durable writer: atomic replace failed (\(reason))")
            }
            var directorySyncSucceeded = syncDirectoryOnce(directory.path)
            if !directorySyncSucceeded {
                directorySyncSucceeded = syncDirectoryOnce(directory.path)
            }
#if DEBUG
            let injectedFailure =
                debugFailingDirectorySyncPhases.contains(phase.rawValue)
#else
            let injectedFailure = false
#endif
            if !directorySyncSucceeded {
                if phase == .pointer {
                    // Committed-with-caveat: never lie about the commit.
                    // (One re-attempt already happened above.)
                } else {
                    throw OversizedEngineError.residencyDivergence(
                        "durable writer: directory sync failed (\(phase.rawValue))")
                }
            } else if injectedFailure {
                // The injected failure only models a sync that DID NOT
                // succeed; honoring the real kernel result keeps the test
                // honest: for payload/digest the injected failure throws
                // (pre-commit), for pointer it cannot un-publish the rename.
                if phase != .pointer {
                    throw OversizedEngineError.residencyDivergence(
                        "durable writer: directory sync failed (injected @\(phase.rawValue))")
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: tmpURL)
            throw error
        }
    }

    private static func syncDirectoryOnce(_ path: String) -> Bool {
        let dirFD = open(path, O_RDONLY)
        guard dirFD >= 0 else { return false }
        defer { close(dirFD) }
        if fcntl(dirFD, F_FULLFSYNC) == 0 { return true }
        return fsync(dirFD) == 0
    }
}

/// Identity digests over the model directory. Deterministic across restarts
/// and independent of load state. The model loader
/// (PerTensorSafetensorsReader) exposes NO immutable version identity, so
/// weights bind at CONTENT level: a streaming full-file SHA-256 per
/// .safetensors (path+size+content digest in the manifest). Cost is
/// O(model bytes) per baseline commit and per recovery validation — the
/// honest default; a verified immutable loader identity could replace this
/// but does not exist today. Tokenizer = content digest of small
/// tokenizer/config files. A missing directory yields the empty-directory
/// digest (tests and model-less harness runs).
enum EngineModelIdentity {
    static func compute(modelDirectory: URL) -> (weights: String, tokenizer: String) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: modelDirectory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        else {
            return (digest(of: []), digest(of: []))
        }
        var weightLines: [String] = []
        var tokenizerData = Data()
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let size = values?.fileSize ?? 0
            let rel = url.path.replacingOccurrences(of: modelDirectory.path + "/", with: "")
            let name = url.lastPathComponent
            if name.hasSuffix(".safetensors") {
                let contentDigest = fileDigest(url) ?? "unreadable"
                weightLines.append("\(rel):\(size):\(contentDigest)")
            }
            let isTokenizerLike =
                name.hasPrefix("tokenizer") || name == "special_tokens_map.json"
                || name.hasPrefix("merges") || name.hasPrefix("vocab")
                || name.hasPrefix("chat_template")
            if isTokenizerLike, size <= 8 * 1024 * 1024,
               let contents = try? Data(contentsOf: url) {
                tokenizerData.append(contents)
            }
        }
        return (digest(of: weightLines.sorted()), digest(of: [String(decoding: tokenizerData, as: UTF8.self)]))
    }

    /// Streaming full-file SHA-256 (1 MiB chunks — never holds a model file
    /// in memory).
    private static func fileDigest(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func digest(of lines: [String]) -> String {
        let canonical = lines.joined(separator: "\n")
        let hash = SHA256.hash(data: Data(canonical.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

/// File-layout store: `sessions/<uuid>/baseline.json` (+ sibling
/// `baseline.sha256`) and a `current.json` pointer that names the ONE
/// recoverable generation. The pointer write is the commit boundary: a
/// session becomes durable-recoverable only after the pointer names it, and
/// retiring the pointer (tombstone) removes recoverability before any
/// teardown proceeds.
public final class EngineSessionBaselineStore {
    public struct Pointer: Codable, Equatable {
        public var formatVersion: Int
        public var sessionUUID: UUID
        public var retired: Bool

        public init(sessionUUID: UUID, retired: Bool) {
            self.formatVersion = EngineSessionBaselineRecord.currentFormatVersion
            self.sessionUUID = sessionUUID
            self.retired = retired
        }
    }

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    private func sessionDirectory(_ uuid: UUID) -> URL {
        root.appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(uuid.uuidString, isDirectory: true)
    }

    private var pointerURL: URL {
        root.appendingPathComponent("current.json", isDirectory: false)
    }

    private static func encode(_ payload: EngineSessionBaselineRecord) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(payload)
    }

    private static func decode(_ data: Data) throws -> EngineSessionBaselineRecord {
        try JSONDecoder().decode(EngineSessionBaselineRecord.self, from: data)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Pre-pointer commit stages. Without the pointer these files are
    /// UNREACHABLE by recovery — a throw here is a deterministic
    /// not-committed. Internal: the SIGKILL harness parks the process at
    /// exactly these stages.
    func writeBaselinePayload(_ record: EngineSessionBaselineRecord) throws {
        let payload = try Self.encode(record)
        try DurableFileWriter.writeDurable(
            payload,
            to: sessionDirectory(record.sessionUUID)
                .appendingPathComponent("baseline.json"),
            phase: .payload)
    }

    func writeBaselineDigest(_ record: EngineSessionBaselineRecord) throws {
        let digestHex = Self.sha256Hex(try Self.encode(record))
        try DurableFileWriter.writeDurable(
            Data(digestHex.utf8),
            to: sessionDirectory(record.sessionUUID)
                .appendingPathComponent("baseline.sha256"),
            phase: .digest)
    }

    func writeBaselineFiles(_ record: EngineSessionBaselineRecord) throws {
        try writeBaselinePayload(record)
        try writeBaselineDigest(record)
    }

    /// Durable commit: payload file (fsync) → digest file (fsync) → pointer
    /// (fsync). The pointer is the last write; a session is recoverable only
    /// after it lands. A throw at payload/digest leaves the pointer
    /// untouched (deterministic not-committed, worst case inert orphan
    /// files); a pointer post-rename directory-sync failure is ACCEPTED as
    /// committed-with-caveat (see `DurableFileWriter.writeDurable`).
    public func commitBaseline(_ record: EngineSessionBaselineRecord) throws {
        try writeBaselineFiles(record)
        let pointer = Pointer(sessionUUID: record.sessionUUID, retired: false)
        let pointerData = try JSONEncoder().encode(pointer)
        try DurableFileWriter.writeDurable(pointerData, to: pointerURL, phase: .pointer)
    }

    /// Durable retirement: replace the pointer with a tombstone BEFORE any
    /// teardown proceeds, so a crash can never present a discarded session
    /// as the recoverable one. Idempotent.
    public func retireCurrent() throws {
        let pointer = Pointer(sessionUUID: UUID(), retired: true)
        let pointerData = try JSONEncoder().encode(pointer)
        try DurableFileWriter.writeDurable(pointerData, to: pointerURL, phase: .pointer)
    }

    /// Read pointer → read payload → verify digest → verify version,
    /// generation binding, and identity bindings. Every failure degrades to
    /// `.invalid` / `.absent` (cold start) — no partial record is ever
    /// returned.
    public func loadCurrentValidated(
        expectedWeightsIdentity: String,
        expectedTokenizerIdentity: String
    ) -> EngineSessionBaselineReadOutcome {
        guard let pointerData = try? Data(contentsOf: pointerURL) else {
            return .absent(reason: "no durable pointer")
        }
        guard let pointer = try? JSONDecoder().decode(Pointer.self, from: pointerData),
              pointer.formatVersion == EngineSessionBaselineRecord.currentFormatVersion
        else {
            return .absent(reason: "pointer unreadable or unknown version")
        }
        guard !pointer.retired else {
            return .absent(reason: "pointer retired by a teardown")
        }
        let directory = sessionDirectory(pointer.sessionUUID)
        guard let payload = try? Data(
            contentsOf: directory.appendingPathComponent("baseline.json")),
            let digestData = try? Data(
                contentsOf: directory.appendingPathComponent("baseline.sha256"))
        else {
            return .invalid(reason: "baseline files missing")
        }
        let digestHex = String(decoding: digestData, as: UTF8.self)
        guard Self.sha256Hex(payload) == digestHex else {
            return .invalid(reason: "baseline checksum mismatch")
        }
        guard let record = try? Self.decode(payload) else {
            return .invalid(reason: "baseline payload undecodable")
        }
        guard record.formatVersion == EngineSessionBaselineRecord.currentFormatVersion else {
            return .invalid(
                reason: "unknown baseline format version \(record.formatVersion)")
        }
        guard record.sessionUUID == pointer.sessionUUID else {
            return .invalid(reason: "baseline does not match the pointer generation")
        }
        guard record.weightsIdentity == expectedWeightsIdentity,
              record.tokenizerIdentity == expectedTokenizerIdentity
        else {
            return .invalid(reason: "model/tokenizer identity mismatch")
        }
        return .valid(record: record)
    }
}

#if DEBUG
/// Process-level crash verification harness (SIGKILL semantics). Runs
/// inside the crash-child executable; the parent test spawns the child per
/// stage, reads the report file, and spawns a verify child after the kill.
/// This is PROCESS-crash evidence only — it makes no claim about power
/// loss or media failure.
public enum EngineBaselineCrashHarness {
    public static func killSelf() -> Never {
        kill(getpid(), SIGKILL)
        // Unreachable; guard against returning.
        exit(9)
    }

    /// Bootstrap a durable session, write the report, then SIGKILL self —
    /// the kill happens AFTER the pointer commit, so recovery must find the
    /// session.
    public static func bootstrapCommitAndKillSelf(
        storeRoot: URL, modelRoot: URL, reportURL: URL
    ) async -> Never {
        let engine = OversizedSegmentedEngine(
            modelDirectory: modelRoot, sessionBaselineDirectory: storeRoot)
        var uuid = ""
        do {
            _ = try await engine.debugEnsureSession(prefix: [1, 2, 3])
            if case .committed(let sessionUUID) = engine.durableBaselineState {
                uuid = sessionUUID.uuidString
            }
        } catch {
            fputs("harness bootstrap failed: \(error)\n", stderr)
            exit(3)
        }
        let report = """
        {"stage":"bootstrap","sessionUUID":"\(uuid)"}
        """
        try? Data(report.utf8).write(to: reportURL)
        killSelf()
    }

    /// Bootstrap, then tear down (durable retirement), then SIGKILL self —
    /// recovery must NOT resurrect the discarded session.
    public static func teardownCommitAndKillSelf(
        storeRoot: URL, modelRoot: URL, reportURL: URL
    ) async -> Never {
        // The crash-relevant effect of newSession is the durable pointer
        // retirement; the in-memory teardown that follows it needs no model.
        do {
            try EngineSessionBaselineStore(root: storeRoot).retireCurrent()
        } catch {
            fputs("harness teardown failed: \(error)\n", stderr)
            exit(3)
        }
        let report = "{\"stage\":\"teardown\"}"
        try? Data(report.utf8).write(to: reportURL)
        killSelf()
    }

    /// Park the commit MID-SEQUENCE and SIGKILL: `crash-after-payload` =
    /// payload durable, digest and pointer never written; `crash-after-digest`
    /// = payload+digest durable, pointer never written. In both cases the
    /// pointer never published, so recovery must treat the incomplete
    /// baseline as NOTHING (cold start) — verified against the real
    /// recovery result, not the child's exit code.
    public static func killMidCommit(
        storeRoot: URL, modelRoot: URL, reportURL: URL, stage: String
    ) async -> Never {
        let store = EngineSessionBaselineStore(root: storeRoot)
        let identity = EngineModelIdentity.compute(modelDirectory: modelRoot)
        let record = EngineSessionBaselineRecord(
            sessionUUID: UUID(), executionID: "S",
            weightsIdentity: identity.weights,
            tokenizerIdentity: identity.tokenizer,
            position: 0, continuationNextInput: "", continuationID: "cont-0",
            prefixTokens: [1, 2, 3])
        do {
            switch stage {
            case "crash-after-payload":
                try store.writeBaselinePayload(record)
            case "crash-after-digest":
                try store.writeBaselineFiles(record)
            default:
                fputs("unknown mid-commit stage \(stage)\n", stderr)
                exit(2)
            }
        } catch {
            fputs("harness mid-commit failed: \(error)\n", stderr)
            exit(3)
        }
        let report = "{\"stage\":\"\(stage)\"}"
        try? Data(report.utf8).write(to: reportURL)
        killSelf()
    }

    /// Simulate a torn baseline: a truncated payload file with a matching
    /// truncation-era digest sibling absent — recovery must degrade to cold
    /// start.
    public static func writeTornBaseline(storeRoot: URL, modelRoot: URL) -> Never {        let uuid = UUID()
        let directory = storeRoot.appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent(uuid.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let full = try! JSONEncoder().encode(
            EngineSessionBaselineRecord(
                sessionUUID: uuid, executionID: "S",
                weightsIdentity: EngineModelIdentity.compute(modelDirectory: modelRoot).weights,
                tokenizerIdentity: EngineModelIdentity.compute(modelDirectory: modelRoot).tokenizer,
                position: 0, continuationNextInput: "", continuationID: "cont-0",
                prefixTokens: [1, 2, 3]))
        try! Data(full.prefix(upTo: full.count / 2)).write(
            to: directory.appendingPathComponent("baseline.json"))
        let pointer = EngineSessionBaselineStore.Pointer(
            sessionUUID: uuid, retired: false)
        try! JSONEncoder().encode(pointer).write(to: storeRoot.appendingPathComponent("current.json"))
        exit(0)
    }

    /// Verify stage: run the public recovery entry point and print a JSON
    /// verdict.
    public static func verifyOutcome(storeRoot: URL, modelRoot: URL) async -> Never {
        let engine = OversizedSegmentedEngine(
            modelDirectory: modelRoot, sessionBaselineDirectory: storeRoot)
        let outcome: String
        do {
            switch try await engine.recoverDurableSession() {
            case .recovered(let sessionUUID, let position):
                outcome = """
                {"outcome":"recovered","sessionUUID":"\(sessionUUID.uuidString)","position":\(position.value)}
                """
            case .coldStart(let reason):
                let escaped = reason.replacingOccurrences(of: "\"", with: "'")
                outcome = "{\"outcome\":\"coldStart\",\"reason\":\"\(escaped)\"}"
            }
        } catch {
            let escaped = String(describing: error).replacingOccurrences(of: "\"", with: "'")
            outcome = "{\"outcome\":\"error\",\"reason\":\"\(escaped)\"}"
        }
        print(outcome)
        exit(0)
    }
}
#endif
