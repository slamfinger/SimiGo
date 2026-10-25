# 隔离运行器仓库化：实现与验证记录

- 批次：`simigo-rc1-tools-vendoring-20261023`
- 日期：2026-10-23
- 授权性质：用户"建议批准运行器参数化放入 `tools/`"。
  **这不是提交授权**：本批未 commit、未 push、未改冻结批次。
- 结论：仓库内运行器已实现，并用**入库版脚本自身**产出新证据
  （207 / 14 / 0、真实写入 0）。工作区改动未提交。

## 1. 交付物（工作区，未提交）

| 文件 | 行数 | sha256（前 16） |
|---|---|---|
| `tools/run_isolated_tests.sh` | 207 | `b7acb4b9078c4447` |
| `tools/make_isolated_xctestrun.py` | 160 | `18f022849127f61b` |
| `tools/rc_noninterference.py` | 121 | `b0baf601d639266c` |
| `tools/rc_noninterference_diff.py` | 156 | `35d06f6f071707e5` |
| `README.md`（+24 / -0） | — | `21217f0495251fbd` |
| `CONTRIBUTING.md`（+23 / -0） | — | `317073c5f9428702` |

三份 Python 与一份 shell 均无主机路径、批次名或 SDK 版本号硬编码
（`grep -n '/Users/\|mr\.simi\|SimiGo-Agent-Runs\|gate-closure-2026' tools/*` 返回空）。

## 2. 从批次脚本到仓库工具

| 批次内硬编码 | 仓库内做法 |
|---|---|
| `$B/derived`、`$B/isolation` | `--app`、`--evidence-dir`（默认落在仓库 `build/`） |
| 白名单前缀含批次目录名 | sentinel `.isolation-root` + 证据目录与受保护根**双向包含**检查 |
| `SimiGo_SimiGo_macosx27.0-arm64.xctestrun` 写死 | 在产物目录 glob 发现，必须恰好 1 个否则退出 |
| `REAL_STATE_ROOTS` 写死两台绝对路径 | 快照条目自带 `role`，差分侧从 `real_state` 派生 |
| 复用旧隔离根 | 每次重建 `home`/`cache`/`state-graph`（D4 需要冷 pool） |
| 无 allow-prefix 与真实根的重叠判断 | 相互包含即拒绝 |

## 3. 用入库版脚本实跑（非批次记录复用）

命令与结果：

```
tools/run_isolated_tests.sh \
  --app $V/products/Debug/SimiGo.app \
  --evidence-dir $V/run1 --tag tools-run1
→ Executed 207 tests, with 14 tests skipped and 0 failures (0 unexpected)
→ ** TEST EXECUTE SUCCEEDED **
```

- 汇总：`run1/isolation_run_tools-run1.json`
  - `executed_skipped_failures = [207, 14, 0]`，`exit_code = 0`，`duration_s = 123`
  - 9 项 check 全 `true`，`passed = true`
  - `noninterference`：`real_user_state_write_count = 0`、`violation_events = 0`、
    `distinct_violation_count = 0`、`reference_changes = 0`
  - 隔离根内容：home 500,622 B / cache 20,344,107,252 B / state-graph 0 B
- xctestrun：`targets = 1`、`other_differences = []`、
  `sha256 = f2444ae4e18ef7e8…`
- 被测 app：从批次产物复制，可执行 sha
  `f30ad77331ed4533f0b897dd181d5e869aba2f9aba7f2238874e70994c101326`，
  与批次原件逐字节一致。
- 与批次 run4 的差异说明：xctestrun 摘要不同（三根绝对路径不同），
  其余（catalog 结构、被测二进制、套件计数）相同；**不把 run4 当作本次结果**。

## 4. fail-closed 负向验证（均不产生测试执行）

| # | 用例 | 期望 | 实测 |
|---|---|---|---|
| N1 | `--evidence-dir ~/.simigo/should-not-exist` | 拒绝、不建目录 | rc=3；目录未创建 |
| N2 | `--evidence-dir $HOME` | 拒绝 | rc=3 |
| N3 | `--app /nonexistent/SimiGo.app` | 拒绝 | rc=3；消息含完整路径 |
| N4 | 生成器 `--out` 不在基座 xctestrun 目录 | 拒绝 | rc=3（`__TESTROOT__` 说明） |
| N5 | 差分 `--allow-prefix $HOME` | 拒绝（覆盖真实根） | rc=3；未写输出文件 |
| N6 | 对照：合理 allow-prefix | 通过 | rc=0，`reference_changes = 0` |

已知粗糙处（未修，属行为记录）：N3 在报告 app 缺失前已创建空的证据目录；
该目录不在任何受保护根内、也不触发隔离根清理，故不是安全缺口。

## 5. 本轮只读复核（未写入任何证据文件）

- `git`：HEAD `de362ef4`，暂存区 0 项。
- RC1 身份重算（只读）：tree `842f72a6…`（129 文件）、
  dylib `6e32892f…`，与冻结身份一致。
- 封存清单重算（只读）：RC1 清单 601/601 通过、0 处不符；
  gate-closure 清单 222/222 通过、0 处不符。
- 口径说明：gate-closure 批次在上一轮“记录发布决定”时被更新
  （决定 md/json、报告、自检、清单 mtime 22:36–22:39；自检 17/17、
  `failed: []`、清单 222 行）。本轮只读复核，未写任何批次文件。
- `RC_SOURCE_FREEZE.json` 逐文件比对：34 个文件中 33 个字节相同；
  唯一变化是 `SimiGo/App/ExecutionStateGraph.swift`
  （新增 `SIMIGO_STATE_GRAPH_STORE` 覆盖分支）。

## 6. 工作区真实范围（供提交决定参考）

| 类别 | 数量 | 说明 |
|---|---|---|
| freeze 内 tracked 修改 | 11 | 其中 10 个仍与 freeze 摘要一致 |
| 隔离修复 tracked 修改 | 4 | TraceLogger、LOCALBHostRuntime、BranchForkTests、PrefixPoolDailyPathE2ETests |
| 文档 | 2 | README、CONTRIBUTING |
| 新增工具 | 4 | `tools/` 四个文件 |
| freeze 内 untracked | 23 文件 / 16 条目 | 逐字节未变 |

即：相对冻结快照，新增变化 11 个文件（1 个 tracked 内容变化 + 4 个 tracked 新改
+ 2 文档 + 4 工具）。

## 7. 重要限制：只提交"文档 + tools"不足以闭合“仓库自可复现”

在 HEAD `de362ef4` 上检查（只读）：

| HEAD 状态 | 影响 |
|---|---|
| `TraceLogger.swift` 仍硬编码 `~/.simigo/logs` | 隔离不生效，运行器会判定越界写入 |
| `EnvManager.swift` 无 `SIMIGO_HOME` / `SIMIGO_CACHE_ROOT` / `SIMIGO_STATE_GRAPH_STORE` | 三根重定向不存在 |
| `ExecutionStateGraph.defaultStoreURL()` 无覆盖分支 | 同上 |
| `Packages/SimiGoRuntime/Package.swift` 已声明 `SimiGoRuntimeContract` 产品，但其 `Sources/` 未跟踪 | HEAD 本身不可构建 |

因此：新检出者拿到 HEAD + `tools/` 后，运行器会**失败关闭**（正确行为），
但无法复现 207/14/0。要让“仓库内可复现测试流程”真正成立，
提交面必须包含隔离改动集（15 个 tracked + 23 个 untracked 源），
而不只是 6 个文件。这是本次审计新发现的范围问题，本批未擅自处理。

## 8. 未做的事

- 未 commit、未 push、未 `git add`。
- 未改动 `simigo-rc1-20261023` 与 `simigo-rc1-gate-closure-20261023` 任何文件。
- 未清理真实用户目录、未复用旧隔离根。
- 未改变产品默认行为、推理、缓存或测试断言。
