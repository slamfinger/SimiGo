# 三个本地提交的审查说明（7329f59 / 3a89817 / f18d65f）

- 批次：`simigo-rc1-repo-closure-20261023`
- 对象：`localb-b3-closure-20261016` 上未推送的三个提交，HEAD `f18d65f`
- 用途：让审查者**不依赖聊天记录**回答三个问题：为什么需要这三个提交、
  怎样从干净检出复现成功、怎样验证失败关闭与零越界写入。
- 本文不改变任何判定：RC1 仍为 `controlled research and integration build`；
  `physical_page_return` 仍 `BLOCKED`；`forward_calls` 仍 `NOT_INSTRUMENTED`；
  字节级可复现仍 **NOT PASS**。
- 授权边界：**未 push、未 merge、未打 tag**；本地领先 origin 3 个提交
  （`origin/localb-b3-closure-20261016` 仍为 `de362ef`）。

约定：文中 `事实` = 已由命令或文件直接读出；`推导` = 由事实推出但本批未实跑；
`未覆盖` = 本批没有验证，不得据此推断为通过。

---

## 0. 一页速览

| 提交 | 一句话目的 | 依赖 | 直接证据 | 单独回滚的后果 |
|---|---|---|---|---|
| `7329f59` | 把三个根的路径重定向写进源码，并补齐 `SimiGoRuntimeContract` 的构建闭包 | 无（栈底） | clean2 构建 rc=0；run3 的 `isolation_home_used_by_app` / `isolation_cache_used_by_app` 均为 true | 隔离器注入的环境变量失去读者 → 隔离不可证明 |
| `3a89817` | 把隔离测试运行器与四个工具脚本入库，并在 README/CONTRIBUTING 声明唯一入口 | 需要 `7329f59` 的语义 | run3 由该脚本本体执行，207/14/0 | 仓库内重新没有可复现的测试入口 |
| `f18d65f` | 生成器遇到非 plist 基座时给出 rc=3 诊断，而不是抛 traceback | 需要 `3a89817` 的生成器 | 负向 N9：rc=3、不写输出 | 错误路径退回“Python traceback + rc=1” |

三个提交的顺序是**栈式**的：B 依赖 A 的语义，C 修 B 中生成器的错误路径。
任何“只提交其中一部分”的方案都会留下一个不可自证的中间态（见 §2）。

---

## 1. 审查对象与环境身份（均为本次复核读出）

| 项 | 值 | 来源 |
|---|---|---|
| HEAD | `f18d65f8f312ffbb837fdf5e07125af044833854` | `git log` |
| 父链 | `f18d65f` → `3a89817` → `7329f59` → `de362ef` | `git log --oneline -4` |
| 工作树 | `git status --porcelain` = 0 行 | 本次复核 |
| 领先 origin | `git rev-list --count origin/..HEAD` = 3 | 本次复核 |
| clean2 检出 | HEAD `f18d65f`，tracked 434，status 0 行 | `clean2/` |
| 工具链 | Xcode 27.1 (27A9275)、Swift 6.4、macOS 27.0.1、arm64 | `simigo-rc1-20261023/RC_SOURCE_FREEZE.json:/toolchain` |
| 冻结构建命令 | `RC_SOURCE_FREEZE.json:/build_configuration/command` | 同上 |
| 工具脚本摘要 | `run_isolated_tests.sh 9ea57489…`、`make_isolated_xctestrun.py d3642a3e…`、`rc_noninterference.py b0baf601…`、`rc_noninterference_diff.py 35d06f6f…` | `shasum -a 256 tools/*` |

---

## 2. 为什么需要这三个提交

### 2.1 起点：能力在机器上，不在仓库里

`simigo-rc1-tools-vendoring-20261023/run1` 证明了“参数化运行器 + 三根重定向 +
前后快照差分”这条流程可以跑出 207/14/0 且零真实写入。但那一轮的运行器与
被改动的 app 源码都还在工作区（11 个 tracked 修改 + 23 个未跟踪文件），
`de362ef` 本身既没有运行器，也没有让三个环境变量生效的代码。

### 2.2 “只提交 tools + 文档”不够用（这是被否决的方案）

三条事实（`git grep … HEAD` / `git show de362ef:…` 可复算）：

1. `SIMIGO_HOME` 在 `de362ef` 无任何读者；到 HEAD 只由
   `Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoPaths.swift` 读取，
   而该文件是 `7329f59` 新增的。
2. `SIMIGO_CACHE_ROOT` 在 `de362ef` 无读者；到 HEAD 只由
   `SimiGo/Headless/SimiGoG1G3Entry.swift` 内的 `SimiGoRuntimeCachePaths` 读取
   （`NativeMLX` 的分支 checkpoint 与 `NativeMLXPrefixPool` 都走它），
   该文件同样是 `7329f59` 新增的。
3. `SIMIGO_STATE_GRAPH_STORE` 在 `de362ef` 无读者；到 HEAD 由
   `SimiGo/App/ExecutionStateGraph.swift` 读取，该文件在 `7329f59` 中修改。
   同一提交里 `TraceLogger.swift` 把硬编码的 `<home>/.simigo/logs` 改为
   `SimiGoPaths.logs`。

**推导（未实跑）**：若只提交 `tools/` 与文档，在一个干净检出上运行
`tools/run_isolated_tests.sh`，三个变量都没有读者，测试宿主仍按产品默认写真实
`~/.simigo`；运行器的 `isolation_home_used_by_app` 检查（要求隔离根内出现
`simigo.sqlite3`）会为 false，脚本以 exit 6 失败。也就是说：**工具能入库，但
它声称的隔离在那份检出上不成立**。这正是必须带上 A 的原因。

### 2.3 为什么不拆得更细、也不合并成一个

- 拆得更细（例如“只提交 contract 源”或“只提交 app 接线”）会产生不能编译的
  中间提交：`SimiGo/` 下 8 个文件与 `SimiGoTests/` 下 4 个文件
  `import SimiGoRuntimeContract`（共 12 个，`git grep -l … HEAD` 可复算），
  并直接使用 `SimiGoPaths`（6 个文件）、`SimiGoESISDatabase` 等符号；
  这些符号只存在于同一提交新增的 7 个源文件中。
- 合并成一个则让“语义变更”和“工具入库”混在同一个提交里，回滚粒度变粗：
  审查者无法只回滚工具而不动产品语义。当前三个提交的回滚后果各不相同（§11）。

### 2.4 一处用词更正

`REPORT_20261023.md` §2 写“缺源即不可构建”。准确含义是**这 38 个文件彼此
不可拆**（app 侧引用的符号在这些新源文件中）。至于 `de362ef` 自身能否构建：
`de362ef` 的 `SimiGoRuntimeContract` 已有 3 个源文件，且 app/测试在 `de362ef`
没有 `import SimiGoRuntimeContract`（grep 计数 0），因此**不能**据此断言
`de362ef` 不可构建。本批未对 `de362ef` 单独做过干净检出构建，
该命题不作为本提交集的论据。真正支撑 A 的是 §2.2 的“变量无读者”。

---

## 3. 提交 A `7329f59` — 路径重定向与 contract 构建闭包

**解决的问题**：让产品代码承认三个环境变量，并在缺省时保持原行为；
同时把 app 侧实际使用、但 `de362ef` 中并不存在的 contract 源文件补齐
（`de362ef` 的该 target 只有 3 个文件，本提交后为 10 个）。

**文件范围**（38 = 23 新增 + 15 修改；逐条可用 `git show --name-status 7329f59` 复算）：

| 组 | 数 | 关键文件 |
|---|---|---|
| contract 源 | 7 | `SimiGoPaths.swift`、`SimiGoBootstrap.swift`、`SimiGoESISDatabase.swift`、`SimiGoEngineRecipe.swift`、`SimiGoModelDiscovery.swift`、`SimiGoSettlementAuthority.swift`、`NativeDeclarativeResultContract.swift` |
| contract 测试 | 8 | `Tests/SimiGoRuntimeContractTests/*`（含 `SimiGoPathsTests`） |
| 包清单 | 2 | `Packages/SimiGoRuntime/Package.swift`（新增 `testTarget` 与 `sqlite3` 链接）、`Package.resolved` |
| app 接线 | 13 | 改：`TraceLogger`、`ExecutionStateGraph`、`Settings`、`Config`、`StatusBarCoordinator`、`LOCALBHostRuntime`、`NativeMLX`、`NativeMLXPrefixPool`、`RuntimeTuning`、`EnvManager`、`Service`；增：`SimiGoBootstrapRunner`、`NativeMLXObservation` |
| headless 入口 | 1 | `SimiGo/Headless/SimiGoG1G3Entry.swift`（含 `SimiGoRuntimeCachePaths`） |
| app 测试 | 7 | 改 3（`BranchForkTests`、`ExecutionStateGraphTests`、`PrefixPoolDailyPathE2ETests`）+ 增 4（`ExternalAdoptionInferenceE2ETests`、`ExternalServerAdoptionTests`、`MemoryReliefRealModelTests`、`SimiGoG1G3HeadlessEntryTests`） |

注：各组互不重叠，7+8+2+13+1+7 = 38，与 `git show --stat` 的 38 个文件一致；
其中新增 23 = 7 + 8 + `Package.resolved` + `SimiGoBootstrapRunner` +
`NativeMLXObservation` + `SimiGoG1G3Entry` + 4 个新增测试，
修改 15 = `Package.swift` + 11 个 app 文件 + 3 个既有测试。

**前置依赖**：无。这是栈底提交，不依赖 B/C 的语义（本批未单独构建 A，
其可编译性由 clean2 在 A 的后继 `f18d65f` 上构建 rc=0 间接覆盖）。

**验证**：clean2 在该提交的**后继**（`f18d65f`）上构建 rc=0；run3 的
`isolation_home_used_by_app` / `isolation_cache_used_by_app` 均为 true，
是这三个根真的生效的直接读数（不是“代码里有这个字符串”的静态推断）。

**未覆盖**：`SimiGoRuntimeContractTests`（8 个文件）在本批**没有被编译或执行**：
`build_clean2.log` 中 `SimiGoRuntimeContractTests` 命中 0 次，
run3 的 xctestrun 只有 1 个 test target（app 测试包，207 个用例）。
因此**不得**由 207/14/0 推断这 8 个测试通过。它们入库的理由是：同一提交的
`Package.swift` 声明了该 test target，若只提交声明不提交源，包处于
“manifest 声明了不存在的测试目标”的状态。

**回滚边界**：`git revert 7329f59` 会同时撤掉环境变量读数与 `SimiGoPaths`，
后续两个提交的隔离语义随之失效；不建议单独回滚 A。

---

## 4. 提交 B `3a89817` — 隔离测试工具与文档入口

**解决的问题**：把只在个人机器上存在的隔离运行器变成仓库资产，并在
README / CONTRIBUTING 声明它是唯一被承认的全量测试入口。

**文件范围**（6 = 4 新增 + 2 修改）：

| 文件 | 角色 | sha256 前 8 |
|---|---|---|
| `tools/run_isolated_tests.sh` | 编排：前置校验 → 生成 xctestrun → 前快照 → 跑测 → 后快照 → 差分 → 9 项 check | `9ea57489` |
| `tools/make_isolated_xctestrun.py` | 复制基座 xctestrun 并只注入三个根，记录逐叶差异 | `d3642a3e`（C 之后） |
| `tools/rc_noninterference.py` | 整树快照（path/bytes/mtime_ns/sha256，≤8MB 内容哈希） | `b0baf601` |
| `tools/rc_noninterference_diff.py` | 差分并区分 real/reference/expected，拒绝与真实根重叠的 allow-prefix | `35d06f6f` |
| `README.md` (+24) | 规定入口与“普通 `xcodebuild test` 不等价” | — |
| `CONTRIBUTING.md` (+23) | 同上，英文版 | — |

**前置依赖**：A。工具本身可独立存在，但它断言的隔离只有 A 的语义到位才成立。

**验证**：run3 就是这份脚本本体跑出来的（`run3/isolation_run_run3.json`），
不是“另写一个临时脚本跑通后把脚本入库”。

**回滚边界**：`git revert 3a89817` 只撤工具与文档，产品语义不动；
仓库回到“无复现入口”的状态，历史证据（run1/run2/run3）仍然可读。

---

## 5. 提交 C `f18d65f` — 生成器的非 plist 错误路径

**解决的问题**：基座 xctestrun 不是 plist 时，生成器抛出 Python traceback
并以 1 退出，而工具文档承诺“exit 3 + 可诊断消息”。这是负向验证在
B 的字节上发现的真实缺陷（N9/N11 同批发现），因此修复后重新取证。

**文件范围**：1 个文件（+10 / -2），仅 `tools/make_isolated_xctestrun.py`：
`plistlib.load` 与重写后的复读均包进 `try/except → die(...)`。

**前置依赖**：B。

**验证**：`negatives-final/transcript.txt` 与本次重放均记录
`rc=3 :: make_isolated_xctestrun: base xctestrun is not a readable plist (…): Invalid file`
且“output written? NO”。

**回滚边界**：`git revert f18d65f` 让错误路径退回 traceback/rc=1；
正常路径不受影响，但“错误路径满足契约”这一条验收会失效。

---

## 6. 从干净检出复现成功（命令逐字取自冻结配置与 run3 日志）

> 运行器不记录自己的 argv。下面第 3 步的调用由 `run3/isolation_run_run3.json`
> 的 `evidence_dir`/`tag` 与 `run3/xctestrun_isolation.json` 的
> `source_xctestrun` 三处记录反推，并与 `run3_runner_stdout.log:50-51` 记录的实际
> xcodebuild 命令行核对一致；若改用等价的显式参数，身份仍由
> `xctestrun_isolation.json` 固定。

**步骤 1：检出并确认身份**

```bash
git clone /Users/mr.simi/Documents/SimiGo simigo && cd simigo
git checkout f18d65f8f312ffbb837fdf5e07125af044833854
git status --porcelain          # 期望：空
git ls-files | wc -l            # 期望：434
```

**步骤 2：构建（冻结命令，唯一偏差是 derivedDataPath）**

冻结值见 `simigo-rc1-20261023/RC_SOURCE_FREEZE.json:/build_configuration/command`：

```bash
xcodebuild build-for-testing -project SimiGo.xcodeproj -scheme SimiGo \
  -configuration Debug -destination platform=macOS,arch=arm64 \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= -enableCodeCoverage NO \
  -derivedDataPath ./build/test
```

- `-derivedDataPath` 是产物输出位置，不是构建输入；RC1 批次用 `…/derived`，
  本批复现用 `./build/test`，这是与冻结命令的唯一差异（`REPORT_20261023.md` §3）。
- 期望：rc=0 且日志出现 `** TEST BUILD SUCCEEDED **`
  （clean2 实测：`build_clean2.log:17186`，实际命令行见同文件 13–14 行）。
- 期望：构建后 `git status --porcelain` 仍为空（`build/` 被 `.gitignore` 覆盖）。

**步骤 3：用仓库内运行器跑全量**

```bash
tools/run_isolated_tests.sh \
  --evidence-dir /Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-repo-closure-20261023/run3 \
  --tag run3
```

等价写法（默认 `--app build/test/Build/Products/Debug/SimiGo.app`、
默认 `--destination platform=macOS,arch=arm64`）。实际执行的测试命令见
`run3_runner_stdout.log:50-51`：

```
xcodebuild test-without-building -xctestrun …/Products/xctestrun_isolated.xctestrun \
  -destination platform=macOS,arch=arm64 -resultBundlePath …/run3/Test-run3.xcresult
```

**步骤 4：判读（全部是文件读数，不靠叙述）**

| 判据 | 期望 | run3 实测 |
|---|---|---|
| 用例计数 | 207 执行 / 14 跳过 / 0 失败 | `isolated_tests_run3.log:2357` |
| 测试结论 | `** TEST EXECUTE SUCCEEDED **` | 同日志 2367 行 |
| 运行器退出码 | 0 | `isolation_run_run3.json:exit_code` |
| 9 项 check | 全 true，`passed true` | 同文件 `checks`/`passed` |
| 隔离根新建 | `fresh_isolation_root true` | 同文件 |
| 真实写入 | `real_user_state_write_count 0`、`violation_events 0` | `snapshot_diff.json` |

9 项 check 的含义（`tools/run_isolated_tests.sh:177-187`）：
`test_execute_succeeded`、`exit_code_zero`、`counts_parsed`、`no_failures`、
`xctestrun_only_three_roots`（逐叶差异为空）、`isolation_home_used_by_app`
（隔离根内出现 `simigo.sqlite3`）、`isolation_cache_used_by_app`（隔离 cache 非空）、
`no_real_user_state_write`、`no_unexpected_write`。

**步骤 5：哪些摘要必须一致，哪些不必**

- **必须一致**（用于确认跑的是同一套东西）：基座 xctestrun
  `c5f53628ffc3d709…`（与 RC1 相同）、注入后隔离 xctestrun `0e76bc3e4b199fd6…`、
  `other_differences == []`、`test_targets_patched == 1`。
- **不必一致**（不得据此宣称可复现）：`SimiGo` 可执行 `e3e144ae…` 与
  `SimiGo.debug.dylib 16e46d76…` 是新构建的字节，与 RC1 的
  `6e32892f…` 不同 → 字节级可复现 **NOT PASS**，见 §10。

**副作用说明**：隔离副本写在基座同目录（`__TESTROOT__` 相对解析），
即 `build/test/Build/Products/xctestrun_isolated.xctestrun`；
它是运行产物、被 `.gitignore` 覆盖，跑完留在该目录。本次重放已复核它未被改动
（`0e76bc3e…` 前后一致）。

---

## 7. 怎样验证失败关闭与零越界写入

### 7.1 失败关闭：12 例，可重放

原始记录在 `negatives-final/transcript.txt`（对 `f18d65f` 的字节）。为了让
审查者不必相信一份手写 transcript，本轮把它做成可执行重放：
`verify_20261023/negatives_replay.sh`，输出 `negatives-replay-20261023/transcript.txt`。
本次重放结果：**12/12 rc 与 sealed 记录一致，`# deviations: 0`，脚本 exit 0**。

| # | 用例 | 触发方式 | 期望 | 实测 |
|---|---|---|---|---|
| N1 | app 缺失 | `--app <不存在>` | rc=3、不建证据目录 | rc=3，`evidence dir created? NO` |
| N2 | 基座缺失 | `--base-xctestrun <不存在>` | rc=3、不建目录 | rc=3，`NO` |
| N3 | 证据目录在真实根内 | `--evidence-dir ~/.simigo/...` | rc=3、不创建 | rc=3，`created? NO` |
| N4 | 证据目录 = `$HOME` | 同上 | rc=3 | rc=3，`refusing to use … as evidence dir` |
| N5 | 证据目录 = 仓库根 | 同上 | rc=3 | rc=3 |
| N6 | 证据目录 = `/` | 同上 | rc=3 | rc=3 |
| N7 | 未知参数 | `--bogus` | rc=2 | rc=2，`unknown argument` |
| N8 | 生成器 `--out` 离开基座目录 | `--out <别处>` | rc=3、不写 | rc=3，`must sit beside the base xctestrun` |
| N9 | 基座不是 plist | `--base-xctestrun bad.xctestrun` | rc=3、不写输出 | rc=3，`not a readable plist (…): Invalid file`，`output written? NO` |
| N10 | 基座在产物目录外 | 运行器 + 外部基座 | 失败关闭 | rc=4（生成器 rc=3 经 `exit 4` 映射） |
| N11 | 差分 allow-prefix 覆盖真实根 | `--allow-prefix "$HOME"` | rc=3、不写 | rc=3，`allow-prefix … overlaps real root` |
| N12 | 对照：合理 allow-prefix | `--allow-prefix <run3>` | rc=0 | rc=0，`real_user_state_write_count=0` |

为什么这些用例构成“失败关闭”而不是“碰巧报错”：

- N1/N2/N3 三例同时断言**成功退出码**与**目录不存在**，直接对应
  “先完成路径安全检查与前置条件验证，再执行任何文件系统副作用”
  （`tools/run_isolated_tests.sh:84-99`：app / 基座校验在 `mkdir` 之前，
  路径文本检查在 `check_evidence`，symlink 解析后再查一次）。
- N8/N9 断言**输出文件未生成**，因此“报错但已写出半个文件”也会被判失败。
- N9 额外断言 clean2 的隔离 xctestrun（`0e76bc3e…`）前后不变，
  即失败路径没有污染上一次成功运行的产物。
- N10 记录的是**降级行为**：运行器的退出码是 4（生成阶段失败），
  而不是 3。这符合脚本头部声明的 `4 xctestrun generation`，但审查者应知道
  它不是 3——这是本批唯一一个“错误码不是 3”的用例。

### 7.2 零越界写入：判据与本次自证

机制（`tools/rc_noninterference.py` + `rc_noninterference_diff.py`）：

1. 受保护根：`~/.simigo`（整树）与 `~/Library/Application Support/SimiGo`，
   角色为 `real_state`；`~/.cache/huggingface` 只取指纹，角色 `reference`。
2. 每棵树的每个文件记录 `path / bytes / mtime_ns / sha256`（≤8 MB 取内容哈希）。
3. 差分把变化分三类：`expected`（运行器自己的证据目录，经 `--allow-prefix` 显式
   授权）、`reference`（只读参考根）、其余一律 `unexpected`。
4. `violation_events` 是**事件数**，`real_user_state_write_count` 是**物理文件数**；
   `allow-prefix` 与真实根相互包含时直接 rc=3 拒绝（N11），
   因此“放宽白名单来掩盖写入”这条路是堵死的。

run3 的读数：`real_user_state_write_count 0`、`violation_events 0`、
`distinct_violation_count 0`、`reference_changes 0`；两个 real 根的
`a_files/b_files` 与 `a_bytes/b_bytes` 完全相等（8971 文件 / 32,398,426,016 B；
1 文件 / 1,068 B）。

**本次复核窗口的自证**：在 run3 之后（23:21）到现在，本轮又做了负向重放、
封存重算等动作。为此在复核结束时再取一次快照，与 `run3/snapshot_post.json`
差分（`verify_20261023/diff_run3post_vs_replay.json`）：

```
real_user_state_write_count 0   violation_events 0
distinct_violation_count 0      reference_changes 0
```

即：本轮审查动作本身对真实用户状态也是零写入。

> 边界：这些是“文件系统层面没写”的读数，不是“进程没有尝试写”的系统调用级证据；
> 运行器与差分都在普通用户权限下运行，未做 sandbox/`fs_usage` 级拦截。

---

## 8. 封存完整性（本次只读重算，未写入任何封存目录）

| 对象 | 冻结值 | 本次重算 | 方法 |
|---|---|---|---|
| RC1 app bundle tree | `842f72a68b7936fd…`（129 文件） | 一致 | 冻结驱动 `rc_artifact_identity.py`，`RC_OUT=` 本批 `verify_20261023/` |
| RC1 `SimiGo.debug.dylib` | `6e32892fe776f30b…`（28,436,352 B，UUID `DEB5F8F9-…`） | 一致 | 同上 |
| RC1 批次清单 | 601 项 | `601/601 OK`，rc=0 | `shasum -a 256 -c MANIFEST_SHA256_rc1.txt` |
| gate-closure 清单 | 222 项 | `222/222 OK`，rc=0 | `shasum -a 256 -c MANIFEST_SHA256_gate_closure.txt` |
| G2 行为证据 | `b730b950c2567a8f…` | 一致 | `shasum -a 256 …/g2-behavioral-turn21/swift-test-g2.log` |

写盘纪律：本批所有新增内容都落在 `simigo-rc1-repo-closure-20261023/` 内
（`run3/`、`verify_20261023/`、`negatives-replay-20261023/`）；
封存批次目录只被读取，冻结驱动被要求把输出写到本批目录（`RC_OUT`），
没有在 `simigo-rc1-20261023/` 或 `simigo-rc1-gate-closure-20261023/` 里产生新文件。

`simigo-rc1-tools-vendoring-20261023/run1` 原样保留，未改写、未删除。

---

## 9. 审查者检查清单（逐条可执行）

```bash
cd /Users/mr.simi/Documents/SimiGo        # ① ② ③ 在仓库内执行

# ① 提交面：三个提交、38+6+1 个文件、无 add -A 痕迹
git log --oneline -4
git show --stat 7329f59 3a89817 f18d65f

# ② 工作树与推送状态
git status --porcelain        # 期望 0 行
git rev-list --count origin/localb-b3-closure-20261016..HEAD   # 期望 3

# ③ 工具字节
shasum -a 256 tools/run_isolated_tests.sh tools/make_isolated_xctestrun.py \
              tools/rc_noninterference.py tools/rc_noninterference_diff.py

cd /Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-repo-closure-20261023   # ④ 以后在批次目录内执行

# ④ 干净检出可构建（clean2 就是 f18d65f 的干净 clone）
git -C clean2 rev-parse --short HEAD    # 期望 f18d65f
git -C clean2 status --porcelain | wc -l          # 期望 0
grep -c "TEST BUILD SUCCEEDED" build_clean2.log   # 期望 ≥1

# ⑤ 入库版运行器结果（run3）
python3 -c 'import json;d=json.load(open("run3/isolation_run_run3.json"));print(d["executed_skipped_failures"],d["passed"],d["exit_code"])'

# ⑥ 失败关闭重放（12 例，自带断言）
bash verify_20261023/negatives_replay.sh; echo "exit=$?"

# ⑦ 封存未变
(shasum -a 256 -c /Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023/MANIFEST_SHA256_rc1.txt | grep -c ': OK$')
(shasum -a 256 -c /Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-gate-closure-20261023/MANIFEST_SHA256_gate_closure.txt | grep -c ': OK$')
```

判定口径：①②③⑤⑦ 任一项不符即为“提交面/证据面不符”；⑥ exit≠0 即“失败关闭回归”。

---

## 10. 已知边界与未覆盖项（不得据本文上调任何判定）

1. **字节级可复现 NOT PASS**：clean2 的 `SimiGo.debug.dylib` `16e46d76…`
   ≠ RC1 的 `6e32892f…`；两者的 xctestrun 倒是相同（`c5f53628…`）。
   本次提交不主张可复现构建。
2. **contract 测试未执行**：见 §3“未覆盖”。207/14/0 只覆盖 app 测试包。
3. **`de362ef` 自身能否构建未实测**：见 §2.4，不作为论据。
4. **`physical_page_return` 仍 `BLOCKED`**；逐层 `forward_calls` 仍
   `NOT_INSTRUMENTED`；`restricted_production_path` 仍成立，
   不主张完整生产路径已验证。
5. **默认 `xcodebuild test` 不等价**：不设三个根时测试宿主写真实 `~/.simigo`，
   该约束在 README（第 87–103 行区间）与 CONTRIBUTING 中保留。
   注意 `CONTRIBUTING.md` 的 “Release hygiene checks” 片段仍以
   `xcodebuild test … -only-testing:SimiGoTests/ExecutionStateGraphTests` 举例，
   紧接其后的段落已声明它不能作为“不碰用户数据”的依据。这是**已知残留**，
   不是本次新增的缺陷；如需彻底消除，应另行改文档并走新的提交。
6. **N10 的 rc=4**：见 §7.1，属脚本文档声明的生成阶段失败码。
7. **`run2/` 是非权威中间态**：它在 `3a89817` 的字节上跑出 207/14/0，
   但生成器错误路径尚未修复；结论只引用 `run3`（`f18d65f` 的字节）。
8. **运行器不记录 argv**：复现命令由证据反推（§6 开头已说明）。
9. **未做的清理**：`run2/`、`clean/`、`clean2/` 全部保留（按用户指示）。

---

## 11. 回滚边界（总表）

| 动作 | 影响范围 | 会失效的验收 | 不会受影响 |
|---|---|---|---|
| `git revert f18d65f` | 1 个工具文件 | 错误路径契约（N9 变 rc=1） | 正常路径、207/14/0、隔离语义 |
| `git revert 3a89817` | 4 工具 + 2 文档 | 仓库内复现入口、负向重放 | app 语义、历史批次证据 |
| `git revert 7329f59` | 38 文件 | 三根重定向、隔离可证性、207 计数 | 历史批次证据（只读） |
| 撤销全部三个（`git reset --hard de362ef`） | 回到起点 | 上述全部 | 批次目录内所有证据文件 |

约束：三种回滚都**只影响本地分支**；因为未 push，origin 始终是 `de362ef`，
不影响任何其他人。回滚不删除批次证据（`simigo-rc1-*` 目录与 `run1/run2/run3`）。

---

## 12. 证据索引（本文每条主张对应的文件）

| 主张 | 证据文件 |
|---|---|
| 三个提交的文件与行数 | `git show --stat`；`REPORT_20261023.md` §1–§2 |
| 干净检出构建成功 | `build_clean2.log`（`TEST BUILD SUCCEEDED` 在 17186 行；命令行 13–14 行） |
| 干净检出保持干净 | `clean2/` 的 `git status`（本次复核 0 行）；`REPORT` §3 |
| 207/14/0 与成功结论 | `run3/isolated_tests_run3.log`（2357、2367 行）；`run3/isolation_run_run3.json` |
| 只注入三个根 | `run3/xctestrun_isolation.json`（`other_differences: []`、`targets 1`） |
| 零真实写入 | `run3/snapshot_diff.json`；`verify_20261023/diff_run3post_vs_replay.json` |
| 失败关闭 12 例 | `negatives-final/transcript.txt`；`negatives-replay-20261023/transcript.txt`（重放） |
| 封存未变 | `verify_20261023/rc1_identity_recheck.txt`、`rc1_manifest_check.log`、`gate_closure_manifest_check.log`、`g2_log_sha.txt` |
| 工具字节 | 本文 §1 的四个 sha256（可用 `shasum -a 256 tools/*` 复核） |
| 冻结构建参数与工具链 | `simigo-rc1-20261023/RC_SOURCE_FREEZE.json` |
| 本批文件完整性 | `MANIFEST_SHA256_repo_closure.txt`（含本文与 `verify_20261023/`） |
