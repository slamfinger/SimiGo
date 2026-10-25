# SimiGo v2.2.0rc1 — Service/HTTP gate batch (simigo-v2.2.0rc1-service-http-20261024)

本批次只做两件事，均由操作者单独授权、互不代表对方结论：

1. **Service/HTTP 路径修复与重新取证（授权路径 1）**：新增受控的
   `prepare / activate / pair-issue / pair-approve` 入口，只调用既有包 API；
   重建并安装新候选；在**新安装候选**上重跑五场景门。
2. **round-2 注记修正**：把无留存证据支持的注记改为“无留存证据支持”，
   改生成逻辑→重新生成→重跑验证器与清单。

两项授权都不改变 GUI 普通提示、物理页归还、逐层 `forward_calls` 的独立判定。

---

## 1. 结论先行

| 事项 | 本批次结果 | 依据 |
| --- | --- | --- |
| Service/HTTP 门（新安装候选） | **PASS**（附两条公开偏差，见 §6） | 五场景各跑 2 次，均一致：200 / 401 / 401 / 401 / 503 / rc=3 |
| 受影响测试（App 套件） | **PASS** 208 executed / 14 skipped / 0 failures | `run_isolated_r5/isolation_run_r5.json` |
| 非干预（文件 + Keychain 元数据） | **PASS** 0 真实用户状态写入、0 违规、0 Keychain 增删 | `evidence/gate_installed_r2/*` |
| 普通启动不自动激活 | **PASS** 无 `localb/`、无监听、无 checkpoint | `evidence/ordinary_launch_no_auto_activation.json` |
| round-2 注记修正 | **DONE**，判定不变（仍 `BLOCKED`） | `REPORT.md` §10（旧批次）+ `evidence/round2_note_correction_*.json` |
| **v2.2.0rc1 总体** | **BLOCKED**（未变） | GUI 普通提示、物理页归还、`forward_calls` 仍独立未闭合 |

---

## 2. 源码差异：相对产生 `cc6fe63c…` 的冻结树

基线：`f18d65f8f312ffbb837fdf5e07125af044833854`（分支 `localb-b3-closure-20261016`）。
上一轮冻结树 = 该 HEAD + 13 个改动路径（`RC_SOURCE_FREEZE.json`，产生安装二进制
`cc6fe63c…`）。本批次逐文件比对（`evidence/source_delta_vs_rc_tree.json`）：

| 路径 | 变更 | 前摘要 | 后摘要 |
| --- | --- | --- | --- |
| `SimiGo/Headless/SimiGoLocalBManagementEntry.swift` | 新增 | — | `f20f2b2ec616…` |
| `SimiGo/App/StatusBarCoordinator.swift` | 修改（+20 行调用点） | `4537cf64eada…`（HEAD 版本，冻结树内为原始文件） | `937edb912fef…` |

其余 13 个冻结路径（LOCALBCore 源码与测试、SimiGoRuntimeContract、pbxproj、
CloudBackend、G1G3Entry、App 测试、TransportWiringTests）**逐字节一致**。因此本轮
没有改包源码、没改工程文件、没改既有测试。

新增入口的作用与边界（源码注释原样记录）：

* `SIMIGO_LOCALB_MGMT ∈ {prepare, activate, pair-issue, pair-approve, serve}`，
  强制要求隔离的 `SIMIGO_HOME`，缺少即 fail-closed（`rc=2`）。
* `prepare` → `LOCALBHostBootstrap.prepareFirstRun`；`activate` → 必须提交操作者
  记录的 checkpoint，再 `activateInitialSetup` + `LOCALBHostRuntime.persistTrustedCheckpoint`。
* `pair-issue` → `issueCredential(mode: .strictHeadless, expectedClientPublicKeyRaw:)`；
  `pair-approve` → `preparePairing` + `approveAndRegister(operatorApproved: false, …)`。
* `serve` → `NativeMLX.startWithLOCALB(info, port, localbTransportIdentity: nil,
  localbRequestAuthorization: nil)`，与 `Service.start` 内部同一调用；TLS 决策仍走
  `LOCALBTransportPolicy`（缺失身份即 fail-closed）。
* 普通启动（无该环境变量）不进入任何管理角色；`applicationDidFinishLaunching`
  仍按原路径建状态栏与 bootstrap。

补丁与新增文件原文：`SERVICE_HTTP_SOURCE_DIFF.patch`、`source/`。

---

## 3. 构建与安装身份（新候选）

| 项 | 值 |
| --- | --- |
| 构建 | `xcodebuild -configuration Release -derivedDataPath <batch>/build build` → `** BUILD SUCCEEDED **` |
| 安装候选 | `<batch>/install/SimiGo.app`（与 Release 产物 `diff -r` 完全一致，`installed_equals_built=true`） |
| 可执行文件 SHA-256 | `60973e086f12583a20a6b578de33e678bd4a7e1846a7b6cd0084cd845eae90cd`（105,731,152 B） |
| Bundle 树摘要 | `243ac13fb77bd53ae5c6f8cd3f7832d1a28abc93850566e0c9878a60c38311ae`（19 个文件） |
| Bundle ID / 版本 | `SwiftUI.SimiGo` / 2.2.0 (26) |
| 签名 | ad-hoc + hardened runtime，`codesign --verify --deep --strict` rc=0；CDHash `e11e87be1865957971bb21dd4372b2b2298da9f7` |
| Gatekeeper | `spctl -a -vv` = rejected（本地未公证 RC 的环境约束，非构建失败） |
| dylib 身份 | bundle 内仅 1 个 Mach-O，无嵌入 framework/dylib；48 个链接库全部来自 OS，逐个路径已记录，均非候选自带 |

完整记录：`evidence/install_identity_new_candidate.json`。

**与旧候选的关系**：旧二进制 `cc6fe63c…` 的任何结果都未用于本轮 Service/HTTP 结论；
本轮所有五场景证据均出自 `install/SimiGo.app`（`60973e08…`）。

构建过程如实保留一次失败：首次 `build-for-testing` 未带项目一贯的
`-enableCodeCoverage NO CODE_SIGNING_ALLOWED=NO`，`yyjson` 动态库在覆盖率插桩下
链接失败（`___llvm_profile_runtime` 未定义），见 `logs/build_for_testing.log`
（`BUILD_RC=65`）。改用项目既有参数后 `BUILD_RC=0`（`logs/build_for_testing_r5.log`）。
源码与参数均未为通过而放宽。

---

## 4. 受影响的测试

* **App 套件**（唯一被本轮源码改动影响的测试面）：`tools/run_isolated_tests.sh`
  全新隔离根，`208 executed / 14 skipped / 0 failures`，`exit_code=0`；
  `real_user_state_write_count=0`、`distinct_violation_count=0`；
  xctestrun 只重写三个隔离根；`LOCALBRequestAuthWiringTests`、
  `ExternalAdoptionInferenceE2ETests`、`SimiGoG1G3HeadlessEntryTests` 均 passed。
  证据：`run_isolated_r5/`。
* **包测试未重跑**：本轮包源码零改动（§2 逐字节比对），因此上一轮的
  LOCALBCore `41/0` 与 SimiGoRuntime 契约 `85/0` 仍是适用证据；本批次**不**把它们
  记作本轮新跑结果。
* **无新增产品测试**：新增入口是受环境变量约束的产品代码，其行为由 §5 的端到端
  证据直接覆盖；没有为了让门通过而添加只测入口的用例。

---

## 5. Service/HTTP 五场景（安装候选，两次独立运行）

两次运行使用不同隔离根与端口（r1: 8100–8102；r2: 8110–8112），结果一致。

| 场景 | 操作者预期 | r1 实测 | r2 实测 | 证据 |
| --- | --- | --- | --- | --- |
| 合法授权 + 有效 proof | 200 | **200**，`content="SERVICE-HTTP-OK"`，`id=chatcmpl-…` | 同 | `evidence/gate_installed/A6_authorized_body.json` |
| 合法请求的生成因果 | 经过正常派发并记录模型调用数 | trace 行数 **4 → 12（delta 8）**；客户端观测 SPKI 与 host 自身证书一致（pin 命中） | delta 同为 8 | `A6` + `A3_serve` + `service_http_gate_installed.json` |
| 无效 proof（伪造签名） | 503（“按当前门槛约定”） | **401** `LOCALB_CLIENT_REQUEST_SIGNATURE_INVALID`，delta **0** | 同 | `A7_negative_probes.json` |
| 无效 proof（缺 proof 头） | 503 | **401** `LOCALB_CLIENT_PROOF_MISSING`，delta **0** | 同 | 同上 |
| 无效 proof（challenge 重放） | 拒绝 | 首次 200（delta 7），重放 **401** `LOCALB_CLIENT_CHALLENGE_INVALID`，delta **0** | 同 | 同上 |
| 信任激活缺失（prepare 但未 activate） | 生成前拒绝、失败关闭 | listener 已绑定、`/health` 200；challenge 路由与受保护路由均 **503** `LOCALB request authorization is not configured`，delta **0**，无 trusted checkpoint | 同 | `B2_serve_noauth.*`、`B3_noauth_probe.json` |
| 授权完全缺失（全新根，未 prepare） | 拒绝、不监听 | `serve` 退出 **rc=3**，`localb_status=LOCALB_TRANSPORT_IDENTITY_MISSING`，端口无监听（connection refused） | 同 | `C1_serve_unprepared.*` |

判定由脚本从磁盘派生，不手写：`driver/verify_service_http_gate.py` →
`evidence/service_http_gate_verdict.json`（`overall: PASS`，五场景逐项 true）。
“生成因果”不是靠响应里有字就算：请求由外部 Python 客户端经 TLS 发到真实监听器，
授权后 trace 行数增加 8，负向三种全部为 0。

### 非干预与隔离（r2 括号）

* `rc_noninterference` 前后快照差分：`real_user_state_write_count=0`、
  `violation_events=0`、`reference_changes=0`（`evidence/gate_installed_r2/snapshot_diff.json`）。
* Keychain 元数据（只读属性，不含密钥）：pre/post 各 2035 项，**新增 0 / 删除 0**；
  既有 1808 项 `com.simigo*` 遗留项原样保留，未清理（`keychain_pre/post.json`）。
* 所有 LOCALB 身份只写 `<隔离根>/home/localb/*.keychain-db`，未写真实登录钥匙串。
* 普通启动（无管理环境变量，隔离根）45 秒内：未创建 `home/localb`、无监听、
  无 checkpoint → **不自动激活**。

---

## 6. 与授权书预期表的偏差（公开，不粉饰）

1. **无效 proof 的语义是 401，不是 503。** 503 只对应
   `HTTPServerError.localbAuthorizationUnavailable`，即“根本没有配置 LOCALB 授权”，
   已在场景“prepare 但未 activate”实测为 503。已经配置授权、但 proof 无法验证的请求
   由 proof 门以 401 拒绝。**产品没有为对齐表格改成 503**：那会把“未激活”与“proof 错”
   混为一谈。若操作者要求字面 503，本门应视为仍 `BLOCKED`。
2. **服务腿走的是 `NativeMLX.startWithLOCALB`，不是 `Service.start` 门面。**
   两者在 HTTP/LOCALB 路径上调用相同，但 `Service.start` 会经
   `AppConfig.persistReference` 向真实 `UserDefaults`（`SwiftUI.SimiGo`）写入引用，
   与本批次的非干预要求冲突。因此“Service 门面自身”未被行使，被行使的是它驱动的
   同一条 HTTP/LOCALB 路径。这一点不满足“必须通过 Service 门面”的更严格读法。
3. **激活面是产品内的环境变量管理入口，不是 GUI 按钮。** GUI 普通提示仍 `BLOCKED`，
   本批次没有把管理入口的行为算作 GUI 已通过。
4. **配对是 strictHeadless 模式**（`operatorApproved=false`、无人工授权引用），
   符合该模式语义，但不等于“有人工确认的配对 UI”。

---

## 7. round-2 注记修正（旧批次，已授权）

* 旧批次 `simigo-v2.2.0rc1-local-acceptance-20261024` 的 `product_service_http.note`
  由 `driver/verify_batch.py` 生成；本次改为 `service_http_note(probe)`，从
  `evidence/m3_stage_c_probe.txt` 的留存内容生成，不再手写断言。
* 旧注记声称 round 2 在运行 pid 上 lsof 观测到 ephemeral 端口、TLS-only 行为、
  伪造 proof 的 POST 返回 503 —— 批次内**无留存证据支持**（唯一留存 stage-C 记录是
  `listening_socket_found=0` / `probe_result=NO_SOCKET_WINDOW OBSERVED`）。
* 更正记录写在旧批次 `REPORT.md` §10（更正原因、原注记逐字、更正后措辞、证据缺口）。
* 判定不变：`product_service_http` 仍 `BLOCKED`，gate 数 16、计数
  12 PASS / 3 BLOCKED / 0 FAIL / 1 NOT_INSTRUMENTED 与更正前一致；
  `verdict_changes={}`、`check_set_changes=[]`。
* 摘要变化（`evidence/round2_note_correction_{before,after}.json`）：

| 文件 | 更正前 SHA-256 | 更正后 SHA-256 |
| --- | --- | --- |
| `REPORT.md` | `af535a34b60e…` | `02b48f6a2926…` |
| `acceptance_report.json` | `9bd75d710791…` | `57de11e7f0a2…` |
| `driver/verify_batch.py` | `5c58862e9bf1…` | `ada9756dace7…` |
| `MANIFEST_SHA256.txt` | `97e952cbcb4a…` | `750e74639ebb…` |

清单已用 `driver/make_manifest.py` 重新生成（89349 条），`driver/verify_manifest.sh`
复验 `manifest_ok=89349 manifest_failed=0`。round-2 原始日志、原始快照与已封存
RC1/G2 证据未改动。

### 证据清单口径（本批次）

`MANIFEST_SHA256.txt` 共 576 条，`driver/verify_manifest.sh` 复验
`manifest_ok=576 manifest_failed=0`；`EVIDENCE_INDEX.md` 另给“结论 → 证据”映射
与逐文件摘要。清单一律排除三类可再生/临时内容，并在
`driver/make_manifest.py` 的文档字符串里写明：`build/`（DerivedData，可由记录的
xcodebuild 命令重建）、隔离根（`m3*`、`*/isolation`，驱动创建后即弃）、以及清单
自身与它自己的两份日志。安装候选 `install/SimiGo.app`、全部 `evidence/`、
`logs/`、`driver/`、`run_isolated_r5/`（含 xcresult）都在清单内。

---

## 8. 仍然 BLOCKED / NOT_INSTRUMENTED（独立，不随本门关闭）

1. **GUI 普通提示**：仍需本机屏幕录制与辅助功能授权，并在安装候选上完成一次真实
   用户输入。本批次没有触碰，也未用 headless 生成代替。
2. **物理页归还**：仍缺 OS 级内存证据；进程退出或 RSS 变化不算归还证明。
3. **逐层 `forward_calls`**：仍未插桩，不得填估算值。
4. **v2.2.0rc1 完整产品验收**：仍 `BLOCKED`。Service/HTTP 由 `BLOCKED` 转为 `PASS`
   （在 §6 两条偏差成立的前提下）不改变这一点。

---

## 9. 治理边界

未执行 `git commit` / `push` / `merge` / `tag` / `reset --hard` / `git clean`；
未修改封存的 RC1/G2 证据与 round-2 原始日志/快照；未清理真实 `~/.simigo`、
Application Support 或登录钥匙串中的任何项。工作树仍停在
`f18d65f` + 上述 2 个文件（1 新增 1 修改）+ 上一轮 13 个冻结路径。
