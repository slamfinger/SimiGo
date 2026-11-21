import Darwin
import Foundation
import SQLite3
import XCTest

@testable import SimiGoRuntimeContract

/// 失效路径 · 种子与扩展。
/// 预注册：ES-IS-research/docs/research/EXPERIMENT_INVALIDATION_ROUTES_PREREG_V0.1_20261116.md
///
/// 问的是：源文件变更时，闭包的**火种**从哪来。`affectedClosure`（`ESISDatabase.swift:11236`）
/// 的 CTE 有两半——种子取 `settlement_bindings ⋈ external_files`（直绑文件的结算），
/// 递归扩展才走 `dependency_edges`。而 `PAPER_S4_MECHANISM:51` 写的是
/// 「only if it has a dependency edge」。两者不能同时对。
///
/// **纪律：哪几处断言、哪几处只打印**
///   装置检查带硬断言——F 必须零依赖边、E 必须零绑定。这不是被测问题，是地基：
///   如果 F 其实有边，那 `dependency_edges=0 却失效` 的观察就另有成因，整轮作废。
///   R1 的 validity 读数**一个断言都不带**，只打印成 `ROUTE_*` 行。
///   判定写在预注册 §3，不写进断言——本轮读的是路径结构，不是"应该怎样"。
///
/// R2/R3 是两次生产码突变（掐种子 / 去递归段），跑的是同一个测试方法，
/// 突变位置与预期见预注册 §2；还原后 sha256 须逐字节一致。
///
///     swift test --filter ESISSourceInvalidationRouteArmsTests 2>&1 | grep '^ROUTE_'
final class ESISSourceInvalidationRouteArmsTests: XCTestCase {

    private let identity = SettlementIdentityBinding.Identity(
        model: "route-model", tokenizer: "route-tokenizer")
    private let query = "route facts"

    private struct Fixture {
        let directory: URL
        let dbURL: URL
        let rootURL: URL
        let db: ESISDatabase
    }

    private func makeFixture(_ name: String) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("simigo-route-\(UUID().uuidString)-\(name)")
        let rootURL = directory.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try Data("V1".utf8).write(to: rootURL.appendingPathComponent("doc.txt"))
        let dbURL = directory.appendingPathComponent("esis.sqlite3")
        let db = try ESISDatabase(url: dbURL)
        try db.runMigrations()
        try db.settleWorkRootContents(rootID: "work", rootURL: rootURL)
        return Fixture(directory: directory, dbURL: dbURL,
                       rootURL: rootURL.resolvingSymlinksInPath(), db: db)
    }

    private func cleanup(_ f: Fixture) {
        f.db.close()
        try? FileManager.default.removeItem(at: f.directory)
    }

    /// 观测者读数：绕开被测库 API，直接开它的 sqlite 文件数行。
    private func observeCount(_ url: URL, _ sql: String) -> Int {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle else { return -1 }
        defer { sqlite3_close(handle) }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return -1
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    // 量具分三把，因为第一版把两件事混成一把、当场红了 3 条：
    //   出边 ≠ 入边：F 被 E 消费，F 有 1 条**入边**，但它自己不依赖任何东西。
    //     判"F 无依赖却被失效"要数的是出边。
    //   全部绑定 ≠ 文件绑定：消费会给派生结算写 `consumer.*` 绑定行，
    //     `source_file_id` 为空，进不了 `affectedClosure` 的种子 JOIN。
    //     判"直绑文件"要用与种子完全同一个谓词。

    /// 与 `affectedClosure` 种子完全同谓词的文件绑定行数。
    private func fileBindings(_ f: Fixture, _ id: String) -> Int {
        observeCount(f.dbURL, """
        SELECT COUNT(*) FROM settlement_bindings b
          JOIN external_files e ON e.file_id=b.source_file_id AND e.root_id=b.source_root_id
         WHERE b.settlement_id='\(id)' AND b.source_root_id='work';
        """)
    }

    /// 全部绑定行（含 `consumer.*` 这类非文件绑定），用来解释两者之差。
    private func allBindings(_ f: Fixture, _ id: String) -> Int {
        observeCount(f.dbURL,
            "SELECT COUNT(*) FROM settlement_bindings WHERE settlement_id='\(id)';")
    }

    /// 出边：这条结算依赖谁。
    private func outEdges(_ f: Fixture, _ id: String) -> Int {
        observeCount(f.dbURL,
            "SELECT COUNT(*) FROM dependency_edges WHERE from_settlement='\(id)';")
    }

    /// 入边：谁依赖这条结算。
    private func inEdges(_ f: Fixture, _ id: String) -> Int {
        observeCount(f.dbURL,
            "SELECT COUNT(*) FROM dependency_edges WHERE to_settlement='\(id)';")
    }

    @discardableResult
    private func makeNative(_ f: Fixture, state: String, linkFile: Bool) throws -> String {
        try f.db.recordExecutionState(
            id: state, parentID: nil, modelIdentity: identity.model, position: 0,
            continuationID: UUID().uuidString, anchor: "anchor-\(state)",
            lifecycle: "active", createdAt: Date())
        let settled = try SettlementAuthority.authorize(
            generatedText: "alpha beta gamma",
            contractJSON: InformationLoop.chatResultContractJSON,
            verifiedBindings: [:])
        let id = try f.db.recordNativeSettlement(settled, stateID: state)
        if linkFile {
            try f.db.linkSettlementToExternalFile(
                settlementID: id, binding: "content",
                rootID: "work", relativePath: "doc.txt")
        }
        return id
    }

    private func declare(_ f: Fixture, settlement: String) throws {
        try f.db.declareSettlementReuseContract(
            settlementID: settlement,
            contractID: SettlementConsumption.Contract.contractID,
            demandClass: SettlementConsumption.Contract.demandClass,
            contractVersion: SettlementConsumption.Contract.version,
            query: query,
            rootIDs: ["work"],
            extractField: SettlementConsumption.Contract.defaultExtractField)
    }

    /// 零模型调用地消费上游，返回派生结算 id（依赖边由此建立）。
    private func consume(_ f: Fixture, source: String, state: String) throws -> String {
        let outcome = try SettlementConsumption.consume(db: f.db, request: .init(
            sourceSettlementID: source,
            consumerStateID: state,
            consumerModelIdentity: identity.model,
            consumerIdentity: identity,
            query: query,
            rootIDs: ["work"]))
        guard case .consumed(let value) = outcome else {
            XCTFail("expected a consumption, got \(outcome)")
            throw SettlementConsumption.Refusal.missingField("outcome")
        }
        return value.consumerSettlementID
    }

    /// 装置 + R1：F 直绑文件（零依赖边）、E 只经消费边依赖 F、U 两者皆无。
    /// 改文件后重扫，读三条的 validity。
    func testSeedAndExpansionRoutes() throws {
        let f = try makeFixture("rescan")
        defer { cleanup(f) }

        let fileID = try makeNative(f, state: "F", linkFile: true)
        try declare(f, settlement: fileID)
        let edgeID = try consume(f, source: fileID, state: "E")
        let unrelatedID = try makeNative(f, state: "U", linkFile: false)

        // ---- 装置检查：不合格则整轮作废，这是地基不是被测问题 ----
        XCTAssertEqual(fileBindings(f, fileID), 1, "F 必须直绑文件")
        XCTAssertEqual(outEdges(f, fileID), 0,
                       "F 必须零出边——它不依赖任何东西。否则 §10.2 的观察另有成因，本轮作废")
        XCTAssertEqual(fileBindings(f, edgeID), 0, "E 自身不绑文件")
        XCTAssertEqual(outEdges(f, edgeID), 1, "E 只有一条出边指向 F")
        XCTAssertEqual(fileBindings(f, unrelatedID), 0, "U 不绑文件")
        XCTAssertEqual(outEdges(f, unrelatedID), 0, "U 无出边")
        print("ROUTE_SETUP F=\(fileID) E=\(edgeID) U=\(unrelatedID)")
        print("ROUTE_SETUP file_bindings F/E/U=\(fileBindings(f, fileID))/\(fileBindings(f, edgeID))/\(fileBindings(f, unrelatedID)) "
            + "all_bindings F/E/U=\(allBindings(f, fileID))/\(allBindings(f, edgeID))/\(allBindings(f, unrelatedID))")
        print("ROUTE_SETUP out_edges F/E/U=\(outEdges(f, fileID))/\(outEdges(f, edgeID))/\(outEdges(f, unrelatedID)) "
            + "in_edges F/E/U=\(inEdges(f, fileID))/\(inEdges(f, edgeID))/\(inEdges(f, unrelatedID))")

        // ---- R1：改文件，重扫 ----
        try Data("V2".utf8).write(to: f.rootURL.appendingPathComponent("doc.txt"))
        let report = try f.db.settleWorkRootContents(rootID: "work", rootURL: f.rootURL)
        print("ROUTE_R1 changed=\(report.changed) removed=\(report.removed) "
            + "invalidatedSettlements=\(report.invalidatedSettlements)")
        print("ROUTE_R1 validity F=\(try f.db.settlementValidity(fileID)) "
            + "E=\(try f.db.settlementValidity(edgeID)) "
            + "U=\(try f.db.settlementValidity(unrelatedID))")
        print("ROUTE_R1 edges_after total=\(try f.db.count("dependency_edges")) "
            + "out F/E/U=\(outEdges(f, fileID))/\(outEdges(f, edgeID))/\(outEdges(f, unrelatedID)) "
            + "file_bindings F/E/U=\(fileBindings(f, fileID))/\(fileBindings(f, edgeID))/\(fileBindings(f, unrelatedID))")
        print("ROUTE_R1 closure_of_E=\(try f.db.upstreamDependencyClosure(ofSettlement: edgeID))")
    }

    /// 交叉对照：同一个装置，走 `invalidateSourceFile` 这条公开入口而非重扫。
    /// 两条入口共用 `affectedClosure`，读数应同形；不同形说明还有一条未识别的路。
    func testInvalidateSourceFileUsesTheSameSeed() throws {
        let f = try makeFixture("direct")
        defer { cleanup(f) }

        let fileID = try makeNative(f, state: "F", linkFile: true)
        try declare(f, settlement: fileID)
        let edgeID = try consume(f, source: fileID, state: "E")
        let unrelatedID = try makeNative(f, state: "U", linkFile: false)
        XCTAssertEqual(fileBindings(f, fileID), 1, "装置检查同 R1")
        XCTAssertEqual(outEdges(f, fileID), 0, "装置检查同 R1：F 零出边")
        XCTAssertEqual(fileBindings(f, edgeID), 0, "装置检查同 R1：E 不绑文件")

        let returned = try f.db.invalidateSourceFile(rootID: "work", relativePath: "doc.txt")
        print("ROUTE_X returned=\(returned.sorted())")
        print("ROUTE_X contains_F=\(returned.contains(fileID)) contains_E=\(returned.contains(edgeID)) "
            + "contains_U=\(returned.contains(unrelatedID))")
        print("ROUTE_X validity F=\(try f.db.settlementValidity(fileID)) "
            + "E=\(try f.db.settlementValidity(edgeID)) "
            + "U=\(try f.db.settlementValidity(unrelatedID))")
    }
}


extension ESISSourceInvalidationRouteArmsTests {
    func testSourceFilesystemErrorsAreCallScopedUnavailableUnlessRefused() {
        // Deletion is no more evidence of changed historical content than a
        // disconnected volume or a cloud placeholder. All reachability failures
        // are returned to this call; none may create a persisted invalidation.
        for code in [
            ENOENT, ENOTDIR, EACCES, EPERM, EIO, ENOTCONN, ETIMEDOUT,
            EHOSTDOWN, EHOSTUNREACH, ENETDOWN, ENODEV, ENXIO,
        ] {
            let error = sourceFilesystemError(
                path: "root/doc.md", code: code, operation: "test-read")
            guard case .sourceReadUnavailable(let path, let actualCode) = error else {
                return XCTFail("errno \(code) must be transient unavailable, got \(error)")
            }
            XCTAssertEqual(path, "root/doc.md")
            XCTAssertEqual(actualCode, code)
        }

        let redirected = sourceFilesystemError(
            path: "root/doc.md", code: ELOOP, operation: "test-open")
        guard case .sql = redirected else {
            return XCTFail("ELOOP/symlink refusal must not be downgraded to unavailable")
        }
    }
}
