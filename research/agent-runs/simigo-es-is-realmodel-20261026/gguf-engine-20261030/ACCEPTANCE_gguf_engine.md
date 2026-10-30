# GGUF（llama.cpp）引擎补齐与 4 槽实验 — 2026-10-30

路线 04 遗留阻塞项：`~/.simigo/bin/llama-server` 是 49,984 B 的 Mach-O 加载器，`@rpath`
指向 `~/.simigo/build/llama.cpp/bin`，但该目录缺失 → 引擎不可加载，GGUF 4 槽端到端被阻断。
本轮补引擎并取读数。实验只读用户状态：不写 `~/.simigo/simigo.sqlite3`、不占 8000 端口、
不改安装版、不改 `~/.simigo/bin/llama-server`（sha256 前后一致）。

## 1. 引擎来源与装配

| 项 | 值 |
| --- | --- |
| 上游 | `https://github.com/ggml-org/llama.cpp`，master `e0f142d5ddc1461ce721644d92af33db23545105`（2026-10-30 检出；sha 由 `git ls-remote` 取得） |
| 源码包 | codeload tar.gz，37 MB（`~/Library/Caches/simigo-llama/llama.cpp-master.tar.gz`） |
| 构建 | cmake 4.3.3 + Ninja，`-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=ON -DLLAMA_BUILD_SERVER=ON -DLLAMA_CURL=OFF -DLLAMA_OPENSSL=OFF -DGGML_METAL=ON -DGGML_BLAS=ON` |
| 产物 | `llama-server` 0.8.0-dev（ggml 0.28.0），含 `libllama-server-impl.dylib`、`libllama-common.0`、`libmtmd.0`、`libllama.0`、`libggml{,-cpu,-blas,-metal,-base}.0` |
| 装配位置 | `~/.simigo/build/llama.cpp/bin/`（shim 的 rpath；只补动态库，不替换 shim） |
| 加载验证 | `~/.simigo/bin/llama-server --version` → `version: 0.8.0-dev … Darwin arm64` |

关键哈希：

```
2e4c0e9eecbacfc01bde25f4d245d8d01bfd56e3081b4d0122fffc707d6d9604  libllama-server-impl.dylib
e9c81370f5eba5c9534f5ed46fb853f4e8a1315693b8c23ad279c3d45d58a5a4  libllama.0.8.0.dylib
27ebc9599c8a2c0e90ae845ce71cea408c0c08d4ab09e05371a9fbc86fdcaa29  libggml.0.28.0.dylib
e15e01c0fb6b56d689e7c1a7bfbff34e6385d1379a84f264aca164db6ea59ffe  ~/.simigo/bin/llama-server（未改动）
```

**与产品内置 pin 的偏差（须记录）**：`EnvManager.ensureDefaultEngineManifest()` 把 llama.cpp
锁在 `0878f7c304cc13915c831ae17694534c94940176`（2026-10-18，build 11720）。本轮补的是
2026-10-30 的 master，原因是 shim 的 ABI 只依赖 `llama_server(int,char**)` 单符号，而 pin
对应的源码构建产物在本次网络窗口不可复现；**发布前若要让产品内建安装与本地装配一致，
应重跑 `0878f7c` 构建并替换 `~/.simigo/build/llama.cpp/bin/`**。这是引擎来源差异，不是
产品行为差异。

## 2. 实验（真实 GGUF 模型，4 槽）

- 模型：`LFM2.5-24B-A2B-Q6_K.gguf`（18 GB，`~/.cache/huggingface/hub/models--LiquidAI--LFM2.5-24B-A2B-GGUF/snapshots/0912d33…/`）
- 启动参数 = 产品 `BackendConfig.llama` 的 GGUF 参数（`Service.swift:113-136`）：
  `--parallel 4 --slots --cache-prompt --cache-type-k q4_0 --cache-type-v q4_0 -ngl 999 -b 1024 -ub 512 --ctx-size 16384 --flash-attn on --jinja`
- 脚本：`engine_parallel4.py`（证据同目录）；`summary.json`、`server.log` 为原始读数。

| 读数 | 值 |
| --- | --- |
| 引擎就绪（模型加载完） | 2.0 s（热缓存；冷盘首次 12.0 s） |
| `/slots` 槽数 | 4（id 0–3，全部 idle） |
| 4 路并发批耗时 | 24.05 s（各带 326–551 completion tokens，思考通道开启） |
| 标记校验 | 4/4 `carries_own_marker=true`；`foreign_markers=[]`；`foreign_markers_in_any_channel=[]` |
| 第 5 路（全部结算后） | 正常准入，仅带 `ENGINE[ECHO]`，零外来标记 |
| 槽位使用 | 日志 `print_timing: id 0/1/2/3` 各 18/11/10/10 行 → 四槽均参与；第 5 路复用 `id 0` |
| 峰值 RSS | 19.96 GB（32 GB 机器；全程无 MLX 驻留、安装版未运行） |

判据：**4 个请求同时在途时，4 个槽同时生成；每个请求只看到自己的标记；全部结算后
新请求立刻复用槽位。** 这关闭了「llama.cpp 4 槽端到端被环境阻断」中的引擎侧阻断。

## 3. 边界（不证什么）

- **不是产品 HTTP 入口的读数**：本轮引擎由脚本直接起在 59997 端口，没有经过
  `HTTPServerChat`/`RequestAdmissionScheduler`。产品侧 4/4 绿仍是 rerun6–rerun10 的 stub
  读数；两侧拼接不构成「产品 GGUF 4 槽端到端 PASS」。
- **未验真实 4 客户端**：`--parallel 4` 下 3 客户端与 4 客户端的产品语义仍未取真实读数。
- **模型思考通道**：该模型默认输出 `reasoning_content`，正文为空时 `max_tokens` 会被思考
  吃尽；判据必须同时看两个通道（本轮已按此判定）。
- **引擎版本**：master 而非产品 pin `0878f7c`，见 §1 末段。
- 产品侧「启动后端」仍需 UI 操作：`SIMIGO_HEADLESS_ROLE` 只提供 produce/consume/memprobe/
  tracepilot，均不启动 HTTP 监听；`SIMIGO_ENV_BOOTSTRAP=1` 只做供给，不监听。因此
  「安装版 + GGUF + 4 客户端」必须在人工启动窗口里做。
