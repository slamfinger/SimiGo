# Track E(命名待定)Residency P3-C 结果:F2 Counter-Basis 拆解
(2026-09-21)——**终审 PASS / R-W CLOSED;P3-C SEALED**

> **状态**:数字与判别入档,待审核终判。执行顺序符合审核冻结:设计
> v0.3 PASS(69c4fc0 终审)→ **Regression Gate 三封锁(A ≡ V4 /
> D ≡ lfu_aging / C ≡ prior diagnostic)PASS** → 才采新格 B。
> 产物:`runs/P3C_F2_DECOMPOSITION_PROVENANCE_20260921/`(META +
> stdout 全文;v5/v4/v3 sha256 见 META)。工具:
> `residency_policy_simulator_v5.py`。全部读数 = **cost/effect
> decomposition,非 causal proof**;符号纪律:signed delta
> (+ = J 增加)≠ effect direction(有利/adverse)。
>
> **终审盖章(2026-09-21,审核方复核 9bc7790):P3-C Results——
> PASS / R-W CLOSED;P3-C SEALED。** 回归门确认为**程序级门位**
> (A/D 序列逐位 dd=0、C 与诊断精确一致、FAIL→exit(1) 在 B 之前);
> R-W = 70.0%(49.35/70.5),R-D NOT TRIGGERED(+1.41 J ≈ 2.0%,
> cost-increasing);恒等式经整数级(69×ext+72×rehy)精确检查。
> **冻结结论**:在本实验域、预注册判据及当前 cost/effect
> decomposition 下,P3-B 中的 F2 底座差距主要由有限窗口与
> cumulative temporal-memory basis 的差异解释;decay 对该差距的
> 独立分解贡献很小(tree +1.41 J,约占原始 70.5 J gap 的 2.0%),
> 且方向为 cost-increasing。
> **终审注记(入档边界)**:①"衰减贡献约等于零"始终理解为本轮
> F2 decomposition 下的结果(seed=42/trace 2000/B=12/H=8/W=200/
> 当前 workload/cost model/B、D 两种 decay operator),**不是对
> decay mechanism 本身的普遍判断**;② C 格措辞收窄 = "在本轮测试
> 的频率策略格中,C 为最低 J 的频率基线"(非"最强",未做广泛
> 策略搜索);③ 审核裁定**不需要 P3-D 继续拆 F2**(收益已明显
> 下降)。**下一步分叉待定夺**:① C 格脱离描述性观察成为新
> Strategy Design(须重新立项/设计/审查,不得因 1084.5 直接升级
> target);② P3-C 封存 → 回 H-P1 / nodes-out → P4 proper。

## Regression Gate(先于 B;PASS)

- **A ≡ V4**:hot 548.7(395/383)/ tree 1133.8(810/798)= P3-B
  冻结数字,**且驱逐序列与 v4 V4 引擎逐位一致(dd=0)**;
- **D ≡ lfu_aging**:hot 544.4(392/380)/ tree 1085.9(776/764)=
  P3-A 冻结数字,且驱逐序列与 v4 lfu_aging 引擎逐位一致(dd=0;
  v4 自身已经 v3 回归门);
- **C ≡ prior diagnostic**:hot 544.4(392/380)/ tree
  1084.5(775/763)= P3-A provenance decay-OFF 诊断值,精确一致;
- 参照行:lru / belady 冻结数字复现 OK;确定性自检 PASS。

## 2×2 grid(B=12;H=8;全 recency tie)

| 格 | 底座 | 衰减 | hot J (rehy/ext) | tree J (rehy/ext) |
|---|---|---|---|---|
| A | window 200 | 无 | 548.7 (395/383) | 1133.8 (810/798) |
| B | window 200 | 条目级半衰 | 554.3 (399/387) | 1145.1 (818/806) |
| C | cumulative | 无 | 544.4 (392/380) | **1084.5 (775/763)** |
| D | cumulative | dict 半衰 | 544.4 (392/380) | 1085.9 (776/764) |

## 分解(cost/effect decomposition;signed delta 由未舍入 J 计算)

| 量 | hot | tree | effect interpretation |
|---|---|---|---|
| F2-a = J(C)−J(A) | −4.2 J | **−49.4 J(\|·\| = 70.1%)** | window 相对 cumulative 降低成本(有利) |
| F2-b = J(D)−J(C) | +0.0 J | **+1.4 J** | half-decay 相对 no-decay 增加成本(**adverse**) |
| 合计 D−A | −4.2 J | −47.9 J | = 底座合计差(P3-B 冻结) |

- signed 恒等式(整数精确):(J(C)−J(A))+(J(D)−J(C)) =
  J(D)−J(A),双 workload OK(显示值 −49.4/+1.4 由未舍入 J
  −49.35/+1.41 计算;舍入表值 1084.5−1133.8 = −49.3 的 0.1 差
  系显示舍入,如实注记);
- **cross-basis contrast**(描述性,非 factorial interaction):
  hot +5.6 J / tree +9.9 J——条目级半衰加在窗口底座上**有害且大于**
  加在 cumulative 底座上(+1.4);窗口的截断已是遗忘机制,再叠渐近
  衰减只会扭曲计数。仅描述,不设出口。

## 预注册判读(tree = 目标 workload;50% 线 = 35.25 J)

| 线 | 判据 | 结果 |
|---|---|---|
| **R-W(window 主导)** | \|F2-a\| ≥ 35.25 | **49.4 ≥ 35.25,成立** |
| R-D(decay 主导) | \|F2-b\| ≥ 35.25 | 1.4 < 35.25,不成立 |

### 判别:**R-W——有限记忆窗口主导**

> **底座差异(47.9 J)几乎全部由时间记忆底座(窗口 vs cumulative)
> 解释:|F2-a| = 49.4 J(70.1%);衰减机制的贡献为 +1.4 J 且方向
> adverse(半衰使成本上升)。** hot 侧一致(底座差合计仅 4.2 J,
> F2-b = 0.0:半衰在 hot 上逐位决策中性,dd=0)。

## 机制哨兵(全部描述性;不承担归因)

| 对(workload) | dd | \|Δrehy\| | 下界 | 首分歧 step |
|---|---|---|---|---|
| C vs A(hot) | 21 | 3 | PASS | 1397 |
| D vs C(hot) | 0 | 0 | PASS | 无(逐位相同) |
| B vs A(hot) | 14 | 4 | PASS | 1228 |
| C vs A(tree) | 615 | 35 | PASS | 218 |
| D vs C(tree) | 399 | 1 | PASS | 200 |
| B vs A(tree) | 368 | 8 | PASS | 204 |

**首分歧精化(结构性)**:激活点前(step<200)窗口计数 ≡ cumulative
计数,故任何对照首分歧 ≥ 200 由结构保证(实测全部满足);恰在 200
仅当激活即刻改变决策(D vs C),否则落在其后(C vs A 218、B vs A
204)——"structural activation point"语义据此精确化,不承诺"恰在 200"。

tie_rate(纯辅助):tree 上 C=0.060 显著低于 A=0.183/D=0.143
(cumulative 计数更弥散,并列更少),描述性记录。

## 结构观察(描述性,非采纳建议)

1. **C 格 = 无衰减 cumulative LFU,在本轮测试的频率策略格中为
   最低 J 的频率基线**(tree 1084.5,低于 lfu_aging 1085.9):
   "aging"在语义上轻微有害。此为域内描述性观察——**未做广泛策略
   搜索,不构成采纳依据**;任何策略采纳 = 重新立项/新设计/新审查,
   **V0 target 与 P3-A/P3-B 冻结全部不动**;
2. B 格(窗口 + 条目级半衰)双 workload 均劣于 A(+5.6/+11.2):
   窗口截断之上叠加渐近衰减只有扭曲、没有增益,与 F2-b 的 adverse
   方向互证(描述性)。

## 诚实性注记

1. 合成 workload 单 seed;50% 线为预注册描述性约定,非统计检验;
2. signed delta 以未舍入 J 计算(−49.35/+1.41),表内 J 显示舍入
   到 0.1,差异已注记;
3. cross-basis contrast 因 B/D 衰减算子不同构,非严格 factorial
   interaction(设计 v0.3 术语边界),仅描述;
4. B 格条目级半衰语义(2^K 整数化)为设计冻结定义,其与 D 的
   floor 行为不要求同构(设计故意);
5. 回归门三封锁在 B 采集之前完成,顺序合规;所有哨兵无实现错误
   信号;
6. 不反推 Track B / M 链 / P0 系列;P0.2 经济闭合状态不变;
   belady 差距仍属 H-P1/nodes-out 域;
7. **(终审注记)"衰减贡献约等于零"= 本轮 F2 decomposition 口径下
   的结果**(seed/trace/B/H/W/workload/cost model/B、D 两种 decay
   operator),不是对 decay mechanism 本身的普遍判断。

## 决策

1. **已终判:PASS / R-W CLOSED,P3-C SEALED**(审核方复核
   9bc7790;**不需要 P3-D 继续拆 F2**——收益已明显下降);
2. **F2 拆解线封存**:R-W 达成即回答设计问题,不自动开
   "窗口 vs cumulative"下一轮;
3. **下一步分叉(待定夺,不预设)**:① 策略层讨论——C 格
   (纯 cumulative LFU)是否脱离描述性观察、作为**全新 Strategy
   Design** 重新立项(重新设计/重新审查;不得因 1084.5 直接升级
   target,当前 V0 冻结不动);② P3-C 封存,回主链 H-P1 →
   nodes-out → P4 proper;③ Track E 命名继续待定。
