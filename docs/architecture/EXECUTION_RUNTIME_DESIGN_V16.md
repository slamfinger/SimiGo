# V1.6 Execution Runtime 设计规格（2026-09-19）

**性质**：能力规格 + 分片实施计划（对应 `docs/decisions/V16_DIRECTION_REGISTRATION_20260919.md`）
**基线**：v1.5 tag（`2faf6d6`）——所有分片以 v1.5 行为为不变量参照，
每片独立可回退、零行为变更或带 A/B 门

## 1. 定位与原则

> SimiGo = macOS 上面向本地 LLM 的 **Execution Runtime**。

1. **先定义能力，不定义实现**：Execution API 先立协议面，实现逐步
   迁移；Fork 能力当前实现 = 磁盘 checkpoint，未来 = 上游原语
   （mlx-swift-lm#629），API 面不变
2. **Session ≠ Execution**：一个 Session 可含多个 execution；
   `sessionID ≠ executionID ≠ kvFingerprint ≠ checkpointID ≠ traceKey`
3. **KV 退位**：KV 是 execution 的底层状态资源，不再是架构主角
4. **少做**：不改 Conditional Restore 判定语义；不建 KV Tree/COW；
   不做 Agent Framework；不做大规模文件搬迁

## 2. 能力 API 面（协议定义，Slice 3 起逐个落实现）

```swift
/// 概念面——Slice 3 落地为对现有路径的薄封装，零新语义
protocol ExecutionControlling {
    func execute(_ req: ExecutionRequest) async throws -> ExecutionResult   // 新执行
    func `continue`(_ req: ExecutionRequest) async throws -> ExecutionResult // 同 lineage 续跑
    func checkpoint(_ id: ExecutionID) async throws -> CheckpointID          // 持久化
    func restore(_ id: ExecutionID, from: CheckpointID) async throws         // 恢复
    func fork(_ id: ExecutionID, reason: String) async throws -> ExecutionID // 派生（parent→child）
}
```

## 3. 数据/决策分离（外审 P0-1 收敛方向）

```text
ExecutionFacts        事实/观测：deltaTokens、kvFingerprint、
  (struct, 纯数据)    checkpointFresh、reuse、rollforwardRisk
        ↓
DecisionPolicy        策略：restoreDeltaLimit、prefillPolicy、
  (纯函数)            toolCallPolicy  ← 吸收 conditionalRestoreEnabled
        ↓                        /rollforwardEnabled/8192 三 flag
ExecutionDecision     决策：.extend / .restore / .rebuild / .fork
        ↓
Executor              执行：现有 generateUsingChatSession 路径
```

## 4. Lineage 模型与 ID 语义表

| ID | 语义 | 载体 | 现状 |
|---|---|---|---|
| sessionID | 用户会话身份 | 协议入参 | 已有 |
| **executionID** | 单次执行身份（新建） | `[EXEC]` 行 | **Slice 1** |
| parentExecutionID | 派生来源（fork 时） | `[EXEC]` 行 | Slice 1 占位 `-` |
| kvFingerprint | KV 配置指纹 | checkpoint meta | 已有 |
| checkpointID | checkpoint 文件身份 | meta sidecar | 已有（文件名+meta） |
| traceKey | 日志短串 | trace 行 | 已有（不可预测短串） |

`[EXEC]` 遥测行规格（Slice 1）：

```text
[EXEC] begin exec=<id8> key=<traceKey> parent=- req=<requestId> incoming=<n>
[MLX] session=... exec=<id8> ...          ← 完成行追加 exec 字段
```

后续分片补：`status=completed/failed/cancelled`、`parent` 真值（fork）、
`checkpointID` 关联。

## 5. 分片计划（每片独立提交，带验收）

| 片 | 内容 | 行为变化 | 验收 |
|---|---|---|---|
| **S1（本轮）** | executionID 生成 + `[EXEC] begin` + 完成行 `exec=` 字段 | 零（log-only） | 单测全绿；trace 出现配对 begin/exec |
| **S2（已完成 2026-09-19）** | ExecutionFacts / ExecutionDecision 类型声明 + 判定纯函数簇（rollforwardRisk/conditionalRestoreGate/estimates/compat/diff/render 对账族，17 函数）搬家至 `ExecutionPolicy.swift`，函数体逐字节不变；NativeMLX 调用点与单测引用改指 ExecutionPolicy | 零 | SimiGoTests 60 执行 0 失败（含 RiskDetector/Compatible/RenderCompatible 测试族）；bench 冒烟随下次 app 部署补 |
| **S3（已完成 2026-09-19）** | ConditionalRestoreConfiguration 配置面（三 flag 合并，`current()` 唯一读取入口，generate 每请求一次性快照，决策与 checkpoint save 门全程只消费快照） | 零（默认值=现值，路径逐条等价） | ExecutionPolicyGateTests：默认等价 + 4 路径 A/B 一致 + 快照冻结隔离，全绿 |
| **S4（已完成 2026-09-19）** | ExecutionControlling 协议面落地为薄封装（fork 复用 BranchFork v1） | 零 | 五动作映射表写入文件头（红线=零新语义）；headless 委托证明（未加载实例各动作错误透传）；fork/restore 端到端回归走 BranchFork 既有测试族 |
| **S5（已完成 2026-09-19）** | ExecutionLineage 有界血统日志（128 FIFO）+ ExecutionStatus/ExecutionRecord/ForkEvent 模型；[EXEC] end（status=completed/failed/cancelled）+ [EXEC] checkpoint + [EXEC] fork（parent/child 真值=storageKey）；五身份分离红线遵守 | 零（log-only+内存记录） | ExecutionLineageTests 4/4（失败捕获/容量淘汰/checkpoint 关联/fork 真值）+ headless generate-failure 回归 |

> S1 追加（四轮外审测试质量收紧，2026-09-19 已落实）：测试缝隙
> `#if DEBUG` 隔离、竞态结果语义分层（RACE_WINDOW_HIT vs
> PROTECTION_PASS_NO_HIT）、可等待配置恢复 + port 0、typed error 断言。
> 详见 `docs/audit/EXECID_TEST_QUALITY_REVIEW_2026-09-19.md`。

## 6. Gate 语义清单（多 Execution 并发前置条件，V1.6 内只登记不实现）

单执行假设对象：ManagedSession/ChatSession、historyJSON 尾部变异、
lastJSON——当前由 `SessionGenerationGate.withExclusive(key)` 结构性封口。
任何引入并发 execution 的提案必须逐对象回答：锁主体是谁、变异窗口在哪、
checkpoint 与谁的 gate 交互。

## 7. 非目标（V1.6 全程不做）

KV Tree / COW / BranchManager / Agent Framework / Conditional Restore
判定语义修改 / prefill 步长重调 / 大规模文件搬迁。
