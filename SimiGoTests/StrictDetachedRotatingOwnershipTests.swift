import Foundation
import MLX
import MLXLMCommon
import SimiGoRuntimeContract
import SimiGo2Experimental
import XCTest

@testable import SimiGo

/// `RotatingKVCache` × **严格 detached HTTP 路径** 上的所有权证明。
///
/// 与前面两个文件的分工，写清楚以免被读成重复证据：
/// - `KVCacheDetachedForkRealModelTests`（依赖层）：rotating 的复制/验证/退休/续算，
///   不经过产品路由，也不观测 `Data` owner；
/// - `KVCacheOwnershipLifetimeTests`（依赖层）：`Data` owner 的四阶段对照，但只有
///   `KVCacheSimple`，且直接调 `fork()` / `forkDetached()`；
/// - 本文件：**两者相交的那一格**——窗口化缓存 + 严格 detached 请求，走
///   `POST /v1/responses`（`require_detached_kv`），并用同一支非持有式探针判定
///   「谁还持有那块 allocation」。
///
/// 四项验收（用户指定，逐条对应一个阶段）：
/// 1. detached 后父子所有权确实分离 —— 观察点在 **fork 事务内部**（见下）；
/// 2. 父分支释放后，全部原父 owner 过期；
/// 3. child 在缓存窗口回绕后仍能真实续算（再发一轮严格 detached 请求）；
/// 4. 失败时不注册半成品分支，也不回退到共享模式。
///
/// 为什么观察点必须在 fork 事务内部：缓存写入会**重新绑定**数组
/// （`concatenated` 产生新分配）。等 HTTP 响应回来再快照，看到的是本轮生成之后的
/// 分配，既不能证明“fork 出来的副本与源分离”，也会让“源 owner 已过期”变成任何
/// 路径都成立的结论。因此本文件用 `NativeMLX.setIntegrationForkWitness` 在 child
/// 登记之后、任何写入之前抓一次快照；生产环境该钩子为 `nil`。
///
/// 三种结论始终分开：
/// - `Data` owner 过期：可观测（弱引用读到 expired）；
/// - buffer 是否离开 MLX 复用池：**未观测**；
/// - 物理页是否归还操作系统：**未观测**，且不能由前两项推导。
///
/// 门控：`SIMIGO_KV_ROTATING_MODEL=<本机 MLX 权重目录>`。缺省 `XCTSkip`。
final class StrictDetachedRotatingOwnershipTests: XCTestCase {

    private static let gateVariable = "SIMIGO_KV_ROTATING_MODEL"
    private static let evidenceName = "rotating-strict-detached-ownership.json"

    /// 窗口上限。容量决定 cache 形态（rotating）以及“能否回绕”，因此必须在任何
    /// 请求之前设定：`GenerateParameters` 只在会话创建时读一次。
    ///
    /// 取 256 不是靠“把指令留在窗口里”换来的——那是 r26–r29 的教训，已经由提示词的
    /// **结构**解决（指令放在最后一条 user 轮，见 `opening`）。这里只需要窗口有实际
    /// 容量、同时 prompt 能越过它。
    private static let window = 256
    /// 结果契约要求的绑定值：结算把 `RESULT=` 行的捕获组当作 `next_input`，所以根 ES
    /// 的 `continueState(input:)` 也必须是这个值本身，不能是 prompt 文本。
    private static let value = "7143"

    private var port = 18_560
    private var host: LOCALBAuthorizedE2E.Host!
    private let sessionID = "rotating-" + UUID().uuidString.prefix(8).lowercased()
    private var evidence: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        // 四个阶段是一条链：前一阶段失败后再读后一阶段只会得到噪声。
        continueAfterFailure = false
        RuntimeTuning.maxKVSize = Self.window
    }

    override func tearDown() {
        RuntimeTuning.maxKVSize = nil
        super.tearDown()
    }

    // MARK: - Gate

    private static func requireModel() throws -> String {
        guard let path = ProcessInfo.processInfo.environment[gateVariable],
            !path.isEmpty
        else {
            throw XCTSkip("rotating 严格 detached 所有权：需 \(gateVariable)=<权重目录>")
        }
        guard FileManager.default.fileExists(atPath: path + "/config.json") else {
            throw XCTSkip("模型不存在：\(path)")
        }
        return path
    }

    // MARK: - 用例

    func testRotatingStrictDetachedOwnershipThroughResponsesRoute() async throws {
        let modelPath = try Self.requireModel()
        let modelInfo = ModelInfo(path: modelPath, kind: .mlx)
        let identity = SimiGoProducerIdentity.identity(fromPath: modelPath)
        evidence["model"] = [
            "path": modelPath,
            "model_fingerprint": identity.model,
            "tokenizer_fingerprint": identity.tokenizer,
        ]
        evidence["window"] = ["max_kv_size": Self.window]

        let runtime = NativeMLX(info: modelInfo, config: ModelConfig())
        host = try LOCALBAuthorizedE2E.makeHost()
        try await runtime.startWithLOCALB(
            modelInfo,
            port: port,
            localbTransportIdentity: host.identity,
            localbRequestAuthorization: (
                coordinator: host.coordinator,
                trustedCheckpoint: host.checkpointProvider
            )
        )
        defer { Task { await runtime.stop() } }
        defer { runtime.setIntegrationForkWitness(nil) }

        func passCount() -> Int {
            runtime.observation.snapshot()["generate_passes"] as? Int ?? -1
        }
        func settlementCount() async throws -> Int {
            try await MainActor.run { () -> Int in
                guard let db = ExecutionStateGraphStore().esis else { return -1 }
                return try db.readSettlementReceipts().count
            }
        }

        // fork 时刻观察器：每次 fork 登记完 child、返回之前抓一次所有权快照。
        // 快照本身只持 `std::weak_ptr<Data>`，不延长任何存储的寿命。
        let witness = ForkWitness()
        runtime.setIntegrationForkWitness { event in
            let snapshot = await event.childSession.watchKVOwnership()
            witness.record(
                snapshot, target: event.targetBranch, policy: event.policy.rawValue)
        }

        // 根 ES：在 fork 路径之外结算，作为冷启动锚点（parentID == nil）。
        // 结算把结果**值**（`RESULT=<x>` 的捕获组）绑定成 next_input，所以这里
        // continueState 的 input 必须是那个值本身，而不是 prompt 文本。
        let rootID = try await MainActor.run { () -> String in
            let store = ExecutionStateGraphStore()
            let root = try store.create()
            try store.continueState(root, input: Self.value)
            let state = try XCTUnwrap(store.state(root.id))
            _ = try store.settleProducerResult(
                generatedText: "RESULT=\(Self.value)",
                boundToState: state,
                producerIdentity: identity)
            return state.id
        }

        // 提示词结构要同时满足两件事，缺一件这条臂就白跑：
        //   1. 整个 prompt 越过窗口 → `RotatingKVCache` 回绕，“回绕后续算”才被真的测到；
        //   2. 指令落在**尾部** → 窗口化裁掉的是开头，模型仍看得到要它输出的那一行。
        // 所以填充放在最前面的 user/assistant 往返里，指令是最后一条 user 轮。
        let opening: [[String: Any]] = [
            ["role": "user", "content": Self.fillerPrompt],
            ["role": "assistant", "content": Self.fillerAck],
            ["role": "user", "content": Self.instruction],
        ]

        // ---- 阶段 0：冷启动一轮，得到 esA 及其**窗口化**缓存 ----
        let cold = try await post(requestBody(
            input: opening, anchor: rootID, settle: true, carrier: "cold"))
        if cold.status != 200 {
            let diag = await diagnose(requestBody(
                input: opening, anchor: rootID, settle: true, carrier: "cold"))
            XCTFail("冷启动请求被拒绝：\(cold.raw)\n--- 同一 prompt 不结算时的模型输出 ---\n\(diag)")
            return
        }
        let esA = try XCTUnwrap(cold.childESStateID, cold.raw)
        XCTAssertTrue(liveBranches(runtime, contain: esA))

        var sourceSession: ChatSession? = try XCTUnwrap(
            runtime.integrationBranchChatSession(sessionId: sessionID, logicalBranchId: esA),
            "esA 必须由真实 ChatSession 承载，否则后面观测不到任何 KV")
        let sourceSample = await sourceSession!.probeKVStorage()
        let parentAtFork = await sourceSession!.watchKVOwnership()
        let sourceKinds = Set(sourceSample.records.map(\.cacheKind))
        let sourceRows = sourceSample.records.map(Self.rows(of:)).max() ?? 0
        let sourceProcessed = parentAtFork.processedTokenCount ?? -1

        evidence["phase0_source"] = [
            "branch": esA,
            "arrays": sourceSample.records.count,
            "owners": parentAtFork.liveIdentities.count,
            "cache_kinds": sourceKinds.sorted(),
            "rows": sourceRows,
            "processed_tokens": sourceProcessed,
            "window": Self.window,
            "wrapped": sourceProcessed > sourceRows,
            "snapshot": parentAtFork.summary(),
        ]
        XCTAssertEqual(
            parentAtFork.entries.count, sourceSample.records.count,
            "所有权快照覆盖 \(parentAtFork.entries.count) 个数组，地址级仪器看到 \(sourceSample.records.count) 个")
        XCTAssertGreaterThan(parentAtFork.entries.count, 0, "esA 没有可观测的 KV 数组")
        XCTAssertTrue(
            sourceKinds.contains("RotatingKVCache"),
            "这条臂要覆盖 RotatingKVCache，实际出现的叶子类型是 \(sourceKinds.sorted())")
        XCTAssertTrue(parentAtFork.allAlive, "fork 之前源 owner 就已过期")
        XCTAssertGreaterThan(
            sourceProcessed, sourceRows,
            "窗口没有回绕（processed=\(sourceProcessed), rows=\(sourceRows)）："
                + "后面的“回绕后仍能续算”就不成立，必须先让 prompt 超过窗口")
        // 快照只留弱引用；这个强引用会延长源会话寿命，必须在“释放父分支”之前丢掉。
        sourceSession = nil

        // ---- 阶段 1：严格 detached HTTP 请求，esA → esB ----
        // 顺序必须是 [.., assistant(上一轮回答), user(指令)]：写反了等于把上一轮的
        // 回答当成“用户说的话”，前缀也对不上缓存记录的 token 账本。
        let strictInput = opening + [
            ["role": "assistant", "content": cold.assistantText],
            ["role": "user", "content": Self.instruction],
        ]
        let strict = try await post(requestBody(
            input: strictInput, anchor: esA, settle: true, branch: "main",
            carrier: "warm", requireDetached: true))
        if strict.status != 200 {
            let diag = await diagnose(requestBody(
                input: strictInput, anchor: esA, settle: true, branch: "main",
                carrier: "warm", requireDetached: true))
            XCTFail("严格 detached 请求被拒绝：\(strict.raw)\n--- 同一 prompt 不结算时的模型输出 ---\n\(diag)")
            return
        }
        let esB = try XCTUnwrap(strict.childESStateID, strict.raw)
        XCTAssertEqual(strict.carrier["resolution"] as? String, "forked")
        XCTAssertEqual(strict.carrier["fork_policy"] as? String, "detached")
        XCTAssertEqual(strict.carrier["detached_storage_verified"] as? Bool, true)
        let isolation = try XCTUnwrap(
            strict.carrier["storage_isolation"] as? [String: Any],
            "严格请求必须公布它验证了什么：\(strict.raw)")
        let arrays = try XCTUnwrap(isolation["arrays"] as? Int)
        let copiedBytes = try XCTUnwrap(isolation["bytes"] as? Int)
        XCTAssertGreaterThan(arrays, 0)
        XCTAssertEqual(isolation["addresses_separated"] as? Int, arrays)
        XCTAssertEqual(isolation["values_matched"] as? Int, arrays)
        XCTAssertEqual(isolation["storage_separated"] as? Bool, true)
        XCTAssertEqual(isolation["values_preserved"] as? Bool, true)
        XCTAssertGreaterThan(copiedBytes, 0)
        let forkKinds = isolation["cache_kinds"] as? [String] ?? []
        XCTAssertTrue(
            forkKinds.contains("RotatingKVCache"),
            "严格 HTTP 臂复制的是窗口化缓存吗？cache kinds: \(forkKinds)")

        // 这就是本文件的核心：**fork 时刻**的 child，不是生成之后的 child。
        let childAtForkB = try XCTUnwrap(
            witness.snapshot(esB), "fork 观察器没有在 esB 登记后、写入前触发")
        let overlapAB = KVOwnershipProbe.compare(parent: parentAtFork, child: childAtForkB)
        evidence["phase1_strict_fork"] = [
            "exchange": strict.summary,
            "source_branch": esA,
            "child_branch": esB,
            "isolation": isolation,
            "fork_token_count": strict.carrier["fork_token_count"] ?? NSNull(),
            "cached_prompt_tokens": strict.cachedTokens,
            "parent": parentAtFork.summary(),
            "child_at_fork": childAtForkB.summary(),
            "overlap": overlapAB.summary(),
        ]
        XCTAssertEqual(
            childAtForkB.entries.count, parentAtFork.entries.count,
            "fork 之后子分支的数组集合与父分支不同，配对不可比")
        XCTAssertTrue(childAtForkB.allAlive, "fork 时刻 child 的 owner 就已过期")
        XCTAssertTrue(
            overlapAB.allSeparated,
            "detached fork 之后父子仍共享 \(overlapAB.shared) 个 owner：存储并未分离")
        XCTAssertEqual(
            isolation["processed_token_count"] as? Int,
            strict.carrier["fork_token_count"] as? Int,
            "被验证的副本必须覆盖 fork 携带的同一批 token")

        // 续算确实用了复制来的缓存（否则“分离”只是分离了一块没人用的存储）。
        XCTAssertGreaterThan(strict.cachedTokens, 0, "本轮没有复用任何 cache，这是一次全量重建")
        XCTAssertEqual(strict.assistantContractValue, "RESULT=\(Self.value)", strict.raw)
        XCTAssertTrue(liveBranches(runtime, contain: esB))
        XCTAssertTrue(
            liveBranches(runtime, contain: esA), "detached fork 不得顺手退休它的源分支")

        // ---- 阶段 2：释放父分支 esA，原父 owner 必须全部过期 ----
        let passesBeforeRelease = passCount()
        let owner = MLXRuntimeCarrierOwner(runtime: runtime)
        let released = try await owner.releaseExecutionCarrier(
            ExecutionCarrierRef(agentID: nil, sessionID: sessionID, branchID: esA))
        try owner.verifyCarrierUnusable(
            ExecutionCarrierRef(agentID: nil, sessionID: sessionID, branchID: esA))
        let parentAliveAfterRelease = parentAtFork.aliveKeys.count
        let parentExpiredAfterRelease = parentAtFork.expiredKeys.count
        evidence["phase2_parent_released"] = [
            "branch": esA,
            "carrier_was_live": released.carrierWasLive,
            "sessions_released": released.sessionsReleased,
            "clear_issued": released.clearIssued,
            "binding_detached": released.bindingDetached,
            "still_live_afterwards": released.stillLiveAfterwards,
            "source_live_branch": runtime.hasLiveSessionBranch(
                sessionId: sessionID, logicalBranchId: esA),
            "parent_alive": parentAliveAfterRelease,
            "parent_expired": parentExpiredAfterRelease,
            "parent_entries": parentAtFork.entries.count,
            "parent_strong_counts": Dictionary(
                parentAtFork.entries.map { ($0.key, $0.strongCount) },
                uniquingKeysWith: { a, _ in a }),
            "generate_passes": passCount(),
        ]
        XCTAssertEqual(passesBeforeRelease, passCount(), "释放分支不得触发一次生成")
        XCTAssertEqual(released.sessionsReleased, 1, "esA 应当恰好有一个存活会话")
        XCTAssertFalse(released.stillLiveAfterwards, "释放之后 esA 仍然存活")
        XCTAssertFalse(
            runtime.hasLiveSessionBranch(sessionId: sessionID, logicalBranchId: esA),
            "释放之后 esA 仍能解析到会话")
        XCTAssertEqual(
            parentAliveAfterRelease, 0,
            "detached fork 之后原父 owner 仍有 \(parentAliveAfterRelease) 个存活："
                + "还有对象持有源存储（强引用计数见上），应当继续追查持有者，"
                + "而不能以 clear() 已调用为由判定通过")
        XCTAssertEqual(parentExpiredAfterRelease, parentAtFork.entries.count)

        // ---- 阶段 3：父分支已消失，child 在自己的窗口回绕状态下续算 ----
        // esB 的缓存同样是窗口化的，且它是由 esA 的窗口副本复制而来：这一轮是
        // “copy 的 copy”在回绕之后继续真实推理。
        var sourceB: ChatSession? = try XCTUnwrap(
            runtime.integrationBranchChatSession(sessionId: sessionID, logicalBranchId: esB))
        let sampleB = await sourceB!.probeKVStorage()
        let parentB = await sourceB!.watchKVOwnership()
        let rowsB = sampleB.records.map(Self.rows(of:)).max() ?? 0
        let processedB = parentB.processedTokenCount ?? -1
        evidence["phase3_source_b"] = [
            "branch": esB,
            "arrays": parentB.entries.count,
            "rows": rowsB,
            "processed_tokens": processedB,
            "wrapped": processedB > rowsB,
            "cache_kinds": Array(Set(sampleB.records.map(\.cacheKind))).sorted(),
            "snapshot": parentB.summary(),
        ]
        XCTAssertTrue(parentB.allAlive, "释放父分支时把 child 的 owner 也带走了")
        XCTAssertGreaterThan(
            processedB, rowsB,
            "child 的窗口没有回绕（processed=\(processedB), rows=\(rowsB)），"
                + "“回绕后仍能续算”这条没有被测到")
        sourceB = nil

        let continueInput = strictInput + [
            ["role": "assistant", "content": strict.assistantText],
            ["role": "user", "content": Self.instruction],
        ]
        let grand = try await post(requestBody(
            input: continueInput, anchor: esB, settle: true, branch: "main",
            carrier: "warm", requireDetached: true))
        if grand.status != 200 {
            let diag = await diagnose(requestBody(
                input: continueInput, anchor: esB, settle: true, branch: "main",
                carrier: "warm", requireDetached: true))
            XCTFail("child 续算请求被拒绝：\(grand.raw)\n--- 同一 prompt 不结算时的模型输出 ---\n\(diag)")
            return
        }
        let esC = try XCTUnwrap(grand.childESStateID, grand.raw)
        XCTAssertEqual(grand.carrier["fork_policy"] as? String, "detached")
        XCTAssertEqual(grand.carrier["detached_storage_verified"] as? Bool, true)
        let isolationC = try XCTUnwrap(grand.carrier["storage_isolation"] as? [String: Any])
        XCTAssertEqual(isolationC["addresses_separated"] as? Int, isolationC["arrays"] as? Int)
        XCTAssertEqual(isolationC["values_matched"] as? Int, isolationC["arrays"] as? Int)
        let childAtForkC = try XCTUnwrap(witness.snapshot(esC))
        let overlapBC = KVOwnershipProbe.compare(parent: parentB, child: childAtForkC)
        evidence["phase3_child_continues"] = [
            "exchange": grand.summary,
            "parent_branch": esB,
            "child_branch": esC,
            "isolation": isolationC,
            "fork_token_count": grand.carrier["fork_token_count"] ?? NSNull(),
            "cached_prompt_tokens": grand.cachedTokens,
            "overlap": overlapBC.summary(),
        ]
        XCTAssertTrue(overlapBC.allSeparated, "第二次 detached fork 仍共享 \(overlapBC.shared) 个 owner")
        XCTAssertTrue(childAtForkC.allAlive)
        XCTAssertGreaterThan(
            grand.cachedTokens, 0,
            "续算把 parent 的窗口整段丢弃了：fork 携带的 KV 没有被这一轮使用")
        XCTAssertEqual(grand.assistantContractValue, "RESULT=\(Self.value)", grand.raw)
        XCTAssertTrue(liveBranches(runtime, contain: esC))
        XCTAssertTrue(
            liveBranches(runtime, contain: esB),
            "父分支 esA 已释放，esB 仍必须是 esC 的活源（否则第三阶段读的是无源复制）")

        // ---- 阶段 4：失败臂 —— 严格请求拿不到 detached 时拒绝，且不留残枝 ----
        _ = try await owner.releaseExecutionCarrier(
            ExecutionCarrierRef(agentID: nil, sessionID: sessionID, branchID: esC))
        try owner.verifyCarrierUnusable(
            ExecutionCarrierRef(agentID: nil, sessionID: sessionID, branchID: esC))
        let passesBeforeRefusal = passCount()
        let settlementsBefore = try await settlementCount()
        let liveBeforeRefusal = Set(liveBranches(runtime))

        let refused = try await post(requestBody(
            input: continueInput + [
                ["role": "assistant", "content": grand.assistantText],
                ["role": "user", "content": Self.instruction],
            ],
            anchor: esC, settle: true, branch: "main",
            carrier: "warm", requireDetached: true))
        let settlementsAfter = try await settlementCount()
        evidence["phase4_refused"] = [
            "exchange": refused.summary,
            "carrier_payload": refused.carrier,
            "generate_passes_before": passesBeforeRefusal,
            "generate_passes_after": passCount(),
            "settlements_before": settlementsBefore,
            "settlements_after": settlementsAfter,
            "live_branches_before": Array(liveBeforeRefusal).sorted(),
            "live_branches_after": liveBranches(runtime),
        ]
        XCTAssertEqual(refused.status, 422, refused.raw)
        XCTAssertEqual(refused.errorKind, "CARRIER_DETACHED_UNAVAILABLE")
        XCTAssertEqual(refused.reasonCode, "detached_unavailable")
        XCTAssertNil(refused.childESStateID, "被拒绝的严格请求不得交出 child ES 身份")
        XCTAssertEqual(passCount(), passesBeforeRefusal, "被拒绝的严格续算不得生成")
        XCTAssertEqual(settlementsAfter, settlementsBefore, "被拒绝的严格续算不得结算")
        XCTAssertEqual(
            Set(liveBranches(runtime)), liveBeforeRefusal,
            "被拒绝的严格 fork 不得登记任何分支（半成品或共享回退都算登记）")
        // “不回退到共享模式”在产品上的可读形式：拒绝载荷里没有任何存储声明。
        XCTAssertNil(refused.carrier["fork_policy"], "拒绝载荷出现了 fork_policy：\(refused.carrier)")
        XCTAssertNil(refused.carrier["storage_isolation"], "拒绝载荷出现了 storage_isolation")
        XCTAssertNotEqual(refused.carrier["resolution"] as? String, "forked")

        evidence["claims"] = [
            "child_owner_separated_at_fork": overlapAB.allSeparated ? "observed" : "not_observed",
            "second_fork_owner_separated_at_fork": overlapBC.allSeparated ? "observed" : "not_observed",
            "source_owner_expired_after_branch_release":
                parentAliveAfterRelease == 0 ? "observed" : "not_observed",
            "child_continued_after_window_wrapped":
                (processedB > rowsB && grand.cachedTokens > 0) ? "observed" : "not_observed",
            "refusal_left_no_branch": Set(liveBranches(runtime)) == liveBeforeRefusal
                ? "observed" : "not_observed",
            "buffer_left_mlx_pool": "not_observed",
            "physical_pages": "not_observed",
        ]
        evidence["boundary"] = [
            "verified": [
                "at the fork transaction (child registered, before any write) every KV array of the"
                    + " child has its own `Data` owner, different from the source's",
                "after the source BRANCH is released, every owner observed on the source before the"
                    + " fork is expired, while the child keeps working",
                "a second strict detached request from the child succeeds on a wrapped window and"
                    + " reuses a non-zero cached prefix",
                "a strict request that cannot fork is refused with no branch registered, no"
                    + " generation, no settlement and no storage claim in the payload",
            ],
            "not_verified": [
                "the released buffers left MLX's reusable pool",
                "the operating system reclaimed physical pages",
                "the draft (speculative) cache: none in this arms' sessions",
                "KVCacheSimple through this route (covered by the previous slice, not re-run here)",
            ],
            "notes": [
                "the fork witness runs inside the fork transaction because the first write rebinds"
                    + " the cache arrays; a post-response snapshot would describe generation output",
                "the probe stores std::weak_ptr<Data> only; every captured array is dropped at once",
                "SIMIGO_PREFIX_POOL=0 is used so a cross-session pool cannot hold the source arrays"
                    + " and make owner expiry unattributable",
            ],
        ]
        evidence["trace_tail"] = traceTail()
        let verdict = (parentAliveAfterRelease == 0 && overlapAB.allSeparated
            && overlapBC.allSeparated && processedB > rowsB && grand.cachedTokens > 0)
            ? "ROTATING_STRICT_DETACHED_OWNERSHIP_VERIFIED"
            : "ROTATING_STRICT_DETACHED_OWNERSHIP_INCOMPLETE"
        evidence["verdict"] = verdict
        XCTAssertEqual(verdict, "ROTATING_STRICT_DETACHED_OWNERSHIP_VERIFIED")
        try writeEvidence()
    }

    // MARK: - fork 时刻见证

    /// 收集 fork 事务内抓到的 child 快照。观察器是 `@Sendable`，所以用一个带锁的
    /// 盒子；快照本身不持有任何 MLX 存储。
    private final class ForkWitness: @unchecked Sendable {
        private let lock = NSLock()
        private var snapshots: [String: KVOwnershipSnapshot] = [:]
        private var policies: [String: String] = [:]

        func record(_ snapshot: KVOwnershipSnapshot, target: String, policy: String) {
            lock.lock()
            defer { lock.unlock() }
            snapshots[target] = snapshot
            policies[target] = policy
        }

        func snapshot(_ target: String) -> KVOwnershipSnapshot? {
            lock.lock()
            defer { lock.unlock() }
            return snapshots[target]
        }
    }

    // MARK: - 形状

    /// 可见行数：`[B, kvHeads, rows, headDim]`。回绕的证据是
    /// `processedTokenCount > rows`，因为 ring 满了以后行数被容量钉住。
    private static func rows(of record: KVStorageSample.ArrayRecord) -> Int {
        record.shape.count >= 3 ? record.shape[2] : (record.shape.last ?? 0)
    }

    // MARK: - HTTP exchange

    private struct Exchange {
        let status: Int
        let raw: String
        let json: [String: Any]

        var assistantText: String {
            guard let output = json["output"] as? [[String: Any]] else { return "" }
            for item in output {
                guard let content = item["content"] as? [[String: Any]] else { continue }
                if let text = content.first?["text"] as? String { return text }
            }
            return ""
        }

        var assistantContractValue: String {
            assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var usage: [String: Any] { json["usage"] as? [String: Any] ?? [:] }
        var cachedTokens: Int {
            let details = usage["input_tokens_details"] as? [String: Any] ?? [:]
            return details["cached_tokens"] as? Int ?? -1
        }
        var settlementPayload: [String: Any] {
            json["continuation_settlement"] as? [String: Any] ?? [:]
        }
        /// 产品发布的“这次请求的载体怎么了”，不从 200 反推。
        var carrier: [String: Any] {
            json["continuation_carrier"] as? [String: Any] ?? [:]
        }
        var errorKind: String? {
            (json["error"] as? [String: Any])?["error_kind"] as? String
        }
        var reasonCode: String? {
            (json["error"] as? [String: Any])?["reason_code"] as? String
        }
        var childESStateID: String? {
            json["child_es_state_id"] as? String
                ?? settlementPayload["child_es_state_id"] as? String
        }

        var summary: [String: Any] {
            [
                "status": status,
                "assistant_text": assistantText,
                "assistant_contract_value": assistantContractValue,
                "cached_tokens": cachedTokens,
                "child_es_state_id": childESStateID ?? "-",
                "carrier": carrier,
                "error_kind": errorKind ?? "-",
                "reason_code": reasonCode ?? "-",
                "body_prefix": String(raw.prefix(400)),
            ]
        }
    }

    private func requestBody(
        input: [[String: Any]], anchor: String?, settle: Bool, branch: String = "main",
        carrier: String? = nil, requireDetached: Bool? = nil
    ) -> [String: Any] {
        var json: [String: Any] = [
            "model": "rotating-ownership",
            "input": input,
            "stream": false,
            "session_id": sessionID,
            "logical_branch_id": branch,
            "temperature": 0,
            "max_tokens": 24,
        ]
        if let anchor { json["previous_es_state_id"] = anchor }
        if settle { json["continuation_settle"] = true }
        if let carrier { json["continuation_carrier"] = carrier }
        if let requireDetached { json["require_detached_kv"] = requireDetached }
        return json
    }

    private func post(_ json: [String: Any]) async throws -> Exchange {
        let data = try JSONSerialization.data(withJSONObject: json)
        let (payload, response) = try await LOCALBAuthorizedE2E.send(
            host: host, port: port, method: "POST", path: "/v1/responses",
            contentType: "application/json", body: data)
        let raw = String(decoding: payload, as: UTF8.self)
        let parsed = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] ?? [:]
        return Exchange(status: response.statusCode, raw: raw, json: parsed)
    }

    /// 被拒时把“模型到底说了什么”捞出来：主路径走结算，结算失败只会回
    /// `NATIVE_RESULT_CONTRACT_REJECTED`，正文被吃掉。同一条 prompt 再走一次
    /// **不结算**的请求（`continuation_settle` 缺省即 false），就能拿到原始输出。
    /// 它只在断言失败之后调用，不参与判定。
    private func diagnose(_ body: [String: Any]) async -> String {
        var probe = body
        probe.removeValue(forKey: "continuation_settle")
        guard let exchange = try? await post(probe) else {
            return "(diagnostic request itself failed)"
        }
        return "status=\(exchange.status) text=\(exchange.assistantText.debugDescription)"
    }

    private func liveBranches(_ runtime: NativeMLX) -> [String] {
        runtime.listSessionBranches(sessionId: sessionID).liveBranches
    }

    private func liveBranches(_ runtime: NativeMLX, contain branch: String) -> Bool {
        liveBranches(runtime).contains { $0 == branch || $0.hasPrefix(branch + "#") }
    }

    // MARK: - 提示词

    /// 填充材料：唯一作用是让 prompt 越过窗口（256），使 `RotatingKVCache` 真的回绕。
    /// 它**不承载任何指令**——窗口化之后模型只看得到最后 `window` 个 token，写在这里的
    /// 要求会被裁掉。r26–r29 的四次 `PRODUCER_RESULT_FIELD_MISSING` 就是这个原因：
    /// 指令留在最前面的 system 里，模型看到的是被截断的上下文。
    private static let fillerPrompt: String = {
        var lines: [String] = ["Reference material follows; never quote or repeat it."]
        for index in 0 ..< 14 {
            lines.append(
                "Reference \(index): the carrier keeps its own copy of every key and value, "
                    + "and that copy survives the source branch being released.")
        }
        return lines.joined(separator: "\n")
    }()

    /// 填充往返的应答。短，只为让填充材料成为一段**已完结**的对话，而不是一个待回答
    /// 的问题——否则模型会去回答它，而不是执行最后的指令。
    private static let fillerAck = "Understood."

    /// 最后一条 user 轮，也就是整个 prompt 的尾部：窗口化只保尾部，指令必须在这里。
    /// 句式取本仓原生产出用例已经验证过的那一条，不自创。
    private static var instruction: String {
        "Output exactly one line and nothing else: RESULT=\(Self.value)"
    }

    // MARK: - 证据

    private func evidenceURL() -> URL {
        if let storePath = ProcessInfo.processInfo.environment["SIMIGO_STATE_GRAPH_STORE"],
            !storePath.isEmpty
        {
            return URL(fileURLWithPath: (storePath as NSString).deletingLastPathComponent)
                .appendingPathComponent(Self.evidenceName)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.evidenceName)
    }

    /// 用例通过但证据没落盘，等于什么都没测出来：写盘失败必须让用例失败。
    private func writeEvidence() throws {
        evidence["session_id"] = sessionID
        evidence["gates"] = [
            Self.gateVariable: ProcessInfo.processInfo.environment[Self.gateVariable] ?? "-",
            "SIMIGO_PREFIX_POOL": ProcessInfo.processInfo.environment["SIMIGO_PREFIX_POOL"] ?? "-",
            "SIMIGO_STATE_GRAPH_STORE":
                ProcessInfo.processInfo.environment["SIMIGO_STATE_GRAPH_STORE"] ?? "-",
        ]
        evidence["observed_at"] = ISO8601DateFormatter().string(from: Date())
        let url = evidenceURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        print("[KV-ROTATING-OWNERSHIP] evidence written to \(url.path)")
    }

    private func traceTail(limit: Int = 160) -> [String] {
        RuntimeTraceLogger.shared.flush()
        let url = SimiGoPaths.logs.appendingPathComponent("native_mlx_trace.log")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let marks = ["[MLX]", "[PROTOCOL]", "[CARRIER]", "[EXEC]"]
        let hits = text.split(separator: "\n").map(String.init).filter { line in
            marks.contains { line.contains($0) }
                && (line.contains(sessionID) || line.contains("continuation_")
                    || line.contains("branchRelease"))
        }
        return Array(hits.suffix(limit))
    }
}
