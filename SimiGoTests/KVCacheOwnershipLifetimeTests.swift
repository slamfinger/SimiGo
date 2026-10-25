import Foundation
import MLX
@_spi(DetachedForkVerification) import MLXLMCommon
import XCTest

@testable import SimiGo

/// 真实权重上的 **allocation 生命周期对照**：普通共享 fork 与严格 detached fork
/// 在同一个四阶段时间轴上，`Data` owner 的存活状态必须相反。
///
/// 这个文件与 `KVCacheDetachedForkRealModelTests` 的分工：
/// - 那个文件证明「存储分离 + 值一致 + 旧载体退休后还能续算」；
/// - 这个文件证明「**谁**还持有那块 allocation」，用的是非持有式弱引用观察，
///   而不是 `Memory.activeMemory` 的差值。
///
/// 四阶段（每一阶段都有共享臂做负向对照）：
///
/// | 阶段 | 共享 fork | detached fork |
/// | --- | --- | --- |
/// | fork 后父子都存活 | 对应数组共享 owner | 父子 owner 不同 |
/// | 释放父分支，child 存活 | 原共享 owner 仍存活 | 原父 owner 应当过期 |
/// | child 继续真实推理 | 原共享存储仍被 child 持有 | child 用重新捕获得到的自己的存储 |
/// | 清空 child 与全部测试数组 | 原 owner 最终过期 | child owner 最终过期 |
///
/// 三种结论在本文件里始终分开：
/// - `Data` owner 过期：弱引用读到 expired，只说明最后一个强引用消失；
/// - buffer 进入 MLX 复用池：**未观测**（本文件不读 allocator 内部状态）；
/// - 物理页归还操作系统：**未观测**，且不能由前两项推导。
///
/// 门控：`SIMIGO_KV_OWNERSHIP_MODEL=<本机 MLX 权重目录>`。缺省 `XCTSkip`。
final class KVCacheOwnershipLifetimeTests: XCTestCase {

    private static let gateVariable = "SIMIGO_KV_OWNERSHIP_MODEL"
    private static let evidenceName = "kv-ownership-lifetime.json"

    private enum Arm: String, CaseIterable {
        case shared
        case detached
    }

    override func setUp() {
        super.setUp()
        // 四阶段是一条链：前一阶段失败后再读后一阶段只会得到噪声。
        continueAfterFailure = false
    }

    private static func requireModel() throws -> String {
        guard let path = ProcessInfo.processInfo.environment[gateVariable],
            !path.isEmpty
        else {
            throw XCTSkip("真实模型 allocation 生命周期对照：需 \(gateVariable)=<权重目录>")
        }
        guard FileManager.default.fileExists(atPath: path + "/config.json") else {
            throw XCTSkip("模型不存在：\(path)")
        }
        return path
    }

    // MARK: - 用例

    func testOwnerExpiryDiffersBetweenSharedAndDetachedFork() async throws {
        let path = try Self.requireModel()
        let container = try await NativeMLX.loadModelContainer(path: path)

        var arms: [[String: Any]] = []
        for arm in Arm.allCases {
            arms.append(try await run(arm, on: container, modelPath: path))
        }

        let verdicts = arms.compactMap { $0["verdict"] as? String }
        let passed = verdicts.count == Arm.allCases.count
            && verdicts.allSatisfy { $0 == "OWNERSHIP_LIFETIME_VERIFIED" }
        var evidence: [String: Any] = [
            "gate": [Self.gateVariable: path],
            "model": ["path": path],
            "boundary": [
                "verified": "for every KV array: which `Data` owns it, whether a sibling fork shares that owner,"
                    + " and whether the last strong reference to the source's owner has disappeared",
                "not_verified": [
                    "the released buffer left MLX's reusable pool",
                    "the operating system reclaimed physical pages",
                ],
                "notes": [
                    "the probe stores std::weak_ptr<Data> only; capture() reads each array once and drops it",
                    "a cache write rebinds arrays, so stage 3 re-captures instead of reading stale entries",
                    "allocator counters are recorded as CONTEXT, never as a lifetime claim",
                ],
            ],
            "arms": arms,
            "verdict": passed ? "OWNERSHIP_LIFETIME_VERIFIED" : "OWNERSHIP_LIFETIME_INCOMPLETE",
        ]
        evidence["all_arms_passed"] = passed
        XCTAssertTrue(passed, "四阶段对照未全部通过：\(verdicts)")
        try Self.writeEvidence(evidence)
    }

    // MARK: - 一条臂

    private func run(_ arm: Arm, on container: ModelContainer, modelPath: String) async throws
        -> [String: Any]
    {
        var evidence: [String: Any] = ["arm": arm.rawValue, "model_path": modelPath]

        let parameters = GenerateParameters(maxTokens: 8, maxKVSize: nil, temperature: 0)
        var source: ChatSession? = ChatSession(container, generateParameters: parameters)
        weak var weakSource = source

        // 0. seed：让缓存里真的有行，否则“覆盖全部 KV 数组”无从谈起。
        let seed = try await Self.turn(source!, Self.seedPrompt)
        XCTAssertGreaterThan(seed.info?.promptTokenCount ?? 0, 0, "\(arm): seed 没有 prefill")
        let sampled = await source!.probeKVStorage()
        let parent = await source!.watchKVOwnership()

        // 覆盖性：快照必须与地址级仪器的记录数一致，不能只挑一个数组。
        XCTAssertEqual(
            parent.entries.count, sampled.records.count,
            "\(arm): 所有权快照覆盖 \(parent.entries.count) 个数组，地址级仪器看到 \(sampled.records.count) 个")
        XCTAssertGreaterThan(parent.entries.count, 0, "\(arm): 快照为空")
        XCTAssertTrue(parent.allAlive, "\(arm): fork 之前源 owner 就已过期")
        evidence["source"] = [
            "arrays": sampled.records.count,
            "owners": parent.liveIdentities.count,
            "processed_tokens": parent.processedTokenCount.map { $0 as Any } ?? NSNull(),
            "kinds": Array(Set(parent.entries.map(\.cacheKind))).sorted(),
            "snapshot": parent.summary(),
        ]

        // 1. fork：共享臂走普通 `fork()`，严格臂走 `forkDetached()`。
        var child: ChatSession?
        switch arm {
        case .shared:
            child = await source!.fork()
        case .detached:
            let forked = try await source!.forkDetached()
            child = forked.session
            evidence["fork_report"] = [
                "arrays": forked.report.arrays,
                "leaves": forked.report.leaves,
                "bytes": forked.report.bytes,
                "storage_separated": forked.report.storageSeparated,
                "values_preserved": forked.report.valuesPreserved,
                "cache_kinds": forked.report.cacheKinds,
            ]
        }
        let childAtFork = await child!.watchKVOwnership()
        let overlap = KVOwnershipProbe.compare(parent: parent, child: childAtFork)
        evidence["stage1_after_fork"] = [
            "parent": parent.summary(),
            "child": childAtFork.summary(),
            "overlap": overlap.summary(),
        ]
        XCTAssertEqual(
            childAtFork.entries.count, parent.entries.count,
            "\(arm): fork 之后子分支的数组集合与父分支不同，配对不可比")
        XCTAssertTrue(childAtFork.allAlive, "\(arm): fork 之后子 owner 不存活")
        switch arm {
        case .shared:
            XCTAssertTrue(
                overlap.allShared,
                "\(arm): 普通 fork 的父子数组没有共享 owner —— 共享臂失去负向对照的意义")
        case .detached:
            XCTAssertTrue(
                overlap.allSeparated,
                "\(arm): detached fork 之后父子仍共享 owner（\(overlap.shared) 对），存储并未分离")
        }

        // 2. 释放父分支，child 保持存活。
        source = nil
        let parentAfterRelease = parent
        let aliveAfterRelease = parentAfterRelease.aliveKeys.count
        let expiredAfterRelease = parentAfterRelease.expiredKeys.count
        let childStillAlive = childAtFork.allAlive
        evidence["stage2_parent_released"] = [
            "source_deallocated": weakSource == nil,
            "parent_alive": aliveAfterRelease,
            "parent_expired": expiredAfterRelease,
            "child_alive": childStillAlive,
            "parent_strong_counts": Dictionary(
                parentAfterRelease.entries.map { ($0.key, $0.strongCount) },
                uniquingKeysWith: { a, _ in a }),
        ]
        XCTAssertTrue(childStillAlive, "\(arm): 释放父分支时 child 的 owner 已经过期")
        switch arm {
        case .shared:
            XCTAssertEqual(
                expiredAfterRelease, 0,
                "\(arm): 共享臂里父分支释放后就有 \(expiredAfterRelease) 个 owner 过期 ——"
                    + " 说明 child 并没有共享存储，负向对照不成立")
        case .detached:
            XCTAssertEqual(
                aliveAfterRelease, 0,
                "\(arm): detached fork 之后原父 owner 仍有 \(aliveAfterRelease) 个存活："
                    + " 还有对象持有源存储（强引用计数见 stage2），应当继续追查持有者，"
                    + " 而不能以 clear() 已调用为由判定通过")
        }

        // 3. child 继续真实推理。缓存写入会重新绑定数组，所以这里**重新捕获**，
        //    而不是拿 fork 时刻的旧条目当作“child 仍用原存储”。
        let continued = try await Self.turn(child!, Self.continuePrompt)
        let childAfter = await child!.watchKVOwnership()
        let continuedOwnerKeys = Set(childAfter.entries.map(\.ownerIdentity))
        let sourceOwnerKeys = Set(parent.entries.map(\.ownerIdentity))
        evidence["stage3_child_continued"] = [
            "generated_tokens": continued.info?.generationTokenCount ?? -1,
            "cache_reuse_mode": continued.info?.cacheReuseMode ?? "nil",
            "cached_prompt_tokens": continued.info?.cachedPromptTokenCount ?? -1,
            "child_snapshot": childAfter.summary(),
            "child_owner_identity_overlap_with_source":
                continuedOwnerKeys.intersection(sourceOwnerKeys).count,
        ]
        XCTAssertGreaterThan(
            continued.info?.generationTokenCount ?? 0, 0, "\(arm): child 续算没有生成 token")
        XCTAssertTrue(childAfter.allAlive, "\(arm): 续算之后 child 的 owner 不存活")
        if arm == .detached {
            // 严格臂必须用重新捕获得到的、自己的存储；共享臂里旧数组可能仍挂在 child
            // 的缓存上，所以这条断言只对 detached 成立，共享臂只记录。
            XCTAssertTrue(
                continuedOwnerKeys.intersection(sourceOwnerKeys).isEmpty,
                "\(arm): 续算之后 child 仍在使用源分支的 \(continuedOwnerKeys.intersection(sourceOwnerKeys).count) 个 owner")
        } else {
            evidence["stage3_shared_source_still_held"] = parentAfterRelease.aliveKeys.count
        }

        // 4. 清空 child 与全部测试数组：所有观察到的 owner 最终都必须过期。
        let watchers = parent.entries.map(\.observer)
            + childAtFork.entries.map(\.observer)
            + childAfter.entries.map(\.observer)
        child = nil
        let surviving = watchers.filter(\.isAlive)
        evidence["stage4_child_released"] = [
            "observed_owners": watchers.count,
            "still_alive": surviving.count,
            "parent_all_expired": parentAfterRelease.allExpired,
            "child_at_fork_all_expired": childAtFork.allExpired,
            "child_after_all_expired": childAfter.allExpired,
            "allocator_context": Self.allocator(),
        ]
        XCTAssertTrue(
            surviving.isEmpty,
            "\(arm): child 清空后仍有 \(surviving.count) 个 owner 存活"
                + "（parent 过期 \(parentAfterRelease.expiredKeys.count)/\(parentAfterRelease.entries.count)，"
                + "child@fork 过期 \(childAtFork.expiredKeys.count)/\(childAtFork.entries.count)，"
                + "child@continue 过期 \(childAfter.expiredKeys.count)/\(childAfter.entries.count)）")

        let passed = arm == .shared
            ? (overlap.allShared && expiredAfterRelease == 0 && surviving.isEmpty)
            : (overlap.allSeparated && aliveAfterRelease == 0 && surviving.isEmpty)
        evidence["claims"] = [
            "data_owner_expiry": surviving.isEmpty ? "observed" : "not_observed",
            "source_owner_expired_before_child_release": arm == .detached
                ? (aliveAfterRelease == 0 ? "observed" : "not_observed")
                : "not_applicable",
            "buffer_left_mlx_pool": "not_observed",
            "physical_pages": "not_observed",
        ]
        evidence["verdict"] = passed ? "OWNERSHIP_LIFETIME_VERIFIED" : "OWNERSHIP_LIFETIME_INCOMPLETE"
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
        print("[KV-OWNERSHIP] evidence written to \(url.path)")
    }
}
