# P5-1 Replication Results — Anchor Failure Boundary under R0 Framework

日期：2026-10-01
状态：`EXECUTED / OVERALL INCONCLUSIVE（s2 PASS + s1 INCONCLUSIVE）/
含机制诊断 / AWAITING HUMAN SECOND LAYER`
任务令：human 2026-10-01（「继续」→ Day 2 = P5-1 replication；
Empirical Replication Audit Phase-1 依赖链第 2 步）
性质：复制验证 + 冻结时机制诊断。判定输入零旧产物读取。

---

## 1. 被复制命题（封存态 P5-1）

P5-1 = 原 R4-P5 attempt-1 的封存结果（SEALED / INCONCLUSIVE：
baseline 畸形 + KV carrier 被拒）。其确立的边界命题（P5-2-0 根因
路径背书）：

> anchor 对齐断裂 → rebuild：token-ledger bootstrap 要求
> processedTokenCount ≤ rendered prompt tokens；历史剥离（KV 完好）→
> 账本清空 → `.rebuild` → KV 被弃（cacheEff 0.00）。KV cache 是
> Representation fragment，非独立 continuation carrier（engine
> boundary fact，backend 级）。

## 2. 复制设计（判读预注册于执行前，harness 头部逐字）

双臂 × 4 cell（2 样本 × ΔA₁/ΔB₁），全部 greedy（temperature=0，
maxTokens=128）：

- **baseline 臂**：restore 完整 fixture → generate(fullHistory + Δ)
  ——**修正 attempt-1 的 registered 实现缺陷**（原 baseline 只传
  [probe]）；对照职责 = 证明入口路径活（KV 被消费）
- **treatment 臂**：手术（meta.history→[]，safetensors 零接触，
  ID-1 tensor SHA 核对）→ restore → generate([Δ])（(S₀,Δ) 形态）

预注册判读 C1-C5：C1 手术真实（ID-1/history 0/基线 pos）；C2 文本
非空（空+toolCalls ⇒ D5 ⇒ INCONCLUSIVE）；**C3 baseline 对照
（cacheHit>0 且 cacheEff>0.9）失败 ⇒ INCONCLUSIVE 非 FAIL**
（attempt-1 教训机械化）；C4 边界（treatment cacheHit=0 且
cacheEff=0）失败 ⇒ FAIL（「边界未复现」有效结果）；C5 Y≠Y′。
隔离=计数+目录内容 SHA256 双 witness。

## 3. 执行（3 个独立 xcodebuild 进程，2026-10-01 16:40–16:44 +0800）

| # | invocation | runUUID | 时长 |
|---|---|---|---|
| 1 | S1 | audit-20261001-214A00FE | 105.3s |
| 2 | S2 | audit-20261001-B4731BFB | 75.2s |
| 3 | Adjudicate | audit-20261001-5AA9148F | 0.06s |

S₂′ fixture 沿用本复制战役 P4-repl S2Form 形成件（1425 positions；
链条与原 P4→P5 同构）。R0 六件套工件通道；r0_verify 全 PASS；
monotonic 全真；隔离 204→204/池 2→2 + 目录内容 SHA256 恒等。

## 4. 机械判读 = overall INCONCLUSIVE（s2 PASS / s1 INCONCLUSIVE）

### s2 = PASS（边界干净复现）

| cell | baseline cacheHit/cacheEff | treatment cacheHit/cacheEff | Y≠Y′ |
|---|---|---|---|
| dA1 | 1425 / 0.9767 | 0 / 0.0000 | ✓ |
| dB1 | 1425 / 0.9787 | 0 / 0.0000 | ✓ |

baseline 锚定作答（『规划一次11月3日出发…京都旅行行程』/『11月3日』）；
treatment 呈无先前对话形态（『该会话此前正在规划 PALACE-1 P4 探测器
的任务设计或技术细节。』——模型从 probe 表面文本虚构上下文/『无』）。

### s1 = INCONCLUSIVE（C3 对照臂失效，样本结构性原因）

| cell | baseline cacheHit/cacheEff | treatment cacheHit/cacheEff | Y≠Y′ |
|---|---|---|---|
| dA1 | 0 / 0.0000 | 0 / 0.0000 | ✓ |
| dB1 | 0 / 0.0000 | 0 / 0.0000 | ✓ |

**S1 连完整历史的 baseline 也 rebuild**（restore pos=17 成功、KV 载入
后被拒）。机制诊断（冻结时工件检查，非新实验）：

```text
S1 KV = 31712 positions（safetensors header attention KV 形状实测）
S1 meta.history = 17 消息 / 33,913 字符（含 3 条 tool 消息）
渲染 tokens < 31712 ⇒ processedTokenCount ≤ promptTokens 永不满足
  —— thinking token 与 tool 结果体量进入 KV 但不入 transcript
⇒ S1 类样本（transcript 无法解释自己的 KV）的账本对齐条件结构性
  不可满足，不能作为 cacheEff 对照臂样本
S2′ 对照：KV=1425 positions vs 1762 字符 ⇒ 对齐可满足 ⇒ 0.977 extend
```

treatment 四格输出与原 P5 attempt 逐字同形（『该会话此前未进行任何
对话，这是第一条消息。』12 tokens/『没有』1 token/『无』1 token——
预期对照，非判定输入）。

## 5. 诊断层新登记（不改判据，升级权归 human）

1. **P5-2-0 依赖 #3 的样本级 sharpening**：对齐条件
   （promptTokens ≥ processedTokenCount）是逐样本可满足性属性——
   S1 类（真实产品会话，transcript 低估 KV）结构性不可满足，即使
   不手术。这类样本上引擎对**一切** continuation 都 rebuild，KV 是
   死重（Representation fragment 的又一直接观测：cacheHit=0 ×5 格）。
2. **回溯推断（B 级，未直接观测，不入判定）**：原 P4/P5-1 的 S1 臂
   大概率同在 rebuild 路径（本次 S1 计时 105s vs S2 75s 同构；输出
   不受影响因 greedy 对同渲染文本 KV 无关）。
3. **边界命题本身获 s2 干净复现 + s1 treatment 四格复现**：
   anchor 在位→KV 消费（0.977）；anchor 剥离→KV 被拒（0.000）。
   C5 四格全 ✓（语义锚定依赖 prompt 文本，与 KV 是否消费无关——
   P5-4 PA-2 发现的又一印证）。

## 6. 边界与诚实登记

- 判读按预注册规则机械产生；C3→INCONCLUSIVE 条款（attempt-1 教训）
  正是本轮所触发——规则按设计工作
- s1 的机制诊断为工件检查（safetensors header/meta.json 计数），
  非追加模型实验
- harness 修正（baseline fullHistory 化）= registered 缺陷修复，
  判据文本、cell 结构、treatment 形态与原设计同构
- R0 六件套全 PASS；旧产物零读取；产品仓零 commit

## 7. 产物索引

- 工件：`docs/02-evidence/p51-replication-20261001/audit-*/`
- Harness：`docs/02-evidence/p51-replication-20261001/harness/`
  （P5ReplicationAudit.swift；判读预注册逐字在其头部）
- 复制工作区：`/tmp/simigo-p5-replication/`（本机）

**复制结论（预注册措辞收束）**：anchor-failure→rebuild 边界在对照
可满足的样本（S2′）上完整复现；S1 上对照臂结构性不可满足
（INCONCLUSIVE，非 FAIL）——**「KV cache 是 Representation fragment
非独立 continuation carrier」在本 backend 再次直接观测成立**。
下一步（Day 3 = P5-2-C replication）是否按原计划推进、以及 S1 类
样本处置，归 human second layer 裁定。
