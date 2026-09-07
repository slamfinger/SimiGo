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
    /// 构造两层 Capability：execution profile 按测试场景指定
    private func makeCapabilities(
        batchDecodeT1: CapabilityStatus
    ) -> InferenceModelCapabilities {
        InferenceModelCapabilities(
            model: ModelCapabilities(
                hasStandardKV: true,
                hasRecurrentState: false,
                supportsPerSequenceRoPE: true,
                supportsCacheTrim: true
            ),
            execution: ValidatedExecutionProfile(
                backendIdentifier: "test-backend",
                batchPrefill: .verified,
                batchDecodeT1: batchDecodeT1,
                raggedBatch: .unknown,
                batchCancellation: .unknown
            )
        )
    }

    private func makeScheduler(
        batchDecodeT1: CapabilityStatus = .verified,
        fixedBatchSize: Int = 4
    ) -> BatchedDecodeScheduler {
        BatchedDecodeScheduler(
            capabilities: makeCapabilities(batchDecodeT1: batchDecodeT1),
            fixedBatchSize: fixedBatchSize
        )
    }

    // MARK: - Capability 两层三态（审计第五轮修正）

    func testRejectedBatchDecodeT1BlocksSubmit_SingleFallback() async {
        // 当前锁定依赖实况：batchDecodeT1 = rejected → 拒绝组批
        // → BatchedDecodeScheduler 自动走 Single / interleaved fallback
        let scheduler = makeScheduler(batchDecodeT1: .rejected)

        do {
            _ = try await scheduler.submit(("r1", "agent/s1"))
            XCTFail("batchDecodeT1 = rejected 时必须拒绝提交（Single fallback）")
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

    func testStaticTopologyAloneDoesNotGrantBatch() {
        // 审计核心原则：Cache topology 是必要条件不是充分条件——
        // hasStandardKV = true 但 execution.batchDecodeT1 = rejected → effective = false
        let capabilities = InferenceModelCapabilities.evaluate(caches: [KVCacheSimple()])
        XCTAssertTrue(capabilities.model.hasStandardKV, "topology 层：Standard-KV 成立")
        XCTAssertEqual(
            capabilities.execution.batchDecodeT1, .rejected,
            "验证层：当前锁定依赖 batchDecodeT1 = rejected"
        )
        XCTAssertFalse(
            capabilities.effectiveSupportsBatchDecode,
            "Effective gate 必须被验证层拒绝——trimmable ≠ batch"
        )
    }

    func testCapabilityEvaluateStandardKVSupportsModelLayer() {
        let capabilities = InferenceModelCapabilities.evaluate(caches: [KVCacheSimple()])
        XCTAssertTrue(capabilities.model.hasStandardKV)
        XCTAssertTrue(capabilities.model.supportsPerSequenceRoPE)
        XCTAssertTrue(capabilities.model.supportsCacheTrim)
    }

    func testCapabilityEvaluateRecurrentCacheModelLayer() {
        // 混合架构（qwen3_5_moe）形态：MambaCache + KVCacheSimple
        let capabilities = InferenceModelCapabilities.evaluate(
            caches: [MambaCache(), KVCacheSimple()]
        )
        XCTAssertFalse(capabilities.model.hasStandardKV)
        XCTAssertTrue(capabilities.model.hasRecurrentState)
        XCTAssertFalse(capabilities.model.supportsCacheTrim)
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
