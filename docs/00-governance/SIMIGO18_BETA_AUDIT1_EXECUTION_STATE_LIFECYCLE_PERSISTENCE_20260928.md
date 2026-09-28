# BETA-AUDIT-1 — Execution State / Lifecycle / Persistence Boundary Audit

日期：2026-09-28
状态：IN PROGRESS / CODE EVIDENCE ROUND 1
审计对象：SimiGo main；产品树与 release/v2.0.0-beta 同树。审计准备基线 e168555；当前 HEAD 109fef9 仅增加审计基线文档。

## 1. 本轮目标
第一轮只审计当前 Beta 真实代码中的 Execution State 承载、identity / position / continuation / lifecycle / lineage 来源，ChatSession / checkpoint / Lineage / RepresentationRef / PrefixPool 边界，以及 create → continue → checkpoint → restore → fork → delete 的真实状态流。

本轮不设计 Palace DB，不设计 Llama adapter，不修改已关闭 FORK-3。

## 2. 当前代码实际状态模型
当前 Beta 没有一个单独的、持久化的 ExecutionState 对象。语义分散在：
- 寻址身份：AgentExecutionKey = agentId + sessionId + logicalBranchId
- 请求级 execution id：generate() 每请求生成 UUID，仅用于 Lineage / trace
- 活会话：NativeMLX.State.sessions → ManagedSession
- Physical KV / token ledger：官方 ChatSession
- SimiGo transcript：ManagedSession.history / historyJSON
- checkpoint：.safetensors + .meta.json
- fork point：SessionCacheMetadata.forkPoint
- binding：process-lifetime ExecutionBindingRegistry
- lineage：process-local ExecutionLineage，128 FIFO
- runtime lifecycle：NativeMLX.lifecycle，全局 runtime 级
- position：主要隐含于 transcript/history 与官方 ChatSession processedTokenCount
- representation：PrefixPool / checkpoint + RepresentationRef

因此 README 所描述的 identity / lineage / position / continuation / lifecycle 五元 Execution State，目前在架构语义层成立，但尚未收敛成一个独立的 durable state record。

这不是立即判定为代码错误，但属于首发路线必须继续验证的核心边界。

## 3. 已确认的正确边界
### 3.1 ChatSession 是物理 KV 权威
NativeMLX 不重新实现 token ledger。ManagedSession 保存消息级 transcript，官方 ChatSession 保存 Physical KV/token accounting。

### 3.2 ExecutionKey 与 Physical Representation 已分离
PrefixPool 的 RepresentationRef 描述 model / KV layout / render / contentHash / boundLength；ExecutionBindingRegistry 是 execution-scoped runtime registry。Step-9/10 的 child binding、parent non-supersede、delete detach 已落地。

### 3.3 checkpoint 是当前最重要的 durable continuity 载体
saveSessionCache 写官方 .safetensors KV snapshot 和 .meta.json transcript / modelId / kvFingerprint / optional forkPoint；loadSessionCache 用 checkpoint 重建新的 ChatSession 和 ManagedSession。

当前跨内存生命周期 continuation 的真实机制主要是 checkpoint artifact + transcript sidecar + reattach，而不是独立 ExecutionState store。

## 4. 第一批 P1 候选
### P1-CANDIDATE-1：checkpoint 双文件不是原子事务
performSave() 先调用 managed.session.saveCache(to: cacheURL)，随后才原子写 metaURL。因此 .safetensors 与 .meta.json 不是同一原子提交单元。

失败窗口：新 cache 已成功写入，而 metadata 写入失败、进程崩溃或存储异常；下一次恢复可能看到新 cache + 旧 metadata。

forkSessionBranch() 同样分别 swap 两个文件。当前没有证据证明已经发生实际损坏，因此本轮暂记 P1 candidate / not yet blocking verdict；不能只因为 whole-fork transactionality 曾登记为 P2，就跳过普通 checkpoint 的一致性审计。

下一步需要 failure injection、generation/mismatch 检测、crash-between-files 模拟，以及 restore fail-closed 证据。

### P1-CANDIDATE-2：Execution State durable identity / lineage 尚未统一
ExecutionLineage 是 Runtime 实例内存对象、128 FIFO、log/query-only，不随 checkpoint 持久化。checkpoint metadata 持久化 storageKey 和 forkPoint，但不是完整 lineage history。

因此 checkpoint 可以恢复一个可继续的 ChatSession，但不能单独恢复完整 Execution lineage history。

暂记 P1 candidate / architecture-completeness check；需要与现有 Gate B / E0-E5 验收语义逐项对齐后定级。

## 5. 已确认的生命周期风险
NativeMLX.suspendIfIdle() 会清除 modelContainer、sessions 和 MLX memory cache。ensureLoaded() 只重新加载 ModelContainer，不自动恢复原 ManagedSession。

当前生产默认 conditionalRestoreEnabled=true，成功轮会保存 checkpoint；PrefixPool 默认开启，因此存在 checkpoint/prefix-pool 恢复经济性。但从 Execution State 语义看，suspend → resume 后并非直接 reattach，而是依赖后续请求重新建立 continuation。

需要分别验证 PrefixPool ON/OFF、checkpoint ON/unavailable、suspend → resume → same Execution continue。不能只用模型重新加载成功作为 resume 正确性证据。

## 6. Oversized 路径发现
OversizedRuntime 与普通 NativeMLX 路径不是同一 Runtime 生命周期实现。当前产品代码明确：single oversized conversation、generation serialized、fork handler 不提供、delete branch 为 no-op、cancellation handler 为 no-op、continuation 依赖内存 servedTranscript。

因此 oversized 的实验 engine 层 Execution State 证明，与产品 OversizedRuntime API 层能力并非完全同构。

这不是立即判定 oversized 实现失败，但必须确认它是否真正验证同一核心 Execution State 路线，而不是独立特殊 runtime。暂列 P1 candidate / scope-conformance audit。

## 7. 已关闭事项不重新打开
delete branch → detach binding、fork restore 成功后才注册 child binding、Step-10 forkPoint/binding，以及 F3 / B-5 / BranchFork 设备证据均已存在，不因本轮审计重新打开。

## 8. 当前审计结论
BETA-AUDIT-1 = OPEN。

当前不能把 README 的 P1 = 0 或已有 79/79 executed test evidence 当成首发技术路线审计完成证明。

下一轮 Round 2：沿 create → generate → checkpoint → suspend → resume → restore → continue → fork → delete 建完整状态转移表；为每个状态找唯一事实源；检查 failure/cancellation 边界；审计普通 checkpoint 与 fork checkpoint 的 generation/mismatch 检测；然后再给 P1 candidates 定级。

首发门槛仍保持 OPEN。