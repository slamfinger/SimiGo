# Branch-Fork 解决途径探索：从「分支功能」到「分歧免疫机制」（2026-09-18）

**性质**：设计探索（未动工；5.1 评审输入）
**前置**：lessons/reconnect-counter-render-loop-2026-09-18.md（第三形态死循环）、
lessons/cancel-mid-prefill-poisoned-session-2026-09-17.md、
kv-fork-checkpoint-experiment-2026-09-17.md（A1-A4 验收）、
BRANCH_FORK_PROTOCOL_DRAFT.md

## 0. 理论支点：恢复会话的分歧免疫性

今天全部浪费（fork-no-rewind 909 万 tok/4 天、单会话 39.5 万）的机制前提是：
**活会话有 token 账本** → 引擎每轮全模板渲染并与账本比较 → 键序不稳定等
造成分叉 → GDN 不可回卷 → 全量重渲。

而 checkpoint 恢复的会话是 **raw-cache + fragment-continuation：没有账本**
（lesson §恢复语义，A1-A3 实证）→ PromptCacheReusePolicy 无可对照对象 →
**结构上不可能分叉，也就永远不需要回卷**。每轮只评估新消息 fragment
（实测 17–209 tok，TTFT 0.17–0.74s）。

推论：**Branch-Fork 的真正价值不是"并行探索分支"，而是"分歧免疫"**。
这把 fork 从一个可选功能变成分歧税的直接对策——前提是免疫性在长程
工具密集会话上成立（A2 只验了两轮，见 §5 验证目标）。

## 1. 途径梯度（按集成深度）

### 途径 0：手工工作流（今天可用，零代码）

客户端在健康点调 `fork_from_branch`（每 ~20 轮或大上下文增量后），
翻车后以同 sessionId + fork 分支的 logicalBranchId 继续对话——
executionKey 原生支持，恢复会话走 delta 契约，秒级回血。
**局限**：要求客户端集成并预判风险点；本质仍是"事前买保险"。

### 途径 1：同 key 滚动前滚（roll-forward）——本探索的核心提案

**关键简化：不需要影子分支。** `loadSessionCache` 对同名 key 是覆盖语义
（已实证）——checkpoint 文件 + 同 key 恢复就够了，fork API 也不必参与
（fork 是并行探索语义；防分歧只需 save + load 同一个 key）。

运行时循环：

```text
每轮成功后：
    saveSessionCache(key)          ← checkpoint = last known good（含 GDN 状态）
下一轮准入前：
    risk = 自产 assistant 参数键序 ≠ 字典序   ← 确定性检测（零成本，见 §2）
    ├─ risk==false → 活会话 extend（现状，最便宜）
    └─ risk==true  → loadSessionCache(key) 覆盖活会话
                      → fragment-continuation 跑本轮（无账本 → 无分歧 → 只付 delta）
```

**代价账**（80k 会话实测推算）：saveCache 序列化 ~175MB，NVMe 1–3s/轮
（持 gate，计入轮间延迟）；对比分歧税期望值（频率 1/4-8 轮 × 税 300–490s
≈ 50–90s/轮）——**20–100× 占优**。节流策略：每 K 轮或新增 ≥4k tok 才
save（K≤4，fixture 数据可校准）。

**风险启发式的精度**：分歧源 = 自产 assistant 消息在下轮被模板重渲染时
键序重排（swift-jinja 字母序）。SimiGo 自己生成并持有该消息的原始 JSON——
**生成序 vs 字典序不等 ⇒ 本轮高风险**，完全本地可判定（TodoWrite 形态
命中、Bash 单键形态安全的既有统计与此检测器一一对应）。

### 途径 2：预测式准入合流（与已登记的 P1 预测式预驱逐同层）

途径 1 的 risk 信号 + est + warmTokens 三者合一进 admission 行：
`action=allow / action=rollforward / action=evict-then-rollforward`。
内存维度先行（swap>2GB 且 warmTokens>预算 → 先逐他后滚前），
统一为「一条 admission 决策线」。

### 途径 3：上游根治（已定稿待发）

Qwen35ToolRestartRule 消除分歧**源**（工具续跑边界键序分叉）——
途径 1 是本地绕行，途径 3 是让 risk 恒为 false 的终局。两者不冲突：
roll-forward 对上游修复前的一切分叉形态（含客户端重写、账本自然失配）
都有效。

## 2. 这套途径同时治什么

| 问题 | 是否覆盖 | 机制 |
|---|---|---|
| fork-no-rewind 分歧税（909 万 tok/4 天） | ✅ 核心目标 | 高风险轮免账本化 |
| 重连计数器死循环（重试从零） | ✅ | 重试轮从 checkpoint 恢复 = 秒级，循环不再自持 |
| suspend/sleep 清场 | ✅（DRAFT 既定） | checkpoint 跨挂起存活 + 首请求自动恢复 |
| 冷启动首请求 | ❌ 合法成本 | — |
| isPrefix 门禁拒收（P1，80 次/4 天） | ❌ 独立问题 | prefixDiff 诊断 + 容错决策 |
| 90k decode 退化（6 tok/s） | ❌ | 唯有上下文压缩/收尾 |

## 3. 诚实边界与代价

1. **免疫性是机制推演 + 两轮实测（A2），未经长程验证**。第一实现切片必须
   携带显式验证目标：工具密集长会话跑在恢复分支上，数 fork-no-rewind
   是否恒为 0。若引擎在 fragment 路径仍内部全渲染（与 A2 的 209 tok
   矛盾），免疫性不成立，途径 1 作废——这是可证伪的。
2. **每轮 saveCache 的 gate 占用**：轮间 +1–3s 延迟（80k 时）；小会话
   （<5k，175MB→~11MB）可忽略。节流常数挂 RuntimeTuning。
3. **遥测盲区扩大**：恢复轮无 mode/cacheEff（官方原值透传），模态统计的
   extend 账本会"漏计"这些轮——`prefill_stats.py` 需补一档
   `mode=fragment`（凭 cacheTokens 存在 + mode 缺失识别）。
4. **逐出交互**：恢复会话的 cacheTokens 正常上报 → admission 的
   warmTokens 记账不受影响（A2 实证 cacheTokens=5413 在列）。
5. **取消语义**：恢复轮中途取消 → 缓存事务归零的是"本轮 fragment"，
   checkpoint 仍在 → 重试 = 再恢复（秒级）。死循环的自持条件被拆除。

## 4. 验证与基准

- **442fbf fixture 是天然的 before 曲线**：6 次 fork-no-rewind / 395,389 tok /
  1,792s。实现后跑同形态工具密集工作负载，`prefill_stats.py` 对照：
  fork-no-rewind 计数应 → 0，新增 fragment 轮（restore 秒级 + delta）。
- 基准 fixture 追加 after 段落，形成 before/after 对账。

## 5. 建议动工切片（修订：验证先行——2026-09-18 外审加闸）

原版 §5 直接列生产切片；按外审加闸修订为两段。**20–100× 是期望收益估算，
不是已兑现数字**——兑现前必须先测。

### Phase A：测量实验（先做，产出 = 数字而非行为）

宿主式实验（`SIMIGO_ROLLFWD_EXP=1` 门控，沿 BranchForkTests 惯例）：

- 合成长程工具密集会话：多键嵌套 tool_calls（TodoWrite 形态）× 50 轮，
  上下文爬坡 10k→80k
- 每轮测量：`saveSessionCache` 耗时、`loadSessionCache` 耗时、
  fragment token 数、TTFT、内存峰值、swap
- 连续 roll-forward 10 / 20 / 50 轮三档
- **验收观测量（免疫性证伪点）**：fork-no-rewind 恒 0、fragment 持续低
  token、TTFT 稳定；若任一轮内部进入全模板渲染，免疫性理论重审
- **隐藏成本核查**：saveCache 是否随上下文线性劣化为新瓶颈（I/O、内存复制、
  cache serialization）
- 产出：真实经济账（替换本档 20–100× 估算）+ 与 442fbf fixture 的
  before/after 对照

### Phase B：生产切片（仅当 Phase A 经济性成立）

原 §5 五项：`RuntimeTuning.rollforwardEnabled`（默认关灰度开）+ 节流常数、
saveSessionCache 每成功轮后调用（节流）、风险检测器（自产参数键序，纯函数
可单测）、高风险轮 loadSessionCache(key) 覆盖 + trace `action=rollforward`、
长程免疫性验证作为验收条件。

## 6. 定谱（外审认可，2026-09-18）

> Branch-Fork 的下一阶段不是"优化 fork"，而是**验证 checkpoint-recovery
> 能否作为一种分歧隔离执行模式**。

三层定位：Qwen35ToolRestartRule 治分歧源（让 risk 少发生）；roll-forward
是运行时保险（risk 发生也不进活账本→rewind→重渲）；GDN checkpoint/rewind
是引擎层长期可回卷能力。正常走 extend，高风险前 roll-forward 到最近健康
checkpoint，从恢复态续 fragment——直接减少**需要进入 cold prefill 的
工作量**，而非给 cold prefill 排队。
