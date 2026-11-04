# 审计简化线 · 官方 ChatSession 迁移踩坑记录

日期：2026-09-12
分支：main（自 audit-simplify-2026-09-11 收敛，52935cc）

## 背景

审计简化线删除自研 KV 推理栈、改走官方 mlx-swift-lm `ChatSession`（后钉到 main `238ad74`）。
目标是三指标：首字延迟（TTFT）、KV/prefix 复用命中率、流式输出。
本文记录该过程中真实踩到的坑，格式遵循 docs/lessons/README。

## 1. OpenAI 字符串化 arguments 与官方 Codable 不兼容（已修复，77eefab）

- **现象**：tool 轮之后每轮 `reuse=false`，TTFT 回到 33-45s 全量 prefill。
- **证据**：`prefixMismatch index=6 role=assistant historyTool=true incomingTool=false`。
- **根因**：OpenAI 协议回传的 `function.arguments` 是字符串化 JSON；官方
  `ToolCall.Function.arguments` 是 `[String: JSONValue]`。纯 Codable 解码必然失败，
  `try?` 静默吞成 `[]` → assistant 回灌丢失 tool_calls → prefix 判断失败 → 每轮重建。
- **处理**：解码前把字符串形态规范化为对象（两种形态都接受）。
- **失败方案**：手写消息签名比对（DefaultMessageGenerator 渲染）——表示漂移随时打破它，
  且渲染器输出形状不是契约。
- **影响范围**：所有经 HTTP 回灌 assistant/tool 消息的路径。
- **长期结论**：跨边界解码失败禁止 `try?` 静默吞；协议的字符串形态要在边界规范化。
- **是否需要 ADR**：否。

## 2. 复用判定有两层，不能混（已按官方分层）

- **现象**：`reuse=true` 但 TTFT 仍 89s（物理 KV 未必命中）；反之物理命中也不代表会话该续。
- **根因**：会话连续性（这个请求续哪个 session）与 KV 物理复用（cache 前缀裁到哪）是两层。
  官方 main 的 token 账本（PromptCacheReusePolicy）在 session 内部做 token 级调和，
  外部只需要保证：同 storageKey 续用、每轮只传**增量**消息（传全量会在内部 conversation 重复）。
- **处理**：SimiGo 只做会话连续性判定（语义签名 role+content+toolFlag）；
  KV 前缀管理全权交给官方账本，命中情况用官方遥测观测
  （`cacheEfficiency`/`cachedPromptTokenCount`/`cacheStatus()`）。
- **长期结论**：不要在应用层重写 token 级前缀比较——那是造轮子；
  `Chat.Message.Tool` 载荷 fileprivate，外部本就不可内省，客户端回显不变量是唯一可依赖的。
- **是否需要 ADR**：建议（分层契约：SimiGo 管逻辑会话，ChatSession 管物理 KV）。

## 3. mlx-swift-lm 3.31.4 与 main 的能力差（已钉 main 238ad74）

- **现象**：3.31.4 无 `cacheStatus()`/token 账本；以 `history:` 初始化的 session
  首轮全量 prefill；重建 session = 全量 prefill（16.5K token ≈ 33-45s @ ~370 tok/s）。
- **证据**：promptTime≈ttft 在所有 rebuild 轮成立。
- **处理**：包约束改为 `branch = main`，Package.resolved 锁 commit（可复现）。
- **长期结论**：升级包前读目标 commit 的源码，release notes 不代表能力面；
  钉分支必须同时提交 Package.resolved。
- **是否需要 ADR**：否（记录于本文件即可）。

## 4. 上游删除不完整是本仓高频模式（三次实锤）

- **现象**：`RuntError.duplicateRequestId` 删了枚举留了使用点；
  `RuntimeLifecycle.swift` 整删留 5 个调用点；TraceLogger 瘦身删 `rawProcessOutput`
  留 Service.swift 4 处调用。每次都直接编译断裂。
- **处理**：每次拉取后立即全量编译验证；修复取向=跟随上游意图（删调用点/换等价 API），
  不复活已删类型。
- **长期结论**：删除类型/方法时必须全仓 grep 调用点并编译；
  本仓上游会在轮次之间 force-push 改写历史——提交本地修复前先 `fetch`，
  推送被拒时先重新评估谱系，不要盲目重试。
- **是否需要 ADR**：否。

## 5. 状态机与调用点必须同进退（FORCE_RELEASED 未决）

- **现象**：每个正常完成的请求都打出
  `FORCE_RELEASED from=CREATED reason=unexpected table rejection`。
- **根因**：Chat/Completions 的 `transitionToQueued/Running` 调用被移除后，请求终身停在
  CREATED；finish 阶梯从 CREATED 出发被迁移表拒绝，走 FORCE_RELEASED 兜底。
- **影响**：功能不受损（收敛原则保证必达 RELEASED），但状态机形同虚设、日志持续报警。
- **长期结论**：移除某个状态迁移调用时，迁移表与守卫要同步收缩；
  这是 P2 遗留，修复前 FORCE_RELEASED 行保留作为信号。
- **是否需要 ADR**：修复时补。

## 6. "一次性输出"排查结论：先分清服务端与客户端（无需改动）

- **现象**：用户感知推理完成后输出一次性到达。
- **证据**：Chat（`sendImmediateSSEChunk`）、Completions、Responses
  （`enqueueResponsesEvents`）三条链路均为逐块发送；路由 `stream==true` 才进流式处理器。
- **根因**：客户端请求未带 `stream:true`，非流式按协议必须整包返回。
- **长期结论**：排查流式问题先确认客户端请求形态（`curl -N` + `stream:true`），
  再怀疑服务端缓冲。
- **是否需要 ADR**：否。

## 7. 长期分叉的两条线，缝合合并不如按最新完成代码收敛（已执行）

- **现象**：audit-simplify（53+ 提交）与 main（文档/实验 10+ 提交）分叉后，
  缝合合并冲突 7 文件，且 TraceLogger 等文件两边语义已分叉。
- **处理**：按用户决策，main 强制重置到最新完成代码（52935cc），
  旧 main 存入备份分支（backup/main-20260912-43647cf）供 cherry-pick。
- **长期结论**：功能线验证期不与 main 缝合；收敛时以最新完成代码为准，
  被替代侧先备份再弃。收敛前把经验沉淀进 docs（本文）。
- **是否需要 ADR**：否。

## 8. 环境事实：本机 35B MoE prefill ≈ 370 tok/s，页出敏感

- **证据**：rebuild 轮 promptTokens/promptTime 线性吻合；v4.5 时代即有
  "35B 权重页出致 decode 掉速"的专项修复（Admission 预算计入权重）。
- **长期结论**：32GB 机器上 16GB 权重 + KV 的组合逼近 wired memory 天花板；
  简化线只剩粗粒度 22GiB/4GiB 上限。若 TTFT 非单调波动再现，
  优先怀疑页出而非代码（v4.5 的 Admission 权重预算是候选恢复项）。
- **是否需要 ADR**：若复现则评估。
