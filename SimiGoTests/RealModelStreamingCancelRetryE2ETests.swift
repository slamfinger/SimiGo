import XCTest
import Foundation
import SimiGoRuntimeContract

@testable import SimiGo

/// 二.5 T-C（owner 2026-10-29 授权；2026-10-30 ADR 后退役）：真实模型、流式
/// Responses、断连后同会话同输入重试的取消—重试观察实验。
///
/// 2026-10-30 ADR 把客户端断连从「取消」改为「detach 跑完」，本套件的硬断言
/// （断连后恰一次 `[CANCEL]` + 一次 `cancelCommitSkip` + 重试是第 2 次进入
/// 引擎）只对 ADR 之前的二进制成立。默认跳过；仅当显式设置
/// `TC_MEASURE_CANCEL_SEMANTICS=1` 时才作为历史仪器运行。它的读数不用于
/// 关闭 #121/#93/#135/#136 中的任何一条。
///
/// 原硬断言只覆盖完整性（规格 §4.6）：取消轮不产生完成行/结算/answered demand；
/// 恰一次 `[CANCEL]` 与一次 `cancelCommitSkip`；重试确实进入引擎（第 2 条
/// `prefillStep`）并在完成后恰产生 1 条答案结算 + 绑定 + 摘要；可选第三次
/// 请求证明重试结果可复用。
///
/// 观察项（只记录，不做 PASS/FAIL、不设门限）：取消→回调、回调→放弃提交的
/// 墙钟；T4 之后是否还有 prefill 行；重试的 `reuse=`/`cacheHitTokens=`/
/// `cacheEff=`/`mode=`/`promptTokens=`；取消轮缺失的缓存读数标明「不可用」，
/// 不补造、不用重试读数替代；session key 是否一致仅记录（W3 #93 / G9 未裁定）。
final class RealModelStreamingCancelRetryE2ETests: XCTestCase {

    private let port = 18_242

    private var host: LOCALBAuthorizedE2E.Host!

    private var modelPath: String {
        if let override = ProcessInfo.processInfo.environment["CONTINUATION_MODEL_PATH"] {
            return override
        }
        let hub = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                ".cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots")
        let snapshots = (try? FileManager.default.contentsOfDirectory(
            at: hub, includingPropertiesForKeys: [.isDirectoryKey]))?
            .filter { $0.hasDirectoryPath } ?? []
        return snapshots.first?.path ?? hub.appendingPathComponent("NOT-PRESENT").path
    }

    // MARK: - Readings

    private struct CancelWindow {
        let traceSince: Int
        let cancelAt: Date
        let prefillLine: String
        let cancelLine: String
        let commitSkipLine: String
        let lines: [String]

        var cancelLatency: TimeInterval? {
            guard let cancelStamp = CancelTrace.timestamp(of: cancelLine) else { return nil }
            return cancelStamp.timeIntervalSince(cancelAt)
        }

        /// Upper bound for "the generation task gave up committing" — NOT the
        /// moment the compute stopped.
        var commitSkipLatency: TimeInterval? {
            guard let cancelStamp = CancelTrace.timestamp(of: cancelLine),
                  let skipStamp = CancelTrace.timestamp(of: commitSkipLine)
            else { return nil }
            return skipStamp.timeIntervalSince(cancelStamp)
        }

        var prefillAfterCancel: [String] {
            guard let cancelStamp = CancelTrace.timestamp(of: cancelLine) else { return [] }
            return lines.filter { line in
                guard line.contains("[MLX] prefill ") else { return false }
                guard let stamp = CancelTrace.timestamp(of: line) else { return false }
                return stamp > cancelStamp
            }
        }

        var completionLines: [String] {
            lines.filter { $0.contains("[MLX] session=") && $0.contains("rawEv=") }
        }
    }

    private func record(_ name: String, _ payload: [String: Any]) {
        let url = SimiGoPaths.logs.appendingPathComponent("tc-realmodel-\(name).json")
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: url)
        print("[TC] recorded \(url.path)")
    }

    private func makeLargePrompt() -> String {
        // ~20k tokens: enough that prefill prints several progress lines and
        // takes tens of seconds on the 30B model, while staying far below the
        // context budget.
        var sections: [String] = []
        for index in 0..<500 {
            sections.append(
                "Section \(index): the maintenance log records routine inspections, "
                    + "replaced parts, measured tolerances and the technician's notes "
                    + "for assembly line seven. No anomaly was reported in this entry.")
        }
        sections.append("Ignore every section above. Reply with exactly the single word: DONE")
        return sections.joined(separator: "\n")
    }

    private func responsesBody(session: String, input: String) -> [String: Any] {
        [
            "model": "tc-cancel-retry-e2e",
            "input": input,
            "session_id": session,
            "stream": true,
            "temperature": 0,
            "disable_thinking": true,
            "max_completion_tokens": 8,
        ]
    }

    // MARK: - The experiment

    func testStreamingCancelThenRetrySettlesOnceAndReuses() async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("local Qwen3-Coder not present: \(modelPath)")
        }
        _ = try CancelPathHarness.requireIsolatedRoots()
        guard ProcessInfo.processInfo.environment["TC_MEASURE_CANCEL_SEMANTICS"] == "1"
        else {
            record("cancel-semantics-retired", [
                "suite": "RealModelStreamingCancelRetryE2ETests",
                "note": "ADR 2026-10-30 turned client-disconnect cancel into "
                    + "detach; the cancel-phase instrument only applies to "
                    + "pre-ADR binaries",
                "gate": "TC_MEASURE_CANCEL_SEMANTICS != 1",
            ])
            throw XCTSkip(
                "T-C cancel phase retired by ADR 2026-10-30; set "
                    + "TC_MEASURE_CANCEL_SEMANTICS=1 only to replay the "
                    + "historical instrument against a pre-ADR binary")
        }
        XCTAssertTrue(
            HTTPServer.isAnswerReuseEnabled,
            "SIMIGO_IS_ANSWER_REUSE must stay unset/1: the reuse check would be "
                + "meaningless against a disabled gate")

        let runtime = NativeMLX(
            info: ModelInfo(path: modelPath, kind: .mlx), config: ModelConfig())
        host = try LOCALBAuthorizedE2E.makeHost()
        try await runtime.startWithLOCALB(
            ModelInfo(path: modelPath, kind: .mlx),
            port: port,
            localbTransportIdentity: host.identity,
            localbRequestAuthorization: (
                coordinator: host.coordinator,
                trustedCheckpoint: host.checkpointProvider
            )
        )
        defer { Task { await runtime.stop() } }

        let session = "tc-\(UUID().uuidString)"
        let input = makeLargePrompt()
        let before = await ESISSweep.stable()
        let traceSince = CancelTrace.size()

        // MARK: Request 1 — cancel mid-prefill

        let first = StreamingClient(host: host, port: port)
        try await first.start(
            path: "/v1/responses",
            body: responsesBody(session: session, input: input))
        XCTAssertEqual(first.status, 200, first.sse)
        let createdLine = await first.waitForLine(
            containing: ["\"type\":\"response.created\""], timeout: 60)
        XCTAssertNotNil(
            createdLine, "the SSE chain never started: \(first.sse)")

        // The disconnect time is proven by the prefill progress line, not
        // inferred from the client closing.
        let prefill = await CancelTrace.waitForLine(
            containing: ["[MLX] prefill "], since: traceSince, timeout: 300)
        let prefillLine = try XCTUnwrap(
            prefill,
            "no prefill progress line; cannot prove the engine entered real "
                + "prefill before the disconnect. window:\n"
                + CancelTrace.window(since: traceSince))
        let cancelAt = first.cancelReading()

        let cancelLineOptional = await CancelTrace.waitForLine(
            containing: ["[CANCEL] r="], since: traceSince, timeout: 120)
        let cancelLine = try XCTUnwrap(
            cancelLineOptional,
            "no [CANCEL] line after the disconnect:\n"
                + CancelTrace.window(since: traceSince))
        let fullRequestID = try XCTUnwrap(CancelTrace.token("r=", in: cancelLine))
        let shortRequestID = CancelTrace.shortID(ofRequestID: fullRequestID)
        let arrival = await CancelTrace.waitForLine(
            containing: ["[PROTOCOL] arrive", "r=\(shortRequestID)"],
            since: traceSince, timeout: 5)
        XCTAssertNotNil(
            arrival, "the cancelled request never arrived through the route")
        let commitSkip = await CancelTrace.waitForLine(
            containing: ["[MLX] cancelCommitSkip", "session="],
            since: traceSince, timeout: 600)
        let commitSkipLine = try XCTUnwrap(
            commitSkip,
            "the generation task never observed the cancellation before commit:\n"
                + CancelTrace.window(since: traceSince))

        let traceBeforeRetry = CancelTrace.size()
        let windowLines = CancelTrace.lines(since: traceSince, until: traceBeforeRetry)
        let window = CancelWindow(
            traceSince: traceSince, cancelAt: cancelAt,
            prefillLine: prefillLine, cancelLine: cancelLine,
            commitSkipLine: commitSkipLine, lines: windowLines)

        XCTAssertEqual(
            window.completionLines, [],
            "the cancelled turn produced a completion line: \(window.completionLines)")
        XCTAssertEqual(
            CancelTrace.count("[CANCEL] r=", since: traceSince, until: traceBeforeRetry), 1,
            "exactly one cancel callback for the cancelled turn")

        let afterCancel = await ESISSweep.stable()
        XCTAssertEqual(
            ESISSweep.newAnswerSettlementIDs(before: before, after: afterCancel), [],
            "the cancelled turn settled an answer")
        XCTAssertEqual(
            ESISSweep.added("execution_states", before: before, after: afterCancel), [],
            "the cancelled turn created an ES state")
        XCTAssertNil(
            ESISSweep.chatStateID(sessionID: session),
            "the cancelled turn linked the session to a state")
        let answeredAfterCancel = try await MainActor.run {
            try ESISSweep.answeredDemand(sessionID: session, query: input)
        }
        XCTAssertNil(
            answeredAfterCancel, "the cancelled turn registered an answered demand")

        // MARK: Request 2 — same session, same input: must generate and settle

        let retry = StreamingClient(host: host, port: port)
        try await retry.start(
            path: "/v1/responses",
            body: responsesBody(session: session, input: input))
        XCTAssertEqual(retry.status, 200, retry.sse)
        let retryCompleted = await retry.waitForLine(
            containing: ["\"type\":\"response.completed\""], timeout: 900)
        let retryCompletedLine = try XCTUnwrap(
            retryCompleted, "the retry never completed: \(retry.sse)")
        let retryFinished = await retry.waitForFinished(timeout: 30)
        XCTAssertTrue(retryFinished, retry.sse)
        let retryEvent = try XCTUnwrap(
            StreamingClient.jsonObject(from: retryCompletedLine))
        let retryResponse = try XCTUnwrap(retryEvent["response"] as? [String: Any])
        XCTAssertEqual(retryResponse["status"] as? String, "completed", retry.sse)
        XCTAssertNil(
            retryResponse["simigo"],
            "the retry must be a generation, not a reuse: \(retry.sse)")

        let afterRetry = await ESISSweep.stable()
        let retrySettlements = ESISSweep.newAnswerSettlementIDs(
            before: afterCancel, after: afterRetry)
        XCTAssertEqual(
            retrySettlements.count, 1,
            "the retry settles exactly one answer: \(retrySettlements)")
        let settlementID = try XCTUnwrap(retrySettlements.first)
        let bindings = try await MainActor.run {
            try ESISSweep.bindings(settlementID: settlementID)
        }
        XCTAssertFalse(
            bindings.isEmpty, "the retry settlement carries its bindings")
        let summary = try await MainActor.run {
            try ESISSweep.summary(settlementID: settlementID)
        }
        XCTAssertNotNil(summary, "the retry settlement carries its summary")
        let answeredOptional = try await MainActor.run {
            try ESISSweep.answeredDemand(sessionID: session, query: input)
        }
        let answered = try XCTUnwrap(
            answeredOptional, "the retry completion must be an answered demand")
        XCTAssertEqual(answered.answerSettlementID, settlementID)
        XCTAssertEqual(
            ESISSweep.newChatStateIDs(before: afterCancel, after: afterRetry).count, 1,
            "the retried turn creates exactly one chat-* state")

        let retryWindow = CancelTrace.lines(since: traceBeforeRetry)
        let prefillSteps = CancelTrace.count("[MLX] prefillStep=", since: traceSince)
        XCTAssertEqual(
            prefillSteps, 2,
            "exactly two engine entries (cancel + retry): \(prefillSteps)")
        XCTAssertFalse(
            retryWindow.filter { $0.contains("[MLX] prefillStep=") }.isEmpty,
            "the retry entered the engine instead of being served as reuse")

        // MARK: Request 3 (optional) — the retried answer is reusable

        let third = StreamingClient(host: host, port: port)
        try await third.start(
            path: "/v1/responses",
            body: responsesBody(session: session, input: input))
        XCTAssertEqual(third.status, 200, third.sse)
        let thirdCompleted = await third.waitForLine(
            containing: ["\"type\":\"response.completed\""], timeout: 120)
        let thirdCompletedLine = try XCTUnwrap(
            thirdCompleted, "the reuse turn never completed: \(third.sse)")
        let thirdFinished = await third.waitForFinished(timeout: 30)
        XCTAssertTrue(thirdFinished, third.sse)
        let thirdEvent = try XCTUnwrap(
            StreamingClient.jsonObject(from: thirdCompletedLine))
        let thirdResponse = try XCTUnwrap(thirdEvent["response"] as? [String: Any])
        let reuseBlock = try XCTUnwrap(
            thirdResponse["simigo"] as? [String: Any],
            "the retried answer was not reusable: \(third.sse)")
        XCTAssertEqual(reuseBlock["answer_reuse"] as? Bool, true)
        XCTAssertEqual(reuseBlock["model_calls"] as? Int, 0)
        XCTAssertEqual(reuseBlock["settlement_id"] as? String, settlementID)
        XCTAssertEqual(
            CancelTrace.count("[MLX] prefillStep=", since: traceSince), 2,
            "the reuse turn must not enter the engine")

        let afterReuse = await ESISSweep.stable()
        XCTAssertEqual(
            ESISSweep.newAnswerSettlementIDs(before: afterRetry, after: afterReuse), [],
            "serving the reuse settles nothing")

        // MARK: Observational readings (recorded, no thresholds)

        let retryCompletionLine = retryWindow.last {
            $0.contains("[MLX] session=") && $0.contains("rawEv=")
        } ?? "absent"
        let cancelSessionKey = CancelTrace.token("session=", in: commitSkipLine) ?? "absent"
        let retrySessionKey = CancelTrace.token("session=", in: retryCompletionLine)
            ?? "absent"
        let retryPrefillStep = retryWindow.last { $0.contains("[MLX] prefillStep=") }
            ?? "absent"
        let prefillAfterCancel = window.prefillAfterCancel
        print(
            "[TC] cancelLatency=\(window.cancelLatency.map { String($0) } ?? "unavailable") "
                + "commitSkipLatencyUpperBound="
                + "\(window.commitSkipLatency.map { String($0) } ?? "unavailable") "
                + "prefillLinesAfterCancel=\(prefillAfterCancel.count)")
        print(
            "[TC] cancel=cancelCommitSkip session="
                + "\(cancelSessionKey == retrySessionKey ? "same" : "different")"
                + " (\(cancelSessionKey) vs \(retrySessionKey))")
        print("[TC] retryCompletion=\(retryCompletionLine)")
        print("[TC] retryPrefillStep=\(retryPrefillStep)")
        if window.completionLines.isEmpty {
            print(
                "[TC] cancelled turn cache readings: unavailable "
                    + "(no engine info event; NOT substituted with the retry's)")
        }

        record("cancel-retry", [
            "session": session,
            "modelPath": modelPath,
            "port": port,
            "promptCharacters": input.count,
            "cancelAtEpoch": cancelAt.timeIntervalSince1970,
            "prefillLine": prefillLine,
            "cancelLine": cancelLine,
            "cancelLatencySeconds": window.cancelLatency.map { $0 as Any } ?? "unavailable",
            "commitSkipLine": commitSkipLine,
            "commitSkipLatencyUpperBoundSeconds":
                window.commitSkipLatency.map { $0 as Any } ?? "unavailable",
            "prefillLinesAfterCancel": prefillAfterCancel,
            "cancelledTurnCacheReadings": "unavailable",
            "cancelledTurnCompletionLines": window.completionLines,
            "retryCompletionLine": retryCompletionLine,
            "retryPrefillStepLine": retryPrefillStep,
            "cancelSessionKey": cancelSessionKey,
            "retrySessionKey": retrySessionKey,
            "sessionKeyEqual": cancelSessionKey == retrySessionKey,
            "prefillStepCount": CancelTrace.count("[MLX] prefillStep=", since: traceSince),
            "settlementID": settlementID,
            "demandID": answered.demandID,
            "reuseBlock": reuseBlock,
            "ledgerBefore": before.counts,
            "ledgerAfterCancel": afterCancel.counts,
            "ledgerAfterRetry": afterRetry.counts,
            "ledgerAfterReuse": afterReuse.counts,
            "traceWindow": windowLines + retryWindow,
        ])
    }
}
