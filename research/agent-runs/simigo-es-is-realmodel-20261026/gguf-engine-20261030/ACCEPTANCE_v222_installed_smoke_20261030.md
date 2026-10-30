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

## 5. 复现

```bash
# 前提：安装版已启动并持有 :8000
python3 research/agent-runs/simigo-es-is-realmodel-20261026/gguf-engine-20261030/smoke3.py
```

脚本从 `/v1/models` 取当前模型 id，读数为 `smoke3.json`。
