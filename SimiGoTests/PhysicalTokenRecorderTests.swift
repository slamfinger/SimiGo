import XCTest
@testable import SimiGo

/// PhysicalTokenRecorder 并发回归（审计 🔴 第 1 条）：
/// append 在 MLX eval 上下文执行、snapshot 在请求任务上下文执行，
/// 取消路径上两者无时序保证——曾是无锁 @unchecked Sendable，已改 Mutex。
/// 本用例在多任务并发下验证计数守恒，锁丢失更新时会失败。
final class PhysicalTokenRecorderTests: XCTestCase {
    func testAppendAndSnapshotBasicFlow() {
        let recorder = PhysicalTokenRecorder()

        recorder.append(1)
        recorder.append(2)
        XCTAssertEqual(recorder.snapshot(), [1, 2])

        recorder.discardLastIfPresent()
        XCTAssertEqual(recorder.snapshot(), [1])
    }

    func testDiscardLastOnEmptyIsNoOp() {
        let recorder = PhysicalTokenRecorder()

        recorder.discardLastIfPresent()
        XCTAssertEqual(recorder.snapshot(), [])
    }

    /// 审计建议（顺序语义）：discard 必须精确移除最后一次 append，
    /// 保留顺序——该序列正是 Physical Token Ledger 的追加/回退语义。
    func testDiscardRemovesLastAppendPreservingOrder() {
        let recorder = PhysicalTokenRecorder()

        recorder.append(11)
        recorder.append(22)
        recorder.append(33)
        recorder.discardLastIfPresent()
        XCTAssertEqual(recorder.snapshot(), [11, 22])

        recorder.append(44)
        XCTAssertEqual(recorder.snapshot(), [11, 22, 44])
    }

    func testSnapshotIsIndependentCopy() {
        let recorder = PhysicalTokenRecorder()
        recorder.append(7)

        let snapshot = recorder.snapshot()
        recorder.append(8)

        XCTAssertEqual(snapshot, [7], "snapshot 必须是值拷贝，不受后续 append 影响")
        XCTAssertEqual(recorder.snapshot(), [7, 8])
    }

    func testConcurrentAppendsConserveCount() async throws {
        let recorder = PhysicalTokenRecorder()
        let writers = 8
        let appendsPerWriter = 25_000

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<writers {
                group.addTask {
                    for token in 0..<appendsPerWriter {
                        recorder.append(token)
                    }
                }
            }

            try await group.waitForAll()
        }

        XCTAssertEqual(
            recorder.snapshot().count,
            writers * appendsPerWriter,
            "并发 append 总数必须守恒——无锁实现会丢失更新"
        )
    }

    func testConcurrentAppendAndDiscardStayConsistent() async throws {
        let recorder = PhysicalTokenRecorder()
        let appends = 50_000
        let discards = appends / 4

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for token in 0..<appends {
                    recorder.append(token)
                }
            }

            group.addTask {
                for _ in 0..<discards {
                    recorder.discardLastIfPresent()
                }
            }

            try await group.waitForAll()
        }

        let finalCount = recorder.snapshot().count
        XCTAssertTrue(
            (appends - discards)...appends ~= finalCount,
            "并发 append/discard 混合后计数必须落在 [\(appends - discards), \(appends)]，实际 \(finalCount)"
        )
    }
}
