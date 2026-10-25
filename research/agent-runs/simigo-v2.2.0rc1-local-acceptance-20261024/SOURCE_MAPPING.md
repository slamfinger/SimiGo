# Lab → 产品 来源映射（v2.2.0rc1 / round 2）

任务书 §3.1 要求的 `Lab source commit → 被选取的文件/实现 → 产品目标路径 → 产品测试 → 验收证据`
映射。本文件的所有结论由 `driver/mapping_scan.py` 从磁盘重算，原始数据见
`evidence/source_mapping_scan.json`（逐文件 sha256）与 `evidence/source_mapping_diverged.json`（差异行数）。

## 0. 参与比对的身份

| 项 | 值 |
|---|---|
| Lab 仓库 | `/Users/mr.simi/Documents/SimiGo-Lab` |
| Lab 分支 / HEAD | `main` / `e7f63856298390deb8596a4a30e173d3fb466eaa` |
| Lab 工作树 | 96 项未提交（17 modified + 79 untracked），领先 `origin/main` 4 个提交 |
| 产品仓库 | `/Users/mr.simi/Documents/SimiGo` |
| 产品分支 / HEAD | `localb-b3-closure-20261016` / `f18d65f8f312ffbb837fdf5e07125af044833854` |
| 产品工作树 | 5 项未提交（见 `RC_SOURCE_FREEZE.json`） |
| 产品引入运行时包的提交 | `9f8bcd0`（vendor standalone runtime package）与 `7329f59`（contract sources + test target） |

比对方法：对 Lab 全部 `.swift`（排除 `.git` / `.build` / `vendor`）建 sha256 索引，
再对产品三个来源根逐文件比对；对每个命中项额外用 `git show HEAD:<lab path>` 复核，
确认产品文件对应的是 Lab **已提交**内容还是仅工作树内容。

## 1. 汇总（按文件）

| 产品来源根 | 文件数 | 与 Lab 字节一致 | 同名但已分叉 | 产品独有 |
|---|---:|---:|---:|---:|
| `Packages/SimiGoRuntime/Sources/SimiGo2Experimental` | 69 | 59 | 10 | 0 |
| `Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract` | 11 | 3 | 1 | 7 |
| `SimiGo/`（App target） | 38 | 0 | 0 | 38 |

分叉的 10 + 1 个文件，产品侧一律是**裁剪版**（研究夹具、实验批处理被移除），
不是功能增强：例如 `MLXPrefixRecomputeExecutor.swift` 产品 116 行 / Lab 643 行、
`PrefixSnapshotStore.swift` 289 / 846、`MaterializationCoordinator.swift` 119 / 625。
逐文件 `+added / -removed` 行数见 `evidence/source_mapping_diverged.json`。

## 2. 逐能力映射

| Lab 来源（HEAD e7f6385） | 被选取的实现/结论 | 产品目标路径 | 产品测试 | 本轮验收证据 |
|---|---|---|---|---|
| `simigo2-experimental/Sources/SimiGo2Experimental/NativeDeclarativeResultContract.swift`（**工作树未提交**，681 行，sha `4a6cefed94fa…`） | 原生声明式结果契约门：结算前校验，抛错即不写不签（fail-closed） | `Packages/…/SimiGoRuntimeContract/NativeDeclarativeResultContract.swift`（字节一致） | `Tests/SimiGoRuntimeContractTests/NativeDeclarativeResultContractTests.swift` | `m4/m4a/consume_m4a_nctamper.json`（摘要篡改，stage=`is_verify_u1`，`generation_call_count=0`）、`consume_m4a_ncinval.json` |
| `…/SimiGoRuntimeContract/RuntimeBackendContract.swift`（67 行，sha `00156bc5d2af…`） | 运行时后端契约 | `Packages/…/SimiGoRuntimeContract/RuntimeBackendContract.swift`（字节一致） | 无同名测试文件（产品侧缺口，见 §4） | 包测试整体 85/0（`logs/pkg_tests_round2.log`）；App 套件 207/14/0 |
| `…/SimiGoRuntimeContract/ExecutionContinuityContract.swift`（165 行，sha `ea173a63ad97…`） | 执行连续性契约 | `Packages/…/SimiGoRuntimeContract/ExecutionContinuityContract.swift`（字节一致） | Lab 有 `ExecutionContinuityContractTests.swift`，**产品未携带** | M4 ES1→IS→ES2 全链（`m4/m4a/{produce,consume}_m4a.json`） |
| `…/SimiGoRuntimeContract/ExecutionStateBackendContract.swift`（80 行） | ES 后端契约 | 同名产品文件（72 行，裁剪 8 行） | 无同名测试文件 | `SimiGoESISDatabaseTests` / `…G2Tests` 覆盖 schema v3 |
| 研究侧 ES/IS 持久化结论（`DurableExecutionStateStore.swift`、`ExecutionContinuityCoordinator.swift` 等，未逐字移植） | IS 表结构 v3：`execution_states`/`settlements`/`settlement_bindings`/`dependency_edges` | `Packages/…/SimiGoRuntimeContract/SimiGoESISDatabase.swift`（产品独有，本轮有未提交修改） | `SimiGoESISDatabaseTests.swift`、`SimiGoESISDatabaseG2Tests.swift` | `m3/home/simigo.sqlite3` 表清单（stage A）+ `produce_m4a.json` 的 `is_settlement_restored_readback=true` |
| `SettlementProvenanceVerification.swift`（432 行，签名 provenance + 外部 trust anchor） | **未集成**（见 §3） | — | — | — |
| 研究侧"模型/tokenizer 身份不匹配必须拒绝"的要求 | 生产者模型/tokenizer 身份绑定，消费端 fail-closed 比对 | `Packages/…/SimiGoRuntimeContract/SimiGoSettlementIdentityBinding.swift`（**本轮新增，未提交**） | `SimiGoSettlementIdentityBindingTests.swift`（新增，未提交） | `m4/m4a/consume_m4a_ncmodel.json`（`stage=is_binding_verify`，`generation_call_count=0`） |
| 三根隔离要求（Lab `RuntimeIsolationGate.swift` + 隔离根结论） | `SIMIGO_HOME` / `SIMIGO_CACHE_ROOT` / `SIMIGO_STATE_GRAPH_STORE` 统一解析 | `Packages/…/SimiGoRuntimeContract/SimiGoPaths.swift`（产品独有，提交 `7329f59`） | `SimiGoPathsTests.swift` | `evidence/m3_stage_a_process_round2.txt`（`ps eww` 三变量 + 落盘目录） |
| 无（产品自有入口） | headless 三角色 `produce`/`consume`/`memprobe`，`path_class=restricted_production_path` | `SimiGo/Headless/SimiGoG1G3Entry.swift`（产品独有；本轮修改 memprobe 等待真实空闲窗口） | App 套件 207 用例（含 headless 相关） | `m4/m4a/*.json`、`m4/m4a/memprobe.json` |
| 无（产品自有时序观测） | `noteReferenceRelease` / `noteResourceReclaim` / `noteSuspend` / `noteResume` 观测原语 | `SimiGo/Inference/NativeMLXObservation.swift`（产品独有） | 结构由 memprobe 自证 | `memprobe.json` 的 `events` / `events_ordered` |

## 3. 明确未集成的 Lab 实现（附原因）

| Lab 实现 | 为什么没有进入产品 |
|---|---|
| `SettlementProvenanceVerification.swift`（签名 provenance，trust anchor 在 IS 之外） | 产品侧尚无签名密钥托管与 trust anchor 分发；`SimiGoSettlementIdentityBinding` 只在文件头写明"不是 attestation、无签名、无 trust anchor"。把它当作已集成会高估产品能力。 |
| `G3IsolatedExecutionEntry.swift`（360 行，文件自述 "G3-only，正常推理不经过这里"） | 与产品的 headless 入口是两套不同实现；把 G3 研究专用入口接进产品会改变生产语义。 |
| `G3DualArmRunner` / `G3ExecutionDispatch` / `G3PerArmKVCache` / `RuntimeIsolationGate` / `ExecutionIdentityAllocator` | 双臂实验与隔离闸门属研究工具，产品当前不需要，且未做产品级测试。 |
| Lab `SimiGoRuntimeContractTests` 中 13 个测试文件（含 `ExecutionContinuityContractTests`、`RuntimeBackendContractTests`、`G3*Tests`） | 其中 G3 系列依赖未集成实现；`ExecutionContinuityContractTests` / `RuntimeBackendContractTests` 属可移植的缺口，未在本轮补（§4）。 |

## 4. 溯源不对称与缺口（必须记录，不得抹平）

1. **`NativeDeclarativeResultContract.swift` 在 Lab 侧未提交。** 该文件在产品仓库已由 `7329f59` 提交，
   但在 Lab 工作树是 `??`（untracked），且 Lab HEAD 中不存在符号 `NativeProducerResultContractGate`。
   即：这一份 681 行的结算门实现，**唯一已提交的来源是产品仓库**，Lab 侧只是工作树副本。
   要满足"Lab source commit → 产品"的严格溯源，需要在 Lab 侧提交该文件（本轮不授权修改 Lab 研究边界）。
2. **12 个被引用文件在 Lab 的 HEAD blob 与产品文件不一致**（10 个同名分叉 + 1 个契约分叉 + 上述未提交文件），
   说明产品的 vendor 内容取自 Lab 工作树而非某个干净提交。逐条列在 `evidence/source_mapping_diverged.json`。
3. **产品未携带两个契约测试**：`ExecutionContinuityContract` 与 `RuntimeBackendContract` 的 Lab 测试文件
   没有对应产品测试；产品对它们的验证只有 App 套件与 M4 端到端，属覆盖缺口。
4. **产品侧 10 个同名分叉文件全部是裁剪**（移除研究夹具与批处理），但裁剪后没有任何"产品侧差异清单"，
   升级 Lab 版本时无法自动判断哪些删除是刻意的。

## 5. 复算方式

```
python3 /Users/mr.simi/SimiGo-Agent-Runs/simigo-v2.2.0rc1-local-acceptance-20261024/driver/mapping_scan.py
```

该脚本对每个产品 Swift 文件做 sha256，与 Lab 全树比对，并用 `git show HEAD:<lab path>`
复核，输出 `evidence/source_mapping_scan.json` 与 `evidence/source_mapping_diverged.json`。
本轮输出：`SimiGo2Experimental` 69 文件 = 59 一致（**59 全部与 Lab HEAD 已提交内容一致**）+ 10 裁剪；
`SimiGoRuntimeContract` 11 文件 = 3 一致（2 个对得上 Lab HEAD，1 个只对得上 Lab 工作树）+ 1 裁剪 + 7 产品独有；
App target 38 文件全部产品独有。

## Round 4 addendum — product hardening found by the acceptance run itself

| change | file | why | evidence |
|---|---|---|---|
| isolated root must also redirect the cloud credential | `SimiGo/App/CloudBackend.swift` | `Service.init()` read the real login Keychain even with `SIMIGO_HOME` set; the item ACL answered the new binary with an interactive SecurityAgent prompt and blocked startup forever (`SecItemCopyMatching → mach_msg`; securityd `QueryKeychainUse::queryUser`) | `round3_archive/evidence/m3_stage_a_process.txt` (bootstrap ABSENT), the `sample` stack in `logs/scan_round3_hang.txt`, `evidence/m3_stage_a_process.txt` (bootstrap 20 models after the fix) |
| regression test for that rule | `SimiGoTests/CloudBackendTests.swift` | the rule must be executable, not a comment | `run_isolated_r4/isolated_tests_r4.log` (`testIsolatedManagedRootNeverReadsOrWritesTheLoginKeychain` passed) |

This is not Lab-sourced code: it is a product-side isolation defect the acceptance
procedure exposed. No Lab file was moved or deleted.
