# RC1 发布门槛处置批次报告（2026-10-23）

- 批次目录：`/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-gate-closure-20261023`
- 被检验的候选版本：`simigo-rc1-de362ef4-20261023`（下文简称 RC1）
- 源码 HEAD：`de362ef46118402b40356c8c9e3633395a151717`，本批 **未 commit、未 push、未改冻结批次**
- 本批只处置两个发布门槛：①全量测试的持久化副作用隔离；②在 RC1 同一构建产物上补跑 memprobe。发布等级由用户决定——该决定已于 2026-10-23 作出，见 §4.1 与 `RELEASE_DECISION_RC1_20261023.md`；本报告只登记证据，不代替该决定。

---

## 0. 结论摘要

**第 1 项（测试隔离）：可重定向，且已在隔离根下取得"零真实写入"证据。**

- 审计出的 9 个持久化 sink 中，5 个原本就可通过 `SIMIGO_HOME` / `SIMIGO_CACHE_ROOT` 重定向；**2 个原本不可**（trace log 硬编码 home、StateGraph 的 Application Support 存储无覆盖入口），已按"默认行为不变 + 可选覆盖"修复；另有 3 处测试侧硬编码路径改走同一解析器。
- **断言零改动**：`git diff` 中两个测试文件的 `XCTAssert*` 行为 0 行变更（详见 §2.2）。
- 隔离根下全量测试 **207 executed / 14 skipped / 0 failures**，与 RC1 基线逐项一致，共复现 3 次（run1、run3、run4）；隔离窗口外真实写入 **run3 = 0、run4 = 0**。
- 正式库 `simigo.sqlite3`（sha `cac32dec…`）、WAL、SHM、prefix-pool（45 文件 / 16,499,561,724 B）、branch-checkpoints（37 文件 / 14,896,048,796 B）在窗口内 **字节不变**。

**第 2 项（RC1 产物上的 memprobe）：已执行，分层判定 A/B/C 有证据、D 保持 BLOCKED。**

- 两次运行（mp1/mp2）前后 dylib `6e32892f…`、bundle tree `842f72a6…` 与 RC1 冻结身份一致，实验未改动产物。
- A `old_kv_unreachable` PASS；B 引用释放 PASS（LOGICAL tier）；C 回收动作 PASS（operation executed）；D `physical_page_return` **BLOCKED**——产品自报 footprint 不能作为 OS 级证据，外部采样未佐证系统级页归还。

**残余边界（不隐藏）**：默认的 `xcodebuild test`（不带注入变量）仍会按产品默认行为写真实 `~/.simigo`；隔离由本批提供的运行器保证，而不是把默认行为改成指向某个固定目录（见 §2.7）。

---

## 1. 范围与约束

用户明确要求的四条，本批逐条对照：

| 要求 | 处置 |
|---|---|
| 测试数据与真实 `~/.simigo` 完全分离 | `isolation/home`（IS/WAL/SHM、manifests、logs）+ `isolation/cache`（prefix-pool、branch-checkpoints）+ `isolation/state-graph` 承载全部写入 |
| 正式数据库与封存证据无意外写入 | 正式库/WAL/SHM 逐字节比对；快照覆盖 **整个** `~/.simigo`（不再只列 6 棵子树）+ App Support + HF 缓存 fingerprint |
| 保持原有断言与覆盖 | 断言 0 改动；207 项执行数与 RC1 基线一致；跳过 14 项亦一致（skip 条件未动） |
| 隔离范围外全量差分，确认无非预期变更 | 每轮 run 前/后整树快照 + 差分；run3、run4 真实写入计数为 0 |

明确**不做**的事（用户约束）：不为让测试变绿而放宽断言；不清理真实目录来消除差异；不重建/不重签/不复制 RC1 产物来"重跑"第 2 项。

---

## 2. 第 1 项：全量测试的持久化副作用隔离

### 2.1 持久化 sink 审计

| # | sink | 真实路径 | 解析入口 | 覆盖变量 | 隔离后落点（本批实测） |
|---|---|---|---|---|---|
| 1 | IS 主库 | `~/.simigo/simigo.sqlite3` | `SimiGoPaths.databaseURL` ← `managedRoot()` | `SIMIGO_HOME` | `isolation/home/simigo.sqlite3`（4,096 B） |
| 2 | WAL / SHM | 同目录 | SQLite | `SIMIGO_HOME` | 449,112 B / 32,768 B |
| 3 | prefix pool | `~/.simigo/prefix-pool` | `SimiGoRuntimeCachePaths.prefixPoolRoot` | `SIMIGO_CACHE_ROOT` | `isolation/cache/prefix-pool`（14 GB） |
| 4 | branch checkpoints | `~/.simigo/branch-checkpoints` | `SimiGoRuntimeCachePaths.branchCheckpointsRoot` | `SIMIGO_CACHE_ROOT` | `isolation/cache/branch-checkpoints`（4.5 GB） |
| 5 | bootstrap report / manifests | `~/.simigo/manifests` | `SimiGoPaths.managedRoot()/manifests` | `SIMIGO_HOME` | `isolation/home/manifests/bootstrap-report.json`（797 B） |
| 6 | **native MLX trace log** | `~/.simigo/logs/native_mlx_trace.log` | `RuntimeTraceLogger` —— **原硬编码 home** | `SIMIGO_HOME`（本批修复） | `isolation/home/logs/native_mlx_trace.log`（146 行 / 13,853 B） |
| 7 | **StateGraph legacy JSON** | `~/Library/Application Support/SimiGo/StateGraph/reference-graph-v1.json` | `ExecutionStateGraphStore.defaultStoreURL()` —— **原无覆盖入口** | `SIMIGO_STATE_GRAPH_STORE`（本批新增） | 见 §2.2 的运行时验证 |
| 8 | LOCALB host dir | `~/.simigo/localb` | `LOCALBHostRuntime.defaultHostDirectory()` —— **原硬编码 home** | `SIMIGO_HOME`（本批修复） | 本机真实 `localb` 不存在，207 项测试未触达；改动是生产路径一致性，不宣称已被测试验证 |
| 9 | HF 模型缓存 | `~/.cache/huggingface` | 测试只读 fixture | —（不需要重定向） | 951 文件 / 242,509,940,763 B 窗口内不变（fingerprint） |

第 6 项是 RC1 阶段唯一被实测到的真实写入点：memprobe 在其窗口内向真实 trace log 追加了 1,987 B（`MEMPROBE_ON_RC1.json → side_effects_observed`）。第 5、7 项是 RC1 审计中"真实 home 之外"的漏网点。

### 2.2 代码改动（5 个文件，断言 0 改动）

| 文件 | 改动 | 默认行为 |
|---|---|---|
| `SimiGo/Observability/TraceLogger.swift`（L23-31） | logs 目录 `homeDirectoryForCurrentUser/.simigo/logs` → `SimiGoPaths.logs` | 不变（无覆盖时仍解析到 `~/.simigo/logs`） |
| `SimiGo/Inference/LOCALBHostRuntime.swift`（L22-28） | host 目录 → `SimiGoPaths.managedRoot()/localb` | 不变 |
| `SimiGo/App/ExecutionStateGraph.swift`（L156-170） | `defaultStoreURL()` 开头新增 `SIMIGO_STATE_GRAPH_STORE` 覆盖分支 | 不变（默认仍为 Application Support 路径） |
| `SimiGoTests/PrefixPoolDailyPathE2ETests.swift`（5 处） | trace log ×4 → `SimiGoPaths.logs`；pool 根 ×1 → `SimiGoRuntimeCachePaths.prefixPoolRoot` | 测试读取的仍是"本次运行写入的那个根" |
| `SimiGoTests/BranchFork/BranchForkTests.swift`（1 处） | `traceLogURL` → `SimiGoPaths.logs` | 同上 |

核对方式与结果：

```
git diff -U0 -- SimiGoTests/PrefixPoolDailyPathE2ETests.swift SimiGoTests/BranchFork/BranchForkTests.swift \
  | grep -E '^[-+].*XCTAssert'      →  (none)
```

测试文件的改动只涉及"从哪里读日志 / 从哪里取 pool 根"，断言阈值、marker 列表、覆盖的用例数均未动。

**第 7 项（StateGraph）的运行时验证**（不是"编译通过"就算）：用遗留 JSON 做定向迁移，证明覆盖变量确实是生效路径。

- 把真实遗留图（1,068 B，sha `50d2b21c…`）复制到覆盖路径，`SIMIGO_STATE_GRAPH_STORE` 指向该副本，运行 headless memprobe：
  - 覆盖路径下出现 `reference-graph-v1.json.migrated-2026-10-23T12-05-38Z`（迁移收取 = 改名保字节）；
  - 隔离库 `migration_receipts`：`source_kind=legacy_execution_graph`、`result=ok`、`rows_imported=2`；
  - 真实 `Application Support/SimiGo/StateGraph` 目录 mtime 仍为 `Oct 23 10:38:51`（早于本批），真实 sidecar sha 不变。
- 说明：SQLite 权威路径下该 JSON 只是历史/回退存储，`persist()` 不写它；因此 207 项测试里 `isolation/state-graph` 保持为空是**预期**，而不是"覆盖没生效"。

### 2.3 构建（隔离版，用于第 1 项）

- 配方（与 RC1 一致，含常被漏掉的三项）：
  `xcodebuild build-for-testing -project SimiGo.xcodeproj -scheme SimiGo -configuration Debug -destination platform=macOS,arch=arm64 CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= -enableCodeCoverage NO -derivedDataPath …`
- 首次尝试失败并保留证据：漏 `-enableCodeCoverage NO`，coverage 插桩使 `yyjson` 链接缺 `___llvm_profile_runtime`（`build_for_testing.attempt1_coverage_FAILED.log`）。按 RC1 原配方重跑成功（`build_for_testing.log`，`** TEST BUILD SUCCEEDED **`）。
- 产物身份（测试前后一致，见 `artifact_identity_isolated-build.json` 与 `artifact_identity_post-iso-run4.json`）：
  - bundle tree `a64e66a4f6eae84b8e9edba5bbe2f9d326d8f44f7264b89bed984bb35525e968`（129 文件）
  - dylib `86edda5904a8391827a66ef65ce8d360909321692c6c9634ba2491da6ecded8a`，28,466,656 B，UUID `84D5EAB9-63BA-3DBF-AE63-62E301C465C2`
  - frameworks 207,614,856 B
- **这份隔离构建不是 RC1**：它包含 §2.2 的 5 处改动，用于证明"改动后测试仍全绿且不写真实 home"。RC1 的二进制身份（`6e32892f…` / `842f72a6…`）不受本构建影响，第 2 项仍只在 RC1 原字节上执行。

### 2.4 隔离注入与运行矩阵

隔离 xctestrun 由 `driver/make_isolated_xctestrun.py` 从构建自带 xctestrun 再生成，注入 3 个变量，并**重新读取两份 plist 逐叶比对**，把"除注入键外无差异"变成测量结果（`xctestrun_isolation.json → other_differences: []`）。重新生成的摘要 `e0ba24c9…` 与 run1/run3 手工生成的那份**逐字节相同**。

| run | 隔离根 | 结果 | 耗时 | 窗口内真实写入 | 备注 |
|---|---|---|---|---|---|
| run1 | 全新（空） | 207 / 14 skip / 0 fail | 112.603 s | 0（同窗口 2 笔外部写入，已归因） | 含 19:43–19:47 构建窗口，见 §2.5 |
| run2 | **复用 run1 的 cache** | 207 / 14 skip / **1 fail** | 97.235 s | — | `testF3DeviceAcceptanceBattery` D4 断言失败，见 §2.6；日志保留为 `isolated_tests_run2_SHARED_CACHE_FAILED.log` |
| run3 | 全新（空），正确前置快照 | 207 / 14 skip / 0 fail | 86.908 s | **0** | `** TEST EXECUTE SUCCEEDED **` |
| run4 | 全新（空），经 `driver/run_isolated_tests.sh` | 207 / 14 skip / 0 fail | 86.778 s | **0** | 运行器端到端复现，`isolation_run_run4.json` |
| 基线 | RC1 原始 suite | 207 / 14 skip / 0 fail | 116.758 s | 101 项（RC1 报告） | 判定基准 |

run3 与 run4 均为"先清空隔离根、再跑"的独立复现；run4 完全由脚本驱动（清根 → 再生成 xctestrun → 前后快照 → 跑 → 差分 → 汇总），证明门槛可复现而不依赖一次性手工步骤。

### 2.5 隔离生效的正面证据（run4）

- `isolation/home`：500,626 B —— 含 `simigo.sqlite3`(4,096) + `-wal`(449,112) + `-shm`(32,768)、`logs/native_mlx_trace.log`（146 行 / 13,853 B）、`manifests/bootstrap-report.json`(797 B)，以及 `bin/build/locks/sources/staging` 空目录骨架（`SimiGoPaths.creatableSubdirectoryNames` 行为）。
- `isolation/cache`：20,341,855,180 B —— `prefix-pool` 14 GB、`branch-checkpoints` 4.5 GB。
- 结论：SQLite（含 WAL/SHM）、bootstrap report、prefix pool、branch checkpoints、trace log 五类写入全部落在隔离根内。
- 封存证据：RC1 批次自带清单 601 行逐行重算，**0 处摘要变化**（不写入、不改动该批次）。

### 2.6 新发现：`testF3DeviceAcceptanceBattery` 对 prefix-pool 磁盘状态非幂等

run2 复用 run1 的 `isolation/cache` 后，该用例在 D4 步骤（line 367）失败：

- 期望 `session=parent/main, messages=6, mode=extend, cacheEff=1.00`，实际未命中 `mode=extend`；
- 原因链：D4 断言依赖"本次运行是冷 pool 的写入者"；run1 已在 pool 里留下同前缀边界，run2 走的是复用路径。
- 处置：**不放宽断言**、不清真实目录；把它记录为测试对磁盘状态的依赖，并把"每次全新隔离根"写进运行器（`driver/run_isolated_tests.sh` 顶部注释即此约束）。

这条发现本身是门槛收口的一部分：如果隔离根被反复复用，测试会假失败——运行器必须先清根，否则"零真实写入"的结论会被一次失败的重跑污染。

### 2.7 非干预差分

差分域：整个 `~/.simigo`（整树）+ 各子树 + `~/Library/Application Support/SimiGo` + `~/SimiGo-Agent-Runs`（fingerprint）+ `~/.cache/huggingface`（fingerprint）。重叠扫描按**绝对路径去重**，同时发布 `violation_events`（记录数）与 `real_user_state_write_paths`（物理文件数）；发布门槛只看物理文件数。

| 窗口 | 真实写入（物理文件） | 说明 |
|---|---|---|
| run3（`pre-iso-tests3` → `post-iso-tests3`） | **0** | `noninterference_diff_iso3-window.json`；预期自写 509（批次自身：隔离缓存/xcresult/日志） |
| run4（`pre-iso-run4` → `post-iso-run4`） | **0** | `noninterference_diff_iso-run4-window.json`；预期自写 507 |
| run1 所在窗口（`post-mp2` → `post-iso-tests`，含构建） | 2（均为**非测试**） | ① `~/.simigo/codex-bridge/session_state.json`：211 B、sha 不变，mtime 19:46:38 = 构建窗口内外部 Codex 插件 SessionStart 钩子；② 真实 `logs/native_mlx_trace.log`：mtime 19:47:58（run1 于 19:49 开始），19:49–19:51 窗口内**零行**，写入者为用户 GUI App（`r=633567` / `NativeMLX stopped`），非测试进程 |

正式库不变量（`pre-iso-tests3` → `post-iso-tests3`，逐字段相同）：

- `simigo.sqlite3`：90,112 B，sha `cac32deccd917074fe4eb72bbef7a9a90abc50f41c30ba47fb767ee52820dcbe`，mtime_ns 不变；
- `-wal`：3,955,232 B，sha `62c988cb…`；`-shm`：32,768 B，sha `760edbfc…`；
- `prefix-pool`：45 文件 / 16,499,561,724 B；`branch-checkpoints`：37 文件 / 14,896,048,796 B。

**残余边界（必须如实保留）**：默认 `xcodebuild test`（不注入变量）仍按产品默认行为写真实 `~/.simigo`。本批交付的是**可复现的隔离运行程序**（`driver/run_isolated_tests.sh`），而不是把默认行为固定到某个目录——因为该 battery 要求冷 pool，固定目录的第二次运行必然假失败，而"每次清空"无法由 Xcode scheme 表达。把隔离做成默认，需要先解决"每次运行一个全新根"的生成机制，属于下一步工程项，不在本批宣称完成。

---

## 3. 第 2 项：RC1 同一产物上的 memprobe

### 3.1 身份绑定

- 被测产物：`/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023/derived/Build/Products/Debug/SimiGo.app`（未重建、未重签、未复制）；
- 门禁值来自 `RC_IDENTITY.json`：dylib `6e32892fe776f30bac69596d78d2d774513a656db901339ecfb7d7f3e0ad1b7b`、bundle tree `842f72a68b7936fd6d5e33bb64af43b300920ec0c32fe6788574212a0df4bdc6`；
- 两次运行的前后身份捕获均由 RC1 同款工具（`driver/rc_artifact_identity.py`，摘要定义不变）产出，`matches_rc1_identity: true`、`artifact_unchanged_by_experiment: true`。门禁不匹配即 `exit 9`（`driver/run_rc1_mp.sh`）。

### 3.2 分层判定（`MEMPROBE_ON_RC1.json → tier_verdicts`）

| tier | 判定 | 依据 |
|---|---|---|
| A `old_kv_unreachable` | **PASS** | 空 `SIMIGO_CACHE_ROOT`（ES2 无旧 KV 可用）+ 进程级确认；本批 G3 重算复核 |
| B 引用释放 | **PASS（LOGICAL tier only）** | `reference_release` 事件在 3,923 ms（mp2）；`sessions_released=1`、`model_container_ref_dropped=true`、`model_container_present_before=true` → `absent_after=true` |
| C 回收动作执行 | **PASS（operation executed）** | `resource_reclaim` 事件在 3,929 ms（mp2），即显式 cache-clear 操作被调用；只证明"动作执行"，不证明 OS 行为 |
| D 物理页归还 | **BLOCKED** | 自报 footprint 从 17.42 GB → 12.35 GB（Δ 5,071,211,088 B）是 `task_vm_info.phys_footprint`，不能作为 OS 级证据；独立采样器未观察到 suspend 边界的系统级页释放 |

两次运行功能面一致：`RESULT=hello`（warm 与 resume 各一次），事件序列 `cold_rebuild → cache_save → reference_release → resource_reclaim → lifecycle_suspend → lifecycle_resume → cold_rebuild → cache_save`。结论不因"多跑一次"而升级；D 的 BLOCKED 是判定规则的结果，不是缺数据。

### 3.3 外部 OS 采样（非佐证，非反证）

- 采样器为独立进程（`driver/os_vm_sampler.py`），读 `vm_stat` / `vm.swapusage` / `ps` RSS，**按完整 bundle 路径**匹配 PID（早期按子串匹配曾把用户 GUI App 误配进来，mp1 的 RSS 无意义，已在证据中标注）。
- mp2（实测序列，采样 7 次）：RSS ≈0 → 3.59 → 8.95 → 8.16 → 3.71 → 11.81 → 10.56 GB，峰值出现在 suspend **之后**；free pages 在 suspend 边界未上升。
- 解释边界：1 s 采样对几秒窗口分辨率不足，故记为"不佐证"，不是"反证"。

### 3.4 实验的副作用（已在第 1 项消除）

mp1/mp2 各产生 **1 个**真实 home 写入：`~/.simigo/logs/native_mlx_trace.log`（RC1 二进制硬编码 TraceLogger）。这不是实验设计缺陷，而是 RC1 的既成事实；第 1 项的 `TraceLogger → SimiGoPaths.logs` 正是针对它的修复。

---

## 4. 发布门槛判定更新与发布决定

| 验收项 | RC1 原判定 | 本批证据状态 |
|---|---|---|
| 源码、模型、工具链身份冻结 | PASS | 未涉及（本批未改冻结批次） |
| 构建与测试二进制一致 | PASS | 隔离构建前后 tree/dylib 一致；RC1 产物未被实验改动 |
| 真实模型跨进程恢复与续算 | PASS（限定范围） | 未涉及 |
| 干净态构建复现 | PASS（源码与功能层面） | 未涉及 |
| 字节级可复现构建 | NOT PASS | 未涉及（本批未主张改善） |
| **全量测试的非干预性** | **FAIL（101 项预期外变更）** | **隔离运行程序下 PASS**：3 次 207/14/0；run3、run4 真实写入 0；正式库/WAL/SHM/pool/checkpoints 字节不变。默认命令仍写真实 home（§2.7 残余边界） |
| **RC1 产物上的资源释放实验** | **NOT RUN** | **已执行**：A PASS / B PASS(LOGICAL) / C PASS(operation) / D BLOCKED，身份绑定 RC1 |
| 研究机制完整性 | 未闭合 | 未变：`restricted_production_path`、`physical_page_return=BLOCKED`、`forward_calls=NOT_INSTRUMENTED` 依然成立 |

### 4.1 发布决定（2026-10-23，用户作出）

- **批准交付**：SimiGo RC1 **受控研究与集成版**（controlled research & integration build）。
- **不批准**：生产级 GA；不宣称 SimiGo 的全部核心研究机制已经得到验证。
- **允许**：受控部署、产品集成、开发者使用、在已验证范围内继续研究。
- **暂不宣称**：全路径验证、普遍性能收益、物理内存完全释放、所有核心机制闭合。
- **强制操作约束**（交付的一部分）：
  1. **C1** 测试必须通过 `driver/run_isolated_tests.sh` 执行（全新隔离根 → 再生成 xctestrun → 前后快照 + 差分）；普通 `xcodebuild test` 不等价。已写入 `SimiGo/README.md` 与 `SimiGo/CONTRIBUTING.md`。
  2. **C2** 研究主张限定为：在已测试任务族中，已结算的信息能经 IS 在新的执行进程中验证、恢复并参与真实模型续算。
  3. **C3** `physical_page_return=BLOCKED`、`forward_calls=NOT_INSTRUMENTED`、字节级可复现 NOT PASS 保持显式未闭合；禁止把另一份构建的实验结果移交给 RC1。
- 落地情况：`SimiGo/README.md` 与 `SimiGo/CONTRIBUTING.md` 已插入该限制（工作区改动、未提交，待审阅）；自检 `test_isolation_constraint_documented` 校验两份文件同时含运行器路径与“不等价/not equivalent”表述。
- 记录文件：`RELEASE_DECISION_RC1_20261023.md` / `.json`（决定人 = 用户，代理只做转录与约束落实）。

---

## 5. 事实 / 结论 / 假设 / 授权

**事实（可直接复核）**

1. 隔离根下 3 次全量运行均为 207 / 14 skip / 0 fail；RC1 基线同为 207 / 14 / 0。
2. run3、run4 窗口内真实用户状态写入物理文件数为 0；正式库三件套 sha 不变。
3. `testF3DeviceAcceptanceBattery` 在复用 pool 时于 line 367 失败（D4），在全新根上通过。
4. RC1 dylib/tree 在两次 memprobe 前后均等于 `RC_IDENTITY.json` 冻结值。
5. `SIMIGO_STATE_GRAPH_STORE` 指向的遗留 JSON 被迁移到同目录 sidecar，`migration_receipts` 记 `rows_imported=2`，真实 Application Support 目录 mtime 未变。
6. 测试断言 0 行改动（`git diff` 可复算）。

**结论（由事实推出，仍可被新证据推翻）**

1. 用户列出的 4 类持久化（SQLite+WAL/SHM、branch checkpoints、prefix pool、bootstrap report）以及 trace log 均可通过统一根重定向；两项原不可重定向的 sink 已被"可选覆盖"修复。
2. 在隔离运行程序下，全量 207 项测试对真实用户状态的非预期写入为 0。
3. RC1 产物上的资源释放达到"逻辑释放 + 回收动作执行"，未达到"物理页归还"。

**假设（未在本批验证）**

1. 用户 GUI App 与外部 Codex 插件的行为归因基于 mtime、进程号与日志行时间戳，未做进程级注入取证。
2. LOCALB host 目录重定向未被执行路径触达（本机不存在该目录），其正确性来自代码一致性而非运行证据。
3. 外部 OS 采样 1 s 分辨率不足，D 的 BLOCKED 不代表"物理页一定未归还"。

**授权边界**：未 commit、未 push、未改冻结批次、未删除真实用户数据；隔离根是唯一被清空的目录（运行器带路径白名单校验，不匹配即拒绝执行）。

---

## 6. 复现

```bash
B=/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-gate-closure-20261023

# 第 1 项：隔离全量测试（清空隔离根 → 再生成 xctestrun → 前后快照 → 跑 → 差分）
"$B/driver/run_isolated_tests.sh" run5

# 第 2 项：RC1 原字节上的 memprobe（含身份门禁与外部采样）
MP_ID=mp3 "$B/driver/run_rc1_mp.sh"

# 单项工具
python3 "$B/driver/make_isolated_xctestrun.py" "$B/derived/Build/Products/Debug/SimiGo.app" "$B"
python3 "$B/driver/rc_noninterference.py"  post-check
python3 "$B/driver/rc_noninterference_diff.py" "$B/noninterference_pre-iso-run4.json" \
        "$B/noninterference_post-iso-run4.json" "$B/noninterference_diff_check.json" "$B"
```

## 7. 交付物（本批关键文件）

| 文件 | 作用 |
|---|---|
| `GATE_CLOSURE_REPORT_20261023.md` | 本报告 |
| `GATE_CLOSURE_SELF_CHECK.json` | 批次自检（17 项，逐项可复算） |
| `MANIFEST_SHA256_gate_closure.txt` | 证据文件清单与摘要 |
| `MEMPROBE_ON_RC1.json` | 第 2 项分层判定与身份绑定 |
| `RELEASE_DECISION_RC1_20261023.md` / `.json` | 发布决定（受控研究与集成版）与三项强制约束 |
| `xctestrun_isolation.json` / `xctestrun_isolation_used_for_run1_thru_run3.json` | 隔离注入记录（再生成 / 历史） |
| `artifact_identity_isolated-build.json`、`artifact_identity_post-iso-run4.json` | 隔离构建身份（前后一致） |
| `isolated_tests.log` / `isolated_tests_run2_SHARED_CACHE_FAILED.log` / `isolated_tests_run3.log` / `isolated_tests_run4.log` | 四轮运行原始日志 |
| `isolation_run_run4.json` | 运行器汇总（结果 + 隔离内容 + 非干预） |
| `noninterference_*`、`noninterference_diff_iso3-window.json`、`noninterference_diff_iso-run4-window.json` | 快照与差分 |
| `hook_smoke_state_graph_migration/` | StateGraph 覆盖的运行时验证（迁移收据 + sidecar + 真实目录未变） |
| `driver/run_isolated_tests.sh`、`driver/make_isolated_xctestrun.py`、`driver/verify_gate_closure.py` | 可复现运行器、xctestrun 生成器、自检器 |
