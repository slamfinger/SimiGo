# DCC-0 — Durable Crash Consistency Design Package v0.1

- 状态：DESIGN / PENDING HUMAN REVIEW（本包只做设计与证据审查；不授权实现、崩溃实验或 Frozen Contract 修改）
- 分支：`codex/restore-recovery-coverage`（基线 main `a281ebdc`；`dbcd9330` → `d0994cbf`）
- 日期：2026-10-13
- 审查命令链：本包全部代码事实基于 `d0994cbf` 工作树的只读检查（grep 调用链 + 逐文件阅读），标注为代码行号处均可在该提交复核。
- 核心问题（human 原话定向）：**SimiGo 的 Execution State 在持久化载体参与后，凭什么仍能可靠地继续执行？**

---

## 1. 任务一：真实数据持久化边界盘点（只读）

### 1.1 恢复事务四组件：全部进程内内存，零持久化参与

| 状态对象 | 存放位置（字段级证据） | 所有者 | 是否持久化 | 在 restore 事务中的角色 |
| --- | --- | --- | --- | --- |
| Backend representation | `OversizedSegmentedStateBackend.prefixes: [ExecutionID: [Int]]`、`boundPositions: [ExecutionID: ExecutionPosition]`（O6ExecutionStateOversized.swift:341-342） | 引擎会话私有实例 | **否**（纯字典，无任何文件/SQLite 调用） | 物理绑定（被 restore/rebind 覆写） |
| 真实可恢复物理状态 | MLX 内存中的权重与激活（大张量）；**表示策略 = prefix-recompute**：表示载荷就是 token 前缀数组，物理状态可由前缀重计算（prefill）重建 | 模型进程 | 权重文件（safetensors）是**只读持久输入**，非会话状态 | 决定了"可持久化的最小恢复载荷 = 元数据（token 前缀 + 位置），物理重建靠重计算" |
| Token Ledger | `OversizedTokenLedger.entries: [OversizedTokenLedgerEntry]`、`lastCommittedPosition: [ExecutionID: Int]`（OversizedTokenLedger.swift:57-59） | 引擎会话私有实例 | **否** | marker 写入对象 |
| Coordinator | `handles` / `records` / `representationHistory` / `bindingUncertain`（ExecutionContinuityCoordinator.swift:117-128） | 引擎会话私有实例 | **否** | 逻辑 handle 与 lifecycle 提交 |
| Engine 元数据 | `currentState: ExecutionStateHandle?`、`sessionInfo: OversizedSessionInfo?`（OversizedSegmentedEngine.swift:146/148） | 引擎实例 | **否** | 会话元数据 |

### 1.2 仓库内已存在的持久化实现与其真实调用链（模块存在 ≠ 被使用）

| 持久化实现 | 实际持久化什么 | 落盘机制 | **restore 事务是否使用** | 真实调用方（代码证据） |
| --- | --- | --- | --- | --- |
| `PrefixSnapshotStore`（simigo2-experimental） | 前缀快照元数据（`Data.write(to:metadataURL, options: .atomic)`，PrefixSnapshotStore.swift:142）+ 快照载荷文件 | `.atomic`（临时文件+rename；进程崩溃安全，**无 fsync**，掉电窗口存在） | **否**。对 engine/backend/ledger/coordinator/MLX-backend 五文件 grep `PrefixPool|PrefixSnapshot|SnapshotStore` = 零命中 | Sources 内仅被自身文件引用；Tests 中由 `PrefixSnapshotStoreTests` / `PrefixPoolSessionLifecycleTests` / `MaterializationCoordinatorTests` 直接构造（测试本地接线）。产品仓（SimiGo 主仓）的跨会话前缀池接线不在本仓 |
| `ExecutionStatePrefixPool` | 进程内池核 + 经 snapshot store 落盘 | 同上 | **否**（同上零命中） | 同上（测试构造） |
| `PersistentSRSRepresentation` | SRS（Settled Relation State）持久格式，含 FileManager/JSON 编码（12 处） | 自有持久格式 | **否**。属 SRS-VAL 研究线工件，与执行恢复事务无调用关系 | SRS-VAL 线 |
| `trackD-memory` CarrierSQLite / UA 运行体 | Unified Carrier 数据库（U-A 线） | SQLite（WAL、CAS、operation ledger） | **否**。`simigo2-experimental/Package.swift` 不依赖 trackD-memory；两世界无 import 关系 | CarrierSQLite 自有测试 + CarrierMADS1 崩溃 runner |
| 模型权重文件（safetensors） | 只读持久输入 | 磁盘 | 只在 `load()` 读取；不属于事务写入 | 引擎 load |

**调用链结论**：restore 事务的完整提交序列为 backend 覆写（内存）→ Ledger append/supersede（内存）→ Coordinator handle/record（内存）→ 引擎两个赋值（内存）。**序列中不存在任何持久化步骤**；仓库内三个持久化实现没有一个进入这条链。

### 1.3 单独报告：是否存在"已承诺持久化却无法恢复"的缺陷

- **restore 事务范围内：无。** 事务不承诺任何持久化，因此不存在承诺-恢复缺口。
- **范围外观察（不构成本事务缺陷，单独列出）**：①`PrefixSnapshotStore` 的 `.atomic` 写对进程崩溃安全、对掉电不承诺（无 fsync），且在 Lab 内无生产恢复路径接线（仅测试）——若未来把池快照升级为恢复权威，须先补 fsync/校验语义；②`PersistentSRS` 的持久一致性属 SRS-VAL 线自查范围。两者均不应与 DCC 的尚未实现能力混为一谈。

---

## 2. 任务二：崩溃点矩阵

### 2.1 故障模型三分（不是同一个模型）

| 模型 | 含义 | 对本事务的效应 |
| --- | --- | --- |
| 进程异常退出（SIGKILL/abort） | 进程地址空间整体消失；已到页缓存的文件写入存活 | 四组件同时湮灭；磁盘侧无事务痕迹 |
| 系统崩溃（内核 panic/掉电） | 同上 + 页缓存丢失 | 若未来有文件写入，rename-无-fsync 的产物可能丢失或不完整；当前事务无文件写入 |
| 持久介质故障 | 已落盘数据损坏 | 影响只读模型文件（load 时失败）与未来记录；当前事务无落盘物 |

### 2.2 矩阵（当前架构 = 事务零持久步骤）

裁定列出的六个崩溃点逐项（崩溃时刻 → 遗留持久状态组合 → 现有启动/恢复处理 → 未完成事务可识别性 → 幂等性）：

| 崩溃点 | 遗留持久状态组合 | 现有启动/恢复处理 | 未完成事务可识别？ | 重放/回滚/重绑定幂等？ |
| --- | --- | --- | --- | --- |
| 目标绑定之前 | 无（会话无持久痕迹） | 重启 = 冷启动，重新 `load()` + bootstrap | 不适用（无持久事务） | 不适用；进程内恢复契约见 bf63e562/36072048（隔离+显式 restoreSession） |
| 绑定成功之后、Ledger 提交之前 | 无 | 同上 | 不适用 | 不适用 |
| marker 已写入之后 | 无 | 同上 | 不适用 | **进程内已证**：append 全有或全无；marker 幂等性作为 DCC-2 要求列入 §3.4 |
| Coordinator 提交之后 | 无 | 同上 | 不适用 | 不适用 |
| Engine 元数据更新之后 | 无 | 同上 | 不适用 | 不适用 |
| 多个持久状态分别完成写入的中间时刻 | **结构性地不存在**：提交序列无持久写 | — | — | — |

**矩阵的结构性结论**：因为提交序列没有持久步骤，**每个崩溃点的持久遗留组合都是空集**——不存在"半提交"的持久状态可供检测。进程内恢复语义（隔离 + 显式恢复 + 零副作用拒绝）已由 `d0994cbf` 及之前的测试链建立；它们是**活进程**的恢复契约，不是崩溃恢复契约。崩溃恢复要成为可讨论的对象，前提是先引入持久会话状态——这正是 §3 的设计对象。

---

## 3. 任务三：恢复协议比较与最小可行方案

### 3.0 使设计成立的使能事实

**prefix-recompute 表示策略**（表示策略的设计原意，见 E5ExecutionStateScenario.swift:20 与 Contract 的 restore 语义：restoreRepresentation 为覆盖式重绑定）意味着：物理状态可由 token 前缀重计算重建。因此持久化恢复**不需要**持久化张量——需要的最小持久载荷是元数据：`(executionID, position, continuation, prefix tokens, weights/tokenizer 身份)`。这决定了两个候选方案的真实成本对比。

### 3.1 候选 A：统一事务边界（单一持久事务管理相关状态）

把 Ledger、Coordinator 逻辑状态、绑定记录、会话元数据的提交期写入放进同一个持久事务（如单 SQLite 事务）。

- 一致性保证：最强——跨组件原子提交，崩溃后无中间态。
- 实现成本：高。要求四个组件共享同一存储引擎；与现状冲突点：①backend 是可插拔内存值登记表（协议层明确"physical payload is opaque"），强行入库破坏抽象；②Coordinator/Ledger 当前为进程内结构，重写为 SQLite 语义是大手术；③而真正不可入库的物理状态（张量）反正要靠重计算重建——统一事务为元数据买到的那点原子性，用架构代价换取，收益有限。
- 失败处理：事务回滚由存储引擎承担，干净。
- 与现有架构兼容性：**低**。

### 3.2 候选 B：显式事务记录 + 恢复协议（推荐）

组件保持内存态；引入**一个**小的持久记录作为唯一跨组件持久行为，以记录的状态机协调提交与恢复。

**推荐：候选 B，且分两档落地（Tier 1 先行）**：

#### Tier 1（DCC-1）：会话基线记录（最小持久载体）

- 持久物：每个引擎会话一个目录 `engine-sessions/<session-uuid>/`，内含 `baseline.json`：
  `{sessionUUID, executionID:"S", weightsIdentity, tokenizerIdentity, position, continuation, prefixTokens}`。
- 写入时机：会话 bootstrap 完成后一次性写入（原子写 + fsync；内容寻址文件名/内嵌校验和使撕裂写可检）。
- 崩溃语义：**任何时刻崩溃，恢复决策恒为"回到基线"**——重启后若 baseline 完整 → 以基线前缀重计算重建物理态、按 baseline 重建 Coordinator/Ledger 初始态；baseline 缺失/校验失败 → 冷启动。restore 事务本身保持内存态：崩溃时未完成的 restore 等价于"回到基线"，**无需判定事务是否完成**。
- 状态转换图：

  ```
  [无记录] --bootstrap--> [BASELINE 持久] --任意崩溃--> 重启：BASELINE 完整? 
                                │                        ├─ 是 → 按基线重建会话（重绑定幂等）
                                └─写失败=无记录           └─ 否 → 冷启动
  ```

- 提交顺序：`create + bindRepresentation`（内存）→ `baseline.json` 持久 → 会话对外可见。恢复权威 = **baseline 记录**；提交成功 = **baseline 持久化成功**。

#### Tier 2（DCC-2，可选扩展）：restore 事务记录（INTENT + 回滚规则）

仅当"崩溃后仍要保住 restore 的效果"成为需求时才做：

- 持久物：`intent.json` `{attemptID, fromPosition, toPosition, continuation, targetPrefixTokens}`，在 backend 重绑定**之前**持久写入。
- 崩溃决策规则（确定性、单向）：
  ```
  [BASELINE] --restore 开始--> [INTENT 持久] --内存提交序列--> 会话继续（intent 可清除）
       crash@INTENT 后任意点 --> 重启发现 INTENT --> 规则：丢弃（回滚）
         = 逻辑位置回 fromPosition、按 intent 的 from 前缀幂等重绑定、不补 marker
  ```
  选**回滚**而非重放的理由：回滚不需要 intent 之外的任何持久状态、重绑定天然幂等（覆盖语义，三实现已静态验证）、宿主可无副作用地重试 restore；重放（roll-forward）要求 marker 幂等去重与 target 前缀持久正确性，收益（省一次 recompute）小于成本，登记为未来备选。
- 幂等性要求（硬性）：①baseline/intent 写入 = 原子+fsync+校验和，撕裂/不可解码 intent 一律按 ABSENT（回滚）处理，不可解码 baseline 一律冷启动；②重绑定 = 覆盖语义（已证）；③若未来采用重放：Ledger marker 必须按 `(executionID, position, kind)` 去重——**当前 append 无去重，这是 Tier 2 的前置改动项**；④记录写入必须位于 `lifecycleSerialLock` 临界区内（与事务序列化一致）。

### 3.3 两候选对照表

| 维度 | A 统一事务 | B 显式记录（Tier1/Tier2） |
| --- | --- | --- |
| 崩溃一致性 | 原子（最强） | 基线/回滚语义（确定性、可判定） |
| 实现成本 | 高（四组件改存储语义） | 低（一个小记录 + 恢复规则） |
| 失败处理 | 存储引擎回滚 | 决策规则单向、fail-safe 到冷启动 |
| 架构兼容性 | 低（破坏可插拔 backend 抽象与单 execution 引擎契约） | 高（组件不动，只加旁路记录） |
| 与使能事实的关系 | 未利用"物理可重计算" | 直接利用：持久载荷=小元数据 |

**推荐**：候选 B / Tier 1 先行；Tier 2 仅在需求确认后启用并先补 marker 去重。

### 3.4 四个验收问题的回答

1. **哪个状态是恢复权威？** 持久的会话基线记录（Tier 2 中再加 intent 记录）。内存四组件不是恢复权威，重启后由权威重建。
2. **何时算提交成功？** Tier 1：baseline 持久化成功即会话提交点；restore 是内存事务，其"成功"止于进程生命期。Tier 2：intent 持久 ≠ 提交；崩溃后按回滚规则处理，不把 INTENT 当成功。
3. **崩溃后如何判定事务是否完成？** Tier 1：不需要判定——一切未持久化效果统一等价于"回到基线"。Tier 2：INTENT 存在且可解码 = 未完成 → 回滚；不可解码 = 视为不存在 → 回滚。
4. **如何安全重建其余状态？** 幂等重绑定（覆盖语义）+ 按基线重计算前缀 + Coordinator/Ledger 从记录重建初始态；任何记录不可信 → 冷启动兜底。**重启的最坏情形永远是定义良好的冷启动**——这是单 execution 引擎 + 可重计算表示给出的结构性安全网。

---

## 4. 任务四：后续实现与验证方案（评审通过后才执行）

### 4.1 必须覆盖的真实崩溃时刻（进程级，非 Swift 异常）

1. baseline 写入中途（撕裂文件）→ 重启判定冷启动。
2. baseline 写入完成、进程即死 → 重启按基线重建。
3. Tier 2：INTENT 写入后、重绑定前杀死 → 重启回滚到 fromPosition，无 marker。
4. Tier 2：重绑定后、marker 前杀死 → 同上。
5. Tier 2：marker 后、Coordinator 提交前杀死 → 同上（回滚规则使 marker 不外泄）。
6. 对照组：无崩溃重启 → 会话按基线正常恢复。

### 4.2 验证仪器

- 复用 `trackD-memory` 的 **CarrierMADS1 spawn-self + SIGKILL** runner 模式（本仓已有成熟先例）：父进程派生自身、在注入点 kill -9、再派生验证进程读取恢复后状态。
- 注入点经 DEBUG 门（同 `debugEnsureSession` 先例）置于记录写入/重绑定/marker 之后。
- 验证断言：重启后 position == 规则预期；Ledger 无被回滚尝试的 marker；marker 去重不变量（若启用重放）；基线校验失败路径走冷启动。
- **明确排除**：`try/catch` 异常注入不构成崩溃验证；不重跑已通过的进程内恢复测试来冒充崩溃证据。

### 4.3 实现顺序（评审后）

DCC-1（baseline + 恢复规则 + 崩溃时刻 1/2/6）→ 独立审查 →（如需求确认）DCC-2（intent + 回滚 + 前置 marker 去重 + 崩溃时刻 3/4/5）。

---

## 5. 剩余风险

1. **掉电 vs 进程崩溃**：`.atomic` rename 无 fsync，掉电下新写文件可能缺失/不完整——Tier 1/2 记录必须显式 fsync（或改用 SQLite/WAL），并把"记录丢失"设计为安全路径（本设计已如此）。
2. **基线复用安全**：baseline 必须绑定 weights/tokenizer 身份，跨模型版本复用前缀不安全（呼应 I-1c M-1 weights-id 义务）。
3. **与 PrefixSnapshotStore 的关系**：它是未来天然载体候选，但当前格式无 fsync/校验/intent 语义；是扩展它还是并行新建，留实现阶段决策，不影响本设计的协议语义。
4. **单 execution 边界**：记录按会话目录隔离，沿用 d0994cbf 契约；多 execution 仍 UNSUPPORTED BY DESIGN。
5. **载荷体积**：prefix tokens 随会话增长；baseline 只存 bootstrap 前缀（小），restore 目标前缀（Tier 2 intent）可能大——若超阈值，记录存摘要+引用 sidecar 快照，属实现细节。

## 6. 验收对照

| 验收问题 | 本包回答位置 |
| --- | --- |
| 恢复权威是谁 | §3.4-1 |
| 何时算提交成功 | §3.4-2 |
| 崩溃后如何判定事务完成 | §3.4-3 |
| 如何安全重建其余状态 | §3.4-4 |
| 实际存储调用链 | §1.2 |
| 崩溃点矩阵 | §2.2 |
| 协议比较 | §3.1-3.3 |
| 已承诺持久化却无法恢复的缺陷 | §1.3（事务内：无；范围外两项单列） |
| 崩溃验证计划 | §4 |
