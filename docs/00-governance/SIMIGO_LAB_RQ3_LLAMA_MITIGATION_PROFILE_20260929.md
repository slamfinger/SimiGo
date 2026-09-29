# SimiGo Lab RQ3 LLAMA Mitigation Launch Profile — 2026-09-29

## Decision

将已验证的 `ubatch2` mitigation 操作化为 canonical RQ3 llama-server launch
profile，并修复 concurrency curve harness 的默认 slot-free timeout。

登记：

```text
MITIGATED_LAUNCH_PROFILE_OPERATIONAL
CURVE_FREE_TIMEOUT_DEFAULT_HARDENED
```

## Canonical launch profile

新增：

```text
simigo2-experimental/scripts/rq3_llama_server_mitigated.sh
```

用法：

```bash
simigo2-experimental/scripts/rq3_llama_server_mitigated.sh MODEL_PATH
```

固定 profile：

```text
ctx2048 / parallel4 / ubatch2 / threads4 / threads-batch4
--no-cache-prompt --no-cache-idle-slots
--cache-ram 0 --slot-prompt-similarity 0.0
```

可选环境变量：

```text
LLAMA_SERVER_BIN
LLAMA_HOST
LLAMA_PORT
LLAMA_THREADS
LLAMA_UBATCH
```

额外参数会追加给 llama-server。该 profile 来自已验证的
`threads4 / ubatch2` stable run；不是通用生产 recommendation。

## Harness hardening

`rq3_llama_concurrency_curve.py` 的默认：

```text
--free-timeout-ms
```

从 `5000` 提高到 `15000`。原因是 `ubatch2` heavy cancellation curve 中
DELETE→all-long-free 可达 13.6s；原 5s default 会把慢释放误报成 failure。
显式传参的既有 artifact 不受影响。

## Smoke validation

wrapper smoke 使用相同 model 在 `LLAMA_PORT=18081` 启动：

```text
health = ok
model_path = Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
```

server log 确认 wrapper 进程启动并监听。该 smoke 只验证 launch profile 可运行，
不重复性能或 identity claim。

## Boundary

本变更不修改 Swift runtime、Execution State backend、llama.cpp 上游实现或采样
逻辑。它只固定研究用 server launch profile，并调整 harness timeout。`ubatch2`
仍会显著放大 latency；未建立生产 readiness 或通用配置结论。

## Non-claims

```text
❌ ubatch2 是通用生产配置
❌ 性能代价已接受或量化
❌ Metal kernel / graph reduction 根因已定位
❌ 所有模型 / backend / context 均已验证
```
