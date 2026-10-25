# SimiGo `v2.2.0rc1` 本机候选验收报告（round 2）

- 批次目录：`/Users/mr.simi/SimiGo-Agent-Runs/simigo-v2.2.0rc1-local-acceptance-20261024`
- 生成时间：2026-10-24（本机 +0800）
- 判定机器：`driver/verify_batch.py` → `acceptance_report.json`（16 项门槛；退出码 1 = 至少一项 FAIL）
- round 1 的全部原始文件保留在 `round1_snapshot/`（无损、未改写）

## 0. 一句话结论

本轮安装的那个确切二进制（`dacf2fc3…`）确实走过了构建、测试、安装、ES→IS→ES2 续算与非干预取证：研究链、受控差异、7 条负向对照、资源生命周期、包/应用测试、身份复算全部 PASS，round 1 唯一的 FAIL（资源生命周期）已修复。但结论**仍不是"可以发布"**，而且比 round 1 多出一条新的硬发现：审计 Keychain 时发现候选在**真实登录钥匙串**里每次 headless 运行都留下 3 个条目（跨 round 1+2 共 45 个，服务名按 `<SIMIGO_RUN_ID>` 命名空间隔离，生产凭据未被改动）。按任务书"越界写入即对该验收失败关闭"的规则，这项记 **FAIL**。此外 GUI 普通提示、安装版受保护路由、`physical_page_return` 仍 BLOCKED，逐层 `forward_calls` 仍 NOT_INSTRUMENTED。

## 1. 这个版本能否从所记录的源码与依赖构建？

能，且源码状态是**未提交但可重建**的：

| 项 | 值 | 证据 |
|---|---|---|
| 产品仓 / 分支 / HEAD | `SimiGo` / `localb-b3-closure-20261016` / `f18d65f8f312ffbb837fdf5e07125af044833854`（ahead 3, behind 0） | `RC_SOURCE_FREEZE.json` |
| 工作树 | 5 项：3 modified（`SimiGoG1G3Entry.swift`、`SimiGoESISDatabase.swift`、`project.pbxproj`）+ 2 untracked（`SimiGoSettlementIdentityBinding.swift` 及其测试） | 同上 + `RC_SOURCE_DIFF.patch`（16,845 B）+ `source_snapshot/` |
| Lab 源 | `SimiGo-Lab` `main` `e7f6385…`（96 项脏） | `SOURCE_MAPPING.md` |
| 工具链 | `swift`/`xcodebuild`/macOS 版本逐项记录 | `RC_SOURCE_FREEZE.json.toolchain` |
| 模型 | `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit` @ `6e302ea604ad9ab206367e2c501d1571023e7b6d`，17 个文件逐文件摘要**本轮重算** | `RC_MODEL_IDENTITY.json`（`reused_from_history=false`） |
| 依赖 | 13 个已解析包（全仓 `Package.resolved` 汇总）+ 3 个声明依赖 | `RC_IDENTITY.json.dependencies` |
| 构建 | Release `xcodebuild` → `** BUILD SUCCEEDED **` | `logs/release_build.log`（round1 的失败尝试保留为 `logs/release_build_attempt1_failed.log`） |

本轮为本轮专门修了一处产品缺陷并**重建**了 Release：round 1 的 `memprobe` 在 Release 下永远无法进入挂起（`suspendIdleTimeoutOverrideSeconds` 只在 `#if DEBUG` 存在），导致资源生命周期观测恒为 false。修法是让探针**等待生产自适应空闲窗口**（240–360 s，floor 240 s）再调用**未修改**的 `suspendIfIdle()`，不使用任何计时 seam（`suspend_window_source=production adaptive idle floor/cap; no release-build override`）。verify 里为此加了反作弊检查 `no_release_timing_seam` + `waited_out_production_idle_floor`。

## 2. 安装的究竟是哪一份实际二进制？

| 项 | 值 |
|---|---|
| 安装路径 | `<batch>/install/SimiGo.app`（独立路径，未覆盖既有安装） |
| Bundle | `SwiftUI.SimiGo`，`2.2.0` / build `26`，19 个文件，bundle tree `bd520f47…` |
| 可执行文件 | `dacf2fc353114088f7fd4079d8e75e8094c4af394c74d0809ccb2d65294dff1c`，104,981,040 B，LC_UUID `EE3B7D96-C979-33B5-B255-B708C4792C80` |
| 包 | `install/SimiGo-v2.2.0rc1.dmg`，`ad959f72c77bb9bf8990f51f642c9f27b22c4c0b2b5ca9273ea78ca356e5bded` |
| 签名 | `codesign --verify`: valid on disk + satisfies Designated Requirement；`spctl`: **rejected**（本地侧载、未公证，环境约束而非构建失败） |

证据：`evidence/m3_install_identity.json`（含可复现的 bundle tree 算法说明）、`evidence/m3_install_identity.txt`、`evidence/build_product_identity.txt`。
**构建产物、测试产物、安装后重新签名的产物是分开记录的**：DMG 内 exe `603bc824…` vs 安装后 `dacf2fc3…`，UUID 不变——安装后重新签名改变了 exe 摘要，报告不把两者混为一谈。

## 3. GUI 与普通推理是否在安装后的包中真实运行？

**部分成立，GUI 一段 BLOCKED。**

- 安装版可执行文件被真实拉起并运行：`ps` 显示进程、`lsof txt` 指向 `install/SimiGo.app/Contents/MacOS/SimiGo`、`ps eww` 显示三个隔离变量**被进程实际解析**（`SIMIGO_HOME` / `SIMIGO_CACHE_ROOT` / `SIMIGO_STATE_GRAPH_STORE` 全指向 `<batch>/m3/`）。
- bootstrap：`modelsDiscovered=20`、`schemaVersion=3`、`issueCount=0`；IS 表含 `execution_states`/`settlements`/`settlement_bindings`/`dependency_edges`。
- 退出与重启：SIGTERM → `quit_result=exited`；同一 bundle 再启动成功并复用持久化数据。
- **普通推理**在安装版里是真的：M4 的 ES1 与 ES2 都由**这个**安装版可执行文件跑出 `RESULT=hello` / `RESULT=delta9-U2`（`m4/*/binary_identity.txt` 绑定 `exe_sha256=dacf2fc3…`），memprobe 的 warm/resume 两次生成也都是真实模型输出。
- **GUI 提示输入**：8 次驱动尝试（JXA 激活 / 菜单树 / `AXPress` / CGEvent HID 点击 / `CGWindowList` / `screencapture` / 键入 / 菜单点击）全部落到"0 窗口"，`screencapture` 报 `could not create image from display`。宿主机未给驱动 **Screen Recording** 与 **Accessibility** 授权，这是取证环境限制，不是 App 崩溃（进程存活、状态栏项存在）。因此该腿标记 **BLOCKED**，不用进程退出或 headless 生成去冒充 GUI 推理。

证据：`evidence/m3_stage_a_process.txt`、`evidence/m3_stage_b_gui_inference.json`（含 `blocked_reason`、`minimum_unblock`）、`m3b/`（stage B 隔离根）。

## 4. Service/HTTP 是否使用正常且符合授权要求的产品路径？

**否——安装版进程的受保护路由 BLOCKED，但这一次有实质进展：真的碰到了产品 HTTPServer。**

| 观测 | 值 |
|---|---|
| 监听 | 运行中的安装版 pid 上 `lsof -nP -a -p <pid> -iTCP -sTCP:LISTEN` → `TCP *:62566 (LISTEN)`（`listening_socket_found=1`） |
| 明文 | `POST /v1/chat/completions` 无 proof → `curl: (52) Empty reply from server`（TLS-only，明文不被服务） |
| TLS + 未授权路由 | `GET /health` → **200** `{"status":"ok","model":"…Qwen3-Coder-30B-A3B-Instruct-4bit"}` |
| TLS + 受保护路由 + 伪造 proof | `POST /v1/chat/completions` → **503** `LOCALB request authorization is not configured`；`authorized_request_completed=0`，`authorization_relaxed=0` |

503 的来源是 `HTTPServer` 的 `localbAuthorizationUnavailable` 守卫；请求授权只能由已验证的 LOCALB host 上下文配置，而写入 trusted checkpoint 的"激活仪式" `persistTrustedCheckpoint` 在 **App target 里的调用点为 0**（只有测试调用）。也就是说：**这个候选不提供任何产品面去激活 host**，安装版必然以未激活态运行，受保护路由在任何合法客户端下都拿不到授权。要 PASS 只有两条路——放宽守卫（禁止）或补一个产品激活面（本轮未做，因为那不是取证动作而是产品功能变更）。

同一份产品代码在**激活后**是能服务授权请求的：产品自己的测试（round 2 测试二进制）里
`testDefaultHostResolutionServesAuthorizedRequests`（真实 TLS 固定 SPKI + 每请求 V2 proof）、`testDefaultHostResolutionFailsClosedBeforeActivation`（未激活必须 fail-closed，正好对应我们观测到的 503）、`testSignedBodyReachesInferenceEndpoint`、`testTamperedBodyIsRejected`、`testChallengeIsSingleUse`、`testMissingProofHeadersAndUnconfiguredAuthorizationFailClosed`、`testUnknownRoutesFailClosedAndOpenRoutesStayOpen`、以及 `ExternalAdoptionInferenceE2ETests.testAdoptedEndpointConfigDispatchesInferenceThroughProductionRuntime` **全部 passed**。

证据：`evidence/m3_stage_c_probe.txt`、`evidence/localb_authorization_path.txt`（自动生成：探针结果 + 调用点 grep + 上述用例逐条结果）。

最小解除：给产品加一个合法的激活/管理面（运维 CLI 或等价物）对隔离 host 目录执行 `persistTrustedCheckpoint`，并用一次性 Keychain 里的配对客户端发起带 V2 proof 的请求。

## 5. IS 恢复后的值是否有因果证据参与 ES2 的真实生成？

有，两轮独立实验都有。

| | m4a | m4b |
|---|---|---|
| ES1 目标 / 生成 | `hello` / `RESULT=hello` | `delta9` / `RESULT=delta9` |
| ES1 PID → ES2 PID | 44187 → 44220 | 16325 → 16347 |
| ES1 已退出 | `ES1 exited before ES2 - OK` | 同 |
| ES2 从 IS 恢复值 | `hello` | `delta9` |
| 摘要 / 有效性 / 绑定 | verified / valid / `ok` | 同 |
| 携带值的环境通道 | `[]` | `[]` |
| 恢复值进入 prompt | true | true |
| 真实续算输出 | `RESULT=hello-U2` | `RESULT=delta9-U2` |
| 反事实基线 | `world`（≠ 目标） | `hello`（= m4a 的目标，≠ delta9） |
| ES2 cache identity | 与 ES1 不同（fresh） | 同 |
| U2 结算摘要 | `bccf6ef6…` | `176d045d…` |

**受控差异**：两次运行只改 ES1 的结算值，ES2 没有任何目标值环境变量，输出随 IS 中的值变化（`RESULT=<值>-U2`），这是**因果**而非环境注入。m4b 有一次**作废**的重跑（忘记导出 `SIMIGO_EXPERIMENT_TARGET=delta9`，得到 hello/hello-U2），原样保存在 `m4/m4b_wrong_target_round2/` 并附 `NOTE.md`，未覆盖任何历史。

负向对照（全部在生成前拒绝，`generation_call_count=0`）：settlement 缺失 `rc=6`、摘要篡改 `rc=6`、结算作废 `rc=6`、模型身份不匹配 `rc=6`、非法 role `rc=2`、缺参 `rc=2`、值泄漏进 consume 环境 `rc=7`。

## 6. 测试与实验是否非干预真实用户状态？

整体：**产品状态零写入**；有一个非产品的 Finder 元数据残留，已单独分析并做了收紧复测。

| 项 | 值 |
|---|---|
| 包测试 | `swift test --package-path Packages/SimiGoRuntime` → **85 executed / 0 failures**（`logs/pkg_tests.log`，含新增身份绑定 8 例） |
| App 隔离套件 | `tools/run_isolated_tests.sh` → **207 executed / 14 skipped / 0 failures**，107 s，fresh root，0 用户态写入，0 违规（`run_isolated_m1d/`、`logs/isolated_m1d.stdout.log`） |
| 全批次 pre/post | 真实根 1 个变更：`~/.simigo/.DS_Store`（24,580→34,820 B）；`~/.simigo` 的 sqlite3 / WAL / SHM / prefix-pool / branch-checkpoints / manifests / logs、`Application Support/SimiGo`、HF reference 根 **0 变更** |
| bracket 复测 | 紧包围一次安装版启动的前后快照：**0 变更**（同一 `dacf2fc3…` 二进制），`.DS_Store` 字节数与 mtime 完全不变 |

`.DS_Store` 的归属：文件头为 `Bud1` + `bwsp` 视图块（Finder 目录视图元数据，不是产品负载）；改写时刻 `01:30:44` 落在 stage A 已退出、m4a 未起跑的空档，**当时没有本候选进程存活**。原始差分不做任何 allowlist 遮掩（`real_user_state_write_count` 仍如实为 1），归因与重测条件写在 `evidence/noninterference_residual_analysis.md`；`verify_batch` 在判定时**读取文件字节**确认 Bud1 头，并额外要求 bracket 复测为 0 且用的是同一安装版二进制。


### 6.1 Keychain（本轮新发现，判定 FAIL）

文件系统快照只覆盖文件；LOCALB 的传输身份落在 **Keychain**，而 `SIMIGO_HOME` 无法重定向 Keychain。审计结果（`evidence/keychain_noninterference.json`，只读元数据、不读密文、不删除任何条目）：

| 项 | 值 |
|---|---|
| 本批次按 run 命名的条目 | **45**（round 1 18 + round 2 27；每个 headless 进程 3 个：index / key / certificate） |
| 服务名 | `com.simigo.headless.g1g3.<SIMIGO_RUN_ID>.<uuid8>`（`SimiGoG1G3Entry.startIsolated` 里 `LOCALBTransportIdentityStore(...).loadOrCreate()`） |
| 时间戳 | `20261023164743…165137`（round 1）与 `20261023172630…173622`（round 2），与 m4a/m4b/memprobe 的运行时刻逐一对齐 |
| 生产凭据 | `com.simigo.localb-transport-identity`、`com.simigo.localb-production-signer`：创建时间 `2026-10-16T14:23:56Z`，**未被本次运行改写** |
| 测试套件条目 | `com.simigo.tests.localb-*` 共 1,646 个（历史累积；`tools/run_isolated_tests.sh` 不创建临时 keychain） |
| 影响面 | 研究链的数值、结算与摘要不依赖身份存放在哪个 service，m4/m4b 结论不受影响 |

按任务书「任何路径无法被隔离，或出现越界写入，应停止受影响验收并失败关闭」，这项记 **FAIL**，而不是用"只是新增、没改生产凭据"来降级。最小修复：headless/实验身份改跑在一次性 Keychain（`security create-keychain` + 作用域内 `SecItemAdd`，teardown 删除），隔离测试运行器同样改为临时 Keychain。

## 7. 各项门槛判定（`acceptance_report.json`，11 PASS / 3 BLOCKED / 1 NOT_INSTRUMENTED / 1 FAIL，共 16 项）

| 门槛 | 判定 | 关键依据 |
|---|---|---|
| `source_and_model_frozen` | PASS | `RC_SOURCE_FREEZE.json` + `RC_MODEL_IDENTITY.json` |
| `build_and_package` | PASS | BUILD SUCCEEDED、DMG、bundle 身份、codesign valid（Gatekeeper rejected 仅记录） |
| `install_and_operate` | **BLOCKED** | 安装版启动/隔离/退出重启/bootstrap 全过；GUI 提示腿未取证 |
| `product_service_http` | **BLOCKED** | socket + TLS + 503 已取证；无授权完成 |
| `research_chain_primary` | PASS | m4a 全链 |
| `research_chain_controlled_difference` | PASS | m4a vs m4b |
| `research_chain_negative_controls` | PASS | 7 条负向对照全部 `status=BLOCKED`、`generation_call_count=0` |
| `negative_controls_refuse_before_generation` | PASS | 每条对照的拒绝阶段与预期阶段逐一相符 |
| `resource_lifecycle` | PASS | 两次 memprobe 正观测（等满 240 s 生产窗口，无 seam） |
| `physical_page_return` | **BLOCKED** | 只有 footprint/退出证据，无 OS 级页归还 |
| `per_layer_forward_calls` | NOT_INSTRUMENTED | 产品无逐层 forward 计数插桩 |
| `app_suite_and_isolation` | PASS | 207/14/0、fresh root、0 写入 |
| `package_suite` | PASS | 85/0 |
| `experiment_non_interference` | PASS | 见第 6 节（文件系统维度） |
| `keychain_non_interference` | **FAIL** | 真实登录钥匙串新增 45 个按 run 命名的条目；生产凭据未改动 |
| `artifact_identity_recomputed` | PASS | `recheck_artifacts.json` 16/16 复算一致 |

复算：`driver/recheck_artifacts.py` 重算了 HEAD/分支/dirty 集合/5 个改动文件摘要/DMG/exe/uuid/Info.plist/bundle 清单/签名/模型 17 文件摘要/单一 revision/符号链接不变 → `verdict: PASS`。

## 8. Lab → 产品来源映射（§3.1）

`SOURCE_MAPPING.md` + `driver/mapping_scan.py` + `evidence/source_mapping_scan.json` + `evidence/source_mapping_diverged.json`，sha256 全树比对并用 `git show HEAD:` 复核：

- `SimiGo2Experimental`：69 文件，59 与 Lab 字节一致（全部为 Lab 已提交内容），10 个同名裁剪。
- `SimiGoRuntimeContract`：11 文件，3 一致（2 已提交 + 1 **只在 Lab 工作树**）、1 裁剪、7 产品独有。
- App target：38 文件，全部产品独有（Lab 不含 App 层）。

溯源不对称 4 条（已如实记录，含关键一条）：产品携带的 681 行结算门 `NativeDeclarativeResultContract.swift` 在 Lab 侧是 **untracked**，Lab HEAD 里不存在 `NativeProducerResultContractGate`，其唯一已提交来源是产品仓 `7329f59`；另有 12 个同名文件 HEAD blob 不一致、Lab 侧缺 2 个契约测试、10 个裁剪无差异清单。

## 9. 仍需解决（按优先级）

1. **FAIL｜Keychain 越界写入**：headless 与隔离测试的身份需改跑一次性 Keychain（见 6.1）。这是本轮唯一 FAIL，修复后需重跑 m4 与隔离套件取证。
2. **BLOCKED｜安装版受保护路由**：需要产品侧激活/管理面（见第 4 节）。这是"完整产品路径"的硬缺口。
3. **BLOCKED｜GUI 普通提示**：需要在已授予 Screen Recording + Accessibility 的 GUI 会话上重跑 `driver/run_stage_b.py`（脚本已具备，判据 `menu_reached && real_model_output`）。
4. **BLOCKED｜`physical_page_return`**：需要 OS 级独立证据（如 `vm_stat`/`footprint` 之外的页归属测量），沿用既定规则不降级。
5. **NOT_INSTRUMENTED｜逐层 `forward_calls`**：需要产品插桩，本轮不动产品。
6. 源码仍为未提交工作树：是否在本地 RC 分支形成小提交、是否合入本地 `main`，作为验收后的单独决定项，本轮未提交、未 push、未打 tag。

## 10. 复现路径

```bash
B=/Users/mr.simi/SimiGo-Agent-Runs/simigo-v2.2.0rc1-local-acceptance-20261024
cd /Users/mr.simi/Documents/SimiGo
python3 tools/rc_noninterference.py --phase pre --out $B/evidence/noninterference_pre_m4.json
bash $B/driver/run_stage_a.sh            # 安装版启动/隔离/退出/重启
bash $B/driver/run_m4.sh                 # ES1→ES2、NC1–7、memprobe（含 240 s 生产空闲窗口）
bash $B/driver/probe_stage_c.sh          # 安装版 HTTPServer 探针（不放宽授权）
python3 $B/driver/run_stage_b.py         # GUI 驱动（需屏幕录制/辅助功能）
python3 tools/rc_noninterference.py --phase post --out $B/evidence/noninterference_post_m4.json
python3 tools/rc_noninterference_diff.py $B/evidence/noninterference_pre_m4.json \
        $B/evidence/noninterference_post_m4.json $B/evidence/noninterference_diff_m4.json
python3 $B/driver/make_freeze.py /Users/mr.simi/Documents/SimiGo $B/RC_SOURCE_FREEZE.json
python3 $B/driver/make_rc_identity.py
python3 $B/driver/make_keychain_report.py    # 只读 Keychain 元数据，不删条目
python3 $B/driver/recheck_artifacts.py $B /Users/mr.simi/Documents/SimiGo
python3 $B/driver/verify_batch.py        # exit 0/1/2
```
