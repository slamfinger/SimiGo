# PALACE-1 Product Durable Writer Provenance Audit — 2026-09-30

状态：`PRODUCT WRITER PROVENANCE AUDIT COMPLETE / AWAITING SECOND-LAYER`  
审计对象：SimiGo 产品仓 `~/Documents/SimiGo`（remote `slamfinger/SimiGo.git`，
branch `main` @ `dc12a0c`，worktree clean）  
方法：**只读**（grep/sed/文件读取）；零代码修改、零删除、零 Contract 变更、
零 PALACE 语义设计  
上游参照：Contract v1.0（UPSTREAM REFERENCE）；Physical Storage Audit
（`6122ffc`，本审计补其 writer 侧 provenance 并修正两处结论）

## 1. durable writer 全景（谁写、何时写、由什么触发）

### 1.1 branch-checkpoints（62G / 102 对）

Writer：`NativeMLX.saveSessionCache` / 内核 `performSave`
（`SimiGo/Inference/NativeMLX.swift:1455-1542`）。三个触发路径：

```text
T-1 每成功轮自动落盘（NativeMLX:1218-1224）——「Phase B：每成功轮落
    checkpoint（roll-forward 的 last known good；实测 0.15s@58k）」；
    Conditional Restore 依赖 ledger-end 新鲜 checkpoint（陈旧 checkpoint
    曾致 +10k 重渲，a210155 对照）
T-2 驱逐保护（:417-443）——checkpointDirty 的会话不可被逐出内存；重试
    保存，失败保活而非静默丢弃连续性
T-3 显式 saveSessionCache 调用（gate 互斥）
```

存储位置：`~/.simigo/branch-checkpoints/`（`defaultBranchCheckpointStore()`，
NativeMLX:1705-1712）；产品自述：「**suspend 会清空内存会话，落盘
checkpoint 是分支唯一的 durable 存活物**」（:1706 注释）。

### 1.2 prefix-pool（15G / 24 对）

Writer：`NativeMLXPrefixPool`（FORK-3 step-9 wiring）→
`PrefixSnapshotStore(root: ~/.simigo/prefix-pool)`；export 登记去重
（`exportedTokenBoundaries`）；**重启 rescan**（重启 warm：磁盘边界重新
注册进池；P-I1 在 admission 对来方消息流重算，坏声明只会 miss）。

### 1.3 Retention 机制存在（修正 Physical Audit F-6）

`BranchCheckpointRetention`（BETA-STORAGE-1，`BranchCheckpointRetention.swift`）：
成对完整性（孤儿 safetensors/meta 互相回收）+ ownership-aware（active keys
永不回收）+ 字节预算（`RuntimeTuning.branchCheckpointByteBudget` 默认
**64 GiB**，env `SIMIGO_BRANCH_CHECKPOINT_MAX_BYTES`）；每次成功轮后
enforce（NativeMLX:1223）。**62G 累积 = 预算内累积（64 GiB 之下），不是
无机制**。prefix-pool 同理：`prefixPoolPhysicalByteBudget` 默认 **16 GiB**
（15G 在预算内）+ token 预算 200k。**Physical Audit F-6「无 retention/GC
痕迹」修正为「retention 为预算驱动且预算未触顶」。**

## 2. 逐问回答（任务包 11 问）

| # | 问题 | 答案（file:line） |
|---|---|---|
| 1 | 谁创建 checkpoint | `saveSessionCache`/`performSave`（NativeMLX:1455-1542）；触发 = T-1 每成功轮 / T-2 驱逐保护 / T-3 显式 |
| 2 | 谁决定 storageKey | `AgentExecutionKey.resolve` → `"\(agentId)/\(sessionId)/\(logicalBranchId)"`（StreamTokenFilter.swift:154-176）；agentId 缺省 `"default"`、规范化 ≤128 字符。**identity source = 产品会话/分支命名（caller 供给）** |
| 3 | generation 从哪里来 | 每次成功保存新生成 UUID（NativeMLX:1527）；fork 时随 checkpoint 复制（SessionCacheMetadata doc :2251-2253）；恢复时作为 sidecar commit identity 校验 |
| 4 | cacheSHA256 对应什么 | 官方 `.safetensors` 字节的流式 SHA-256（`sha256HexOfFile` 4MB chunk；STEP-10 review：lifecycle-boundary 操作，不进生成热路径）= **representation integrity identity**；恢复失配 fail-closed（:1624-1626） |
| 5 | transcript 从哪里来 | `managed.historyJSON`——活会话实际处理过的消息史（role+content）；落盘为逐字快照；恢复时 `makeChatMessages` 重建。source of truth = 运行时会话自身 |
| 6 | checkpoint 与 transcript 如何关联 | 同名文件对 + generation/cacheSHA256 绑定：「vendor cache 与 sidecar 分开写；generation id + content hash 绑定成对，两写之间任何 crash = invalid checkpoint 而非 mixed pair」（:1521-1523） |
| 7 | prefix snapshot 谁登记 | `NativeMLXPrefixPool` 持 Lab `ExecutionBindingRegistry`（**FORK-3 step-9：日常路径上 Execution↔Representation 绑定的真实持有者**）+ `PrefixSnapshotStore`；Ref 由 entry chain hash 派生（R-I1，kind `.prefixSnapshot`） |
| 8 | checkpoint 与 prefix 是否同一 State | **代码层未建立直接关联**：checkpoint 按 storageKey（分支会话持久），pool 按 namespace（modelID+kvFingerprint）跨会话共享；bindings 进程生命周期，「**pool store 持久化，registry 不持久（恢复的会话在 poolBind 重绑）**」（NativeMLXPrefixPool:46-49）。互补机制（会话持久 vs 跨会话前缀共享），同一性证据未建立——维持 UNKNOWN |
| 9 | 删除 checkpoint 后谁恢复 | **无自主恢复路径**：`loadSessionCache` 对缺失文件直接 throw（:1609）；产品恢复语义 = 客户端下一轮传全量对话（fragment-continuation delta 契约），会话自客户端侧重建（首 token 冷）。恢复责任 = 客户端协作 + 重算，非 checkpoint 系统自主 |
| 10 | 删除 prefix 后谁重建 | 登记行为：rescan 跳过缺失（P-I1：admission 重算，坏声明只 miss）；installHook 任一失败自愈 + nil → 回退全量 prefill。= **性能回退路径**（是否伴随 State 损失 = UNKNOWN，留给实验） |
| 11 | meta.json 是 State 记录还是附属 metadata | **代码层：附属 commit-record**——加载 fail-closed 要求 safetensors 在场且 SHA 匹配，单独 meta.json 无恢复代码路径。**潜在：它含全部 transcript + modelId + generation + storageKey + forkPoint = 一份完整进程外语义记录，其独立恢复用途未实现**。按 human 指令措辞：当前无法确认其为 representation 附属物或独立 durable semantic record——由恢复实验（E3）回答 |

### 2.1 额外发现：两套身份方案在产品代码里已有部分映射

```text
M-1  产品把 storageKey 直接作为 executionID 传给 Lab 契约调用
     （NativeMLX:764/:1192 —— ExecutionBindingRegistry / pool bind）：
     「ExecutionID ≈ storageKey」在运行时调用层已发生
M-2  lineage.attachCheckpoint(executionId:checkpointKey:)（ExecutionLineage
     .swift:70-76）——执行与 checkpoint 的关联在进程内 lineage 中登记
M-3  recordFork(parent:child:) 仅在 fork 全程（save→copy→load）成功后
     记录——「失败的 fork 不留 parent→child 假 provenance」（:80-84）
M-4  Contract 五元组 vs 物理字段的对应残缺：
     storageKey ≈ ExecutionID 角色；checkpointGeneration ≈ 代际身份；
     forkPoint ≈ lineage 记录；cacheSHA256 ≈ 完整性；
     【position / continuation.nextInput / lifecycle-tombstone 无物理
     字段】——position 隐含于 transcript 长度；无 tombstone 概念
     （retention 按预算直接删 pair）
```

## 3. 对 Physical Storage Audit 的两处修正

```text
F-6 修正：「无 retention/GC 痕迹」→「retention 机制存在且预算驱动
（checkpoint 64 GiB / pool 16 GiB 默认；本轮实测 62G/15G 均在预算内）；
累积 = 预算内行为」。durable accumulation 无 lifecycle 的表述保留
（lifecycle = tombstone/恢复语义，仍不存在）。

C 答案措辞撤换（human 指令）：撤「零个 durable Execution State 实例」
结论，改为「当前无法确认 meta.json 是 Physical Representation 的附属物，
还是已构成独立的 durable semantic record；因此当前无法判断 Physical
Representation 全部消失后是否仍存在 durable Execution State」——
meta.json 至少是进程外 durable record；是否为 State 由恢复实验回答。
```

## 4. 关键机制发现（provenance 的研究价值）

```text
K-1 恢复判据已在产品代码中存在且 fail-closed：generation（sidecar commit
    identity）+ cacheSHA256（content identity）+ modelId（同源校验）。
    这是一套已运行的「恢复完整性三重判据」——Contract AC-3 的 RB-4/RB-7
    在产品侧的对应物。
K-2 checkpoint = 「一个逻辑执行的 durable receipt」（产品自述，BETA-
    STORAGE-1 头注）——与 Contract 的 snapshot 概念在语义上同构，但字段
    方案不同（M-4）。
K-3 fork = 磁盘 round-trip（官方 saveCache → 独立反序列化实例；「选边
    提升」：target 覆盖语义 + 其余分支 DELETE）；forkPoint 登记 + lineage
    recordFork 仅记录成功 fork。
K-4 会话恢复语义 = 官方 fragment-continuation：客户端下一轮传全量对话，
    SimiGo 按 delta 只传新增，首 token 即 warm（loadSessionCache doc）。
K-5 依赖的 Lab 契约类型：`import SimiGo2Experimental`（NativeMLX:9）；
    ExecutionBindingRegistry 为日常路径绑定的真实持有者（进程生命周期）。
```

## 5. 对 Contract v1.0 / OP / G 的影响（重锚定，不解决）

```text
OP-1  transcript equivalence——transcript 已是 durable 事实（meta.json），
      但「transcript 恢复 = SAME State」仍无证据；E3 实验对象
OP-2/G-7  durable identity——产品的 storageKey + generation + lineage
      attach 是已运行的类身份机制，但跨重启 reservation 无 tombstone
      语义；重锚定
OP-3/G-10  durable store——产品 checkpoint/pool 就是已存在的 durable
      store 实物（77G），「无 durable store」的表述须精化为「无 SC-2
      形状的 durable store」；重锚定
RB-1…RB-8  K-1 三重判据 = RB-4/RB-7 的产品侧对应物；CONFIRMED-unchanged
IC-1…IC-5  SAME/NEW 法则不变；IC-1 的工程兑现 = E1/E2/E3 实验对象
S3 风险图  G-5/G-6/G-8 相关判断不受影响；G-10 的「Lab 零实物」表述按
      本审计精化
```

## 6. Non-claims

```text
✔ 只读审计（grep/sed/文件读取）；零代码修改、零删除、零 Contract 变更
✔ 不做 PALACE 语义设计；不关闭任何 OP/G；E1/E2/E3 实验矩阵留待 human
✔ provenance 基线 = 产品仓 main @ dc12a0c；后续 commit 不在本审计内
```
