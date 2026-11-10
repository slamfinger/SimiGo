import Foundation
import SimiGoRuntimeContract

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
    let outcome = try SimiGoISAdmission.admit(db: db, stateID: stateID, consumer: cliIdentity)
    let obj: [String: Any] = ["value": outcome.recoveredValue]
    print(String(data: try JSONSerialization.data(withJSONObject: obj), encoding: .utf8)!)

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

default:
    FileHandle.standardError.write(Data("unknown mode \(mode)\n".utf8))
    exit(2)
}
