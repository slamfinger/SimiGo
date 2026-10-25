# SimiGo v2.2.0rc1 — 逐层 `forward_calls` 门批次 (simigo-v2.2.0rc1-layer-forward-calls-20261024)

本批次只推进一件事：把 `per_layer_forward_calls` 从"没有插桩、没有数字"推进到
"有真实插桩、数字可溯源到文件、且观测本身不改变模型行为"。

它**不**关闭 GUI，**不**修改 Service/HTTP 的代码，也**不**改动物理页归还的台账结论——
但它换了二进制，所以既有门都不能沿用上一候选的结果：Service/HTTP 五场景门在
新候选上**原样重跑**（第 8 节），物理页归还也按**同一套预注册规则**重跑（第 9 节，
结果是 BLOCKED）。最后，它**不**修改验收台账 `acceptance_report.json`。

---

## 1. 结论先行

| 事项 | 本批次结果 | 依据 |
| --- | --- | --- |
| 逐层 forward 计数（新安装候选 `95224f06…`） | **有插桩、有数字**：48 层，每层每 pass 恰好 1 次，L1–L9 全真，`estimated_values=0` | `evidence/layer_forward_calls_verdict.json` |
| 门原文"产品里没有逐层计数插桩" | **不准确，必须更正**：插桩一直在运行时包里，缺的是驱动方 | `evidence/instrumentation_inventory.json` |
| 本批次源码 delta | **2 个文件**：App 源 `+112/−1`，测试 `+18/−0` | `evidence/patch_attribution.json` |
| 新安装候选身份 | exe `95224f06…`、bundle 树 `8a3fb751…`、`installed_equals_built=true` | `evidence/install_identity_new_candidate.json` |
| 受影响测试 | **PASS** 210 executed / 14 skipped / 0 failures；真实用户状态写入 0 | `run_isolated_lf2/isolation_run_lf2.json`（lf2）、`run_isolated_lf3/isolation_run_lf3.json`（v5 构建上重跑，同数） |
| Service/HTTP（新候选重跑） | **PASS**：五场景全过，200 / 401 / 401 / 503；非法 proof 生成 0；Keychain 2035→2035 | `evidence/gate_installed_g2/service_http_gate_verdict.json` |
| Service/HTTP 门面覆盖（本轮增量，v5 构建） | **PASS**：serving leg 由 `Service.shared.start(path:)` 起监听；门面自己的 `[NODE] backend=`/`[READY] ` 出现在服务了 HTTP 200 的那次运行里；真实 defaults 域六个摘要前后完全一致 | `evidence/gate_v5_facade/service_http_gate_installed.json`、`evidence/gate_v5/service_http_gate_verdict.json` |
| 本轮新构建身份（v5） | exe `83a88048…`、bundle 树 `aacb6b4a…`、`installed_equals_built=true`；源码 +66 行（1 个文件） | `evidence/install_identity_v5_candidate.json`、`SERVICE_FACADE_LEG.patch` |
| round-3 台账门 `product_service_http` 的投影（v5） | **8/8 判据在 v5 上成立 → 投影 PASS；台账仍未并** | `evidence/service_http_ledger_projection_v5.json` |
| 逐层 forward 计数在 v5 上重跑 | **PASS**：48 层、L1–L9 全真、`estimated_values=0` | `evidence/layer_forward_calls_verdict_v5.json` |
| 物理页归还（新候选重跑，os4） | **BLOCKED**：A1–A4、A6–A9 全 true，**A5 false**（0.4996 < 0.50，差 −6.6 MiB）；**未改阈值** | `evidence/os_page_return_verdict_os4.json`、`evidence/os_page_return_cross_candidate.json` |
| 物理页归还（**当前候选 `83a880…`** 上重跑） | 同一二进制六次试验：**os5 0.517308 PASS、os5b 0.499115 BLOCKED、os5c 0.496538 BLOCKED**，注册后三次 **os6a 0.514509 / os6b 0.516235 / os6c 0.512096 全 PASS**。规则/阈值一字未改；注册判据形式上满足，但六次总体是 4/2 且分布与时间窗相关 → **门仍写 BLOCKED，待你定“评估单元”**（见 9.4） | `evidence/os_page_return_verdict_os5{,b,c}.json`、`os_page_return_verdict_os6{a,b,c}.json`、`evidence/os_page_return_trial_dispersion.json`、`evidence/os_page_return_preregistration_next.json`、`evidence/os_page_return_preregistration_amendment_1.json` |
| “free+inactive 把目标自己没被回收的 inactive 页算成归还”这条怀疑 | **被数据推翻**：inactive 在窗口内是**净流出**（约 13 GiB → 5 GiB），它对 A5 增益的贡献最多 0.0033；free-only 反而给 0.997–0.998，**是更松的口径**。因此**没有**采纳它（见 9.4.2） | `evidence/os_page_return_free_only_exploratory.json` |
| 401 与 503 的分工 | 从散文升级为**源码行引用**：状态映射由脚本从 `HTTPServer.swift` 读出，11 项检查全 true；归因任一为假则判定器自动降 BLOCKED | `evidence/service_http_status_mapping_attribution.json`、`driver/attribute_proof_status.py` |
| os5 窗口的非干预 | **CLEAN**：偏好域六个摘要 + Keychain 元数据逐行（含时间戳）在 os5/os5b/os5c 前后完全一致 | `evidence/noninterference_os5_series.json`、`evidence/noninterference_gate_v5.json` |
| 台账里三条门**记录的理由**已过时 | `per_layer_forward_calls`（“产品里没有插桩”）、`physical_page_return`（“没采到 OS 级证据”）、`product_service_http`（5 条判据记为 false，现已实测为 true）**的理由与当前证据冲突**；`install_and_operate` 的理由**仍然成立**（缺真人操作）。此清单只读，台账未动 | `evidence/ledger_reason_staleness.json`、`driver/project_ledger_staleness.py` |
| 产品 GUI 普通提示 | **BLOCKED**：屏幕录制权限**已授予并复探通过**（截屏 rc=0、5,249,809 B、3840×2160），现在只差你亲手在候选里点一次（第 10.1 / 10.3 节） | `evidence/gui_prerequisite_recheck_os5.json`、`evidence/gui_walk1_walkthrough.json` |
| 验收台账 | **未修改**：仍 12 PASS / 3 BLOCKED / 0 FAIL / 1 NOT_INSTRUMENTED，sha256 `57de11e7…` | `evidence/ledger_untouched.json` |
| **v2.2.0rc1 总体** | **仍 BLOCKED** | GUI 缺一次真人操作；物理页归还同一二进制跨阈值、按预注册规则未构成候选级 PASS；台账未并表（Service/HTTP 已在 v5 上门面齐备，台账仍 BLOCKED，并表需授权） |

一句话：这一项现在有了证据；但"有了证据"和"门已经并进台账"是两件事，后者需要单独授权。

---

## 2. 门措辞更正：原话与事实不符

旧批次的判定器 `driver/verify_batch.py:341` 写的是：

```python
gate("per_layer_forward_calls", "NOT_INSTRUMENTED", {
    "instrumented": False,
}, "No per-layer forward-count instrumentation exists in the product.")
```

这句话在产品里是**可证伪的**。`Packages/SimiGoRuntime/Sources/SimiGo2Experimental/Instrumentation/`
下有四份文件、共 1,838 行：

| 文件 | 行数 | 作用 |
| --- | --- | --- |
| `GroupExecutionTraceProbe.swift` | 594 | 观测点安装（`TracedLinear`）、`layerEntered` 事件、`passCount`、`tracesStable` |
| `MeasuredExecutionTracePilot.swift` | 442 | 驱动协议 `G1.9-A.PILOT.V1`、A1/A2 自检、报告结构 |
| `InstrumentationIdentityProbe.swift` | 532 | 插桩身份与边界记录 |
| `MeasuredTraceCollection.swift` | 270 | 轨迹采集 |

所以准确的说法不是"没有插桩"，而是：

> **插桩存在、被编进运行时包，但在 HEAD 上没有任何调用方把它驱动起来，
> 因此从未产出过逐层数字。**

这一点是测出来的，不是断言的：`git grep` 在 `f18d65f` 上检索
`ExecutionTracePilot` / `GroupExecutionTraceProbe` / `MeasuredTraceCollection`，
**在 `Instrumentation/` 目录之外命中 0 次**；本批次之后命中 2 个文件
（`SimiGo/Headless/SimiGoG1G3Entry.swift`、`SimiGoTests/SimiGoG1G3HeadlessEntryTests.swift`），
都是本批次新增的。见 `evidence/instrumentation_inventory.json` 的
`references_outside_instrumentation_dir_at_head` 与 `references_outside_instrumentation_dir`。

这条更正**不是**"门通过了"的论据。它只说明门的措辞需要改；门能不能转 PASS，
取决于第 5 节的数字。

---

## 3. 本批次改了什么（delta 归因）

| 文件 | 目标 | 补丁 | 前 SHA-256 | 后 SHA-256 | 行数 | 影响安装产物 |
| --- | --- | --- | --- | --- | --- | --- |
| `SimiGo/Headless/SimiGoG1G3Entry.swift` | App | `LAYER_FORWARD_INSTRUMENTATION.patch` | `9a1e2b16…` | `25c4e967…` | `+112/−1` | 是 |
| `SimiGoTests/SimiGoG1G3HeadlessEntryTests.swift` | 测试 | `TESTS_TRACE_ROLE_COVERAGE.patch` | `ee3ddc9c…` | `69f5f2d2…` | `+18/−0` | 否（第 4 节有测量） |

### 3.1 为什么不能拿 `git diff` 当归因

本批次开工前，产品工作树就已经有 15 条未提交改动（`evidence/worktree_before_build.txt`），
其中同一文件 `SimiGoG1G3Entry.swift` 也有别人的未提交修改。于是：

* `git diff` 对这个文件报 **+237/−12** —— 其中 **+125/−11 不是我改的**；
* 我对 pre-edit 字节的**真实 delta 是 +112/−1**。

所以归因的单位不是"相对 HEAD"，而是"相对我动手前的字节"。
`evidence/patch_attribution.json` 用可重放的规则固定这件事：

| 规则 | 内容 | 结果 |
| --- | --- | --- |
| P1 | pre-edit 副本哈希 == 动手前记录的 sha | true（App）、true（测试） |
| P2 | 补丁零 fuzz、无 `.rej`/`.orig` | true、true |
| P3 | 重放结果与被编译的文件逐字节相同 | true、true |
| P4 | 补丁只触达 1 个路径 | true、true |
| P5 | 工作树文件仍等于构建时消费的 sha | true、true |
| P6 | 测试改动没有移动安装候选（改前/改后身份逐键相同） | true，`changed_keys=[]` |

App 侧的 pre-edit 副本来源要在报告里写清楚：它是我把本批次的 6 处替换**反向重放**
重建出来的，哈希与动手前记录的 `9a1e2b16…` 一致。测试侧的 pre-edit 副本来源更硬：
该文件当时干净，副本就是 `git show HEAD:SimiGoTests/SimiGoG1G3HeadlessEntryTests.swift`
（`ee3ddc9c…`）。

### 3.2 新增角色做了什么

`SimiGoHeadlessRole` 增加 `case tracepilot`；`evaluate(env:)` 对它只要求
`SIMIGO_EXPERIMENT_ROOT` / `SIMIGO_RUN_ID` / `SIMIGO_HEADLESS_MODEL_PATH`（与其它角色同一套
前置校验），不要求 `SIMIGO_HEADLESS_TARGET_VALUE`（它产出的是报告，不是结算值）。
`run(role:)` 对 `tracepilot` 调 `ExecutionTracePilot.run(repetitions: 2, maxTokens: 16)`，
把报告写到 `<root>/layerforwardtrace_<rid>.json`，并写进程证据。

这个角色**不加任何观测点**：观测点由 `Instrumentation/` 里既有的 `TraversalProvider`
安装，被动观察，不改参数、不改采样。

---

## 4. 构建与安装身份

| 项 | 值 |
| --- | --- |
| 构建 | `xcodebuild -project SimiGo.xcodeproj -scheme SimiGo -configuration Release -derivedDataPath <batch>/build build` → `** BUILD SUCCEEDED **` |
| 安装候选 | `<batch>/install/SimiGo.app` |
| 可执行文件 SHA-256 | `95224f06cf9c1387cd77c2582cec7d009584a28ce66ff4de76b405a764737fe6`（105,931,120 B） |
| Bundle 树摘要 | `8a3fb75116979a0054026d830b93b30a15a6f37741b7cdf72d31d60266155add`（19 个文件） |
| Bundle ID / 版本 | `SwiftUI.SimiGo` / 2.2.0 (26) |
| 签名 | ad-hoc + hardened runtime；`codesign --verify --deep --strict` rc=0；CDHash `443b17cf779d93b77ad3f30cc54c720c445805ff` |
| Gatekeeper | `spctl -a -vv` = rejected（本地未公证 RC 的环境约束，非构建失败） |
| dylib 身份 | bundle 内仅 1 个 Mach-O；48 个链接库全部来自 OS，逐个路径已记录 |
| 产物 = 安装 | `installed_equals_built = true` |

### 4.1 加测试之后重新构建，身份没有动

新增单测属于测试目标，不属于 App 目标。为避免"口说无凭"，加测试之后
用同一 `-derivedDataPath` 重跑了一次 Release 构建：

* 日志 `logs/build_release_after_test_change.log`：`** BUILD SUCCEEDED **`，
  `SwiftCompile` 命中 **0 次**（Xcode 判定 App 目标无输入变化，未做任何编译）；
* 重建后 `Release/SimiGo.app` 的 exe 摘要仍是 `95224f06…`；
* 重跑 `driver/make_install_identity.py`，与改测试前记录的文档**逐键完全相同**
  （`changed_keys: []`，含 bundle 树、可执行、CDHash、codesign、spctl、Mach-O 成员）。

### 4.2 与旧候选的关系

* 旧安装候选 `60973e08…`（Service/HTTP 批次）与 `cc6fe63c…`（round3 台账）的任何结果
  **都没有被沿用到本批次结论**。
* 本批次所有数字出自 `install/SimiGo.app`（`95224f06…`）；判定器规则 L9 就是
  "raw 文件里记录的可执行摘要 == 安装候选的可执行摘要"，防止拿旧二进制的结果充数。

---

## 5. 插桩实跑与逐层数字

### 5.1 怎么跑的

`SIMIGO_HEADLESS_ROLE=tracepilot`，在安装候选上以 forkpty 启动，
`SIMIGO_HOME` / `SIMIGO_CACHE_ROOT` / `SIMIGO_STATE_GRAPH_STORE` / `SIMIGO_EXPERIMENT_ROOT`
全部指向 `runs/lf1/` 内的隔离目录。驱动 `driver/run_layer_forward_trace.py` **不数任何
forward**：它只启动进程，然后从进程写下的报告里重新切分 pass、重新统计每层事件数。

进程结果：`exit_code=0`、墙钟 32.8 s、未超时；报告 `status=PASS`、
`protocolVersion=G1.9-A.PILOT.V1`、`instrumentedModuleCount=48`、
`g19a1BaselineIdentityPass=true`、`g19a2TraceStabilityPass=true`。

### 5.2 数字

模型 `config.json`：`num_hidden_layers=48`、`model_type=qwen3_moe`、`num_experts=128`；
运行时报告 `Qwen3MoEModel`。

| prompt | 每 repetition pass 数 | 观测层数 | `layerEntered` 事件 | 每层 forward 次数 |
| --- | --- | --- | --- | --- |
| P1 | 2 / 2 | 48 | 192 | 4 |
| P2 | 16 / 16 | 48 | 1,536 | 32 |
| P3 | 16 / 16 | 48 | 1,536 | 32 |
| 合计 | — | 48 | **3,264** | 4 – 32 |

`pass_shape_lengths = [48]`：每个 pass 都完整覆盖 0..47，且升序、无重复。
`estimated_values = 0`：报告里没有任何估值、时序推算或调用图猜测。
插桩开销（pilot 自报）：`maxOverheadRatio=1.202`、`mean=1.126`、
`peakMemoryOverheadMegabytes=3.48`。

### 5.3 九条预注册规则

| 规则 | 内容 | 结果 |
| --- | --- | --- |
| L1 | 既有 pilot 真的跑了（exit 0 / 证据 OK / pilot PASS） | true |
| L2 | 数字能追到文件（重算 sha256 == 进程记录的 sha256） | true |
| L3 | 轨迹稳定（每 case ≥2 rep、pass 数跨 rep 恒定且非零、声明==重算、trace stable） | true |
| L4 | 每个声明的层都被看到（48 == `num_hidden_layers`，0..47 无缺） | true |
| L5 | 每层每 pass 恰好进入一次 | true |
| L6 | 观测没改变任何东西（token 序列相同、logits 逐位相同） | true |
| L7 | 执行是逐层顺序的（每 pass 覆盖 0..47 各一次、升序） | true |
| L8 | 没有数字来自驱动方（验证器独立重算 == 驱动方派生块） | true |
| L9 | 候选就是新构建（raw exe 摘要 == 安装候选 exe 摘要） | true |

判定：`verdict = PASS`，`contradictions = []`（`evidence/layer_forward_calls_verdict.json`）。

> **跨 prompt 的 pass 数不相等是合法的。** EOS 早停会让短 prompt 少跑几次；
> 规则只要求**同一 prompt 跨 repetition 稳定**。不要求 4 == 32。

---

## 6. 这些数字覆盖什么、不覆盖什么

覆盖：

* 每个 decoder 层的 MLP 下投影（含 MoE 的 `switch_mlp.down_proj`）在每次前向里被进入一次；
* 前向 pass 的个数、顺序与逐层覆盖；
* 观测在此之前/之后模型输出逐位相同（被动观察的实证）。

不覆盖（报告自身字段，原样引用）：

* `observedScope = DECODER_MLP_DOWN_PROJ / CORE_NOT_DIRECTLY_OBSERVED`：
  **decoder 核心本身没有被直接观测**，观测的是它之后的下投影模块；
* `boundary = ... / NOT_DEMAND / NOT_PREDICTION / EXPERT_DEMAND_NOT_INSTRUMENTED`：
  **专家级 demand 没有插桩**，本批次不提供任何"哪个专家被调了多少次"的数字；
* 这是 **受限的生产路径**（`NativeMLX` / `MLXLMCommon` 之下），**不是 Service/HTTP wire 路径**。
  这正是授权书划的红线：本批次**没有**、也**不能**用这里的数字替代 Service/HTTP 门。

---

## 7. 受影响测试

| 运行 | 时点 | 套件结果 | 隔离 | 判定 |
| --- | --- | --- | --- | --- |
| `run_isolated_lf1` | 加单测之前 | 208 / 14 / 0 | 新鲜根，真实用户状态写入 0 | PASS（被 lf2 取代） |
| `run_isolated_lf2` | 加 2 个 `tracepilot` 单测之后 | **210 / 14 / 0** | 新鲜根，真实用户状态写入 0 | **PASS** |

两次都跑 `tools/run_isolated_tests.sh`，每次自建全新隔离根、注入三个根变量、
前后各取一次快照并差分。`run_isolated_lf2/isolation_run_lf2.json` 的九项检查全 true：

```
test_execute_succeeded, exit_code_zero, counts_parsed, no_failures,
xctestrun_only_three_roots, isolation_home_used_by_app, isolation_cache_used_by_app,
no_real_user_state_write, no_unexpected_write
```

非干预实测：`real_user_state_write_count=0`、`violation_events=0`、
`swept_real_roots=[~/.simigo, ~/Library/Application Support/SimiGo]`。

### 7.1 为什么要加这 2 个测试

`SimiGoHeadlessRole` 新增的 `tracepilot` 在既有测试里**零覆盖**：原有测试只覆盖
`produce` / `consume` / 未知角色。补的两条正好卡住最容易退化的两件事：

* `testTracepilotResolvesWithoutTargetValue`：它不要求目标值（否则角色永远解析不了）；
* `testTracepilotFailsClosedWithoutModelPath`：缺模型路径时仍在**任何模型工作之前**拒绝。

两条在 `run_isolated_lf2/isolated_tests_lf2.log` 里都 `started` + `passed`；
`SimiGoG1G3HeadlessEntryTests` 由 5 条变 7 条。

### 7.2 测试宿主与安装候选的构建差异（如实披露）

测试宿主是 **Debug** 构建（`-configuration Debug`，因为测试目标需要 `@testable import SimiGo`），
安装候选是 **Release** 构建。两者由**同一份源码**产生：App 源文件哈希在上表两处一致
（`25c4e967…`），且第 4.1 节测出加测试后 Release 产物未变。这个差异是本批次的
已知边界，不用它去支撑任何 Release 侧结论——Release 侧的结论由第 5 节的实跑支撑。

---

## 8. Service/HTTP：在新候选上重跑（因为二进制换了）

上一批的 Service/HTTP PASS 绑定在 `60973e08…` 上。本批次换了二进制，按纪律不能沿用，
所以把**既有的**五场景门原样重跑一遍——不改 Service/HTTP 代码、不关 TLS、不放宽 proof。

用 `--roots-prefix g2 --port-base 8200` 在全新隔离根 `g2A/g2B/g2C` 上跑，
证据在 `evidence/gate_installed_g2/`（含产品自己的 stdout/stderr 十九份）。

| 场景 | 预期（操作者表） | 本候选实测 | 判定 |
| --- | --- | --- | --- |
| 合法授权、有效 proof | HTTP 200 | **200**，body `SERVICE-HTTP-OK` | PASS |
| 无效 proof | 503 | **401**（proof gate 拒绝，见偏差） | PASS |
| 合法请求的生成因果 | 经过正常派发并计数 | trace 4 → 12 行（**delta 8**），且 `observed_spki` == activate 记录的 `transport_spki` | PASS |
| 无效 proof 的生成因果 | `generation_call_count=0` | 伪造 proof 401、无 proof 头 401、challenge 重放 401，**replay trace delta 0** | PASS |
| 信任激活或授权缺失 | 生成前拒绝、失败关闭 | 无授权：`/v1/challenge` **503** `LOCALB request authorization is not configured`；未 prepare：进程未监听即退出（`LOCALB_TRANSPORT_IDENTITY_MISSING`），健康检查 Connection refused | PASS |

判定器：`overall = PASS`，五个场景各 true，`candidate_equals_release_product = true`。

两条偏差照旧公开，未因重跑而淡化：

1. **无效 proof 返回 401 而不是 503。** 503 是"完全没有配置授权"（S5），
   401 是"配置了授权但 proof 过不了"。要它返回 503 就得把"未激活"和"坏 proof"混成一件事，
   产品没有这么改。
2. **serving leg 走的是 `NativeMLX.startWithLOCALB`，不是 `Service.start` 门面。**
   因为 `Service.start` 会往真实用户 defaults 域写 SwiftUI 偏好引用，本批次禁止动真实状态。
   被验证的是它驱动的那条 HTTP/LOCALB 路径，`Service` 门面本身没有被执行。
   本轮把这条偏差追到底了（`driver/inventory_service_facade.py` →
   `evidence/service_facade_inventory.json`，只读 `git grep`，HEAD `f18d65f`）：生产代码里
   持有 `Service.shared` 的只有 `SimiGo/App/StatusBarCoordinator.swift:68`，能调
   `startSelected()` 的只有 `MenuApp.swift:233`、`MenuApp.swift:265`、`Settings.swift:243`
   ——**全在 AppKit 层**；测试目标 0 处、headless 入口 0 处。也就是：这条偏差与“GUI 门
   未闭合”是同一个缺口——**用户可见的那次启动，是唯一会执行 Service 门面的入口**。
   好消息是它能在同一次操作里一起关掉，见 10.3 的 `service_facade`。

非干预（同一次运行的前后快照）：`real_user_state_write_count = 0`、`violation_events = 0`；
登录 Keychain 元数据 **2035 → 2035**（本产品相关条目 0 新增 0 删除）。

### 8.1 本轮增量：让 serving leg 走**真正的** `Service` 门面（v5 构建）

上一节的偏差 2 说的是实话：serving leg 走的是 `NativeMLX.startWithLOCALB`，
`Service` 门面本身没有被执行。按你的授权（路径 1）加了受控入口，然后**重建、重装、重取证**。

**改了什么（只加一个角色，只调现存 API）**

`SimiGo/Headless/SimiGoLocalBManagementEntry.swift`：387 → 453 行（+66），
差异存 `SERVICE_FACADE_LEG.patch`（sha256 `b694fb9c…`），编辑前后源文件都留在 `source_v5/`。
新增 `SIMIGO_LOCALB_MGMT=serve-service` 只做一件事：`Service.shared.start(path:)`。

- 没有注入任何配置：端口走产品自己的 `SIMIGO_PORT` 规则（`InferenceNodeConfiguration.fromEnvironment`），
  LOCALB 主机从隔离托管根解析；`start(path:)` 不碰 `selectModel`，因此也不写 defaults。
- 没有加路由、没关 TLS、没放宽 proof、没接受请求自报 SPKI、没在普通启动里自动激活：
  `evaluate` 仍要求隔离 `SIMIGO_HOME`，角色名不在允许表里就失败关闭。
- `Service.start(path:)` → `internalStart` → `NativeMLX.start(path:port:)` → `startWithLOCALB(nil, nil)`，
  与直接路径是同一个调用，所以两种 legs 的传输语义可比。

**新构建身份（旧证据全部留在原位）**

| 项 | 值 | 证据 |
| --- | --- | --- |
| 构建目录 | `build_v5/`（未覆盖 `build/`） | — |
| 安装候选 | `install_v5/SimiGo.app`（未覆盖 `install/`） | — |
| exe sha256 | `83a88048569f4470b9a82ff0ee7ed6817572e8bd777b7df8a6ce3a357c98b70d` | `evidence/install_identity_v5_candidate.json` |
| bundle 树 | `aacb6b4a9434c5526ad5bdc9ae36479a90638fa1dc87702fc99e6aa506ccd3e7`，19 个文件 | 同上 |
| 安装 == 构建 | `true` | 同上 |
| Bundle ID / 版本 | `SwiftUI.SimiGo` / 2.2.0 (26) | 同上 |
| 签名 | adhoc，`codesign --verify --deep --strict` rc=0；`spctl` rejected（与上批一致） | 同上 |
| dylib / 资源包身份 | 包内**无随包 dylib**：19 个文件里只有 1 个 Mach-O（`Contents/MacOS/SimiGo`）；`otool -L` 48 条全为 `/usr/lib` 与 `/System/...`；随包的是 `mlx-swift_Cmlx.bundle`（`default.metallib`）、`swift-crypto_*`、`swift-transformers_Hub` 六个 `.bundle` | 同上（`macho_members` / `main_executable_libraries`） |

**五场景在新候选上原样重跑**（`--roots-prefix g5 --port-base 8400`，隔离根 `g5A/g5B/g5C`）

| 场景 | 预期 | v5 实测 | 判定 |
| --- | --- | --- | --- |
| 合法授权、有效 proof | 200 | **200**，body `SERVICE-HTTP-OK` | PASS |
| 无效 proof | 503 | **401** `LOCALB_CLIENT_REQUEST_SIGNATURE_INVALID`（语义偏差仍在，见下） | PASS |
| 合法请求的生成因果 | 正常派发并计数 | trace 4 → 12（**delta 8**） | PASS |
| 无效 proof 的生成因果 | `generation_call_count=0` | 伪造 proof / 缺头 / 重放均 401，**trace delta 0** | PASS |
| 信任激活或授权缺失 | 生成前拒绝 | 无授权 503（delta 0）；未 prepare 进程未监听即 rc=3 | PASS |

**门面 leg 的证据：不是“我说它走了门面”，而是门面自己写的行**

`--serve-role serve-service`（隔离根 `g6A/g6B/g6C`，端口 8410-8412）：

| 检查 | 结果 |
| --- | --- |
| 角色就是门面 | `serve_payload.role = serve-service`，`binding = Service.start(path:)` |
| 门面自报运行中 | `listening = true`、`service_is_running = true`、`base_url = http://127.0.0.1:8410` |
| 门面自己的 trace 行 | `[NODE] backend=MLX … bind=127.0.0.1:8410` ×1、`[READY] http://127.0.0.1:8410/v1` ×1（`[CFG] source=` ×2 只计数，不作证据——理由见 11 第 11 条） |
| 合法请求 | 200，`generation delta 8`，非空 `chatcmpl-` 响应 |
| 无效 proof | 401，`trace delta 0` |
| 未激活 | 受保护路由 503、`delta 0`；未 prepare 时 rc=3 且**端口上没有监听** |
| 反例（同一脚本、直接角色 g5） | `[NODE]/[READY]` 计数 **0/0** → 这组标记确实能区分两条路径 |

判定器：`overall = PASS`，`facade_leg.facade_leg_passed = true`（8 项 required 全 true），
偏差 2 的状态从“未执行门面”变成 `closed_on_this_candidate`。旧判定文件 `evidence/gate_installed_g2/` 一个字没改。

**非干预：这一次是真的测出来的**

`driver/snapshot_prefs.py`（只读）在两次门之前之后各取一次真实产品偏好域（`SwiftUI.SimiGo`）的快照，
文件字节、大小、`mtime_ns`、`defaults export` 摘要、值集合摘要、key 数量 **六项全一致**（20 个 key 未变）；
登录 Keychain 元数据 **2035 → 2035**。这与 11 第 12 条那句被推翻的话直接相关。

**受影响测试与新构建上的其他门**

- App 套件在 v5 的 Debug 宿主 + 全新隔离根上重跑：210 executed / 14 skipped / **0 failures**，
  `real_user_state_write_count = 0`、`violation_events = 0`（`run_isolated_lf3/`）。
- 逐层 `forward_calls` 也在 v5 上重跑（`lf3v5`）：48 层、L1–L9 全真、每层每 pass 恰好 1 次、`estimated_values = 0`
  （`evidence/layer_forward_calls_verdict_v5.json`；旧 `layer_forward_calls_verdict.json` 未动）。

**这条不证明什么（保留）**

1. 无效 proof 仍是 **401** 不是操作者表的 503——语义差没有为了“对齐表格”去改产品。
   这一条现在有了源码级引用，见 8.3。
2. 门面失败关闭时，`Service` 把类型化状态吞成了文本：未激活时报的是
   `❌ The operation couldn’t be completed. (LOCALBCore.LOCALBStatus error 57.)`，
   `LOCALB_TRANSPORT_IDENTITY_MISSING` 这个 token 在门面这一层已经看不到了。
   本轮**如实记录**这个可观测性缺口，没有替它补一条“猜出来的”状态。
3. `serve-service` 是**受控管理面**，不是 GUI 那次点击：它证明请求能走完 `Service` → 监听 → proof → 生成，
   但“用户从菜单栏启动”这条入口仍然只在 AppKit（第 8 节偏差 2 的追查），GUI 门仍归 10.3 那条命令。

### 8.2 把 round-3 台账那条门逐条投影到 v5（投影，不是并表）

round-3 台账的 `product_service_http` 不是看一个总数，而是看八个判据
（`driver/verify_batch.py:153-178` 的 probe-token 分支）。那八个判据当时全落在“没有监听窗口”上。
这一轮我在 v5 上按同一组**语义**重测了一遍，并且没有改台账。

新装置 `driver/probe_transport_discipline.py`：独立根 `t5U1/t5U2`、端口 8500/8501，
每个请求都走候选自己的监听 socket，**没有一次**调用 `NativeMLX.generate`。

| 台账判据 | v5 实测 | 值 |
| --- | --- | --- |
| `probe_present` | `evidence/transport_v5/service_http_transport_probe_v5.json` | true |
| `listening_socket_found` | `lsof -sTCP:LISTEN` 的 owner pid == 候选 pid（53757 激活 / 53790 未激活） | true |
| `tls_only_transport` | 明文 GET → curl rc=52 `Empty reply from server`；默认信任 → rc=60 self-signed；peer SPKI 与 prepare 值一致 | true |
| `unconfigured_authorization_refused` | 未 activate 时 `/localb/auth/challenge` → **503** `not configured`，trace +0 | true |
| `no_authorization_relaxation` | 子进程 env 只有 7 个 `SIMIGO_*`（隔离根 / 角色 / 模型 / 端口），无 relax 键；产品侧 TLS 校验未动 | true |
| `authorized_request_completed` | 200 + 非空 `chatcmpl`，trace **delta 8**；同一端口无 proof → 401 | true |
| `authorization_surface_recorded` | 封存文件在；**在当前树上重扫**：`app_target_code_sites=1`（`SimiGoLocalBManagementEntry.swift:188`），写封存记录时是 0 | true |
| `authorized_lane_passes_in_test_target` | v5 的 App 套件里 10 个 LOCALB 用例全 passed（`lf3`，210/14/0） | true |

投影判定 `PASS`（`evidence/service_http_ledger_projection_v5.json`；重跑一次，输出逐字节相同）。

**三处必须说清的地方**

1. **401 与 503 不是同一个判据。** 台账要的 503 是“授权未配置”的守卫（S5），我们观测到的就是这个 503；
   操作者表里“无效 proof → 503”是另一件事，产品在 proof 失败时用 401 拒绝。这条偏差仍然公开，
   我没有为了让表好看去改产品。
2. **`tls_verify=18` 这个 round-2 token 不复现**，所以新记录里没有它。我只写实测：明文 rc=52、
   默认信任 rc=60、SPKI match。“TLS 强制”这个语义被测到了，旧字符串没有。把旧 token 抄进新记录
   就是把记忆当证据。
3. **activation surface 的性质变了**：v5 里第一个 app-target 的 ceremony 调用点是环境变量门控的管理入口
   （要求隔离 `SIMIGO_HOME`），不是普通启动、也不是 GUI 流程。所以“产品完全没有激活面”对 v5 已不成立，
   “用户点一下就激活”仍然不成立。

**这不是并表**：`acceptance_report.json` 的 sha256 仍是 `57de11e7…`，计数 12 / 3 / 0 / 1，总体 `BLOCKED`；
投影文件里写死了 `ledger_modified: false` 与 `merge_requires_authorization: true`。要不要并，是你的决定。
（本轮重生成投影：sha256 从 `256b33bc…` 变为 `4337ef3d…`，内容变化只有两处：多了 8.3 的
`status_convention`，并把 `facade_leg.serve_role` 这个容易误读的字段拆成“直连腿角色”与
“门面源文件角色”（此前它写的是 `serve`，而门面那次跑的是 `serve-service`）。台账仍未动。）

### 8.3 401 与 503 的分工：钉到源码行，而不是留在散文里

操作者表要“无效 proof → 503”，实测 401。上一版的解释只有文字，这一版把它换成可核对的引用：
`driver/attribute_proof_status.py` 从产品源码里**读出**状态映射（401/503 不是写死在脚本里的常量），
再问本次运行观测到的每个状态可能由哪个 case 抛出。输出
`evidence/service_http_status_mapping_attribution.json`：11 项检查全 true，`rc=0`。

| 项 | 源码事实（`SimiGo/Protocol/HTTPServer.swift`，除注明外） |
| --- | --- |
| 状态映射 | `var statusCode`（`:110`–`:141`）：`localbRequestRejected → 401`、`localbAuthorizationUnavailable → 503`、`localbTransportNotTrusted`/`localbRouteDenied → 403` |
| proof 失败走哪条 | `:1400`–`:1401` `catch let status as LOCALBStatus { throw .localbRequestRejected(reason: status.rawValue) }`；缺 proof 头在同 case 的 `:1345` |
| 观测到的 token 出处 | `LOCALB_CLIENT_REQUEST_SIGNATURE_INVALID` 定义在 `Packages/LOCALBCore/Sources/LOCALBCore/LOCALBProductionSigner.swift:76`，`LOCALB_CLIENT_CHALLENGE_INVALID` 在 `:74` |
| 503 走哪条 | `:1333` 与 `:1435` 两处 `throw .localbAuthorizationUnavailable`，各自紧接 `guard let authorization = localbRequestAuthorization`（`:1332` / `:1434`）——语义是“这台主机根本没配置请求授权”，正是 S5 |
| 请求自报 SPKI 不被采信 | `:1326`–`:1327` 注释 “Client-supplied SPKI values are never read.”；`:1328`、`:1431` 只用 accept 时写入的 `context.transportSecurity` |
| 信任检查点 | `:1398`（另 `:1486`）把 `authorization.trustedCheckpoint()` 传给 `authorizeProtectedRequest` |
| 源码身份 | HEAD `f18d65f`；`HTTPServer.swift` sha256 `d478e0e8fb0709ce…`，`git hash-object` == `git rev-parse HEAD:`，工作树干净；本轮**未修改**这两个文件 |

所以准确的表述是：**表里那个 503 是 S5 的状态；proof 门的现行门槛就是 401。**
这条偏差在判定文件里仍然保留（不删、不粉饰），只是从“我说”变成“引到行”。
`verify_service_http_gate.py` 新增 `--status-mapping-source`：一旦归因文件的 11 项检查有任一为
`false`，总体判定直接降为 `BLOCKED`——源码解释不了观测时，不给 PASS。
重跑判定器后新判定的 sha256 是 `3cb4fb9a…`（上一版为 `d8fec254…`，即当时写进
`MANIFEST_SHA256.txt:76` 的那一份；原始记录
`service_http_gate_installed.json` 一字未动），两次重跑**逐字节相同**。

---

## 9. 物理页归还：在新候选上按同一套规则重跑（os4）

上一批的 `physical_page_return` PASS 属于 os3，跑在 `60973e08…` 上。本批次换了二进制，
沿用它就是拿旧二进制的数字给新候选背书。所以把 `run_os_page_return.py` /
`verify_os_page_return.py` 复制进本批，**只**把脚本里硬编码的 CANDIDATE 指到
`install/SimiGo.app`（`95224f06…`），其余**一字未改**：10 ms 采样、1500 ms settle 窗口、
`MIN_LOW = 20`、阈值仍是 `host_gain >= drop_bytes // 2`。

### 9.1 结果：A5 没过，判 BLOCKED

进程 `exit_code=0`、墙钟 256.7 s、22,514 个采样点。

| 规则 | os3（`60973e08…`） | os4（`95224f06…`） |
| --- | --- | --- |
| A1 出货的 suspend 真的跑了 | true | true |
| A2 anchor 前是加载态 | true | true |
| A3 驻留集下降 | true | true |
| A4 低占用持续 | true | true |
| **A5 内核把页收回池** | **true**（0.508324） | **false**（0.499600） |
| A6 compressor 不是去处 | true | true |
| A7 进程存活、证据在窗口之后写入 | true | true |
| A8 噪声地板小 | true | true |
| A9 应用与内核一致 | true | true |
| 判定 | PASS | **BLOCKED** |

A5 的算术（**从字节重算，不用判定器里保留 3 位小数的字段**）：

| 量 | os3 | os4 |
| --- | --- | --- |
| 驻留下降 | 17,299,238,624 B（16.11 GiB） | 17,291,980,536 B（16.10 GiB） |
| anchor 可复用池 free+inactive | 14,940,405,760 B | 14,985,871,360 B |
| 窗口内池峰值 | 23,734,026,240 B | 23,624,941,568 B |
| 收回量（峰值 − anchor） | 8,793,620,480 B | 8,639,070,208 B |
| 比值 | **0.508324** | **0.499600** |
| 阈值（`drop_bytes // 2`） | 8,649,619,312 B | 8,645,990,268 B |
| 余量 | **+144,001,168 B**（+0.134 GiB） | **−6,920,060 B**（−6.6 MiB） |

矛盾项（判定器原文，两条）：

```
the shipped suspend ran, but the kernel's available pages did not rise by at least half of the resident drop
the process gave up resident bytes that the kernel never returned to the free/inactive pool
```

### 9.2 没有做的事

* **没有调阈值**（仍是 0.50）、**没有改规则**（`rule_changed=false`、`threshold_changed=false`）、
  **没有重新定义 A5**、没有把 os3 的结果搬过来说"新候选也一样"。
* 台账里 `physical_page_return` 本来就是 `BLOCKED`，这次重跑**没有改变**它的台账状态——
  既没有"顺手改成 PASS"，也没有因为这次失败去改别的东西。
* 判定器补了 `raw_file` / `raw_sha256` 两个字段，把判定绑定到它推导的那份 raw 字节
  （`d0a3a140…`）。补字段后重跑判定器，除这两个新键外**所有已有键逐键相同**，判定仍是
  BLOCKED——这是溯源改进，不是重判。

> `evidence/os_page_return_raw.json` 是 `run_os_page_return.py` 自己写出的文件名；
> `evidence/os_page_return_raw_os4.json` 是它的**逐字节副本**（同 sha256 `d0a3a140…`），
> 加 rid 后缀是为了与上一批的 `os_page_return_raw_os3.json` 对齐。判定器读的是后者。

### 9.3 A5 这个指标本身贴着噪声带（事实，不是申诉）

A5 的分子是 `max(free+inactive) − anchor(free+inactive)`，它把**进程自己刚释放、还没被
内核回收的 inactive 页**也算成"回到池里"。于是一个真的把内存还回去的行为，比值结构性地
落在 0.5×drop 附近——阈值 0.50 正好压在这条自噪声带上。

两个候选的实测差异（`evidence/os_page_return_cross_candidate.json`）：

| 量 | 差异 |
| --- | --- |
| 收回量 | −154,550,272 B（**−1.76%**） |
| 驻留下降 | −7,258,088 B（−0.04%） |
| 比值 | −0.008724（−0.87 个百分点） |
| 到阈值的余量 | −150,921,228 B |

即：**os4 失败的余量（6.6 MiB）比两个候选之间收回量的差异（147 MiB）小 22 倍**。
这不能推出"页没还回去"；A6、A7、A9 和 free 池的数字都指向同一方向。它只能推出
一件更窄、也更该被承认的事：**这条规则在自己的分辨率之下，无法区分"还了"和"没还"**。

但"指标不好"不是这次判 PASS 的理由。**这一段的推断后来被数据推翻了**：本节当时假设
free-only 会是"更严"的指标，所以要求它在下一次运行之前预注册；实际把五个试验的字节拆开
算后，free-only 是**更松**的口径（见 9.4.2）。所以预注册里明确**不采纳**它。在看到 os4 差
0.04 个百分点之后立刻换指标，那是移动球门，不是更诚实。所以本节的结论保持 **BLOCKED**。

### 9.4 当前候选上的重复试验：一个二进制能跨阈值摆动（os5 / os5b / os5c，及注册后的 os6 集）

os4 只说明旧候选 `95224f06…`。Service/HTTP 门面又改了一次代码，所以现在必须问的是：
`83a88048569f…` 这个二进制自己怎么样。把 `OS_PROBE_CANDIDATE` / `OS_PROBE_RAW` 做成环境变量
（测量逻辑一字未改），在同一候选上背靠背跑完整试验。

#### 9.4.1 三个试验，两个方向（同一可执行文件）

| 试验 | 二进制 | 驻留下降 | 收回量 | 比值（从字节重算） | 阈值 | 余量 | 判定 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| os5 | `83a880…` | 17,300,188,920 B | 8,949,530,624 B | **0.517308** | 8,650,094,460 B | **+299,436,164 B** | PASS |
| os5b | `83a880…` | 17,297,305,264 B | 8,633,352,192 B | **0.499115** | 8,648,652,632 B | **−15,300,440 B** | BLOCKED |
| os5c | `83a880…` | 17,299,107,528 B | 8,589,656,064 B | **0.496538** | 8,649,553,764 B | **−59,897,700 B** | BLOCKED |

离散度（`driver/compare_os_trials.py` → `evidence/os_page_return_trial_dispersion.json`）：

| 分组 | 试验 | 比值跨度 | 余量跨度 |
| --- | --- | --- | --- |
| `60973e08…` | os3 | 0.0 | 0 |
| `95224f06…` | os4 | 0.0 | 0 |
| **`83a880…`** | **os5 / os5b / os5c** | **0.020771** | **359,333,864 B** |

这三个事实必须一起说：

1. **同一二进制能在 0.50 两侧摆动**，比值跨度 0.0208（约 343 MiB）。所以"一次试验的 PASS"
   不构成关于二进制的结论，"一次试验的 BLOCKED"也不构成——包括 os4 那一次。
2. **候选之间的差异小于二进制自身的重复噪声**：os4 距阈值 −6.6 MiB，而同一候选的试验间
   跨度是它的 52 倍。这条指标现在分辨不了候选。
3. 三个试验的其余规则都干净：A1–A4、A6–A9 全 true，`exit_teardown_used_for_verdict=false`，
   驻留下降量三者只差 0.02%（17.30 GB 量级），也就是**工作负载是重现的**，摆的是池那一侧。

#### 9.4.2 free-only 这条怀疑被数据推翻，而且方向相反

操作者提出的方法学问题（A5 把"目标自己刚释放、尚未被内核回收的 inactive 页"也算成归还）
是一个可以算的命题，不该停留在"听起来合理"。`driver/analyze_os_free_only.py` 用**与判定器
完全相同的 anchor 和 settle 窗口**把五个已存原始记录的增益按桶拆开（只分析，不重判）：

| 量 | 实测 |
| --- | --- |
| inactive 对 A5 增益的贡献 | **0.0000 – 0.0033**（几乎为零） |
| anchor 时刻的 free 池 | **0.13 – 0.25 GiB**（基本空） |
| anchor 时刻的 inactive 积压 | **≈ 13 GiB**（别的进程早就留下的） |
| 窗口内 free 峰值 | ≈ 16.2 GiB |
| 窗口内 inactive | **流出**：13 GiB → 4.9–5.7 GiB |
| `ratio_free_only` | **0.997212 – 0.998814** |
| `ratio_free_plus_inactive`（实际评分口径） | 0.496538 – 0.517308 |

结论与怀疑的方向**相反**：这台机器到达 anchor 时 free 几乎是空的、inactive 压着 13 GiB 积压；
内核一边回收目标释放的页、一边把**原有的 inactive 积压**也回收进来填 free。`free+inactive`
把这个积压净额掉了，所以它是两者中**更保守**的口径；单看 free 会因为"回填到高位水位"
而直接给到 0.998，**远松于** 0.50。所以：

- **不采纳** free-only 作为判据。在看过 BLOCKED 之后换成它，是把球门往能过的那一侧挪。
- 这条怀疑本身**记下并公开**：它不成立，这是新证据，不是旧结论的重复。
- 真正被测量出来的混杂因素是**主机起始池状态**：增益 = `peak(free+inactive) − anchor(free+inactive)`，
  而 anchor 在不同试验之间就差 0.8 GiB（13.14 – 13.96 GiB）。五个试验增益落在 8.00–8.34 GiB，
  阈值 ≈ 8.05 GiB ——**阈值整个落在这条指标的试验间散布里**。

#### 9.4.3 预注册（只对未来生效，不追溯）

`evidence/os_page_return_preregistration_next.json`（登记 18:40，18:55 修订）：

- **适用于**：在该时间戳**之后启动**的页归还试验；**不适用于** os3/os4/os5/os5b/os5c，
  它们保留各自判定器当时写下的判定，一个字不改。
- **A1–A9 与阈值 0.50 全部不动**（`threshold_changed=false`、`metric_redefined=false`）。
- 新的候选级主张必须：**同一 exe sha256 上三次独立试验全部过 A5**；报告必须给从字节
  重算的逐试验比值、最小比值、以字节计的余量，不得只给保留 3 位小数的判定字段；必须
  同时记下 free-only 比值与 inactive 占比（明确标为非判据）；必须记录 anchor 时刻的主机池状态。
- **不得挑选主机起始状态**：不许为了拿到好看的 anchor 而重跑、等待"机器安静"或丢弃异常试验；
  启动的每一个试验都保留、都计数。
- 明确不采纳 free-only、不降低 0.50、不做主机状态归一化（看见五个试验之后再发明一个修正
  因子就是拟合数据）。
- 上面这些正文（包括“不得挑选主机起始状态”那条）都在 **18:50:14** 那份文件里，而不是后来补的；
  后续记录与自我质疑另存为 `evidence/os_page_return_preregistration_amendment_1.json`（19:11），
  它**不改判据、不追溯、不覆盖注册件**。

#### 9.4.4 注册后的三次集（os6a / os6b / os6c）：形式上过线，但时间窗在摆动

先说时序，因为这是“注册在前”的硬证据：

| 事件 | 时间 | 依据 |
| --- | --- | --- |
| 预注册文件写入批次目录 | **18:50:14** | 该文件的 mtime |
| os6a 启动 | **18:50:39** | `logs/os6_chain.log` |
| os6b / os6c 启动 | 18:55:16 / 18:59:51 | 同上 |
| 三次全部跑完 | 19:04:29 | 同上 |

JSON 里自写的 `registered_at` 是 18:40；文件在盘上的 mtime 是 **18:50:14**。两个数都说
“早于 os6a 的 18:50:39”，但以后者为准——那是外部可查的物证，不是我自己写的时钟。

**并且文件里那个 `amended_at: 18:55` 是错的**：我当时凭印象写了“18:55 修订”，而实际上
修订后的正文在 18:50:14 就已经落盘（早于 os6a）。排序结论不变，但那个时刻是记错的，
登记在 `evidence/os_page_return_preregistration_amendment_1.json` 里；这份登记件**不覆盖**
原注册文件（盖掉它就会毁掉“注册在跑之前”的物证），那个错标签也保留不改。

| 试验 | 启动 | 驻留下降 | 收回量（peak − anchor） | 阈值（drop//2） | 比值 | 余量 | 判定 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| os6a | 18:50:39 | 17,297,534,688 B | 8,899,739,648 B | 8,648,767,344 B | **0.514509** | +250,972,304 B | PASS |
| os6b | 18:55:16 | 17,297,419,904 B | 8,929,542,144 B | 8,648,709,952 B | **0.516235** | +280,832,192 B | PASS |
| os6c | 18:59:51 | 17,284,706,040 B | 8,851,423,232 B | 8,642,353,020 B | **0.512096** | +209,070,212 B | PASS |

三个试验都是当前候选（`identity.exe_sha256 = 83a88048569f…`、`candidate_override` 指向
`install_v5/SimiGo.app`），参数与 os5 完全同一行（`OS_PROBE_INTERVAL=0.01`、`OS_PROBE_BASELINE=20`、
`MIN_LOW=20`、settle 1500 ms），`exit_teardown_used_for_verdict=false`，A1–A9 全 true，
矛盾项 0，exit_code 0。os6 窗口前后非干预 **CLEAN**（`evidence/noninterference_os6_series.json`）。

这些判定不是“信一份文件”：七个试验（os4–os6c）的判定文件都从留存 raw 重新生成过一次，
与在盘文件**逐字节相同**（三个 BLOCKED 的 rc=1：os4/os5b/os5c；四个 PASS 的 rc=0：os5/os6a/os6b/os6c），记录在
`logs/repro_os_verdicts.log`。这是复现校验，不是重跑试验、也不是重判。

**所以注册判据形式上过了：同一 exe、注册之后、三次全过 A5。** 但同一堆数据里还有两个
必须一并说的事实，否则这一段就成了只报好的一半：

| 分组 | 窗口 | 结果 |
| --- | --- | --- |
| os5 / os5b / os5c | 18:26 – 18:42 | PASS / **BLOCKED** / **BLOCKED**（增益 8.335 / 8.040 / 8.000 GiB） |
| os6a / os6b / os6c | 18:50 – 19:04 | PASS / PASS / PASS（增益 8.289 / 8.316 / 8.243 GiB） |

1. **六次合起来是 4 PASS / 2 BLOCKED**，同一个可执行文件。只拿注册后的三个说“满了”，
   而同一二进制刚给你两个 BLOCKED——那就是把切分点当结论。
2. **失败集中在前一个时间窗口，通过集中在后一个**，而 anchor 几乎一样（13.06–13.27 GiB），
   差的是 peak（失败 21.14 / 21.31 GiB，通过 21.30–21.51 GiB）。采样点数也分属两套
   （os5 系列 22.5k，os6 系列 19.9k，差≈ 28 s）。也就是说：唯一系统的区别是**窗口**，
   不是二进制。
3. **我自己就是“跑到一个干净集为止”这个模式里的嫌疑人**。我先看见 os5b/os5c 失败，
   然后注册规则、又跑了三个，结果全过。注册与启动的先后是可核的（18:50:14 < 18:50:39），
   判据也没被软化（还是 0.50，还是三次全过），但这不能单独排除时间效应。

因此本节的写法是**两个事实都保留，不下“候选级 PASS”的结论**：

- 报告给注册判据的形式满足（包括上面那些必须同时看的事实）；
- `physical_page_return` 在本批次写为 **BLOCKED，待你对“评估单元”的判定**：
  如果你认可“注册后的集”是合法评估单元，它就应当改成 PASS；如果你要求先排除时间效应，
  那需要的是另一条预注册（例如同一窗口内交错重复、或至少跨两个时间窗的全过），
  而不是我临时把 0.50 调低或者把 free-only 拉回来。

八次试验（含上一批 os3 与旧候选 os4）的并列与离散度全部在
`evidence/os_page_return_trial_dispersion.json`；free-only / inactive 分解在
`evidence/os_page_return_free_only_exploratory.json`（`binding=false`）。


---

## 10. 仍未闭合的项（各自独立，不随本项关闭）

| 事项 | 状态 | 缺什么 / 依据 |
| --- | --- | --- |
| 逐层 `forward_calls` | **本批次给出插桩与数字**：v5 上 `lf3v5` 重跑，`candidate_exe_sha256=83a880…`、L1–L9 全 true、事件 3,264、`estimated_values=0` | **插桩与数字已绑定当前候选**（不是旧二进制）；但覆盖范围仍限于 `DECODER_MLP_DOWN_PROJ / CORE_NOT_DIRECTLY_OBSERVED`，专家级 demand 未插桩；台账仍 `NOT_INSTRUMENTED`，其理由已 stale（见 10.4） |
| 产品 GUI 普通提示 | **BLOCKED**（不再是 BLOCKED_PREREQUISITE） | 屏幕录制与辅助功能均已授予并复探通过（`evidence/gui_prerequisite_recheck_os5.json`）；**只差你本人的一次操作**（10.1 / 10.3）。两条 AX 通道仍无可见效果、原因未定（10.2.1），不得当作产品缺陷也不得当作 GUI 已通过 |
| 物理页归还 | **BLOCKED**：当前候选六次 4 PASS / 2 BLOCKED；注册后的 os6 集三次全过（形式上满足注册判据） | 阈值与规则未改；未采纳 free-only（它更松）；预注册仅对未来试验生效；**总体 4/2 与时间窗相关 → 评估单元待你定**，见 9.4 |
| Service/HTTP | **PASS（v5 新候选，含 `Service` 门面）** | 五场景全过（第 8 节）+ 门面 leg 8 项 required 全 true（8.1）+ 台账 8 判据投影 PASS（8.2）+ 401/503 已钉到源码行（8.3）；台账仍 BLOCKED，并表需另授权 |
| 验收台账 `acceptance_report.json` | **未修改**：12 / 3 / 0 / 1，`sha256=57de11e7…` | 并表需单独授权；哪几条门的**记录理由**已被现证据推翻，见 10.4 |
| **v2.2.0rc1 完整验收** | **BLOCKED** | GUI 缺一次真人操作；页归还的“评估单元”未定（注册后 3/3 与同二进制总体 4/2 共存）；台账未并表 |

关于并表算术（写进 `evidence/ledger_untouched.json` 的 `expected_if_merged`，但不执行）：
`per_layer_forward_calls` 从 `NOT_INSTRUMENTED` 移到 `PASS`，即 `PASS 12+1=13`、
`NOT_INSTRUMENTED 1-1=0`；`BLOCKED` 三项（`install_and_operate`、`physical_page_return`、
`product_service_http`）不动。

### 10.1 GUI 的前置条件：本轮只测了权限，没有操作 GUI

`driver/probe_gui_prerequisites.py`（只读、不申请授权、不启动候选）的结果：

| 权限 | 探测方式 | 结果 |
| --- | --- | --- |
| 辅助功能（Automation / System Events） | `osascript ... count processes` | **已有**（返回进程数 80） |
| 屏幕录制 | `screencapture -x /tmp/...png` | **缺失**：rc=1 `could not create image from display`，未生成文件 |

**本轮复探（已改）**：`evidence/gui_prerequisite_recheck_os5.json` —— 辅助功能仍有（System Events 返回 92 个进程），
屏幕录制**已授予**：`screencapture -x` rc=0，生成 5,249,809 B 的 3840×2160 截屏。也就是说
GUI 门现在缺的**只剩那一次真实用户操作**，不再卡在权限上。这一条对我自己的装置也有影响：
装置里 `screenshot_present` 原来只看“文件有字节”，权限没授时靠 rc=1 就拦住了；现在权限已给，
一张全黑的图也能有字节。所以我把阈值加到字节地板（200,000 B，本机一张真实屏 5.2 MB），又补
了一次 1 秒后的第二张截屏并比较两者 sha256（活桌面有菜单栏时钟，不会逐字节相同）；同时把
“要操作哪个二进制”显式化：脚本默认仍指 `install/`（`95224f06…`），现在用 `GUI_APP=` 覆盖，
并在提示里打印即将启动的 exe sha256。**未闭合项**：两张截屏逐字节相同并不能排除整帧均匀，
所以它只记录不判负——它是个信号，不是新门槛。

所以上面那段表格是**当时测出来的**历史状态（`evidence/gui_prerequisite_probe.json`），它不再
是现在的阻塞理由。现在 GUI 门的准确状态是：**BLOCKED，缺一次真实用户操作**。
无论权限如何，都需要在安装候选里走完那一次操作，本轮没做，也不拿 headless 生成冒充。
授权由机器主人在系统设置里给（屏幕与系统音频录制 → 勾选跑脚本的宿主 App/Terminal），
本轮我没有替任何人点过那个开关，只是探测到它已经开了。

### 10.2 我试过用辅助功能去操作它；结论是这条通道在这台机器上不能用

权限只是第一道门。第二道门是：**自动化能不能真的操作这个 app**。本轮把候选
（`95224f06…`）用 LaunchServices 打开（`open -n -F --env …`，与用户双击同一路径），
隔离根在 `runs/gui4/`，进程确实起来了：`bootstrap: issueCount=0 models=20`、
`simigo.sqlite3` 建立、`SIMIGO_HOME` 在进程环境里可见。

然后逐项测（`driver/run_gui_ax_probe.py gui4`，权威运行）：

| 探测 | 结果 |
| --- | --- |
| 激活策略 | `backgroundOnly = true`（菜单栏常驻 app） |
| AX 菜单栏 | 2 个：主菜单栏（Apple/SimiGo/Edit/View/Window/Help）与 extras 栏（1 项，description `SimiGo`） |
| 状态项位置 | `[-1, 1068]`，尺寸 `[20, 24]`（当时的读法是“逻辑屏 1920×1080，x = −1 在屏外”；这个读法在 10.2.1 被推翻） |
| AXPress 状态项 | 无报错，`windows` 仍为 0 |
| `CGWindowList` | 调用方看不到任何窗口（未授屏幕录制时这张表本身就是空的） |
| **AXPress 派发测试** | 按 app 自己的 **`Quit SimiGo`** 菜单项 → 3 秒后进程**仍在**（当时未先打开父菜单；10.2.1 补做了） |
| 对照：AppleEvent | `tell application "SimiGo" to quit` 生效（进程退出） |

最后两行当时被我写成“决定性”的：**AXPress 返回成功，但动作不派发**。对照的 AppleEvent
能退出，说明 app 活着、事件循环正常。但这个结论要缩小：菜单项在不打开父菜单时按本来
就不派发，所以 gui4 的 Quit 测试不构成证据。上一批的 “AXPress succeeds” 与本轮初稿的
“AXPress 被受理但不派发”，两个措辞都不准确，见 10.2.1 与第 11 节。

非干预（同一次运行前后快照，`evidence/gui_gui4_snapshot_diff.json`）：
`real_user_state_write_count = 0`、`violation_events = 0`。

### 10.2.1 追加探测（gui5）：重做派发测试，并给坐标找参照系

gui4 留了两个可疑点，本轮用 `driver/run_gui_ax_probe2.py gui5` 重测（同一隔离根、
同一候选、同样前后快照）：

| 探测（gui5） | 结果 | 说明 |
| --- | --- | --- |
| P3 按正确顺序的派发测试 | `AXShowMenu` 打开 app 菜单 → 按 `Settings…` → 无报错，`windows` 仍为 0 | 上次没开父菜单，这次开了，结果一样 |
| P4 状态项 `AXShowMenu` | 无报错，`windows` 0 → 0，进程仍在 | 与 AXPress 同 |
| P2 坐标系标定 | `NSScreen` = 1920×1080；SimiGo extras 项 `[-1, 1068]` / `[20, 24]`；**但 app 自己的菜单栏项全部报 `[0, 30]` / 尺寸 `[0, 0]`** | 尺寸 0×0 是不可能的几何，说明这条通道报的坐标不能当事实 |
| P2 同级参照 | `Control Center` 不可访问（`exists=false`）、`SystemUIServer` 的 `menuBars = 0` | **拿不到任何可比对的邻居** |

因此两句话必须改：

1. **“x = −1 在屏外”不能当测量结论。** 它是在没有任何参照物的情况下对一串不可靠坐标的
   解读；同一批数据里明显可见的菜单项也被报成 `[0, 30]`、`[0, 0]`。准确说法是：
   **无法从这条通道判定状态项是否在屏幕上**。
2. **“AXPress 被受理但不派发”过强。** 重做后行为一样，但仍无法区分两种原因：
   (a) 这台机器上 AX 动作对这个 app 不生效；(b) 该 app 的状态项/菜单栏本来就不在
   可见位置上，于是没有东西可派发。两种都让 GUI 门关着，但**是不是产品缺陷完全不同**。

能分开这两种原因的只有两样，都不是我能单方面取得的：屏幕录制（看得到菜单栏）与你的
眼睛。所以这两条继续挂在“未定”上：不写成产品缺陷，也不写成“差一次点击”。

还有一条线索值得记下，但**它只是假设**：产品里有段注释写过同类症状——
`SimiGo/App/StatusBarCoordinator.swift:62-63` 说旧的 `MenuBarExtra(.window)` 在系统睡眠
唤醒后“performClick 受理、按钮高亮，面板零创建”，所以才改成现在的 `NSStatusItem`。
而 `togglePopover` 依赖 `popover.show(relativeTo: sender.bounds, of: sender, …)`：若按钮
所在的窗口不可见（例如菜单栏项被挤进溢出区），这个调用就不会造出面板。这与“AX 动作
无报错但 `windows` 不动”一致，也与 `[-1, 1068]` 这种被挤出屏外的坐标一致。
但这三条一致不等于证明：真要落成结论，需要你在屏幕上看到那个图标到底在不在。

**这不能当成产品缺陷的证据。** 它只说明：在这台主机上，agent 代替不了那次用户操作，
而且连“状态项是否可见”都判不了。要推进 GUI 门，只有两条路，两条都需要你：

1. **你本人操作一次**：授予屏幕录制后，在菜单栏里点开 SimiGo 面板（顺手告诉我
   那个状态项在你屏幕上到底在不在——AX 报的 `x = −1` 不可信，但也不能排除真的被挤到屏外），
   走一次普通操作；我负责采集进程身份、结果与隔离根差分。
2. **另授权一个受控入口**：例如给 app 加一个只用于验收的命令行/菜单项入口去开
   `Execution State` 窗口。这是**产品代码改动**，需要新的构建与新身份，不在现有授权内。

三者之中，我没有自己选一条“看起来能过”的路。

### 10.3 把“你操作、我取证”做成一条命令：`driver/gui_walkthrough.py`

上面两条路里，第一条不需要改产品代码，只需要你动一次手。为了让那一次动手直接变成
可核验的证据，本轮写了 `driver/gui_walkthrough.py`（只新增 driver，**不含任何产品改动**，
所以不需要新构建、新身份，候选仍是 `95224f06…`）。

它做的事：先给真实用户状态拍前快照 → 用 LaunchServices（与双击同一路径）在
`runs/<tag>/` 的隔离根里打开 `install/SimiGo.app` → 打印操作说明并等你 →
截屏（`screencapture -x`）→ 读产品自己的 trace
（`<SIMIGO_HOME>/logs/native_mlx_trace.log`：`[PROTOCOL] arrive` 计请求，
`[MLX] session=` 计真实生成）→ 用 AppleEvent 退出 → 拍后快照并做差分。

判定规则写死为七个条件，全部来自测量，没有一个是“看起来像”：

| 条件 | 来源 |
| --- | --- |
| `process_stayed_up` | `pgrep` 找得到候选进程 |
| `isolated_home_seen_by_app` | `ps eww` 里出现 `SIMIGO_HOME=<隔离根>` |
| `operator_attested` | 你回到终端按了回车（或输入了一句说明） |
| `screenshot_present` | `screencapture` 生成的文件字节数 > 0 |
| `generation_observed` | 隔离根 trace 里 `[MLX] session=` 至少 1 行 |
| `real_user_state_write_count_zero` | 前后快照差分 |
| `violation_events_zero` | 同上 |

只有七项全真，它才写 `evidence/m3_stage_b_gui_inference.json`（`real_model_output: true`）
——`verify_batch.py` 读的就是这个文件；否则**不写**，并且会把之前残留的同名文件删掉，
避免留下一个看着像 PASS 的旧文件。

它还会在同一份 trace 里找 `[NODE] backend=` / `[READY]`。这两个只在 `Service.start` 的路径
里发出（`Service.swift:949`、`:989`），所以它们出现就意味着那次操作走的是 **Service 门面**，
不只是 `NativeMLX`——也就是第 8 节偏差 2 会被同一次操作关掉（字段：`service_facade`）。
`[CFG]` 我一开始也当成了标记，walk2 立刻打出假阳性（没人点启动也出现了
`[CFG] source=saved`，因为它来自启动期的 `resolveConfig`），于是收紧成前两个。

**本轮的实测不是“GUI 通过”，而是“装置能用且不会自判通过”。** 我用
`--wait-seconds 6` 跑了一次无人值守自检（`evidence/gui_walk1_walkthrough.json`）：

| 记录项 | 值 |
| --- | --- |
| 候选 | `95224f06…`（与安装候选一致） |
| 隔离根被 app 看到 | true |
| bootstrap | `modelsDiscovered=20`、`schemaVersion=3`、`issueCount=0` |
| 截屏 | rc=1 `could not create image from display`（屏幕录制仍未授予） |
| trace | 文件存在（109 B），`request_events=0`、`generation_events=0` |
| 退出 | AppleEvent quit 生效（进程由在→不在） |
| 非干预 | 写入 0、违规 0 |
| 门面标记 | walk2 用宽的 `[CFG]` → 假阳性 `true`；收紧为 `[NODE] backend=`/`[READY]` 后 walk3 = `false` |
| 判定 | `real_model_output=false`；缺 `operator_attested`、`screenshot_present`、`generation_observed` |
| 门输入文件 | **未生成**（这正是 `install_and_operate` 读作 BLOCKED 的形态） |

**权限到位后的复测（walk4，本轮）**：屏幕录制授予之后，装置必须仍然**不会**自判通过。
`GUI_APP=$B/install_v5/SimiGo.app python3 driver/gui_walkthrough.py walk4 --wait-seconds 6`：

| 记录项 | walk4 实测 |
| --- | --- |
| 启动的候选 | `install_v5/SimiGo.app`，提示里打印 exe `83a88048569f…`，`candidate_identity_match = install_identity_v5_candidate.json` |
| 截屏 | rc=0、5,029,465 B、3840×2160；`screenshot_present=true`（地板 200,000 B） |
| 两张连续截屏 | sha 不同（…8172 vs …c313）→ `consecutive_captures_differ=true`，`uniform_frame_not_excluded=false` |
| 真人操作证明 | `operator_attested=false`（mode = non-interactive） |
| 生成事件 | `generation_events=0`、`generation_observed=false`、`real_model_output=false` |
| 门面标记 | `service_facade_observed=false`（没人点启动，这是预期） |
| 非干预 | 写入 0、违规 0 |
| 门输入文件 | **仍未生成**；`finding` 原文：GUI gate stays BLOCKED |

也就是说：权限到位只修好了装置的**一个**输入（截屏），剩下两个输入（你的操作声明、
真实生成事件）仍然只能由你本人产生——这正是 walk4 要证明的事。

**你要做的两步**（屏幕录制已在 10.1 复探为已授予，不需再申请）：

```bash
cd ~/SimiGo-Agent-Runs/simigo-v2.2.0rc1-layer-forward-calls-20261024
GUI_APP="$PWD/install_v5/SimiGo.app" python3 driver/gui_walkthrough.py walked --operator 你的名字
```

（必须带 `GUI_APP`：不带时装置默认启动旧候选 `install/`（`95224f06…`），见 11 第 17 条。
命令会先把即将启动的 exe sha256 打印出来，你可以核对那是不是你要被归因的那个二进制。）

按提示点菜单栏里的 SimiGo、发一句普通提示、回终端按回车。若你在屏幕上**根本看不到
那个状态项**，就直接在提示里写这句话——那会成为产品侧的关键证据（AX 报的 `x = −1`
可能不是测量假象，而是真被挤到屏外），而不是被记成“你没操作”。

屏幕录制在 os5 之后已复探为**已授予**（`screencapture -x` rc=0、5,249,809 B、3840×2160，
见 10.1），所以 `screenshot_present` 不再是卡点；卡点只剩你的一次真实点击。
权限到位后，单靠“截屏命令没报错”已经不能区分真画面与全黑画面，所以装置里加了
字节地板（`MIN_SCREENSHOT_BYTES = 200_000`）与两张截屏的 sha 对比（只记录不判负）。
我不会拿空白图、别人的截图或 headless 生成去顶替那一张。

> 注意 `product_service_http` 在台账里仍是 `BLOCKED`。它现在有了三份独立证据
> （`60973e08…` 上一批、`95224f06…` 本批次、`83a880…` 本轮门面构建），但台账没被本批次
> 改写，所以计数不动。并表同样需要单独授权。

### 10.4 并表决策的输入：台账里哪些“理由”已经与现行证据冲突

台账不只给状态，还给**为什么不是 PASS**（每条门的 `note` 与 `checks`）。那些理由也有保质期。
`driver/project_ledger_staleness.py`（只读）把台账逐条对到本批次现有判定文件上，把“理由仍然成立”
与“理由已被推翻”区分开——写入 `evidence/ledger_reason_staleness.json`，`ledger_modified=false`：

| 台账门 | 当时记的理由 | 现证据 | 理由是否仍成立 |
| --- | --- | --- | --- |
| `per_layer_forward_calls` | “No per-layer forward-count instrumentation exists in the product.”（`instrumented: false`） | `layer_forward_calls_verdict_v5.json`：同一 exe `83a880…` 上 3,264 事件、L1–L9 全 true | **否**——但“插桩存在”不等于“覆盖全模型路径”，`observed_scope_limit` 已声明专家级 demand 未插桩 |
| `physical_page_return` | “No OS-level page-return evidence was collected…”（`os_level_page_return_evidence: false`） | os3/os4/os5/os5b/os5c 五份 OS 级判定 + 离散度 + 预注册 | **否**——但现有集里无“同一 exe 三次全过”，按新规则仍不够候选级 PASS |
| `product_service_http` | 8 判据中 5 条记为 false（含 `listening_socket_found`、`tls_only_transport`、`authorized_request_completed`、`no_authorization_relaxation`、`unconfigured_authorization_refused`） | 同一组语义在 v5 上全部实测为 true（见 8.2 投影）；门面腿 8 项全过；归因 11 项全 true | **否**——但激活入口仍是受控管理面，不是 GUI |
| `install_and_operate` | “gui_prompt_ran_real_model: false” | 无 `m3_stage_b_gui_inference.json`；装置仍不自判通过 | **是**——理由与当前事实一致 |

两个用法上的区分：

1. **理由 stale ≠ 应该改成 PASS**。它只说明台账里那句“缺什么”已经不描述现状了。
   逐层计数能不能算关，取决于你对“完整 `forward_calls` 覆盖”的范围判定；
   页归还差的是“同一二进制三次全过”的集，不是差的理由。
2. 该文件是**生成**的：所有 `measured_now` 字段都是从名列证据文件里读出来的，没有一处
   是我手抄的结论；若某份证据缺失，它写 `present: false` 而不是默计一个结果。


---

## 11. 过程中被我自己推翻的东西（披露，不粉饰）

1. **我写了一个不存在的 API**：先用 `InstrumentationReportDigest.sha256Hex(data)`，
   该符号不存在（编译失败），改成 CryptoKit `SHA256.hash(data:)` + hex。
2. **判定器初版规则设计错了**：我一度要求"pass 数跨 prompt 相等"，
   那会把 EOS 早停判成违规。改成"同一 prompt 跨 repetition 稳定"。
   这条错误规则在跑之前被改掉，没有产出过任何被判分的数字。
3. **曾评估改第三方依赖**：为插桩去买断 MLX 依赖（9.4 MB checkout + `.package(path:)`）
   被否，理由不是成本，而是**观测点本来就在产品包里**，改依赖会伪造一个更大的 delta。
4. **第一次构建失败**：`-derivedDataPath` 缺 `-scheme`，报错原文保留在
   `logs/build.log` 之前的那次尝试里；改用 `-scheme SimiGo` 后成功。
5. **第一次隔离测试失败**：`tools/run_isolated_tests.sh` 默认找
   `build/test/Build/Products/Debug/SimiGo.app`，不存在 → exit 3。改为
   `--app` 指向同源码的 Debug 产物，并先跑 `build-for-testing` 生成 xctestrun。
6. **比较脚本第一版把误差抹掉了**：它直接读判定器保留 3 位小数的
   `kernel_returned_over_drop`，于是 os4 的 0.4996 被显示成 `0.500`，余量算出 `0.0`。
   改成从字节重算（`(max − anchor) − drop // 2`），os4 的余量才是真实的 `−6,920,060 B`。
   这正好说明为什么不能拿四舍五入后的字段做判定依据。
7. **GUI 探测的前两次跑输了**：`rc_noninterference_diff.py` 收的是位置参数，
   我先按 `--before/--after/--out` 传，退出码 2，快照差分没生成。所以 `gui1`、`gui3`
   两次的 AX 结论可用，但非干预字段是空的；`gui4` 是修正后的权威运行
   （`real_user_state_write_count=0`、`violation_events=0`）。前两次未删除，作为对照留着。
8. **我自己也写过一句会误导的话**：本批次早先沿用了上一批的 “AXPress succeeds”。
   本轮用 `Quit` 做客观察后才确认它只是“受理”。这句已改（§ 10.2）。
9. **“AXPress 被受理但不派发”这个替代措辞也过强**：gui4 的 Quit 测试根本没先打开父菜单，
   菜单项不派发是正常现象，不构成证据。gui5 补做了 `AXShowMenu` 后行为确实一样，
   但仍分不清“AX 通道不行”与“状态项/菜单栏本就不在可见位置”。已改成“未定”（§ 10.2.1）。
10. **我把一串不可靠坐标当成了几何事实**：写成“逻辑屏 1920×1080，x = −1 在屏外”，
    却没有量任何一个参照物。gui5 一试就露：同一批数据里明显可见的菜单项被报成
    `[0, 30]` 尺寸 `[0, 0]`，`Control Center` 无法访问，`SystemUIServer` 的 `menuBars` 为 0。
    结论已降级为“无法从这条通道判定可见性”（§ 10.2.1）。
11. **门面标记一开始选宽了**：把 `[CFG]` 也算作“Service 门面执行过”，结果 walk2 在没人点
    启动的情况下就报 `service_facade_observed=true`——因为 `resolveConfig` 在启动期也会发
    `[CFG] source=saved`。收紧为 `[NODE] backend=`/`[READY]`（只在 `Service.start` 内发出）后
    walk3 复测为 `false`。两个运行都保留，不删。
12. **我把 defaults 写入的责任归错了地方**：上一轮写的是“`Service.start` 会往真实用户 defaults 域写
    SwiftUI 偏好引用”。实际写的是 `selectModel(path)`（`Service.swift:664-683` 里的 `AppConfig.set` /
    `persistReference`）；`start(path:)` 走 `internalStart`，对 defaults 只读不写。v5 的门面 leg 用
    前后六个摘要把这件事测了一遍（确实 0 改），新判定文件按事实写。
    封存的那份旧判定文件里这句原话不动——它是当时认识的存档，不是现在的事实声明。
13. **我以为门面会把 `LOCALB_*` 类型化状态原样留在 `status` 里**，所以 `typedStatus()` 直接从
    `service.status` 里提 token。实测未激活时门面报的是
    `The operation couldn’t be completed. (LOCALBCore.LOCALBStatus error 57.)`——token 在门面这层已经丢了。
    我没有给产品补一个“猜出来的”状态，而是把这条可观测性缺口写进 8.1，并把门面 leg 的 S5 要求
    收紧成“rc=3 / 端口无监听 / 503 / delta 0”，**不要求**那个 token。
14. **清单第一版把新构建目录当成了证据**：`make_evidence_index.py` 的排除规则是按目录名写的
    `{"build"}`，我在 `build_v5/` 里重建候选后就漏了它，生成出 46,948 行索引 /
    46,949 条清单 / 4.6 GiB——`manifest_failed=0` 是真的，但条目数是错的（DerivedData 可从
    第 12 节 3c 的 `xcodebuild` 命令复现，不属于证据）。修法是把两个生成脚本的排除集合扩成
    `{"build", "build_v5"}` 并在文件头写清理由，重生成后回落到 1,699 行 / 1,700 条 /
    299.2 MiB、`manifest_failed=0`。这也说明 self-check 不能只看 `failed=0`。
15. **我第一版把“激活面”的调用点数成了 3**：直接沿用 round-3 那个 grep 口径（只排除函数定义行），
    结果把 `SimiGoLocalBManagementEntry.swift` 里两行注释也算成了调用点。重扫后同时给两个数：
    文本命中 3 / **代码点 1**（`:188`）。判据看的是后者，两个数都留在投影文件里，不二选一。
16. **我把 os4 的运行参数写错了**：第 12 节注释里我说“只有 CANDIDATE 常量指向 `install/SimiGo.app`，
    参数全部默认”。实际不是：脚本默认 0.1 s 采样 / 30 s 基线，os4 是用 `OS_PROBE_INTERVAL=0.01`、
    `OS_PROBE_BASELINE=20` 跑的（raw 里 `interval_seconds=0.01`、`baseline_seconds=20.0` 可查）。
    本轮把候选与输出路径也改成环境变量（`OS_PROBE_CANDIDATE` / `OS_PROBE_RAW`），不再靠改脚本常量
    重跑——“这一轮测的是哪个二进制”应该只出现在记录里，而不是只在源码里。
17. **GUI 装置默认启动的是旧候选**：`gui_walkthrough.py` 里 `APP = install/SimiGo.app`（`95224f06…`）。
    这是在屏幕录制授权到位、我要把人引到那一次操作时才发现的——不修的话，你亲手点的那一下
    会被归给上一个二进制。现在 `GUI_APP=` 可覆盖，提示里打印即将启动的 exe sha256，结果里
    多了与 `install_identity_*` 的匹配字段。walk1–3 的历史记录不动，它们的
    `candidate_exe_sha256` 本来就是 `95224f06…`。
18. **“有字节的截屏”在权限到位后不再是判据**：原来 `screenshot_present` 只看字节数，靠的是没权限时
    `screencapture` 直接 rc=1。权限给了之后，一张全黑的帧也能有几 MB。加了 200,000 B 地板与
    第二张截屏的 sha256 对比；第二张只记录不判负（逐字节相同只能提示“排除不了整帧均匀”，
    把它当新门槛就是我又在挪球门）。
19. **我在 9.3 里替 free-only 做了方向假设**：当时写的是“要换就得预注册一个**更严**的
    free-only 准则”。把五个试验的字节按桶拆开后，方向是反的：inactive 在窗口内净流出，
    free-only 给 0.997–0.998，是**更松**的口径。旧句子不删（它是当时推理的存档），9.4.2 就地
    更正。错得比较幸运：我当时的结论是“先预注册再跑”，而不是“现在就换”。
20. **`keychain_snapshot.py` 的字段名在说谎**：全登录 Keychain 的 2035 条元数据存在键
    `simigo_items` 下，看名字像是“只属于 SimiGo 的条目”。新差分器 `diff_snapshots.py` 拿它做
    全量比对（含 created/modified 时间戳），并另给一份按 service 含 `simigo` 过滤的作用域行；
    快照文件本身一字未改，因为这个字段名已经被旧记录引用。脚本里的命名错误我不动它的数据，
    只在产物里把口径写清。
21. **“并表后应该是 13/3/0/0”这句话把三件事当成了一件事**：三条门的理由都 stale 了，但
    “插桩存在”≠“覆盖全路径”、“有 OS 级证据”≠“候选级三次全过”、“服务腿 8 判据真”≠“GUI 激活可用”。
    所以本轮不再给一个“预期计数”，而是给 `ledger_reason_staleness.json` 让你逐条决定；
    第 10 节表格里那句“预期 13 / 3 / 0 / 0”作为旧记录保留，但它不是我对并表结果的提议。
22. **证据文件会被自己的下一次运行覆盖**：`os_page_return_trial_dispersion.json` 第一版是在
    os5b/os5c 完成**之前**生成的（只有 os3/os4/os5），我跑完五次后直接重生成覆盖了它。旧的
    离散度内容没有单独留存，但它的**输入**（五份 raw + 五份判定）全部在盘且 sha 未变，
    重跑 `compare_os_trials.py os3 os4 os5 os5b os5c` 可再现。这是再生成，不是重判；
    以后这类汇总件应该自带输入 rid 列表，让“旧汇总被新汇总覆盖”这件事从产物里就能核。
23. **我把预注册的修订时刻记错了**：注册件里写 `amended_at: 18:55`，而它在盘上的 mtime 是
    **18:50:14**（早于 os6a 的 18:50:39）——那个 18:55 是我凭印象写的，不是从时钟读的。
    排序结论不变，但错标签保留在原文件里不改（改它等于回写日期），事实在
    `evidence/os_page_return_preregistration_amendment_1.json` 里逐字更正。
24. **“注册后三次全过”与“同一个二进制六次 4/2”必须同时报**：我先看到 os5b/os5c 失败，
    再注册规则、再跑三个全过。这个形状本身就是“跑到干净集为止”的嫌疑，而我不拿它当
    PASS 的理由；它也不反过来构成“产品没还页”的证据——因为 A1–A4、A6–A9 在六个试验里
    全 true，变的只有池那一侧的 peak。我把“评估单元到底算哪个”交给操作者，而不是自己选一个对
    我有利的。

---

## 12. 复现

```bash
B=~/SimiGo-Agent-Runs/simigo-v2.2.0rc1-layer-forward-calls-20261024
R=/Users/mr.simi/Documents/SimiGo

# 1) 归因：补丁能重放到字节一致，且测试改动没有移动安装候选
cd "$B" && python3 driver/verify_patch_attribution.py

# 2) 插桩实跑（安装候选，隔离根）
python3 driver/run_layer_forward_trace.py lf1
python3 driver/verify_layer_forward_calls.py   # exit 0 PASS / 2 BLOCKED / 1 矛盾

# 3) 受影响测试（同源码 Debug 宿主 + 全新隔离根）
cd "$R"
xcodebuild build-for-testing -project SimiGo.xcodeproj -scheme SimiGo \
  -configuration Debug -destination platform=macOS,arch=arm64 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= -enableCodeCoverage NO \
  -derivedDataPath "$B/build/test"
tools/run_isolated_tests.sh --app "$B/build/test/Build/Products/Debug/SimiGo.app" \
  --tag lf2 --evidence-dir "$B/run_isolated_lf2"

# 4) 清单（排除 DerivedData：build/ 与 build_v5/；理由见 make_manifest.py 头部注释）
cd "$B" && python3 driver/make_evidence_index.py && python3 driver/make_manifest.py . \
  && sh driver/verify_manifest.sh

# 3b) Service/HTTP 在新候选上原样重跑（隔离根 g2A/g2B/g2C，端口 8200-8202）
cd "$B"
python3 driver/keychain_snapshot.py evidence/gate_g2_keychain_pre.json
python3 driver/run_service_http_gate.py --evidence-dir "$B/evidence/gate_installed_g2" \
  --roots-prefix g2 --port-base 8200
python3 driver/verify_service_http_gate.py \
  --source evidence/gate_installed_g2/service_http_gate_installed.json \
  --out evidence/gate_installed_g2/service_http_gate_verdict.json
python3 driver/keychain_snapshot.py evidence/gate_g2_keychain_post.json

# 3c) 本轮增量：加受控入口 serve-service → 重建 → 重装（新目录，不动 install/）
#     源码差异：SERVICE_FACADE_LEG.patch（编辑前后源文件在 source_v5/）
cd "$R"
xcodebuild build -project SimiGo.xcodeproj -scheme SimiGo -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$B/build_v5"
cp -R "$B/build_v5/Build/Products/Release/SimiGo.app" "$B/install_v5/SimiGo.app"
cd "$B" && python3 driver/make_install_identity.py \
  --app "$B/install_v5/SimiGo.app" \
  --built "$B/build_v5/Build/Products/Release/SimiGo.app" \
  --out evidence/install_identity_v5_candidate.json

# 3d) v5 候选：五场景原样重跑 + 门面 leg（隔离根 g5*/g6*，端口 8400/8410），前后快照
cd "$B"
python3 driver/snapshot_prefs.py evidence/prefs_v5_pre.json
python3 driver/keychain_snapshot.py evidence/keychain_v5_pre.json
python3 driver/run_service_http_gate.py --evidence-dir evidence/gate_v5 \
  --roots-prefix g5 --port-base 8400 --app "$B/install_v5/SimiGo.app" \
  --build-product "$B/build_v5/Build/Products/Release/SimiGo.app"
python3 driver/run_service_http_gate.py --evidence-dir evidence/gate_v5_facade \
  --roots-prefix g6 --port-base 8410 --app "$B/install_v5/SimiGo.app" \
  --build-product "$B/build_v5/Build/Products/Release/SimiGo.app" \
  --serve-role serve-service
python3 driver/verify_service_http_gate.py \
  --source evidence/gate_v5/service_http_gate_installed.json \
  --out evidence/gate_v5/service_http_gate_verdict.json \
  --facade-source evidence/gate_v5_facade/service_http_gate_installed.json
python3 driver/snapshot_prefs.py evidence/prefs_v5_post.json
python3 driver/keychain_snapshot.py evidence/keychain_v5_post.json

# 3e) 把 401/503 的分工钉到源码行，再用它重生判定（不手改 JSON）
cd "$B"
python3 driver/attribute_proof_status.py --leg evidence/gate_v5/service_http_gate_installed.json \
  --out evidence/service_http_status_mapping_attribution.json      # rc=0：11 项检查全 true
python3 driver/verify_service_http_gate.py \
  --source evidence/gate_v5/service_http_gate_installed.json \
  --out evidence/gate_v5/service_http_gate_verdict.json \
  --facade-source evidence/gate_v5_facade/service_http_gate_installed.json \
  --status-mapping-source evidence/service_http_status_mapping_attribution.json
python3 driver/project_service_http_ledger.py     # 投影里多一个 status_convention

# 3f) v5 上重跑受影响测试与逐层 trace（各自新目录，不覆盖 lf2/install 的旧证据）
cd "$R"
xcodebuild build-for-testing -project SimiGo.xcodeproj -scheme SimiGo \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= -enableCodeCoverage NO \
  -derivedDataPath "$B/build_v5/test"
tools/run_isolated_tests.sh --app "$B/build_v5/test/Build/Products/Debug/SimiGo.app" \
  --tag lf3 --evidence-dir "$B/run_isolated_lf3"
cd "$B" && SIMIGO_TRACE_CANDIDATE="$B/install_v5/SimiGo.app" \
  SIMIGO_TRACE_EVIDENCE="$B/evidence/layer_forward_trace_raw_v5.json" \
  python3 driver/run_layer_forward_trace.py lf3v5
SIMIGO_TRACE_VERDICT="$B/evidence/layer_forward_calls_verdict_v5.json" \
  python3 driver/verify_layer_forward_calls.py \
  evidence/layer_forward_trace_raw_v5.json \
  evidence/install_identity_v5_candidate.json

# 3g) 把 round-3 台账那条门的八个判据投影到 v5（不写台账）
cd "$B"
python3 driver/probe_transport_discipline.py --app "$B/install_v5/SimiGo.app" \
  --evidence-dir "$B/evidence/transport_v5"   # 独立根 t5U1/t5U2，端口 8500/8501
python3 driver/project_service_http_ledger.py  # 输出 evidence/service_http_ledger_projection_v5.json

# 5) 物理页归还：同一套预注册规则，在每个候选上重跑
#    参数就是这三个环境变量；阈值/规则/MIN_LOW/settle 均未动
#    os4 跑在 install/（`95224f06…`），当时是靠改脚本常量指候选的
OS_PROBE_INTERVAL=0.01 OS_PROBE_BASELINE=20 python3 driver/run_os_page_return.py os4
python3 driver/verify_os_page_return.py \
  evidence/os_page_return_raw_os4.json evidence/os_page_return_verdict_os4.json 20 1500
#    rc=1 且 verdict=BLOCKED：A5 矛盾（这是真实结果，不是脚本错误）
#    os5/os5b/os5c 跑在当前候选 install_v5/（`83a880…`），候选与输出路径都是环境变量
for T in os5 os5b os5c; do
  OS_PROBE_CANDIDATE="$B/install_v5/SimiGo.app" OS_PROBE_RAW="$B/evidence/os_page_return_raw_${T}.json" \
  OS_PROBE_INTERVAL=0.01 OS_PROBE_BASELINE=20 python3 driver/run_os_page_return.py "$T"
  python3 driver/verify_os_page_return.py "evidence/os_page_return_raw_${T}.json" \
    "evidence/os_page_return_verdict_${T}.json" 20 1500   # rc=0 PASS / rc=1 矛盾（A5 false）/ rc=2 BLOCKED
done
python3 driver/compare_os_runs.py      # 只并列 os3/os4，不改任何判定
python3 driver/compare_os_trials.py os3 os4 os5 os5b os5c   # 按二进制分组给余量与离散度，不重判
#    把操作者的 free-only 怀疑算一遍（非判据、不重判；用与判定器相同的 anchor/settle）
python3 driver/analyze_os_free_only.py os3 os4 os5 os5b os5c
#    预注册只对“启动时间晚于登记时间”的试验生效；旧试验保留原判定
#    evidence/os_page_return_preregistration_next.json：件内自写 registered_at=18:40，
#    在盘 mtime = 18:50:14（以后者为准）；件内那个 amended_at=18:55 是错的，
#    更正与自我质疑另存于 evidence/os_page_return_preregistration_amendment_1.json（注册件不覆盖）
#    注册后的三次集（候选仍是 `83a880…`）：
bash logs/run_os6.sh                    # os6a/os6b/os6c，同一命令同一参数，日志在 logs/os6*_*.log
python3 driver/compare_os_trials.py os3 os4 os5 os5b os5c os6a os6b os6c
python3 driver/analyze_os_free_only.py os3 os4 os5 os5b os5c os6a os6b os6c
#    判定复现：从留存 raw 重生一次，与在盘判定文件比 sha256（不重跑试验、不重判）
for T in os4 os5 os5b os5c os6a os6b os6c; do
  python3 driver/verify_os_page_return.py "evidence/os_page_return_raw_${T}.json" \
    "/tmp/repro_${T}.json" 20 1500
  shasum -a 256 "/tmp/repro_${T}.json" "evidence/os_page_return_verdict_${T}.json"
done   # 全部 IDENTICAL，结果记在 logs/repro_os_verdicts.log
#    非干预差分（只读两份快照，不碰 defaults / Keychain）：rc=0 CLEAN / rc=1 DRIFT
python3 driver/diff_snapshots.py os5-series \
  evidence/prefs_os5_pre.json evidence/prefs_os5_post.json \
  evidence/keychain_os5_pre.json evidence/keychain_os5_post.json \
  evidence/noninterference_os5_series.json
python3 driver/diff_snapshots.py os6-series \
  evidence/prefs_os6_pre.json evidence/prefs_os6_post.json \
  evidence/keychain_os6_pre.json evidence/keychain_os6_post.json \
  evidence/noninterference_os6_series.json

# 5b) 台账“理由保质期”只读投影（不写台账、不改判定）
python3 driver/project_ledger_staleness.py

# 6) GUI 前置条件（只读探测，不申请授权、不启动候选）
python3 driver/probe_gui_prerequisites.py                              # 当时：屏幕录制缺失
python3 driver/probe_gui_prerequisites.py evidence/gui_prerequisite_recheck_os5.json   # 本轮：已授予

# 7) GUI 可达性：用 LaunchServices 打开候选，测 AX 到底能不能操作它（gui4 为权威）
python3 driver/run_gui_ax_probe.py gui4
#    关键看 A5：按 app 自己的 Quit 项后 stillRunning 仍为 true → AXPress 不派发

# 8) GUI 取证装置：先无人值守自检（不会判过），再等你本人操作
#    注意默认 APP 是旧候选 `95224f06…`，要测当前候选必须显式给 GUI_APP
GUI_APP="$B/install_v5/SimiGo.app" python3 driver/gui_walkthrough.py walk4 --wait-seconds 6
#    自检预期：screenshot_present=true（权限已给）、operator_attested=false、
#    generation_observed=false、门输入 m3_stage_b_gui_inference.json 不生成
GUI_APP="$B/install_v5/SimiGo.app" python3 driver/gui_walkthrough.py walked --operator 你的名字
#    ↑ 这一步只能你本人做：真人在安装候选里点菜单栏、发一句普通提示

# 8b) GUI 追加探测：按正确顺序重做派发测试，并给坐标找参照系（gui5）
python3 driver/gui_ax_probe2.py gui5
#    P3：AXShowMenu → 按 Settings… → windows 仍为 0；P2：菜单栏项几何报 [0,30]/[0,0] → 不可作参照

# 8c) Service 门面的真实入口：谁在生产代码里能触发它（只读 git grep）
python3 driver/inventory_service_facade.py
```

判定器退出码：`0` PASS / `2` BLOCKED / `1` 矛盾证据。本次 `verify_layer_forward_calls.py = 0`。

---

## 13. 治理边界

* 未 push、未 merge、未创建 tag；
* 未修改任何封存的历史证据（RC1 / G2 / round2 / round3 台账）；
* 未修改 `acceptance_report.json`，未手改任何 JSON 让报告"看起来一致"；
* 未关闭 TLS、未放宽 proof 校验、未改 Service/HTTP 路径；本批次的 Service/HTTP 结果是
  **原样重跑既有五场景门**，不是对它的代码修改；
* 未做 GUI 操作，未替任何人申请或勾选屏幕录制/辅助功能权限（只做了只读的权限探测，
  见 10.1；本轮复探发现权限已被机器主人授予，但那个开关不是我动的）；**未向屏幕发送任何
  合成的鼠标/键盘事件**（在用户前台环境里乱发点击是危险的）；
* 新增的 `driver/gui_walkthrough.py` 只在七个条件全真时写门输入文件，条件不全时
  **主动删除**同名残留文件；本轮自检（walk1–walk4）因此没有留下任何 `real_model_output: true`，
  也没有生成 `evidence/m3_stage_b_gui_inference.json`；walk4 是在权限已到位后跑的，
  它仍然判 false；
* gui5 确实向该 app 发过 AX 动作（`AXPress` / `AXShowMenu`），但那是 AX API、只指向
  这一个进程，且实测无可见效果；**仍未发送任何 CGEvent 鼠标/键盘事件**，也未向用户前台
  应用投射任何输入；
* 物理页归还：**未调阈值、未改规则、未重新定义 A5**；os4 按旧阈值判 BLOCKED；
  第 9.3 节当时对“A5 结构性偏差”的解释（inactive 虚增分子）**已被 9.4.2 的字节分解推翻**，
  两个假设都没被拿当改判理由；本轮只把它们当“需要预注册重复试验”的线索；
* 预注册只对**启动时间晚于注册**的试验生效（注册件 mtime 18:50:14 < os6a 启动 18:50:39）；
  os3/os4/os5/os5b/os5c 的判定一字未改，也没被新集“平均”掉或覆盖掉；free-only **未被采纳为判据**
  （实测它更松）；“评估单元”的取舍留给操作者，见 9.4.4 与
  `evidence/os_page_return_preregistration_amendment_1.json`；
* os4 的判定器增加了 `raw_file` / `raw_sha256` 两个溯源字段，未改变任何已有字段与判定，
  且已用重跑证明（除新键外逐键相同）；
* **没有改动上一批封存的 os3 证据**；os3 的 raw 只被只读地算了一次 sha256，写在本批文档里。
* 本批次的 PASS **按二进制分别绑定**，不得串用：逐层计数与 Service/HTTP 五场景/门面腿/投影
  成立在 `83a88048569f…`（`install_v5/`）；早期的 `95224f06…`（`install/`）与 `60973e08…`、
  `cc6fe63c…` 的结果不构成对新候选的证明，反之亦然。本轮**没有再改产品源码**，
  所以 `83a880…` 仍是当前候选。
* 运行时副作用：每次跑安装候选都会在批次根落一个 `default.profraw`（插桩构建的 LLVM
  profile 数据，本轮 8,020,912 B、mtime 随最后一次运行）。它是**运行副产物而不是证据**，
  但我不删它（删了反而丢掉“真的跑过这个二进制”的痕迹），清单里按实际字节收录并列行。
* 本轮收尾时的清单计数：`EVIDENCE_INDEX.md` 1,876 行、`MANIFEST_SHA256.txt` 1,877 条，
  `sh driver/verify_manifest.sh` 输出 `manifest_ok=1877 manifest_failed=0`。这两个数字会
  随新增留痕文件变动，以重生成后的实际输出为准（本节上一版写 1,876 条，是
  `logs/repro_os_verdicts.log` 落盘前的计数）。
