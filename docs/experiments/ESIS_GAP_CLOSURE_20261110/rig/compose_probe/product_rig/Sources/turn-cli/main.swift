import Foundation
import SimiGoRuntimeContract

// HEAD 11a5061 起契约类型统一去 SimiGo 前缀；typealias 保住 v2 装置原文不改语义。
typealias SimiGoESISDatabase = ESISDatabase
typealias SimiGoISAdmission = ISAdmission
typealias SimiGoSettlementConsumption = SettlementConsumption
typealias SimiGoSettlementAuthority = SettlementAuthority
typealias SimiGoInformationLoop = InformationLoop
typealias SimiGoSettlementIdentityBinding = SettlementIdentityBinding

/// 契约声明/源结算预埋 helper —— 全部走真实 API
/// （SettlementAuthority.authorize / recordNativeSettlementWithIdentity /
///   declareSettlementReuseContract），不用裸 SQL。
///
/// 编译：加入 /tmp/e 临时包（绕过 mlx 子模块解析的已验证路径）：
///   Sources/contract-cli/main.swift（本文件）
///   Package.swift 增补：
///     .executableTarget(name: "contract-cli",
///                       dependencies: ["SimiGoRuntimeContract"]),
///
/// 用法：
///   contract_cli declare --db PATH --settlement ID --query Q [--roots work,more]
///   contract_cli stage   --db PATH --root-url DIR --value V --query Q
///                        [--state-id S] [--model M] [--tokenizer T] [--root-id work]


/// 拒绝的稳定机器名（与 Refusal 的 case 一一对应），用于 driver 侧分类。
func refusalReason(_ e: SimiGoISAdmission.Refusal) -> String {
    switch e {
    case .noSettlement: return "no-settlement"
    case .unknownSettlement: return "unknown-settlement"
    case .digestMismatch: return "digest-mismatch"
    case .invalidated: return "invalidated"
    case .dependencyMissing: return "dependency-missing"
    case .dependencyInvalid: return "dependency-invalid"
    case .producerBinding: return "producer-binding"
    case .emptyValue: return "empty-value"
    }
}

func arg(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write(Data("usage: contract_cli constants|declare|stage ...\n".utf8))
    exit(2)
}
let mode = args[1]

// constants 不需要数据库：把 Swift 常量的字面值交给 driver（避免脚本侧硬编码猜测）。
if mode == "constants" {
    let obj: [String: String] = [
        "contract_id": SimiGoSettlementConsumption.Contract.contractID,
        "demand_class": SimiGoSettlementConsumption.Contract.demandClass,
        "version": SimiGoSettlementConsumption.Contract.version,
        "extract": SimiGoSettlementConsumption.Contract.defaultExtractField,
    ]
    print(String(data: try JSONSerialization.data(withJSONObject: obj), encoding: .utf8)!)
    exit(0)
}

guard let dbPath = arg("--db") else {
    FileHandle.standardError.write(Data("missing --db\n".utf8))
    exit(2)
}
let db = try SimiGoESISDatabase(url: URL(fileURLWithPath: dbPath))
try db.runMigrations()  // 幂等：全新实验库由本 helper 建表；服务器库则原样通过
defer { db.close() }

switch mode {
case "init":
    print("INIT")

case "get-value":
    guard let stateID = arg("--state") else {
        FileHandle.standardError.write(Data("get-value needs --state\n".utf8))
        exit(2)
    }
    // 走真实准入读路径取结算值——consume 服务给消费者的就是这个 recoveredValue，
    // 所以它是 C 臂返回内容的唯一合法期望值来源（模型原文 ≠ 规范化结算值）。
    let cliIdentity = SimiGoSettlementIdentityBinding.Identity(
        model: "contract-cli", tokenizer: "contract-cli")
    // 拒绝是读数，不是崩溃：调用方需要一个可分类的观测值。
    do {
        let outcome = try SimiGoISAdmission.admit(db: db, stateID: stateID, consumer: cliIdentity)
        let obj: [String: Any] = ["admitted": true, "value": outcome.recoveredValue]
        print(String(data: try JSONSerialization.data(withJSONObject: obj), encoding: .utf8)!)
    } catch let refusal as SimiGoISAdmission.Refusal {
        let obj: [String: Any] = [
            "admitted": false,
            "reason": refusalReason(refusal),
            "detail": refusal.description,
        ]
        print(String(data: try JSONSerialization.data(withJSONObject: obj), encoding: .utf8)!)
        exit(3)
    }

case "declare":
    guard let sid = arg("--settlement"), let query = arg("--query") else {
        FileHandle.standardError.write(Data("declare needs --settlement --query\n".utf8))
        exit(2)
    }
    let roots = (arg("--roots") ?? "work").split(separator: ",").map(String.init)
    try db.declareSettlementReuseContract(
        settlementID: sid,
        contractID: SimiGoSettlementConsumption.Contract.contractID,
        demandClass: SimiGoSettlementConsumption.Contract.demandClass,
        contractVersion: SimiGoSettlementConsumption.Contract.version,
        query: query,
        rootIDs: roots)
    print("DECLARED \(sid)")

case "stage":
    let rootID = arg("--root-id") ?? "work"
    guard let rootURLPath = arg("--root-url"),
          let value = arg("--value"),
          let query = arg("--query") else {
        FileHandle.standardError.write(Data("stage needs --root-url --value --query\n".utf8))
        exit(2)
    }
    let stateID = arg("--state-id") ?? ("es-s0-" + UUID().uuidString.lowercased())
    let model = arg("--model") ?? "rehearsal-model"
    let tokenizer = arg("--tokenizer") ?? "rehearsal-tokenizer"
    let rootURL = URL(fileURLWithPath: rootURLPath, isDirectory: true)

    _ = try db.settleWorkRootContents(rootID: rootID, rootURL: rootURL)
    let settled = try SimiGoSettlementAuthority.authorize(
        generatedText: value,
        contractJSON: SimiGoInformationLoop.chatResultContractJSON,
        verifiedBindings: [:])
    try db.recordExecutionState(
        id: stateID, parentID: nil, modelIdentity: model,
        position: 1, continuationID: UUID().uuidString,
        anchor: settled.payloadDigest, lifecycle: "active", createdAt: Date())
    let identity = SimiGoSettlementIdentityBinding.Identity(model: model, tokenizer: tokenizer)
    let sid = try db.recordNativeSettlementWithIdentity(
        settled, stateID: stateID, identity: identity).uuidString
    try db.recordIdentityBindings(settlementID: sid, identity: identity)
    try db.declareSettlementReuseContract(
        settlementID: sid,
        contractID: SimiGoSettlementConsumption.Contract.contractID,
        demandClass: SimiGoSettlementConsumption.Contract.demandClass,
        contractVersion: SimiGoSettlementConsumption.Contract.version,
        query: query,
        rootIDs: [rootID])
    print("STAGED \(sid) state=\(stateID)")

case "stage-linked":
    // 与生成路径同构：先落 IS 检索结算，再落模型结算，再写 dependency_edges。
    // kind 与引擎 insertInformationAdvancementRows 一致："information-demand"。
    let rootID = arg("--root-id") ?? "work"
    guard let rootURLPath = arg("--root-url"),
          let value = arg("--value"),
          let query = arg("--query") else {
        FileHandle.standardError.write(Data("stage-linked needs --root-url --value --query\n".utf8))
        exit(2)
    }
    let stateID = arg("--state-id") ?? ("es-linked-" + UUID().uuidString.lowercased())
    let demandID = arg("--demand-id") ?? ("demand-" + stateID)
    let model = arg("--model") ?? "rehearsal-model"
    let tokenizer = arg("--tokenizer") ?? "rehearsal-tokenizer"
    let rootURL = URL(fileURLWithPath: rootURLPath, isDirectory: true)

    _ = try db.settleWorkRootContents(rootID: rootID, rootURL: rootURL)
    let retrieval = try db.recordInformationRetrieval(.init(
        demandID: demandID, stateID: stateID, sessionID: nil,
        query: query, rootIDs: [rootID], includeChat: false,
        inputDigest: "v2:\(rootID):\(query)",
        payload: Data(("retrieval:" + query).utf8),
        hitCount: 1, itemIDs: [], inputs: []))
    let settled = try SimiGoSettlementAuthority.authorize(
        generatedText: value,
        contractJSON: SimiGoInformationLoop.chatResultContractJSON,
        verifiedBindings: [:])
    try db.recordExecutionState(
        id: stateID, parentID: nil, modelIdentity: model,
        position: 1, continuationID: UUID().uuidString,
        anchor: settled.payloadDigest, lifecycle: "active", createdAt: Date())
    let identity = SimiGoSettlementIdentityBinding.Identity(model: model, tokenizer: tokenizer)
    let sid = try db.recordNativeSettlementWithIdentity(
        settled, stateID: stateID, identity: identity).uuidString
    try db.recordIdentityBindings(settlementID: sid, identity: identity)
    try db.addDependency(fromSettlement: sid,
                         toSettlement: retrieval.retrievalSettlementID,
                         kind: "information-demand")
    try db.declareSettlementReuseContract(
        settlementID: sid,
        contractID: SimiGoSettlementConsumption.Contract.contractID,
        demandClass: SimiGoSettlementConsumption.Contract.demandClass,
        contractVersion: SimiGoSettlementConsumption.Contract.version,
        query: query,
        rootIDs: [rootID])
    print("STAGED-LINKED \(sid) state=\(stateID) retrieval=\(retrieval.retrievalSettlementID)")

case "invalidate":
    guard let rootID = arg("--root-id"), let rel = arg("--path") else {
        FileHandle.standardError.write(Data("invalidate needs --root-id --path\n".utf8))
        exit(2)
    }
    let affected = try db.invalidateSourceFile(rootID: rootID, relativePath: rel)
    print("INVALIDATED " + affected.joined(separator: ","))

case "scan":
    // 只重扫、不造结算：产品侧真实的"文件变了"入口（settleWorkRootContents）。
    let rootID = arg("--root-id") ?? "work"
    guard let rootURLPath = arg("--root-url") else {
        FileHandle.standardError.write(Data("scan needs --root-url\n".utf8))
        exit(2)
    }
    let rep = try db.settleWorkRootContents(
        rootID: rootID, rootURL: URL(fileURLWithPath: rootURLPath, isDirectory: true))
    let obj: [String: Any] = [
        "scanned": rep.scanned, "reused": rep.reused, "settled": rep.settled,
        "changed": rep.changed, "removed": rep.removed,
        "binaryOrLarge": rep.skippedBinaryOrLarge,
        "invalidatedSettlements": rep.invalidatedSettlements,
        "objectsCreated": rep.objectsCreated, "deduplicated": rep.deduplicated,
    ]
    print("SCANNED " + String(data: try JSONSerialization.data(
        withJSONObject: obj, options: [.sortedKeys]), encoding: .utf8)!)

case "resolve":
    // 产品环：SimiGoInformationLoop.resolve —— 与 HTTP 路径同一个函数。
    guard let query = arg("--query") else {
        FileHandle.standardError.write(Data("resolve needs --query\n".utf8))
        exit(2)
    }
    let roots = arg("--roots").map {
        $0.split(separator: ",").map(String.init)
    } ?? []
    let loop = SimiGoInformationLoop(database: db)
    let r = try loop.resolve(.init(
        stateID: arg("--state"),
        sessionID: arg("--session"),
        requestIdentity: arg("--request"),
        query: query,
        rootIDs: roots,
        includeChat: (arg("--chat") ?? "0") == "1",
        limit: Int(arg("--limit") ?? "40") ?? 40))
    let obj: [String: Any] = [
        "demandID": r.demandID, "reused": r.reused, "hits": r.hits.count,
        "retrievalSettlementID": r.retrievalSettlementID,
        "items": r.itemIDs, "stale": r.staleItemIDs,
        "inputDigest": r.inputDigest,
    ]
    print("RESOLVED " + String(data: try JSONSerialization.data(
        withJSONObject: obj, options: [.sortedKeys]), encoding: .utf8)!)

case "turn":
    // 产品生成路径的结算形态（与 HTTP 生成路径同一组函数，无手工装配）：
    //   settleWorkRootContents（根索引，"文件变了"的唯一入口）
    //   → SimiGoInformationLoop.resolve（检索结算 + 文件绑定 settlement_bindings.source_file_id）
    //   → SimiGoInformationLoop.settleTurn（模型结算 + advancement 依赖边 information-demand）。
    // 第二次同 request 的 turn 就是"同一 demand 第二权威"的构造点：demand 身份
    // （canonical: query/request/limit/root-scope/inputs）不含 stateID，stateID 只在
    // request 缺省时作 fallback，所以显式 --request 相同 ⇒ 同一 demand。
    let rootID = arg("--root-id") ?? "shared"
    guard let rootURLPath = arg("--root-url"),
          let value = arg("--value"),
          let query = arg("--query") else {
        FileHandle.standardError.write(Data("turn needs --root-url --value --query\n".utf8))
        exit(2)
    }
    let stateID = arg("--state-id") ?? ("es-turn-" + UUID().uuidString.lowercased())
    let request = arg("--request")
    let model = arg("--model") ?? "rehearsal-model"
    let tokenizer = arg("--tokenizer") ?? "rehearsal-tokenizer"
    let rootURL = URL(fileURLWithPath: rootURLPath, isDirectory: true)

    let scanRep = try db.settleWorkRootContents(rootID: rootID, rootURL: rootURL)
    let loop = SimiGoInformationLoop(database: db)
    let r = try loop.resolve(.init(
        stateID: stateID, sessionID: nil, requestIdentity: request,
        query: query, rootIDs: [rootID], includeChat: false, limit: 40))
    let identity = SimiGoSettlementIdentityBinding.Identity(model: model, tokenizer: tokenizer)
    let t = try loop.settleTurn(
        generatedText: value, resolution: r, stateID: stateID, parentStateID: nil,
        position: 1, modelIdentity: model, identity: identity, sessionID: nil,
        summaryQuery: query)
    let obj: [String: Any] = [
        "rootID": rootID,
        "scan": ["scanned": scanRep.scanned, "settled": scanRep.settled,
                 "changed": scanRep.changed,
                 "invalidatedSettlements": scanRep.invalidatedSettlements],
        "demandID": r.demandID, "resolveReused": r.reused, "hits": r.hits.count,
        "retrievalSettlementID": r.retrievalSettlementID,
        "settlementID": t.settlementID, "turnReused": t.reused, "stateID": t.stateID,
    ]
    print("TURN " + String(data: try JSONSerialization.data(
        withJSONObject: obj, options: [.sortedKeys]), encoding: .utf8)!)

case "ext-turn":
    // 第三 intake 的 IS 落点：与 app 的 ExternalTurnSink.write 同一函数组
    // （recordExternalTurn / recordExternalResponse / verifyExternalTurn）。
    // 刻意不写结算：我们没执行过的调用没有执行状态（论文 §6.7 纪律）。
    guard let session = arg("--session"), let req = arg("--request"),
          let user = arg("--user"), let answer = arg("--answer") else {
        FileHandle.standardError.write(Data("ext-turn needs --session --request --user --answer\n".utf8))
        exit(2)
    }
    let provider = arg("--provider") ?? "qoder"
    let model = arg("--model")
    _ = try db.recordExternalTurn(sessionID: session, provider: provider,
                                  requestID: req, userText: user, model: model,
                                  createdAt: Date())
    _ = try db.recordExternalResponse(sessionID: session, provider: provider,
                                      requestID: req, assistantText: answer, model: model,
                                      createdAt: Date())
    let verified = try db.verifyExternalTurn(sessionID: session, requestID: req,
                                             verifiedAt: Date())
    print("EXT-TURN verified=\(verified)")

default:
    FileHandle.standardError.write(Data("unknown mode \(mode)\n".utf8))
    exit(2)
}
