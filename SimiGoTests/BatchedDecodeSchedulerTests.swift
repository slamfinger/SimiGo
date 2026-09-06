import XCTest
import MLX
import MLXLMCommon
@testable import SimiGo

/// S1 第一提交（白皮书第二十五章）：BatchedDecodeScheduler 骨架契约测试。
/// 锚定不变量：executionKey ≠ slotId；Batch 只属于 Execution Plane；
/// Capability 过滤先于 Batch Formation；成员取消不缩批、不污染他路。
final class BatchedDecodeSchedulerTests: XCTestCase {
    private func makeCapabilities(batchDecode: Bool) -> InferenceModelCapabilities {
        InferenceModelCapabilities(
            supportsBatchDecode: batchDecode,
            supportsPerSequenceRoPE: batchDecode,
            supportsIndependentKVState: batchDecode,
            supportsPromptCacheTrim: batchDecode,
            supportsRaggedBatch: false,
            supportsRecurrentStateBatch: false,
            supportsSpeculativeDecode: false,
            supportsPagedKV: false
        )
    }

    // MARK: - Capability Filter（formation 管线第一级）

    func testCapabilityUnsupportedRejectsSubmit() async {
        let scheduler = BatchedDecodeScheduler(
            capabilities: makeCapabilities(batchDecode: false),
            fixedBatchSize: 4
        )

        do {
            _ = try await scheduler.submit(("r1", "agent/s1"))
            XCTFail("不支持 Batch 的模型必须拒绝提交")
        } catch let error as BatchSchedulerError {
            XCTAssertEqual(error, .capabilityUnsupported)
        } catch {
            XCTFail("意外错误: \(error)")
        }
    }

    func testCapabilityEvaluateStandardKVSupportsBatch() {
        // Standard-KV（KVCacheSimple）→ Batch Decode 支持
        let capabilities = InferenceModelCapabilities.evaluate(caches: [KVCacheSimple()])
        XCTAssertTrue(capabilities.supportsBatchDecode)
        XCTAssertTrue(capabilities.supportsPerSequenceRoPE)
        XCTAssertTrue(capabilities.supportsIndependentKVState)
    }

    func testCapabilityEvaluateRecurrentCacheRejectsBatch() {
        // 混合架构（qwen3_5_moe）形态：MambaCache + KVCacheSimple —— 实机 NO-GO 证据
        let capabilities = InferenceModelCapabilities.evaluate(
            caches: [MambaCache(), KVCacheSimple()]
        )
        XCTAssertFalse(capabilities.supportsBatchDecode, "含 recurrent cache 必须 NO-GO")
        XCTAssertFalse(capabilities.supportsRecurrentStateBatch)
        XCTAssertFalse(capabilities.supportsRaggedBatch)
        XCTAssertFalse(capabilities.supportsPagedKV, "S2 未立项前恒 false")
        XCTAssertFalse(capabilities.supportsSpeculativeDecode, "S3 未立项前恒 false")
    }

    // MARK: - Batch Formation（固定 batch 2/4）

    func testFormBatchFIFOAndSlotAssignment() async {
        let scheduler = BatchedDecodeScheduler(
            capabilities: makeCapabilities(batchDecode: true),
            fixedBatchSize: 4
        )

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
        let scheduler = BatchedDecodeScheduler(
            capabilities: makeCapabilities(batchDecode: true),
            fixedBatchSize: 4
        )

        _ = try? await scheduler.submit(("r1", "agent/s1"))
        _ = try? await scheduler.submit(("r2", "agent/s2"))

        let formed = await scheduler.formBatch()
        XCTAssertEqual(formed.count, 2, "不足额时按实际等待数组批")
    }

    func testFormBatchOnEmptyReturnsEmpty() async {
        let scheduler = BatchedDecodeScheduler(
            capabilities: makeCapabilities(batchDecode: true),
            fixedBatchSize: 4
        )

        let formed = await scheduler.formBatch()
        XCTAssertTrue(formed.isEmpty)
    }

    // MARK: - Batch 容量

    func testBatchFullRejectsSubmit() async {
        let scheduler = BatchedDecodeScheduler(
            capabilities: makeCapabilities(batchDecode: true),
            fixedBatchSize: 2
        )

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

    // MARK: - 成员取消（白皮书第九章：B 离开，A/C/D 继续）

    func testCancelActiveMemberRemovesItAndKeepsOthers() async {
        let scheduler = BatchedDecodeScheduler(
            capabilities: makeCapabilities(batchDecode: true),
            fixedBatchSize: 4
        )

        for i in 1...4 {
            _ = try? await scheduler.submit(("r\(i)", "agent/s\(i)"))
        }
        _ = await scheduler.formBatch()

        await scheduler.cancel(requestId: "r2")

        let activeMembers = await scheduler.activeMembers()
        XCTAssertEqual(activeMembers.map { $0.requestId }, ["r1", "r3", "r4"], "被取消成员立即离开后续 decode step")
        let activeCount = await scheduler.activeCount
        XCTAssertEqual(activeCount, 3)

        let finished = await scheduler.finishedMembers()
        XCTAssertEqual(finished.count, 1)
        XCTAssertEqual(finished[0].requestId, "r2")
        XCTAssertEqual(finished[0].phase, .cancelled)
    }

    func testCancelWaitingMemberRemovesIt() async {
        let scheduler = BatchedDecodeScheduler(
            capabilities: makeCapabilities(batchDecode: true),
            fixedBatchSize: 4
        )

        _ = try? await scheduler.submit(("r1", "agent/s1"))
        await scheduler.cancel(requestId: "r1")

        let formed = await scheduler.formBatch()
        XCTAssertTrue(formed.isEmpty, "等待中的取消成员不得进入 batch")
    }

    // MARK: - step / finish 计数

    func testStepCompletedIncrementsGeneratedTokens() async {
        let scheduler = BatchedDecodeScheduler(
            capabilities: makeCapabilities(batchDecode: true),
            fixedBatchSize: 4
        )

        for i in 1...2 {
            _ = try? await scheduler.submit(("r\(i)", "agent/s\(i)"))
        }
        _ = await scheduler.formBatch()

        await scheduler.stepCompleted(requestId: "r1")
        await scheduler.stepCompleted(requestId: "r1")
        await scheduler.stepCompleted(requestId: "r2")

        let activeMembers = await scheduler.activeMembers()
        XCTAssertEqual(activeMembers.first { $0.requestId == "r1" }?.generatedTokens, 2)
        XCTAssertEqual(activeMembers.first { $0.requestId == "r2" }?.generatedTokens, 1)
    }

    func testFinishMovesMemberToFinished() async {
        let scheduler = BatchedDecodeScheduler(
            capabilities: makeCapabilities(batchDecode: true),
            fixedBatchSize: 4
        )

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
        // 同一 executionKey 的重复请求会得到不同 slotId；不同 executionKey 可能共享 slotId。
        let scheduler = BatchedDecodeScheduler(
            capabilities: makeCapabilities(batchDecode: true),
            fixedBatchSize: 4
        )

        _ = try? await scheduler.submit(("r1", "agent/s1"))
        _ = try? await scheduler.formBatch()
        await scheduler.finish(requestId: "r1")

        _ = try? await scheduler.submit(("r2", "agent/s1")) // 同 key 复用 slot 0
        let formed = await scheduler.formBatch()
        XCTAssertEqual(formed[0].slotId, 0, "slotId 复用")
        XCTAssertEqual(formed[0].executionKey, "agent/s1", "executionKey 保持 Logical 身份")
        XCTAssertNotEqual(formed[0].slotId.description, formed[0].executionKey)
    }
}
