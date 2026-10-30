# v2.2.2 安装版真机冒烟（3 客户端）— 2026-10-30

本轮取的是**已发布二进制**的运行时读数，补上 `RELEASE_NOTES_v2.2.2` 里「未在安装版上验证」这一条。
证据脚本与原始 JSON 见同目录 `smoke3.py`、`smoke3.json`（JSON 由脚本直接写出，未经手工编辑）。

## 1. 身份（先核身份，再取读数）

| 项 | 值 |
| --- | --- |
| 安装位 | `/Applications/SimiGo.app` |
| 版本 | `CFBundleShortVersionString 2.2.2` / `CFBundleVersion 32` |
| 可执行文件 sha256 | `2261b1d7949868a38f378dc2e085ff8cfe90554e55ea1c6ab5a7fc4cbdf70e1d`（与 `SimiGo-v2.2.2-32-2261b1d7.dmg` 内一致） |
| 服务进程 | pid 33868，`argv[0] = /Applications/SimiGo.app/Contents/MacOS/SimiGo`，启动 15:38:46 |
| 监听 | 该 pid 持有 `*:8000` |
| 模型 | `peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX` |

服务由 owner 从菜单栏手动启动（无 headless 监听），符合既定前置。

## 2. 读数

先一次 warmup 触发模型加载，随后 3 路并发（ALPHA / BRAVO / CHARLIE），`temperature=0`、`max_tokens=64`、非流式。

| 请求 | 状态 | 墙钟 | 正文 | 自带标记 | 外来标记 |
| --- | --- | ---: | --- | --- | --- |
| warmup | 200 | 34.33 s | `WARMUP[OK]` | — | — |
| ALPHA | 200 | 7.53 s | `MARK[ALPHA]` | 是 | 无 |
| BRAVO | 200 | 11.54 s | `MARK[BRAVO]` | 是 | 无 |
| CHARLIE | 200 | 9.55 s | `MARK[CHARLIE]` | 是 | 无 |

- 3 路并发总墙钟 **11.55 s**（≈ 最慢一路），`finish_reason` 均为 `stop`。
- warmup 34.33 s 含 35B 模型首次加载 + 冷 prefill；此后 RSS 才驻留。
- 响应体**不含 `usage` 字段**（`usage: null`），这是本构建非流式 chat 的实际形状，记录在案，不作好坏判定。

## 3. 落库增量（只读副本对账）

在 warmup 之前与全部请求结算之后，各复制一次 `simigo.sqlite3{,-wal,-shm}` 三件套（`mode=ro` 打开副本，不动真库）：

| 表 | 前 | 后 | 增量 |
| --- | ---: | ---: | ---: |
| `chat_messages` | 289 | 296 | +7 |
| `settlements` | 307 | 314 | +7 |
| `information_demands` | 198 | 201 | +3 |

## 4. 边界（不证什么）

- **不是并发生成的读数**：MLX 路径仍是 `serializeGeneration=true` 全局单飞，本窗口的生成只有 1 s 级，串行与并发在墙钟上不可分辨。这 11.55 s 只能读作「三路在途、上下文互不串」，不能读作「三路同时生成」。
- **行数增量只能聚合对账**：4 次请求（1 warmup + 3 并发）对应 `chat_messages` +7、`settlements` +7、`information_demands` +3；按请求逐一归因需要 `request_id`/`state_id` 关联，本轮未做。不据此判断「哪一轮没落库」或「有无重复结算」。
- 未覆盖：流式、`/v1/responses`、工具调用、取消/断连、GGUF 后端、真实第三方 Agent 客户端。
- 本次读数只对可执行文件 `2261b1d7…0e1d` 有效。

## 5. 追加：owner「已启动 llama」后的实际拓扑（2026-10-30 15:42）

owner 启动后复核监听者，**不是产品受管后端**：

| 项 | 值 |
| --- | --- |
| `*:8000` 监听者 | `llama-server` pid 34819（`~/.simigo/bin/llama-server` 直接启动） |
| 启动参数 | `--model …Cyber-Tiel-Coder-35B-A3B-GGUF-MTP… --port 8000 --host 127.0.0.1 --parallel 1 --cache-prompt --slots --ctx-size 131072 …` |
| `/slots` | **1 个**（`total_slots: 1`） |
| `/health` | `{"status":"ok"}`（引擎形状，无 `model` 字段） |
| `SimiGo.app` | pid 33868 **仍在运行**，但已不再持有 :8000 |

后果（不是推断，是拓扑）：产品 HTTP 入口此刻不可达，请求直接打到 llama.cpp；`--parallel 1`
意味着即使发 4 路也只会有 1 个槽。**这一窗口不能产出「产品 GGUF 4 槽」读数，也不能产出
level-4 读数。** 要取该类读数，需要二者之一：停掉这个独立引擎后在菜单栏用产品启动 GGUF
后端（产品按 `--parallel` 配置传参），或把独立引擎换到非 8000 端口再启动产品监听。

## 6. 复现

```bash
# 前提：安装版已启动并持有 :8000
python3 research/agent-runs/simigo-es-is-realmodel-20261026/gguf-engine-20261030/smoke3.py
```

脚本从 `/v1/models` 取当前模型 id，读数为 `smoke3.json`。

## 7. 追加：owner 在菜单栏启动 GGUF 后端后的读数（2026-10-30 15:45–15:54）

### 7.1 拓扑：这次引擎是产品的子进程，但产品入口仍不在链路上

| 项 | 值 |
| --- | --- |
| `127.0.0.1:8000` 监听者 | `llama-server` pid 35459，**PPID = 33868**（`/Applications/SimiGo.app/Contents/MacOS/SimiGo`） |
| 启动参数 | `--model …Cyber-Tiel-Coder-35B-A3B-GGUF-MTP… --port 8000 --host 127.0.0.1 --alias 0bbcf3cc… --parallel 1 --cache-prompt --slots --cache-type-k q4_0 --cache-type-v q4_0 -ngl 99 -b 1024 -ub 512 --ctx-size 131072 --flash-attn on` |
| 产品自身监听 | `lsof -a -p 33868 -iTCP -sTCP:LISTEN` **为空** |
| `/slots` | 1 个（`id 0`，`n_ctx 131072`） |
| `/health` | `{"status":"ok"}`（引擎形状，无 `model` 字段） |
| 驻留 | 引擎 RSS 20.4 GB；模型 blob 21 GB；测试开始前已加载约 7.5 min |

产品日志（`~/.simigo/logs/native_mlx_trace.log`，该文件同时接收产品日志与引擎 stderr）：

```
[15:45:03.219] 🧩 llama-server 参数: … --parallel 1 --cache-prompt --slots …
[15:45:05.174] 🧩 llama.cpp 性能配置: parallel=1 | ngl=99 | specNMax=2 | flash-attn=on
```

代码侧对应：GGUF 分支走 `ProcessRuntime`（`Service.swift:958-969`），只有 `HTTPServer` 的三处构造
（`NativeMLX.swift:457`、`RemoteOpenAIRuntime.swift:53`、`OversizedRuntime.swift:97`）才带 ES/IS、
结算与准入层。**所以 GGUF 模式下产品只负责拉起引擎，请求由客户端直连 llama.cpp。**

### 7.2 读数：4 路并发（`smoke4.py`，15:54:27–15:54:33）

| 标记 | HTTP | 耗时 (s) | 内容 | 自带标记 | 外来标记 |
| --- | --- | --- | --- | --- | --- |
| ALPHA | 200 | 2.08 | `MARK[ALPHA]` | 是 | 无 |
| BRAVO | 200 | 4.73 | `MARK[BRAVO]` | 是 | 无 |
| CHARLIE | 200 | 3.02 | `MARK[CHARLIE]` | 是 | 无 |
| DELTA | 200 | 3.89 | `MARK[DELTA]` | 是 | 无 |

并发墙钟 4.73 s，全部 `finish_reason=stop`。第 5 路（同 `user`、换 session 的 ALPHA 重试）
200 / 0.84 s / `MARK[ALPHA]`。

引擎日志把「只有 1 个槽」坐实：四个请求全部落在 `slot id 0`，`print_timing` 依次出现在
15:54:29.6（task 22）、30.5（task 19）、31.4（task 20）、32.3（task 21），间隔 0.86–0.9 s，
第 5 路 33.1（task 114）——**串行完成，不是同时生成**。

DB 对账（只读副本）：`chat_messages 296→296`、`settlements 314→314`、`information_demands 201→201`、
`information_reuse_events 3→3`，库文件 mtime 保持 15:40。**GGUF 模式下这 5 次请求在产品侧零写入**，
与 7.1 的代码路径一致（没有 `HTTPServer` 就没有结算/ES/IS）。

### 7.3 边界

- **不是 4 槽并发读数**：本次 `--parallel 1` 是默认值；`SIMIGO_LLAMA_PARALLEL` 只在引擎被拉起时
  读一次（`Service.swift:117-119`，上限 4），要取 4 槽读数必须以该环境变量重启 App。这一窗口没有做。
- **不是产品语义读数**：准入、结算、答案复用、IS 检索在 GGUF 路径上根本不存在（7.1），
  零交叉只说明引擎单槽在串行服务时不串内容。
- 脚本传入的 `user` 字段 llama.cpp 不用于隔离，不能据此推断会话身份。
- 内存边界：35B GGUF 已占 20.4 GB（总 32 GB），4 槽的额外 KV 占用未测量。
- 只对可执行文件 `2261b1d7…0e1d` 与 shim `e15e01c0…` 有效。

### 7.4 复现

```bash
python3 research/agent-runs/simigo-es-is-realmodel-20261026/gguf-engine-20261030/smoke4.py
```

原始读数 `smoke4.json`，参数与槽时序分别见 `spawn_args_20261030.txt`、`slot_timeline_20261030.txt`。
