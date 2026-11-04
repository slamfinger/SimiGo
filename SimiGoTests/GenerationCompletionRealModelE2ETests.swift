import XCTest
import Foundation
import SimiGoRuntimeContract
@testable import SimiGo

/// T-1 end-to-end gate on the REAL model over the product Responses entry point
/// (owner ruling 2026-10-28, option 「新增真实模型定向测类」).
///
/// This is not an HTTP-shape test: the truncation is produced by the engine
/// itself, through the token-budget channel the implementation actually honours
/// (`max_completion_tokens` -> `ModelConfig.maxTokens` -> `GenerateParameters`),
/// and the verdict is read off the engine's own termination line
/// (`stop=` / `genTokens=` / `maxTokens=`) plus the store's settlement rows.
/// `max_output_tokens` is only the wire's *reporting* code and is never sent.
///
/// The two opposite readings required by the ruling:
///  A) budget exhausted -> engine says `capped`; the wire says `incomplete`;
///     NO settlement and NO advancement is written; an exact repeat generates
///     again instead of serving the half answer. A positive control (a natural
///     completion in the same session, then its repeat) runs inside the SAME
///     test so the negative result cannot be manufactured by switching reuse
///     off.
///  B) natural end -> engine says `complete`; the turn settles; the exact
///     repeat is served from the settlement with zero model calls, still with
///     reuse enabled.
///
/// Guarded by model presence: absent local weights means XCTSkip, so no stub or
/// fixture can ever stand in for these readings.
final class GenerationCompletionRealModelE2ETests: XCTestCase {
    private let cappedPort = 18_481
    private let completePort = 18_482
    private var host: LOCALBAuthorizedE2E.Host!

    /// Per-request token budgets: small enough that the greedy engine runs out
    /// of budget on an enumeration prompt, generous enough that a one-word
    /// answer reaches EOS long before the cap.
    private let cappedBudget = 12
    private let completeBudget = 64
    private let cappedQuery =
        "List 200 English synonyms for the word compute, numbered one per line."
    private let controlQuery = "Reply with exactly the single word: READY"

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

    // MARK: - instruments

    private var traceURL: URL {
        SimiGoPaths.logs.appendingPathComponent("native_mlx_trace.log")
    }

    private func traceSize() -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: traceURL.path)
        return attributes?[.size] as? Int ?? 0
    }

    /// The trace lines appended after `offset`, polled until one of `markers`
    /// shows up. The trace logger is a serial async queue, so after a marker
    /// lands one more short read picks up the settle/reuse lines queued behind it.
    private func traceWindow(
        since offset: Int, waitingFor markers: [String], timeout: TimeInterval = 20
    ) -> [String] {
        func read() -> [String] {
            guard let data = try? Data(contentsOf: traceURL), data.count > offset else {
                return []
            }
            return String(decoding: data.suffix(data.count - offset), as: UTF8.self)
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map(String.init)
        }
        let deadline = Date().addingTimeInterval(timeout)
        var window = read()
        while Date() < deadline {
            if window.contains(where: { line in markers.contains(where: line.contains) }) {
                Thread.sleep(forTimeInterval: 0.6)
                return read()
            }
            Thread.sleep(forTimeInterval: 0.2)
            window = read()
        }
        return window
    }

    private func value(_ marker: String, in line: String) -> String? {
        guard let range = line.range(of: marker) else { return nil }
        var token = String(line[range.upperBound...].prefix { !$0.isWhitespace })
        // The engine line interpolates the optional it holds, so a capped
        // budget prints as `maxTokens=Optional(12)`.
        if token.hasPrefix("Optional("), token.hasSuffix(")") {
            token = String(token.dropFirst("Optional(".count).dropLast())
        }
        return token
    }

    private struct Ledger {
        let states: Int
        let answerSettlements: Int
        let demands: Int
        let advancements: Int
        let chatRows: Int
        let reuseEvents: Int
    }

    @MainActor
    private func ledger() throws -> Ledger {
        let db = try XCTUnwrap(ExecutionStateGraphStore().esis)
        return Ledger(
            states: try db.count("execution_states"),
            answerSettlements: try db.readSettlementReceipts().count,
            demands: try db.count("information_demands"),
            advancements: try db.count("information_advancements"),
            chatRows: try db.count("chat_messages"),
            reuseEvents: try db.count("information_reuse_events"))
    }

    @MainActor
    private func answered(_ session: String, _ query: String) throws ->
        SimiGoESISDatabase.AnsweredDemand? {
        let db = try XCTUnwrap(ExecutionStateGraphStore().esis)
        return try db.answeredDemand(sessionID: session, query: query)
    }

    // MARK: - runtime + wire

    private struct Outcome {
        let status: Int
        let json: [String: Any]
        let raw: String
        let window: [String]
        var simigo: [String: Any]? { json["simigo"] as? [String: Any] }
        var responseStatus: String? { json["status"] as? String }
        var engineLine: String? {
            window.last { $0.contains("[MLX] session=") && $0.contains("maxTokens=") }
        }
        var servedText: String? {
            guard let output = json["output"] as? [[String: Any]],
                  let content = output.first?["content"] as? [[String: Any]] else { return nil }
            return content.first?["text"] as? String
        }
    }

    private func startRuntime(port: Int) async throws -> NativeMLX {
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
        return runtime
    }

    /// One signed Responses turn. `body` carries only fields the product reads:
    /// the budget rides on `max_completion_tokens`, never on `max_output_tokens`.
    private func turn(
        session: String, query: String, maxTokens: Int, waitFor markers: [String]
    ) async throws -> Outcome {
        let offset = traceSize()
        let body = try JSONSerialization.data(withJSONObject: [
            "model": "t1-completion-e2e",
            "input": query,
            "session_id": session,
            "stream": false,
            "temperature": 0,
            "disable_thinking": true,
            "max_completion_tokens": maxTokens,
        ])
        let (data, response) = try await LOCALBAuthorizedE2E.send(
            host: host, port: activePort, method: "POST",
            path: "/v1/responses", contentType: "application/json", body: body)
        let raw = String(decoding: data, as: UTF8.self)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return Outcome(
            status: response.statusCode, json: json, raw: raw,
            window: traceWindow(since: offset, waitingFor: markers))
    }

    private var activePort = 18_481

    /// Raw readings stay in the run root (SIMIGO_HOME relocates `SimiGoPaths.logs`)
    /// so the archive holds the response bytes, not only the assertion outcomes.
    private func record(_ name: String, _ payload: [String: Any]) {
        let url = SimiGoPaths.logs.appendingPathComponent("t1-realmodel-\(name).json")
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: url)
    }

    // MARK: - A) budget exhausted

    /// Ruling row 1: the cap is recognised as truncation, the response is
    /// incomplete, no reusable settlement exists, and a repeat cannot hit the
    /// half answer — while reuse itself is proven live by the control pair.
    func testBudgetCappedTurnSettlesNothingAndIsNotReusable() async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("local Qwen3-Coder not present: \(modelPath)")
        }
        XCTAssertTrue(
            HTTPServer.isAnswerReuseEnabled,
            "the off-switch would make the negative result meaningless: "
                + "SIMIGO_IS_ANSWER_REUSE must stay unset/1 for this gate")

        activePort = cappedPort
        let runtime = try await startRuntime(port: cappedPort)
        defer { Task { await runtime.stop() } }

        let session = "t1-capped-\(UUID().uuidString)"
        let before = try await MainActor.run { try ledger() }

        let capped = try await turn(
            session: session, query: cappedQuery, maxTokens: cappedBudget,
            waitFor: ["maxTokens=", "[SETTLE_SKIP]"])
        XCTAssertEqual(capped.status, 200, capped.raw)

        // ① the engine itself says the budget ran out, at the requested cap.
        let engineLine = try XCTUnwrap(capped.engineLine, "no completion line: \(capped.raw)")
        XCTAssertEqual(value("stop=", in: engineLine), "capped", engineLine)
        XCTAssertEqual(
            value("maxTokens=", in: engineLine), String(cappedBudget),
            "the per-request token budget must reach the engine: \(engineLine)")
        let cappedTokens = Int(try XCTUnwrap(
            value("genTokens=", in: engineLine), "genTokens missing: \(engineLine)")) ?? -1
        XCTAssertGreaterThanOrEqual(
            cappedTokens, cappedBudget,
            "the vendor only reports .length once the budget is spent: \(engineLine)")

        // ② the wire reports the turn as incomplete, with the reason.
        XCTAssertEqual(capped.responseStatus, "incomplete", capped.raw)
        let incompleteDetails = try XCTUnwrap(
            capped.json["incomplete_details"] as? [String: Any], capped.raw)
        XCTAssertEqual(incompleteDetails["reason"] as? String, "max_output_tokens", capped.raw)

        // ③ no settlement, no advancement — the fail-closed skip is recorded.
        XCTAssertTrue(
            capped.window.contains { $0.contains("[SETTLE_SKIP] wire=responses completion=capped") },
            "no [SETTLE_SKIP] in window:\n\(capped.window.joined(separator: "\n"))")
        let afterCapped = try await MainActor.run { try ledger() }
        XCTAssertEqual(afterCapped.answerSettlements, before.answerSettlements,
                       "a capped turn must write no answer settlement")
        XCTAssertEqual(afterCapped.advancements, before.advancements,
                       "a capped turn must advance no demand")
        XCTAssertGreaterThan(afterCapped.demands, before.demands,
                             "the turn did enter the IS path, so the checks below are not vacuous")
        let answeredCapped = try await MainActor.run {
            try answered(session, cappedQuery) != nil
        }
        XCTAssertFalse(answeredCapped, "the half answer must not be an answered demand")

        // ④ the exact repeat re-generates instead of serving the incomplete text.
        let repeatCapped = try await turn(
            session: session, query: cappedQuery, maxTokens: cappedBudget,
            waitFor: ["maxTokens=", "[IS_REUSE]"])
        XCTAssertEqual(repeatCapped.status, 200, repeatCapped.raw)
        XCTAssertNil(repeatCapped.simigo, "an incomplete result must never be served as reuse")
        XCTAssertNotNil(repeatCapped.engineLine, "the repeat must run the model again")
        XCTAssertFalse(
            repeatCapped.window.contains { $0.contains("[IS_REUSE]") },
            "no reuse line may accompany the repeat: \(repeatCapped.window)")
        let afterRepeat = try await MainActor.run { try ledger() }
        XCTAssertEqual(afterRepeat.answerSettlements, afterCapped.answerSettlements,
                       "the repeat of a capped turn still settles nothing")

        // Positive control in the SAME process, store and session: reuse works.
        let control = try await turn(
            session: session, query: controlQuery, maxTokens: completeBudget,
            waitFor: ["maxTokens=", "[SETTLE_SKIP]"])
        XCTAssertEqual(control.status, 200, control.raw)
        let controlLine = try XCTUnwrap(control.engineLine, control.raw)
        XCTAssertEqual(value("stop=", in: controlLine), "complete", controlLine)
        XCTAssertEqual(control.responseStatus, "completed", control.raw)
        let afterControl = try await MainActor.run { try ledger() }
        XCTAssertEqual(afterControl.answerSettlements, afterRepeat.answerSettlements + 1,
                       "the natural turn settles exactly one answer")

        let controlRepeat = try await turn(
            session: session, query: controlQuery, maxTokens: completeBudget,
            waitFor: ["[IS_REUSE]"])
        XCTAssertEqual(controlRepeat.simigo?["answer_reuse"] as? Bool, true,
                       "the gate is live in this run: \(controlRepeat.raw)")
        XCTAssertNil(controlRepeat.engineLine,
                     "the control reuse must not call the model: \(controlRepeat.window)")

        // And the capped query is STILL unreachable after the gate proved itself.
        let cappedRepeatAgain = try await turn(
            session: session, query: cappedQuery, maxTokens: cappedBudget,
            waitFor: ["maxTokens=", "[IS_REUSE]"])
        XCTAssertNil(cappedRepeatAgain.simigo,
                     "reuse is live, yet the incomplete result stays unmatched")
        XCTAssertNil(cappedRepeatAgain.window.first { $0.contains("[IS_REUSE]") })

        record("capped", [
            "session": session,
            "modelPath": modelPath,
            "budget": cappedBudget,
            "cappedResponse": capped.raw,
            "cappedEngineLine": engineLine,
            "repeatResponse": repeatCapped.raw,
            "repeatEngineLine": repeatCapped.engineLine ?? "none",
            "controlResponse": control.raw,
            "controlRepeat": controlRepeat.raw,
            "traceWindow": capped.window + repeatCapped.window + control.window
                + controlRepeat.window,
            "ledgerBefore": before.answerSettlements,
            "ledgerAfterCapped": afterCapped.answerSettlements,
            "ledgerAfterRepeat": afterRepeat.answerSettlements,
            "ledgerAfterControl": afterControl.answerSettlements,
            "demandsBefore": before.demands,
            "advancementsBefore": before.advancements,
            "advancementsAfter": afterControl.advancements,
        ])
    }

    // MARK: - B) natural completion

    /// Ruling row 2: a natural end is recognised as complete, settles, and the
    /// exact repeat is served from that settlement with zero model calls.
    func testNaturallyCompletedTurnSettlesAndReusesWithoutModelCall() async throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("local Qwen3-Coder not present: \(modelPath)")
        }
        XCTAssertTrue(
            HTTPServer.isAnswerReuseEnabled,
            "the reuse reading must come from the live gate, not from a disabled one")

        activePort = completePort
        let runtime = try await startRuntime(port: completePort)
        defer { Task { await runtime.stop() } }

        let session = "t1-complete-\(UUID().uuidString)"
        let query = "Reply with exactly the single word: OK"
        let before = try await MainActor.run { try ledger() }

        let first = try await turn(
            session: session, query: query, maxTokens: completeBudget,
            waitFor: ["maxTokens=", "[SETTLE_SKIP]"])
        XCTAssertEqual(first.status, 200, first.raw)

        let engineLine = try XCTUnwrap(first.engineLine, "no completion line: \(first.raw)")
        XCTAssertEqual(value("stop=", in: engineLine), "complete", engineLine)
        XCTAssertEqual(value("maxTokens=", in: engineLine), String(completeBudget), engineLine)
        let generatedTokens = Int(try XCTUnwrap(
            value("genTokens=", in: engineLine), "genTokens missing: \(engineLine)")) ?? -1
        XCTAssertGreaterThan(generatedTokens, 0, engineLine)
        XCTAssertLessThan(
            generatedTokens, completeBudget,
            "a natural end stops inside the budget, which is what separates it from a cap: "
                + engineLine)
        XCTAssertFalse(
            first.window.contains { $0.contains("[SETTLE_SKIP]") },
            "a complete turn is not skipped: \(first.window)")
        XCTAssertEqual(first.responseStatus, "completed", first.raw)
        XCTAssertNil(first.simigo, "a generated turn is not a reuse")
        XCTAssertNotNil(first.json["incomplete_details"] as? NSNull, first.raw)

        let afterFirst = try await MainActor.run { try ledger() }
        XCTAssertEqual(afterFirst.answerSettlements, before.answerSettlements + 1,
                       "the settled turn publishes one answer settlement")
        XCTAssertGreaterThan(afterFirst.advancements, before.advancements,
                             "the demand is advanced by the settled answer")
        let maybeAnswer = try await MainActor.run { try answered(session, query) }
        let answer = try XCTUnwrap(
            maybeAnswer, "the completed turn must be an answered demand")

        let repeatTurn = try await turn(
            session: session, query: query, maxTokens: completeBudget,
            waitFor: ["[IS_REUSE]"])
        XCTAssertEqual(repeatTurn.status, 200, repeatTurn.raw)
        let block = try XCTUnwrap(repeatTurn.simigo, "reuse block missing: \(repeatTurn.raw)")
        XCTAssertEqual(block["answer_reuse"] as? Bool, true, repeatTurn.raw)
        XCTAssertEqual(block["model_calls"] as? Int, 0, repeatTurn.raw)
        XCTAssertEqual(block["settlement_id"] as? String, answer.answerSettlementID,
                       "the served answer is the settlement this turn produced")
        XCTAssertEqual(block["demand_id"] as? String, answer.demandID, repeatTurn.raw)
        XCTAssertEqual(repeatTurn.responseStatus, "completed", repeatTurn.raw)
        XCTAssertEqual(repeatTurn.servedText, first.servedText,
                       "the repeat serves the settled text")
        XCTAssertNil(repeatTurn.engineLine,
                     "the reuse must not run the model: \(repeatTurn.window)")
        XCTAssertTrue(
            repeatTurn.window.contains { $0.contains("[IS_REUSE]") && $0.contains("model_calls=0") },
            "zero-call evidence line: \(repeatTurn.window)")

        let afterRepeat = try await MainActor.run { try ledger() }
        XCTAssertEqual(afterRepeat.answerSettlements, afterFirst.answerSettlements,
                       "serving a reused answer writes no settlement")
        XCTAssertEqual(afterRepeat.states, afterFirst.states,
                       "serving a reused answer creates no ES state")

        record("complete", [
            "session": session,
            "modelPath": modelPath,
            "budget": completeBudget,
            "firstResponse": first.raw,
            "engineLine": engineLine,
            "repeatResponse": repeatTurn.raw,
            "traceWindow": first.window + repeatTurn.window,
            "settlementID": answer.answerSettlementID,
            "demandID": answer.demandID,
            "sourceStateID": answer.stateID,
            "generatedTokens": generatedTokens,
            "ledgerBefore": before.answerSettlements,
            "ledgerAfterFirst": afterFirst.answerSettlements,
            "ledgerAfterRepeat": afterRepeat.answerSettlements,
            "demandsBefore": before.demands,
            "demandsAfterRepeat": afterRepeat.demands,
            "advancementsBefore": before.advancements,
            "advancementsAfterRepeat": afterRepeat.advancements,
        ])
    }
}
