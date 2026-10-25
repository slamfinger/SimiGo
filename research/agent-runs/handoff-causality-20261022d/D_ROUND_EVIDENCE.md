# D 轮证据总账：普通任务入口的 IS 结算准入与双世界因果

- run root：`~/SimiGo-Agent-Runs/handoff-causality-20261022d`
- 运行标签：`handoff-causality-20261022d`
- 核心问题：不经过 `Causality.swift` 的专项编排，也不由入口预先读取/拼接 IS 结果，普通任务执行能否从 Information Space 恢复已结算依赖，并在准入通过后继续真实模型计算？
- 研究判定范围：C1–C4 分别判定，**不合并为单一总 PASS**；C4/B3b 不混入本轮 C2 验收
- 历史证据：`run-20261022a`、b 轮、c 轮目录未修改、未覆盖

---

## 1. 运行身份与证据边界

| 项 | 值 |
|---|---|
| HEAD | `e7f63856298390deb8596a4a30e173d3fb466eaa`（branch `main`） |
| 改动前快照 | `manifests/workspace-before.json`，`2026-10-22T03:22:58Z` |
| 快照覆盖 | 5,179 个文件；3,703 条被保护路径；staged diff 为空（`e3b0c442…`） |
| 改动后快照 | `manifests/workspace-after.json`，5,183 个文件；3,703 条保护路径 |
| 守卫校验 | `manifests/workspace-guard-verify.json`：`result=PASS`，`changed_file_count=10`，`issues=[]` |
| 本轮变更 | 10 个文件：6 修改、4 新增；没有保护路径或历史运行被改动（见 §2） |
| 入口二进制 | `SimiGoTaskRun`，sha256 `dcbfa536324a38483682895714f1c3d9249e46d88b9b4bf118b8768f95d5c5ec`，103,550,192 B |
| 构建一致性 | `logs/rebuild-check.log`：`swift build --product SimiGoTaskRun` 为 `Build complete! (0.53秒)`，**未重新链接**，二进制 sha256 仍为 `dcbfa536…` → 运行所用二进制与最终源码一致 |
| 模型 | `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`，`snapshot_revision=6e302ea6…`，`--max-tokens 64` |
| 源码差异 | `diffs/d-round-vs-pre-d.diff`（d 轮增量）、`diffs/worktree-vs-head.diff`（相对 HEAD 的工作树） |
| 变更清单 | `diffs/d-change-inventory.json`（逐文件前后 sha256、pre-d 重建方式） |
| 全量产物索引 | `MANIFEST_SHA256.txt`（本文件与索引自身之外的 run root 全量 sha256） |

### 1.1 pre-d 基线的重建与一条诚实边界

- c 轮 diff 锚定 HEAD `e7f63856`。用 `git worktree add --detach` + `c-round-session.diff` 重建 pre-d 工作树后，下列 4 个文件的 sha256 与 d 快照完全一致：bridge `45d89fab…`、integration `994c9015…`、tests `2789320a…`、Causality `99b2aa58…`。
- `Package.swift` 的 pre-d 内容由当前文件删除 `SimiGoTaskRun` product/target 块重建，sha256 `5a0e0c25…` 与快照一致。
- `Sources/RealModelHandoff/main.swift` 的 pre-d 文本不在 c 轮 diff 中，也不在会话记录中；快照只记录了 pre-d sha256 `272d9c3b…`。因此 `main.swift` 的 d 增量以 `hash_only` 记录，**不伪造文本差异**。路径独立性证据不依赖这条差异，而依赖新增入口 `SimiGoTaskRun` 的源码扫描与 integration/bridge 的可重建差异。
- 工作树自 HEAD 起一直未提交；本轮会话增量由 before/after 快照与 10 文件 inventory 精确覆盖，相对 HEAD 的更大增量由 `diffs/worktree-vs-head.diff` 保存。

---

## 2. 普通任务入口的接入方式（不是新增适配框架）

### 2.1 `continueTask` 自身完成准入

`simigo2-experimental/Sources/SimiGo2Experimental/ProductionRuntimeInformationIntegration.swift`（sha256 `994c9015…` → `de1c2b38…`）

- `continueTask` 不再接收调用方传入的 `nextInputText`；函数体第一行是 `resolveTaskInput(database:taskItemID:evaluatedAtUTC:)`，准入先于任何新副作用。
- 模型只 tokenize `admission.inputText`；`modelValue` 闭包改为 `(produced, admission)`，结算值构造与“被校验的对象身份”使用同一份准入数据。
- 返回值改为 `ProductionTaskInformationContinuation`（handle + report + admission），调用方可直接记录本次准入证据。
- **删除** `continueTaskFromInformationSpace`：不再存在“先在专项方法里准入、再转调普通方法”的第二条路径。

`simigo2-experimental/Sources/RealModelHandoff/Causality.swift`（`99b2aa58…` → `160c070b…`）

- Phase 1 A0 与 Phase 2 均改调 `continueTask`；handoff 不再拥有独立的准入包装层。

`execution-information-loop/production_runtime_bridge.py`（`45d89fab…` → `269f1088…`）

- 任务项可声明 `next_input_template` + `input_bindings`，也可在没有依赖时声明字面量 `next_input`；两者都来自 IS 中的任务定义，调用方不提供输入。
- 缺少模型输入模板时仍以 `TEMPLATE_MISSING` 拒绝；`input_bindings` 缺省为空列表，类型错误以 `BINDINGS_MALFORMED` 拒绝。

### 2.2 新入口 `SimiGoTaskRun`：只命名任务，不携带答案

`simigo2-experimental/Sources/SimiGoTaskRun/main.swift`（394 行，sha256 `fd583247…`）与 `TaskResultContract.swift`（90 行，sha256 `1bf89ac5…`），在 `Package.swift` 中作为独立 executableTarget 注册（依赖 `SimiGo2Experimental`、`SimiGoRuntimeContract`、MLX 系列，**不链接 `RealModelHandoff`**）。

- CLI 只接收：数据库、item id、demand id、advancement id、evaluated-at、模型目录、lab root、state 目录、输出路径、max-tokens。**没有** settlement 值、输入文本、模板或 nonce 参数。
- 入口只读任务项自身的 `source_payload`：`prompt_seed`（可选）与 `result_contract`（字段名 + 正则）。不读 settlement，不做模板插值，不读环境变量。
- `result_contract` 无声明时，结算原始生成文本与 token ids；有声明时按 item 自带正则提取字段，并把 `admitted_input_sha256`、`admitted_dependency_settlement_object_ids` 一并写入结算值。
- 拒绝路径输出 `INPUT_ADMISSION_REFUSED` 并以退出码 1 结束；成功路径输出 `TASK_SETTLED`。

结构上不存在旁路：入口的入参中没有任何可承载 nonce 或结算值的字段；输入只能由 `resolveTaskInput` 从数据库解析。

---

## 3. 实际执行证据：双世界端到端因果

两个世界使用**新的独立 nonce**，各自在独立目录中由 `SimiGoTaskRun` 依次执行 U1、U2；runner 只写 `--run-root`。

| 项 | world-a | world-b |
|---|---|---|
| U1 terminal | `TASK_SETTLED` | `TASK_SETTLED` |
| U1 准入 sha / 长度 | `fd236bc5…` / 369 B | `3b8fe2b4…` / 369 B |
| U1 结算对象 | `97485cca2351163967493a4d276662c14b4c247660a31af6b291e5ccd29cf4ba` | `31eb5588ea0df7b76132912ca85a7f46f37979e174a04d2a0b06115a5adc3c6d` |
| U2 声明依赖 | `TASK-SOURCE`, `TASK-U1` | `TASK-SOURCE`, `TASK-U1` |
| U2 绑定 secret / checksum | `fb0e0c4267832164` / `3a13` | `336f6d3a6001152d` / `0544` |
| U2 输入 sha / 长度 | `9bbd0ec0…` / 176 B | `6733a096…` / 176 B |
| U2 结算动作 | SOURCE `REUSE`、U1 `REUSE`、U2 `COMPUTE` | SOURCE `REUSE`、U1 `REUSE`、U2 `COMPUTE` |
| U2 结算对象 | `8a2ecc92…` | `7f639d74…` |
| U2 输出（契约捕获） | `ANSWER=fb0e0c4267832164-3a13` | `ANSWER=336f6d3a6001152d-0544` |
| 生成前计数 text/seed/model | 1 / 1 / 1 | 1 / 1 / 1 |
| positive checks | **24 / 24 true** | **24 / 24 true** |

- 每个世界的 U2 输入 sha256 与 `input_admission.input_sha256` 相同；binding 的 `settlement_object_id` 等于 `dependency_settlement_object_ids` 中对应项；U2 结算值的 `admitted_input_sha256` 与 `admitted_dependency_settlement_object_ids` 同准入对象一致。
- U1 自身也是普通入口执行：SOURCE `REUSE` + U1 `COMPUTE`，U1 结算对象随后被 U2 `REUSE`。
- 成功续跑会按设计写入 U2 结算与执行状态，因此两世界的 `database_unchanged=false`、`state_unchanged=false`；这不是副作用违规，而是成功结算的正常记录。

### 3.1 B2 双世界差分（`summary.json.b2` + `phase2/B2-world-comparison.json`）

7 项 checks 全为 true：`u2_templates_identical`、`cold_seeds_identical`、`u1_settlements_differ`、`u2_inputs_differ`、`outputs_differ`、`each_output_matches_its_own_world`、`world_pair_distinguished`。

两世界模板与冷种子相同；U2 输入的差异只能来自各自 IS 中的 U1/SOURCE 结算对象，且各自输出只匹配本世界结算值。

### 3.2 B4 nonce 交叉污染审计（`logs/nonce-surface-audit.json`）

两世界均 `verdict=CLEAN`、`cross_contaminated=false`。U2 输入面全部无 nonce：argv、环境、`state/u2`、`evidence/u2.json`、`logs/u2.log`、另一世界的数据库/状态/证据/日志、`worlds/attempts`。

同世界 U1 evidence 与主数据库中被允许出现 nonce（`source_payload_log_text`、`source_registration_value`、`u1_model_input_and_state`、`u1_settlement_result`），作为 U1 的输出记录显式列入 allowlist；`same_world_u1_evidence_contains_nonce=true` 是**预期**，不被当作 U2 输入通道。

### 3.3 D4 路径独立性（`summary.json.path_independence`）

5 项 checks 全为 true：

- `entry_source_has_no_settlement_read`
- `entry_source_has_no_template_interpolation`
- `entry_source_reads_no_environment`
- `entry_target_does_not_link_handoff`
- `only_the_ordinary_entry_was_invoked`（`handoff_binary_invoked=false`）

源码 forbidden tokens 全部为 false：`readSettlement(`、`next_input_template`、`input_bindings`、`replacingOccurrences`、`ProcessInfo.processInfo.environment`、`RealModelHandoff`。`Package.swift` 的 `SimiGoTaskRun` target 块不依赖 `RealModelHandoff`，runner 记录的实际进程 argv 只包含 `SimiGoTaskRun`。

---

## 4. 负对照：生成前拒绝回归

三组条件均在**独立数据库副本**上执行，入口进程退出码 1，terminal 为 `INPUT_ADMISSION_REFUSED`。

| 条件 | 干预 | 拒绝 stage | reason | text/seed/model 计数 | DB / state 不变 |
|---|---|---|---|---|---|
| B1-missing | 删除 TASK-U1 的 settlement | `SETTLEMENT_NOT_ADMITTED` | `MISSING_OR_SUPERSEDED_SETTLEMENT` | 0 / 0 / 0 | true / true |
| B2-tampered | 翻转 TASK-U1 结算对象字节（声明 id 仍为原值） | `SETTLEMENT_OBJECT_UNREADABLE` | `ObjectByteMismatch: 97485cca…` | 0 / 0 / 0 | true / true |
| B3-dependency | 改写 TASK-U2 的依赖声明，移除 TASK-U1 | `INPUT_BINDING_DEPENDENCY_NOT_DECLARED` | `placeholder {secret} requires TASK-U1, which the current task item no longer declares` | 0 / 0 / 0 | true / true |

每组 9 项 checks 全 true：`admission_status_refused`、`refused_before_generation`、`generation_not_entered`、`tokenize_text_zero`、`tokenize_seed_zero`、`generation_zero`、`stage_matches`、`database_unchanged`、`state_unchanged`。

自动化补充（不加载模型）：

- `execution-information-loop/admission_selftest.py` → `logs/admission-selftest.json` / `.log`：happy / missing-settlement / tampered-object-bytes / dependency-mismatch **4/4 PASS**（拒绝组断言结构化 refusal、DB 字节不变、无新文件）。
- `Tests/SimiGo2ExperimentalTests/ProductionInputAdmissionTests.swift`（重命名为 `testOrdinaryTaskEntryRefusesInadmissibleSettlementBeforeGeneration`，直接调用 `continueTask`）→ `logs/swift-test-admission.log`：1 test / 0 failures，内部断言 tokenize/generation/modelValue 全 0、DB 字节与 state identity 不变。
- 无模型 preflight → `logs/preflight/preflight.json`：`u1_admitted=true`、`u1_bound_to_source=true`、`u2_refused_before_u1_settlement=true`，verdict PASS。

---

## 5. 作废运行与重试披露

`logs/void-run-20261022T033632Z`：首轮。世界内 `files_contain()` 对单文件使用 `rglob` 导致 B4 误报、D4 目标块解析失败；world-b U2 模型输出缺少 `ANSWER=` 前缀，契约拒绝。整轮作废，未进入本总账的判定。

`logs/void-run-20261022T033808Z`：第二轮。world-a U1 模型复制 secret 出错，bridge 在结算时以摘要不符 fail-closed（`TASK_FAILED`），整轮作废。

最终运行：每世界 1 次尝试（`summary.json.worlds.*.attempts` 记录 attempt=1、`TASK_SETTLED`），未使用历史尝试目录。runner 的重试策略仅对 U1 `TASK_FAILED` 生效（重建世界 + 新 nonce，最多 3 次）；`INPUT_ADMISSION_REFUSED` 永不重试，负对照结果不会因重试被稀释。

---

## 6. C1–C4 增量判定（逐项独立）

### C1 恢复准入 — 判定：**保留，并由普通入口的生成前拒绝补强**

- 普通入口 `continueTask` 在真实运行中先准入、后生成：两世界 U1/U2 均 `ADMITTED`，输入 sha256 与准入对象一致，生成计数恰为 1。
- 缺失、字节篡改、依赖不匹配在普通入口的 tokenize 与模型生成之前被拒绝，计数全 0，DB/state 无副作用。
- 相对 c 轮：拒绝不再依赖 handoff 或专项准入包装层；`continueTaskFromInformationSpace` 已删除。

### C2 信息来源 — 判定：**在普通任务入口（生产 `continueTask`）获得因果支持，但仍限定于被测生产路径**

- 两世界模板相同、冷种子相同，U1 结算对象不同 → U2 输入 sha 不同 → 输出不同且各自匹配；binding 与依赖对象 ID 可逐项对应。
- 入口不读 settlement、不插值模板；U2 输入只能由 `resolveTaskInput` 从物理 IS 解析。
- 不能扩大成：整个 SimiGo 普通执行流程均已具备同等保证；也不能扩大成：任意任务定义、任意 ES 后端或通用 `carrier_loop` 已通过。

### C3 重算策略 — 判定：**语义未改变，路径差异仍保留**

- `carrier_loop.py` 未被 d 轮修改（不在 10 文件变更清单内），未实现全局 no-recompute。
- D 轮只验证生产准入路径上的拒绝与放行，不主张通用循环应采用同一策略。

### C4 来源真实性 — 判定：**保留为独立限制，不冒充已解决**

- D 轮未重跑 B3b，未把它混入 C2 验收；摘要自洽的语义替身仍可能通过“字节可读 + 摘要匹配”的准入。
- 本轮新增的“结算值携带 admitted 输入身份”只增强了输入与结算的对应记录，不构成执行谱系真实性证明。

---

## 7. 未覆盖与必须保留的边界

1. **结论范围**：仅覆盖被测生产运行路径（`continueTask` + `SimiGoTaskRun` + 本 fixture 的任务定义），不自动推广到整个 SimiGo 执行流程。
2. **C4/B3b**：仍需要“结果 ↔ 生成执行”的不可伪造绑定；D 轮未提供。
3. **通用循环**：`carrier_loop` 的重算语义未改，也未纳入生产准入。
4. **单一模型与单一后端**：只使用一个 MLX 4bit 快照、debug 构建、单一 ES 后端；跨模型、跨后端、release 构建未验证。
5. **nonce 的允许面**：同世界 U1 evidence 与主数据库必然包含 nonce；B4 只证明它未进入 U2 的输入面或其他世界。
6. **main.swift 文本差异缺口**：见 §1.1；以 hash、入口源码扫描与可重建差异替代，不声称已获得逐行 pre-d 文本。
7. **成功运行的写入**：成功 U2 会新增结算与执行状态，`database_unchanged=false` 属预期；只有拒绝组要求零副作用。

---

## 8. 结论边界（一句话版）

D 轮证明了：在普通任务执行入口 `SimiGoTaskRun` 调用生产 `continueTask` 时，任务项按自身声明的依赖从物理 IS 取得已结算结果，经对象身份、字节摘要、依赖闭包与有效性准入后才 tokenize 并进入真实模型生成；两个独立结算分别驱动各自的下游输入与输出；缺失、篡改与依赖不匹配都在生成前被拒绝且无副作用；`Causality.swift` 不再拥有专项准入路径。C1 得到补强，C2 的因果支持从 handoff 扩展到普通入口但仍限定被测生产路径，C3 语义未变，C4 仍是独立限制。
