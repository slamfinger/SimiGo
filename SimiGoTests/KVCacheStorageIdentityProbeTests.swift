import Foundation
import MLX
@_spi(DetachedForkVerification) import MLXLMCommon
import MLXLLM
import XCTest

/// 原生 KV 存储身份探针：在**真实** `ChatSession.fork()` 上观测父子分支的底层存储。
///
/// 这个用例不回答"物理内存是否归还"，也不回答"allocation 的最后一个所有者是谁"。
/// 它只回答三个问题，并且分别记录、分别定级：
///
///   阶段 A  fork 后父子分支持有的对应 KV 数组，是否读到同一段字节？
///   阶段 B  父分支被释放后，child 继续使用的存储身份是否与释放前一致，且仍能续算？
///   阶段 C  当前依赖能否观测 allocation 的引用计数 / 最后引用释放？不能就写
///           `ADDRESS_ONLY`，不升级为"物理释放已证明"。
///
/// 为什么必须先测：`KVCache.copy()` 的文档说"独立深拷贝"，`KVCacheSimple.copy()`
/// 的实现是 `state.map { $0[.ellipsis] }` —— 一句切片表达式。两者的矛盾不能靠读源码
/// 裁决，只能靠在**实际依赖版本**里采样执行后的存储。
///
/// 仪器边界（决定了什么结论可以说）：
/// - 地址直接读 `mlx_array_data_uint8`（数组自己的 buffer），**不**经
///   `asData(access: .noCopy).data.baseAddress`。后者看起来更“不拷贝”，实测却错了：
///   Swift `Data` 在 ≤ 14 字节时把内容**内联**在值里，`baseAddress` 指向的是那个
///   `Data` 自己的存储。后果是同一个量化 cache 的四个 8 字节 `scales`/`biases` 数组
///   报出同一个地址（一个栈槽），而它们的数值摘要四个都不同；≥ 16 字节时两者才一致，
///   所以多 KB 的注意力数组从未暴露这个缺陷。
/// - `.noCopyIfContiguous` 同样不能用：它遇到非连续数组会静默退回复制，那样每个
///   地址都是一个新临时对象，“不同地址”就会被误读成“独立存储”。
/// - 地址只在一个样本的存活期内有意义，绝不跨进程/跨运行/跨缓存重写持久化。
/// - 因此本用例先做**同一 session 的两次采样必须自洽**的前置校验：如果同一个 session
///   两次采样都读不到相同地址，说明 getter 在造临时副本，任何跨 session 比较都不成立，
///   结论只能是 `C_UNRESOLVED`。
final class KVCacheStorageIdentityProbeTests: XCTestCase {

    // MARK: - 模型与输入

    /// 与 mlx-swift-lm 自带 `ChatSessionTests` 同级的最小 Gemma3：8 层、vocab 100。
    /// 8 层 + `slidingWindowPattern = 6` 是有意的：让顶层同时出现
    /// `KVCacheSimple` 与 `RotatingKVCache` 两种叶子，避免只测到单一实现。
    private static func makeTinyModel() -> ModelContext {
        let config = Gemma3TextConfiguration(
            modelType: "text",
            hiddenSize: 64, hiddenLayers: 8, intermediateSize: 64, attentionHeads: 4,
            headDim: 64,
            rmsNormEps: 0.00001, vocabularySize: 100, kvHeads: 4,
            ropeTheta: 1_000_000, ropeLocalBaseFreq: 10_000,
            ropeTraditional: false, queryPreAttnScalar: 256,
            slidingWindow: 512, slidingWindowPattern: 6,
            maxPositionEmbeddings: 32768
        )
        let model = Gemma3TextModel(config)
        // 权重是随机的：本用例只关心存储身份与缓存推进，不关心生成质量。
        // 但惰性权重必须先在单线程里求值，否则并发取样时各层可能各自兑现。
        eval(model)

        let tokenizer = ProbeTokenizer()
        return .init(
            configuration: ModelConfiguration(id: "simigo-kv-storage-probe-tiny"),
            model: model,
            processor: ProbeInputProcessor(tokenizer: tokenizer),
            tokenizer: tokenizer)
    }

    /// 每个标量映射到 `1...80`，加上模板标记也全部落在 vocab 100 以内。
    private struct ProbeTokenizer: Tokenizer {
        var bosToken: String? = nil
        /// 不给 eos：让每次生成都跑满 `maxTokens`，避免随机权重恰好早早命中 eos
        /// 而让"缓存是否推进"变成偶发断言。
        var eosToken: String? = nil
        var unknownToken: String? = nil

        func encode(text: String, addSpecialTokens: Bool) -> [Int] {
            text.unicodeScalars.map { Int($0.value) % 80 + 1 }
        }

        func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
            tokenIds.map(String.init).joined(separator: " ")
        }

        func convertTokenToId(_ token: String) -> Int? { nil }
        func convertIdToToken(_ id: Int) -> String? { String(id) }

        func applyChatTemplate(
            messages: [[String: any Sendable]],
            tools: [[String: any Sendable]]?,
            additionalContext: [String: any Sendable]?
        ) throws -> [Int] {
            var tokens: [Int] = []
            for message in messages {
                let role = message["role"] as? String
                switch role {
                case "system": tokens.append(96)
                case "tool": tokens.append(98)
                case "assistant": tokens.append(94)
                default: tokens.append(97)
                }
                let content = message["content"] as? String ?? ""
                tokens.append(contentsOf: encode(text: content, addSpecialTokens: false))
                if role != "assistant" { tokens.append(95) }
            }
            tokens.append(94)  // assistant 生成标记
            return tokens
        }
    }

    private struct ProbeInputProcessor: UserInputProcessor {
        let tokenizer: any Tokenizer
        let configuration = ModelConfiguration(id: "simigo-kv-storage-probe-tiny")
        let messageGenerator = DefaultMessageGenerator()

        func prepare(input: UserInput) throws -> LMInput {
            let messages = messageGenerator.generate(from: input)
            let tokens = try tokenizer.applyChatTemplate(
                messages: messages,
                tools: input.tools,
                additionalContext: input.additionalContext)
            return LMInput(text: .init(tokens: MLXArray(tokens)))
        }
    }

    private static func generationParameters() -> GenerateParameters {
        GenerateParameters(maxTokens: 6, temperature: 0, topP: 0)
    }

    /// 弱持有父分支，用来证明它确实被释放，同时探针自己不延长它的生命周期。
    private final class WeakSession {
        weak var value: ChatSession?

        init(_ value: ChatSession) {
            self.value = value
        }
    }

    // MARK: - 用例 1：仪器自检

    /// 如果仪器连"构造上必然共享"的一对数组都判成不同地址，那么后面任何
    /// "父子独立"的结论都不可信。这里同时验证它**能**分辨真正的独立分配。
    func testProbeSeparatesSharedViewFromIndependentAllocation() throws {
        let base = MLXArray((0 ..< 96).map { Float($0) }).reshaped([2, 3, 4, 4])
        let view = base[.ellipsis]
        let independent = MLXArray((0 ..< 96).map { Float($0) }).reshaped([2, 3, 4, 4])
        eval([base, view, independent])

        let records = KVStorageProbe.sample([base, view, independent])
        XCTAssertEqual(records.count, 3)

        for record in records {
            XCTAssertTrue(
                record.isComparable,
                "自检失败：\(record.role) 读不到稳定地址（address=\(record.address) "
                    + "stable=\(record.addressStable)）。此时任何跨 session 比较都不可用。")
            XCTAssertEqual(record.shape, [2, 3, 4, 4])
            XCTAssertEqual(record.byteCount, 96 * 4)
        }

        // `.ellipsis` 视图与基数组共享字节；两个分别构造的数组同时存活，必然不同址。
        XCTAssertEqual(
            records[0].address, records[1].address,
            "`array[.ellipsis]` 是一个视图，必须与基数组同址，否则探针无法观测共享。")
        XCTAssertNotEqual(
            records[0].address, records[2].address,
            "两个同时存活的独立数组不可能同址，否则探针无法分辨独立分配。")
    }

    // MARK: - 用例 2：真实 fork 的 A / B / C 三阶段

    /// 一条连续的生命周期：同 session 写入 → fork → 父子同活采样（A）→
    /// 释放父分支、保留 child 并继续续算（B）→ 定级 allocation 可观测性（C）。
    ///
    /// 三个相位必须在同一个 session 生命周期内完成，所以是一个用例而不是三个：
    /// 分成多个用例会让 XCTest 重排执行顺序，阶段 B 断言的前提就不存在了。
    func testForkStorageIdentityAcrossParentRelease() async throws {
        let model = Self.makeTinyModel()
        var evidence: [String: Any] = [
            "probe": "KVCacheStorageIdentityProbe",
            "test": "testForkStorageIdentityAcrossParentRelease",
            "model": [
                "family": "Gemma3TextModel",
                "hidden_layers": 8,
                "vocabulary_size": 100,
                "kv_heads": 4,
                "head_dim": 64,
                "sliding_window": 512,
                "sliding_window_pattern": 6,
                "weights": "random (structural probe, not a quality test)",
            ],
        ]

        // 父分支：先真的写满一次 prefill + 6 个生成 token，让缓存不是空的。
        var parent: ChatSession? = ChatSession(
            model, generateParameters: Self.generationParameters())
        let firstTurn = try await parent!.respond(to: "parent branch seed prompt")
        let parentBeforeFork = await parent!.probeKVStorage()
        let statusBeforeFork = try await parent!.cacheStatus()
        XCTAssertFalse(
            parentBeforeFork.records.isEmpty,
            "父分支在生成之后必须已实现缓存；空样本说明探针没有看到任何 KV。")
        XCTAssertTrue(
            parentBeforeFork.isComparable,
            "父分支采样不可比较（逐条见证据），仪器在此环境下不可用。")

        // 同一 session 的两次采样必须自洽。这是整个用例的前置条件：若 getter 每次
        // 返回新临时副本，跨 session 的"不同地址"就只是仪器的产物。
        let parentResample = await parent!.probeKVStorage()
        let selfOverlap = KVStorageProbe.compare(parentBeforeFork, parentResample)
        XCTAssertTrue(
            selfOverlap.isFullyShared,
            "同一 session 两次采样不同址（\(selfOverlap.summary)）：getter 在造临时副本，"
                + "跨 session 比较无意义。")

        // ---- 阶段 A：fork 之后，父子同时存活 ----
        let child = await parent!.fork()
        let parentAtFork = await parent!.probeKVStorage()
        let childAtFork = await child.probeKVStorage()
        let childResample = await child.probeKVStorage()

        // fork 本身不应改写父分支的存储。
        let forkEffect = KVStorageProbe.compare(parentBeforeFork, parentAtFork)
        // child 自己的两次采样也必须自洽，否则下面的 compare 不可读。
        let childSelf = KVStorageProbe.compare(childAtFork, childResample)
        // 核心观测：父子对应数组是否读到同一段字节。
        let parentVsChild = KVStorageProbe.compare(parentAtFork, childAtFork)

        XCTAssertTrue(
            forkEffect.isFullyShared,
            "fork() 改写了父分支的存储身份（\(forkEffect.summary)），"
                + "说明复制过程发生了就地写或重新分配。")
        XCTAssertTrue(
            childSelf.isFullyShared,
            "child 两次采样不同址（\(childSelf.summary)），跨 session 比较不可读。")
        XCTAssertFalse(parentVsChild.pairs.isEmpty, "父子没有任何可配对的记录。")

        let phaseA = Self.relation(parentVsChild)
        evidence["phase_a"] = [
            "question": "fork 后父子分支持有的对应 KV 数组，是否读到同一段字节？",
            "parent_vs_child": Self.json(parentVsChild, verdict: phaseA),
            "fork_did_not_disturb_parent": Self.json(forkEffect),
            "child_resample_self_consistent": Self.json(childSelf),
            "records_parent_at_fork": Self.records(parentAtFork),
            "records_child_at_fork": Self.records(childAtFork),
            "cache_kinds": Array(Set(parentAtFork.records.map(\.cacheKind))).sorted(),
            "processed_tokens": [
                "parent": parentAtFork.processedTokenCount.map { $0 as Any } ?? NSNull(),
                "child": childAtFork.processedTokenCount.map { $0 as Any } ?? NSNull(),
            ],
            "first_turn_characters": firstTurn.count,
        ]

        // ---- 阶段 B：释放父分支，child 保持存活 ----
        // 探针不持强引用：`probeKVStorage()` 只返回纯值记录，样本里既没有数组也没有会话。
        let watchingParent = WeakSession(parent!)
        parent = nil
        XCTAssertNil(
            watchingParent.value,
            "父分支 ChatSession 仍被强引用持有：探针本身泄漏了引用，阶段 B 的观测无效。")

        let childAfterRelease = await child.probeKVStorage()
        let survived = KVStorageProbe.compare(childAtFork, childAfterRelease)

        // 存储身份在父分支消失后保持不变，且因为 child 仍持有该数组，这段字节在两次
        // 采样之间不可能被回收再复用。
        XCTAssertTrue(
            survived.isFullyShared,
            "父分支释放后 child 的存储身份发生变化（\(survived.summary)）。")
        XCTAssertEqual(
            childAfterRelease.processedTokenCount, childAtFork.processedTokenCount,
            "父分支释放不应改变 child 的缓存进度。")

        // child 必须真的能在旧载体消失后继续算，而不只是"还拿着一个地址"。
        let childTurn = try await child.respond(to: "continue on the child branch")
        let childAfterTurn = await child.probeKVStorage()
        let advanced =
            (childAfterTurn.processedTokenCount ?? 0) > (childAfterRelease.processedTokenCount ?? 0)
        // 续算必然要往缓存里写（append）。若写完之后地址仍是同一个，说明写入直接落在
        // 它从父分支继承来的那段 buffer 上（没有 copy-on-write）；若地址变了，说明
        // 写入自身触发了一次复制。这个区别决定了"共享"是否只在 fork 那一刻成立。
        let afterAppend = KVStorageProbe.compare(childAfterRelease, childAfterTurn)

        evidence["phase_b"] = [
            "question": "父分支释放后，child 的存储身份是否不变，且仍能续算？",
            "parent_object_deallocated": true,
            "child_storage_survived_parent_release": Self.json(survived),
            "child_generated_after_release": !childTurn.isEmpty,
            "child_generated_text_length": childTurn.count,
            "cache_advanced_after_release": advanced,
            "child_storage_after_append": Self.json(afterAppend),
            "processed_tokens": [
                "at_fork": childAtFork.processedTokenCount.map { $0 as Any } ?? NSNull(),
                "after_parent_release":
                    childAfterRelease.processedTokenCount.map { $0 as Any } ?? NSNull(),
                "after_child_turn":
                    childAfterTurn.processedTokenCount.map { $0 as Any } ?? NSNull(),
            ],
            "child_arrays_after_append": Self.records(childAfterTurn),
        ]

        XCTAssertTrue(
            advanced,
            "child 在父分支释放后没有推进缓存（\(childAfterTurn.processedTokenCount ?? -1) "
                + "<= \(childAfterRelease.processedTokenCount ?? -1)），续算未被证明。")

        // ---- 阶段 C：allocation 生命周期是否可观测 ----
        // MLX Swift 暴露的是 dtype/shape/strides/nbytes 与进程级 Memory 计数器，
        // 没有 per-allocation 身份，也没有引用计数。地址只能证明"同一段字节在两次
        // 采样之间被两个对象读到"，不能证明"最后一个所有者已释放"。
        evidence["phase_c"] = [
            "question": "allocation 的引用计数与最后引用释放是否可观测？",
            "allocation_lifetime_observability": "ADDRESS_ONLY",
            "observable": [
                "MLXArray.nbytes/dtype/shape/strides",
                "mlx_array_data_uint8 via asData(access: .noCopy) — 元素 0 的宿主地址",
                "MLX.Memory.activeMemory/cacheMemory/peakMemory — 进程级，不可归因",
            ],
            "not_observable": [
                "per-allocation identity",
                "retain/release count",
                "the moment the last owner is released",
                "OS page reclaim after that release",
            ],
            "allocator_at_child_turn": [
                "active_bytes": childAfterTurn.allocator.activeBytes,
                "cached_bytes": childAfterTurn.allocator.cachedBytes,
                "peak_bytes": childAfterTurn.allocator.peakBytes,
            ],
        ]

        // ---- 汇总 ----
        let verdict: String
        switch phaseA {
        case "SHARED_ALL", "MIXED":
            verdict = "B_SHARED_STORAGE"
        case "INDEPENDENT_ALL":
            verdict = "A_INDEPENDENT_STORAGE"
        default:
            verdict = "C_UNRESOLVED"
        }
        evidence["verdict"] = verdict
        evidence["verdict_meaning"] = [
            "A_INDEPENDENT_STORAGE":
                "fork 后所有对应数组都不同址：当前机制已提供存储隔离，不加深拷贝，"
                + "继续追踪释放后的生命周期。",
            "B_SHARED_STORAGE":
                "fork 后至少一部分对应数组同址：旧 allocation 仍被 child 使用，"
                + "需要独立复制策略才能让父分支释放有意义。",
            "C_UNRESOLVED":
                "拓扑不匹配或地址不自洽：不给 ChatSession 加 ObjectIdentifier 冒充身份，"
                + "保留 NOT_INSTRUMENTED 并继续向 MLXArray/allocation 所有权边界下探。",
        ][verdict]
        evidence["cache_status_before_fork"] = [
            "phase": "\(statusBeforeFork.phase)",
            "processed_token_count":
                statusBeforeFork.processedTokenCount.map { $0 as Any } ?? NSNull(),
            "layers": statusBeforeFork.layers.map { layer in
                ["path": layer.path, "kind": "\(layer.kind)"]
            },
        ]
        evidence["not_proven"] = [
            "physical_kv_page_reclaim":
                "NOT_OBSERVED：本探针只读地址，allocation 生命周期与 OS 归还物理页都不在观测面内。",
            "exclusive_parent_ownership":
                "UNKNOWN：同址只能说明两次采样读到同一段字节；父子是否共同持有该 allocation "
                + "的引用，需要 MLX 暴露引用计数才能判定。",
            "address_equality_is_not_ownership":
                "地址相等是观测，不是所有权证明；唯一可说的是 child 在父分支消失后仍读到同一段字节。",
        ]

        try Self.writeEvidence(evidence)

        // 本切片的断言只到"可判定"为止，不对共享关系预设结论：
        // 结论由证据文件里的 phase_a 决定，生产复制策略不在本切片修改范围内。
        XCTAssertTrue(
            ["A_INDEPENDENT_STORAGE", "B_SHARED_STORAGE", "C_UNRESOLVED"].contains(verdict),
            "未知判定：\(verdict)")
    }

    // MARK: - 用例 3：父分支存活期间的 child 首次写入隔离

    /// 已判定：fork 当刻 16/16 同址；父释放后 child 仍持原地址；child 首次写入后 16/16 换址。
    /// 仍未判定：**child 写入时，父分支读到的数据有没有变**。
    ///
    /// 地址相等只说明“两次采样从同一段字节的起点开始读”，说明不了“写进去的是同一段字节”。
    /// 所以这一格用 `includeValues` 取每层 K/V 的数值摘要，在写入前后各读一次父分支。
    ///
    /// 两个子情形，区别只在“写入落在父分支可见范围的哪里”：
    ///   A 自然续算：child 沿 fork 后的 transcript 直接回复一句。
    ///   B 改写追问：child 的 transcript 在父分支已缓存的部分内分叉，reuse 模式应为 `rewind`。
    /// 两者的写入起点都由模型路径自报的 `cachedPromptTokenCount` 决定，**不预先假定**：
    /// 父分支尾部那几个生成 token 是模板重渲染无法复现的，所以即使 A 也会回退到
    /// 共同前缀（证据里就是 `rewind`）。哪个子情形真正把写入推进了父分支可见范围，
    /// 由 `rows_overlapping_parent_visible_range` 说话，不靠预设。
    /// 只有重叠的写入能检验隔离；不重叠的那个只能证明“无从看见”。
    ///
    /// 父分支从第一个断言到最后一个断言都由测试作用域强持有，不交给弱引用观察：
    /// 本用例的前提就是它一直活着。
    func testChildWriteDoesNotChangeParentVisibleData() async throws {
        let model = Self.makeTinyModel()
        let parent = ChatSession(model, generateParameters: Self.generationParameters())
        let parentSeed = "isolation parent seed prompt"
        _ = try await parent.respond(to: parentSeed)

        // ---- 父分支基线 ----
        let parentBaseline = await parent.probeKVStorage(includeValues: true)
        let parentBaselineAgain = await parent.probeKVStorage(includeValues: true)
        let baselineStable = KVStorageProbe.compare(parentBaseline, parentBaselineAgain)
        // 摘要必须自身确定：同一个 session 连续两次读到同样的数值，否则后面的
        // “数值没变”可能只是哈希本身不稳定。
        XCTAssertTrue(
            baselineStable.isValueFullyUnchanged,
            "同一 session 连续两次取数值摘要不一致（\(baselineStable.summary)）："
                + "摘要不可用，本用例无法判定隔离。")
        XCTAssertTrue(
            parentBaseline.isComparable,
            "父分支基线不可比较（逐条见记录），仪器在此环境下不可用。")
        XCTAssertFalse(parentBaseline.records.isEmpty, "父分支没有已实现的 KV 数组。")

        let parentRows = parentBaseline.processedTokenCount ?? 0
        XCTAssertGreaterThan(parentRows, 0, "父分支基线里没有任何缓存行。")

        // ---- 两个分支都在 fork 当刻与父分支同址同值 ----
        let appendChild = await parent.fork()
        let parentAtFork = await parent.probeKVStorage(includeValues: true)
        let appendChildAtFork = await appendChild.probeKVStorage(includeValues: true)
        // 窗口 = 父分支可见行数：写入后 child 行数会变，整数组摘要就不同形了。
        let appendChildWindowAtFork = await appendChild.probeKVStorage(
            includeValues: true, valueRows: parentRows)
        let forkEffect = KVStorageProbe.compare(parentBaseline, parentAtFork)
        let sharedAtFork = KVStorageProbe.compare(parentAtFork, appendChildAtFork)
        XCTAssertTrue(
            forkEffect.isValueFullyUnchanged,
            "fork() 改变了父分支自己的数值（\(forkEffect.summary)），前提不成立。")
        XCTAssertEqual(
            sharedAtFork.sharedCount, sharedAtFork.pairs.count,
            "fork 当刻父子不同址（\(sharedAtFork.summary)），与本切片前序结论不一致。")
        XCTAssertEqual(
            sharedAtFork.sameValueCount, sharedAtFork.pairs.count,
            "fork 当刻父子同址但数值摘要不同（\(sharedAtFork.summary)）："
                + "说明摘要把地址或未初始化的尾部算了进去，不可用。")

        // ---- 子情形 A：child 顺着 transcript 自然续算 ----
        let turnA = try await Self.runTurn(appendChild, "child first continuation")
        let parentAfterA = await parent.probeKVStorage(includeValues: true)
        let appendChildAfterA = await appendChild.probeKVStorage(includeValues: true)
        let appendChildWindowAfterA = await appendChild.probeKVStorage(
            includeValues: true, valueRows: parentRows)
        let childLandedA = KVStorageProbe.compare(appendChildWindowAtFork, appendChildWindowAfterA)
        let parentImpactA = KVStorageProbe.compare(parentAtFork, parentAfterA)
        let childWriteA = KVStorageProbe.compare(appendChildAtFork, appendChildAfterA)

        // ---- 子情形 B：child 的 transcript 在父分支已缓存的区域内分叉 ----
        // 只保留父分支首条消息的**前半段**，让渲染后的 prompt 在第 20 个 token 左右分叉：
        // 分叉点落在父分支已缓存的 35 行之内，reuse 决策应回退到 `rewind`，
        // 于是 child 的 prefill 会从父分支可见范围内开始写。
        let divergingChild = await parent.fork(
            history: [Chat.Message(role: .user, content: "isolation parent seed")])
        let divergingChildAtFork = await divergingChild.probeKVStorage(includeValues: true)
        let divergingChildWindowAtFork = await divergingChild.probeKVStorage(
            includeValues: true, valueRows: parentRows)
        let sharedAtForkB = KVStorageProbe.compare(parentAtFork, divergingChildAtFork)
        let turnB = try await Self.runTurn(divergingChild, "child rewinds inside the parent range")
        let parentAfterB = await parent.probeKVStorage(includeValues: true)
        let divergingChildAfterB = await divergingChild.probeKVStorage(includeValues: true)
        let divergingChildWindowAfterB = await divergingChild.probeKVStorage(
            includeValues: true, valueRows: parentRows)
        let childLandedB = KVStorageProbe.compare(
            divergingChildWindowAtFork, divergingChildWindowAfterB)
        let parentImpactB = KVStorageProbe.compare(parentAtFork, parentAfterB)
        let childWriteB = KVStorageProbe.compare(divergingChildAtFork, divergingChildAfterB)

        let overlapA = Self.writeRange(
            info: turnA.info, visibleRows: parentRows, writer: appendChildAtFork)
        let overlapB = Self.writeRange(
            info: turnB.info, visibleRows: parentRows, writer: divergingChildAtFork)

        // 父分支全程未被写入：地址、shape、token 数、数值摘要都必须与 fork 当刻一致。
        XCTAssertTrue(
            parentImpactA.isValueFullyUnchanged,
            "child A 续算后父分支可见数据发生变化（\(parentImpactA.summary)）。")
        XCTAssertTrue(
            parentImpactB.isValueFullyUnchanged,
            "child B 回退写入后父分支可见数据发生变化（\(parentImpactB.summary)）。")
        for (name, sample) in [("A", parentAfterA), ("B", parentAfterB)] {
            XCTAssertEqual(
                sample.processedTokenCount, parentAtFork.processedTokenCount,
                "child \(name) 写入后父分支的缓存行数发生改变。")
        }

        // B 的前提：写入范围必须真的与父分支可见范围相交，否则 B 退化成一个更贵的 A。
        // 这里故意断言而不是只记证据：前提不成立时本用例没有测到隔离，应当报红而不是报绿。
        XCTAssertEqual(
            turnB.info?.cacheReuseMode, "rewind",
            "子情形 B 没有回退写入（mode=\(turnB.info?.cacheReuseMode ?? "nil")），"
                + "写入落在父分支范围之外，隔离未被检验。")
        XCTAssertGreaterThan(
            overlapB.overlapRows, 0,
            "子情形 B 的写入范围与父分支可见范围无交集，隔离未被检验。")

        var evidence: [String: Any] = [
            "probe": "KVCacheStorageIdentityProbe",
            "test": "testChildWriteDoesNotChangeParentVisibleData",
            "question":
                "父分支仍存活时，child 的首次续算写入是否改变父分支可见数据？",
            "instrument": [
                "addresses": "asData(access: .noCopy) — 元素 0 的宿主地址，两次自读一致才采信",
                "values": "FNV-1a over asData(access: .copy) 的连续逻辑字节 + shape",
                "digest_is_identity": false,
            ],
            "parent_rows": parentRows,
            "parent_alive_throughout": true,
            "baseline_digest_is_deterministic": Self.json(baselineStable),
            "fork_did_not_disturb_parent": Self.json(forkEffect),
            "parent_vs_child_at_fork": Self.json(sharedAtFork),
            "parent_vs_child_at_fork_rewind": Self.json(sharedAtForkB),
            "case_a_append": [
                "reuse_mode": turnA.info?.cacheReuseMode ?? "nil",
                "write": Self.json(
                    overlapA, pitchRowsAfter: Self.pitchRows(appendChildAfterA)),
                "parent_after_child_write": Self.json(parentImpactA),
                "child_write": Self.json(childWriteA),
                "child_write_landed_in_parent_window": Self.json(childLandedA),
                "parent_visible_rows_after": parentAfterA.processedTokenCount ?? -1,
            ],
            "case_b_rewind": [
                "reuse_mode": turnB.info?.cacheReuseMode ?? "nil",
                "write": Self.json(
                    overlapB, pitchRowsAfter: Self.pitchRows(divergingChildAfterB)),
                "parent_after_child_write": Self.json(parentImpactB),
                "child_write": Self.json(childWriteB),
                "child_write_landed_in_parent_window": Self.json(childLandedB),
                "parent_visible_rows_after": parentAfterB.processedTokenCount ?? -1,
            ],
            "cases": [
                "A": Self.json(parentImpactA),
                "B": Self.json(parentImpactB),
            ],
        ]

        // ---- 判定 ----
        let parentUnchanged =
            parentImpactA.isValueFullyUnchanged && parentImpactB.isValueFullyUnchanged
        let verdict: String
        if !baselineStable.isValueFullyUnchanged || !parentBaseline.isComparable {
            verdict = "NOT_INSTRUMENTED"
        } else if !parentUnchanged {
            verdict = "ISOLATION_VIOLATED"
        } else if overlapB.overlapRows <= 0 || turnB.info?.cacheReuseMode != "rewind" {
            verdict = "CONDITIONAL_NO_OVERLAP"
        } else {
            verdict = "ISOLATED_ON_OVERLAPPING_WRITE"
        }
        evidence["verdict"] = verdict
        evidence["verdict_meaning"] = [
            "ISOLATED_ON_OVERLAPPING_WRITE":
                "child 在父分支可见范围内写入后，父分支的地址、shape、行数与数值摘要均未变："
                + "当前 fork 语义提供逻辑写入隔离。仍需注意这不是“父分支独占 allocation”的证明，"
                + "也没有证明最后一个引用何时释放。",
            "CONDITIONAL_NO_OVERLAP":
                "父分支没变，但 child 的写入没有落在父分支可见范围内：隔离未被检验，"
                + "只能记 NOT_INSTRUMENTED，不能记为成立。",
            "ISOLATION_VIOLATED":
                "child 写入改变了父分支可见数据：不能依赖当前 fork 语义，"
                + "必须先实现独立存储或等价的写入隔离机制。",
            "NOT_INSTRUMENTED": "仪器自检未过，本轮不对写入隔离作任何结论。",
        ][verdict]
        evidence["not_proven"] = [
            "exclusive_allocation_ownership":
                "UNKNOWN：父分支数值未变不等于 child 不再持有父分支那段 allocation。",
            "last_reference_release":
                "NOT_OBSERVED：本轮没有任何观测面能给出引用计数或最后引用释放。（本轮判定“写入隔离”，不判定“allocation 最后引用释放”。）",
            "physical_page_return":
                "NOT_OBSERVED：未观测，也不在本探针观测面内。",
            "write_is_out_of_place_by_contract":
                "本轮只观测“写入后父分支字节未变 + 写入者换址”，未逐层证明每一个写入都是 out-of-place；"
                + "MLX 层面另有用例单独验，但那是 primitive 级证据，不是 ChatSession 级证明。",
        ]

        try Self.writeEvidence(evidence, filename: "kv-write-isolation-probe.json")

        print("[KV-ISOLATION] verdict=\(verdict) overlapA=\(overlapA.overlapRows) overlapB=\(overlapB.overlapRows)")
    }

    // MARK: - 用例 4：写入 primitive 是否就地

    /// 上面的隔离结论依赖一个前提：缓存的写入路径（下标 set → `mlx_slice_update`）
    /// 不会就地改写共享 buffer。这个用例在 **MLX primitive 层**直接测它，
    /// 不经过 ChatSession，也不手工拼缓存：
    ///
    /// - 两个视图与基数组同址（存储共享）；
    /// - 对其中之一写入 2 行；
    /// - 写入者换址，而基数组与另一个读者的地址与数值都不变。
    ///
    /// 这里**不**宣称“所以 KV 缓存一定安全”：它只说明这条 write path 本身是
    /// out-of-place 的，ChatSession 级结论仍由用例 3 给出。
    func testSliceUpdateDoesNotWriteThroughASharedBuffer() throws {
        let base = MLXArray((0 ..< 32).map { Float($0) }).reshaped([2, 4, 4])
        eval(base)
        let reader = base[.ellipsis]
        let writer = base[.ellipsis]
        eval([reader, writer])

        // 两次采样用同一个 tag：配对键是 (tag, path, role)，tag 不同就配不上，
        // 会变成 only_in_first/only_in_second，而不是“数值变了”。
        let before = KVStorageProbe.sample([base, reader, writer], tag: "shared", includeValues: true)
        XCTAssertEqual(before[0].address, before[1].address)
        XCTAssertEqual(before[0].address, before[2].address)

        // 真实缓存的写入路径就是这个下标 set：KVCacheSimple/RotatingKVCache 都写
        // `keys[.ellipsis, previous..<offset, 0...] = newRows`。
        writer[.ellipsis, 1 ..< 3, 0...] = MLXArray.zeros([2, 2, 4])
        eval(writer)

        let after = KVStorageProbe.sample([base, reader, writer], tag: "shared", includeValues: true)
        // 基数组与读者仍在原处；写入者换到了新分配。
        XCTAssertEqual(after[0].address, before[0].address, "写入穿透到了基数组的存储。")
        XCTAssertEqual(after[1].address, before[1].address, "写入穿透到了另一个读者的存储。")
        XCTAssertNotEqual(after[2].address, before[2].address, "写入没有换址，说明可能是就地改写。")

        // 数值层面：基数组与读者必须完全没变（含 shape）。
        let baseAndReader = KVStorageProbe.compare(
            [before[0], before[1]], [after[0], after[1]])
        XCTAssertTrue(
            baseAndReader.isValueFullyUnchanged,
            "共享 buffer 的读者读到了被改写的数据（\(baseAndReader.summary)）。")

        var evidence: [String: Any] = [
            "probe": "KVCacheStorageIdentityProbe",
            "test": "testSliceUpdateDoesNotWriteThroughASharedBuffer",
            "question": "下标写入（mlx_slice_update）是否就地改写共享 buffer？",
            "shared_before": Self.records(before),
            "shared_after": Self.records(after),
            "reader_values_unchanged": baseAndReader.isValueFullyUnchanged,
            "writer_relocated": after[2].address != before[2].address,
            "scope":
                "MLX primitive 级证据：说明这条 write path 是 out-of-place，不替代 ChatSession 级的用例 3。",
        ]
        let verdict =
            baseAndReader.isValueFullyUnchanged && after[2].address != before[2].address
            ? "WRITE_PATH_OUT_OF_PLACE" : "WRITE_PATH_MAY_BE_IN_PLACE"
        evidence["verdict"] = verdict
        try Self.writeEvidence(evidence, filename: "kv-write-primitive-probe.json")
        XCTAssertEqual(verdict, "WRITE_PATH_OUT_OF_PLACE")
    }

    // MARK: - 用例 5：反方向（父分支写入，child 存活）

    /// 用例 3 证明的是 child 写入不改**存活父分支**。缺的反方向是：
    /// **父分支写入不改存活 child**。
    ///
    /// 这一格故意落到用例 3 碰不到的那条路径上：
    /// child fork 之后每层容量被折成了 offset，它的首次写入必然 reset/concatenated，
    /// **根本不会走到“在既有 extent 内就地落下”的分支**；而父分支不一样，它仍持有
    /// 自己的 buffer（`step` 增长出来的行数），trim 只减 offset、不动 `keys` 的 extent，
    /// 于是它这一轮 `rewind` 的写入区间可以整段落在既有 extent 内 ——
    /// 走的就是 `slice_update` 那条 out-of-place 路径，并且与 child 可见范围相交。
    ///
    /// “落在既有 extent 内”不靠猜：`strides` 推出的底层行距在写入前后不变，
    /// 就是没走 reset/concatenated 的可观测判据（reset 会把 extent 撑成 `previous + step`）。
    /// 换句话说：这一格把隔离从“容量折叠的意外”里抽离出来，只剩 primitive 的值语义在担保。
    ///
    /// 两个必须同时成立的排伪条件（用户的验收要求）：
    ///   - 写入区间真的与 child 可见范围相交，否则本轮无效；
    ///   - 父分支自己的更新真的生效了（行数推进 + 换址），否则“child 没变”是假绿。
    func testParentWriteDoesNotChangeLiveChildVisibleData() async throws {
        let model = Self.makeTinyModel()
        let parent = ChatSession(model, generateParameters: Self.generationParameters())
        _ = try await parent.respond(to: "parent branch seed prompt")

        let parentBaseline = await parent.probeKVStorage(includeValues: true)
        let parentBaselineAgain = await parent.probeKVStorage(includeValues: true)
        let baselineStable = KVStorageProbe.compare(parentBaseline, parentBaselineAgain)
        XCTAssertTrue(
            baselineStable.isValueFullyUnchanged,
            "同一 session 连续两次取数值摘要不一致（\(baselineStable.summary)）：摘要不可用。")
        XCTAssertTrue(parentBaseline.isComparable, "父分支基线不可比较，仪器不可用。")

        // ---- fork：child 全程存活且不再被使用，只当一个被动读者 ----
        let child = await parent.fork()
        let childAtFork = await child.probeKVStorage(includeValues: true)
        let parentAtFork = await parent.probeKVStorage(includeValues: true)
        let sharedAtFork = KVStorageProbe.compare(parentAtFork, childAtFork)
        XCTAssertEqual(
            sharedAtFork.sharedCount, sharedAtFork.pairs.count,
            "fork 当刻父子不同址（\(sharedAtFork.summary)），前提与本切片前序结论不一致。")
        XCTAssertEqual(
            sharedAtFork.sameValueCount, sharedAtFork.pairs.count,
            "fork 当刻父子同址但数值摘要不同（\(sharedAtFork.summary)）。")
        let childRows = childAtFork.processedTokenCount ?? 0
        XCTAssertGreaterThan(childRows, 0, "child 在 fork 当刻没有任何缓存行。")

        // 写入会把父分支的可见行数从 childRows 推到更大，整数组摘要就不同形了。
        // 这里固定一个窗口（= child 可见行数）在写入前后各采一次，只回答一件事：
        // **child 看得见的那几行，父分支写入后数值到底变没变。**
        let parentWindowAtFork = await parent.probeKVStorage(
            includeValues: true, valueRows: childRows)

        // ---- 只让父分支走一次真实续算（rewind + 写入） ----
        let turn = try await Self.runTurn(parent, "parent rewrite after the fork")
        let parentAfter = await parent.probeKVStorage(includeValues: true)
        let childAfter = await child.probeKVStorage(includeValues: true)
        let parentWindowAfter = await parent.probeKVStorage(
            includeValues: true, valueRows: childRows)
        let writeLanded = KVStorageProbe.compare(parentWindowAtFork, parentWindowAfter)

        let parentSelf = KVStorageProbe.compare(parentAtFork, parentAfter)
        let childImpact = KVStorageProbe.compare(childAtFork, childAfter)
        let range = Self.writeRange(
            info: turn.info, visibleRows: childRows, writer: parentAtFork)

        // 前提一：父分支自己真的写了。“child 没变”只有在写入生效时才有意义。
        let parentRowsAdvanced =
            (parentAfter.processedTokenCount ?? 0) > (parentAtFork.processedTokenCount ?? 0)
        XCTAssertTrue(
            parentRowsAdvanced,
            "父分支行数没有推进（\(parentAtFork.processedTokenCount ?? -1) → "
                + "\(parentAfter.processedTokenCount ?? -1)），写入未生效，本轮无法判定隔离。")
        XCTAssertEqual(
            parentSelf.sharedCount, 0,
            "父分支写入后仍有层同址（\(parentSelf.summary)），写入可能未真正重绑定。")
        // 前提二：写的是父分支本来就有的 extent，不是 child 那种“先扩容再写”。
        // 两条可观测事实：写入整段落在写入前的底层行距内；写入后行距没变。
        // 后者是决定性的 —— reset/concatenated 一定把 extent 撑成 `previous + step`。
        let pitchRowsAfter = Self.pitchRows(parentAfter)
        XCTAssertGreaterThan(
            range.pitchSurplus, 0,
            "父分支写入前没有 spare capacity（可见 \(range.writerRows) 行 / 底层行距 "
                + "\(range.pitchRows) 行）：这一轮测不到“extent 内写入”。")
        XCTAssertTrue(
            range.fitsInExistingExtent,
            "父分支写入末行 \(range.writeEnd) 超出了写入前的底层行距 \(range.pitchRows)："
                + "这一轮退化成了 reset/concatenated 路径，测不到 `slice_update` 那条分支。")
        XCTAssertEqual(
            pitchRowsAfter, range.pitchRows,
            "父分支写入后底层行距由 \(range.pitchRows) 变成 \(pitchRowsAfter)："
                + "说明走了 reset/concatenated，本轮不是 extent 内写入。")
        // 排伪：写入必须真的改动了 child 可见的那几行。`offset` 前进与换址在
        // `slice_update` 下即使空写也会发生，所以“行数推进 + 换址”不足以排除空写。
        XCTAssertEqual(
            writeLanded.sharedCount, 0,
            "父分支窗口内仍有层指向原 buffer（\(writeLanded.summary)），写入未换址。")
        XCTAssertEqual(
            writeLanded.sameValueCount, 0,
            "父分支在 child 可见行上的数值与写入前相同（\(writeLanded.summary)）："
                + "rewind 没有真正改写重叠行，本轮不能判定隔离。")
        // 前提三：写入区间确实与 child 可见范围相交。
        XCTAssertEqual(
            turn.info?.cacheReuseMode, "rewind",
            "父分支这一轮不是 rewind（mode=\(turn.info?.cacheReuseMode ?? "nil")），"
                + "写入落在 child 可见范围之外，隔离未被检验。")
        XCTAssertGreaterThan(
            range.overlapRows, 0,
            "父分支写入区间与 child 可见范围无交集，隔离未被检验。")

        // 结论断言：child 的地址、shape、行数与数值摘要全部不变。
        XCTAssertEqual(
            childImpact.sharedCount, childImpact.pairs.count,
            "父分支写入后 child 的存储身份发生变化（\(childImpact.summary)）。")
        XCTAssertTrue(
            childImpact.isValueFullyUnchanged,
            "父分支写入穿透到了存活 child 的可见数据（\(childImpact.summary)）。")
        XCTAssertEqual(
            childAfter.processedTokenCount, childAtFork.processedTokenCount,
            "父分支写入改变了 child 的缓存行数。")

        let instrumentOk = baselineStable.isValueFullyUnchanged && childAtFork.isComparable
        let premiseOk =
            parentRowsAdvanced && range.overlapRows > 0 && range.pitchSurplus > 0
            && turn.info?.cacheReuseMode == "rewind"
            && range.fitsInExistingExtent && pitchRowsAfter == range.pitchRows
            && writeLanded.sameValueCount == 0
        let childUnchanged =
            childImpact.isValueFullyUnchanged
            && childImpact.sharedCount == childImpact.pairs.count
        let verdict: String
        if !instrumentOk {
            verdict = "NOT_INSTRUMENTED"
        } else if !premiseOk {
            verdict = "INVALID_OBSERVATION"
        } else if childUnchanged {
            verdict = "BIDIRECTIONAL_ISOLATION"
        } else {
            verdict = "PARENT_WRITE_LEAKED_INTO_CHILD"
        }

        let evidence: [String: Any] = [
            "probe": "KVCacheStorageIdentityProbe",
            "test": "testParentWriteDoesNotChangeLiveChildVisibleData",
            "question":
                "父分支在 fork 后仍有 spare capacity 时，它的真实 rewind 写入是否改变存活 child 的可见数据？",
            "parent_alive_throughout": true,
            "child_used_as_passive_reader_only": true,
            "baseline_digest_is_deterministic": Self.json(baselineStable),
            "parent_vs_child_at_fork": Self.json(sharedAtFork),
            "parent_write": Self.json(
                range, writer: "parent", other: "child",
                pitchRowsAfter: pitchRowsAfter),
            "parent_records_at_fork": Self.records(parentAtFork),
            "parent_records_after": Self.records(parentAfter),
            "child_records_at_fork": Self.records(childAtFork),
            "parent_write_took_effect": [
                "rows_advanced": parentRowsAdvanced,
                "rows_before": parentAtFork.processedTokenCount ?? -1,
                "rows_after": parentAfter.processedTokenCount ?? -1,
                "storage_rebound": parentSelf.sharedCount == 0,
                "self_compare": Self.json(parentSelf),
                "child_visible_window": childRows,
                "rows_rewritten_in_window": writeLanded.sameValueCount
                    == 0 ? "all" : "only_some_or_none",
                "window_compare": Self.json(writeLanded),
                "why_window":
                    "写入前后父分支可见行数不同，整数组摘要不同形；窗口把两侧截到同一批行，"
                    + "才能回答“child 看得见的行有没有被改”。",
            ],
            "child_after_parent_write": Self.json(childImpact),
            "child_records_after": Self.records(childAfter),
            "verdict": verdict,
            "verdict_meaning": [
                "BIDIRECTIONAL_ISOLATION":
                    "父分支在既有 extent 内、且与 child 可见范围重叠的写入没有改变 child 的"
                    + "地址/行数/数值：双向逻辑写入隔离成立。这一格走的是 `slice_update`"
                    + "而不是 reset/concatenated（依据：写入后底层行距未变、写入者换址），"
                    + "所以隔离不再依赖“容量折叠”这条偶发路径，但仍然是 primitive 值语义的依赖，"
                    + "不是缓存层写下来的保证。",
                "PARENT_WRITE_LEAKED_INTO_CHILD":
                    "父分支写入改变了存活 child 的可见数据：写入隔离有缺陷，"
                    + "必须先修原生缓存路径，不能再用路径副作用解释隔离。",
                "INVALID_OBSERVATION":
                    "写入未生效、模式不是 rewind、写入区间与 child 可见范围无交集，"
                    + "或者写入走了 reset/concatenated（写入后底层行距变化）："
                    + "本轮测不到“extent 内写入”的隔离，不得记为通过。",
                "NOT_INSTRUMENTED": "仪器自检未过，本轮不作结论。",
            ][verdict],
            "not_proven": [
                "exclusive_allocation_ownership":
                    "UNKNOWN：child 数值未变，不等于父分支写入后 child 仍不持有同一段 allocation。",
                "last_reference_release": "NOT_OBSERVED：本轮不涉及释放。",
                "physical_page_return": "NOT_OBSERVED：不在探针观测面内。",
                "real_model_equivalence":
                    "本轮是随机权重微型 Gemma3，只回答存储语义，不回答真实续算等价。",
            ],
        ]
        try Self.writeEvidence(evidence, filename: "kv-write-isolation-parent-probe.json")
        print(
            "[KV-ISOLATION-PARENT] verdict=\(verdict) mode=\(turn.info?.cacheReuseMode ?? "nil") "
                + "overlap=\(range.overlapRows) pitch=\(range.pitchRows)->\(pitchRowsAfter)")
        XCTAssertTrue(
            ["BIDIRECTIONAL_ISOLATION", "PARENT_WRITE_LEAKED_INTO_CHILD",
             "INVALID_OBSERVATION", "NOT_INSTRUMENTED"].contains(verdict),
            "未知判定：\(verdict)")
    }

    // MARK: - 用例 6：显式 detached fork（严格存储分离）

    /// A 切片证明的是逻辑写入互不污染，**不是**存储独立。这个用例问的是另一件事：
    /// child 的 KV 数组是不是自己的 buffer。
    ///
    /// 三层判据，缺一不可：
    ///   ① 依赖自己那道门：`forkDetached` 只在验证通过后才返回，报告里
    ///      `storageSeparated` / `valuesPreserved` 必须全为真，且它覆盖的数组数
    ///      等于探针同一时刻看到的数组数（否则门只查了子集）。
    ///   ② 第三方仪器：用现有的 `KVStorageProbe` 对父子各采一次，要求 0/N 同址、
    ///      N/N 同值、shape 与 token 数一致 —— 不能只信被测对象自己的报告。
    ///   ③ 释放后仍能续算：父分支被释放，child 用**它自己的**存储再跑一轮，
    ///      缓存行数推进且 `cachedPromptTokenCount > 0`（不是冷 prefill）。
    ///
    /// 仍然不回答：旧 allocation 的最后一个引用何时释放、物理页是否归还。
    /// 分离只说明“child 不再持有旧数组”，不说明旧数组的字节已回到系统。
    func testDetachedForkOwnsItsStorageAndSurvivesSourceRelease() async throws {
        let model = Self.makeTinyModel()
        var evidence: [String: Any] = [
            "probe": "KVCacheStorageIdentityProbe",
            "test": "testDetachedForkOwnsItsStorageAndSurvivesSourceRelease",
            "model": "Gemma3TextModel(8 layers, random weights) — structural, not quality",
        ]

        var parent: ChatSession? = ChatSession(
            model, generateParameters: Self.generationParameters())
        let seed = try await Self.runTurn(parent!, "detached fork seed prompt")

        let parentBefore = await parent!.probeKVStorage(includeValues: true)
        XCTAssertTrue(parentBefore.isComparable, "父分支采样不可比较，仪器不可用。")
        let kinds = Set(parentBefore.records.map(\.cacheKind))
        // 两种叶子都必须出现：只测 KVCacheSimple 等于没测旋转窗口路径。
        XCTAssertTrue(
            kinds.contains("KVCacheSimple"),
            "本轮没有 KVCacheSimple 叶子（\(kinds.sorted())），覆盖不完整。")
        XCTAssertTrue(
            kinds.contains("RotatingKVCache"),
            "本轮没有 RotatingKVCache 叶子（\(kinds.sorted())），滑窗路径未被覆盖。")

        // ---- ① 依赖自己的门 ----
        let activeBefore = Memory.activeMemory
        let peakBefore = Memory.peakMemory
        let started = Date()
        let (child, report) = try await parent!.forkDetached()
        let elapsed = -started.timeIntervalSinceNow
        let peakAfter = Memory.peakMemory

        XCTAssertTrue(
            report.storageSeparated,
            "门报告存储未分离（\(report.summary)）：拒绝使用。")
        XCTAssertTrue(
            report.valuesPreserved,
            "门报告数值未保持一致（\(report.summary)）：拒绝使用。")
        XCTAssertEqual(
            report.main.arrays, parentBefore.records.count,
            "门覆盖的数组数（\(report.main.arrays)）与探针看到的"
                + "数组数（\(parentBefore.records.count)）不一致：门只验证了子集。")
        XCTAssertEqual(report.main.processedTokenCount, parentBefore.processedTokenCount)
        XCTAssertGreaterThan(report.bytes, 0)

        // ---- ② 第三方仪器的独立观测 ----
        let childAtFork = await child.probeKVStorage(includeValues: true)
        let relation = KVStorageProbe.compare(parentBefore, childAtFork)
        XCTAssertFalse(relation.pairs.isEmpty, "父子没有任何可配对的记录。")
        XCTAssertEqual(
            relation.sharedCount, 0,
            "detached 后父子仍有同址数组（\(relation.summary)）：复制没有真正分离存储。")
        XCTAssertEqual(
            relation.sameValueCount, relation.valueComparedCount,
            "detached 后父子数值摘要不一致（\(relation.summary)）：复制改变了缓存内容。")
        XCTAssertEqual(
            report.main.arrays, relation.pairs.count,
            "门统计的数组数与仪器配对数不同：两套观测看的不是同一批数组。")
        for pair in relation.pairs {
            XCTAssertEqual(
                pair.firstShape, pair.secondShape,
                "\(pair.tag)/\(pair.role) 的行数在复制后变了："
                    + "\(pair.firstShape) -> \(pair.secondShape)")
        }
        XCTAssertEqual(
            childAtFork.processedTokenCount, parentBefore.processedTokenCount,
            "token 时间线在 detached fork 上发生了变化。")

        // 事后复核：对**真正拿到的那个 session** 再跑一次同一道门。
        let recheck = try await child.verifyStorageSeparation(from: parent!)
        XCTAssertTrue(recheck.storageSeparated && recheck.valuesPreserved)

        let childRowsBefore = Self.visibleRows(childAtFork)
        XCTAssertGreaterThan(childRowsBefore, 0, "child 在 fork 当刻没有任何缓存行。")

        // ---- ③ 释放旧分支，child 用自己的存储续算 ----
        let watching = WeakSession(parent!)
        parent = nil
        XCTAssertNil(
            watching.value,
            "父分支仍被强引用持有：用例自己泄漏了引用，“释放后续算”无效。")

        let continuation = try await Self.runTurn(child, "continue on the detached branch")
        let childAfterTurn = await child.probeKVStorage()
        let childRowsAfter = Self.visibleRows(childAfterTurn)
        XCTAssertGreaterThan(
            childRowsAfter, childRowsBefore,
            "父分支释放后 child 的缓存没有推进（\(childRowsBefore) -> \(childRowsAfter)）。")
        let reused = continuation.info?.cachedPromptTokenCount ?? 0
        XCTAssertGreaterThan(
            reused, 0,
            "child 在父分支释放后做的是冷 prefill（cachedPromptTokenCount=0），"
                + "不是沿用自己的缓存续算。")

        let verdict: String
        if !(report.storageSeparated && report.valuesPreserved) {
            verdict = "DETACHED_COPY_INVALID"
        } else if relation.sharedCount != 0 {
            verdict = "DETACHED_COPY_SHARES_STORAGE"
        } else if relation.sameValueCount != relation.valueComparedCount {
            verdict = "DETACHED_COPY_VALUES_DIFFER"
        } else if reused <= 0 || childRowsAfter <= childRowsBefore {
            verdict = "DETACHED_COPY_BROKE_CONTINUATION"
        } else {
            verdict = "DETACHED_STORAGE_VERIFIED"
        }

        evidence["gate"] = [
            "storage_separated": report.storageSeparated,
            "values_preserved": report.valuesPreserved,
            "leaves": report.leaves,
            "arrays": report.arrays,
            "bytes": report.bytes,
            "cache_kinds": report.cacheKinds,
            "summary": report.summary,
            "covered_every_sampled_array": report.main.arrays == parentBefore.records.count,
        ]
        evidence["independent_probe"] = [
            "parent_vs_child": Self.json(relation, verdict: Self.relation(relation)),
            "child_after_fork": Self.json(childAtFork),
            "recheck_report": recheck.summary,
            "cache_kinds": kinds.sorted(),
        ]
        evidence["cost"] = [
            "fork_seconds": elapsed,
            "bytes_copied": report.bytes,
            "active_bytes_before": activeBefore,
            "active_bytes_after": Memory.activeMemory,
            "peak_bytes_before": peakBefore,
            "peak_bytes_after": peakAfter,
            "peak_delta_bytes": peakAfter - peakBefore,
            "note": "微型模型随机权重的量级参考值，不代表真实模型的成本。",
        ]
        evidence["after_source_release"] = [
            "child_rows_before": childRowsBefore,
            "child_rows_after": childRowsAfter,
            "cache_reuse_mode": continuation.info?.cacheReuseMode ?? "nil",
            "cached_prompt_tokens": reused,
            "reprefilled_tokens": continuation.info?.promptTokenCount ?? -1,
            "generated_tokens": continuation.info?.generationTokenCount ?? -1,
            "characters": continuation.text.count,
            "seed_characters": seed.text.count,
        ]
        evidence["verdict"] = [
            "verdict": verdict,
            "DETACHED_STORAGE_VERIFIED":
                "child 的 KV 数组在被验证的时刻不读父分支的字节，数值/行数/token 数一致，"
                + "且父分支释放后 child 仍用自己的缓存续算。",
            "DETACHED_COPY_SHARES_STORAGE": "复制没有分离存储：严格模式不得使用。",
            "DETACHED_COPY_VALUES_DIFFER": "复制改变了缓存内容：严格模式不得使用。",
            "DETACHED_COPY_BROKE_CONTINUATION": "分离后无法沿用缓存续算：严格模式不得使用。",
            "DETACHED_COPY_INVALID": "门自己未通过：本轮不作结论。",
            "not_proven": [
                "last_reference_release": "NOT_OBSERVED：父分支释放只证明引用被解除。",
                "physical_page_return": "NOT_OBSERVED：不在探针观测面内。",
                "real_model_cost": "见 KVCacheDetachedForkRealModelTests。",
            ],
        ]
        try Self.writeEvidence(evidence, filename: "kv-detached-fork-probe.json")
        print(
            "[KV-DETACHED] verdict=\(verdict) arrays=\(report.arrays) bytes=\(report.bytes) "
                + "separated=\(relation.sharedCount)/\(relation.pairs.count) "
                + "seconds=\(String(format: "%.3f", elapsed)) reuse=\(reused)")
        XCTAssertTrue(
            ["DETACHED_STORAGE_VERIFIED", "DETACHED_COPY_INVALID",
             "DETACHED_COPY_SHARES_STORAGE", "DETACHED_COPY_VALUES_DIFFER",
             "DETACHED_COPY_BROKE_CONTINUATION"].contains(verdict),
            "未知判定：\(verdict)")
        XCTAssertEqual(verdict, "DETACHED_STORAGE_VERIFIED")
    }

    // MARK: - 用例 7：严格模式的失败处理（fail-closed）

    /// 一个“只在成功时才给出保证”的路径，必须先证明它**会拒绝**。
    ///
    /// 三格，每一格都在堵一种“看起来通过”的假象：
    ///   ① 没有已实现 cache 的会话：`forkDetached` 必须报错，而不是返回一个冷 child
    ///      （冷 child 会让“旧载体退休”看起来成功，实际上什么都没续上）。
    ///   ② 普通 `fork()`（已知共享存储）：同一道门必须拒绝。否则这道门分不清共享与
    ///      独立，用例 6 的“0/N 同址”就只是门自己造出来的结论。
    ///   ③ 同一对会话改用 `forkDetached`：必须通过。否则②只能说明门一律拒绝。
    func testDetachedForkRefusesSharedOrColdSources() async throws {
        let model = Self.makeTinyModel()
        var evidence: [String: Any] = [
            "probe": "KVCacheStorageIdentityProbe",
            "test": "testDetachedForkRefusesSharedOrColdSources",
        ]

        // ---- ① 冷会话：没有可分离的 cache ----
        let cold = ChatSession(model, generateParameters: Self.generationParameters())
        var coldRefusal = "NO_ERROR"
        do {
            _ = try await cold.forkDetached()
            XCTFail("没有已实现 cache 的会话必须被拒绝，而不是返回冷 child。")
        } catch let error as DetachedForkError {
            coldRefusal = "\(error)"
            guard case .noRealizedCache = error else {
                XCTFail("拒绝理由不是 noRealizedCache：\(error)")
                return
            }
        }

        // ---- ② 共享的 fork 必须被同一道门拒绝 ----
        let parent = ChatSession(model, generateParameters: Self.generationParameters())
        _ = try await Self.runTurn(parent, "detached gate negative control")
        let shared = await parent.fork()
        let parentSample = await parent.probeKVStorage(includeValues: true)
        let sharedSample = await shared.probeKVStorage(includeValues: true)
        let sharedRelation = KVStorageProbe.compare(parentSample, sharedSample)
        XCTAssertEqual(
            sharedRelation.sharedCount, sharedRelation.pairs.count,
            "前提不成立：普通 fork 本轮不同址（\(sharedRelation.summary)）。")

        var sharedRefusal = "NO_ERROR"
        do {
            _ = try await shared.verifyStorageSeparation(from: parent)
            XCTFail("门接受了共享存储的 fork：它无法分辨共享与独立。")
        } catch let error as DetachedForkError {
            sharedRefusal = "\(error)"
            guard case .verificationFailed(let detail) = error else {
                XCTFail("拒绝理由不是 verificationFailed：\(error)")
                return
            }
            XCTAssertTrue(
                detail.contains("still reads the source's storage"),
                "拒绝理由没有点名“仍读源存储”，无法据此定位：\(detail)")
        }

        // ---- ③ 对照组：同一对会话走 detached 必须通过 ----
        let (detached, report) = try await parent.forkDetached()
        XCTAssertTrue(report.storageSeparated && report.valuesPreserved, report.summary)
        let detachedRelation = KVStorageProbe.compare(
            await parent.probeKVStorage(), await detached.probeKVStorage())
        XCTAssertEqual(
            detachedRelation.sharedCount, 0,
            "对照组仍然同址（\(detachedRelation.summary)）：门不是可用的判据。")

        evidence["cold_source"] = ["refusal": coldRefusal]
        evidence["shared_fork"] = [
            "refusal": sharedRefusal,
            "shared_before_refusal": sharedRelation.summary,
        ]
        evidence["detached_control"] = [
            "storage_separated": report.storageSeparated,
            "values_preserved": report.valuesPreserved,
            "shared_after_detach": detachedRelation.sharedCount,
            "summary": report.summary,
        ]
        evidence["verdict"] = [
            "verdict": "STRICT_PATH_REFUSES_AND_ACCEPTS",
            "meaning":
                "严格路径在无可分离 cache 时拒绝、在已知共享时拒绝、在真正分离时接受："
                + "fail-closed 行为成立，且用例 6 的通过不是门的构造产物。",
        ]
        try Self.writeEvidence(evidence, filename: "kv-detached-fork-refusal.json")
        print(
            "[KV-DETACHED-GATE] cold=\(coldRefusal) shared=\(sharedRefusal) "
                + "control_separated=\(detachedRelation.sharedCount == 0)")
    }

    // MARK: - 用例 8：逐 cache 类型（不需要模型）

    /// 用例 6 只覆盖了 Gemma3 实际出现的两种叶子（`KVCacheSimple` +
    /// `RotatingKVCache`）。依赖里还有别的 cache 类型，而“存储分离”是逐个实现的：
    /// 只测到一种，等于其余几种的 `detachedCopy()` 从没被执行过。
    ///
    /// 所以这一格绕开模型，直接给每一种能出现的 cache 建一个真实状态，逐个走同一道门
    /// （复制 → 兑现 → 门 → 第三方仪器 → 再写一轮）：
    ///
    ///   - 必须能分离的：`KVCacheSimple`、`RotatingKVCache`（写到 wrap）、
    ///     `QuantizedKVCache`（打包数组不能被反量化重打包）、`ArraysCache`（带未写槽）、
    ///     `MambaCache`、`CacheList`（复合，逐 child 递归）。
    ///   - 必须拒绝的：`ChunkedKVCache`（`state` 表达不了前端 trim，无法忠实验证）、
    ///     `TurboQuantKVCache` / `VarianceNormalizedKVCache`（本轮未实现分离）、
    ///     自定义 `BaseKVCache` 子类（新类型默认没有分离实现）。
    ///
    /// 拒绝格的断言不止“抛了错”，还要抛**对**理由：把 `unsupportedCacheKind` 记成
    /// `verificationFailed` 是两件不同的事，后者意味着实现声称做了却做错了。
    func testEveryCacheKindDetachesOrRefuses() throws {
        var evidence: [String: Any] = [
            "probe": "KVCacheStorageIdentityProbe",
            "test": "testEveryCacheKindDetachesOrRefuses",
            "model": "none — caches are built directly, no model is involved",
        ]
        var refusals: [[String: Any]] = []
        var continued: [String: Int] = [:]

        // ---- 能分离的一类：先写真实状态 ----

        // 1. 最普通的两数组 cache，三点行。
        let simple = KVCacheSimple()
        _ = simple.update(
            keys: Self.block(rows: 3, seed: 1), values: Self.block(rows: 3, seed: 2))

        // 2. 环状 cache：maxSize=4 用单 token 写 6 次，越过容量后必然 wrap。
        //    不 wrap 的话测到的只是“没绕回”的那条路径，而 wrap 之后 `state` 返回的是
        //    整段 ring（顺序与 idx 有关），正是最容易复制错的情形。
        let rotating = RotatingKVCache(maxSize: 4, keep: 0, step: 4)
        for step in 0 ..< 6 {
            _ = rotating.update(
                keys: Self.block(rows: 1, seed: 10 + Float(step)),
                values: Self.block(rows: 1, seed: 30 + Float(step)))
        }
        XCTAssertEqual(
            rotating.metaState.last, "true",
            "RotatingKVCache 没有 wrap（metaState=\(rotating.metaState)）：这格没测到 ring 路径。")

        // 3. 量化 cache：直接放已打包的四/六个数组，offset 设到满行，
        //    否则 `state` 会把自己 trim 成 0 行（拿不到地址，门会拒绝）。
        let quantizedCache = QuantizedKVCache(groupSize: 32, bits: 4)
        let qKeys = quantized(Self.block(rows: 2, headDim: 32, seed: 40), groupSize: 32, bits: 4)
        let qValues = quantized(Self.block(rows: 2, headDim: 32, seed: 50), groupSize: 32, bits: 4)
        let packed: [MLXArray?] = [
            qKeys.wq, qKeys.scales, qKeys.biases,
            qValues.wq, qValues.scales, qValues.biases,
        ]
        quantizedCache.state = packed.compactMap { $0 }
        quantizedCache.offset = 2

        // 4. 数组型 cache：三个槽只写两个，槽 1 故意留空。
        //    `state` 会丢掉 nil 槽，所以这里同时验证“复制没有顺手把槽数改成 2”。
        let arrays = ArraysCache(size: 3)
        arrays[0] = Self.block(rows: 2, headDim: 4, seed: 60)
        arrays[2] = Self.block(rows: 2, headDim: 4, seed: 61)
        XCTAssertEqual(arrays.state.count, 2, "前提不成立：数组型 cache 的 state 没有丢 nil 槽。")

        // 5. 带类型身份的数组型 cache（选择性解码的状态就是它）。
        let mamba = MambaCache()
        mamba[0] = Self.block(rows: 1, headDim: 4, seed: 70)
        mamba[1] = Self.block(rows: 1, headDim: 4, seed: 71)

        // 6. 复合 cache：路径 `0` / `1` 各一个 child，复制必须逐 child 递归。
        let listSimple = KVCacheSimple()
        _ = listSimple.update(
            keys: Self.block(rows: 2, seed: 80), values: Self.block(rows: 2, seed: 81))
        let listRotating = RotatingKVCache(maxSize: 2, keep: 0, step: 2)
        _ = listRotating.update(
            keys: Self.block(rows: 1, seed: 82), values: Self.block(rows: 1, seed: 83))
        let list = CacheList(listSimple, listRotating)
        list.offset = listSimple.offset

        // ---- 逐个走门 ----

        let simpleCopy = try Self.checkDetached("KVCacheSimple", simple, evidence: &evidence)
        let rotatingCopy = try Self.checkDetached("RotatingKVCache", rotating, evidence: &evidence)
        let quantizedCopy = try Self.checkDetached(
            "QuantizedKVCache", quantizedCache, evidence: &evidence)
        let arraysCopy = try Self.checkDetached("ArraysCache", arrays, evidence: &evidence)
        _ = try Self.checkDetached("MambaCache", mamba, evidence: &evidence)
        _ = try Self.checkDetached("CacheList", list, evidence: &evidence)

        // 未写的槽必须是未写的槽，而不是空数组或零矩阵。
        if let arraysCopy = arraysCopy as? ArraysCache {
            XCTAssertNil(
                arraysCopy[1],
                "源 cache 的第 1 槽是未写，复制后却被填上了：槽位结构没有被保留。")
            XCTAssertEqual(arraysCopy.state.count, arrays.state.count, "复制的槽数变了。")
        } else {
            XCTFail("ArraysCache 的复制换了类型：\(type(of: arraysCopy))")
        }

        // ---- 复制出来还得能继续写 ----

        // 形状对、值对、但一写就崩的副本不是可用的 cache。这里各写一个 token，
        // offset 必须推进 1。
        if let cache = simpleCopy as? KVCacheSimple {
            let before = cache.offset
            _ = cache.update(
                keys: Self.block(rows: 1, seed: 900), values: Self.block(rows: 1, seed: 901))
            continued["KVCacheSimple"] = cache.offset - before
        } else {
            XCTFail("KVCacheSimple 的复制换了类型：\(type(of: simpleCopy))")
        }
        if let cache = rotatingCopy as? RotatingKVCache {
            let before = cache.offset
            _ = cache.update(
                keys: Self.block(rows: 1, seed: 902), values: Self.block(rows: 1, seed: 903))
            continued["RotatingKVCache"] = cache.offset - before
        } else {
            XCTFail("RotatingKVCache 的复制换了类型：\(type(of: rotatingCopy))")
        }
        if let cache = quantizedCopy as? QuantizedKVCache {
            let before = cache.offset
            _ = cache.updateQuantized(
                keys: Self.block(rows: 1, headDim: 32, seed: 904),
                values: Self.block(rows: 1, headDim: 32, seed: 905))
            continued["QuantizedKVCache"] = cache.offset - before
        } else {
            XCTFail("QuantizedKVCache 的复制换了类型：\(type(of: quantizedCopy))")
        }
        for (name, advanced) in continued {
            XCTAssertEqual(
                advanced, 1, "\(name) 的复制没有接受后续写入（offset 推进 \(advanced)）。")
        }
        XCTAssertEqual(continued.count, 3, "有三类复制没有验证“还能继续写”。")

        // ---- 必须拒绝的一类 ----

        /// 拒绝格：必须是 `DetachedForkError`，而且理由要对得上。
        func expectRefusal(_ name: String, _ cache: KVCache, _ kind: String) {
            var refusal = "NO_ERROR"
            do {
                _ = try KVCacheDetachment.detachedCopy(of: cache)
                XCTFail("\(name) 没有拒绝：严格模式不得把无法验证的 cache 交出去。")
            } catch let error as DetachedForkError {
                refusal = "\(error)"
                let matches: Bool
                switch error {
                case .unsupportedCacheKind: matches = kind == "unsupportedCacheKind"
                case .invalidState: matches = kind == "invalidState"
                default: matches = false
                }
                XCTAssertTrue(matches, "\(name) 的拒绝理由不是 \(kind)：\(error)")
            } catch {
                XCTFail("\(name) 抛出的不是 DetachedForkError：\(error)")
            }
            refusals.append(["cache_kind": name, "expected": kind, "refusal": refusal])
        }

        // 前端 trim 过的分块 cache：缓冲区只剩 2 行，offset 却仍是 3。
        // `state` 在 offset 处越界，所以复制出来的东西无法与源比对 —— 只能拒绝。
        let chunked = ChunkedKVCache(chunkSize: 2)
        _ = chunked.update(keys: Self.block(rows: 3, seed: 90), values: Self.block(rows: 3, seed: 91))
        chunked.maybeTrimFront()
        expectRefusal("ChunkedKVCache(after maybeTrimFront)", chunked, "invalidState")

        // 依赖里存在、但本轮没有实现分离的两类：必须明确拒绝，而不是悄悄共享。
        expectRefusal("TurboQuantKVCache", TurboQuantKVCache(), "unsupportedCacheKind")
        expectRefusal("VarianceNormalizedKVCache", VarianceNormalizedKVCache(), "unsupportedCacheKind")

        // 将来新增的类型就长这样：只实现 `state`，没有分离实现。
        expectRefusal("UnimplementedProbeCache", UnimplementedProbeCache(), "unsupportedCacheKind")

        evidence["detachable"] = Array(continued.keys).sorted()
        evidence["refused"] = refusals
        evidence["verdict"] = [
            "verdict": "ALL_CACHE_KINDS_DETACH_OR_REFUSE",
            "meaning":
                "六种能分离的 cache 复制后 0 同址、值/shape/dtype/offset/metaState 一致、"
                + "且复制出的对象还能继续写入；四种不能分离的 cache 全部抛 DetachedForkError 且理由正确。",
            "not_proven": [
                "real_model_usage":
                    "KVCacheSimple / RotatingKVCache 在真实模型上由用例 6 与"
                    + "KVCacheDetachedForkRealModelTests 覆盖；Quantized / Arrays / Mamba /"
                    + "CacheList 只在构造状态上验证，未在真实模型里跑过续算。",
                "last_reference_release": "NOT_OBSERVED：本用例不涉及释放。",
                "physical_page_return": "NOT_OBSERVED：不在探针观测面内。",
            ],
        ]
        try Self.writeEvidence(evidence, filename: "kv-detached-fork-cache-kinds.json")
        print(
            "[KV-DETACHED-KINDS] detachable=\(continued.keys.sorted()) "
                + "refused=\(refusals.count) continued=\(continued)")
    }

    /// 走一遍严格路径：复制 → 兑现 → 门 → 第三方仪器 → 类型/元数据不变。返回复制品。
    ///
    /// 两套观测刻意都用上：`verify` 是被测实现自己的门，`KVStorageProbe` 是另一套
    /// 独立实现。只有两者都说“不同址、同数值”，才不是自己证明自己。
    @discardableResult
    private static func checkDetached(
        _ name: String, _ source: KVCache, evidence: inout [String: Any]
    ) throws -> KVCache {
        // 复制前先采源分支：值摘要必须描述“复制之前”的字节。
        let before = KVStorageProbe.sample(source.state, tag: "source", includeValues: true)
        XCTAssertFalse(before.isEmpty, "\(name)：源 cache 没有可见数组，这一格什么都没测到。")
        XCTAssertTrue(
            before.allSatisfy(\.isComparable), "\(name)：源数组不可比较，仪器不可用（\(before.count) 个）。")

        let detached = try KVCacheDetachment.detachedCopy(of: source)
        KVCacheDetachment.evaluate([detached])

        // ① 依赖自己的门
        let report = try KVCacheDetachment.verify(
            source: [source], detached: [detached], tag: name,
            sourceTokenCount: source.offset, detachedTokenCount: detached.offset)
        XCTAssertTrue(
            report.storageSeparated,
            "\(name)：门报告存储未分离（separated=\(report.addressesSeparated)/\(report.arrays)）。")
        XCTAssertTrue(
            report.valuesPreserved,
            "\(name)：门报告数值不一致（values=\(report.valuesMatched)/\(report.arrays)）。")
        XCTAssertEqual(
            report.arrays, before.count,
            "\(name)：门验证的数组数（\(report.arrays)）与仪器看到的（\(before.count)）不同：门只查了子集。")
        XCTAssertEqual(report.processedTokenCount, source.offset, "\(name)：门的 token 数与源不同。")
        XCTAssertGreaterThan(report.bytes, 0, "\(name)：复制没有搬任何字节。")
        XCTAssertFalse(report.cacheKinds.isEmpty, "\(name)：门没有记录任何 cache 类型。")

        // ② 第三方仪器（独立实现，不采信门的结论）
        let after = KVStorageProbe.sample(detached.state, tag: "source", includeValues: true)
        let relation = KVStorageProbe.compare(before, after)
        XCTAssertTrue(
            relation.onlyInFirst.isEmpty && relation.onlyInSecond.isEmpty,
            "\(name)：复制后数组结构变了（\(relation.summary)）。")
        XCTAssertEqual(
            relation.sharedCount, 0, "\(name)：复制后仍有同址数组（\(relation.summary)）。")
        XCTAssertEqual(
            relation.sameValueCount, relation.pairs.count,
            "\(name)：复制改变了数值（\(relation.summary)）。")
        XCTAssertEqual(
            relation.valueComparedCount, relation.pairs.count,
            "\(name)：有数组没有参与数值比较（\(relation.summary)）。")
        XCTAssertEqual(relation.pairs.count, before.count, "\(name)：配对数与源记录数不同。")
        for pair in relation.pairs {
            XCTAssertEqual(
                pair.firstShape, pair.secondShape,
                "\(name)：\(pair.role) 的形状变了 \(pair.firstShape) -> \(pair.secondShape)")
        }

        // ③ 复制不是“换个类型”：类型 / offset / metaState 都要原样
        XCTAssertEqual(
            String(describing: type(of: detached)), String(describing: type(of: source)),
            "\(name)：复制改变了 cache 的具体类型。")
        XCTAssertEqual(detached.offset, source.offset, "\(name)：offset 变了。")
        XCTAssertEqual(
            detached.metaState, source.metaState,
            "\(name)：metaState 变了（\(source.metaState) -> \(detached.metaState)）。")

        evidence[name] = [
            "leaves": report.leaves,
            "arrays": report.arrays,
            "bytes": report.bytes,
            "cache_kinds": report.cacheKinds,
            "storage_separated": report.storageSeparated,
            "values_preserved": report.valuesPreserved,
            "offset": source.offset,
            "meta_state": source.metaState,
            "independent_probe": [
                "summary": relation.summary,
                "compared": relation.pairs.count,
                "shared": relation.sharedCount,
                "same_value": relation.sameValueCount,
            ],
        ] as [String: Any]
        return detached
    }

    // MARK: - 证据

    /// 一轮真实的续算，同时把 `GenerateCompletionInfo` 带出来。
    ///
    /// `cachedPromptTokenCount` 是这一轮**没重新 prefill** 的 prompt token 数：
    /// `extend` 时它等于父分支的缓存行数，`rewind` 时它就是回退后的写入起点。
    /// 所以“child 到底写到哪一行”不是推测，是模型路径自报的。
    private static func runTurn(
        _ session: ChatSession, _ prompt: String
    ) async throws -> (text: String, info: GenerateCompletionInfo?) {
        var text = ""
        var info: GenerateCompletionInfo?
        for try await item in session.streamDetails(to: prompt) {
            if let chunk = item.chunk { text += chunk }
            if let value = item.info { info = value }
        }
        return (text, info)
    }

    /// 写入者这一轮写入的行区间，以及它与**另一方**可见范围的关系。
    /// 用例 3 的写入者是 child，另一方是父分支；用例 5 正好相反。
    private struct WriteRange {
        let writeStart: Int
        let prefilled: Int
        let generated: Int
        let otherRows: Int
        let writerRows: Int
        /// 写入前写入者数组的**底层行距**（每个 head 在 buffer 里占多少行），由 `strides` 推出。
        /// 它不等于 `state.shape[2]`：后者是可见行数。只有自己拥有整段 buffer 的数组
        /// 才有 `dim(2) == pitchRows`；fork 出来的 child 拿到的是父分支 buffer 的切片视图，
        /// 它的 `dim(2)` 只有可见行数，pitchRows 却仍是父分支那段。
        /// 所以 pitchRows 不能被读成“某一侧的容量”，它只能配合“写入后行距是否变化”一起读：
        /// 行距变大就说明走了 reset/concatenated，行距不变才说明写在了既有 extent 内。
        let pitchRows: Int
        let overlapRows: Int
        let writeEnd: Int

        var pitchSurplus: Int { pitchRows - writerRows }
        /// 写入末行落在写入前就存在的 extent 内。落在内才可能走 `slice_update`
        /// 而不是 reset/concatenated（是否真的没扩容，另由写入后的行距验证）。
        var fitsInExistingExtent: Bool {
            pitchRows > 0 && writeEnd > 0 && writeEnd <= pitchRows
        }
    }

    private static func writeRange(
        info: GenerateCompletionInfo?, visibleRows: Int, writer sample: KVStorageSample
    ) -> WriteRange {
        let writeStart = info?.cachedPromptTokenCount ?? -1
        let prefilled = info?.promptTokenCount ?? -1
        let generated = info?.generationTokenCount ?? -1
        // 写入前该侧的可见行数（`state` 的 shape[2]，等于 offset）。
        let writerRows = sample.records.map(\.shape).filter { $0.count == 4 }.map { $0[2] }.max() ?? 0
        let end = max(writeStart, 0) + max(prefilled, 0) + max(generated, 0)
        let overlap = writeStart < 0 ? 0 : max(0, min(end, visibleRows) - writeStart)
        return .init(
            writeStart: writeStart, prefilled: prefilled, generated: generated,
            otherRows: visibleRows, writerRows: writerRows,
            pitchRows: pitchRows(sample),
            overlapRows: overlap, writeEnd: end)
    }

    /// 由 `strides` 推出的底层行距：每个 head 在 buffer 里占多少行。
    ///
    /// 4 维注意力数组 `[B, H, rows, D]` 的 `strides[1] / strides[2]` 就是它；
    /// 折叠后的视图（`state` 返回 `keys[.ellipsis, ..<offset, 0...]`）继承的是 buffer 的
    /// strides，所以这个数读的是“视图指向的那段存了多少行”，不是视图自己的行数。
    private static func pitchRows(_ sample: KVStorageSample) -> Int {
        sample.records
            .filter { $0.shape.count == 4 && $0.strides.count == 4 && $0.strides[2] > 0 }
            .map { $0.strides[1] / $0.strides[2] }
            .max() ?? 0
    }

    /// 该侧 `state` 的可见行数（`shape[2]` 的最大值）。四维数组里它是序列轴。
    private static func visibleRows(_ sample: KVStorageSample) -> Int {
        sample.records
            .map(\.shape)
            .filter { $0.count == 4 }
            .map { $0[2] }
            .max() ?? 0
    }

    /// 真正被写进 cache 的 KV 数据。
    ///
    /// 每个元素都不同：复制若把行序、head 序或打包字序接错，摘要就会不同。
    /// 全零或同一个标量会让“复制错了”看起来和“复制对了”一样。
    private static func block(rows: Int, headDim: Int = 8, seed: Float) -> MLXArray {
        let values = (0 ..< (rows * headDim)).map { Float($0) * 0.25 + seed }
        return MLXArray(values).reshaped([1, 1, rows, headDim])
    }

    /// `writer` 是写入者，`other` 是必须不被穿透的一方；只影响字段名，不影响数值。
    ///
    /// `pitchRowsAfter` 才是“有没有扩容”的判据：reset/concatenated 会把 extent 撑成
    /// `previous + step`，行距一定变；行距不变则是 `slice_update` 落在既有 extent 内。
    private static func json(
        _ range: WriteRange, writer: String = "child", other: String = "parent",
        pitchRowsAfter: Int? = nil
    ) -> [String: Any] {
        var fields: [String: Any] = [
            "write_start_row": range.writeStart,
            "prefilled_tokens": range.prefilled,
            "generated_tokens": range.generated,
            "write_end_row": range.writeEnd,
            "\(other)_visible_rows": range.otherRows,
            "\(writer)_visible_rows_before_write": range.writerRows,
            "\(writer)_storage_pitch_rows_before_write": range.pitchRows,
            "\(writer)_storage_pitch_surplus_rows": range.pitchSurplus,
            "write_fits_existing_extent": range.fitsInExistingExtent,
            "rows_overlapping_\(other)_visible_range": range.overlapRows,
        ]
        if let pitchRowsAfter {
            fields["\(writer)_storage_pitch_rows_after_write"] = pitchRowsAfter
            fields["write_grew_extent"] = pitchRowsAfter != range.pitchRows
        }
        return fields
    }

    private static func relation(_ overlap: KVStorageOverlap) -> String {
        guard !overlap.pairs.isEmpty else { return "UNRESOLVED_NO_PAIRS" }
        guard overlap.onlyInFirst.isEmpty, overlap.onlyInSecond.isEmpty else {
            return "UNRESOLVED_TOPOLOGY"
        }
        if overlap.sharedCount == overlap.pairs.count { return "SHARED_ALL" }
        if overlap.sharedCount == 0 { return "INDEPENDENT_ALL" }
        return "MIXED"
    }

    private static func records(_ sample: KVStorageSample) -> [[String: Any]] {
        records(sample.records)
    }

    private static func records(_ list: [KVStorageSample.ArrayRecord]) -> [[String: Any]] {
        list.map { record in
            [
                "tag": record.tag,
                "path": record.path,
                "cache_kind": record.cacheKind,
                "role": record.role,
                "dtype": record.dtype,
                "shape": record.shape,
                "strides": record.strides,
                "byte_count": record.byteCount,
                // 十六进制字符串，避免把地址误读成可持久复用的标识。
                "address": String(record.address, radix: 16),
                "address_stable": record.addressStable,
                "is_comparable": record.isComparable,
                "value_digest": record.valueDigest.map { String($0, radix: 16) as Any }
                    ?? NSNull(),
            ]
        }
    }

    private static func json(_ sample: KVStorageSample) -> [String: Any] {
        [
            "processed_token_count": sample.processedTokenCount.map { $0 as Any } ?? NSNull(),
            "is_comparable": sample.isComparable,
            "record_count": sample.records.count,
            "allocator": [
                "active_bytes": sample.allocator.activeBytes,
                "cached_bytes": sample.allocator.cachedBytes,
                "peak_bytes": sample.allocator.peakBytes,
            ],
        ]
    }

    private static func json(_ overlap: KVStorageOverlap, verdict: String) -> [String: Any] {
        var output: [String: Any] = [
            "verdict": verdict,
            "compared": overlap.comparedCount,
            "shared": overlap.sharedCount,
            "is_fully_shared": overlap.isFullyShared,
            "is_fully_independent": overlap.isFullyIndependent,
            "only_in_first": overlap.onlyInFirst.sorted(),
            "only_in_second": overlap.onlyInSecond.sorted(),
        ]
        output["same_value"] = overlap.sameValueCount
        output["compared_for_value"] = overlap.valueComparedCount
        output["is_value_fully_unchanged"] = overlap.isValueFullyUnchanged
        output["pairs"] = overlap.pairs.map { pair in
            [
                "key": "\(pair.tag)/\(pair.path.map(String.init).joined(separator: "."))/\(pair.role)",
                "first_address": String(pair.firstAddress, radix: 16),
                "second_address": String(pair.secondAddress, radix: 16),
                "same_storage": pair.isSameStorage,
                "first_shape": pair.firstShape,
                "second_shape": pair.secondShape,
                "first_digest": pair.firstDigest.map { String($0, radix: 16) as Any }
                    ?? NSNull(),
                "second_digest": pair.secondDigest.map { String($0, radix: 16) as Any }
                    ?? NSNull(),
                "same_value": pair.isSameValue,
            ] as [String: Any]
        }
        return output
    }

    private static func json(_ overlap: KVStorageOverlap) -> [String: Any] {
        json(overlap, verdict: relation(overlap))
    }

    private static func evidenceURL(_ filename: String) -> URL {
        if let storePath = ProcessInfo.processInfo.environment["SIMIGO_STATE_GRAPH_STORE"],
            !storePath.isEmpty
        {
            return URL(fileURLWithPath: (storePath as NSString).deletingLastPathComponent)
                .appendingPathComponent(filename)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
    }

    /// 证据文件就是这个切片的交付物：用例通过但证据没落盘，等于什么都没测出来。
    /// 所以写盘失败必须让用例失败，而不是打印一行没人看的警告。
    private static func writeEvidence(
        _ evidence: [String: Any],
        filename: String = "kv-storage-identity-probe.json"
    ) throws {
        var evidence = evidence
        evidence["observed_at"] = ISO8601DateFormatter().string(from: Date())
        let url = evidenceURL(filename)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        print("[KV-PROBE] evidence written to \(url.path)")
    }
}

/// 一个只实现了 `state`、没有分离实现的 cache：将来新增的类型就长这样。
///
/// 它存在的意义是证明“未知类型一律拒绝”，而不是被当成能拷的一类放过去。
private final class UnimplementedProbeCache: BaseKVCache {
    override var state: [MLXArray] {
        get { [MLXArray([Float](repeating: 0.25, count: 4))] }
        set { _ = newValue }
    }
}
