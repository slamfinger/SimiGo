# Track E(命名待定)Residency P3-C 设计:F2 Counter-Basis 拆解
(2026-09-21)——**DRAFT v0.2 待审核;Implementation LOCKED**

> **状态**:DRAFT v0.2,待审核;设计 PASS 前不得实现、不得采数。
> **v0.1 审 = CONDITIONAL PASS**(2026-09-21,审核方复核 ff64f8e:
> 研究问题/F2-a、F2-b 拆解/A-C-D 铰链恒等式/2×2 完整性/C 先验披露/
> step-200 降级/R-W、R-D 双独立判定/R-SHARED 强度/V0 冻结边界/
> LOCKED 门位——全 PASS)。**v0.2 落两项必修**:①F2-b 符号语义
> 拆分——signed delta(+1.4 J)与 effect direction(adverse)冻结为
> 两个概念,禁混写;②格位必要性收紧——A/C/D = 最小主效应分解路径,
> B = 补齐 2×2 的交互观察格(不承担主效应归因);术语统一为
> **cost/effect decomposition(非 causal proof)**。另采纳:B/D 衰减
> 实现不同构 = 设计故意;structural activation point 术语固定。
> 前置:P3-B Results 终审 **PASS / R3 CLOSED**(072fc2f)。边界继承:
> P3-A/P3-B 封存;**V0(min(1,n/H), W=200, id tie)= 冻结 baseline,
> 永不修改**;target 定义本轮不涉。

## 0. 设计问题(审核方指引原文锁定)

> **cost-aware 决策差距,究竟来自"有限记忆窗口",还是"历史频率
> 的衰减机制",还是两者组合?**

即把 R3 已确认的 F2(计数底座差异,tree 合计效应 47.9 J)拆解为:

```
F2
├── F2-a  时间记忆底座:window(200) vs cumulative
└── F2-b  衰减机制:cumulative vs cumulative + half-decay(每 200 步)
```

## 1. 可观测基础(全部冻结/已存档数字;先验如实披露)

**可加分解恒等式(2×2 的 C 格为铰链)**:设 A = window 无衰减,
C = cumulative 无衰减,D = cumulative+半衰,则 signed 恒等式
**(J(C)−J(A)) + (J(D)−J(C)) = J(D)−J(A) = −47.9(tree)精确成立**
——F2-a 与 F2-b 的 signed 和恒等于底座合计差。违反即实现错误。

**先验诊断披露(诚实预注册)**:C 格在 P3-A provenance 对照实验中
已有一次诊断性测量(decay-OFF side-check:tree 1084.5 = rehy 775/
ext 763;hot 544.4,见 `runs/P3A_V2_RERUN_PROVENANCE_20260921/
SIDECHECK_DECAY_OFF.txt`)。据此**先验预期**(如实声明,非预断)。

**符号/方向两概念冻结(v0.2 必修①;全文强制)**:signed delta
(数学符号,+ = J 增加)与 effect direction(效果方向,有利/不利
/adverse)是两个独立概念,禁止混写,禁止用"方向为负"指代 F2-b:

| 量 | signed delta | effect interpretation |
|---|---|---|
| F2-a = J(C)−J(A) | **−49.3 J**(|·| = 70.5 的 69.9%) | window 相对 cumulative **降低**成本(有利) |
| F2-b = J(D)−J(C) | **+1.4 J**(2.0%) | half-decay 相对 no-decay **增加**成本(**adverse / cost-increasing**)——与 P3-A stale 事件 1084.5→1085.9 同源 |

signed 校验:−49.3 + 1.4 = −47.9 ✓。
本设计目的 = 以回归门级 provenance 正式确认/推翻该先验,并补齐
2×2 缺格(B),不是"验证已知答案"的仪式。

**step-200 首分歧彻底降级(结构性激活点)**:W=200 且衰减间隔=200,
窗口截断与首次半衰在 step 200 **同时首次激活**;此前窗口计数 ≡
cumulative 计数(尚无截断),故任何底座对照的首分歧必然恰在
step 200——**首分歧位置是参数巧合的结构产物,对 F2-a/F2-b 无归因
力**。P3-B v1.1 的"定位证据"措辞据此再降一级。**术语固定(v0.2):
structural activation point(结构激活点);禁用"首分歧证据支持
aging"类表述**——P3-B 历史解释以 v1.1 为准,P3-C 用本术语,不互斥。

## 2. 2×2 变体(封闭;全部 recency tie(last_access, id),F3 固定)

| 格 | 底座 | 衰减 | 身份 |
|---|---|---|---|
| A | window 200 | 无 | = **V4**(P3-B 冻结:hot 548.7 / tree 1133.8) |
| B | window 200 | 每 200 步半衰 | **新测量(唯一新语义格)** |
| C | cumulative | 无 | 正式重跑(先验诊断已存在,§1) |
| D | cumulative | 每 200 步半衰 | = **lfu_aging**(P3-A 冻结:hot 544.4 / tree 1085.9) |

**格位必要性(v0.2 必修②;审核焦点"4 格 vs 3 格"的固定答案)**:
**A/C/D 构成主效应的最小可加分解路径**(铰链路径,足以回答 §0
主问题);**B 不承担 F2-a/F2-b 主效应归因**——其唯一职能 = 补齐
完整 2×2 并观察底座×衰减交互(interaction / cross-basis
validation cell)。**3 格足以回答主问题;第 4 格用于完整因子结构
与交互观察。**

**B 格语义(预注册实现定义,定义选择列入 §6 待审)**:窗口条目级
衰减——窗口条目 (s, n) 的权重 = 2^(−k),k = floor(now/200) −
floor(s/200) 为该条目存续期间经历的半衰边界数;有效计数 = 窗口内
该节点条目权重和(衰减语义与 lfu_aging 一致:每条访问记录每跨一次
边界折半)。**整数化实现**:全权重乘 2^K,K = TRACE_LEN/200 = 10,
即 w_int = 2^(K−k),tie 比较纯整数、无浮点歧义。注:C→D 路径沿用
v3 冻结的 dict 整除半衰(freq //= 2),保证 D 与 P3-A 冻结数字回归
兼容。**B 与 D 的衰减实现不要求逐条数值同构——这是设计故意如此:
B 的目标是定义 window-base 下的独立策略,D 的首要身份是 P3-A
frozen reference;不得为"形式统一"而修改 D 的实现。**

**读数(signed)**:
- **F2-a = J(C) − J(A)**(window vs cumulative,无衰减);
- **F2-b = J(D) − J(C)**(衰减效应,cumulative 底座);
- 恒等式校验:F2-a + F2-b = −47.9(tree)/ −4.3(hot),必成立;
- **交互 = (J(B) − J(A)) − F2-b**(衰减在窗口底座上的效应与其在
  cumulative 底座上的效应之差;描述性,不设出口)。
- 符号约定(v0.2):signed delta 正号 = J 增加(成本上升);效果
  方向叙述只用"有利/不利(adverse)"词汇。

## 3. 执行协议(simulator v5)

1. **回归门(先于 B/C 采数)**:v5 引擎必须复现 A ≡ V4(P3-B 冻结
   J/rehy/ext,含驱逐序列逐位)与 D ≡ lfu_aging(P3-A 冻结),以及
   lru/belady 参照行;**C 与先验诊断值(1084.5/544.4)相等作为交叉
   核对**(预期相等——同一语义同一种子;若不等,先查实现再解读);
   任何违反 → 停,不采数;
2. 新采数仅 B、C 两格(H=8 主轮,hot/tree 双跑);变体集封闭,
   无参数网格(W=200=衰减间隔 冻结,不开 sweep);
3. 机制通道(全部描述性、降级为实现哨兵):逐对不一致驱逐决策数
   dd(双侧计步法)+ 首分歧 step(标注"结构性激活点,无归因力")+
   tie_rate(纯辅助);**行为一致性下界 dd ≥ |Δrehy| 适用于 (C,A)、
   (D,C)、(B,A) 三对,违反 = 实现错误,停**;
4. 确定性自检;五通道输出照旧;本轮不涉 P_pressure 新口径;
5. 禁止:按结果增删格子、调衰减参数、换 B 格语义重跑。

## 4. 判读(预注册;描述性;单 seed 限定)

- **主判据**(以原始 70.5 J 差距为分母,沿用 P3-B 50% 线纪律):
  **R-W** = |F2-a| ≥ 35.25(window 主导);**R-D** = |F2-b| ≥ 35.25
  (decay 主导)。**两线独立判定、可同时成立**——两因子 effect
  direction 可相反(先验即相反:F2-a 有利 / F2-b 不利),不存在
  "至多一达"约束;均不达 → **R-SHARED**(描述性出口:报告两者
  份额,结论 = 无单一主导;不证"存在共同作用机制")。
- **符号/方向纪律(v0.2)**:一律使用"signed delta(+ = J 增加)"
  与"effect direction(有利/不利)"两个概念;F2-b 先验效果方向为
  adverse(半衰使成本上升),不得写作"方向为负";不粉饰、不因
  "aging"名义回避;若 R-D 成立且 effect adverse,结论表述为
  "衰减是主要不利因素"而非正面成分;
- 交互项描述性报告;|交互| 相对 F2-b 量级显著时,记录"衰减×窗口
  存在实质交互",处置归审核,不自行开新轮;
- **术语纪律(v0.2)**:本轮是**预注册的成本效应分解(cost/effect
  decomposition),而非因果机制证明**——恒等式只保证路径上的
  cost decomposition(ΔAC + ΔCD = ΔAD),不证明真实系统的因果
  机制;不得使用"因果归因/causal attribution"表述。主效应读数由
  分解承担;机制通道(dd/首分歧/tie_rate)只作实现哨兵——与
  P3-B 三条件结构不同,勿套用;
- hot 侧一致性:hot 底座差合计仅 4.3 J,任何格子 hot 大变动视为
  异常信号,先查实现。

## 5. 边界(继承)

- 合成 workload 单 seed;B=12;H=8;C 比 0.69:0.72;W=200=衰减间隔
  冻结;结论限定 P3-A 固定实验域;
- target 与 P3-A/P3-B 全部冻结数字零改动;不反推 P0.2/Track B;
- belady 差距(tree 56.2%)仍属 H-P1/nodes-out 域,本轮不触及;
- Track E 命名继续待定。

## 6. 待审核焦点(v0.1 审已答;终审确认项标注)

① B 格组合语义——审核裁定"可以通过"(B 格语义写死为正确动作),
   B/D 不同构声明已按建议强化(v0.2);② 4 格 vs 3 格——**已答并
   落档(v0.2 格位必要性段):A/C/D = 最小主效应分解路径,3 格足答
   主问题;B = 补齐 2×2 + 交互观察,不承担归因**;③ C 格先验诊断值
   定位为交叉核对——审核"先验披露 PASS";④ step-200 降级——审核
   PASS,术语固定 structural activation point;⑤ 两线独立可同达
   结构——审核 PASS;⑥ R-SHARED——审核 PASS(保持描述性出口,
   不证共同机制)。
   **待终审项:仅 v0.2 两必修的落档质量(①符号语义拆分;②格位
   收紧 + cost decomposition 术语统一)。**
   PASS 后门位(审核方原文):v5 实现 → Regression Gate(A、D、C
   逐项封锁确认)→ PASS → **才允许采新格(B)**;此门不松。
