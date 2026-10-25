import Foundation
import MLX
@_spi(DetachedForkVerification) import MLXLMCommon
import XCTest

@testable import SimiGo

/// 真实权重上的 detached fork 回归：**旧载体退休之后，续算分支还能跑**。
///
/// model-free 的 `KVCacheStorageIdentityProbeTests` 已经证明：每一种本轮覆盖的 cache
/// 类型，要么被复制到独立存储并通过同一道门，要么被明确拒绝。它证明不了的另一半是
/// 本文件的两件事：
///
///   ① 真实架构（Qwen3-MoE，48 层 × 4 KV heads × head_dim 128 ⇒ 每 token ≈ 96 KiB KV）
///      上，`forkDetached()` 真的能完成，并且第三方仪器（`KVStorageProbe`）在**真实
///      权重产生的数组**上读出 0 个共享地址、全部数值相同。
///   ② 旧分支的最后一个强引用解除之后，新分支仍能在同一批权重上继续生成，且模型路径
///      自报的 `cacheReuseMode` / `processedTokenCount` 说明它用的是复制来的行，不是
///      重新 prefill 一遍。
///
/// 这个文件**不**回答什么：
/// - 旧分支的 allocation 是否真的释放了。本文件只记录 allocator 计数（CONTEXT），
///   并把“释放后字节回到 MLX 复用池”与“物理页归还操作系统”分开陈述。
/// - 复制成本的默认策略。这里测量一次，给出时间与峰值，**不**据此把 `fork()` 改成
///   深拷贝 —— 普通 `fork` 的语义在本切片里没有动。
///
/// 门控：`SIMIGO_KV_DETACH_MODEL=<本机 MLX 权重目录>`。缺省 `XCTSkip`，因为
/// 30B 级权重不该在默认测试里被加载。
final class KVCacheDetachedForkRealModelTests: XCTestCase {

    private static let gateVariable = "SIMIGO_KV_DETACH_MODEL"
    private static let evidenceName = "kv-detached-fork-real-model.json"

    /// 复制之后要验证的行窗口。窗口只影响第三方摘要读多少行，不影响门：门比较的是
    /// 完整 `state`（`KVCacheDetachment.verify`），窗口是给 `KVStorageProbe` 用的。
    private static let digestRows = 64

    /// 分配粒度的假设值，只用于核对「观察到的 active delta 是否与按页取整的
    /// 预测一致」。它不是从 MLX 读来的配置，也不参与任何验收断言。
    private static let allocationGranularity = 16 * 1024

    override func setUp() {
        super.setUp()
        // 每个断言都是同一段测量链上的一环：前一步失败后再跑下一步只会读到噪声。
        continueAfterFailure = false
    }

    // MARK: - 门控

    private static func requireModel() throws -> String {
        guard let path = ProcessInfo.processInfo.environment[gateVariable],
            !path.isEmpty
        else {
            throw XCTSkip("真实模型 detached fork 回归：需 \(gateVariable)=<权重目录>")
        }
        guard FileManager.default.fileExists(atPath: path + "/config.json") else {
            throw XCTSkip("模型不存在：\(path)")
        }
        return path
    }

    // MARK: - 用例

    func testDetachedForkOnRealWeightsSurvivesSourceRetirement() async throws {
        let path = try Self.requireModel()

        let loadStarted = Date()
        let container = try await NativeMLX.loadModelContainer(path: path)
        let loadSeconds = Date().timeIntervalSince(loadStarted)

        var evidence: [String: Any] = [
            "gate": [Self.gateVariable: path],
            "model": [
                "path": path,
                "load_seconds": loadSeconds,
                "allocator_after_load": Self.allocator(),
            ],
            "boundary": [
                "verified": "the surviving branch's visible KV arrays read storage the source does not read,"
                    + " and present the same values, shapes, dtypes, offsets and cache metadata",
                "not_verified": [
                    "the source's last reference is released",
                    "the allocator returns those bytes to the operating system",
                    "anything about physical pages",
                ],
                "notes": [
                    "allocator counters are CONTEXT: a drop cannot be attributed to one allocation,"
                        + " and a rise cannot prove one is still held",
                    "a plain fork() still shares storage; that behaviour is unchanged by this slice",
                ],
            ],
        ]

        var arms: [[String: Any]] = []
        for arm in Self.arms {
            arms.append(try await run(arm, on: container, modelPath: path))
        }
        evidence["arms"] = arms

        let allVerified = arms.allSatisfy { ($0["detach_verified"] as? Bool) == true }
        let allContinued = arms.allSatisfy { ($0["continued_after_retirement"] as? Bool) == true }
        let allRetired = arms.allSatisfy { ($0["source_deallocated"] as? Bool) == true }
        evidence["verdict"] = allVerified && allContinued && allRetired
            ? "REAL_MODEL_DETACHED_FORK_VERIFIED"
            : "REAL_MODEL_DETACHED_FORK_INCOMPLETE"
        XCTAssertTrue(
            allVerified && allContinued && allRetired,
            "真实模型上没有同时满足：存储分离 + 旧分支已释放 + 新分支续算 | \(evidence["verdict"]!)")

        try Self.writeEvidence(evidence)
    }

    // MARK: - 每条臂

    private struct Arm {
        let name: String
        /// `nil` 时不设窗口上限：Qwen3 的全注意力层因此得到 `KVCacheSimple`。
        let maxKVSize: Int?
        /// 这条臂应当出现的叶子 cache 类型。断言它是为了让“覆盖了哪种 cache”不是
        /// 靠推断，而是靠观测。
        let expectKind: String
        /// `KVCacheSimple` 上续算必然复用缓存前缀；窗口化 rotating 的复用计数由实现
        /// 决定（可能因容量不足而重建），所以只在这里断言前者，后者仅记录。
        let assertPrefixReuse: Bool
        let why: String
    }

    private static let arms: [Arm] = [
        .init(
            name: "simple",
            maxKVSize: nil,
            expectKind: "KVCacheSimple",
            assertPrefixReuse: true,
            why: "全注意力、无窗口上限：缓存按 token 线性增长，是最常见的续算载体"),
        .init(
            name: "rotating",
            maxKVSize: 64,
            expectKind: "RotatingKVCache",
            assertPrefixReuse: false,
            why: "窗口化缓存：state 是回绕后的窗口视图，复制路径与 metaState 恢复都不同"),
    ]

    private func run(_ arm: Arm, on container: ModelContainer, modelPath: String) async throws
        -> [String: Any]
    {
        var evidence: [String: Any] = [
            "arm": arm.name,
            "why": arm.why,
            "max_kv_size": arm.maxKVSize.map { $0 as Any } ?? NSNull(),
            "expect_kind": arm.expectKind,
        ]

        // 参数决定 cache 形态（maxKVSize 决定 rotating），因此必须建 session 前给定。
        let parameters = GenerateParameters(
            maxTokens: 8, maxKVSize: arm.maxKVSize, temperature: 0)
        // 保持可选：退休那一步要把最后一个强引用置空，`let` 做不到。
        var parent: ChatSession? = ChatSession(container, generateParameters: parameters)
        weak var weakParent = parent

        // 1. seed：一轮足够长的 prompt，让缓存里有真实的行。
        let seed = try await Self.turn(parent!, Self.seedPrompt)
        let seedInfo = seed.info
        XCTAssertGreaterThan(
            seedInfo?.promptTokenCount ?? 0, 0, "\(arm.name): seed 没有 prefill 任何 token")
        evidence["seed"] = [
            "prompt_characters": Self.seedPrompt.count,
            "prompt_tokens": seedInfo?.promptTokenCount ?? -1,
            "generated_tokens": seedInfo?.generationTokenCount ?? -1,
            "generated_text": Self.preview(seed.text),
        ]

        // 2. 复制前采样（父分支仍存活）。第三方仪器的地址在这里才有意义。
        let before = await parent!.probeKVStorage(
            includeValues: true, valueRows: Self.digestRows)
        XCTAssertTrue(
            before.isComparable,
            "\(arm.name): 复制前采样不可比较（有数组读不到稳定地址），后续任何地址比较都不成立")
        let kinds = Set(before.records.map(\.cacheKind))
        evidence["before"] = Self.sampleJSON(before, kinds: kinds)
        XCTAssertTrue(
            kinds.contains(arm.expectKind),
            "\(arm.name): 这条臂要覆盖 \(arm.expectKind)，实际出现的叶子类型是 \(kinds.sorted())")

        // 3. 负向对照：普通 fork 必须被同一道门拒绝。
        //    没有这一步，“分离已验证”也可能只是门在真实权重上什么都没检查。
        var control = ""
        do {
            let shared = await parent!.fork()
            do {
                _ = try await shared.verifyStorageSeparation(from: parent!)
                XCTFail("\(arm.name): 普通 fork 通过了存储分离门 —— 这道门在真实权重上是空转")
                control = "unexpectedly-passed"
            } catch let error as DetachedForkError {
                control = error.description
            }
        }
        evidence["plain_fork_control"] = ["rejected": !control.isEmpty, "reason": control]

        // 4. detached fork：计时 + 峰值。先归零 peak，才能把这次复制的瞬时开销
        //    从 17 GB 级模型加载的峰值里分出来。
        Memory.peakMemory = 0
        let activeBefore = Memory.activeMemory
        let cachedBefore = Memory.cacheMemory
        let started = DispatchTime.now().uptimeNanoseconds
        let forked = try await parent!.forkDetached()
        let forkSeconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
        let activeAfter = Memory.activeMemory
        let peakAfter = Memory.peakMemory
        let cachedAfter = Memory.cacheMemory
        var child: ChatSession? = forked.session
        let report = forked.report

        XCTAssertTrue(report.storageSeparated, "\(arm.name): \(report.summary)")
        XCTAssertTrue(report.valuesPreserved, "\(arm.name): \(report.summary)")
        XCTAssertEqual(
            report.main.arrays, before.records.filter { $0.tag == "main" }.count,
            "\(arm.name): 门验证的数组数与仪器采到的数组数不一致，说明只验证了子集")
        XCTAssertGreaterThan(report.bytes, 0)

        // 内存口径（上一轮报告最大的缺陷就在这里）：三个数字来自三个不同的
        // 度量，不能互相替代。这里把每个数的**来源、窗口、包含什么**写清楚，
        // 并单独算一遍「按 16 KiB 分配粒度」的预测值供核对；核对结果只作为证据，
        // 不作为门——内存指标不是本用例的验收对象。
        let activeDelta = activeAfter - activeBefore
        let perArrayLogical = report.arrays > 0 ? report.bytes / report.arrays : 0
        let perArrayPages = (perArrayLogical + Self.allocationGranularity - 1)
            / Self.allocationGranularity
        let predictedDelta = perArrayPages * Self.allocationGranularity * report.arrays
        let deltaResidual = activeDelta - predictedDelta

        evidence["fork"] = [
            "seconds": forkSeconds,
            "arrays": report.arrays,
            "leaves": report.leaves,
            "bytes_copied": report.bytes,
            "storage_separated": report.storageSeparated,
            "values_preserved": report.valuesPreserved,
            "cache_kinds": report.cacheKinds,
            "processed_token_count": report.main.processedTokenCount,
            "sections": report.sections.map {
                [
                    "tag": $0.tag, "leaves": $0.leaves, "arrays": $0.arrays, "bytes": $0.bytes,
                    "values_matched": $0.valuesMatched,
                    "addresses_separated": $0.addressesSeparated,
                    "tokens": $0.processedTokenCount, "kinds": $0.cacheKinds,
                ] as [String: Any]
            },
            "memory": [
                "metric_basis": [
                    "bytes_copied": "复制数组的 mlx_array nbytes 之和（逻辑字节），"
                        + "来自验证报告本身；不是分配器页，也不是常驻内存。",
                    "active_delta": "forkDetached 前后的进程级 Memory.activeMemory 差值。"
                        + "窗口内 MLX 活动分配、分配器复用池归还/取用、以及与该调用无关的"
                        + "进程分配都会落在里面；它不等于复制字节数，也不等于新增物理页。",
                    "peak_window": "peak 在 forkDetached 之前被重置，窗口恰好覆盖「复制 → 求值 → 验证」，"
                        + "且窗口结束时父、子两个会话都仍然存活（没有退休源）。",
                    "transient_over_active": "窗口内进程级峰值减去窗口结束时的 active。"
                        + "含分配器预留与门比较用的临时数组；不得当作 detached copy 的内存开销。",
                    "is_cost_claim": false,
                ],
                "active_before": activeBefore,
                "active_after": activeAfter,
                "active_delta": activeDelta,
                "cached_before": cachedBefore,
                "cached_after": cachedAfter,
                "peak_after": peakAfter,
                "transient_over_active": peakAfter - activeAfter,
                "granularity_check": [
                    "assumed_bytes": Self.allocationGranularity,
                    "bytes_per_array_logical": perArrayLogical,
                    "pages_per_array": perArrayPages,
                    "predicted_active_delta": predictedDelta,
                    "observed_active_delta": activeDelta,
                    "observed_minus_predicted": deltaResidual,
                    "model_matches": deltaResidual == 0,
                ],
                "note": "bytes_copied 是唯一可以直接引用的复制量；"
                    + "active_delta 与 transient_over_active 是进程级观察值，"
                    + "不参与复制成本结论。",
            ],
        ]

        // 5. 第三方仪器复核：0 个共享地址 + 全部数值相同（门之外的第二套观测）。
        let after = await child!.probeKVStorage(
            includeValues: true, valueRows: Self.digestRows)
        let overlap = KVStorageProbe.compare(before, after)
        evidence["cross_check"] = [
            "compared": overlap.comparedCount,
            "shared": overlap.sharedCount,
            "same_value": overlap.sameValueCount,
            "value_compared": overlap.valueComparedCount,
            "only_in_first": overlap.onlyInFirst,
            "only_in_second": overlap.onlyInSecond,
            "summary": overlap.summary,
        ]
        XCTAssertEqual(
            overlap.comparedCount, before.records.count,
            "\(arm.name): 配对记录数少于采样数，拓扑变了")
        XCTAssertTrue(
            overlap.onlyInFirst.isEmpty && overlap.onlyInSecond.isEmpty,
            "\(arm.name): 复制前后 cache 拓扑不同")
        XCTAssertEqual(overlap.sharedCount, 0, "\(arm.name): \(overlap.summary)")
        XCTAssertTrue(overlap.isValueFullyUnchanged, "\(arm.name): \(overlap.summary)")

        // 6. 退休旧载体：解除最后一个强引用，并证明对象真的没了。
        let childAddresses = after.records.map(\.address)
        parent = nil
        var released = false
        for _ in 0 ..< 64 {
            if weakParent == nil {
                released = true
                break
            }
            await Task.yield()
        }
        XCTAssertTrue(released, "\(arm.name): 旧分支仍有强引用，续算结论不能算“旧载体退休后”")

        // 旧分支消失之后，幸存分支的存储身份不应被牵动（它读的是自己的 buffer）。
        let afterRelease = await child!.probeKVStorage(includeValues: false)
        let childAddressesUnchanged = afterRelease.records.map(\.address) == childAddresses
        XCTAssertTrue(
            childAddressesUnchanged, "\(arm.name): 旧分支释放后，新分支的存储地址变了")
        evidence["retirement"] = [
            "source_deallocated": released,
            "child_addresses_unchanged": childAddressesUnchanged,
            "allocator_after_release": Self.allocator(),
            "note": "activeMemory 下降只说明记账变化；字节可能回到 MLX 复用池，"
                + "这与“操作系统收回物理页”是两件事，本用例不宣称后者",
        ]

        // 7. 真实续算：旧载体已经不在，新分支继续跑。
        let continued = try await Self.turn(child!, Self.continuePrompt)
        let continuedInfo = continued.info
        let afterContinue = await child!.probeKVStorage(includeValues: false)
        let rowsBefore = afterRelease.processedTokenCount ?? -1
        let rowsAfter = afterContinue.processedTokenCount ?? -1

        evidence["continuation"] = [
            "text": Self.preview(continued.text),
            "prompt_tokens": continuedInfo?.promptTokenCount ?? -1,
            "cached_prompt_tokens": continuedInfo?.cachedPromptTokenCount ?? -1,
            "generated_tokens": continuedInfo?.generationTokenCount ?? -1,
            "cache_reuse_mode": continuedInfo?.cacheReuseMode ?? "nil",
            "processed_tokens_before": rowsBefore,
            "processed_tokens_after": rowsAfter,
            "allocator_after_continuation": Self.allocator(),
        ]

        XCTAssertFalse(continued.text.isEmpty, "\(arm.name): 旧分支释放后新分支没有产出")
        XCTAssertGreaterThan(
            continuedInfo?.generationTokenCount ?? 0, 0, "\(arm.name): 新旧分支续算没有生成 token")
        XCTAssertGreaterThan(
            rowsAfter, rowsBefore, "\(arm.name): 续算之后缓存行数没有推进")
        if arm.assertPrefixReuse {
            XCTAssertGreaterThan(
                continuedInfo?.cachedPromptTokenCount ?? 0, 0,
                "\(arm.name): 续算把整段 prompt 重新 prefill 了，说明用的不是复制来的缓存")
        }

        evidence["detach_verified"] = report.storageSeparated && report.valuesPreserved
        evidence["continued_after_retirement"] =
            !continued.text.isEmpty && rowsAfter > rowsBefore
        evidence["source_deallocated"] = released
        child = nil
        return evidence
    }

    // MARK: - 生成

    private static func turn(
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

    /// 约 190 token 的种子 prompt（Qwen 系分词器约 4 字符/token）。
    /// 行数足够让窗口化臂真正回绕（maxKVSize=64），又不至于让复制成本失真。
    private static let seedPrompt: String = {
        var lines: [String] = []
        for index in 0 ..< 10 {
            lines.append(
                "Line \(index): the carrier keeps its own copy of every key and value"
                    + " it has already processed.")
        }
        return lines.joined(separator: "\n") + "\n\nReply with exactly one word: ready."
    }()

    private static let continuePrompt = "Continue the list from Line 10 onwards."

    // MARK: - 证据

    private static func allocator() -> [String: Int] {
        [
            "active": Memory.activeMemory,
            "cached": Memory.cacheMemory,
            "peak": Memory.peakMemory,
        ]
    }

    private static func sampleJSON(
        _ sample: KVStorageSample, kinds: Set<String>
    ) -> [String: Any] {
        [
            "arrays": sample.records.count,
            "bytes": sample.records.reduce(0) { $0 + $1.byteCount },
            "cache_kinds": kinds.sorted(),
            "roles": sample.records.map(\.role),
            "shapes": sample.records.map { $0.shape.map(String.init).joined(separator: "x") },
            "dtypes": Array(Set(sample.records.map(\.dtype))).sorted(),
            "addresses_stable": sample.records.allSatisfy(\.addressStable),
            "processed_token_count": sample.processedTokenCount.map { $0 as Any } ?? NSNull(),
            "allocator": [
                "active": sample.allocator.activeBytes,
                "cached": sample.allocator.cachedBytes,
                "peak": sample.allocator.peakBytes,
            ],
        ]
    }

    private static func preview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count <= 200 ? trimmed : String(trimmed.prefix(200)) + "…"
    }

    private static func evidenceURL(_ filename: String) -> URL {
        if let storePath = ProcessInfo.processInfo.environment["SIMIGO_STATE_GRAPH_STORE"],
            !storePath.isEmpty
        {
            return URL(fileURLWithPath: (storePath as NSString).deletingLastPathComponent)
                .appendingPathComponent(filename)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }

    /// 用例通过但证据没落盘，等于什么都没测出来：写盘失败必须让用例失败。
    private static func writeEvidence(_ evidence: [String: Any]) throws {
        var evidence = evidence
        evidence["observed_at"] = ISO8601DateFormatter().string(from: Date())
        let url = evidenceURL(evidenceName)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONSerialization.data(
            withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        print("[KV-DETACHED-REAL] evidence written to \(url.path)")
    }
}
