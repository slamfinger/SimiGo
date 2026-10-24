# E 轮：结算来源真实性（Settlement Provenance）结果

- 运行标识：`settlement-provenance-20261022e`
- 运行根：`/Users/mr.simi/SimiGo-Agent-Runs/settlement-provenance-20261022e`
- 前置快照 HEAD：`e7f63856298390deb8596a4a30e173d3fb466eaa`（branch `main`）
- 快照时间：`2026-10-22T04:00:39Z`（任何 E 轮源码修改之前）
- 最终状态：`summary.json` → `terminal_state = OBSERVED`
- 证据性质：真实 MLX 模型（Qwen3-Coder-30B-A3B-Instruct-4bit）双世界运行 + 8 组无模型篡改拒绝 + legacy advancement 覆盖 + 源码调用链审计

## 1. 结论摘要

E 轮把“结算记录里多存几个哈希”推进为：

1. 受信任生产路径在真实结算成功后，对一份**规范化签名声明**做 Ed25519 签名；
2. 新执行实例在 `continueTask` 内、tokenize 与生成之前，恢复结果时验证签名、来源、依赖闭包和有效性；
3. 没有签名、签名无效、依赖闭包不一致时，tokenize 与模型生成调用均为 0；
4. 无法验证的新增格式结算不会静默回退到未签名复用。策略 `off`（仅隔离库测试）不能验证签名结算，带 provenance 的结算在 `off` 下一律拒绝复用；`off` 生产者写出的结算保持 legacy 无 provenance 形态。

本轮达到 8/8 篡改条件 PASS、E0 有效签名 probe PASS、legacy 覆盖 PASS、覆盖审计 PASS、双世界可区分。

| 结论对象 | E 轮判定 | 证据边界 |
| --- | --- | --- |
| C1 恢复准入 | `PASS（受测普通入口 + legacy 路径）` | 既有准入能力保持；签名缺失/无效同样前置拒绝，三个计数器为 0 |
| C2 信息来源 | `PASS（受测双世界路径）` | 两世界模板与 cold seed 相同，U1 结算/签名不同，U2 输入与输出分别对应各自世界 |
| C3 重算策略 | `UNCHANGED` | 普通任务路径拒绝而不是重算；legacy 不可复用时仍按既有策略重算并重签 |
| C4 来源真实性 | `PASS（第一档信任边界）` | 受信任生产路径签署的结算可与“自洽重写但无有效签名”的替代区分；T3 明确排除 |

## 2. 运行身份与信任根

前置快照记录在 `manifests/pre-snapshot-meta.json`，包含 HEAD、分支、6 个受保护文件修改前摘要；`manifests/workspace-before.json` 记录 5183 个工作树文件。

`workspace_guard.py verify` 的最终结果为 `PASS`：HEAD 与分支未变，12 个变化文件全部在 E 轮允许清单内（11 个源码/测试 + 1 个本报告），无冻结路径变化。guard 对快照中已存在的证据文件保持冻结；本报告在快照时并不存在，属于新增文件，必须显式加入允许清单，不能借“新增”绕过对既有证据的保护。

信任根（数据库之外）：

| 项 | 值 |
| --- | --- |
| 算法 | Ed25519 |
| key id | `e-round-e7ba00a712248330` |
| 私钥文件 | `trust/settlement-signing-key.json`，mode `0600` |
| 信任锚 | `trust/settlement-trust-anchor.json`，mode `0444` |
| 信任锚 sha256 | `8aeaedde2a358165170c5e8f8147794a0ee37f994a6d77f7b9d6798133757402` |
| 攻击者锚（同 key id、不同公钥） | `trust/attacker-anchor.json`，sha256 `f3da34c739fcc59d38e5f0b14ac5aa9964e08e22ec38ea9ed3db7e53dd6e8a28` |
| 生产者/消费者 build 绑定 | `2ba3b17fe28da7d00e1069ae3d29ed03e79a2472f2cb3bb8402ec99caeefe461` |

生产进程使用 `SIMIGO_SETTLEMENT_PROVENANCE=required`，必须同时具备私钥与锚；消费进程使用 `verify`，只加载锚，不加载私钥。8 组篡改运行全部在没有 `SIMIGO_SETTLEMENT_SIGNING_KEY` 的消费环境中完成——它们没有因缺私钥而启动失败，而是在验签阶段被拒绝。这直接证明消费端不需要签名能力。子进程环境由 `run_phase_e.py` 的 `child_environment` 构造：E0 probe 第 1545 行、矩阵第 1593 行均为 `with_key=False, policy="verify"`。`trust-separation-audit.json` 进一步核对：私钥文件 mode `0600`、锚 mode `0444`、两者 key id 与公钥一致；扫描运行根内 17 个 SQLite（共 1,142,784 字节）未发现私钥材料（base64 / raw / hex 三种形式）。签名接口也不是通用签名器：`settlement_provenance.sign_declaration` 只有 `carrier_loop.settle()` 一个调用点，且位于 `build_declaration` 之后；bridge 不暴露 `sign` / `settle` 子命令，`SigningKey.load` 只出现在 `load_policy` 中。

## 3. 实现内容

### 3.1 规范化签名声明

签名对象是 detached Ed25519 签名，payload 至少绑定：

| 要求 | payload 字段 |
| --- | --- |
| 结算对象 ID、schema/version、任务项 ID | `settlement_object_id`、`settlement_schema_id`、`settlement_contract`、`item_id`、`advancement_id` |
| 结果值及规范化摘要 | `settlement_object_id` 是完整声明（含 `result` 与 `basis`）的规范化内容地址；`provenance.result_value_sha256` 是 `result.value` 的规范化摘要 |
| source 对象身份、摘要、版本 | `provenance.source.object_id`、`payload_sha256`、`version` |
| 完整依赖闭包 | `provenance.dependencies[item] = {object_id, result_value_sha256}` |
| validity basis、策略、时间 | `provenance.validity.{evaluated_at_utc, valid_until_utc, validity_policy_sha256}`；`basis` 由 `settlement_object_id` 覆盖 |
| 任务/执行实例/结算事件身份 | `provenance.task.{item_object_id, payload_sha256}`、`producer.{run_id, execution_id, process_id}`、`event.{settlement_event_id, sequence, previous_settlement_object_id}` |
| 算法、密钥 ID、签名值 | payload 内的 `algorithm`、`key_id`；detached envelope 内的 `signature_base64` |

结果值不是靠“多写一个字段”进入签名声明，而是靠内容地址：消费者必须同时验证 envelope 签名、`settlement_object_id` 等于数据库中结算对象的当前内容地址、`provenance.result_value_sha256` 等于 `digest(result.value)`。任一不一致，即使签名本身有效也不得复用。

`provenance` 还绑定 `model.{snapshot_revision, weights_manifest_sha256}` 与 `output.{generated_token_ids_sha256, generated_token_count}`，使“哪个模型、哪些 token 产生了这个结果”进入签名声明。

签名字段不写进结算对象本身，而是独立对象 `settlement-signature:<item>`；结算对象、结算索引、签名对象、签名索引在同一原子写入组中提交。签名 payload 绑定结算对象的内容地址，避免循环哈希。

两个身份必须分开报告，不能混用：`signature_object_id` 是 detached 签名对象的自身内容地址，`settlement_object_id` 是该签名覆盖的结算对象地址。消费端描述符同时返回两者；入口证据同时写入 `settlement_signature_object_id` 与 `signed_settlement_object_id`，并由 `signature-identity-audit.json` 从数据库重新推导核对。

### 3.2 生产端与消费端

- 生产端：`carrier_loop.settle()` 在 `provenance_policy="required"` 下签名；缺少私钥/锚时拒绝启动或拒绝结算。
- 消费端：`production_runtime_bridge.resolve_model_input` 以 `provenance_policy="verify"` 打开；`_resolve_settled_dependency` 复用与 `execute_demand` 相同的 `_settlement_reuse_decision`，先校验 basis，再校验签名、来源、依赖、validity、event chain。
- Swift 端：`SettlementProvenanceVerifier` 独立执行 Ed25519 验签，核对 canonical payload 字节、object/item/key/algorithm、task/source/dependencies/validity/event/producer，并要求每个声明依赖恰好一个签名。`continueTask` 还核对：签名信封声明的被签结算对象等于本次执行项 action 的结算对象，action 报告的签名对象等于信封自身身份；两者不一致即拒绝报告成功。
- 顺序：`continueTask` 第 1106 行调用 `resolveTaskInput`，第 1135 行才进行第一次 `tokenizeText`；`resolveTaskInput` 内第 1482 行从 bridge 取得签名描述符，第 1643 行执行 `SettlementProvenanceVerifier.verify`，而该函数体内没有任何 tokenize 或生成调用。`verification-path-audit.json` 将这条静态链路固化为可复核证据。

错误分层保持可解释：

- 只改结果值、不重算摘要：`SETTLEMENT_NOT_ADMITTED` / `SETTLEMENT_BASIS_MISMATCH`；
- 结果、摘要、basis、provenance、event 全部自洽重写但没有签名私钥：`SETTLEMENT_SIGNATURE_INVALID`；
- 删除签名：`SETTLEMENT_SIGNATURE_MISSING`；
- 任务项元数据改变导致 `task.payload_sha256` 不一致：`SETTLEMENT_PROVENANCE_MISMATCH`；
- 合法签名但依赖闭包属于另一世界：`SETTLEMENT_NOT_ADMITTED` / `SETTLEMENT_BASIS_MISMATCH`；
- 以 `off` 打开但遇到带 provenance 的结算：`SETTLEMENT_SIGNATURE_UNVERIFIABLE`，只能重算，不能复用。

`off` 分支的 fail-closed 硬化是在 E 双世界/矩阵/legacy 运行之后加入的：`settle` 在 `off` 下只写 legacy 无 provenance 结算，`_verify_signed_settlement` 在 `off` 下拒绝任何带 provenance 的结算。它只改变 `off` 路径；矩阵使用 `verify`，legacy 使用 `required`，因此不改变 E0/E1–E8/legacy 的结果。该分支由 `carrier_selftest.py` 47/47 与真实 world-a 副本的 `off-policy-refusal.json` 10/10 覆盖。

### 3.3 legacy advancement

`production_runtime_bridge.execute` 使用 `open_loop(require_provenance=True)`，随后进入同一个 `_settlement_reuse_decision`。不可复用时按既有 C3 策略重算并重新签名，而不是消费被篡改值；复用动作现在会报告实际验证通过的 `settlement_signature_object_id`。

## 4. 双世界因果证据

两个世界使用相同的 U2 模板与相同的 cold seed，但 U1 结算不同：

| 世界 | source checksum | U1 secret | U2 输入 sha256（前 16） | U2 输出 | U1 结算对象 / 签名对象 | U2 结算对象 / 签名对象 |
| --- | --- | --- | --- | --- | --- | --- |
| world-a | `dae3` | `2ae9cc0529188dbb` | `3d03c4d0fdb3b6e0` | `ANSWER=2ae9cc0529188dbb-dae3` | `c81903413cdf…` / `4851da6d6c3b…` | `5ceac08e735b…` / `c339de12c1ef…` |
| world-b | `e7e5` | `9aae4aec613dd160` | `40b4e380752aa715` | `ANSWER=9aae4aec613dd160-e7e5` | `b71e8cb670ad…` / `65c1c23ef197…` | `c6ecc7f7f3d8…` / `f45b209be3b2…` |

`world-comparison.json` 的结果：

- `u2_templates_identical = true`
- `cold_seeds_identical = true`
- `u1_settlements_differ = true`、`u1_signatures_differ = true`
- `u2_inputs_differ = true`、`outputs_differ = true`
- `each_output_matches_its_own_world = true`

`nonce-surface-audit.json` 对每个世界检查另一世界的 nonce 是否出现在本世界的 argv、环境、文件、状态目录中；两个方向均无交叉污染。

E0 无模型 probe 在未修改的签名世界上通过全部 10 项检查：`ADMITTED`、所有 admission checks 为真、每个依赖一个签名、计数器全 0、`model_loaded=false`、数据库与状态目录未变。

## 5. 篡改矩阵

每组都在 world-a 的 base 快照副本上做单点变异；消费环境只有公钥锚，没有私钥。

| 条件 | 变异 | 实际拒绝阶段 / 原因 | 拒绝项 | tokenize(text/seed) | generate | generation_entered | DB / state |
| --- | --- | --- | --- | --- | --- | --- | --- |
| E1 result-value-only | 只改结果值 | `SETTLEMENT_NOT_ADMITTED` / `SETTLEMENT_BASIS_MISMATCH` | TASK-U1 | 0 / 0 | 0 | false | 未变 / 未变 |
| E2 result-and-digests | 结果+摘要+basis+provenance+event 自洽重写 | `SETTLEMENT_SIGNATURE_INVALID` | TASK-U1 | 0 / 0 | 0 | false | 未变 / 未变 |
| E3 producer-field | 改写 producer 字段 | `SETTLEMENT_SIGNATURE_INVALID` | TASK-U1 | 0 / 0 | 0 | false | 未变 / 未变 |
| E4 task-item-metadata | 改任务项 `source_kind` | `SETTLEMENT_PROVENANCE_MISMATCH` | TASK-U1 | 0 / 0 | 0 | false | 未变 / 未变 |
| E5 dependency-substitution | 用 world-b 的合法签名 source 结算替换 | `SETTLEMENT_NOT_ADMITTED` / `SETTLEMENT_BASIS_MISMATCH` | TASK-U1 | 0 / 0 | 0 | false | 未变 / 未变 |
| E6 signature-removed | 自洽重写并删除 U1 签名 | `SETTLEMENT_SIGNATURE_MISSING` | TASK-U1 | 0 / 0 | 0 | false | 未变 / 未变 |
| E7 anchor-swapped | 换成攻击者锚（同 key id、不同公钥） | `SETTLEMENT_SIGNATURE_INVALID` | TASK-SOURCE | 0 / 0 | 0 | false | 未变 / 未变 |
| E8 foreign-signed-replay | 复制 world-b 的 U1 签名结算 | `SETTLEMENT_NOT_ADMITTED` / `SETTLEMENT_BASIS_MISMATCH` | TASK-U1 | 0 / 0 | 0 | false | 未变 / 未变 |

观察项（不作为通过条件）：真实入口在进入 `continueTask` 前加载模型容器（本轮 2.34–2.61 秒），因此 `model_loaded_before_refusal=true`。本轮保证的是 **tokenize 与生成调用为 0**，不是“权重加载前拒绝”。E0 probe 走独立的 admission 分支，不加载模型。

E2 与 E6 是 C4 的核心对照：攻击者可以在没有私钥的情况下把所有内容摘要和事件链重写成语义自洽的替代结算，但无法生成与信任锚匹配的有效签名。系统不是靠“再算一次摘要”来判定真实性。

## 6. legacy advancement 覆盖

`phase3-legacy` 在隔离 PALACE carrier 上执行四次 advancement，并在每次 `execute` 后调用 `confirm-runtime-application`（模拟 Swift runtime 的完成步骤）：

1. `legacy-1`：全部 9 个 item COMPUTE，全部带签名。
2. `legacy-2`：全部 REUSE；每个复用动作报告签名对象，且该签名用独立 Ed25519 验签通过。
3. 篡改副本：对 `REAL-1` 做自洽重写（`payload_digest=0*64`），删除 `REAL-2` 的签名。
4. `legacy-3`：`REAL-1` COMPUTE + `SETTLEMENT_SIGNATURE_INVALID`，`REAL-2` COMPUTE + `SETTLEMENT_SIGNATURE_MISSING`；其余 7 个 REUSE。被篡改的 `REAL-1` 值没有被消费；重算后的结算重新签名。
5. `legacy-4`：全部 REUSE，且所有签名独立验签通过。

因此 legacy task advancement 没有绕开同一套结算验证；同时 C3 的重算策略未被改变。

## 7. 构建、测试与静态审计

| 检查 | 结果 | 原始日志 |
| --- | --- | --- |
| `swift build --product SimiGoTaskRun` | exit 0 | `logs/swift-build-product.log` |
| `swift build --build-tests` | exit 0 | `logs/swift-build-tests.log` |
| `swift test --filter ProductionInputAdmissionTests` | 1 test passed，0 failures | `logs/swift-test-admission.log` |
| `carrier_selftest.py` | `result = PASS`，47/47 项 | `logs/carrier-selftest.log` |
| `admission_selftest.py --out …` | `verdict = PASS` | `logs/admission-selftest.json` |
| `signature-identity-audit.py` | `verdict = PASS`，6/6 项（2 世界 × 3 item） | `logs/signature-identity-audit.json` |
| `verification-path-audit.py` | `verdict = PASS`，9/9 项 | `logs/verification-path-audit.json` |
| `entry-coverage-audit.py` | `verdict = PASS`，15/15 项 | `logs/entry-coverage-audit.json` |
| `trust-separation-audit.py` | `verdict = PASS`，15/15 项；17 个数据库无密钥材料，签名接口单入口 | `logs/trust-separation-audit.json` |
| `probe_off_policy.py` | `verdict = PASS`，10/10 项；真实 world-a 副本上 off 拒绝签名复用、verify 正常复用 | `logs/off-policy-refusal.json` |
| `workspace_guard.py verify` | `PASS`，12 个允许变化，无冻结路径变化 | `logs/workspace-guard-verify.json` |

`coverage-audit.json` 的源码证据：

- `continueTask` 定义在第 1094 行；`resolveTaskInput` 调用在第 1106 行；第一次 `tokenizeText` 在第 1135 行；函数体 381 行。
- `resolveTaskInput` 定义在第 1475 行；bridge 返回签名描述符在第 1482 行；Ed25519 验签在第 1643 行；函数体内无 tokenize、无生成。
- bridge 消费端 `provenance_policy="verify"` 在第 885 行。
- bridge 生产端 `provenance_policy="required"` 在第 109、1170、1219 行。
- legacy `execute` 的 `require_provenance=True` 在第 225 行。
- 所有 `.continueTask(` 调用点（`SimiGoTaskRun`、`RealModelHandoff/main.swift`、`RealModelHandoff/Causality.swift`）都传入 `provenance:`，没有遗留未覆盖调用点。

覆盖的生产任务入口（`entry-coverage-audit.json` 从 `Sources/` 重新推导，构造 `ProductionRuntimeInformationIntegration` 的源码入口恰好是这 3 个）：

| 入口 | 准入链路 | 本轮动态执行 |
| --- | --- | --- |
| `SimiGoTaskRun` | `continueTask → resolveTaskInput → bridge resolve-model-input (verify) → Swift Ed25519 verify` | 是：双世界 + E0 probe + E1–E8 |
| `RealModelHandoff` | 同一 `continueTask` 准入；handoff 只选择 item | 否：静态调用链覆盖（5 个调用点均传 `provenance:`） |
| `ActualMLXSmokeChild`（legacy） | `continueWithRealInformation`（定义 794，`runBridge("execute")` 在 829）→ bridge `execute`（`open_loop(require_provenance=True)` 在 225）→ `execute_demand` → `_settlement_reuse_decision`（1414）→ `_verify_signed_settlement` | 部分是：bridge `execute` 由 `phase3-legacy` 动态执行；Swift 包装器本身未运行 |

`continueWithRealInformation` 不是非任务型直接推理，而是任务推进 API：它唯一的 `Sources/` 调用点在 `ActualMLXSmokeChild/main.swift` 第 120 行。它在第 829 行先执行 bridge `execute` 准入，第 892 行才第一次 `tokenizeText`；bridge 的 `open_loop` 显式传入 `require_provenance=True`，`load_policy` 优先采用显式策略而非环境默认值，因此不会因缺少环境变量静默降级为 `off`。

明确的非任务直接推理排除项（记录调用位置与理由，不强行改造成 IS 任务）：

| 入口 | 调用位置 | 排除理由 |
| --- | --- | --- |
| `SimiGo2App.send / sendSmallScale / self-test` | `engine.generate(` 第 347/643/648 行 | 交互式 chat/benchmark，直接消费用户文本，不命名 task item，不构造 IS 集成，不读取结算 |
| `MLXGroupResidencyBenchmark / MLXGroupInferenceGate` | `ChatTemplateGeneration.generate(` | 测量/residency 探针，无任务身份与结算 |
| `GroupExecutionTraceProbe / MeasuredExecutionTracePilot` | `ChatTemplateGeneration.generate(` | instrumentation-only trace，无任务身份与 IS 准入 |
| `G3SwiftIsolationEntry` | 注入的 `generate:` 闭包 | 隔离/取消门测试，不做任务推进 |

`entry-coverage-audit.json` 逐一核对这些文件：不含 `ProductionRuntimeInformationIntegration`、`continueTask`、`continueWithRealInformation`，同时存在直接生成证据（`SimiGo2App` 347/643/648、`MLXGroupResidencyBenchmark` 88/102/150/209、`GroupExecutionTraceProbe` 349、`MeasuredExecutionTracePilot` 245、`G3SwiftIsolationEntry` 70）。

## 8. C1–C4 判定与边界

### C1 恢复准入

`PASS（受测入口）`。`continueTask` 保持既有 `resolveTaskInput` 准入；新增签名验证失败时同样在生成前拒绝。8 组拒绝的 `tokenize_text_calls`、`tokenize_seed_calls`、`model_continuation_calls` 全部为 0，`generation_entered=false`，数据库与状态目录摘要未变。

### C2 信息来源

`PASS（受测双世界路径）`。两个独立世界使用相同模板和相同 cold seed，得到不同 U1 结算、不同 U2 输入和不同输出；消费的 `TASK-U1` / `TASK-SOURCE` 对象 ID 与 admission 中验签的结算对象完全一致。`SimiGoTaskRun` 不读取 handoff 专项编排、不展开模板、不通过 argv/环境/侧文件接收输入。`signature-identity-audit.json` 进一步从数据库重建每个 item 的“签名对象 / 被签结算对象”对，并核对 admission descriptor、action 与入口报告三者一致。

### C3 重算策略

`UNCHANGED`。普通任务路径在准入失败时拒绝，不进入计算；legacy 路径保持既有语义：不可复用时由受信任 calculator 重算并重新签名，记录 `SETTLEMENT_SIGNATURE_INVALID` / `SETTLEMENT_SIGNATURE_MISSING`。本轮没有为了 C4 改变重算策略。

### C4 来源真实性

`PASS（第一档信任边界）`。受信任生产路径签署的结算，与“自洽重写但没有有效签名”“替换为另一世界的合法签名结算”“换锚”能够可靠区分。密钥不存在于数据库；锚点在数据库之外且只读；消费端不加载私钥。`signature-identity-audit.json` 对 2 个世界的 `TASK-SOURCE`、`TASK-U1`、`TASK-U2` 共 6 个对象独立验签，并证明签名对象 ID 与被签结算对象 ID 是两个不同内容地址，入口报告与数据库重建结果逐项一致。`trust-separation-audit.json` 把“密钥/锚分离、数据库不含私钥材料、消费进程不传私钥”变成可复核检查。`off-policy-refusal.json` 在真实 world-a 副本上验证剩余的 `off` 分支：`_settlement_reuse_decision` 对 `TASK-SOURCE` 与 `TASK-U1` 都返回 `SETTLEMENT_SIGNATURE_UNVERIFIABLE`；`execute_demand` 把两者都判为 COMPUTE，`reused_item_ids=[]`，计算器覆盖依赖闭包；off 重算后的副本重新以 verify 打开仍被拒绝（`SETTLEMENT_SIGNATURE_MISSING`）；原始签名世界的另一副本以 verify 打开则正常 REUSE。原 world-a 数据库字节未变。

信任边界：

- 在范围内：意外损坏、局部非自洽篡改、无法读取签名私钥或突破受保护锚点的整库改写。
- 明确排除 T3：攻击者同时控制数据库、签名私钥和信任锚。
- 签名只证明受信任生产路径对该结算声明进行了签署，不证明模型答案在语义上正确。
- 保护假设：私钥与锚点的隔离依赖运行账户与文件系统权限（`0600` / `0444`）以及密钥文件不在数据库内；不声称在此之上防御能读取密钥文件、提权改写锚点或同时控制三者的攻击者（T3）。
- 不声称对“来自另一数据库实例的完整、合法签名历史”的谱系防护；E8 只覆盖“复制另一世界的 U1 结算”这一具体闭包不一致情形。
- 不声称覆盖仓库内所有推理调用；只覆盖第 7 节列出的生产任务入口，非任务入口逐项记录排除理由。
- `off` 不是验证模式，也不能作为“未签名复用”的后门：带 provenance 的结算在 `off` 下一律拒绝（`SETTLEMENT_SIGNATURE_UNVERIFIABLE`）；`off` 生产者只写 legacy 无 provenance 结算。
- 动态证据的范围：`SimiGoTaskRun` 的 `continueTask` 与 bridge 的 `execute` 被真实运行或篡改矩阵执行；`RealModelHandoff` 与 `ActualMLXSmokeChild` 的 Swift 包装器本轮只有静态调用链证据，不声称它们已被动态验证。

## 9. 复现

```sh
# 1. 构建
cd simigo2-experimental
swift build --product SimiGoTaskRun
swift build --build-tests
swift test --filter ProductionInputAdmissionTests

# 2. E 轮真实运行（会创建新的 run root）
python3 simigo2-experimental/scripts/ordinary_task/run_phase_e.py \
  --run-root <new-run-root> \
  --lab-root /Users/mr.simi/Documents/SimiGo-Lab \
  --model-dir <Qwen3-Coder-30B-A3B-Instruct-4bit snapshot> \
  --max-tokens 64

# 3. 工作树边界
python3 <run-root>/tools/workspace_guard.py verify \
  --repo /Users/mr.simi/Documents/SimiGo-Lab \
  --before <run-root>/manifests/workspace-before.json \
  --out <run-root>/logs/workspace-guard-verify.json \
  --allow-change '<E 轮允许的源码/测试/报告 glob>'

# 4. 签名对象身份独立审计（只读）
python3 <run-root>/tools/audit_signature_identity.py

# 5. 验签位于生成前路径的静态审计
python3 <run-root>/tools/audit_verification_path.py

# 6. 生产入口覆盖审计（只读；含 continueWithRealInformation）
python3 <run-root>/tools/audit_entry_coverage.py

# 7. 密钥/锚分离与数据库无密钥材料审计（只读）
python3 <run-root>/tools/audit_trust_separation.py

# 8. off 策略探针（只读原数据库，变更只发生在临时副本）
python3 <run-root>/tools/probe_off_policy.py

# 9. 产物清单与复核（verify 记录不进入清单，避免自指）
python3 <run-root>/tools/make_manifest.py
python3 <run-root>/tools/verify_manifest.py
```

运行器拒绝覆盖非空 `worlds/`、`phase2/`、`phase3-legacy/`；失败尝试会归档到 `worlds/attempts/` 或 `previous-attempts/`，不会覆盖既有轮次产物。

## 10. 产物索引

运行根：

- `summary.json`：终端状态、双世界、矩阵、legacy、coverage、claims
- `phase2/conditions.json`：篡改矩阵逐项证据
- `phase2/world-comparison.json`：双世界对比
- `phase2/E*/evidence/u2.json`：每个拒绝条件的原始入口证据
- `phase3-legacy/`：legacy 数据库、四次 execute 与 confirm 日志
- `logs/coverage-audit.json`、`logs/workspace-guard-verify.json`、`logs/signature-identity-audit.json`、`logs/verification-path-audit.json`、`logs/entry-coverage-audit.json`、`logs/trust-separation-audit.json`、`logs/off-policy-refusal.json`、`logs/manifest-verify.json`
- `logs/*.log`：构建、测试、selftest 原始日志
- `diffs/`：`tracked-changes.diff`（git 跟踪文件）、`new-files.diff`（快照中不存在的 3 个新文件）、`untracked-current/`（快照前已存在但 git 未跟踪的 5 个文件的当前全文；其改前摘要只存在于快照，无法逐字节重建 diff，`diffs/README.md` 说明这一限制）
- `manifests/MANIFEST_SHA256.txt`：运行根产物摘要清单（不含 `previous-attempts/`、清单自身与 `logs/manifest-verify.json`）；`verify_manifest.py` 逐项核对摘要、大小、guarded 路径，并检测清单之外的新增文件
- `tools/`：guard、签名身份审计、验签路径审计、入口覆盖审计、密钥/锚分离审计、off 策略探针、差异 README 生成器、清单生成与复核脚本；均为只读审计或本地产物写入
- `previous-attempts/`：开发过程中的失败/中间尝试，保留但不作为最终证据

最终证据是 identity 修正后的最新运行（当前运行根）。`previous-attempts/attempt-0` 到 `attempt-3` 以及 `attempt-4-pre-identity-fix` 仅用于诊断，不参与 C1–C4 判定。E0/E1–E8/legacy 在该运行上执行；随后加入的 `off` fail-closed 硬化只影响 `off` 路径，并由第 7 节的两项独立证据覆盖，不重写矩阵原始产物。
