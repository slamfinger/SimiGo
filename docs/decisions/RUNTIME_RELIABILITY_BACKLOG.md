# Runtime 可靠性封口 Backlog（Runtime Reliability Backlog）

日期：2026-09-11
状态：生效（P0 立即执行）
背景：三模型对照排查（docs/experiments/MODEL_COMPATIBILITY_MATRIX.md）结束后的
优先级重排。本阶段目标不是"支持更多模型"，而是：

> 任何模型出了问题，SimiGo 都能准确告诉你：是协议、session、cache、tool、
> 资源、取消、模型本身，还是底层 MLX。

## 边界纪律（❌ 永不做）

- ❌ 自己实现 Qwen35 decode / prefill / speculative decoding / 段编译
- ❌ 为 3D shape 写 SimiGo workaround
- ❌ fork MLXLMCommon 内部实现
- 上述属于 mlx-swift-lm / MLX upstream。SimiGo 发现问题 → 整理可复现 case 上报。

## P0 —— 可靠性封口 ✅ 定版（2026-09-12）

```text
P0 Runtime Reliability Baseline
────────────────────────────────────
P0-1  Generation failure classification    DONE
P0-2  Watchdog                            DEFERRED
P0-3  Session single-concurrency           DONE
P0-4  Cancellation / drain / release      VERIFIED
P0-5  KV fingerprint consistency           DONE

Memory lifecycle
────────────────────────────────────
Session LRU                               VERIFIED
Memory telemetry                          VERIFIED
NativeMLX cache release                   VERIFIED
512 loader                                DEFERRED
```

### P0-1 Generation 错误分类 ✅（已实现）

现状缺陷：所有失败路径在 LC 里都是 `reason=cancelled_or_failed`，
无法区分是谁出了问题。

分类词表：

| reason | 语义 |
|---|---|
| `completed` | 正常完成 |
| `cancelled_by_client` | 客户端断连/取消（context 已 closed） |
| `cancelled_by_runtime` | Runtime shutdown / 配置重载触发停止 |
| `cancelled_internally` | 推理引擎内部取消（连接仍存活，含 tool 早停） |
| `model_execution_error: …` | generateHandler 抛出的非取消异常 |
| `generation_timeout:<phase>` | watchdog 超时（P0-2 暂缓；词表保留为未来接入位） |

实现锚点：
- `ConnectionContext.finishLifecycle(success:failureReason:)`；
  失败且未显式分类时回落 `cancellationFailureReason()`
  （`cancelledByRuntime` > `closed` > 内部取消）。
- `HTTPServer.stop()` 对全部 context `markCancelledByRuntime()`。
- 6 个 generation handler 的 catch 块写入 `failureReason`。

### P0-2 Generation watchdog / 分阶段超时（❌ 暂不实施——用户决定 2026-09-11）

不做粗糙的 request timeout（Qwen3-Coder 冷启动 TTFT 25–33s 属正常）。
分阶段 deadline，全部经 RuntimeTuning 可配：

| deadline | 语义 | 建议默认 |
|---|---|---|
| first_event | stream 进入到首个 Generation 事件 | 180s（冷启动含 kernel JIT） |
| decode_stall | 相邻 token 间最大间隔 | 30s |
| tool | 保留位（工具执行在客户端） | — |

超时 → 取消任务 → 按 P0-1 分类上报 `generation_timeout:<phase>`，
session gate 释放路径复用现有 DRAINING/RELEASING。

### P0-3 Session 单并发契约 ✅（已实现）

官方 ChatSession 非 thread-safe（单 task/thread 使用）。
改造已落地：`QUEUED→RUNNING` 的所有权移交给推理层——
`RuntimeLifecycleCoordinator.transition(to:.running)` 移入
`NativeMLX.generate` 的 gate 获取闭包内（转换失败按取消处理），
6 个协议 handler 不再自行置位 RUNNING。

效果：全局串行化下，排队请求的 LC 保持 QUEUED 直至真正拿到 gate；
被取消的排队请求直接走取消路径（不再产生虚假 RUNNING）。

**回归记录（2026-09-12 实测发现，已修复）**：P0-3 改造只给 6 个
handler 中的 4 个补了 `CREATED→QUEUED`（Chat 非流式、Completions
非流式、Responses 两条）。**Chat 流式与 Completions 流式漏补**——
注册后直接进 `generate`，gate 闭包从 CREATED 撞 `→RUNNING`
（表外迁移）→ INVALID → 转 CancellationError → 旧代码静默吞掉，
SSE 已发头、无 error chunk、无 `[DONE]`，客户端无限等待
（表象：3 分钟无响应/永远 Thinking，与 suspend 无关——失败节奏
即客户端轮次节奏）。修复：两处补 `transitionToQueued()`；
四处 `catch is CancellationError`（Chat/Completions × 流式/非流式）
按取消契约给终态——流式发 error chunk + `[DONE]` + close
（客户端仍连接时），非流式发 503。教训：把状态迁移挪进共享层时
必须枚举全部调用方；静默 catch 会把协议层缺陷变成客户端挂死。

### P0-4 Cancellation → drain → release 强保证 ✅（回归断言已入仓）

现状已有 CANCELLING → DRAINING → RELEASING 骨架与 session gate
按 task 完成释放的语义。补强：官方明确 stream 提前停止必须取消底层
generation task，否则 cache lock 可能被一直持有。验收标准：
取消后同 session 下一请求必须能立即获得 gate（回归断言）。

**E = VERIFIED WITH HARNESS TRANSPORT FLAKINESS**：Runtime 机制验证通过
（两次独立实机：RST → ~0.2s [CANCEL] → drain/release → E2 requeue，
0.7s 完成）；2026-09-12 矩阵一次因 TCP RST 未被服务端感知而产生
测试层失败——归因测试层传输 flake，非 Runtime 缺陷。harness 重试
加固列为独立测试工具改进，不与 P0 验收绑定。

✅ 已实现并实机验证：回归骨架收编入仓 `tools/harness/`
（场景 cancel_requeue 断言"取消后 B 15s 内 response.completed"，
实测 elapsed=0s；官方 ChatSession onTermination 自动取消内部 task）。

### P0-5 KV cache / token ledger 一致性 ✅（已实现）

封口已落地：`ManagedSession` 增加 `kvFingerprint`（KVCacheSettings
的 String(describing:) 指纹，类型为 Equatable）；复用判定加入
`existing.kvFingerprint == kvFingerprint`——KV 配置变更时旧缓存
一律失效，新 ChatSession 按新配置全量 prefill，杜绝
"旧 KV cache + 新 KV 配置继续复用"。

## P1 —— 能力与可观测

- **Model Capability Matrix 正式化 ✅（P1-1 v1 已实现）**：
  下一站 **P1-2 Responses Contract**：usage projection / ledger /
  cached_tokens 已受控实测 VERIFIED（2026-09-12 三轮观测，
  见 experiments/MODEL_COMPATIBILITY_MATRIX.md），
  剩真实 Codex client-level acceptance 终验；
  Responses 层消费 Runtime 真实状态（GenerationResult/ledger），
  不自建事实。随后 **P1-3 Tool Governance Contract**：
  Contract 先行（TOOL_REQUESTED/VALIDATED/REJECTED/DISPATCHED/RESULT/FAILED
  + 结构化 reason），Runtime 层能力，NativeMLX 与 Llama.cpp 共享。
  `ModelCapabilityContract`（backend/architecture/contextLength +
  capabilities/runtime/protocolEndpoints 三段）挂到 `GET /v1/models`。
  三态 `CapabilityStatus`（supported/unsupported/unverified）——
  未实测保持 unverified，不以无证据推断 unsupported；
  运行约束（concurrency/cacheInvalidation/constraints）独立于能力段，
  不反向驱动 Runtime。已实测族：qwen3_5_moe / qwen3_moe
  （兼容矩阵 2026-09-11/12），其余架构族 unverified。"模型加载成功 ≠ 支持所有协议能力"。
- **Responses 协议完善**：P2 字段（created schema 子集、usage 实测值、
  reasoning 事件）按官方定义补齐。
- **Tool governance 结构化**：`TOOL_REQUESTED/VALIDATED/REJECTED/
  DISPATCHED/RESULT` 事件 + 结构化拒绝原因（undeclared_tool /
  invalid_arguments / schema_mismatch / tool_disabled / timeout）。
- **Unified Memory telemetry**：model weights / KV cache / draft /
  runtime allocations / swap pressure；不使用 CUDA 式 GPU/CPU 二分。
- **Remote Runtime Observability（Queue Visibility）**：
  5.1 候选首项，观察窗口（2026-09-13→09-19/20）后实施；
  窗口内 LAN 排队痛点实锤则提级。
  事实基础：全局生成串行（`serializeGeneration=true` → `__global_generation__`）；
  排队请求 LC 保持 QUEUED 不虚假 RUNNING（P0-3）；
  `SessionGenerationGate.waiters` 真实 FIFO（`LifecycleGates.swift`）；
  `X-Request-Id` 已随响应头下发；SSE 心跳（801cb89）已解决连接存活。
  缺口：LAN 客户端只见「连接活着但无 token」，无法区分正常排队与卡住——
  QUEUED 事实只存在于本机 trace，Runtime Truth 缺 Remote Observability。
  方案（不改 OpenAI 主协议 / 不复制 queue / HTTPServer 不自建队列防双事实源）：
  Gate 增只读快照（不动 acquire/release）→ Lifecycle 提供 request state
  （`state(of:)` 已有）→ HTTPServer 增只读 `GET /v1/runtime/requests/{id}`。
  一期仅 state（CREATED/QUEUED/RUNNING/terminal）；二期 position/ahead——
  前置条件是 `Waiter` 目前无 requestId 关联（仅 id:UUID+continuation），
  需把 requestID 传入 `withExclusive`（小接口扩展），position 计算须容忍
  排队中取消（`cancel(id:key:)` 移除）。`phase: PREFILL`、ETA、Web UI、
  SSE 私有 runtime comment、OpenAI chunk 私有字段全部暂缓。
  适用边界（诚实声明）：只服务 SimiGo-aware 客户端（自研 LAN 客户端 /
  运维查询 / 面板）；标准 OpenAI Agent（Codex / Claude Code）既不轮询
  私有端点也不解析 SSE 注释语义，只能得到心跳级活性——设计内行为，
  不对其承诺排队可见性。

## P2 —— 已完成/外部

- 兼容性回归矩阵：docs/experiments/MODEL_COMPATIBILITY_MATRIX.md ✅
- MLX upstream issue：外部（素材：19:44 sample 栈 + 三模型对照 + draftN 对照
  + S1 B>1/T=1 差异记录）
