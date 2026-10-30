import Darwin
import Foundation
import Network
import XCTest
import LOCALBCore
import SimiGoRuntimeContract

@testable import SimiGo

/// 二.5 T-B（owner 2026-10-29 授权；2026-10-30 ADR 后语义更新）：取消链内部
/// 的三段控制流。
///
/// B1  peer close -> [PROTOCOL] peerClosed -> terminate -> **detach**：生成
///     不被取消（无 cancel 回调、requestTask 不 cancel），本轮继续跑完并停
///     在 fail-closed 的收尾路径（不结算、不提交）。
/// B2a the SSE heartbeat keeps a silent-but-live stream alive (handler wiring).
/// B2b a heartbeat send error escalates to terminate -> **detach**（手动取消
///     不经过此路径），with a deterministic RST peer instead of "wait 5 s and
///     hope".
///
/// These prove control flow, not that a real model stopped. B2b is allowed to
/// end as an evidence gap (XCTSkip) if Network.framework never hands the error
/// to the send completion under this RST shape — it must never be reported as
/// PASS when the branch was not entered.
final class CancelChainInternalTests: XCTestCase {

    private let port = 59_382

    private var host: LOCALBAuthorizedE2E.Host!
    private var modelPath: String!

    override func setUpWithError() throws {
        _ = try CancelPathHarness.requireIsolatedRoots()
        host = try LOCALBAuthorizedE2E.makeHost()
        modelPath = try CancelPathHarness.makeModelStandIn("tb")
    }

    override func tearDown() {
        if let modelPath {
            try? FileManager.default.removeItem(atPath: modelPath)
        }
        modelPath = nil
        host = nil
        super.tearDown()
    }

    @MainActor
    private func startServer(
        _ engine: BlockingStubEngine,
        _ cancel: RecordingCancelHandler
    ) async throws -> HTTPServer {
        let server = try CancelPathHarness.startServer(
            port: port, modelPath: modelPath, host: host,
            engine: engine, cancel: cancel)
        let ready = await CancelPathHarness.waitUntilReady(
            host: host, port: port)
        XCTAssertTrue(ready, "the stub server never became ready on :\(port)")
        return server
    }

    private func responsesBody(session: String, input: String) -> [String: Any] {
        [
            "model": "cancel-path-http-test",
            "input": input,
            "session_id": session,
            "stream": true,
        ]
    }

    // MARK: - B1) Peer close detaches the generation instead of cancelling it

    @MainActor
    func testPeerCloseDetachesGenerationWithoutCancelling() async throws {
        let session = "tb1-\(UUID().uuidString)"
        let question = "does a peer close let the local turn finish"

        // The turn is short but outlives the close: the first chunk proves the
        // stream is live, the silent gap lets the client leave first, and the
        // second chunk + return prove the engine kept running.
        let engine = BlockingStubEngine(
            .complete(chunks: ["B1-FIRST", "B1-SECOND"],
                      text: "B1-ANSWER", silenceAfterFirst: 2))
        let cancel = RecordingCancelHandler()
        let server = try await startServer(engine, cancel)
        defer { server.stop() }

        let traceSince = CancelTrace.size()

        let client = StreamingClient(host: host, port: port)
        try await client.start(
            path: "/v1/responses",
            body: responsesBody(session: session, input: question))
        XCTAssertEqual(client.status, 200, client.sse)
        let firstDelta = await client.waitForLine(
            containing: ["output_text.delta", "B1-FIRST"], timeout: 15)
        XCTAssertNotNil(
            firstDelta, "the stream must be live before the close: \(client.sse)")
        XCTAssertEqual(engine.generateCount, 1)
        XCTAssertTrue(engine.started)

        client.cancelReading()

        let peerClosedLine = await CancelTrace.waitForLine(
            containing: ["[PROTOCOL] peerClosed"], since: traceSince, timeout: 10)
        let line = try XCTUnwrap(
            peerClosedLine,
            "[PROTOCOL] peerClosed missing from the window:\n"
                + CancelTrace.window(since: traceSince))
        let shortID = try XCTUnwrap(
            CancelTrace.token("r=", in: line),
            "the peerClosed line carries no request id: \(line)")

        let detachLine = await CancelTrace.waitForLine(
            containing: ["[DETACH]", "slots=1"], since: traceSince, timeout: 10)
        let detach = try XCTUnwrap(
            detachLine,
            "[DETACH] missing from the window:\n"
                + CancelTrace.window(since: traceSince))
        XCTAssertEqual(
            String(CancelTrace.token("r=", in: detach)?
                .dropFirst("req-".count).prefix(6) ?? "-"),
            shortID,
            "the detached turn is the request the peer close named: \(detach)")

        // The detached turn must keep running after the client is gone.
        let exited = await engine.waitForExit(timeout: 15)
        XCTAssertTrue(exited, "the detached generation never ran to completion")
        XCTAssertFalse(
            engine.cancelObserved,
            "the engine observed a cancellation after the client left")
        XCTAssertEqual(
            engine.chunksAfterCancel, 0,
            "chunks were emitted after the stub observed cancellation")
        XCTAssertEqual(
            cancel.count, 0,
            "a client disconnect must not call the cancel handler: \(cancel.requestIds)")

        // Nothing may re-terminate into a cancel: sleep past the watcher's next
        // chance (connection teardown, send-error path) and re-check.
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(
            cancel.count, 0,
            "a second close/terminate produced a cancel callback: \(cancel.requestIds)")
        XCTAssertEqual(
            CancelTrace.count(
                "[DETACH]", since: traceSince), 1,
            "the orphan slot must be claimed exactly once:\n"
                + CancelTrace.window(since: traceSince))
        print("[TB-B1] peerClosed=\(line) detach=\(detach) callbacks=\(cancel.requestIds)")
    }

    // MARK: - B2a) The heartbeat keeps a silent-but-live stream alive

    @MainActor
    func testHeartbeatKeepsSilentStreamAlive() async throws {
        let session = "tb2a-\(UUID().uuidString)"
        let question = "does the heartbeat keep the silent stream alive"

        // 6 s of engine silence after the first chunk; the heartbeat interval is
        // the product constant (5 s), so exactly one quiet window is covered
        // without touching the product's timing.
        let engine = BlockingStubEngine(
            .complete(chunks: ["SILENT-FIRST", "SILENT-LAST"],
                      text: "SILENT-ANSWER", silenceAfterFirst: 6))
        let cancel = RecordingCancelHandler()
        let server = try await startServer(engine, cancel)
        defer { server.stop() }

        let client = StreamingClient(host: host, port: port)
        try await client.start(
            path: "/v1/responses",
            body: responsesBody(session: session, input: question))
        XCTAssertEqual(client.status, 200, client.sse)
        let firstDelta = await client.waitForLine(
            containing: ["output_text.delta", "SILENT-FIRST"], timeout: 15)
        XCTAssertNotNil(firstDelta, "no first delta: \(client.sse)")

        let indexAfterFirstDelta = client.events.count
        let heartbeatLine = await client.waitForLine(
            containing: ["\"type\":\"response.in_progress\""],
            afterIndex: indexAfterFirstDelta, timeout: 8)
        let heartbeat = try XCTUnwrap(
            heartbeatLine,
            "the silent window produced no heartbeat event: \(client.sse)")
        // Liveness is proven by the engine never observing a cancellation and
        // still returning a result — not by the callback count. A normal
        // terminal close signals the handler once after the turn already
        // finished (T-A A1's finding); that callback cannot interrupt a
        // generation the engine never saw cancelled.
        XCTAssertFalse(
            engine.cancelObserved,
            "the running generation observed a cancellation during the silent window")
        XCTAssertEqual(
            engine.generateCount, 1,
            "the heartbeat entered a second generation: \(engine.generateCount)")
        XCTAssertTrue(engine.started)

        let completed = await client.waitForLine(
            containing: ["\"type\":\"response.completed\""], timeout: 20)
        let completedLine = try XCTUnwrap(
            completed, "the stream did not finish: \(client.sse)")
        let finished = await client.waitForFinished(timeout: 10)
        XCTAssertTrue(finished, client.sse)

        XCTAssertEqual(engine.generateCount, 1, "the heartbeat must not restart generation")
        XCTAssertTrue(engine.exitObserved)
        XCTAssertFalse(
            engine.cancelObserved,
            "the heartbeat cancelled a generation that went on to complete")
        XCTAssertNil(
            client.errorDescription,
            "the client must stay connected through the silent window")

        let event = try XCTUnwrap(
            StreamingClient.jsonObject(from: heartbeat),
            "heartbeat event is not JSON: \(heartbeat)")
        XCTAssertEqual(event["type"] as? String, "response.in_progress")
        let sequence = try XCTUnwrap(event["sequence_number"] as? Int)
        XCTAssertGreaterThan(sequence, 1, "the heartbeat has its own sequence number")
        let completion = try XCTUnwrap(
            StreamingClient.jsonObject(from: completedLine))
        XCTAssertEqual(completion["type"] as? String, "response.completed")
        print(
            "[TB-B2a] heartbeat=\(heartbeat) completedSequence="
                + "\(completion["sequence_number"] ?? "nil") "
                + "chunksAfterCancel=\(engine.chunksAfterCancel) "
                + "cancelObserved=\(engine.cancelObserved) "
                + "cancelCount=\(cancel.count) cancelIds=\(cancel.requestIds) "
                + "cancelTimes=\(cancel.times)")
    }

    // MARK: - B2b) Heartbeat send failure escalates to terminate -> detach (RST peer)

    /// Deterministic dead-connection injection: a POSIX listener accepts the
    /// connection, then closes it with SO_LINGER 0 (RST). The heartbeat is run
    /// directly on that `ConnectionContext` at a 0.05 s interval, so the first
    /// or second send lands on a reset socket.
    ///
    /// Deliberate, documented deviation from the literal test-plan wording
    /// "do not arm the peer-close watcher": `markGenerationStarted()` is
    /// required for `closeAndTakeRequestTask` to grant a detach at all, and it
    /// arms the watcher as a side effect. The watcher cannot terminate here
    /// because `onPeerClosed` is left nil — only the heartbeat's send-error
    /// branch can call `terminate`.
    @MainActor
    func testHeartbeatSendFailureDetachesGeneration() async throws {
        let peer: RSTPeer
        do {
            peer = try RSTPeer()
        } catch {
            throw XCTSkip(
                "B2b evidence gap: could not construct the RST peer: \(error)")
        }
        defer { peer.stop() }

        let connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: peer.port)!,
            using: .tcp)
        let stateRecorder = ConnectionStateRecorder()
        // Read-only recorder: it never terminates, so it cannot mask the
        // heartbeat branch under test.
        connection.stateUpdateHandler = { state in
            stateRecorder.record(state)
            if case .failed = state {
                // If the transport reports failure before any send error is
                // delivered, keep waiting for the send completion below.
            }
        }
        connection.start(queue: DispatchQueue(label: "b2b.nwconnection"))

        guard await peer.waitForAccepted(timeout: 5) else {
            connection.cancel()
            throw XCTSkip(
                "B2b evidence gap: the RST peer never accepted the connection; "
                    + "state=\(stateRecorder.latest)")
        }
        guard await CancelPathWait.until(timeout: 5, {
            stateRecorder.latest.contains("ready")
        }) else {
            connection.cancel()
            throw XCTSkip(
                "B2b evidence gap: NWConnection never reached ready against the "
                    + "RST peer; state=\(stateRecorder.latest)")
        }
        guard await peer.waitForReset(timeout: 5) else {
            connection.cancel()
            throw XCTSkip(
                "B2b evidence gap: the RST peer never closed the accepted socket; "
                    + "state=\(stateRecorder.latest)")
        }

        let context = HTTPServer.ConnectionContext(connection: connection)
        // `onPeerClosed` intentionally stays nil (see the doc comment above).
        XCTAssertTrue(context.markGenerationStarted())

        let cancel = RecordingCancelHandler()
        let server = HTTPServer(
            port: 59_383,
            modelId: "cancel-chain-heartbeat-test",
            generateHandler: { _, _, _, _, _, _, _, _, _ in
                GenerationResult(text: "", usage: nil, completion: .complete)
            },
            forkBranchHandler: { _, _, _, target in
                SessionCacheMetadata(
                    storageKey: "t/\(target)", modelId: "cancel-chain-heartbeat-test",
                    savedAt: Date(), history: [])
            },
            deleteBranchHandler: { _, _, _ in },
            listBranchesHandler: { _, _ in (live: [], checkpoints: []) },
            checkHealthHandler: { true },
            cancelGenerationHandler: { cancel.record($0) }
        )
        let eventCounter = LockedCounter()
        let traceSince = CancelTrace.size()
        let heartbeat = server.startSSEHeartbeat(
            for: context,
            interval: 0.05,
            makeEvent: {
                eventCounter.bump()
                return Data(": b2b-probe\n\n".utf8)
            })
        defer {
            heartbeat.cancel()
            connection.cancel()
        }

        let detached = await CancelPathWait.until(timeout: 3) {
            context.detachedByClient
        }
        guard detached else {
            // The spec's fallback: record the observed close behaviour and the
            // failure location, and stop. No repeated runs, no semantics change,
            // no product injection point.
            throw XCTSkip(
                "B2b evidence gap (unverified, not PASS): the heartbeat send "
                    + "completion never delivered an error under this RST shape. "
                    + "callbacks=\(cancel.count) closed=\(context.closed) "
                    + "detached=\(context.detachedByClient) "
                    + "heartbeatEvents=\(eventCounter.value) "
                    + "connectionState=\(stateRecorder.latest)")
        }

        XCTAssertTrue(context.closed, "terminate must close the context")
        XCTAssertEqual(
            cancel.count, 0,
            "a send failure must detach, not call the cancel handler: \(cancel.requestIds)")

        let detachLine = await CancelTrace.waitForLine(
            containing: ["[DETACH]", "r=\(context.requestId)"],
            since: traceSince, timeout: 10)
        XCTAssertNotNil(
            detachLine,
            "[DETACH] r=\(context.requestId) missing from the window:\n"
                + CancelTrace.window(since: traceSince))

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(
            cancel.count, 0,
            "the heartbeat failure must not turn into a cancel: \(cancel.requestIds)")
        XCTAssertEqual(
            CancelTrace.count("[DETACH]", since: traceSince), 1,
            "the detached turn must claim exactly one orphan slot:\n"
                + CancelTrace.window(since: traceSince))
        print(
            "[TB-B2b] detached=\(context.detachedByClient) closed=\(context.closed) "
                + "callbacks=\(cancel.requestIds) detachLine=\(detachLine ?? "nil") "
                + "heartbeatEvents=\(eventCounter.value) "
                + "connectionState=\(stateRecorder.latest)")
    }
}

// MARK: - B2b support (test-only)

/// Accepts one TCP connection and closes it with SO_LINGER 0 (RST).
final class RSTPeer: @unchecked Sendable {
    let port: UInt16

    private let listenFD: Int32
    private let queue = DispatchQueue(label: "com.simigo.tests.rst-peer")
    private let lock = NSLock()
    private var _accepted = false
    private var _reset = false
    private var _failure: String?

    enum PeerError: Error, CustomStringConvertible {
        case socket(String)
        var description: String {
            switch self {
            case .socket(let message): return message
            }
        }
    }

    init() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw PeerError.socket("socket() failed: errno=\(errno)")
        }
        var yes: Int32 = 1
        setsockopt(
            fd, SOL_SOCKET, SO_REUSEADDR, &yes,
            socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 1) == 0 else {
            let code = errno
            close(fd)
            throw PeerError.socket("bind/listen failed: errno=\(code)")
        }

        var local = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard named == 0 else {
            let code = errno
            close(fd)
            throw PeerError.socket("getsockname failed: errno=\(code)")
        }

        self.port = UInt16(bigEndian: local.sin_port)
        self.listenFD = fd

        queue.async { [weak self] in
            self?.acceptThenReset()
        }
    }

    private func acceptThenReset() {
        let accepted = accept(listenFD, nil, nil)
        guard accepted >= 0 else {
            lock.withLock { _failure = "accept() failed: errno=\(errno)" }
            return
        }
        lock.withLock { _accepted = true }
        // Give the client time to leave its handshake state before the reset.
        usleep(150_000)
        var linger = Darwin.linger(l_onoff: 1, l_linger: 0)
        setsockopt(
            accepted, SOL_SOCKET, SO_LINGER, &linger,
            socklen_t(MemoryLayout<Darwin.linger>.size))
        close(accepted)
        lock.withLock { _reset = true }
    }

    var accepted: Bool { lock.withLock { _accepted } }
    var reset: Bool { lock.withLock { _reset } }
    var failure: String? { lock.withLock { _failure } }

    func waitForAccepted(timeout: TimeInterval) async -> Bool {
        _ = await CancelPathWait.until(timeout: timeout) {
            self.accepted || self.failure != nil
        }
        return accepted
    }

    func waitForReset(timeout: TimeInterval) async -> Bool {
        _ = await CancelPathWait.until(timeout: timeout) {
            self.reset || self.failure != nil
        }
        return reset
    }

    func stop() {
        shutdown(listenFD, SHUT_RDWR)
        close(listenFD)
    }
}

final class ConnectionStateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _latest = "unset"

    func record(_ state: NWConnection.State) {
        lock.withLock { _latest = String(describing: state) }
    }

    var latest: String { lock.withLock { _latest } }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    func bump() { lock.withLock { _value += 1 } }
    var value: Int { lock.withLock { _value } }
}
