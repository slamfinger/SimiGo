import XCTest
@testable import SimiGo

/// #90 第一阶段（测试层）：跨请求活会话采纳的判据，与活会话驻留字节上限
/// 的口径/上限推导。全部是纯函数与合成 config.json——不加载模型、不碰
/// ES/IS、不需要真机窗口。真实模型读数只在第二阶段另行安排。
final class SessionAdoptionTests: XCTestCase {

    private func candidate(
        key: String = "openai/s-request:aaa/history",
        historyCount: Int = 4,
        isStrictPrefix: Bool = true,
        kvFingerprint: String? = nil,
        thinkingDisabled: Bool? = false,
        inFlightRequestId: String? = nil,
        agentId: String? = "default",
        lastActivity: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> SessionAdoption.Candidate {
        SessionAdoption.Candidate(
            key: key,
            historyCount: historyCount,
            historyIsStrictPrefixOfIncoming: isStrictPrefix,
            kvFingerprint: kvFingerprint,
            thinkingDisabled: thinkingDisabled,
            inFlightRequestId: inFlightRequestId,
            agentId: agentId,
            lastActivity: lastActivity
        )
    }

    private func request(
        incomingCount: Int = 5,
        kvFingerprint: String? = nil,
        thinkingDisabled: Bool = false,
        agentId: String = "default"
    ) -> SessionAdoption.Request {
        SessionAdoption.Request(
            incomingCount: incomingCount,
            kvFingerprint: kvFingerprint,
            thinkingDisabled: thinkingDisabled,
            agentId: agentId
        )
    }

    // MARK: - 采纳判据

    func testStrictPrefixAppendIsAdoptable() {
        let chosen = SessionAdoption.choose([candidate()], for: request())
        XCTAssertEqual(chosen?.key, "openai/s-request:aaa/history")
    }

    func testEqualLengthTranscriptIsRejected() {
        // 逐条追加要求入站严格更长；等长意味着本轮没有新增消息（或重放），
        // 不是可续接的分支。
        XCTAssertNil(SessionAdoption.choose(
            [candidate(historyCount: 5)], for: request(incomingCount: 5)))
    }

    func testLongerButNotPrefixIsRejected() {
        // 历史中段被改写 → 已生成区不再可信，落冷路径。
        XCTAssertNil(SessionAdoption.choose(
            [candidate(historyCount: 4, isStrictPrefix: false)],
            for: request(incomingCount: 8)))
    }

    func testKVFingerprintMismatchIsRejected() {
        XCTAssertNil(SessionAdoption.choose(
            [candidate(kvFingerprint: "turboquant")], for: request(kvFingerprint: nil)))
        XCTAssertNil(SessionAdoption.choose(
            [candidate(kvFingerprint: nil)], for: request(kvFingerprint: "turboquant")))
        XCTAssertEqual(
            SessionAdoption.choose(
                [candidate(kvFingerprint: "same")], for: request(kvFingerprint: "same"))?
                .key,
            "openai/s-request:aaa/history",
            "显式同名指纹是兼容态")
    }

    func testBothUnrecordedFingerprintsMatch() {
        // nil == nil：两侧都走基配置（默认 kv 设置），是同一执行配置。
        XCTAssertNotNil(SessionAdoption.choose([candidate()], for: request()))
    }

    func testThinkingConfigurationMustMatch() {
        XCTAssertNil(SessionAdoption.choose(
            [candidate(thinkingDisabled: true)], for: request(thinkingDisabled: false)))
        XCTAssertNotNil(SessionAdoption.choose(
            [candidate(thinkingDisabled: true)], for: request(thinkingDisabled: true)))
    }

    func testUnrecordedThinkingConfigurationIsNeverAdoptable() {
        // 未知 ≠ 相容：老表示没记录该维度时不允许借用。
        XCTAssertNil(SessionAdoption.choose(
            [candidate(thinkingDisabled: nil)], for: request(thinkingDisabled: false)))
        XCTAssertNil(SessionAdoption.choose(
            [candidate(thinkingDisabled: nil)], for: request(thinkingDisabled: true)))
    }

    func testInFlightShardIsNeverAnAdoptionCandidate() {
        XCTAssertNil(SessionAdoption.choose(
            [candidate(inFlightRequestId: "req-running")], for: request()))
    }

    func testChoosesMostRecentlyActiveEligibleShard() {
        let older = candidate(
            key: "openai/s-request:old/history",
            lastActivity: Date(timeIntervalSince1970: 1))
        let newer = candidate(
            key: "openai/s-request:new/history",
            lastActivity: Date(timeIntervalSince1970: 2))
        let busy = candidate(
            key: "openai/s-request:busy/history",
            inFlightRequestId: "req-x",
            lastActivity: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(
            SessionAdoption.choose([older, newer, busy], for: request())?.key,
            "openai/s-request:new/history",
            "在合格候选里取最近活跃；在途者即便最新也不选")
    }

    func testNoCandidatesMeansNoAdoption() {
        XCTAssertNil(SessionAdoption.choose([], for: request()))
    }

    func testEligibleKeepsEveryQualifyingShardForAudit() {
        let eligible = SessionAdoption.eligibleCandidates(
            [
                candidate(key: "ok-a"),
                candidate(key: "ok-b", historyCount: 1),
                candidate(key: "too-long", historyCount: 9),
                candidate(key: "busy", inFlightRequestId: "r"),
            ],
            for: request()
        )
        XCTAssertEqual(eligible.map(\.key), ["ok-a", "ok-b"])
    }

    /// 「必须冷」的可观测判据：`sessionAdoptMiss reasons=` 的每个理由码都必须
    /// 能唯一对应一条判据，且与 `eligibleCandidates` 是同一套判定——否则
    /// E2E 里「检过且无合格候选」的断言可以与真实采纳逻辑分叉。
    func testEligibilityExposesOneReasonPerCandidate() {
        let cases: [(SessionAdoption.Candidate, SessionAdoption.Eligibility)] = [
            (candidate(key: "no-agent", agentId: nil), .unknownAgent),
            (candidate(key: "other-agent", agentId: "agent-b"), .differentAgent),
            (candidate(key: "busy", inFlightRequestId: "r"), .inFlight),
            (candidate(key: "no-thinking", thinkingDisabled: nil), .unknownThinking),
            (candidate(key: "thinking", thinkingDisabled: true), .thinkingMismatch),
            (candidate(key: "fp", kvFingerprint: "turboquant"), .fingerprintMismatch),
            (candidate(key: "long", historyCount: 5), .notShorter),
            (candidate(key: "fork", isStrictPrefix: false), .notStrictPrefix),
            (candidate(key: "ok"), .eligible),
        ]
        for (candidate, expected) in cases {
            XCTAssertEqual(
                SessionAdoption.eligibility(candidate, for: request()), expected,
                candidate.key)
        }
        XCTAssertEqual(
            cases.compactMap { $0.1.reason },
            [
                "unknownAgent", "differentAgent", "inFlight", "unknownThinking",
                "thinkingMismatch", "fpMismatch", "notShorter", "notPrefix",
            ])
        XCTAssertEqual(
            SessionAdoption.eligibleCandidates(cases.map(\.0), for: request()).map(\.key),
            ["ok"], "eligibility 与 eligibleCandidates 必须是同一条判据")
    }

    // MARK: - 驻留字节口径

    /// 用真机生产模型（qwen3_5_moe，40 层 = 10 full + 30 linear）的几何字段
    /// 断言公式：注意力 20 480 B/token，状态 64 389 120 B/会话。交叉验证
    /// 对象是真实缓存数组——同形状、同 T 的一份生产快照
    /// （`~/.simigo/prefix-pool/44eaa202ce92e06d/e4890e3f1b45e353-12.safetensors`，
    /// 张量段实测 271 278 080 B）与下面的估读逐字节相等。
    func testResidencyMatchesProductionGeometry() throws {
        let modelDir = try makeModelDirectory(config: [
            "model_type": "qwen3_5_moe_text",
            "num_hidden_layers": 40,
            "hidden_size": 2048,
            "num_key_value_heads": 2,
            "head_dim": 256,
            "num_attention_heads": 16,
            "full_attention_interval": 4,
            "linear_num_key_heads": 16,
            "linear_num_value_heads": 32,
            "linear_key_head_dim": 128,
            "linear_value_head_dim": 128,
            "linear_conv_kernel_dim": 4,
            "torch_dtype": "bfloat16",
            "mamba_ssm_dtype": "float32",
        ])
        let residency = try XCTUnwrap(LiveSessionResidency.resolve(modelPath: modelDir))
        XCTAssertEqual(residency.bytesPerToken, 20_480)
        XCTAssertEqual(residency.fixedBytesPerSession, 64_389_120)
        XCTAssertEqual(residency.estimatedBytes(processedTokens: 10_102), 271_278_080,
                       "与同一 T 的真实缓存数组逐字节相等")
        XCTAssertEqual(residency.estimatedBytes(processedTokens: 0),
                       residency.fixedBytesPerSession,
                       "固定状态与上下文长度无关")
        XCTAssertEqual(residency.estimatedBytes(processedTokens: -5),
                       residency.fixedBytesPerSession,
                       "负 token 读数不得放大口径")
    }

    func testResidencyUsesLayerTypesWhenPresent() throws {
        let modelDir = try makeModelDirectory(config: [
            "num_hidden_layers": 4,
            "layer_types": ["full_attention", "linear_attention",
                            "full_attention", "linear_attention"],
            "num_key_value_heads": 8,
            "head_dim": 128,
            "hidden_size": 1024,
            "linear_num_key_heads": 16,
            "linear_num_value_heads": 32,
            "linear_key_head_dim": 128,
            "linear_value_head_dim": 128,
            "linear_conv_kernel_dim": 4,
            "torch_dtype": "bfloat16",
            "mamba_ssm_dtype": "float32",
        ])
        let residency = try XCTUnwrap(LiveSessionResidency.resolve(modelPath: modelDir))
        // 2 个注意力层 ×(K,V)×8 头×128×2B
        XCTAssertEqual(residency.bytesPerToken, 2 * 2 * 8 * 128 * 2)
        // 2 个状态层 ×(卷积态 3×8192×bf16 + 递归态 32×128×128×f32)
        XCTAssertEqual(residency.fixedBytesPerSession, 2 * (49_152 + 2_097_152))
    }

    func testPureAttentionModelHasNoFixedState() throws {
        let modelDir = try makeModelDirectory(config: [
            "num_hidden_layers": 48,
            "num_key_value_heads": 8,
            "head_dim": 128,
            "hidden_size": 4096,
            "torch_dtype": "bfloat16",
        ])
        let residency = try XCTUnwrap(LiveSessionResidency.resolve(modelPath: modelDir))
        XCTAssertEqual(residency.bytesPerToken, 48 * 2 * 8 * 128 * 2)
        XCTAssertEqual(residency.fixedBytesPerSession, 0)
    }

    func testCompositeVLMReadsGeometryFromTextConfig() throws {
        let modelDir = try makeModelDirectory(config: [
            "model_type": "qwen3_5_moe",
            "text_config": [
                "num_hidden_layers": 40,
                "num_key_value_heads": 2,
                "head_dim": 256,
                "hidden_size": 2048,
                "full_attention_interval": 4,
                "linear_num_key_heads": 16,
                "linear_num_value_heads": 32,
                "linear_key_head_dim": 128,
                "linear_value_head_dim": 128,
                "linear_conv_kernel_dim": 4,
                "torch_dtype": "bfloat16",
                "mamba_ssm_dtype": "float32",
            ],
        ])
        let residency = try XCTUnwrap(LiveSessionResidency.resolve(modelPath: modelDir))
        XCTAssertEqual(residency.bytesPerToken, 20_480)
        XCTAssertEqual(residency.fixedBytesPerSession, 64_389_120)
    }

    func testMissingGeometryReturnsNilRatherThanAGuess() throws {
        // 有状态层但缺 GDN 字段：宁可不启用字节维度，也不拿猜出来的宽度逐出暖会话。
        let modelDir = try makeModelDirectory(config: [
            "num_hidden_layers": 40,
            "num_key_value_heads": 2,
            "head_dim": 256,
            "full_attention_interval": 4,
            "torch_dtype": "bfloat16",
        ])
        XCTAssertNil(LiveSessionResidency.resolve(modelPath: modelDir))
        XCTAssertNil(LiveSessionResidency.resolve(
            modelPath: NSTemporaryDirectory() + "no-such-model-dir-\(UUID().uuidString)"))
    }

    func testHeadDimFallsBackToHiddenOverHeads() throws {
        let modelDir = try makeModelDirectory(config: [
            "num_hidden_layers": 4,
            "num_key_value_heads": 2,
            "num_attention_heads": 8,
            "hidden_size": 1024,
            "torch_dtype": "float16",
        ])
        let residency = try XCTUnwrap(LiveSessionResidency.resolve(modelPath: modelDir))
        XCTAssertEqual(residency.bytesPerToken, 4 * 2 * 2 * (1024 / 8) * 2)
        XCTAssertEqual(residency.fixedBytesPerSession, 0)
    }

    // MARK: - 上限推导

    func testCeilingIsThePhysicalFormOfTheTwoExistingBudgets() {
        let residency = LiveSessionResidency(bytesPerToken: 20_480, fixedBytesPerSession: 64_389_120)
        let ceiling = LiveSessionResidency.byteBudget(
            residency: residency, override: nil)
        XCTAssertEqual(
            ceiling,
            64_389_120 * RuntimeTuning.sessionLimit
                + 20_480 * RuntimeTuning.warmTokenBudget)
        // 语义核对：按既有两条预算的最坏组合（sessionLimit 个会话、各
        // warmTokenBudget/sessionLimit token）不应触发字节上限。
        let worstCaseWithinBudget = residency.estimatedBytes(
            processedTokens: RuntimeTuning.warmTokenBudget / RuntimeTuning.sessionLimit)
            * RuntimeTuning.sessionLimit
        XCTAssertLessThanOrEqual(worstCaseWithinBudget, ceiling)
    }

    func testExplicitOverrideWinsWhenPositive() {
        let residency = LiveSessionResidency(bytesPerToken: 100, fixedBytesPerSession: 200)
        XCTAssertEqual(
            LiveSessionResidency.byteBudget(residency: residency, override: 123_456), 123_456)
        // 0/负数不是「把上限定成 0」——那会让每轮都逐出，退回推导值。
        XCTAssertEqual(
            LiveSessionResidency.byteBudget(residency: residency, override: 0),
            200 * RuntimeTuning.sessionLimit + 100 * RuntimeTuning.warmTokenBudget)
        XCTAssertEqual(
            LiveSessionResidency.byteBudget(residency: residency, override: -1),
            200 * RuntimeTuning.sessionLimit + 100 * RuntimeTuning.warmTokenBudget)
    }

    func testProductionCeilingIsBoundedNotUnbounded() {
        let residency = LiveSessionResidency(bytesPerToken: 20_480, fixedBytesPerSession: 64_389_120)
        let ceiling = LiveSessionResidency.byteBudget(residency: residency, override: nil)
        // 生产模型（35B-A3B GDN）：上限必须是可解释的有限值，且明显小于
        // MLX 总内存限（22 GiB）——活会话驻留不得吃掉整个预算。
        XCTAssertGreaterThan(ceiling, 0)
        XCTAssertLessThan(ceiling, RuntimeTuning.mlxMemoryLimitBytes)
        XCTAssertEqual(ceiling, 2_563_112_960)
        XCTAssertEqual(
            Double(ceiling) / Double(RuntimeTuning.gibibyte), 2.39, accuracy: 0.01,
            "8×固定态 + 100k token×20480 B = 2.39 GiB，全部来自既有常数")
    }

    // MARK: - 上限触发（逐出选择）

    private func resident(_ key: String, _ tokens: Int, inFlight: Bool = false) -> ResidencyGovernor.Resident {
        let residency = LiveSessionResidency(bytesPerToken: 20_480, fixedBytesPerSession: 64_389_120)
        return ResidencyGovernor.Resident(
            key: key,
            bytes: residency.estimatedBytes(processedTokens: tokens),
            isInFlight: inFlight
        )
    }

    func testCeilingNotExceededReleasesNothing() {
        let residency = LiveSessionResidency(bytesPerToken: 20_480, fixedBytesPerSession: 64_389_120)
        let ceiling = LiveSessionResidency.byteBudget(residency: residency, override: nil)
        let plan = ResidencyGovernor.evictionPlan(
            [resident("a", 5_000), resident("b", 5_000)],
            protectedBytes: residency.estimatedBytes(processedTokens: 5_000),
            ceiling: ceiling
        )
        XCTAssertFalse(plan.fired, "三个小会话远在既有预算内，不得逐出")
    }

    func testCeilingExceededReleasesLeastRecentlyUsedFirst() {
        let residency = LiveSessionResidency(bytesPerToken: 20_480, fixedBytesPerSession: 64_389_120)
        let ceiling = LiveSessionResidency.byteBudget(residency: residency, override: nil)
        // 每个 20k token 会话 = 64 389 120 + 20 000×20 480 = 473 989 120 B。
        // 12 个候选 + 本轮 1 个 = 6 161 858 560 B；回到 2 563 112 960 B 上限内
        // 最多只能留 5 个 ⇒ 必须按 LRU 释放前 8 个。
        let residents = (0..<12).map { resident("s\($0)", 20_000) }
        let plan = ResidencyGovernor.evictionPlan(
            residents,
            protectedBytes: residency.estimatedBytes(processedTokens: 20_000),
            ceiling: ceiling
        )
        XCTAssertEqual(plan.victims, ["s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7"],
                       "按传入的 LRU 顺序释放，回到上限即停手")
        XCTAssertEqual(plan.warmBytesAfter, 5 * 473_989_120)
        XCTAssertLessThanOrEqual(plan.warmBytesAfter, ceiling)
    }

    func testInFlightShardsAreNeverSelectedEvenWhenOverCeiling() {
        let residency = LiveSessionResidency(bytesPerToken: 20_480, fixedBytesPerSession: 64_389_120)
        let ceiling = LiveSessionResidency.byteBudget(residency: residency, override: nil)
        let residents = [
            resident("busy-a", 20_000, inFlight: true),
            resident("idle", 20_000),
            resident("busy-b", 20_000, inFlight: true),
        ]
        let plan = ResidencyGovernor.evictionPlan(
            residents,
            protectedBytes: residency.estimatedBytes(processedTokens: 120_000),
            ceiling: ceiling
        )
        XCTAssertEqual(plan.victims, ["idle"], "在途分片与淘汰隔离")
        XCTAssertGreaterThan(plan.warmBytesAfter, ceiling,
                             "只剩在途者时接受超上限，而不是打掉正在跑的请求")
    }

    func testProtectedShardAloneOverCeilingDoesNotEvictAnything() {
        let residency = LiveSessionResidency(bytesPerToken: 20_480, fixedBytesPerSession: 64_389_120)
        let ceiling = LiveSessionResidency.byteBudget(residency: residency, override: nil)
        let plan = ResidencyGovernor.evictionPlan(
            [],
            protectedBytes: residency.estimatedBytes(processedTokens: 130_000),
            ceiling: ceiling
        )
        XCTAssertFalse(plan.fired, "本轮会话自身超上限时无从逐出，下一轮再按 LRU 结算")
        XCTAssertGreaterThan(plan.warmBytesAfter, ceiling)
    }

    func testDifferentAgentScopeIsNeverAdoptable() {
        // 隔离裁定：不同 agent 的请求之间不借用活分片，判据成立也不行。
        XCTAssertNil(SessionAdoption.choose(
            [candidate(agentId: "agent-a")], for: request(agentId: "agent-b")))
        // 未登记作用域 = 未知，未知不等于相容。
        XCTAssertNil(SessionAdoption.choose(
            [candidate(agentId: nil)], for: request(agentId: "default")))
        XCTAssertNotNil(SessionAdoption.choose(
            [candidate(agentId: "agent-a")], for: request(agentId: "agent-a")))
    }

    // MARK: - 采纳作用域（只在请求级身份之间）

    func testAdoptionScopeIsRequestScopedIdentityOnly() throws {
        // 客户端未提供 session 时 HTTPServer.makeRequestScopedSessionId 铸造
        // `<ns>-request:<uuid>`（HTTPServer.swift:2650），每轮都是新身份：
        // 只有这类身份之间允许采纳。
        let minted = try AgentExecutionKey(
            agentId: nil, sessionId: "openai-request:\(UUID().uuidString.lowercased())",
            logicalBranchId: "main")
        XCTAssertTrue(AgentExecutionKey.isRequestScopedSession(minted.storageKey))

        // 有稳定 sessionId 的两个真实会话窗口不得互相借用表示（#90 裁定 D：
        // 跨会话共享属于 #92/W2′，本窗口未开启）。
        let stable = try AgentExecutionKey(
            agentId: nil, sessionId: "chat-session-42", logicalBranchId: "main")
        XCTAssertFalse(AgentExecutionKey.isRequestScopedSession(stable.storageKey))

        // 判据是 `-request:`（带冒号的铸造形状），不是「名字里含 request」。
        let lookalike = try AgentExecutionKey(
            agentId: nil, sessionId: "user-request-7", logicalBranchId: "main")
        XCTAssertFalse(AgentExecutionKey.isRequestScopedSession(lookalike.storageKey))
    }

    // MARK: - 取消逐出（#90 C + #134 有条件驱逐）

    func testZeroEventCancelOfFreshShardWithoutEvidenceEvictsIt() {
        // 既有语义保持：本轮新建、未产出任何流事件即被取消，且拿不出保留
        // 证据（账本为空）→ 毒分片逐出。
        let decision = CancelEviction.decide(
            rawEventCount: 0, reusedSameSession: false, adoptedForeignShard: false,
            retainedLedgerTokens: 0, cacheProcessedTokens: 0)
        XCTAssertEqual(decision, .evictFreshShard)
        XCTAssertEqual(CancelEviction.freshShardMarker, "poisonedSessionEvict",
                       "观测契约不变：标记与既有一致")
    }

    func testProvenRetainedPrefixKeepsMemorySessionResident() {
        // #134：上游已把取消前缀证明可用（账本非空且与物理 cache 计数逐字
        // 相等）⇒ 不再仅凭零输出定罪，保留内存会话并走独立观测行。
        let decision = CancelEviction.decide(
            rawEventCount: 0, reusedSameSession: false, adoptedForeignShard: false,
            retainedLedgerTokens: 4_096, cacheProcessedTokens: 4_096)
        XCTAssertEqual(decision, .retainProvenPrefix)
    }

    func testLedgerAheadOfPhysicalCacheIsNotProvenRetention() {
        // 账本比 cache 多 ⇒ 计数一致性不成立，这段前缀没有物理表示背书。
        XCTAssertEqual(
            CancelEviction.decide(
                rawEventCount: 0, reusedSameSession: false, adoptedForeignShard: false,
                retainedLedgerTokens: 4_096, cacheProcessedTokens: 4_095),
            .evictFreshShard)
    }

    func testCacheProgressWithoutLedgerIsNotProvenRetention() {
        // cache 有进度但账本为空 = 未经上游证明的残留（正是 2026-09-17 挂死
        // 形状）⇒ 照旧逐出。零输出本身不定罪，但也没有证据就不保活。
        XCTAssertEqual(
            CancelEviction.decide(
                rawEventCount: 0, reusedSameSession: false, adoptedForeignShard: false,
                retainedLedgerTokens: 0, cacheProcessedTokens: 4_096),
            .evictFreshShard)
        // 读取失败（探针记 -1）同样按「无证据」处理。
        XCTAssertEqual(
            CancelEviction.decide(
                rawEventCount: 0, reusedSameSession: false, adoptedForeignShard: false,
                retainedLedgerTokens: 4_096, cacheProcessedTokens: -1),
            .evictFreshShard)
    }

    func testAdoptedShardIsEvictedOnCancelRegardlessOfEvents() {
        // #90 C：借用方无法为别人的表示背书 ⇒ 中途取消（事件数 > 0）同样逐出，
        // 不看零事件条件。
        XCTAssertEqual(
            CancelEviction.decide(
                rawEventCount: 0, reusedSameSession: true, adoptedForeignShard: true,
                retainedLedgerTokens: 0, cacheProcessedTokens: 0),
            .evictAdoptedShard)
        XCTAssertEqual(
            CancelEviction.decide(
                rawEventCount: 137, reusedSameSession: true, adoptedForeignShard: true,
                retainedLedgerTokens: 0, cacheProcessedTokens: 0),
            .evictAdoptedShard)
        XCTAssertEqual(CancelEviction.adoptedShardMarker, "adoptedCancelEvict")
    }

    func testRetentionEvidenceDoesNotOverrideAdoptionOwnership() {
        // 采纳来的分片即便计数一致也逐出：存续判据不得越过所有权判据
        // （#90 C 的裁定优先于 #134 的保活条件）。
        XCTAssertEqual(
            CancelEviction.decide(
                rawEventCount: 0, reusedSameSession: true, adoptedForeignShard: true,
                retainedLedgerTokens: 4_096, cacheProcessedTokens: 4_096),
            .evictAdoptedShard)
    }

    func testSameSessionReuseCancelKeepsShardResident() {
        // 同一身份自己的复用轮，或已产出事件的新一轮：行为与 #90 之前一致，
        // 不因本次实现扩大逐出面（保留型判定只属于「新建 + 零事件」这一支）。
        XCTAssertEqual(CancelEviction.decide(
            rawEventCount: 0, reusedSameSession: true, adoptedForeignShard: false,
            retainedLedgerTokens: 0, cacheProcessedTokens: 0), .keepResident)
        XCTAssertEqual(CancelEviction.decide(
            rawEventCount: 42, reusedSameSession: false, adoptedForeignShard: false,
            retainedLedgerTokens: 4_096, cacheProcessedTokens: 4_096), .keepResident)
    }

    // MARK: - helpers

    private func makeModelDirectory(config: [String: Any]) throws -> String {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("simigo-residency-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let data = try JSONSerialization.data(withJSONObject: config)
        try data.write(to: dir.appendingPathComponent("config.json"))
        return dir.path
    }
}
