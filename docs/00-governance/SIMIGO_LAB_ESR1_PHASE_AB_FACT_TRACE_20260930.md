# ES-R1 Phase A+B Fact Trace — State Inventory & Live-State Baseline

日期：2026-09-30  
状态：`ESR1_PHASE_AB_COMPLETE / PHASE_C_AWAITING_HUMAN_BOUNDARY_RULING`  
实验 Gate：`ES-R1`（结果类 R1-A/B/C/D，Phase C/D 后裁定）  
Phase A = 只读链路追踪；Phase B = 破坏前确定性基线（已执行，零 durable
写入，204 前后核验）  
State 对象 = 真实 checkpoint `5401315f`（17 条 agent 会话 + safetensors KV，
实验副本 /tmp/simigo-palace1-e1/baseline，SHA 已验）

## Phase A — State Inventory

### A1 Identity（谁读/谁写/谁验证）

| 标识 | 写者 | 读者 | 验证者 | 角色 |
|---|---|---|---|---|
| `storageKey` = agentId/sessionId/logicalBranchId | AgentExecutionKey.resolve（StreamTokenFilter:154-176） | sessions 字典寻址（NativeMLX:674 等）、checkpoint 文件名、lineage.attachCheckpoint、Lab 契约 executionID（:764/:1192） | 无独立校验——**身份即寻址** | **主身份载体** |
| checkpoint 文件名 | cacheFileName(for: key) 展平 | loadSessionCache 寻址 | 间接（key→文件名映射） | storageKey 的 durable 投影 |
| `meta.storageKey` 字段 | performSave | **无人校验**（E1.5-Q1） | 无 | informational duplicate |
| `checkpointGeneration` | :1527 每保存新 UUID | load presence 校验（:1614） | presence-only | commit marker（非身份） |
| request UUID（requestId） | generate 调用方 | lifecycle coordinator / activeRequestTasks | 注册制 | **Transient（每请求）** |
| Lab `ExecutionID` | coordinator.create/fork | handle 字典 / lineage | duplicate 拒绝 | Lab 语义身份（零 MLX） |
| lineage（product） | attachCheckpoint/recordFork | 无 reader（进程内 O 层） | fork 全程成功才记录 | 观测 provenance |
| lineage（Lab） | coordinator fork | restore/handle | tombstone 政策（Phase B 登记） | 语义 linkage |

**A1 结论**：身份 = **caller key（storageKey）**，一物三面（运行时寻址/
文件名/Lab ExecutionID 同值）；request UUID 是瞬态；generation/SHA 是
完整件标记而非身份（E1.5 已钉）。

### A2 Position（四个不等物）

```text
logical position（Lab ExecutionPosition） = 轮次计数，continueExecution +1
KV token length（safetensors 形状）       = 31712 token（物理影子，E0）
checkpoint generation                     = UUID（版本标记，非位置）
history.count（product 事实位置代理）      = 17（本 State；loadSessionCache
                                            恢复后即此值；delta 契约按
                                            count 计算 coveredMessages）
```

**A2 结论**：产品侧**没有独立 logical position 字段**——`history.count`
兼任位置代理（E0 F-1 的具体形态：Contract 五元组的 position 在物理层
缺席）。KV token 长度与轮次**不同层不同单位**。Phase B 实测：restore 后
position_before = 17，probe 后 = 18（history.count 口径）。

### A3 Continuation（history 不参与时，还有什么能说「从这里继续」）

逐层盘点（读者实测）：

```text
1. fragment-continuation delta 契约——产品当前唯一机制：客户端传全量
   对话，SimiGo 以 existing.history（或 incoming.dropLast）为锚计算增量。
   ⇒ continuation point = 现有 history 的末端；无 history 即无锚。
2. Lab continuation.nextInput（String）——契约级文本标记，随 handle 走；
   restore/fork 显式携带。
3. Lab ExecutionPosition——轮次级位置标记（restore 目标即位置）。
4. checkpoint meta.transcript——durable 的 history 副本（R2n/E3 已证
   continuation-bearing），本身无「继续点」标记，继续点 = 其末端。
5. lineage / BindingRegistry / checkpoint generation——均不携带
   continuation 信息（provenance / 关系 / 完整性）。
```

**A3 结论**：当前系统内「从这里继续」= **history 末端**（product 经
delta 契约，Lab 经 nextInput/position）。除 history/nextInput 外无任何
独立 continuation marker——这正是 R2n/E3 的 necessity/locus 结论在
代码层的形状。

### A4 Representation 分类（D/R/P/O/T/U）

| 对象 | 分类 | 依据 |
|---|---|---|
| live MLX session（ManagedSession：ChatSession+KV） | **P + R**（表示 + 运行时绑定一体——当前产品唯一二合一物） | 字段表（:30-54）；驱逐=bind 失效 |
| checkpoint safetensors | **P** | E0/R1 |
| checkpoint meta.json | **D candidate**（continuation-bearing 已证：R2n/E3；transcript 无完整性门：E1.5-Q2） | 本链 |
| Prefix Pool 条目 | **P**（性能表示，E2） | E2 |
| BindingRegistry 行 | **R**（进程内，restore 后重绑） | NativeMLXPrefixPool:46-49 |
| lineage records / trace log | **O** | ExecutionLineage |
| checkpointDirty / lastCompletionMode / cacheEff | **T**（瞬态运行时态，不持久化） | ManagedSession 字段表 |
| request UUID | **T** | A1 |
| Contract 五元组的物理实例 | **U**（产品层无字段——G-B2-2/物理 audit F-1 的持续形态） | E0/provenance |

## Phase B — Live-State Baseline（已执行）

```text
State = default/5401315f-faa7-4984-9639-fccef06ae188/main
        generation c1185f0a…；history 17；safetensors SHA 已验（E1）
隔离   = pool OFF（env）+ conditionalRestore OFF（tunable）→ 零 durable
        写入（204 前后核验）；probe =「继续执行。」（greedy，maxTokens 32）
B0a    restore(position 17) → probe → O1 = 「你是想继续查看其他目录吗？
        比如：- **三公司管理制度及规定**（另一个4号文件夹）- **国家及地方法」
        （55 字符；深度会话关联——延续「查看参考文件」的任务线）
B0b    re-restore（rewind 到 checkpoint 位置）→ 同 probe → O2 = O1 逐字相同
PB1    CONFIRMED：live-state baseline 确定性成立（P1 强证据层可用）
```

**Phase B 意义**：State(E, 17) 的可继续执行性 + 确定性输出已锁定——
Phase C 删除表示后的任何 Reuse 尝试都有了可归因的基线（O1/O2 可比对；
P1 层判定可用）。

## Phase C 前置事实（供 human 裁定破坏边界）

```text
可破坏对象（副本内）：safetensors（= P，E1 mutation 已有先例）
保留对象（副本内）：meta.json（= D candidate，含 transcript/generation/
                    modelId）
Runtime 可见性：loadSessionCache 在 meta 在场时走完整校验链后于缺失
                safetensors 处 fail-closed（E1-R1 ×3）——即「重建表示的
                专用 API」不存在（materialization seam absent 的候选形态）
复用路径候选（Phase D 待裁）：现有 API 中最接近 State Reuse 的入口 =
                loadSessionCache（restore 到 N）——但其本质是把 P 装回，
                而非从 State 物化新表示；真正符合「State Reuse」定义的
                入口在现有产品中【尚未发现】——Phase C/D 将以实验裁定
                R1-A / R1-B / R1-C
```

## 产物对照（human §13）

```text
① ES-R1_FACT_TRACE     = 本文件（Phase A + Phase B 部分）
② REPRESENTATION_LOSS  = Phase C 后产出
③ REUSE_EXECUTION_TRACE = Phase D 后产出
④ GATE RESULT          = R1-A/B/C/D（Phase D 后裁定）
```
