import Foundation
import SQLite3
import XCTest

@testable import SimiGoRuntimeContract

/// ④语义不限制 opt-in ＋ ⑤风险提示面（owner 裁定 A7195E7A）。
///
/// 分层：结算结果自身密封对象的完整性（行存在/非 MIGRATED_LEGACY、payload digest
/// 匹配、值非空）永远 fail-closed，显式接受也不能绕过；新鲜度/谱系门（自身 validity、
/// 上游闭包成员 invalid 或 missing）在显式 acceptInvalidated 下转为风险提示并放行，
/// 默认 false 全照旧拒绝（#236 零回归）。失效只翻 validity，从不删除结果或拓扑边，
/// 因此历史查询永远可答（⑤读取面 settlementRiskReport）。
///
/// 全部跑在隔离临时 SQLite 上，无模型/Keychain/GUI/共享用户状态。
final class SettlementRiskAcceptanceTests: XCTestCase {

    private static let referenceContract =
        #"{"schema_version":"simigo.result-contract/v1","fields":{"content":{"pattern":"^RESULT=(.+)$","capture_group":1,"type":"string","normalize":"trim","nonempty":true}},"constraints":[{"kind":"equals_binding","field":"content","binding":"next_input"}]}"#
    private static let deltaContract =
        #"{"schema_version":"simigo.result-contract/v1","fields":{"delta":{"pattern":"^RESULT=(.+)$","capture_group":1,"type":"string","normalize":"trim","nonempty":true}},"constraints":[{"kind":"equals_binding","field":"delta","binding":"next_input"}]}"#

    private let producer = SettlementIdentityBinding.Identity(
        model: "risk-model", tokenizer: "risk-tokenizer")

    // MARK: - Admission harness

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-risk-\(UUID().uuidString)-\(name).sqlite3")
    }
    private func cleanup(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }
    private func open(_ name: String) throws -> (URL, ESISDatabase) {
        let url = tempURL(name)
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        return (url, db)
    }

    private func executeSQL(_ url: URL, _ sql: String) throws {
        var handle: OpaquePointer?
        let openCode = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil)
        guard openCode == SQLITE_OK, let handle else {
            throw NSError(domain: "SettlementRiskAcceptanceTests.SQLite",
                          code: Int(openCode))
        }
        defer { sqlite3_close(handle) }
        let code = sqlite3_exec(handle, sql, nil, nil, nil)
        guard code == SQLITE_OK else {
            throw NSError(domain: "SettlementRiskAcceptanceTests.SQLite",
                          code: Int(code))
        }
    }

    @discardableResult
    private func mkSettlement(
        _ db: ESISDatabase, stateID: String, value: String,
        contract: String = SettlementRiskAcceptanceTests.referenceContract
    ) throws -> String {
        try db.recordExecutionState(
            id: stateID, parentID: nil, modelIdentity: "m", position: 1,
            continuationID: "C", anchor: "a", lifecycle: "active", createdAt: Date())
        let settled = try SettlementAuthority.authorize(
            generatedText: "RESULT=\(value)", contractJSON: Data(contract.utf8),
            verifiedBindings: ["next_input": .string(value)])
        let sid = try db.recordNativeSettlement(settled, stateID: stateID)
        try db.recordIdentityBindings(settlementID: sid, identity: producer)
        return sid
    }

    /// Bind a settlement to a source file and invalidate it by a revision change.
    private func invalidateViaSource(
        _ db: ESISDatabase, settlementID: String, file: String
    ) throws {
        try db.indexExternalFile(rootID: "work", relativePath: file, kind: "md",
                                 size: 4, modifiedAt: nil, contentDigest: "d1")
        try db.linkSettlementToExternalFile(settlementID: settlementID, binding: "content",
                                            rootID: "work", relativePath: file)
        _ = try db.reindexExternalFile(rootID: "work", relativePath: file, kind: "md",
                                       size: 5, modifiedAt: nil, contentDigest: "d2")
        _ = try db.invalidateSourceFile(rootID: "work", relativePath: file)
    }

    private func expectRefusal<T>(
        _ body: () throws -> T, _ matcher: (ISAdmission.Refusal) -> Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        do {
            _ = try body()
            XCTFail("expected admission refusal, but it succeeded", file: file, line: line)
        } catch let refusal as ISAdmission.Refusal {
            XCTAssertTrue(matcher(refusal), "unexpected refusal: \(refusal)", file: file, line: line)
        } catch {
            XCTFail("expected Refusal, got \(error)", file: file, line: line)
        }
    }

    // MARK: - ④ opt-in freshness gates (admission)

    func testOptInAdmitInvalidatedProceedsWithNotice() throws {
        let (url, db) = try open("inv")
        defer { db.close(); cleanup(url) }
        let sid = try mkSettlement(db, stateID: "S-inv", value: "hello")
        try invalidateViaSource(db, settlementID: sid, file: "src.md")
        XCTAssertEqual(try db.settlementValidity(sid), "invalid")

        // 默认仍拒（#236 零回归）。
        expectRefusal(
            { try ISAdmission.admit(db: db, stateID: "S-inv", consumer: producer) },
            { if case .invalidated(let s) = $0 { return s == sid }; return false })

        // 显式接受 → 放行＋提示，值仍是密封的原值。
        let admitted = try ISAdmission.admit(
            db: db, stateID: "S-inv", consumer: producer, acceptInvalidated: true)
        XCTAssertEqual(admitted.recoveredValue, "hello")
        XCTAssertEqual(admitted.riskNotices.count, 1)
        XCTAssertEqual(admitted.riskNotices.first?.code, SettlementRiskNotice.invalidated)
        XCTAssertEqual(admitted.riskNotices.first?.settlementID, sid)
        XCTAssertEqual(admitted.riskNotices.first?.detail, "source-file:work/src.md")
    }

    func testOptInAdmitMissingDependencyProceedsWithNotice() throws {
        let (url, db) = try open("depmissing")
        defer { db.close(); cleanup(url) }
        let sid = try mkSettlement(db, stateID: "S-child", value: "hello")
        try db.addDependency(fromSettlement: sid, toSettlement: "GHOST")

        expectRefusal(
            { try ISAdmission.admit(db: db, stateID: "S-child", consumer: producer) },
            { if case .dependencyMissing(let s, let d) = $0 { return s == sid && d == "GHOST" }; return false })

        // 上游对象误删不能否定本结算自身密封结果的正确性 → 风险，可接受。
        let admitted = try ISAdmission.admit(
            db: db, stateID: "S-child", consumer: producer, acceptInvalidated: true)
        XCTAssertEqual(admitted.recoveredValue, "hello")
        XCTAssertEqual(admitted.riskNotices.count, 1)
        XCTAssertEqual(admitted.riskNotices.first?.code, SettlementRiskNotice.upstreamMissing)
        XCTAssertEqual(admitted.riskNotices.first?.settlementID, "GHOST")
    }

    func testOptInAdmitInvalidDependencyProceedsWithNotice() throws {
        let (url, db) = try open("depinvalid")
        defer { db.close(); cleanup(url) }
        let sa = try mkSettlement(db, stateID: "S-A", value: "a")
        try invalidateViaSource(db, settlementID: sa, file: "a.md")
        // 子结算在上游失效之后新建：真实依赖边的级联只作用于已存在的下游，
        // 因此 sb 自身仍 valid，而它的上游 sa 已 invalid（dependencyInvalid 门）。
        let sb = try mkSettlement(db, stateID: "S-B", value: "b")
        try db.addDependency(fromSettlement: sb, toSettlement: sa)
        XCTAssertEqual(try db.settlementValidity(sa), "invalid")
        XCTAssertEqual(try db.settlementValidity(sb), "valid")

        expectRefusal(
            { try ISAdmission.admit(db: db, stateID: "S-B", consumer: producer) },
            { if case .dependencyInvalid(let s, let d) = $0 { return s == sb && d == sa }; return false })

        let admitted = try ISAdmission.admit(
            db: db, stateID: "S-B", consumer: producer, acceptInvalidated: true)
        XCTAssertEqual(admitted.recoveredValue, "b")
        XCTAssertEqual(admitted.riskNotices.count, 1)
        XCTAssertEqual(admitted.riskNotices.first?.code, SettlementRiskNotice.upstreamInvalidated)
        XCTAssertEqual(admitted.riskNotices.first?.settlementID, sa)
    }

    // MARK: - Integrity gates stay hard-refuse under opt-in

    func testIntegrityTamperRefusedEvenUnderOptIn() throws {
        let (url, db) = try open("tamper")
        defer { db.close(); cleanup(url) }
        try db.recordExecutionState(id: "S-t", parentID: nil, modelIdentity: "m",
                                    position: 1, continuationID: "C", anchor: "a",
                                    lifecycle: "active", createdAt: Date())
        let good = try SettlementAuthority.authorize(
            generatedText: "RESULT=hello", contractJSON: Data(Self.referenceContract.utf8),
            verifiedBindings: ["next_input": .string("hello")])
        let tampered = SettlementAuthority.SettledResult(
            schemaVersion: good.schemaVersion, contractID: good.contractID,
            contractDigest: good.contractDigest, validatedPayload: good.validatedPayload,
            payloadDigest: String(repeating: "0", count: 64),
            trace: good.trace, settledAt: good.settledAt)
        let sid = try db.recordNativeSettlement(tampered, stateID: "S-t")
        try db.recordIdentityBindings(settlementID: sid, identity: producer)

        expectRefusal(
            { try ISAdmission.admit(db: db, stateID: "S-t", consumer: producer, acceptInvalidated: true) },
            { if case .digestMismatch(let s) = $0 { return s == sid }; return false })
    }

    func testIntegrityEmptyValueRefusedEvenUnderOptIn() throws {
        let (url, db) = try open("empty")
        defer { db.close(); cleanup(url) }
        try mkSettlement(db, stateID: "S-e", value: "x", contract: Self.deltaContract)
        expectRefusal(
            { try ISAdmission.admit(db: db, stateID: "S-e", consumer: producer, acceptInvalidated: true) },
            { if case .emptyValue = $0 { return true }; return false })
    }

    // MARK: - Continuation edge opt-in

    func testSettleContinuationOptInAgainstInvalidatedParent() throws {
        let (url, db) = try open("cont")
        defer { db.close(); cleanup(url) }
        let parent = try mkSettlement(db, stateID: "P", value: "hello")
        try invalidateViaSource(db, settlementID: parent, file: "p.md")

        // 默认：父失效 → 子结算拒，且不落库。
        XCTAssertThrowsError(try ISAdmission.settleContinuation(
            db: db, parentStateID: "P", consumer: producer, childStateID: "C",
            generatedText: "RESULT=hello", contractJSON: Data(Self.referenceContract.utf8)))
        XCTAssertNil(try db.latestSettlementID(forStateID: "C"))

        // 显式接受：子结算可成，admission 带提示，子结算落库且可再准入。
        let done = try ISAdmission.settleContinuation(
            db: db, parentStateID: "P", consumer: producer, childStateID: "C",
            generatedText: "RESULT=hello", contractJSON: Data(Self.referenceContract.utf8),
            acceptInvalidatedDependency: true)
        XCTAssertEqual(done.admission.recoveredValue, "hello")
        XCTAssertEqual(done.admission.riskNotices.first?.code, SettlementRiskNotice.invalidated)
        XCTAssertEqual(try db.latestSettlementID(forStateID: "C"), done.settlementID)
    }

    // MARK: - ⑤ read-only risk report

    func testRiskReportReturnsPreservedValueAndNotices() throws {
        let (url, db) = try open("report")
        defer { db.close(); cleanup(url) }
        let sid = try mkSettlement(db, stateID: "S-r", value: "hello")
        let settlementsBefore = try db.count("settlements")
        try invalidateViaSource(db, settlementID: sid, file: "r.md")

        let report = try db.settlementRiskReport(settlementID: sid)
        XCTAssertEqual(report.validity, "invalid")
        XCTAssertEqual(report.value, "hello", "失效不删结果，历史查询永远可答")
        XCTAssertEqual(report.notices.first?.code, SettlementRiskNotice.invalidated)
        XCTAssertEqual(report.notices.first?.detail, "source-file:work/r.md")
        // 读取面不写任何行。
        XCTAssertEqual(try db.count("settlements"), settlementsBefore)
        XCTAssertEqual(try db.count("settlement_risk_notices"), 0)
    }


    func testRiskReportRefusesTamperedPayload() throws {
        let (url, db) = try open("report-tamper")
        defer { db.close(); cleanup(url) }
        try db.recordExecutionState(id: "S-report-tamper", parentID: nil, modelIdentity: "m",
                                    position: 1, continuationID: "C", anchor: "a",
                                    lifecycle: "active", createdAt: Date())
        let good = try SettlementAuthority.authorize(
            generatedText: "RESULT=hello", contractJSON: Data(Self.referenceContract.utf8),
            verifiedBindings: ["next_input": .string("hello")])
        let tampered = SettlementAuthority.SettledResult(
            schemaVersion: good.schemaVersion, contractID: good.contractID,
            contractDigest: good.contractDigest, validatedPayload: good.validatedPayload,
            payloadDigest: String(repeating: "0", count: 64),
            trace: good.trace, settledAt: good.settledAt)
        let sid = try db.recordNativeSettlement(tampered, stateID: "S-report-tamper")

        XCTAssertThrowsError(try db.settlementRiskReport(settlementID: sid))
    }

    func testRiskReportRefusesMigratedLegacyPayload() throws {
        let (url, db) = try open("report-legacy")
        defer { db.close(); cleanup(url) }
        let sid = try mkSettlement(db, stateID: "S-report-legacy", value: "hello")
        try executeSQL(
            url,
            "UPDATE settlements SET validation_status='MIGRATED_LEGACY' WHERE settlement_id='\(sid)';")

        XCTAssertThrowsError(try db.settlementRiskReport(settlementID: sid))
    }

    func testSettlementReceiptRefusesTamperedPayloadDigest() throws {
        let (url, db) = try open("receipt-tamper")
        defer { db.close(); cleanup(url) }
        let sid = try mkSettlement(db, stateID: "S-receipt-tamper", value: "hello")
        let zeros = String(repeating: "0", count: 64)
        try executeSQL(
            url,
            "UPDATE settlements SET payload_digest='\(zeros)' WHERE settlement_id='\(sid)';")
        XCTAssertThrowsError(try db.settlementReceipt(sid))
    }

    func testSettlementReceiptRefusesMigratedLegacyPayload() throws {
        let (url, db) = try open("receipt-legacy")
        defer { db.close(); cleanup(url) }
        let sid = try mkSettlement(db, stateID: "S-receipt-legacy", value: "hello")
        try executeSQL(
            url,
            "UPDATE settlements SET validation_status='MIGRATED_LEGACY' WHERE settlement_id='\(sid)';")
        XCTAssertThrowsError(try db.settlementReceipt(sid))
    }

    func testSettlementReceiptCarriesFreshnessRiskNotices() throws {
        let (url, db) = try open("receipt-risk")
        defer { db.close(); cleanup(url) }
        let sid = try mkSettlement(db, stateID: "S-receipt-risk", value: "hello")
        _ = try db.invalidateSettlement(sid)

        let receipt = try XCTUnwrap(db.settlementReceipt(sid))
        XCTAssertEqual(receipt.validity, "invalid")
        XCTAssertEqual(receipt.riskNotices.first?.code, SettlementRiskNotice.invalidated)
    }

    // MARK: - Consumption opt-in

    private struct ConsumptionFixture {
        let directory: URL
        let db: ESISDatabase
    }
    private let consumerIdentity = SettlementIdentityBinding.Identity(
        model: "model-a", tokenizer: "tokenizer-a")

    private func makeConsumptionFixture(_ name: String) throws -> ConsumptionFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-risk-consume-\(UUID().uuidString)-\(name)")
        let rootURL = directory.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("alpha beta gamma".utf8).write(to: rootURL.appendingPathComponent("notes.md"))
        let db = try ESISDatabase(url: directory.appendingPathComponent("esis.sqlite3"))
        try db.runMigrations()
        try db.settleWorkRootContents(rootID: "work", rootURL: rootURL)
        return ConsumptionFixture(directory: directory, db: db)
    }

    @discardableResult
    private func makeConsumptionSource(_ f: ConsumptionFixture) throws -> String {
        let stateID = UUID().uuidString
        try f.db.recordExecutionState(
            id: stateID, parentID: nil, modelIdentity: consumerIdentity.model,
            position: 0, continuationID: UUID().uuidString, anchor: "source-anchor",
            lifecycle: "active", createdAt: Date())
        let settled = try SettlementAuthority.authorize(
            generatedText: "alpha beta gamma",
            contractJSON: InformationLoop.chatResultContractJSON, verifiedBindings: [:])
        let sid = try f.db.recordNativeSettlementWithIdentity(
            settled, stateID: stateID, identity: consumerIdentity).uuidString
        try f.db.linkSettlementToExternalFile(
            settlementID: sid, binding: "content", rootID: "work", relativePath: "notes.md")
        try f.db.declareSettlementReuseContract(
            settlementID: sid,
            contractID: SettlementConsumption.Contract.contractID,
            demandClass: SettlementConsumption.Contract.demandClass,
            contractVersion: SettlementConsumption.Contract.version,
            query: "alpha facts", rootIDs: ["work"],
            extractField: SettlementConsumption.Contract.defaultExtractField,
            requiredConsumerIdentity: nil)
        return sid
    }

    private func consumptionRequest(
        source: String, consumer: String, accept: Bool
    ) -> SettlementConsumption.Request {
        .init(
            sourceSettlementID: source, consumerStateID: consumer,
            consumerModelIdentity: consumerIdentity.model, consumerIdentity: consumerIdentity,
            query: "alpha facts", rootIDs: ["work"],
            acceptInvalidatedDependency: accept)
    }

    func testConsumptionOptInProceedsWithNoticeAndBasis() throws {
        let f = try makeConsumptionFixture("optin")
        defer { f.db.close(); try? FileManager.default.removeItem(at: f.directory) }
        let source = try makeConsumptionSource(f)
        // 只翻 validity，不改文件内容 → canonical 输入不变，拒因只能是新鲜度。
        _ = try f.db.invalidateSourceFile(rootID: "work", relativePath: "notes.md")
        XCTAssertEqual(try f.db.settlementValidity(source), "invalid")

        // 默认拒。
        XCTAssertThrowsError(try SettlementConsumption.consume(
            db: f.db, request: consumptionRequest(source: source, consumer: "c-default", accept: false)))

        // 显式接受 → 消费成功，零模型调用，带提示。
        let outcome = try SettlementConsumption.consume(
            db: f.db, request: consumptionRequest(source: source, consumer: "c-optin", accept: true))
        guard case .consumed(let consumed) = outcome else {
            return XCTFail("expected consumption, got \(outcome)")
        }
        XCTAssertEqual(consumed.modelCalls, 0)
        XCTAssertEqual(consumed.value, "alpha beta gamma")
        XCTAssertEqual(consumed.riskNotices.first?.code, SettlementRiskNotice.invalidated)
        XCTAssertEqual(consumed.riskNotices.first?.settlementID, source)

        // 落库 basis 诚实记录 opt-in 与风险清单，source_validity 不再硬写 valid。
        let rows = try f.db.settlementConsumptions(consumerStateID: "c-optin")
        XCTAssertEqual(rows.count, 1)
        let basis = try JSONSerialization.jsonObject(with: rows[0].basisJSON) as? [String: Any]
        XCTAssertEqual(basis?["accept_invalidated_dependency"] as? Bool, true)
        XCTAssertEqual(basis?["source_validity"] as? String, "accepted-with-risk")
        let notices = basis?["risk_notices"] as? [[String: Any]]
        XCTAssertEqual(notices?.first?["code"] as? String, SettlementRiskNotice.invalidated)
    }

    func testConsumptionReplayPersistsNewRiskAcceptanceWithoutDuplicate() throws {
        let f = try makeConsumptionFixture("replay-risk")
        defer { f.db.close(); try? FileManager.default.removeItem(at: f.directory) }
        let source = try makeConsumptionSource(f)

        let firstOutcome = try SettlementConsumption.consume(
            db: f.db, request: consumptionRequest(
                source: source, consumer: "c-replay-risk", accept: false))
        guard case .consumed(let first) = firstOutcome else {
            return XCTFail("expected initial consumption, got \(firstOutcome)")
        }
        XCTAssertFalse(first.reusedExisting)
        XCTAssertTrue(first.riskNotices.isEmpty)

        // The source changes validity after consumption; the same semantic basis
        // remains unchanged, so this exercises only the idempotent replay path.
        _ = try f.db.invalidateSourceFile(rootID: "work", relativePath: "notes.md")
        XCTAssertEqual(try f.db.settlementValidity(source), "invalid")
        XCTAssertEqual(try f.db.settlementValidity(first.consumerSettlementID), "invalid")

        // Default remains fail-closed and must not append an acceptance event.
        XCTAssertThrowsError(try SettlementConsumption.consume(
            db: f.db, request: consumptionRequest(
                source: source, consumer: "c-replay-risk", accept: false)))
        XCTAssertEqual(try f.db.count("settlement_risk_notices"), 0)

        // Explicitly accepting the newly discovered risk reuses the one existing
        // consumption record and appends the event to its settlement risk ledger.
        let retryOutcome = try SettlementConsumption.consume(
            db: f.db, request: consumptionRequest(
                source: source, consumer: "c-replay-risk", accept: true))
        guard case .consumed(let retry) = retryOutcome else {
            return XCTFail("expected idempotent consumption replay, got \(retryOutcome)")
        }
        XCTAssertTrue(retry.reusedExisting)
        XCTAssertEqual(retry.consumptionID, first.consumptionID)
        XCTAssertEqual(retry.consumerSettlementID, first.consumerSettlementID)
        XCTAssertFalse(retry.riskNotices.isEmpty)

        let rows = try f.db.settlementConsumptions(consumerStateID: "c-replay-risk")
        XCTAssertEqual(rows.count, 1, "replay must not create a second consumption row")
        let originalBasis = try JSONSerialization.jsonObject(with: rows[0].basisJSON) as? [String: Any]
        XCTAssertEqual(originalBasis?["accept_invalidated_dependency"] as? Bool, false)
        XCTAssertEqual(originalBasis?["source_validity"] as? String, "valid",
                       "the original basis must remain immutable")

        let riskCount = Int(try rawText(
            f.directory.appendingPathComponent("esis.sqlite3"),
            "SELECT COUNT(*) FROM settlement_risk_notices WHERE settlement_id='\(first.consumerSettlementID)';")) ?? 0
        XCTAssertGreaterThan(riskCount, 0, "the replayed risk acceptance must be durable")
    }

    // MARK: - Replay durable notices (settleTurn reuse branch)

    private struct ReplayFixture {
        let url: URL
        let db: ESISDatabase
        let loop: InformationLoop
        let root: URL
    }
    private let replayIdentity = SettlementIdentityBinding.Identity(
        model: "replay-model", tokenizer: "replay-tokenizer")

    private func makeReplayFixture(_ name: String) throws -> ReplayFixture {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-risk-replay-\(UUID().uuidString)-\(name).sqlite3")
        let db = try ESISDatabase(url: url)
        try db.runMigrations()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-risk-replay-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("needle revision 0".utf8).write(to: root.appendingPathComponent("a.md"))
        try db.settleWorkRootContents(rootID: "work", rootURL: root, carryText: false)
        return ReplayFixture(url: url, db: db, loop: InformationLoop(database: db), root: root)
    }
    private func cleanupReplay(_ f: ReplayFixture) {
        f.db.close()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: f.url.path + suffix))
        }
        try? FileManager.default.removeItem(at: f.root)
    }
    private func replaySource() -> ESISDatabase.DeclaredSourceIdentity {
        .init(sourceType: "chat", sourceSessionID: "s1", sourceTurnID: "t1",
              sourceMessageID: "m1", sourceRevision: "1")
    }
    private func rawText(_ url: URL, _ sql: String) throws -> String {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle else { return "" }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return "" }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return "" }
        return sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
    }
    private func assistantCount(_ f: ReplayFixture) throws -> Int {
        Int(try rawText(f.url,
            "SELECT COUNT(*) FROM chat_messages WHERE session_id='s1' AND role='assistant';")) ?? -1
    }

    @discardableResult
    private func firstSettle(_ f: ReplayFixture) throws -> String {
        let resolution = try f.loop.resolve(.init(sessionID: "s1", query: "needle", includeChat: false))
        let userID = try f.db.appendChatMessage(
            sessionID: "s1", role: "user", content: "needle? first", model: nil, createdAt: Date())
        let turn = try f.loop.settleTurn(
            generatedText: "the answer", resolution: resolution, stateID: "S-1",
            parentStateID: nil, position: 0, modelIdentity: replayIdentity.model,
            identity: replayIdentity, sessionID: "s1", summaryQuery: "needle",
            sourceIdentity: replaySource(), operationKey: "op-1",
            chatTurn: .init(sessionID: "s1", userMessageID: userID,
                            assistantText: "the answer", model: replayIdentity.model, createdAt: Date()))
        return turn.settlementID
    }

    @discardableResult
    private func replayDirect(
        _ f: ReplayFixture, stateID: String, accept: Bool
    ) throws -> ESISDatabase.SettlementWithAdvancement {
        let settled = try SettlementAuthority.authorize(
            generatedText: "the answer", contractJSON: InformationLoop.chatResultContractJSON,
            verifiedBindings: [:])
        let userID = try f.db.appendChatMessage(
            sessionID: "s1", role: "user", content: "needle? replay", model: nil, createdAt: Date())
        return try f.db.recordNativeSettlementWithIdentityAndAdvancement(
            settled, stateID: stateID, identity: replayIdentity, childState: nil,
            advancement: nil, sourceIdentity: replaySource(), operationKey: "op-1",
            chatTurn: .init(sessionID: "s1", userMessageID: userID,
                            assistantText: "the answer", model: replayIdentity.model, createdAt: Date()),
            chatSessionID: "s1", chatModelIdentity: replayIdentity.model,
            acceptInvalidatedDependency: accept)
    }

    func testOptInReplayRecordsDurableRiskNotices() throws {
        let f = try makeReplayFixture("durable")
        defer { cleanupReplay(f) }
        let answer = try firstSettle(f)
        try Data("needle revision 1 changed".utf8).write(
            to: f.root.appendingPathComponent("a.md"), options: .atomic)
        let invalidated = try f.db.invalidateSourceFile(rootID: "work", relativePath: "a.md")
        XCTAssertTrue(invalidated.contains(answer), "答案须在失效闭包内：\(invalidated)")
        let committedBefore = try assistantCount(f)

        // 默认重放拒，事务回滚，不写 chat 行，不落提示。
        XCTAssertThrowsError(try replayDirect(f, stateID: "S-2", accept: false))
        XCTAssertEqual(try assistantCount(f), committedBefore)
        XCTAssertEqual(try f.db.count("settlement_risk_notices"), 0)

        // 显式接受重放：复用原结算，写一条 chat 行，提示落库（append-only）。
        let replay = try replayDirect(f, stateID: "S-3", accept: true)
        XCTAssertTrue(replay.reused)
        XCTAssertEqual(replay.settlementID.uuidString, answer)
        XCTAssertEqual(replay.riskNotices.first?.code, SettlementRiskNotice.invalidated)
        XCTAssertEqual(try assistantCount(f), committedBefore + 1)
        let durable = Int(try rawText(f.url,
            "SELECT COUNT(*) FROM settlement_risk_notices WHERE settlement_id='\(answer)';")) ?? -1
        XCTAssertGreaterThanOrEqual(durable, 1, "接受的风险须持久化到 settlement_risk_notices")
        // 原结算对象未被改写：仍失效、值仍可查。
        XCTAssertNotEqual(try f.db.settlementValidity(answer), "valid")
        XCTAssertEqual(try f.db.settlementRiskReport(settlementID: answer).value, "the answer")
    }
}