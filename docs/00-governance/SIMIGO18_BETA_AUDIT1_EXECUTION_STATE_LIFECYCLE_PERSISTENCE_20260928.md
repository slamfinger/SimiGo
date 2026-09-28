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
## 9. Round 2 — 九状态单事实源 / 转移 / 失败取消边界（代码级）

审计树：SimiGo main @ 109fef9（树 = 基线 e168555）。行号为该树实际位置。

### 9.1 create
- SoT：`NativeMLX.state.sessions[storageKey] → ManagedSession`（进程内存）。
- 创建路径：(a) generate 冷重建新会话；(b) 池命中 poolBind restore；(c)
  loadSessionCache。三条路径互斥，均落同一个 sessions 槽位。
- 失败边界：无活模型 → notLoaded；池绑定失败 → 回退冷路径（不抛）；
  loadSessionCache 失败 → 抛出、不注册会话。

### 9.2 generate
- SoT：KV/token = ChatSession（物理权威）；transcript = ManagedSession
  .history/historyJSON；请求级 lineage = 进程内 128 FIFO。
- 入口顺序（:407）：oversized 直通（:412，见 9.9）→ ensureLoaded →
  AgentExecutionKey.resolve → lineage.begin → 全局生成 gate → Task +
  LC QUEUED→RUNNING（排队期取消 = CancellationError）→ 注册（重复
  requestId → task.cancel + 抛；isRunning=false → notLoaded）→
  withTaskCancellationHandler（取消传播进 task）→ lineage.end。
- 失败/取消：generateUsingChatSession 内错误上抛 → lineage.end(failed/
  cancelled)；取消走 record() 的 retain-cancelled-prefix 路径（前缀
  保留 + ledger 以本轮 promptTokens 重建，6d01a13）。
- suspend 不可与 generate 并发：suspend 要求 activeRequestTasks 空。

### 9.3 checkpoint
- SoT：磁盘双文件 .safetensors（官方 saveCache，非原子写）+
  .meta.json（SessionCacheMetadata，.atomic 写）。
- **两个失败窗口（W1/W2）**：
  - W1 崩溃于 saveCache 中途 → 部分 safetensors + 旧 meta → restore
    抛出（fail-closed），但**上一代好 checkpoint 已被覆盖销毁**（可用
    性损失，非一致性损失）。
  - W2 崩溃于 saveCache 之后、meta 写之前 → 新 safetensors + 旧 meta
    → **两个文件各自合法，restore 静默成功且 transcript 与 KV 错位**。
- 交叉核对能力：SessionCacheMetadata 无 tokenCount/无 cache 指纹字段
  → 当前**无法检测** W2 错位。修复方向 = save 时盖章 tokenCount（+
  可选 cache 内容指纹），restore 时与实际 ledger 交叉核对，不符即
  fail-closed。注入实验只量化 W2 概率，机制本身已由代码路径确证。

### 9.4 suspend
- 代码（:366）：lifecycleGate 下 lifecycle=.suspended、modelContainer=
  nil、**sessions.removeAll()**、Memory.clearCache()；前置 = 无活跃
  请求 + 闲置超时（自适应，600s 基线）。
- suspend 后存活状态只剩磁盘：checkpoint 文件、prefix-pool artifacts、
  branch-checkpoints 目录。进程存活 → ExecutionBindingRegistry 与
  lineage FIFO 保留（suspend 不清进程内存对象，只清 runtime 状态）。

### 9.5 resume
- 代码（:311）：ensureLoaded 仅重载 ModelContainer；**不回挂任何
  ManagedSession**；lifecycle=.running。
- suspend→resume→同一 Execution continue 的真实路径 = 后续请求触发的
  冷重建（池 admission / branch checkpoint conditional restore），而
  非直接 reattach。resume 成功 ≠ Execution State 恢复成功——二者必须
  分开验证（Round 3 注入矩阵项）。

### 9.6 restore
- 代码（:1420 performLoad）：逐文件 fail-closed——meta decode 失败抛、
  modelId 不匹配抛、snapshot decode 失败抛；但 **W2 错位对（各自合法）
  静默通过**（见 9.3）。恢复会话携带 checkpoint 的 kvFingerprint
  （reuse 检查依赖）+ isRestoredSnapshot 标记。

### 9.7 continue
- 复用/extend 路径（账本修复链后）：恢复/活会话下一轮按 delta 契约
  extend，mode=extend/restore 有 trace 证据；错位对进入时（W2）同样
  走 extend——错误状态被当正常续跑，这是 W2 的实际危害面。

### 9.8 fork
- 代码（:1522 起，含 9956e64 审核批次）：stamp forkPoint（单文件
  原子）→ loadSessionCache 成功 → bind child（事务边界：restore 失败
  不留绑定）→ lineage.recordFork。R1-R5 维持。

### 9.9 delete
- 代码（:1633 起，含 9956e64）：remove session → session.clear() →
  **registry.detach**（行保留、active 清除）→ 删 checkpoint 文件。
  分支不可 merge 语义不变。

### 9.10 oversized 直通（P1-CANDIDATE-3 代码级确证）
- generate() 入口 :412：`if let oversized … return try await
  oversized.handleGenerate(...)` —— 发生在 AgentExecutionKey.resolve、
  lineage.begin、sessions、checkpoint、BindingRegistry、取消保留路径
  **之前**。即 oversized 请求不经过普通执行状态机制约任何一个环节。
- 结论：P1-CANDIDATE-3 的 scope 分叉在代码级确证；"同一核心路线"
  的主张目前仅 oversize 的**模型执行层**成立，执行状态层是独立实现。
  定级待 Round 3 的 conformance 决策。

### 9.11 Round 2 定级输入（Round 3 已裁定，见下节）

```text
P1-CANDIDATE-1  机制升级：W2（错位对静默通过）为正确性危害，
                代码路径确证；W1 为可用性危害。定级=维持 P1
                candidate，Round 3 注入定概率。
P1-CANDIDATE-2  确证：durable Execution State 不存在（lineage
                128 FIFO 进程内、checkpoint 无 lineage history）。
                Round 3 已裁定：非阻断架构边界——durable lineage
                非五动作核心 invariant 的已证要求；ExecutionLineage
                ≈ observability/history。
P1-CANDIDATE-3  确证：代码级直通分叉。定级=Round 3 conformance
                决策（补齐 vs 声明独立 runtime 边界）。
```

下一步 Round 3：W1/W2 失败注入实验 + Gate B/E 对齐矩阵 + oversized
conformance 决策。

## 10. Round 3 — failure-path proof / Gate-B semantic reconciliation（2026-09-28）

### 10.1 C1 failure-path：当前是 fail-open，而不是 fail-closed
代码证据：generate 成功提交 history 后，在 restorePolicy 任一 checkpoint flag 开启时调用 performSave()；performSave() 失败被 catch，只记录 checkpointFailed，不使本轮 generate 失败。
因此：
- logical Execution 已 commit；
- checkpoint 可能不存在、半更新或混代；
- API 仍向调用方返回本轮 GenerationResult；
- 后续 suspend 会清空 sessions；若没有其他可用 PrefixPool 表示，则该轮 durable continuation 可能丢失。
这意味着 checkpoint 当前实际语义是 best-effort recovery aid，而不是成功提交后的强 durability invariant。
若 Beta 对外把 checkpoint 描述为 Execution State durable continuity，则这是 P1 blocking；若明确声明为 best-effort optimization，则需要把对外契约降级并证明 suspend/restore 核心路径不依赖它。当前生产 Conditional Restore 又明确依赖 fresh checkpoint，因此不能简单视为纯优化。

### 10.2 C1 mismatch：现有 guard 不足以证明同代
现有 Conditional Restore 有 kvFingerprint 和 rollforwardCompatible 两层守卫，这是防止配置不兼容和 transcript 前缀陈旧的重要保护；但它们不能证明 safetensors 与 meta.json 属于同一次 checkpoint commit。
因此现有 guard 能做到部分 fail-safe，但不能关闭 generation skew。

### 10.3 C3 fork race：代码路径已能构造出 skew，尚无生产证据证明发生
forkSessionBranch 在 source save 完成后释放 source gate，再读取 cachedTokenIds 并复制 checkpoint 文件。当前没有跨 source/target 的事务 token 或 generation。
因此这是静态代码可证明的 race window，而不是需要等真机偶发复现才能成立的问题。
同时，Step-10 child binding 的顺序仍正确：target restore 成功后才 bind；本轮不重新打开 Step-10。

### 10.4 C2 与既有 ExecutionControlling 语义的对齐
当前 ExecutionControlling 五动作是既有路径的直映射：execute/continue → generate；checkpoint → saveSessionCache；restore → loadSessionCache；fork → forkSessionBranch。产品文档明确要求“不产生第二套执行语义”。
因此当前 Beta 的 Execution State 核心并不是要求一个新的 durable object，而是要求既有五动作之间保持同一 Execution identity / position / continuation semantics。
现阶段没有足够证据把“完整、跨 Runtime、无限历史的 durable lineage log”定义成 Beta 核心 invariant。ExecutionLineage 更接近 observability/history；其 128 FIFO 和 process-local 生命周期不能单独判为 Beta P1。
因此 C2 从“首发阻断候选”降为：Architecture boundary / non-blocking for current Beta，前提是 release contract 不宣称完整 lineage durable。

### 10.5 Round 3 结论
- P1-C1：CONFIRMED BLOCKER — checkpoint consistency + durability semantics 未闭合。
- P1-C3：CONFIRMED BLOCKER — fork source generation 与 child checkpoint generation 没有共同事务边界。
- C2：NON-BLOCKING ARCHITECTURE BOUNDARY — durable lineage 不是当前五动作核心 invariant 的已证要求。
- suspend/resume：NON-BLOCKING，但 release wording 必须定义为 Runtime resume + Execution reconstitution。
- Oversized：仍待产品路径对齐，不得用 oversized engine evidence 替代 NativeMLX lifecycle proof。

### 10.6 Gate status
**BETA-AUDIT-1 = FAIL / RETURN TO IMPLEMENTATION FOR C1 + C3**

这不是要求重新设计 SimiGo 的 Execution State，也不是启动 Palace-1。首发前只需要把 checkpoint generation/commit 与 fork transaction boundary 收紧到当前五动作语义之内，并补对应 failure/race evidence。
