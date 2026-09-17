# DRAFT：Branch-Fork 生产协议设计登记（2026-09-17）

**状态：DRAFT —— 5.1 观察窗口内只登记不实现；窗口期满后按本稿评审动工。**
**证据基础：** `docs/lessons/kv-fork-checkpoint-experiment-2026-09-17.md`（fe766a1→8e82fd8）。
**能力边界已实证：** 磁盘 checkpoint fork（GDN 混合 + all-attention 双架构）、内存版
`KVCache.copy()` fork 双向隔离、fork 增量 prefill、fork/cold greedy 逐字一致、长程记忆保持。
**未实证且不在本稿范围：** 任意 token 位置 fork（设计上不做）、并发分支执行（生产
`__global_generation__` 串行是系统属性，分支价值在省 prefill 而非并行吞吐）。

## 待决策问题与建议答案

### 1. 什么时候 fork —— 显式触发，不做隐式

由客户端请求显式触发（OpenAI 兼容扩展字段，如 chat 请求的 `metadata.simigo_fork_from`）。
不做隐式自动 fork：自动分叉会让 cacheEff/mode 语义复杂化，与遥测诚实红线冲突。

### 2. 由什么协议触发 —— 两个最小面

- `POST /v1/chat/completions` 请求可选 `simigo_branch`（logicalBranchId，AgentExecutionKey
  已支持寻址）+ `simigo_fork_from`（源分支）。
- Runtime 新增 `forkSession(source:target:)`：源 checkpoint → 目标 logicalBranchId 注册。

### 3. 快照获取路径 —— 先磁盘版，上游 API 跟进后切内存版

关键约束：官方 ChatSession 公开面只有 `saveCache(to: URL)`，**没有 in-process 快照导出**。
生产 fork 第一版走临时文件往返（已实证，≈175MB 级 IO）；上游公开 in-memory snapshot API
后再切 `KVCache.copy()` 路径（隔离性已由 `testInMemoryForkCopyOwnership` 实证）。

### 4. 分支生命周期与回收

- 分支 = logicalBranchId 维度的 session，沿用 P1 LRU（`sessionLimit`，驱逐走官方 `clear()`）。
- 回收显式化：`DELETE` 分支 → `clear()` + sessions 移除 + checkpoint 文件 GC。
- **不做 merge**：KV 不可合并，合并=选边；客户端选边后把胜者提升为新 main。

### 5. 与 idleSuspend 的交互（关键架构约束）

`RuntimeLifecycle` suspend 会 `sessions.removeAll()` + 释放容器——**所有分支（含普通会话）
随模型卸载消失，checkpoint 文件是唯一跨 suspend 的存活物**。resume 后分支需重新
`loadSessionCache`。推论：跨 suspend 的分支必须落盘；内存版 fork 只在挂起-free 窗口内有效。

### 6. usage 表达

恢复路径 `mode`/`cachedPromptTokens` 盲区是官方 raw-cache 语义（上游欠账），对外沿用
官方原值不估算；分支元数据带 `fork_parent`/`fork_point` 补足可观测性。上游补账本语义后升级。

## 验收门（窗口期满后）

1. 生产 prompt 分布下 fork vs cold 的 TTFT benchmark；
2. 多分支内存上界实测（快照成本按 lessons 公式逐模型估算）；
3. suspend/resume 往返后分支恢复正确性；
4. 与 LRU 驱逐的交互（被逐分支经 checkpoint 可再载入）。
