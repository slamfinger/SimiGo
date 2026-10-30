import Darwin
import Foundation
import Network
import SQLite3
import XCTest
import LOCALBCore
import SimiGoRuntimeContract

@testable import SimiGo

// MARK: - Polling

enum CancelPathWait {
    static func until(
        timeout: TimeInterval,
        interval: TimeInterval = 0.02,
        _ condition: @escaping @Sendable () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
        return condition()
    }
}

// MARK: - Cancel callback recorder

/// Records every `cancelGenerationHandler` invocation. The chain's contract is
/// checked by COUNT and by the affected request id — never by trusting that a
/// callback "probably happened".
final class RecordingCancelHandler: @unchecked Sendable {
    private let lock = NSLock()
    private var _requestIds: [String] = []
    private var _times: [Date] = []

    func record(_ requestId: String) {
        lock.withLock {
            _requestIds.append(requestId)
            _times.append(Date())
        }
    }

    var count: Int { lock.withLock { _requestIds.count } }
    var requestIds: [String] { lock.withLock { _requestIds } }
    var times: [Date] { lock.withLock { _times } }

    func waitForCount(_ expected: Int, timeout: TimeInterval) async -> Bool {
        await CancelPathWait.until(timeout: timeout) { self.count >= expected }
    }
}

// MARK: - Blocking stub engine

/// A generation stand-in that can hold the generate task open until the product
/// cancels it. This is the component that makes "the cancel actually reached a
/// running generation" checkable WITHOUT a model: the stub only leaves its loop
/// after `Task.isCancelled` becomes true.
///
/// Evidence levels are kept distinct (owner ruling 2026-10-29):
///   1. the cancel callback fired            -> `RecordingCancelHandler`
///   2. the generate task observed cancel    -> `cancelObserved` + `exitObserved`
///   3. real model execution stopped         -> only the real-model window (T-C)
final class BlockingStubEngine: @unchecked Sendable {
    enum Mode: Sendable {
        /// Emit the chunks, then finish. `silenceAfterFirst` keeps the stream
        /// quiet long enough for the heartbeat to have to inject an event.
        case complete(chunks: [String], text: String, silenceAfterFirst: TimeInterval)
        /// Emit one chunk then stream periodic chunks until the task is cancelled.
        case streamUntilCancelled(first: String, interval: TimeInterval)
        /// Emit one chunk then fail generation with CancellationError while the
        /// client stays connected (server-internal cancel shape).
        case throwCancellationAfterChunk(first: String, delay: TimeInterval)
        /// Non-streaming shape: one accumulator callback, then hold until cancel.
        case blockUntilCancelled(first: String?)
        /// Call-order fork for the detached-orphan yield: the FIRST generate
        /// call streams and keeps ticking until cancelled; every LATER call
        /// holds briefly, emits `laterChunks` and completes. The later hold
        /// must outlive one orphan tick so the contention probe sees it.
        case firstStreamsThenCompletes(
            first: String, interval: TimeInterval,
            laterHold: TimeInterval, laterChunks: [String], laterText: String)
    }

    private let mode: Mode
    private let lock = NSLock()
    private var _generateCount = 0
    private var _started = false
    private var _cancelObserved = false
    private var _exitObserved = false
    private var _chunksAfterCancel = 0

    init(_ mode: Mode) {
        self.mode = mode
    }

    var generateCount: Int { lock.withLock { _generateCount } }
    var started: Bool { lock.withLock { _started } }
    var cancelObserved: Bool { lock.withLock { _cancelObserved } }
    var exitObserved: Bool { lock.withLock { _exitObserved } }

    /// Chunks the ENGINE handed to `onChunk` after it had observed cancellation.
    /// The engine loop exits before this point, so a non-zero value means the
    /// stub kept emitting into a cancelled turn. This measures the engine side;
    /// it does not measure the server-side send path of a closed connection.
    var chunksAfterCancel: Int { lock.withLock { _chunksAfterCancel } }

    func waitForStarted(timeout: TimeInterval = 5) async -> Bool {
        await CancelPathWait.until(timeout: timeout) { self.started }
    }

    func waitForCancelObserved(timeout: TimeInterval = 10) async -> Bool {
        await CancelPathWait.until(timeout: timeout) { self.cancelObserved }
    }

    func waitForExit(timeout: TimeInterval = 10) async -> Bool {
        await CancelPathWait.until(timeout: timeout) { self.exitObserved }
    }

    func makeHandler() -> HTTPServer.GenerateHandler {
        { [self] _, _, _, _, _, _, _, onChunk, _ in
            let callIndex = lock.withLock {
                _generateCount += 1
                _started = true
                return _generateCount
            }
            defer {
                lock.withLock { _exitObserved = true }
            }

            switch mode {
            case .complete(let chunks, let text, let silenceAfterFirst):
                for (index, chunk) in chunks.enumerated() {
                    if index > 0 {
                        let pause = index == 1 ? silenceAfterFirst : 0
                        if pause > 0 {
                            try? await Task.sleep(
                                nanoseconds: UInt64(pause * 1_000_000_000))
                        }
                    }
                    emit(chunk, onChunk: onChunk)
                }
                return GenerationResult(text: text, usage: nil, completion: .complete)

            case .streamUntilCancelled(let first, let interval):
                emit(first, onChunk: onChunk)
                var tick = 0
                // Bound the hold so a test that never cancels fails on its
                // callback assertion instead of hanging the suite.
                while tick < 1_000 {
                    if Task.isCancelled { break }
                    do {
                        try await Task.sleep(
                            nanoseconds: UInt64(interval * 1_000_000_000))
                    } catch {
                        break
                    }
                    if Task.isCancelled { break }
                    emit("tick-\(tick)", onChunk: onChunk)
                    tick += 1
                }
                if Task.isCancelled {
                    lock.withLock { _cancelObserved = true }
                }
                throw CancellationError()

            case .throwCancellationAfterChunk(let first, let delay):
                emit(first, onChunk: onChunk)
                if delay > 0 {
                    try? await Task.sleep(
                        nanoseconds: UInt64(delay * 1_000_000_000))
                }
                throw CancellationError()

            case .blockUntilCancelled(let first):
                if let first {
                    emit(first, onChunk: onChunk)
                }
                var tick = 0
                while tick < 1_000 {
                    if Task.isCancelled { break }
                    do {
                        try await Task.sleep(nanoseconds: 20_000_000)
                    } catch {
                        break
                    }
                    tick += 1
                }
                if Task.isCancelled {
                    lock.withLock { _cancelObserved = true }
                }
                throw CancellationError()

            case .firstStreamsThenCompletes(
                let first, let interval, let laterHold, let laterChunks, let laterText):
                guard callIndex == 1 else {
                    if laterHold > 0 {
                        try? await Task.sleep(
                            nanoseconds: UInt64(laterHold * 1_000_000_000))
                    }
                    for chunk in laterChunks {
                        emit(chunk, onChunk: onChunk)
                    }
                    return GenerationResult(
                        text: laterText, usage: nil, completion: .complete)
                }
                emit(first, onChunk: onChunk)
                var tick = 0
                while tick < 1_000 {
                    if Task.isCancelled { break }
                    do {
                        try await Task.sleep(
                            nanoseconds: UInt64(interval * 1_000_000_000))
                    } catch {
                        break
                    }
                    if Task.isCancelled { break }
                    emit("orphan-tick-\(tick)", onChunk: onChunk)
                    tick += 1
                }
                if Task.isCancelled {
                    lock.withLock { _cancelObserved = true }
                }
                throw CancellationError()
            }
        }
    }

    private func emit(
        _ chunk: String,
        onChunk: @escaping @Sendable (String) -> Void
    ) {
        let alreadyCancelled = lock.withLock { _cancelObserved }
        if alreadyCancelled {
            lock.withLock { _chunksAfterCancel += 1 }
        }
        onChunk(chunk)
    }
}

// MARK: - Trace probe

enum CancelTrace {
    static var url: URL {
        SimiGoPaths.logs.appendingPathComponent("native_mlx_trace.log")
    }

    static func size() -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.size] as? Int ?? 0
    }

    /// Bytes appended after `since` (optionally cut at `until`).
    static func window(since: Int, until: Int? = nil) -> String {
        guard let data = try? Data(contentsOf: url), data.count > since else { return "" }
        let end = min(until ?? data.count, data.count)
        guard end > since else { return "" }
        return String(decoding: data[since..<end], as: UTF8.self)
    }

    static func lines(since: Int, until: Int? = nil) -> [String] {
        window(since: since, until: until)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    static func waitForLine(
        containing markers: [String],
        since: Int,
        timeout: TimeInterval
    ) async -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let hit = lines(since: since).first { line in
                markers.allSatisfy(line.contains)
            }
            if let hit { return hit }
            try? await Task.sleep(nanoseconds: 100_000_000)
        } while Date() < deadline
        return lines(since: since).first { line in
            markers.allSatisfy(line.contains)
        }
    }

    static func count(
        _ needle: String,
        since: Int,
        until: Int? = nil
    ) -> Int {
        lines(since: since, until: until).reduce(0) {
            $0 + ($1.contains(needle) ? 1 : 0)
        }
    }

    /// `[PROTOCOL] arrive ... r=<6 hex> ...` — the short request id the cancel
    /// callback's full `req-<8 hex>` id must agree with.
    static func shortArriveID(of line: String) -> String? {
        guard line.contains("[PROTOCOL] arrive") else { return nil }
        return token("r=", in: line)
    }

    /// `req-1a2b3c4d` -> `1a2b3c` (the trace's short form).
    static func shortID(ofRequestID requestID: String) -> String {
        String(requestID.dropFirst("req-".count).prefix(6))
    }

    static func token(_ marker: String, in line: String) -> String? {
        guard let range = line.range(of: marker) else { return nil }
        let value = line[range.upperBound...].prefix { !$0.isWhitespace }
        return value.isEmpty ? nil : String(value)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    /// Trace lines start `[yyyy-MM-dd HH:mm:ss.SSS] ...`.
    static func timestamp(of line: String) -> Date? {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else {
            return nil
        }
        let stamp = String(line[line.index(after: line.startIndex)..<close])
        return timestampFormatter.date(from: stamp)
    }
}

// MARK: - Streaming client

/// A real signed LOCALB/TLS streaming client. Disconnect = cancel the reading
/// task, which closes the connection (FIN); the manual harness's RST path is a
/// recorded residual gap, not something this client pretends to cover.
final class StreamingClient: @unchecked Sendable {
    struct Event: Sendable {
        let line: String
        let at: Date
    }

    let host: LOCALBAuthorizedE2E.Host
    let port: Int

    private let lock = NSLock()
    private var _events: [Event] = []
    private var _status: Int?
    private var _finished = false
    private var _error: Error?
    private var task: Task<Void, Never>?

    init(host: LOCALBAuthorizedE2E.Host, port: Int) {
        self.host = host
        self.port = port
    }

    var status: Int? { lock.withLock { _status } }
    var isFinished: Bool { lock.withLock { _finished } }
    var errorDescription: String? {
        lock.withLock { _error.map { String(describing: $0) } }
    }
    var events: [Event] { lock.withLock { _events } }
    var lines: [String] { lock.withLock { _events.map(\.line) } }
    var sse: String { lines.joined(separator: "\n") }

    func start(path: String, body: [String: Any]) async throws {
        let request = try await Self.makeRequest(
            host: host, port: port, path: path, body: body)
        let session = host.session
        let task = Task { [weak self] in
            do {
                let (bytes, response) = try await session.bytes(for: request)
                self?.setStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
                for try await line in bytes.lines {
                    self?.append(line)
                }
            } catch {
                self?.setError(error)
            }
            self?.markFinished()
        }
        self.task = task
        _ = await waitForStatus(timeout: 10)
    }

    /// One signed request for callers that need the raw data task (the
    /// non-streaming cancel case cancels before any response byte exists).
    static func makeRequest(
        host: LOCALBAuthorizedE2E.Host,
        port: Int,
        path: String,
        body: [String: Any]
    ) async throws -> URLRequest {
        let payload = try JSONSerialization.data(withJSONObject: body)
        let headers = try await LOCALBAuthorizedE2E.proofHeaders(
            host: host, port: port, method: "POST", target: path,
            contentType: "application/json", body: payload)
        var request = URLRequest(
            url: URL(string: "https://127.0.0.1:\(port)\(path)")!,
            timeoutInterval: 900)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = payload
        return request
    }

    func waitForStatus(timeout: TimeInterval) async -> Int? {
        _ = await CancelPathWait.until(timeout: timeout) { self.status != nil }
        return status
    }

    /// Waits for a line containing all markers, only at or after `afterIndex`.
    func waitForLine(
        containing markers: [String],
        afterIndex: Int = 0,
        timeout: TimeInterval
    ) async -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let hit = matchingLine(containing: markers, afterIndex: afterIndex) {
                return hit
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        } while Date() < deadline
        return matchingLine(containing: markers, afterIndex: afterIndex)
    }

    func matchingLine(containing markers: [String], afterIndex: Int = 0) -> String? {
        let snapshot = events
        guard afterIndex < snapshot.count else { return nil }
        return snapshot[afterIndex...].first { event in
            markers.allSatisfy(event.line.contains)
        }?.line
    }

    func waitForFinished(timeout: TimeInterval) async -> Bool {
        await CancelPathWait.until(timeout: timeout) { self.isFinished }
    }

    /// Cancels the reading task. URLSession propagates this to the data task and
    /// closes the connection; the server sees the peer close while generation is
    /// still running.
    @discardableResult
    func cancelReading() -> Date {
        let at = Date()
        task?.cancel()
        return at
    }

    private func setStatus(_ status: Int) {
        lock.withLock { _status = status }
    }

    private func append(_ line: String) {
        lock.withLock { _events.append(Event(line: line, at: Date())) }
    }

    private func setError(_ error: Error) {
        lock.withLock { _error = error }
    }

    private func markFinished() {
        lock.withLock { _finished = true }
    }

    /// Parses a `data: {...}` line. Returns nil for `[DONE]`, heartbeats and
    /// non-JSON lines.
    static func jsonObject(from line: String) -> [String: Any]? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count)
            .trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]",
              let data = payload.data(using: .utf8)
        else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func lastEvent(
        ofType type: String,
        in lines: [String]
    ) -> [String: Any]? {
        for line in lines.reversed() where line.contains("\"type\":\"\(type)\"") {
            if let object = jsonObject(from: line) { return object }
        }
        return nil
    }
}

// MARK: - ES/IS sweep

/// Read-only id-set + row-count snapshot over the fixed table set the owner
/// named. Answer settlements and `is-retrieval:<demand>` rows are kept as two
/// disjoint classes; no assertion is allowed to compare a single global count.
struct ESISSweep {
    struct Snapshot: Equatable {
        var counts: [String: Int] = [:]
        var ids: [String: Set<String>] = [:]
    }

    private static let tables: [(table: String, idExpression: String)] = [
        ("execution_states", "state_id"),
        ("settlements", "settlement_id"),
        ("settlement_bindings",
         "settlement_id || '|' || COALESCE(name, '') || '|' || COALESCE(value_digest, '')"),
        ("information_advancements", "advancement_id"),
        ("settlement_summaries", "settlement_id"),
        ("settlement_reuse_contracts", "settlement_id"),
        ("settlement_consumptions", "consumption_id"),
        ("information_reuse_events", "reuse_id"),
        ("information_demands", "demand_id"),
        ("chat_execution_links", "session_id || '|' || current_state_id"),
        ("chat_messages", "CAST(id AS TEXT)"),
        ("retrieval_settlements", "demand_id"),
        ("roots", "root_id"),
        ("external_files", "CAST(file_id AS TEXT)"),
        ("information_items", "item_id"),
    ]

    static func take() -> Snapshot {
        var snapshot = Snapshot()
        guard FileManager.default.fileExists(atPath: SimiGoPaths.databaseURL.path) else {
            return snapshot
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            SimiGoPaths.databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil
        ) == SQLITE_OK else {
            sqlite3_close(handle)
            return snapshot
        }
        guard let handle else { return snapshot }
        defer { sqlite3_close(handle) }
        sqlite3_busy_timeout(handle, 3_000)

        for (table, idExpression) in tables {
            snapshot.counts[table] = scalar(
                handle, "SELECT COUNT(*) FROM \(table);")
            snapshot.ids[table] = stringColumn(
                handle, "SELECT \(idExpression) FROM \(table);")
        }
        return snapshot
    }

    /// Async settlement/summary writes can trail the response; two identical
    /// consecutive reads are required before a snapshot is used as evidence.
    static func stable(timeout: TimeInterval = 3) async -> Snapshot {
        var current = take()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
            let next = take()
            if next == current { return next }
            current = next
        }
        return current
    }

    static func added(
        _ table: String,
        before: Snapshot,
        after: Snapshot
    ) -> Set<String> {
        (after.ids[table] ?? []).subtracting(before.ids[table] ?? [])
    }

    static func removed(
        _ table: String,
        before: Snapshot,
        after: Snapshot
    ) -> Set<String> {
        (before.ids[table] ?? []).subtracting(after.ids[table] ?? [])
    }

    static func newAnswerSettlementIDs(
        before: Snapshot, after: Snapshot
    ) -> Set<String> {
        added("settlements", before: before, after: after)
            .filter { !$0.hasPrefix("is-retrieval:") }
    }

    static func newRetrievalSettlementIDs(
        before: Snapshot, after: Snapshot
    ) -> Set<String> {
        added("settlements", before: before, after: after)
            .filter { $0.hasPrefix("is-retrieval:") }
    }

    static func newAnswerBindingIDs(
        before: Snapshot, after: Snapshot
    ) -> Set<String> {
        added("settlement_bindings", before: before, after: after)
            .filter { !$0.hasPrefix("is-retrieval:") }
    }

    static func newRetrievalBindingIDs(
        before: Snapshot, after: Snapshot
    ) -> Set<String> {
        added("settlement_bindings", before: before, after: after)
            .filter { $0.hasPrefix("is-retrieval:") }
    }

    static func newChatStateIDs(
        before: Snapshot, after: Snapshot
    ) -> Set<String> {
        added("execution_states", before: before, after: after)
            .filter { $0.hasPrefix("chat-") }
    }

    static func answerSettlementIDs(forState stateID: String) -> Set<String> {
        stringColumn(
            "SELECT settlement_id FROM settlements WHERE state_id = '\(sqlEscaped(stateID))' AND settlement_id NOT LIKE 'is-retrieval:%';"
        )
    }

    static func chatStateID(sessionID: String) -> String? {
        let rows = stringColumn(
            "SELECT current_state_id FROM chat_execution_links WHERE session_id = '\(sqlEscaped(sessionID))';"
        )
        return rows.first
    }

    @MainActor
    static func answeredDemand(
        sessionID: String, query: String
    ) throws -> SimiGoESISDatabase.AnsweredDemand? {
        let store = ExecutionStateGraphStore()
        guard let db = store.esis else { return nil }
        return try db.answeredDemand(sessionID: sessionID, query: query)
    }

    @MainActor
    static func bindings(settlementID: String) throws -> [String: String] {
        let store = ExecutionStateGraphStore()
        guard let db = store.esis else { return [:] }
        return try db.settlementBindings(settlementID: settlementID)
    }

    @MainActor
    static func summary(
        settlementID: String
    ) throws -> SimiGoESISDatabase.SettlementSummaryRecord? {
        let store = ExecutionStateGraphStore()
        guard let db = store.esis else { return nil }
        return try db.settlementSummary(settlementID: settlementID)
    }

    // MARK: - SQLite helpers

    private static func sqlEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private static func scalar(_ handle: OpaquePointer, _ sql: String) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt
        else {
            sqlite3_finalize(stmt)
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private static func stringColumn(
        _ handle: OpaquePointer, _ sql: String
    ) -> Set<String> {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt
        else {
            sqlite3_finalize(stmt)
            return []
        }
        defer { sqlite3_finalize(stmt) }
        var values: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let text = sqlite3_column_text(stmt, 0) {
                values.insert(String(cString: text))
            }
        }
        return values
    }

    private static func stringColumn(_ sql: String) -> Set<String> {
        guard FileManager.default.fileExists(atPath: SimiGoPaths.databaseURL.path) else {
            return []
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            SimiGoPaths.databaseURL.path, &handle, SQLITE_OPEN_READONLY, nil
        ) == SQLITE_OK else {
            sqlite3_close(handle)
            return []
        }
        guard let handle else { return [] }
        defer { sqlite3_close(handle) }
        sqlite3_busy_timeout(handle, 3_000)
        return stringColumn(handle, sql)
    }
}

// MARK: - Server harness

enum CancelPathHarness {
    static func requireIsolatedRoots() throws -> URL {
        let env = ProcessInfo.processInfo.environment
        guard let home = env["SIMIGO_HOME"], !home.isEmpty,
              let graphStore = env["SIMIGO_STATE_GRAPH_STORE"], !graphStore.isEmpty,
              let cache = env["SIMIGO_CACHE_ROOT"], !cache.isEmpty,
              home.hasPrefix("/"), graphStore.hasPrefix("/"), cache.hasPrefix("/")
        else {
            throw XCTSkip(
                "isolated roots not injected: run through tools/make_isolated_xctestrun.py "
                    + "so no real model or user state is touched")
        }
        let root = URL(
            fileURLWithPath: (home as NSString).standardizingPath, isDirectory: true)
        XCTAssertTrue(
            SimiGoPaths.databaseURL.path.hasPrefix(root.path),
            "authoritative store resolves outside the isolation root")
        return root
    }

    /// A model-free snapshot DIRECTORY: identity is re-derived from disk without
    /// loading weights, so settlement/admission are real product code.
    static func makeModelStandIn(_ tag: String) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SimiGoCancelPath-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true)
        try Data(#"{"model_type":"cancel-path-stand-in"}"#.utf8)
            .write(to: dir.appendingPathComponent("tokenizer.adapter.json"))
        return dir.path
    }

    static func startServer(
        port: Int,
        modelPath: String,
        host: LOCALBAuthorizedE2E.Host,
        engine: BlockingStubEngine,
        cancel: RecordingCancelHandler
    ) throws -> HTTPServer {        let identity = SimiGoProducerIdentity.identity(fromPath: modelPath)
        let server = HTTPServer(
            port: port,
            modelId: "cancel-path-http-test",
            generateHandler: engine.makeHandler(),
            forkBranchHandler: { _, _, _, target in
                SessionCacheMetadata(
                    storageKey: "t/\(target)", modelId: "cancel-path-http-test",
                    savedAt: Date(), history: [])
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true },
            cancelGenerationHandler: { cancel.record($0) },
            informationTurnProducer: {
                InformationTurnProducer(
                    modelIdentity: identity.model, identity: identity)
            }
        )
        server.configureLOCALBTransport(identity: host.identity)
        server.configureLOCALBRequestAuthorization(
            coordinator: host.coordinator,
            trustedCheckpoint: host.checkpointProvider)
        try server.start()
        return server
    }

    static func waitUntilReady(
        host: LOCALBAuthorizedE2E.Host,
        port: Int,
        timeout: TimeInterval = 20
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let result = try? await LOCALBAuthorizedE2E.send(
                host: host, port: port, method: "GET", path: "/v1/models"),
                result.1.statusCode < 500 {
                return true
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return false
    }
}
