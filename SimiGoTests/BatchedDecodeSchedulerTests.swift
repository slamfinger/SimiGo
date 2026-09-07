import XCTest
import MLX
import MLXLMCommon
@testable import SimiGo

/// S1 第一提交（白皮书第二十五章 + 第五轮审计修正）：BatchedDecodeScheduler 骨架契约测试。
/// 锚定不变量：
/// - executionKey ≠ slotId（Logical 身份与 Execution 槽位永不互相冒充）
/// - Capability 两层三态：Static（topology）是必要条件，Validated Execution 是充分条件，
///   Scheduler 看 Effective——当前锁定依赖 batchDecodeT1 = rejected → 拒绝组批走单路
/// - 取消语义：fixed-slot / non-compaction——cancel 标记不缩批，quantum 边界回收
final class BatchedDecodeSchedulerTests: XCTestCase {
    /// 构造两层三态 Capability：资格键固定为测试环境键；
    /// batchDecodeT1 按场景指定；effectiveSupportsBatchDecode 按键匹配 + 状态判定。
    private func makeCapabilities(
        batchDecodeT1: CapabilityStatus,
        keyMatches: Bool = true
    ) -> InferenceModelCapabilities {
        let profileKey = ExecutionQualificationKey(
            backendVersion: "mlx-swift test",
            runtimeVersion: "mlx-swift-lm test",
            modelFamily: "qwen3_moe",
            modelFingerprint: "test-model",
            hardwareFamily: "test-hw",
            memoryClass: "test-mem",
            executionBatchSize: 4,
            decodeShape: "T=1-fixed-quantum",
            precision: "float16"
        )
        let environmentKey = keyMatches
            ? profileKey
            : ExecutionQualificationKey(
                backendVersion: "mlx-swift test",
                runtimeVersion: "mlx-swift-lm test",
                modelFamily: "qwen3_moe",
                modelFingerprint: "test-model",
                hardwareFamily: "test-hw",
                memoryClass: "test-mem",
                executionBatchSize: 4,
                decodeShape: "T=1-fixed-quantum",
                precision: "float16"
            )

        return InferenceModelCapabilities(
            model: ModelCapabilities(
                hasStandardKV: true,
                hasRecurrentState: false,
                hasCacheTopologyCompatibleWithTrim: true
            ),
            executionProfile: ValidatedExecutionProfile(
                key: profileKey,
                batchPrefill: .verified,
                batchDecodeT1: batchDecodeT1,
                perSequenceRoPE: .verified,
                raggedBatch: .unknown,
                batchCancellation: .unknown
            ),
            // evaluate 时的判定语义：键匹配 + 验证状态全 verified → gate 开
            effectiveSupportsBatchDecode: keyMatches && batchDecodeT1 == .verified
        )
    }

    private func makeScheduler(
        batchDecodeT1: CapabilityStatus = .verified,
        keyMatches: Bool = true,
        fixedBatchSize: Int = 4
    ) -> BatchedDecodeScheduler {
        BatchedDecodeScheduler(
            capabilities: makeCapabilities(
                batchDecodeT1: batchDecodeT1,
                keyMatches: keyMatches
            ),
            fixedBatchSize: fixedBatchSize
        )
    }

    // MARK: - Capability 两层三态 + 资格键（审计第五/六轮）

    func testRejectedBatchDecodeT1BlocksSubmit_GateChoosesSingleFallback() async {
        // 当前锁定依赖实况：batchDecodeT1 = rejected → Effective gate 关闭
        // → Scheduler 拒绝组批；Single / interleaved fallback 由 Execution Gate 选择
        let scheduler = makeScheduler(batchDecodeT1: .rejected)

        do {
            _ = try await scheduler.submit(("r1", "agent/s1"))
            XCTFail("batchDecodeT1 = rejected 时必须拒绝提交（Execution Gate 选择单路）")
        } catch let error as BatchSchedulerError {
            XCTAssertEqual(error, .capabilityUnsupported)
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    func testVerifiedBatchDecodeT1AllowsSubmit() async {
        // 验证态：batchDecodeT1 = verified → 允许组批
        let scheduler = makeScheduler(batchDecodeT1: .verified)
        do {
            let sequence = try await scheduler.submit(("r1", "agent/s1"))
            XCTAssertEqual(sequence.phase, .waiting)
        } catch {
            XCTFail("verified 状态下提交不应失败: \(error)")
        }
    }

    func testQualificationKeyMatchOpensGate() {
        // 合成「上游已修复」的全 verified profile（键 = 当前执行环境）：
        // 键匹配 + 状态全 verified → Effective gate 开
        // （当前现实是 qwen3CoderRecord 的 batchDecodeT1 = rejected → gate 关——见下一测试）
        let passingProfile = ValidatedExecutionProfile(
            key: ExecutionQualificationKey.currentEnvironment(
                modelFamily: "qwen3_moe",
                modelFingerprint: "Qwen3-Coder-30B-A3B-Instruct-4bit (mlx-community)",
                batchSize: 4,
                precision: "float16"
            ),
            batchPrefill: .verified,
            batchDecodeT1: .verified,
            perSequenceRoPE: .verified,
            raggedBatch: .verified,
            batchCancellation: .verified
        )
        let capabilities = InferenceModelCapabilities.evaluate(
            caches: [KVCacheSimple()],
            modelFamily: "qwen3_moe",
            modelFingerprint: "Qwen3-Coder-30B-A3B-Instruct-4bit (mlx-community)",
            precision: "float16",
            batchSize: 4,
            executionProfile: passingProfile
        )
        XCTAssertTrue(
            capabilities.effectiveSupportsBatchDecode,
            "键匹配 + 状态全 verified → gate 开"
        )
    }

    func testQualificationKeyMismatchClosesGate() {
        // 审计 P1 修复核心：资格键失配 ⇒ 验证状态失效（verified 不可读取）⇒ gate 关
        // ——防止 static verified profile 退化成无视环境的全局许可证。
        // 同样的全 verified 状态，但键来自不同内存档位的环境 → gate 关。
        let foreignProfile = ValidatedExecutionProfile(
            key: ExecutionQualificationKey(
                backendVersion: "mlx-swift 0.31.6",
                runtimeVersion: "mlx-swift-lm 3.31.4",
                modelFamily: "qwen3_moe",
                modelFingerprint: "Qwen3-Coder-30B-A3B-Instruct-4bit (mlx-community)",
                hardwareFamily: "arm64-darwin",
                memoryClass: "999GB",
                executionBatchSize: 4,
                decodeShape: "T=1-fixed-quantum",
                precision: "float16"
            ),
            batchPrefill: .verified,
            batchDecodeT1: .verified,
            perSequenceRoPE: .verified,
            raggedBatch: .verified,
            batchCancellation: .verified
        )
        let mismatched = InferenceModelCapabilities.evaluate(
            caches: [KVCacheSimple()],
            modelFamily: "qwen3_moe",
            modelFingerprint: "Qwen3-Coder-30B-A3B-Instruct-4bit (mlx-community)",
            precision: "float16",
            batchSize: 4,
            executionProfile: foreignProfile
        )
        XCTAssertFalse(
            mismatched.effectiveSupportsBatchDecode,
            "资格键失配 ⇒ verified 状态不可读取（防止全局许可证）"
        )
    }

    func testCurrentQwen3CoderRecordKeepsGateClosed() {
        // 当前实况：qwen3CoderRecord 的 batchDecodeT1 = rejected（实机 NO-GO 证据）→
        // 键匹配但状态 rejected → gate 关 → Single / interleaved fallback
        let capabilities = InferenceModelCapabilities.evaluate(
            caches: [KVCacheSimple()],
            modelFamily: "qwen3_moe",
            modelFingerprint: "Qwen3-Coder-30B-A3B-Instruct-4bit (mlx-community)",
            precision: "float16",
            batchSize: 4,
            executionProfile: .qwen3CoderRecord
        )
        XCTAssertEqual(capabilities.executionProfile.batchDecodeT1, .rejected)
        XCTAssertFalse(
            capabilities.effectiveSupportsBatchDecode,
            "当前依赖缺陷未修复 → gate 必须保持关闭"
        )
    }

    func testStaticTopologyAloneDoesNotGrantBatch() {
        // 审计核心原则：Cache topology 是必要条件不是充分条件——
        // 即使键匹配，execution 状态 rejected 也使 gate 关闭
        let capabilities = InferenceModelCapabilities.evaluate(
            caches: [KVCacheSimple()],
            modelFamily: "qwen3_moe",
            modelFingerprint: "test-model",
            precision: "float16",
            batchSize: 4,
            executionProfile: ValidatedExecutionProfile(
                key: ExecutionQualificationKey.currentEnvironment(
                    modelFamily: "qwen3_moe",
                    modelFingerprint: "test-model",
                    batchSize: 4,
                    precision: "float16"
                ),
                batchPrefill: .verified,
                batchDecodeT1: .rejected,
                perSequenceRoPE: .verified,
                raggedBatch: .unknown,
                batchCancellation: .unknown
            )
        )
        XCTAssertTrue(capabilities.model.hasStandardKV, "topology 层：Standard-KV 成立")
        XCTAssertFalse(
            capabilities.effectiveSupportsBatchDecode,
            "Effective gate 必须被验证层拒绝——trimmable ≠ batch"
        )
    }

    func testModelLayerStructureFacts() {
        let capabilities = InferenceModelCapabilities.evaluate(
            caches: [KVCacheSimple()],
            modelFamily: "qwen3_moe",
            modelFingerprint: "test-model",
            precision: "float16",
            batchSize: 4,
            executionProfile: .qwen3CoderRecord
        )
        XCTAssertTrue(capabilities.model.hasStandardKV)
        XCTAssertTrue(capabilities.model.hasCacheTopologyCompatibleWithTrim)
        XCTAssertFalse(capabilities.model.hasRecurrentState)
    }

    func testModelLayerRecurrentTopology() {
        // 混合架构（qwen3_5_moe）形态：MambaCache + KVCacheSimple
        let capabilities = InferenceModelCapabilities.evaluate(
            caches: [MambaCache(), KVCacheSimple()],
            modelFamily: "qwen3_5_moe",
            modelFingerprint: "hybrid-model",
            precision: "float16",
            batchSize: 4,
            executionProfile: .qwen3CoderRecord
        )
        XCTAssertFalse(capabilities.model.hasStandardKV)
        XCTAssertTrue(capabilities.model.hasRecurrentState)
    }

    // MARK: - Batch Formation（固定 batch 2/4）

    func testFormBatchFIFOAndSlotAssignment() async {
        let scheduler = makeScheduler()

        for i in 1...4 {
            _ = try? await scheduler.submit(("r\(i)", "agent/s\(i)"))
        }

        let formed = await scheduler.formBatch()
        XCTAssertEqual(formed.count, 4)
        XCTAssertEqual(formed.map { $0.requestId }, ["r1", "r2", "r3", "r4"], "FIFO")
        XCTAssertEqual(formed.map { $0.slotId }, [0, 1, 2, 3], "slotId 按形成顺序分配")

        let activeMembers = await scheduler.activeMembers()
        XCTAssertEqual(activeMembers.map { $0.slotId }, [0, 1, 2, 3])
        let waitingCount = await scheduler.waitingCount
        XCTAssertEqual(waitingCount, 0)
    }

    func testFormBatchPartialWhenFewerWaiting() async {
        let scheduler = makeScheduler()

        _ = try? await scheduler.submit(("r1", "agent/s1"))
        _ = try? await scheduler.submit(("r2", "agent/s2"))

        let formed = await scheduler.formBatch()
        XCTAssertEqual(formed.count, 2, "不足额时按实际等待数组批")
    }

    func testFormBatchOnEmptyReturnsEmpty() async {
        let scheduler = makeScheduler()
        let formed = await scheduler.formBatch()
        XCTAssertTrue(formed.isEmpty)
    }

    // MARK: - Batch 容量

    func testBatchFullRejectsSubmit() async {
        let scheduler = makeScheduler(fixedBatchSize: 2)

        _ = try? await scheduler.submit(("r1", "agent/s1"))
        _ = try? await scheduler.submit(("r2", "agent/s2"))

        do {
            _ = try await scheduler.submit(("r3", "agent/s3"))
            XCTFail("batch 已满必须拒绝提交")
        } catch let error as BatchSchedulerError {
            XCTAssertEqual(error, .batchFull)
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    // MARK: - 取消语义（审计第五轮修正：fixed-slot / non-compaction）

    func testCancelMarksInactiveAndRetainsSlot() async {
        let scheduler = makeScheduler()

        for i in 1...4 {
            _ = try? await scheduler.submit(("r\(i)", "agent/s\(i)"))
        }
        _ = await scheduler.formBatch()

        await scheduler.cancel(requestId: "r2")

        // fixed-slot 语义：slot 1 仍被 r2 持有（phase = .cancelled），不缩批
        let roster = await scheduler.rosterMembers()
        XCTAssertEqual(roster.map { $0.slotId }, [0, 1, 2, 3], "slot 保留至 quantum 边界")
        XCTAssertEqual(roster[1].phase, .cancelled)

        // active 名册（phase == .active）排除 r2
        let activeMembers = await scheduler.activeMembers()
        XCTAssertEqual(activeMembers.map { $0.requestId }, ["r1", "r3", "r4"])
        let activeCount = await scheduler.activeCount
        XCTAssertEqual(activeCount, 3)

        // 未回收前容量仍被占用（fixed slot 语义）
        do {
            _ = try await scheduler.submit(("r5", "agent/s5"))
            XCTFail("取消未回收前 slot 仍占用——fixed-slot 语义")
        } catch let error as BatchSchedulerError {
            XCTAssertEqual(error, .batchFull)
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    func testReclaimCancelledSlotsFreesCapacity() async {
        let scheduler = makeScheduler(fixedBatchSize: 2)

        _ = try? await scheduler.submit(("r1", "agent/s1"))
        _ = try? await scheduler.submit(("r2", "agent/s2"))
        _ = await scheduler.formBatch()

        await scheduler.cancel(requestId: "r2")

        // quantum 边界回收
        let reclaimed = await scheduler.reclaimCancelledSlots()
        XCTAssertEqual(reclaimed, 1)

        // 回收后容量释放，可提交新成员（slotId 单调分配，不复用旧 slotId）
        let sequence = try? await scheduler.submit(("r3", "agent/s3"))
        XCTAssertNotNil(sequence)
        XCTAssertEqual(sequence?.slotId, 2, "slotId 单调分配（同阶段内不复用）")

        let formed = await scheduler.formBatch()
        XCTAssertEqual(formed.map { $0.requestId }, ["r3"])
        XCTAssertEqual(formed.map { $0.slotId }, [2])
    }

    func testCancelWaitingMemberRemovesIt() async {
        let scheduler = makeScheduler()

        _ = try? await scheduler.submit(("r1", "agent/s1"))
        await scheduler.cancel(requestId: "r1")

        let formed = await scheduler.formBatch()
        XCTAssertTrue(formed.isEmpty, "等待中的取消成员不得进入 batch")
    }

    // MARK: - Forward 执行布局（审计第六轮 P1-2：executionFrame 契约）

    func testExecutionFrameKeepsInactiveRowPlaceholder() async {
        // Forward 接线契约：Scheduler 便利投影 ≠ Forward 执行布局——
        // executionFrame 必须按 slot 顺序保留 inactive 占位行（non-compaction），
        // 不得把 [A, B✗, C, D] 压缩成 [A, C, D]（compact 语义由 activeMembers 承担）。
        let scheduler = makeScheduler()

        for i in 1...4 {
            _ = try? await scheduler.submit(("r\(i)", "agent/s\(i)"))
        }
        _ = await scheduler.formBatch()
        await scheduler.cancel(requestId: "r2")

        let frame = await scheduler.executionFrame()

        XCTAssertEqual(frame.slots.count, 4, "inactive 行必须占位——不得压缩成 3 行")
        XCTAssertEqual(frame.slots.map(\.slotId), [0, 1, 2, 3], "行顺序 = slot 顺序")
        XCTAssertEqual(frame.slots.map(\.requestId), ["r1", "r2", "r3", "r4"])
        XCTAssertEqual(frame.activeMask, [true, false, true, true])
        XCTAssertEqual(frame.activeRequestIds, ["r1", "r3", "r4"])

        // 同一状态下 compact 便利投影只有 3 行——两种投影语义不同，契约由此钉住
        let activeMembers = await scheduler.activeMembers()
        XCTAssertEqual(activeMembers.map(\.requestId), ["r1", "r3", "r4"])
        let rosterCount = await scheduler.rosterCount
        XCTAssertEqual(
            frame.slots.count, rosterCount,
            "frame 行数 = roster slot 数，而非活跃成员数"
        )
    }

    func testExecutionFrameAfterReclaimKeepsMonotonicSlotOrder() async {
        let scheduler = makeScheduler(fixedBatchSize: 2)

        _ = try? await scheduler.submit(("r1", "agent/s1"))
        _ = try? await scheduler.submit(("r2", "agent/s2"))
        _ = await scheduler.formBatch()
        await scheduler.cancel(requestId: "r1")
        let reclaimed = await scheduler.reclaimCancelledSlots()
        XCTAssertEqual(reclaimed, 1)

        _ = try? await scheduler.submit(("r3", "agent/s3"))
        let formed = await scheduler.formBatch()

        let frame = await scheduler.executionFrame()
        XCTAssertEqual(
            frame.slots.map(\.slotId), [1, 2],
            "回收后 frame 只含现存 slot，新 slotId 单调分配不复用"
        )
        XCTAssertEqual(frame.activeMask, [true, true])
        XCTAssertEqual(formed.map(\.slotId), [2])
    }

    // MARK: - step / finish 计数

    func testStepCompletedIncrementsActiveOnly() async {
        let scheduler = makeScheduler()

        for i in 1...2 {
            _ = try? await scheduler.submit(("r\(i)", "agent/s\(i)"))
        }
        _ = await scheduler.formBatch()

        await scheduler.stepCompleted(requestId: "r1")
        await scheduler.stepCompleted(requestId: "r1")

        await scheduler.cancel(requestId: "r2")

        // cancelled 成员不再计数（forward 侧跳过）
        await scheduler.stepCompleted(requestId: "r2")

        let activeMembers = await scheduler.activeMembers()
        XCTAssertEqual(activeMembers.first { $0.requestId == "r1" }?.generatedTokens, 2)
        let cancelled = await scheduler.rosterMembers()
        XCTAssertEqual(
            cancelled.first { $0.requestId == "r2" }?.generatedTokens, 0,
            "cancelled 成员不得继续计数"
        )
    }

    func testFinishMovesMemberToFinished() async {
        let scheduler = makeScheduler()

        _ = try? await scheduler.submit(("r1", "agent/s1"))
        _ = await scheduler.formBatch()

        await scheduler.finish(requestId: "r1")

        let activeMembers = await scheduler.activeMembers()
        XCTAssertTrue(activeMembers.isEmpty)

        let finished = await scheduler.finishedMembers()
        XCTAssertEqual(finished.count, 1)
        XCTAssertEqual(finished[0].phase, .finished)
    }

    // MARK: - 身份不变量

    func testExecutionKeyNeverEqualsSlotIdSemantically() async {
        // 白皮书不变量：executionKey 是 Logical 身份，slotId 是 Execution 槽位——
        // slotId 单调分配、阶段内不复用（fixed-slot 语义）；身份永远不由 slot 承载。
        let scheduler = makeScheduler()

        _ = try? await scheduler.submit(("r1", "agent/s1"))
        _ = try? await scheduler.formBatch()
        await scheduler.finish(requestId: "r1")

        _ = try? await scheduler.submit(("r2", "agent/s1")) // 同 key 新请求
        let formed = await scheduler.formBatch()
        XCTAssertEqual(formed[0].slotId, 1, "slotId 单调分配（阶段内不复用已回收 slot）")
        XCTAssertEqual(formed[0].executionKey, "agent/s1", "executionKey 保持 Logical 身份")
        XCTAssertNotEqual(formed[0].slotId.description, formed[0].executionKey)
    }
}
