# 非干预残留事件分析（round 2）

## 1. 事件

`evidence/noninterference_diff_m4.json`（`pre_round2` → `post_m4_round2`）在真实用户根上只报告 1 个变更：

| 项 | 值 |
|---|---|
| path | `/Users/mr.simi/.simigo/.DS_Store` |
| 变更类型 | modified（内容比较，非新增/删除） |
| pre | 24,580 bytes, sha256 `c4c1477b…` |
| post | 34,820 bytes, sha256 `4fb902d6…` |
| mtime | `2026-10-24T01:30:44`（+0800） |
| 其它真实根 | `~/Library/Application Support/SimiGo`（1 file / 1,068 bytes）0 变更；HF reference 根 951 files 0 变更 |

`~/.simigo` 内全部产品/研究状态 0 变更：`simigo.sqlite3`、`-wal`、`-shm`、`prefix-pool/`、`branch-checkpoints/`、`manifests/`、`logs/` 均未出现在 changed 列表中。

## 2. 内容性质

`xxd` 头 8 字节 = `00 00 00 01 42 75 64 31`（"Bud1"），`strings` 含
`bwsp` / `ShowStatusBar` / `ShowSidebar` / `WindowBounds` / `{{508, 122}, {1222, 880}}` / `viewOptionsVersion`。
这是 **Finder 目录视图元数据**（`Bud1` 容器 + `bwsp`/`lsvC` 视图块），不是 SQLite、WAL、JSON 状态或缓存负载。写入者只能是 Finder（或使用 Finder 视图 API 的 GUI 应用），产品 `SimiGo` 二进制不写 DS_Store。

## 3. 时间归属

| 时间（+0800） | 事件 | 候选进程是否存活 |
|---|---|---|
| 01:25:01 | `pre_round2` 快照 | 否 |
| 01:26–01:27 | stage A 两次启动/退出（隔离根 `m3/`） | 是，但根在 `m3/` |
| 01:27–01:31 | stage A 已退出、m4a 尚未起跑的空档 | **否** |
| **01:30:44** | **`.DS_Store` 被改写** | **否** |
| 01:31–01:36 | m4a（ES1/ES2/NC1–7/memprobe，隔离根） | 是 |
| 01:41–01:44 | stage B GUI 驱动 | 是 |
| 01:45:12 | `post_m4_round2` 快照 | 否 |

写入时刻落在**没有任何候选进程存活**的空档内，因此不能归因于本 RC 产物。当时 Finder 进程存活（pid 752），且此刻 `Finder.windows` 计数为 0——即该窗口在快照之间被关闭过，与"宿主机上有人在 Finder 里浏览过 `~/.simigo`"一致。`driver/` 下所有驱动脚本在该时段没有任何 `open`/`osascript`/Finder 调用（stage B 的 JXA 首次运行在 01:41 之后）。

## 4. 收紧验证：bracket 复测

为把"候选自身是否写用户态"从推测变成测量，追加一次紧包围的对照：
`driver/noninterference_bracket.sh` 取快照 → 启动**同一安装版**二进制（三个隔离根指向 `m3-bracket/`）→ 运行 40s → SIGTERM → 再取快照 → 差分。

结果（`evidence/noninterference_bracket.txt` / `_pre.json` / `_post.json` / `_diff.json`）：

- `exe_sha256_on_disk=dacf2fc3…`（与 round2 安装身份一致）
- 隔离根内正常生成 `simigo.sqlite3`(+`-wal`/`-shm`)、`manifests/bootstrap-report.json`、`logs/native_mlx_trace.log`
- `quit_result=exited`
- `DS_Store` bytes/mtime 在 bracket 前后完全一致（34,820 / 01:30:44）
- 差分：`violation_events=0`、`real_user_state_write_count=0`

## 5. 结论

| 判定项 | 结果 | 依据 |
|---|---|---|
| 候选产物写真实用户状态 | **否（PASS）** | bracket 前后 0 变更；产品状态文件 0 变更 |
| 全批次 pre/post 中唯一残留变更 | `.DS_Store`（Finder 视图元数据） | 内容为 Bud1/bwsp，非产品负载 |
| 残留事件归因 | **外部（Finder GUI），非候选** | 写入时刻无候选进程存活；bracket 复测 0 变更 |

按任务书"若有并发外部变化导致归因不清，记录 INCONCLUSIVE 并说明需要重测的条件"，此处**不采用** allowlist 掩盖，也不修改差分口径：原始差分保留 `real_user_state_write_count=1` 与路径清单，本节负责解释其归属，并给出可复现的收紧测量（bracket）作为主要证据。

重测条件（若需要把该项也压到 0）：在宿主机关闭所有 Finder 窗口/预览面板、且无人浏览 `~/.simigo` 的窗口期内重跑 `pre → stage A → m4 → post`；判据为 `real_user_state_write_count=0`。
