# C 轮证据总账：生产任务执行路径的 IS 结算准入

- run root：`~/SimiGo-Agent-Runs/handoff-causality-20261022c`
- 运行标签：`handoff-causality-20261022c`
- 研究判定范围：C1–C4 分别判定，**不合并为单一总 PASS**
- 历史证据：b 轮 `handoff-causality-20261022b` 与 `run-20261022a` 未修改、未覆盖

---

## 1. 运行身份与证据边界

| 项 | 值 |
|---|---|
| HEAD | `e7f63856298390deb8596a4a30e173d3fb466eaa`（branch `main`） |
| 改动前快照 | `manifests/workspace-before.json`，`2026-10-22T02:35:44Z` |
| 快照覆盖 | 5,176 个文件；3,703 条被保护路径；staged diff 为空（sha256 `e3b0c442…`，即空串） |
| 改动后校验 | `manifests/workspace-after.json`，`2026-10-22T02:53:33Z`，`result=PASS`，`issues=[]` |
| 本轮变更文件 | 8 个（见 §2），全部在 `changed_files` 内且前后 sha256 已记录 |
| 二进制 | `111d7b4ed738c973b035e6505f0a3cb2d6bcade7db612aff53478eb00b249d0c`，104,139,408 B，mtime `02:43:25Z` |
| 二进制的两个 argv 路径 | `.build/debug/RealModelHandoff`（Phase 2）与 `.build/out/out/Products/Debug/RealModelHandoff`（Phase 1）realpath 相同、sha256 相同，是同一个物理文件（`manifests/binary-identity.json`） |
| 运行后构建 | `logs/swift-build.log`：`Build complete`，`BUILD_EXIT=0`，**未重新链接 `RealModelHandoff`**（二进制 mtime 仍为 `02:43:25Z`） → 该二进制与 guard 后的源码状态一致 |
| 源码差异 | `diffs/c-round-session.diff`（8 个文件，181,385 B，sha256 `f7745d72…`） |
| 全量产物索引 | `MANIFEST_SHA256.txt`（本文件之外的 run root 全量 sha256） |

### 1.1 本轮消除了 b 轮的追溯性边界，但保留一条新的诚实边界

- b 轮问题：`workspace_guard` 快照建立在 Phase 1 之后，无法证明 Phase 1 期间的工作树变化被覆盖。
- c 轮做法：**快照先于任何本轮编辑**（02:35:44Z），随后所有编辑、构建、4 项 Python 自测、Swift 测试、Phase 2、Phase 1、guard verify 依次发生；guard 的 8 个文件哈希在本文件写作时逐个重算，**全部与 `workspace-after.json` 一致**，证明 guard 之后没有任何源码改动。
- 仍需明示的边界：工作树自 HEAD `e7f63856` 起一直未提交，部分生产路径代码（bridge 的 `resolve-model-input` 骨架、integration 的适配段落）在 02:35:44Z 快照之前就已存在于工作树。因此：
  - **本轮会话增量**由 before/after 快照精确覆盖（8 文件、逐文件 sha256）；
  - **相对 HEAD 的全部未提交增量**由 `diffs/c-round-session.diff`（锚定 `e7f63856`）保存，不依赖快照；
  - 仍不能把“快照之前某次工作树内编辑发生在哪一刻”归因到本轮。这一点不再影响本轮因果结论，因为实际执行的二进制 sha256 固定、且运行后构建为 no-op（源码未再变化）。

---

## 2. 生产执行路径的改动（不是新增 ES/IS 适配层）

### 2.1 结算解析、依赖校验、输入构造进入生产路径

`execution-information-loop/production_runtime_bridge.py`（38,285 → 51,008 B，sha256 `45d89fab…`）

- 新增 `resolve-model-input`：读取任务项的 `input_bindings` 与 `next_input_template`，**递归**解析依赖闭包，复用既有 `_settlement_reuse_decision` 判定（`state==SETTLED`、contract、来源版本、`source_payload` 摘要、`result_value` 摘要、`dependency_object_ids`、`valid_until`、`validity_policy`、`evaluated_at`）。
- 输出准入对象：`input_sha256`、`input_byte_length`、`template_sha256`、每个 binding 的 `byte_offset/byte_length/value_sha256`、`settlement_object_id`（等于对象字节 sha256）、`result_value_sha256`、`dependency_settlement_object_ids`、`checks`。
- 结构化拒绝：`AdmissionRefusal(stage, reason, detail)`；新增 `SETTLEMENT_OBJECT_UNREADABLE`（对象字节不可读/摘要不符）与 `TASK_ITEM_UNREADABLE`（任务项不可读）两个阶段，不再以未捕获异常中断。

`simigo2-experimental/Sources/SimiGo2Experimental/ProductionRuntimeInformationIntegration.swift`（52,911 → 68,137 B，sha256 `994c9015…`）

- `ProductionTaskInputAdmission` / `ProductionTaskInputBinding` / `ProductionTaskInformationContinuation`。
- `resolveTaskInput(database:taskItemID:evaluatedAtUTC:)`：调用 bridge 后做**独立的字节级复核**——输入 sha256 与字节长度、模板 sha256、7 项必需 checks、`settlement_object_id == settlement_object_sha256`、binding 切片与 `value_sha256` 一致、依赖声明集合与闭包一致、模板重展开等于 `inputText`。
- `continueTaskFromInformationSpace(...)`：**先准入，再 `continueTask`**；模型只接收 `admission.inputText`，`modelValue` 闭包额外收到 admission，使“被校验的对象身份”与“注入模型的值”是同一份数据。

### 2.2 harness 不再中介取值

`simigo2-experimental/Sources/RealModelHandoff/Causality.swift`（29,332 → 28,335 B，sha256 `99b2aa58…`）

- 删除 `settlementFields`、`readSettlement` / `readItem` 调用与本地字符串插值；Phase 1 A0 与 Phase 2 均改为调用生产 `continueTaskFromInformationSpace`。
- Phase 2 逐案例记录 `harness_read_settlement_calls`、`harness_read_item_calls`、`harness_is_reads`，6 个案例**全部为 0 / 0 / []**。
- 新 terminal：`PHASE2_INPUT_ADMISSION_REFUSAL`、`PHASE2_PRE_GENERATION_FAILURE`、`PHASE2_SETTLEMENT_REFUSAL`；schema 升为 `SIMIGO-CAUSALITY-PHASE2-V2`。
- 说明：Phase 1 A0 的 evidence schema 没有记录 `harness_read_*` 字段（`SIMIGO-CAUSALITY-PHASE1-V1`），因此 A0 的“非中介”证据是 admission 记录 + 代码路径 + `production_continuation_invoked=true`，而不是这两个计数器。这是本轮的一条 schema 不一致，需要下一轮补齐。

### 2.3 无旁路注入

- 6 个 Phase 2 案例的 argv 中 `command_contains_nonce=false`；nonce 不出现在 argv、环境、cold seed、U2 基础模板、另一世界数据库/日志/状态、临时文件中（B4 `surface_contains_nonce` 全部 false）。
- 两世界 cold seed 相同（`cold_seed_identical=true`），只有 IS 结算值不同 → U2 输入的差异只能来自结算对象。

- 结构上也没有注入通道：`continueTaskFromInformationSpace` 的入参只有 `database`、`handle`、`advancementID`、`evaluatedAtUTC`、`demandID`、`taskItemID`、`seedText`、`maxTokens` 与 `modelValue` 闭包，**没有接受结算值的参数**；`resolveTaskInput` 只从数据库读取并解析。`seedText` 是两世界相同的冷启动种子，不承载 nonce 或结算值。
- b 轮 run root 在 02:35 之后没有任何文件被写入（`find -newermt` 为空），历史证据未被覆盖。

---

## 3. 生成前准入时序：B3c 的时序缺陷已闭合

拒绝发生在 `resolveTaskInput` 内，早于 `tokenize`、早于种子 tokenize、早于 `continueTask`：

| 案例 | 干预 | 拒绝 stage | reason | 生成前计数 `text/seed/model` | `generation_entered` | `continue_task_entered` |
|---|---|---|---|---|---|---|
| B1-harness | 删除 TASK-U1 的 settlement 行（保留 item/source） | `SETTLEMENT_NOT_ADMITTED` | `MISSING_OR_SUPERSEDED_SETTLEMENT`（item `TASK-U1`） | 0 / 0 / 0 | false | false |
| B3a | TASK-U1 结算对象字节被替换（id 仍声明原值） | `SETTLEMENT_OBJECT_UNREADABLE` | `ObjectByteMismatch: abc6c050…` | 0 / 0 / 0 | false | false |
| B3c | TASK-U2 不再声明对 TASK-U1 的依赖 | `INPUT_BINDING_DEPENDENCY_NOT_DECLARED` | `placeholder {secret} requires TASK-U1, which the current task item no longer declares`（item `TASK-U2`） | 0 / 0 / 0 | false | false |

三个案例均 `production_continuation_invoked=true`（确实进入了生产路径）且 `generation_entered=false`（在生成前被拒），因此 b 轮“U2 先消耗未最终校验的输入、再在结算阶段被拒”的问题在受测 handoff 路径上不再出现。

自动化测试（同一套 mutation，独立于真实模型运行）：

- `execution-information-loop/admission_selftest.py`：happy / missing / tampered / dep-mismatch 四条件，断言结构化 refusal、stage/reason、DB 字节不变、无新文件；`logs/admission-selftest.json` → **4/4 PASS**。
- `Tests/SimiGo2ExperimentalTests/ProductionInputAdmissionTests.swift`：以 `--emit-fixture` 复用上述 mutation，在 Swift 侧断言 `tokenize_text_calls=0`、`tokenize_seed_calls=0`、`model_continuation_calls=0`、`modelValueBuilder=0`、DB 字节与 state 目录 identity 不变；`logs/swift-test-admission.log` → **1 test / 0 failures（内部覆盖 3 个条件）**。

---

## 4. Phase 1：恢复准入（stage-A 基线，逐案例独立进程与独立副本）

| 案例 | 干预 | 结果 | 生成调用 | 备注 |
|---|---|---|---|---|
| A0 | 基线不变 | `PHASE1_OBSERVED`，`input_admission_status=ADMITTED` | 1（text 1 / seed 0） | 恢复成功，position=1，prefix tail 匹配；答案 `KC3489-e9af`；输入 sha256 `019345dd…`（166 B），模板 `7610b375…`；依赖 SOURCE `a71d8564…`、U1 `130b3d2e…`；U2 settlement 动作 1 次 |
| A1 | 删除 settlement checkpoint | `settlementCheckpointMissing:PRODUCTION-REAL-PALACE` | 0 | 生成前失败 |
| A2a | result digest 篡改 | `settlementCheckpointMismatch:PRODUCTION-REAL-PALACE:result_digest` | 0 | 生成前失败 |
| A2b | validity basis 篡改 | `settlementCheckpointMismatch:PRODUCTION-REAL-PALACE:validity_basis` | 0 | 生成前失败 |
| A3 | IS 无已结算执行 | `informationSpaceHasNoSettledExecution:ADVANCED` | 0 | 生成前失败 |
| A4 | state 目录为空 | `durableExecutionStateMissing:PRODUCTION-REAL-PALACE` | 0 | 生成前失败 |

`phase1/summary.json`：`all_observed_as_expected=true`（进程退出码全为 0；失败以结构化 `failure_label` 记录）。

对照 b 轮：A0 的读取与插值已从 harness 移除，改由生产路径构造输入；A1–A4 的拒绝语义不变。

---

## 5. Phase 2：双世界与 B0–B4

两世界各自：独立 stage-A 进程生成并结算不同 nonce，随后 U2 在**新进程 + 空 state 目录**中启动。

| 案例 | 世界 | terminal | 准入 | U1 / U2 动作 | 关键证据 | 生成 |
|---|---|---|---|---|---|---|
| B0-A | A | `PHASE2_OBSERVED_SUCCESS` | ADMITTED | U1 REUSE / U2 COMPUTE | U1 obj `abc6c050…`，SOURCE `00e4a2f7…`；input `31c52016…`（192 B）；template `7610b375…`；答案 `5feb29e7…-84cf` | 1（1/1/1） |
| B0-B | B | `PHASE2_OBSERVED_SUCCESS` | ADMITTED | U1 REUSE / U2 COMPUTE | U1 obj `271bd0d6…`，SOURCE `832b7e88…`；input `d45fd439…`（192 B）；同一 template；答案 `e66e0c8e…-84cf` | 1（1/1/1） |
| B1-harness | A | `PHASE2_INPUT_ADMISSION_REFUSAL` | REFUSED | — | 见 §3 | 0 |
| B3a | A | `PHASE2_INPUT_ADMISSION_REFUSAL` | REFUSED | — | 对象声明 `abc6c050…`，实际字节 sha `cb735be3…` | 0 |
| B3b | A | `PHASE2_OBSERVED_SUBSTITUTION` | ADMITTED | U1 REUSE（替身）/ U2 COMPUTE | 替身 obj `7f937107…`，`result_value_sha256` `3dc67443…`；input `c0dc38ca…`；答案 `2331067d…-84cf` | 1（1/1/1） |
| B3c | A | `PHASE2_INPUT_ADMISSION_REFUSAL` | REFUSED | — | 见 §3 | 0 |
| B1-loop | A | `OBSERVED` | 不适用（通用循环） | SOURCE REUSE，**U1 COMPUTE、U2 COMPUTE** | 删除 U1 settlement 后，carrier_loop 重算 `TASK-U1`、`TASK-U2` | 不适用 |

- **B2（双世界差分）**：`C2_DIFFERENTIAL_ESTABLISHED`，9 项 checks 全 true——结算对象不同、U2 输入不同、模板相同、cold seed 相同、两世界输出各自跟随本世界结算值、两世界均为 U1 复用 + U2 计算。
- **B4（交叉污染审计）**：两世界均 `CLEAN`，`cross_contaminated=false`。nonce 长度 32 hex（sha256 `8b433559…` / `a244643e…`），仅出现在允许面（本世界主数据库、U1 prompt seed、U1 结算结果、U1 source payload），argv/环境/另一世界/临时文件命中全为空。
- **进程与状态记录**：stage-A pid 7313 / 7590，退出码 0，`alive_after_exit=false`；逐案例 evidence 记录 `pid`、`database_before/after`、`state_before/after`、`is_status_before/after`、`es_lifecycle_records`；主驱动侧还记录 `started_at_utc`、`wall_seconds`、`timed_out`、argv、日志 sha256。

### 5.1 输入与输出 token

- 输入：`prompt.next_input`、`next_input_sha256`、`next_input_byte_length`、`seed_sha256`；准入对象中的 `input_sha256` 与之相等（A0/B0-A/B0-B/B3b 均一致）。
- 输出：`generated_token_ids`（B0 系列 64 个 token、A0 32 个 token）、`generated_text`、`answer`、`answer_sha256`、`matches_settled_expected`。
- 注意：A0 的 `generated_text` 在答案后继续输出了 session log 片段（32 token 截断内），因此 `matches_expected` 依据的是 `answer` 字段与前缀/结算匹配，而不是整段文本相等。

---

## 6. C1–C4 增量判定（逐项独立）

### C1 恢复准入 — 判定：**已观察（本轮延伸至生产任务执行路径）**

- 本轮证据：A0 经生产 `continueTaskFromInformationSpace` 恢复并生成（`ADMITTED`、1 次生成、prefix tail 匹配、position=1）；A1–A4 在模型生成前拒绝，`model_continuation_calls=0`。
- 相对 b 轮的变化：准入与输入构造发生在执行器内部，而不是由 harness 编排。
- 不能扩大成：恢复机制在所有路径（含通用循环、其他 ES 后端）均已验证。

### C2 信息来源 — 判定：**有限支持（限定受测 handoff 路径）**

- 本轮证据：B2 九项差分全部成立；U2 的输入 sha256 与准入对象一致，且该对象由 bridge 从物理 IS 解析得到；两世界模板相同而输入不同，差异只能来自各自结算值。
- 相对 b 轮的变化：U2 输入由**执行器**构造，harness 的 IS 读取计数为 0/0。
- 不能扩大成：通用执行循环已经自主完成这条数据流；也不能扩大成“任何 IS 对象都能被正确消费”。

### C3 重算策略 — 判定：**路径差异仍成立（未统一）**

- 本轮证据：handoff B1 拒绝且 0 生成；同一缺失条件下，通用 `carrier_loop`（B1-loop）重算 `TASK-U1` 与 `TASK-U2`。
- 相对 b 轮的变化：无。carrier_loop 的重算语义**未被修改**。
- 不能扩大成：缺失结算必须统一拒绝，或应当统一重算。

### C4 来源真实性 — 判定：**边界仍独立存在（未被本轮修复）**

- 本轮证据：B3b 用摘要自洽的语义替身替换 U1 结算对象（`7f937107…`），准入**接受**，模型输出与替身值一致；标签 `SUBSTITUTED_VALUE_IS_DIGEST_VALID_BUT_NOT_LINEAGE_AUTHENTIC`。
- 结论：摘要有效性与对象身份一致，只能证明“对象字节未被篡改且自洽”，**不能证明该结果由所声明的 U1 计算产生**。
- 需要的新机制：执行溯源绑定（例如把生成进程、模型快照、prompt/token 序列与结算对象做不可伪造关联），而不是更换摘要算法。

---

## 7. `summary.json` 的 `admission_conditions` 修订说明

- 初版汇总函数对所有条件都要求 `tokenize_text_calls==0`，导致被准入的 B0-A/B0-B/B3b 被误判 `pass:false`。
- 修订方式：新增 `scripts/handoff_causality/derive_admission_conditions.py`，**只读取不可变 per-case evidence**（逐个记录 sha256），重新推导并写 `admission_conditions_v2.json`（`SIMIGO-CAUSALITY-PHASE2-ADMISSION-V2`，`all_pass=true`），再修订 `summary.json` 的该字段并追加 `summary_revisions`。
- 未重跑任何条件，未修改任何 per-case evidence。判定规则：拒绝组要求 `tokenize_text/seed/model` 全 0；准入组要求 1/1/1。
- 证据 sha256（v2 内 `evidence_provenance`）：B0-A `cebecfce…`、B0-B `d5b834c1…`、B1-harness `606cb6eb…`、B3a `d45a4420…`、B3b `c00180d4…`、B3c `3936631f…`。

---

## 8. 构建、测试与 guard

| 项 | 结果 | 证据 |
|---|---|---|
| `swift build` | 0 | `logs/swift-build.log` |
| 聚焦 Swift 测试 | 1 test / 0 failures | `logs/swift-test-admission.log` |
| Python 准入自测 | 4/4 PASS | `logs/admission-selftest.json`、`.stdout.json` |
| Phase 2 runner | `PHASE2_EXIT=0`，`terminal_state=OBSERVED` | `logs/phase2-runner.log`、`summary.json` |
| Phase 1 runner | `PHASE1_EXIT=0`，`all_observed_as_expected=true` | `logs/phase1-runner.log`、`phase1/summary.json` |
| workspace guard | `PASS`，8 文件，`issues=[]` | `manifests/workspace-after.json` |
| 源码差异 | 8 文件补丁 | `diffs/c-round-session.diff` |

---

## 9. 本轮未覆盖 / 下一轮需要的证据

1. **C4 执行谱系**：需要“结果 ↔ 生成执行”的绑定与验证机制，B3b 在本轮只能作为限制性测试。
2. **Phase 1 schema 不一致**：A0 未记录 `harness_read_settlement_calls` / `harness_read_item_calls`，下一轮应统一为 Phase 2 的字段，使“非中介”在 Phase 1 也有同构计数证据。
3. **通用循环未纳入生产准入**：本轮只改 handoff 路径；`carrier_loop` 仍按原语义重算（C3 的路径差异是刻意保留的）。
4. **ES 身份字符串复用**：执行状态 id 仍以字符串拼接（如 `phase2-B0-A-u2-<run>`）标识，不是内容寻址；这不影响本轮判定，但不能据此声称 ES 身份不可伪造。
5. **快照前的工作树编辑时刻**：见 §1.1，已用二进制哈希 + 运行后构建 no-op + 相对 HEAD 的补丁缓解，但不能回溯到具体时刻。

---

## 10. 结论边界（一句话版）

本轮证明了：在生产任务执行路径内部，任务项按自身依赖从物理 IS 取得已结算结果，经对象身份、字节摘要、依赖闭包与有效性准入后才构造模型输入；缺失、字节篡改与依赖不匹配都在任何 tokenize/生成之前被拒绝，且数据库与执行状态无副作用。C1 延伸至该路径，C2 仅在该路径获得有限支持，C3 的路径差异保持不变，C4 仍是独立的来源真实性边界。
