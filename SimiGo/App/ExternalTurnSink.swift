import Foundation
import SimiGoCollection
import SimiGoRuntimeContract

/// 采集桥 → Information Space 的唯一入口。
///
/// Qoder 的一轮会话是它的 agent 用**自己的云端 API** 产生的：SimiGo 既没有
/// 发出那个请求，也没有那个执行的状态。所以这里走外部轮次合同
/// （`recordExternalTurn` / `recordExternalResponse` / `verifyExternalTurn`），
/// 不借 ES 结算通道 —— 事后给一次外部调用补一个 ES，就是把观测冒充执行。
///
/// 检索资格的判据是**答案完整 + 问答绑定成立**，不是「父链是否完美」：
/// 采集的是已经结束的历史，`recorded` 原本的用途（防止在途文本被并发请求
/// 当成记忆）在这里不存在。父链在压缩后断裂只降低归因强度，不改变「这条
/// 答案确实跟在这个问题后面」这个文件事实。所以：
/// - 可检索：`eligible`、压缩后按文件顺序绑定的两类、排队命令；
/// - 不检索：被打断（答案残缺）、agent 自说自话的续跑/通知/回调；
/// - 只审计：子代理 / 侧链（`.internalOperation`）。
///
/// 归因关系只有三态：`parentChain` / `fileOrderAfterCompaction` /
/// `fileOrderNoChain`。无绑定的回答走 `.orphanAssistant`，不产生轮次，
/// 也就不会到这里 —— 问答要成对才成立，IS 里没有「孤儿轮次」这种行。
///
/// 幂等：`request_id` 用候选的源身份键，重投只会读回既有行；verify 只提升
/// `recorded` 行，所以重复 verify 是空操作。
final class ExternalTurnSink {
    /// 外部轮次的来源标识。转发时代只有一个上游（`openai-compatible`）；
    /// 采集时代的来源是具体的 agent。
    static let provider = "qoder"

    private let databaseURL: URL
    private var db: ESISDatabase?

    init(databaseURL: URL = ManagedPaths.databaseURL) {
        self.databaseURL = databaseURL
    }

    /// 采集器串行队列上的唯一入口。返回即表示本批已被接受；抛错则整批重投。
    func deliver(_ batch: [CandidateDelivery]) throws {
        for delivery in batch {
            guard case .turn(let turn) = delivery.event else { continue }
            try write(turn)
        }
    }

    /// 非轮次事件（基线、无答案闭合、解析失败、孤儿、压缩）没有可入库的
    /// 问答对，不写 IS：它们不是信息，是采集器的诊断。
    private func write(_ turn: CollectedTurnRecord) throws {
        guard !turn.promptText.isEmpty, !turn.answerText.isEmpty else { return }
        let database = try open()
        let sessionID = "qoder:\(turn.projectID)/\(turn.sessionID)"
        let requestID = turn.identity.operationKey
        let createdAt = Self.date(from: turn.timestamp)

        let eligibility: ESISDatabase.ChatTurnEligibility
        var verified = false
        switch turn.disposition {
        case .eligible,
             .requiresReview(.fileOrderAfterCompaction),
             .requiresReview(.fileOrderNoChain),
             .deferredAutoTurn(.queuedCommand):
            eligibility = .ordinary
            verified = true
        case .requiresReview(.interrupted), .deferredAutoTurn:
            eligibility = .ordinary
        case .internalRecord:
            eligibility = .internalOperation
        }

        try database.recordExternalTurn(
            sessionID: sessionID, provider: Self.provider, requestID: requestID,
            userText: turn.promptText, model: turn.answerModel, createdAt: createdAt,
            eligibility: eligibility)
        try database.recordExternalResponse(
            sessionID: sessionID, provider: Self.provider, requestID: requestID,
            assistantText: turn.answerText, model: turn.answerModel, createdAt: createdAt,
            eligibility: eligibility)
        guard verified else { return }
        try database.verifyExternalTurn(
            sessionID: sessionID, requestID: requestID, verifiedAt: Date())
    }

    /// 采集器与 sink 共用一条串行队列，所以句柄按进程生命周期持有一次就够；
    /// 每批重开会把 `PRAGMA integrity_check` 变成回填时的逐个全库扫描。
    private func open() throws -> ESISDatabase {
        if let db { return db }
        let opened = try ESISDatabase(url: databaseURL, createIfNeeded: true)
        try opened.runMigrations()
        db = opened
        return opened
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso = ISO8601DateFormatter()

    /// transcript 的时间戳是采集到的观测时刻；解析不了才退到写入时刻。
    /// 时间只影响行的 `created_at`，不参与幂等键。
    static func date(from stamp: String?) -> Date {
        guard let stamp, !stamp.isEmpty else { return Date() }
        return isoFractional.date(from: stamp) ?? iso.date(from: stamp) ?? Date()
    }
}
