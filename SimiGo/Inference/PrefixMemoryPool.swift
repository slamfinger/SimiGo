import Foundation
import MLX
import MLXLMCommon
import SimiGo2Experimental
import SimiGoRuntimeContract

/// #136 内存前缀池（SIMIGO17）——被取消轮次的**可证明前缀边界**在进程内的
/// 续接载体。
///
/// 与磁盘前缀池的分工：磁盘池服务「已结算的跨执行复用」，其门禁
/// （`checkBindAuthority` + IS 结算摘要对账）原样保留；本池只服务**同一
/// 未完成执行的续接**——首轮长 prefill 被客户端超时打断后，重试不必从零
/// 重算引擎已经证明落盘（内存）的那一段行。
///
/// 三条码住的红线：
///
/// 1. **边界只能由引擎证明**。条目唯一来源是
///    `ChatSession.interruptedPrefixBoundary()`：边界取自各注意力层 offset
///    的一致值并与渲染 token 前缀、GDN 递推状态逐项核验，任何不一致即抛
///    错。`prefill.progress` 不进来（它报告的是驱动打算到达的位置，不是
///    cache 的事实）。
/// 2. **源表示不可被消费方写坏**。池持有的是引擎在取消点克隆出的快照，采纳
///    时交出的永远是**再克隆一次**的独立副本（`InterruptedPrefixBoundary
///    .clonedForAdoption()`，上游 `MLXLMCommon` 里实现）。复验按层族分流：
///    注意力层是位置权威，必须 offset 与行数都等于边界，且因为
///    `KVCacheSimple.copy()` 不带 offset，副本的 offset 要写回去再读回核对；
///    递推层（`MambaCache`）不记行数——它的 offset 只是逐字搬运的字段，
///    不是位置证据，对它断言边界会把 10a/30r 的生产模型一律拒绝（2026-10-29
///    实测 `memPoolCloneRejected tokens=1972`，复验规则错在池这一侧，不在
///    引擎）。采纳时消费方还会用自己的活拓扑再验一遍
///    （`ChatSession.snapshotRepresentsPrefix`），两道门都过才 seeding。
/// 3. **ES 续接授权不迁移不掉**。条目携带捕获时的 ES 身份
///    （`executionKey.logicalBranchId`；非受管日常路径为 nil）。采纳要求
///    当前轮的 ES 身份与条目**逐字相等**——nil 只匹配 nil。跨身份、跨模型
///    身份、跨 KV 指纹、前缀内容不同一律 miss，回退冷 prefill。
///
/// 生命周期：随进程。模型卸载（`suspendIfIdle` 真正释放权重）与逻辑会话
/// 真正结束时清池；预算内 LRU 逐出对语义正确性零影响（下次请求重算）。
nonisolated final class PrefixMemoryPool: @unchecked Sendable {
    static let shared = PrefixMemoryPool()

    struct Entry {
        let key: String
        let modelID: String
        let kvFingerprint: String
        let tokenCount: Int
        let boundaryHash: UInt64
        let bytes: Int
        /// 捕获该表示的执行身份；nil = 非受管日常路径。
        let esStateID: String?
        let capturedAt: Date
        var lastUsedAt: Date
        /// 源表示与其证明拓扑——只读，采纳时由上游再克隆一次。
        let boundary: ChatSession.InterruptedPrefixBoundary
    }

    struct Stats {
        let entries: Int
        let tokens: Int
        let bytes: Int
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var tokenTotal = 0
    private var byteTotal = 0

    /// ES 续接授权上下文：本轮 generate 开始前由产品路径写入，钩子在
    /// `.prefillAll` 策略边界内读取。生成本身跨会话串行
    /// （`RuntimeTuning.serializeGeneration`），不存在并发轮次互踩。
    ///
    /// `authority` 是协议层为这个 ES 身份登记、并在本轮 bind 处消费掉的那次
    /// IS 结算权威。`.notGoverned` = 日常轮次（无受管续接），按身份逐字相等
    /// 放行；一旦本轮处于受管续接语义下，内存采纳必须过**和磁盘池同一个**
    /// digest 比较——迁到内存不得让已结算复用失检（§II.3）。
    private var adoptionContext: String?
    private var adoptionAuthority = ISKVBindAuthority.Lookup.notGoverned

    // MARK: - 授权上下文

    func setAdoptionContext(
        _ esStateID: String?, authority: ISKVBindAuthority.Lookup = .notGoverned
    ) {
        lock.withLock {
            adoptionContext = esStateID
            adoptionAuthority = authority
        }
    }

    // MARK: - 捕获

    /// 把引擎证明出的边界登记为源表示。返回 nil 且只记原因的场景：开关
    /// 关闭、条目独占不下预算。任何「证明不了」的情况根本到不了这里——
    /// 上游已经 throw。
    func capture(
        _ boundary: ChatSession.InterruptedPrefixBoundary,
        namespace: PrefixPoolNamespace,
        esStateID: String?
    ) -> Entry? {
        guard RuntimeTuning.prefixMemoryPoolEnabled else { return nil }
        let cumulative = PrefixChain.cumulative(boundary.tokens)
        let hash = cumulative.last ?? 0
        let key = SimiGoSettlementKVBinding.Representation(
            modelID: namespace.modelID,
            kvFingerprint: namespace.kvFingerprint,
            tokenCount: boundary.tokenCount,
            boundaryHash: hash).poolKey
        let now = Date()
        let entry = Entry(
            key: key,
            modelID: namespace.modelID,
            kvFingerprint: namespace.kvFingerprint,
            tokenCount: boundary.tokenCount,
            boundaryHash: hash,
            bytes: boundary.bytes,
            esStateID: esStateID,
            capturedAt: now,
            lastUsedAt: now,
            boundary: boundary)
        return lock.withLock {
            if let existing = entries[key] {
                // 同一边界重复取消：保留更早的捕获时间，刷新使用时间。
                // 快照内容声明相同（同一 content hash），换掉无收益。
                entries[key] = Entry(
                    key: existing.key, modelID: existing.modelID,
                    kvFingerprint: existing.kvFingerprint,
                    tokenCount: existing.tokenCount, boundaryHash: existing.boundaryHash,
                    bytes: existing.bytes, esStateID: esStateID,
                    capturedAt: existing.capturedAt, lastUsedAt: now,
                    boundary: existing.boundary)
                return existing
            }
            guard boundary.bytes > 0, boundary.bytes <= RuntimeTuning.prefixMemoryPoolByteBudget
            else { return nil }
            entries[key] = entry
            tokenTotal += entry.tokenCount
            byteTotal += entry.bytes
            enforceBudgetLocked()
            return entry
        }
    }

    // MARK: - 采纳

    /// 最长内容匹配 + ES 身份匹配的条目，返回**独立副本**与边界长度。
    /// miss 的情形全部回退冷 prefill：无条目、命名空间不符、身份不符、
    /// 边界哈希不符（前缀内容分叉）、ES 权威拒绝、副本自证不符。
    func adopt(
        promptTokenIds: [Int],
        namespace: PrefixPoolNamespace
    ) -> (snapshot: PromptCacheSnapshot, matchedTokenCount: Int)? {
        guard RuntimeTuning.prefixMemoryPoolEnabled, !promptTokenIds.isEmpty else { return nil }
        // 候选与授权在同一把锁里一起取出：采纳用的权威必须和筛身份时看到的是
        // 同一份本轮上下文，不允许两次读之间存在窗口。
        let gate: (context: String?, authority: ISKVBindAuthority.Lookup) = lock.withLock {
            (adoptionContext, adoptionAuthority)
        }
        guard let candidate = passingCandidate(
            promptTokenIds: promptTokenIds, namespace: namespace,
            context: gate.context, authority: gate.authority, source: "adopt"
        ) else { return nil }
        let clone: PromptCacheSnapshot
        do {
            clone = try candidate.boundary.clonedForAdoption()
        } catch let error as ChatSession.InterruptedPrefixBoundaryError {
            // 复验不过就不采纳：宁可再付一次冷 prefill，也不把自己说不清
            // 的行数记成已处理。reason 是 §IV.3 要的拒绝读数。
            RuntimeTraceLogger.shared.trace(
                "[MLX] memPoolCloneRejected tokens=\(candidate.tokenCount)"
                    + " key=\(candidate.key.suffix(12)) reason=\(error.description)")
            return nil
        } catch {
            RuntimeTraceLogger.shared.trace(
                "[MLX] memPoolCloneRejected tokens=\(candidate.tokenCount)"
                    + " key=\(candidate.key.suffix(12)) err=\(String(describing: error))")
            return nil
        }
        lock.withLock {
            if var current = entries[candidate.key] {
                current.lastUsedAt = Date()
                entries[candidate.key] = current
            }
        }
        // 命中行是 §IV.3 主读数的锚点：重试的 prefill 只需付
        // `promptTokens - matched` 那段。
        RuntimeTraceLogger.shared.trace(
            "[MLX] memPoolHit matchedTokens=\(candidate.tokenCount)"
                + " promptTokens=\(promptTokenIds.count)"
                + " bytes=\(candidate.bytes)"
                + " layers=\(candidate.boundary.attentionLayerCount)a/"
                + "\(candidate.boundary.recurrentLayerCount)r"
                + " es=\(candidate.esStateID.map { String($0.suffix(12)) } ?? "-")")
        return (clone, candidate.tokenCount)
    }

    /// W4：预算门的**只读**探测——走和采纳完全同一道门（命名空间、ES 身份
    /// 逐字相等、链哈希对账、`bindVerdict` 权威），但不克隆、不刷新
    /// `lastUsedAt`、不产生任何采纳侧写。返回的边界长度让门按**剩余预填充
    /// 工作**估算，而不是对着一段引擎已经证明落盘的 token 判 503。
    ///
    /// 任何一关不过都返回 nil＝按完整冷 prefill 估算：一条候选存在从来不是
    /// 复用许可，门也不许借「大概会命中」把注定超时的尝试放行。
    func provenMatchTokenCount(
        promptTokenIds: [Int],
        namespace: PrefixPoolNamespace,
        esStateID: String?,
        authority: ISKVBindAuthority.Lookup
    ) -> Int? {
        guard RuntimeTuning.prefixMemoryPoolEnabled, !promptTokenIds.isEmpty else { return nil }
        return passingCandidate(
            promptTokenIds: promptTokenIds, namespace: namespace,
            context: esStateID, authority: authority, source: "budget"
        )?.tokenCount
    }

    /// 两条入口共用的那一段筛选：`source` 只用于把门的预探测读数与真实采纳
    /// 读数分开，判定逻辑两边逐字相同。
    private func passingCandidate(
        promptTokenIds: [Int],
        namespace: PrefixPoolNamespace,
        context esStateID: String?,
        authority: ISKVBindAuthority.Lookup,
        source: String
    ) -> Entry? {
        let candidates = lock.withLock {
            entries.values
                .filter {
                    $0.modelID == namespace.modelID
                        && $0.kvFingerprint == namespace.kvFingerprint
                        && $0.tokenCount < promptTokenIds.count
                        && $0.esStateID == esStateID
                }
                .sorted { $0.tokenCount > $1.tokenCount }
        }
        guard !candidates.isEmpty else { return nil }
        // 链哈希一次算全（同 #4 的口径）：cumulative[i] == hash(tokens[0...i])。
        let cumulative = PrefixChain.cumulative(promptTokenIds)
        var bindRejected = false
        for candidate in candidates {
            guard cumulative.indices.contains(candidate.tokenCount - 1),
                cumulative[candidate.tokenCount - 1] == candidate.boundaryHash
            else { continue }
            // §II.3：内容边界对上之后还要过 ES 权威——和磁盘池调的同一个
            // `bindVerdict`。本轮不受管（`.notGoverned`）时按身份相等放行；
            // 受管续接下没有结算登记过这条边界就是拒绝。物理表示存在从来
            // 不是复用许可，这一条不因为换了内存池而失效。
            let bind = NativeMLXPrefixPool.bindVerdict(
                authority, namespace: namespace,
                tokenCount: candidate.tokenCount, boundaryHash: candidate.boundaryHash)
            guard bind.permitsBind else {
                bindRejected = true
                RuntimeTraceLogger.shared.trace(
                    "[MLX] memPoolBindRejected reason=\(bind.rejectionReason ?? "kv_binding_blocked")"
                        + " tokens=\(candidate.tokenCount) key=\(candidate.key.suffix(12))"
                        + " es=\(candidate.esStateID.map { String($0.suffix(12)) } ?? "-")"
                        + " src=\(source)")
                continue
            }
            return candidate
        }
        // 候选存在但边界哈希不符 = 前缀内容在这一段之前已经分叉。这是
        // §IV.3 要的「账本不匹配时拒绝复用」读数：不采纳，回退冷 prefill。
        // ES 权威拒绝已经逐条记过 `memPoolBindRejected`，不再冒充哈希分叉。
        if !bindRejected {
            RuntimeTraceLogger.shared.trace(
                "[MLX] memPoolHashReject candidates=\(candidates.count)"
                    + " longest=\(candidates.first?.tokenCount ?? 0)"
                    + " promptTokens=\(promptTokenIds.count)"
                    + " src=\(source)")
        }
        return nil
    }

    // MARK: - 清退

    /// 模型卸载/隔离窗口收尾：整池归零。读数（条目/token/byte）进 trace，
    /// 供 §IV.4「卸载后条目数与所占预算归零」直接取证。
    @discardableResult
    func purge(reason: String) -> Stats {
        let snapshot: Stats = lock.withLock {
            let stats = Stats(entries: entries.count, tokens: tokenTotal, bytes: byteTotal)
            entries.removeAll(keepingCapacity: false)
            tokenTotal = 0
            byteTotal = 0
            return stats
        }
        RuntimeTraceLogger.shared.trace(
            "[MLX] memPoolPurge reason=\(reason) entries=\(snapshot.entries)"
                + " tokens=\(snapshot.tokens) bytes=\(snapshot.bytes)")
        return snapshot
    }

    /// 逻辑会话真正结束：只摘掉该执行身份登记的表示。
    func purge(esStateID: String?) -> Int {
        guard let esStateID else { return 0 }
        let removed = lock.withLock {
            let keys = entries.compactMap { $0.value.esStateID == esStateID ? $0.key : nil }
            for key in keys {
                if let entry = entries.removeValue(forKey: key) {
                    tokenTotal -= entry.tokenCount
                    byteTotal -= entry.bytes
                }
            }
            return keys.count
        }
        if removed > 0 {
            RuntimeTraceLogger.shared.trace(
                "[MLX] memPoolPurgeBranch entries=\(removed) es=\(esStateID.suffix(12))")
        }
        return removed
    }

    var stats: Stats {
        lock.withLock { Stats(entries: entries.count, tokens: tokenTotal, bytes: byteTotal) }
    }

    private func enforceBudgetLocked() {
        let tokenBudget = RuntimeTuning.prefixMemoryPoolTokenBudget
        let byteBudget = RuntimeTuning.prefixMemoryPoolByteBudget
        while entries.count > 1, tokenTotal > tokenBudget || byteTotal > byteBudget {
            let oldest = entries.values.min(by: { $0.lastUsedAt < $1.lastUsedAt })
            guard let victim = oldest, let held = entries.removeValue(forKey: victim.key) else {
                break
            }
            tokenTotal -= held.tokenCount
            byteTotal -= held.bytes
            RuntimeTraceLogger.shared.trace(
                "[MLX] memPoolEvict tokens=\(held.tokenCount) bytes=\(held.bytes)"
                    + " es=\(held.esStateID.map { String($0.suffix(12)) } ?? "-")")
        }
    }
}
