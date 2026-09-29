# BETA4-PROD-FINDINGS-1 — 2026-09-29

> v2.0.0-beta.4（build 7）生产首份真机日志的发现归档。
> 性质：**事实 + 实验入口**——A/B 结论不在此预写。
> 轨道边界：本档属于 **v2.0-beta.4 Production Findings**，不重开
> Optimization Convergence Phase（后者保持 CLOSED）。

## 1. Production Environment

- 模型 `peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX`（Qwen3.6 混合架构），
  ctx=131072，thinkOff；32 GiB Apple Silicon；swap 5.6-7.3GB 常驻。
- 负载形态：单会话连续工具循环 9 轮（22:20:49-22:23:30），
  上下文 24,856 → 28,702 token 单调增长。
- 日志：`~/.simigo/logs/native_mlx_trace.log` @ 2026-09-29 22:15-22:23。

## 2. Retention — PASS / R3 frozen

- 每轮 `[STORAGE] branchRetention retained=95-96 … budgetRemoved=0`：
  预算前置门（b37d88f）常态零 decode 早退，按设计工作。
- **真实跨越轮实测**（22:22:55）：存储越过 64 GiB，同一轮驱逐 2 对
  （freedGiB=2.34）回到 61.66 GiB；sweep 落在 cacheSave 后 ~70ms 窗口，
  当轮 ttft=858ms 无感知影响。
- 结论：crossing = 低频、批量回收、~2.3 GiB 余量的事件。
  **R1（mtime/filename 去 decode 化）冻结**；重开硬验收条件不变
  （collision/mtime 异常/fork copy/重复保存下的预算收敛性质证明）。

## 3. Checkpoint Reconciliation — profiling complete / A、B pending

**现象**：每个工具结果轮固定序列
`cacheLoad（~350ms）→ rollforwardSkip checkpointStale → rollforwardDiff
content "" ≠ null → 回退 extend（cacheEff 0.96-1.00）`。

**Timestamp 分解**（r=537f96 样本，其余工具轮同构）：

```text
22:22:13.778  [LC] RUNNING           ← gate 取得
22:22:14.124  cacheLoad 完成          ← performLoad 本体（读 safetensors
                                        + SHA-256 + restore）
22:22:14.125  rollforwardSkip        ← reconciliation 本体 ≈ ≤1ms
22:22:14.130  admission
22:22:14.946  prefill 222/222 完成
```

归因：**~346ms 全部是 performLoad 上界**（内部四段——磁盘读/SHA-256/
快照解码/ChatSession 构造——现有日志不可分，需插桩）；reconciliation
≤1ms。cacheLoad start 无埋点，346ms 为 RUNNING→cacheLoad-done 上界束紧。

**根因（rollforwardDiff 自证 + 考古）**：账本提交形态的纯 tool_call
assistant 消息 content 写 `""`（`assistantToJSON`，自 757082c / 09-11
transcript sidecar 诞生起即如此），Codex 客户端回显 `content: null`。
渲染对账 `"" ≠ null` → 每工具轮条件恢复必然 stale。
**beta.4 未制造此问题**（pre-existing）。

**结构性认识**：条件恢复只在 `reusedSession && 账本尾部含 tool_calls`
时尝试（活会话温暖可 extend 的轮次），存在理由是对冲 tool 尾轮重渲染
分叉。本日志 9/9 轮对冲未兑现、extend 全部健康——对冲当前是纯支出
（346ms/轮）；且即便 `""→null` 修复让对冲成功，346ms restore 仍然发生
（被保留而非被丢弃），节省的是 extend 段 0.4-2.2s。**修复的收益模型
据此修正。**

### 实验入口

- **实验 A（null-equivalence，已授权实施）**：仅改
  `assistantToJSON` 空 content `"" → .null`。观察 5 项：
  ① `checkpointStale` 是否消失；② restore 是否稳定成功；③ cacheEff
  保持 0.96-1.00；④ restore 后 transcript/message/binding 有无差异；
  ⑤ 总轮次延迟。成功标准 = stale 消失 + restore 语义正确 + 性能无负向
  异常（**不是** stale 消失本身）。
- **存量 checkpoint 预期**：旧形态 `""` 对新回显 `null` 有一次瞬态
  stale，其后新 checkpoint 以 null 形态稳定；观察 5-10 个工具轮确认
  无 `"" → null → ""` 振荡。
- **实验 B（hedge-skip， contingent on A PASS）**：
  `warmSession && previousMode == extend && previousCacheEff ≥ 0.95 →
  skip restore`。三态对照：baseline（restore→stale→extend）/ A
  （restore→成功）/ B（不 restore→直接 extend）。`0.95` 仅为实验阈值，
  不写死为产品语义；最终设计须回答"restore 预期收益何时覆盖 ~346ms
  固定成本"。

### 实验 A 结果（2026-09-29 23:07，真机 9 工具轮 + 1 总结轮，PASS）

执行形态：`build/release-exp-a` Release 构建（含 d3961bb），探针客户端
以 Codex 同款回显驱动（assistant content:null + 字符串化 arguments），
会话 `expa1/main`，垫底文本将上下文撑至 ~8.3k（90KB 中文经 BPE 压缩
低于预期的 22.5k——规模注记见下）。

| 观察项 | 基线（22:20 生产日志） | 实验 A（本轮） |
|---|---|---|
| `checkpointStale` | 6/6 工具轮 stale | **0/9** |
| 条件恢复 | 必然 skip | **`action=rollforward` 9/9 稳定成功** |
| cacheEff | 0.96-1.00 | **1.00 ×9**（首轮 cold 0.00 除外） |
| transcript/binding | — | bindingGen 1→10 连续；[TOOL] 链合法；**anomaly=0 / REJECTED=0 / unknown_tc=0**；rawB=emitB |
| 轮次延迟 | TTFT 1.6-5.8s @25-28k | wall 1.47-1.5s、TTFT ~1.0s @8.3k |

- 无 `"" ↔ null` 振荡：history 2→20 单调，checkpoint 一轮转换后稳定
  null 形态。
- 附带发现：restore 成功后 completion 行 vendor 自报 `mode=extend` 且
  `cacheHitTokens = cacheTokens` 全额——恢复态会话的下一轮生成在 vendor
  账本视角与活会话 extend 同形（rendering/attribution 无新歧义）。
- **规模注记**：本轮上下文 8.3k（非生产 27k），restore 本体在该规模
  ≈1-10ms；生产规模的 restore 成本（~346ms）未在本轮复测。A 的五项
  语义/一致性观察全部成立；**B（hedge-skip）在生产规模下的延迟收益
  对照仍需 25k+ 真机负载**。
- **判定：A = PASS**。B 解锁，独立 commit 待授权。

## 4. Token Export — deterministic noCacheAvailable / capability investigation pending

- 每轮 `poolTokenExportFailed ×13-14 err=noCacheAvailable`（全边界），
  同模型同会话 9 轮 100% 复现；同轮 message 级 `poolExport` 成功、
  `cacheSave` 成功。指向 vendor `savePrefixSnapshot` 对该模型混合缓存
  （Qwen3.6 GDN 系）不支持前缀快照。
- **非 beta.4 回归**（#4 仅改哈希计算；B-6 为 beta.3 功能）。
  best-effort、无正确性影响；但 token 级跨会话共享在该模型为死功能，
  且失败边界不进 dedup 集合 → 每轮重试全部边界（噪音 + 重复失败调用）。
- **待收集证据**（回答"暂时性 vs 永久 unsupported"）：①非混合缓存模型
  同路径；②重启后同模型；③`poolRescan` 中是否存在该模型历史 token
  snapshot。收集齐再议 namespace 级 negative-capability 锁存。

## 5. Binding / Tool Lifecycle / Swap — no action

`bindingGen=1→9` 单调；`[TOOL] REQUESTED→VALIDATED→RESULT` 全链合法、
零 anomaly；`rawB=emitB`（过滤器零吞没）；`[LC]` 全链健康；
`prefillStep=2048` 选档正常；swap 5.6-7.3GB 为当前硬件形态。
beta.4 核心路径 9/9 轮无 corruption / 回退 / 泄漏。

## 6. Experimental Plan

- **A：null-equivalence** — 已授权，本档提交后实施（独立 commit +
  差分测试 + CPU-only 回归）；真机观察 5-10 工具轮。
- **B：hedge-skip** — contingent on A PASS（独立 commit、独立真机对照）。
- **C：token export 观察** — 持续收集，不与 A/B 混。

## 7. Scope Boundary

本档与 A/B 实验不重开 Optimization Convergence Phase（CLOSED）。
A/B 属于 Production Findings 轨道；结论（无论正负）回写本档。
