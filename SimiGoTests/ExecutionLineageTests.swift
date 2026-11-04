import XCTest
@testable import SimiGo

/// S5 验收：血统日志——失败捕获、容量淘汰、checkpoint 关联、fork 真值。
final class ExecutionLineageTests: XCTestCase {
    private func record(_ id: String) -> ExecutionRecord {
        ExecutionRecord(
            executionId: id, requestId: "req-\(id)", agentId: nil,
            sessionId: "s", logicalBranchId: "main", status: .running,
            startedAt: Date())
    }

    /// 未加载模型时 generate 抛 notLoaded——血统必须捕获 failed 终态
    /// 而非留下 .running 孤儿记录（headless，无需权重）。
    func testGenerateFailureProducesFailedRecord() async {
        let runtime = NativeMLX(
            info: ModelInfo(path: "/nonexistent-model", kind: .mlx),
            config: ModelConfig())
        do {
            _ = try await runtime.generate(
                sessionId: "lin",
                messages: [.object(["role": .string("user"),
                                    "content": .string("x")])],
                tools: nil,
                config: ModelConfig()) { _ in }
            XCTFail("未加载模型时 generate 应抛错")
        } catch {
            // 预期
        }
        let snapshot = runtime.lineage.snapshot
        XCTAssertEqual(snapshot.records.count, 1)
        XCTAssertEqual(snapshot.records.first?.status, .failed)
        XCTAssertNotNil(snapshot.records.first?.completedAt)
        // 失败链证明（外审十一轮）：begin→running→failed→completedAt
        // 全链可观测——时间序一致且身份字段透传一致
        let rec = snapshot.records.first!
        XCTAssertLessThanOrEqual(rec.startedAt, rec.completedAt!)
        XCTAssertFalse(rec.executionId.isEmpty)
        XCTAssertEqual(rec.logicalBranchId, "main")
    }

    /// 容量淘汰：超过上限后 FIFO 丢弃最旧记录。
    func testBoundedCapacity() {
        let lineage = ExecutionLineage(capacity: 128)
        for i in 0..<200 {
            lineage.begin(record("exec-\(i)"))
        }
        let snapshot = lineage.snapshot
        XCTAssertEqual(snapshot.records.count, 128)
        XCTAssertEqual(snapshot.records.first?.executionId, "exec-72")
        XCTAssertEqual(snapshot.records.last?.executionId, "exec-199")
    }

    /// checkpoint 关联 + 终态语义。
    func testCheckpointAssociationAndTerminalStatus() {
        let lineage = ExecutionLineage()
        lineage.begin(record("exec-a"))
        lineage.attachCheckpoint(executionId: "exec-a", checkpointKey: "k/main")
        lineage.end(executionId: "exec-a", status: .completed)
        let rec = lineage.snapshot.records.first
        XCTAssertEqual(rec?.status, .completed)
        XCTAssertEqual(rec?.checkpointKey, "k/main")
        XCTAssertNotNil(rec?.completedAt)
    }

    /// fork 派生真值：parent/child 均为 storageKey，事件有界。
    /// 失败链直接证明：begin(running) → end(.failed) → 终态与时间戳。
    func testBeginRunningToEndFailedChain() {
        let lineage = ExecutionLineage()
        lineage.begin(record("exec-f"))
        XCTAssertEqual(lineage.snapshot.records.first?.status, .running)
        lineage.end(executionId: "exec-f", status: .failed)
        let rec = lineage.snapshot.records.first
        XCTAssertEqual(rec?.status, .failed)
        XCTAssertNotNil(rec?.completedAt)
        XCTAssertLessThanOrEqual(rec!.startedAt, rec!.completedAt!)
    }

    func testForkRecording() {
        let lineage = ExecutionLineage(capacity: 2)
        lineage.recordFork(parent: "a/main", child: "a/fork1")
        lineage.recordFork(parent: "a/fork1", child: "a/fork2")
        lineage.recordFork(parent: "a/fork2", child: "a/fork3")
        let forks = lineage.snapshot.forks
        XCTAssertEqual(forks.count, 2, "容量 2 应淘汰最旧")
        XCTAssertEqual(forks.first?.parent, "a/fork1")
        XCTAssertEqual(forks.last?.child, "a/fork3")
    }
}
