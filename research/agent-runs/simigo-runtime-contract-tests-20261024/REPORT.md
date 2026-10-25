# SimiGoRuntimeContract 独立测试取证 — REPORT

批次目录：`/Users/mr.simi/SimiGo-Agent-Runs/simigo-runtime-contract-tests-20261024`
取证时间：2026-10-24 00:06–00:13 (+0800)
授权范围：仅验证本地提交 `f18d65f` 的 `SimiGoRuntimeContract` 契约实现与测试；不改源码、不提交、不推送、不合并、不动旧批次。

## 0. 判定

**PASS**（31/31 检查通过，判定由 `assemble_evidence.py` 从原始日志重算，非手填）。

补上的证据缺口：此前 `build-for-testing` 不编译 `SimiGoRuntimeContractTests`，
`207/14/0` 只覆盖 app 测试包；本次证明该 8 个测试文件在一个干净检出中
真正编译并执行，**77 executed / 0 failed / 0 skipped**，两次独立运行结果一致。

本判定只覆盖“契约实现 + 契约测试在 Debug/arm64/macOS 27 SDK 下通过”，
不改变 RC1 发布等级，也不代表 `v2.2.0rc1` 产品集成已通过（见 §9）。

## 1. 被固定的测试对象

| 项目 | 值 |
|---|---|
| 产品仓 | `/Users/mr.simi/Documents/SimiGo` |
| 分支 | `localb-b3-closure-20261016` |
| HEAD | `f18d65f8f312ffbb837fdf5e07125af044833854` |
| 远端跟踪 | `origin/localb-b3-closure-20261016 = de362ef4…`（本地领先 3） |
| 工作树 | `git status --porcelain` 0 行 |
| `Packages/SimiGoRuntime/Package.swift` | sha256 `e9afb4c66871262b6099f43231274eafa70197712259eec34ac2a152422e5949`（52 行） |
| `Packages/SimiGoRuntime/Package.resolved` | sha256 `5f8aa0a6f6328fb83188e841272db7f15289616c38eb16fadff98d0bdddec152` |

干净检出：`git clone /Users/mr.simi/Documents/SimiGo src/contract-checkout` 后
`git checkout f18d65f8…`。检出后记录：HEAD 相同、tracked 434 文件、
`git status --porcelain` 0 行、`Package.swift` 与 `Package.resolved` 摘要与产品仓逐字节一致。
（本地 clone 默认使用硬链接共享不可变对象，不复制工作树；对象内容由 HEAD 与摘要共同固定。）

## 2. 测试 target 归属（先证明“属于已声明 target”，再执行）

`swift package describe --type json`（`logs/package_describe.json`）：

- target `SimiGoRuntimeContractTests`，`type = test`，`module_type = SwiftTarget`，**sources = 8**
- target `SimiGoRuntimeContract`，library，sources = 10，依赖 `[]`
- 包依赖声明：`mlx-swift`、`mlx-swift-lm`、`swift-transformers`（契约 target 不依赖它们）

8 个测试源（`package_describe.json` 与 `git ls-tree -r HEAD` 双证一致）：

`NativeDeclarativeResultContractTests.swift`、`SimiGoBootstrapTests.swift`、
`SimiGoESISDatabaseG2Tests.swift`、`SimiGoESISDatabaseTests.swift`、
`SimiGoEngineRecipeTests.swift`、`SimiGoModelDiscoveryTests.swift`、
`SimiGoPathsTests.swift`、`SimiGoSettlementAuthorityTests.swift`

## 3. 执行方式

工具链：Xcode 27.1 (27A9275)、Apple Swift 6.4、target `arm64-apple-macosx27.0.0`、macOS 27.0.1。

命令（逐字，见 `run2/command.txt`；两次运行相同）：

```
SIMIGO_HOME=<run>/isolation/home
SIMIGO_CACHE_ROOT=<run>/isolation/cache
SIMIGO_STATE_GRAPH_STORE=<run>/isolation/state-graph
cd <run>/src/contract-checkout
swift test --package-path Packages/SimiGoRuntime --scratch-path <run>/scratch
```

- `--scratch-path` 指向批次目录，构建产物不落入检出，因此检出在运行后仍为 0 改动（已核）。
- 隔离根为批次内全新空目录，运行前后不删除，便于核对“是否被写入”。
- **run1**：会话内直接执行上述命令（rc 由进程退出观测，日志尾行 `Test Suite 'All tests' passed`）。
- **run2**：由 `run_contract_tests.sh` 端到端重放（新建 clone + 隔离根 + scratch），rc 由脚本写入 `run2/logs/swift_test.rc`。
- `run_contract_tests.sh` 写于 run1 之后，是**重放器**而非 run1 的生成器；run1 的原始日志为主证据，run2 用于证明可重放。

## 4. 结果

| 指标 | run1 | run2 |
|---|---|---|
| 退出码 | 0（进程退出观测） | 0（`logs/swift_test.rc`） |
| 执行测试数 | 77 | 77 |
| 失败 | 0 | 0 |
| 跳过 | 0 | 0 |
| suite 数 | 8 | 8 |
| 构建 | `Build complete!` 49.21s | `Build complete!` 47.50s |
| 总耗时 (wall) | 92.21s | 98.32s |
| 测试二进制 sha256 | `3462e3f56f4af290…`（1,915,568 B） | `5e1301ea2d743d27…`（1,915,760 B） |

两次运行的 suite 计数逐项相同（见 §5），但**测试二进制字节不同**：Debug 二进制内嵌
构建路径，`run1`/`run2` 的 scratch 路径不同。这里只能主张“同源码、同测试集、同结果”，
不能主张二进制可复现。

`swift test` 的构建图包含 1102 个编译单元（含 `mlx-swift`、`mlx-swift-lm`、
`swift-transformers`、`SimiGo2Experimental`），那是因为包内其他 target 需要它们；
**实际执行的只有 `SimiGoRuntimeContractTests.xctest` 一个 bundle**。
日志末尾 `✔ Test run with 0 tests in 0 suites passed` 是 swift-testing 的空运行汇总，
本 target 全部用例是 XCTest 风格，没有 swift-testing 用例，不构成跳过。

## 5. 8 个文件的编译与执行映射（声明 vs 执行）

| 源文件 | suite 类 | 声明 `func test*` | 执行 | 失败 | 跳过 |
|---|---|---|---|---|---|
| `NativeDeclarativeResultContractTests.swift` | `DeclarativeNativeResultContractTests` | 21 | 21 | 0 | 0 |
| `SimiGoBootstrapTests.swift` | `SimiGoBootstrapTests` | 6 | 6 | 0 | 0 |
| `SimiGoESISDatabaseG2Tests.swift` | `SimiGoESISDatabaseG2Tests` | 7 | 7 | 0 | 0 |
| `SimiGoESISDatabaseTests.swift` | `SimiGoESISDatabaseTests` | 11 | 11 | 0 | 0 |
| `SimiGoEngineRecipeTests.swift` | `SimiGoEngineRecipeTests` | 14 | 14 | 0 | 0 |
| `SimiGoModelDiscoveryTests.swift` | `SimiGoModelDiscoveryTests` | 6 | 6 | 0 | 0 |
| `SimiGoPathsTests.swift` | `SimiGoPathsTests` | 7 | 7 | 0 | 0 |
| `SimiGoSettlementAuthorityTests.swift` | `SimiGoSettlementAuthorityTests` | 5 | 5 | 0 | 0 |
| **合计** | 8 suites | **77** | **77** | **0** | **0** |

方法：对每个源文件正则提取 `class *: XCTestCase` 与 `func test*`，与日志中
`Test Case '-[Suite testName]' passed` 逐名比对。
结果：**声明但未执行 = none**，**执行但未声明 = none**，**非 passed 状态 = none**。

## 6. 隔离与真实用户状态

快照工具：仓库内 `tools/rc_noninterference.py`（快照）+ `tools/rc_noninterference_diff.py`（分类差分）。
受保护真实根：`~/.simigo`（8971 文件 / 32,398,426,016 B）、
`~/Library/Application Support/SimiGo`（1 文件 / 1,068 B）；参照根：`~/.cache/huggingface`（951 文件）。

两次运行的前后差分（`noninterference_diff.json`、`run2/noninterference_diff.json`）：

```
real_user_state_write_count = 0
violation_events            = 0
distinct_violation_count    = 0
reference_changes           = 0
```

隔离根写入：两次运行都是 **0 文件**（`isolation/` 三层空目录运行后仍为空）。
需要明确：这同时说明这三个变量对本次测试**没有被触发**——契约测试不读写
managed root / cache root / state graph store，它们用系统临时目录做 SQLite 夹具。
因此本批的隔离结论来自“真实根零写入”的直接差分，而不是“观察到了隔离根被使用”。
把“传了变量”当成“隔离已生效”的推断在这里不成立，也不被本报告采用。

## 7. 依赖解析身份

`Package.resolved` 的 12 个 pin 与实际 `scratch/checkouts/*` 的 HEAD 逐一相等（大小写归一后比对）：

| identity | revision |
|---|---|
| mlx-swift | `ef5f1b6bb24e27922189316362f3057c64261704` |
| mlx-swift-lm | `bc64ee696de102ad43fd76dd6ac01dc37f6427d3` |
| swift-transformers | `c21fdcde390313a6d98d8e33a346f2c3486c3ab0` |
| swift-huggingface | `0ece9a1ef443309d26a69af9897ee8ad82f43a9a` |
| swift-jinja | `4588064a20f3fc093c95f2f7d3359999bf30cae5` |
| tokens/others | `eventsource 86b5096a…`、`swift-asn1 3b6410f7…`、`swift-collections 98ef3c98…`、`swift-crypto da9d28d6…`、`swift-numerics 0c0290ff…`、`swift-syntax 79e4b74a…`、`yyjson 8b4a38dc…` |

完整列表见 `contract_test_result.json:checkout_facts`。

## 8. 可复现步骤（审查者独立执行）

```
B=/path/to/new-batch
git clone /Users/mr.simi/Documents/SimiGo "$B/src/contract-checkout"
git -C "$B/src/contract-checkout" checkout f18d65f8f312ffbb837fdf5e07125af044833854
mkdir -p "$B/isolation/home" "$B/isolation/cache" "$B/isolation/state-graph"
cd "$B/src/contract-checkout"
SIMIGO_HOME="$B/isolation/home" SIMIGO_CACHE_ROOT="$B/isolation/cache" \
SIMIGO_STATE_GRAPH_STORE="$B/isolation/state-graph" \
swift test --package-path Packages/SimiGoRuntime --scratch-path "$B/scratch"
```

期望：`Executed 77 tests, with 0 failures (0 unexpected)`，退出码 0。
或直接：`run_contract_tests.sh <new-run-dir>`（含快照、差分、summary 生成）。
判定重算：`python3 assemble_evidence.py`（只读日志与检出，exit 0 = PASS）。

## 9. 本判定不覆盖什么

- 不覆盖 app target 实际链接的那份 `SimiGoRuntimeContract` 副本在运行时的行为；
  本次是包内独立构建与执行，同源码、同 commit，但产物不同。
- 不覆盖 Release 配置、签名、封装、安装、GUI、真实模型、Service/HTTP、ES/IS 跨进程链路。
- 不覆盖 MLX 推理路径：契约 target 不依赖 MLX，构建图里的 MLX 只是包内其他 target 的依赖。
- 不改变 `physical_page_return = BLOCKED`、`forward_calls = NOT_INSTRUMENTED`、
  `restricted_production_path` 的既有判定。
- 不构成二进制可复现证据（见 §4 的两个二进制摘要差异）。

## 10. 边界与未做事项

- 产品仓与 Lab 仓在本次取证前后均为 0 行改动（HEAD 未变：`f18d65f`）。
- 未提交、未推送、未合并、未打 tag；未修改任何测试断言或源码。
- 未删除或改写旧批次（RC1、gate-closure、run1/run2/run3、clean/clean2）任何文件。
- 未修改封存证据；本批次所有新文件都在仓库外目录。

## 11. 证据索引

| 文件 | 内容 |
|---|---|
| `identity.txt` | run1 对象/工具链/测试文件清单 |
| `logs/package_describe.json` | target 归属与 sources 清单 |
| `logs/swift_test.stdout.log` / `.stderr.log` | run1 完整输出（77/0/0 + 构建日志） |
| `pre_snapshot.json` / `post_snapshot.json` / `noninterference_diff.json` | run1 前后快照与差分 |
| `run2/` | 由 `run_contract_tests.sh` 生成的重放运行（含自己的 identity/logs/snapshots/summary） |
| `run_contract_tests.sh` | 端到端重放器（clone→隔离→test→快照→差分→summary） |
| `assemble_evidence.py` | 判定重算器（31 项检查，exit 0 = PASS） |
| `contract_test_result.json` | 机器可读结果：对象、逐 suite 计数、二进制摘要、依赖身份、检查明细 |
| `MANIFEST_SHA256.txt` | 本批次文件摘要清单（`shasum -c` 可校验） |
