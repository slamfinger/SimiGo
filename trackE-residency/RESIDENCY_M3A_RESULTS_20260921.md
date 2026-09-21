# Track E(命名待定)Residency M3-A 结果(2026-09-21)

> **终审判定(2026-09-21):M3-A——FINAL PASS。**
>
> **正式研究结论(审核冻结句,原文入档)**:在本实验配置下,
> rehydration 后采用段表表示或连续物化表示,均保持与 resident
> control 相同的 continuation;因此,当前证据支持 continuation 对
> 表示形态具有 **config-level independence**。**该结果不构成
> residency architecture 应采用某一种 representation 的架构结论。**
>
> **47% 表述冻结**:73 MiB / 155 MiB ≈ 47% 仅为结构性载荷字节数;
> 不得写成"更高效/节省成本/更快/更优/bandwidth advantage"——效率
> 归 M4。
>
> **M3-A 的真正价值(审核表述)**:M3 后残留解释"也许只是当前
> runtime 的 continuation 恰好依赖 COW segment semantics"被直接
> 攻击——现在至少可以说 **continuation correctness 并未表现出对这
> 两种 representation form 的依赖**(config 级)。
>
> **实验链状态(审核判定表)**:M1 FINAL PASS / M2 FINAL PASS /
> M3 FINAL PASS / M3-A FINAL PASS;M3-B(OPEN)→ M3-C(OPEN)→
> M4(OPEN)。M3 冻结语句不变;M3-A 作为下一层证据:*Representation
> form → Continuation independence(config-level evidence)*。
>
> **工程审计限制正式关闭(审核方完成源码逐行核验)**:68daa06 在
> `slamfinger/mlx-swift-lm@exp/execution-state-fork` 上核验通过,
> 源码实验契约与 M3 结果文档一致(twin child/前置门/私有页外化/
> release/段表重挂/sharedRows==parent offset/96-step/offset+96/
> parent intact)。M3-A 源码(`ResidencyM3AContinuationPair.swift`)
> 亦经审核方远端核对。
>
> **M3-B 设计收紧(审核定序)**:不再三臂重复 M3-A——**只走段表
> rehydrate → continuation**,16K 与 64K 两个深度,各与驻留 control
> 逐 token 对照。轴分离:M3-A=representation 轴 / M3-B=depth 轴 /
> M3-C=topology 轴 / M4=cost 轴。M3-B 靶子 = "continuation
> correctness 是否只是浅位置 @4616 的偶然现象"。

> **首跑记录(史料)**:本文档初版记录三臂设计与两臂 96/96 结果;
> 初版状态行"待审核方终判"已被上方终审取代。 代码:`ResidencyM3AContinuationPair.swift`
> (exp 分支)。独立成对实验,不修改已 FINAL PASS 的 M3。

## 攻击的架构分叉(M3 终判定序)

> "段表只是当前实现碰巧能跑" vs "residency continuation 本身不依赖
> 表示形态"

## 设计(同父代三臂,单变量 = 重表示路径)

```
P @4096(驻留父代)
  ├── ctrl      = fork → 后缀512 → decode8   驻留全程(control)
  ├── treatSeg  = 同上 → 私有页外化(520 行/73,292 KiB)→ 重挂回
  │             驻留父代 → 仍为 COW 段表(M3 臂,成对复现)
  └── treatCont = 同上 → 全视图外化(155,212 KiB)→ 重建为连续
                表示(物化路径,M1 形态)
```

可证伪前置门:两臂外化前均 ≡ ctrl(五类状态逐元素 + next-input)✓✓。

## 结果:两臂主门均 PASS

| 臂 | 重表示路径 | 结构核查 | 主门(N=96) |
|---|---|---|---|
| seg | 私有页 → 段表重挂 | 仍为 COW 段表,sharedRows=父代 offset ✓ | **96/96 全等** |
| cont | 全视图 → 物化连续 | 全部 KVCacheSimple,offset @4616 ✓ | **96/96 全等** |

offset 三侧精确推进 +96;父代完好;11.2s 三侧 288 步 decode(描述性)。

## 意义(待终判;措辞按纪律)

1. **架构分叉在本配置下的答案**:两条重表示路径都沿 ctrl 的未来
   继续——continuation **不是**段表实现碰巧能跑;同时段表路径以
   私有页增量载荷(73 MiB,为全视图 155 MiB 的 47%)达到相同行为
   结果。**载荷字节差是结构性事实(520/4616 行 vs 全部),不升级为
   性能结论**(带宽/时间归 M4 交替对照)。
2. **表示无关性的 config 级证据**:在 rehydrate 时刻选择"不物化"
   或"物化",后续 96 步行为逐 token 相同——表示转换时机(以及是否
   转换)在本配置下不影响行为正确性。这只是 config 级,不普遍化。
3. 与 M3 合并观察:M3(段表臂)在独立实验中亦 96/96——成对复现
   一致。

## 诚实性注记

1. 单配置(35B / 4.6K / 单节点 / N=96 / 单轮);深位置与多节点的
   表示对照属 M3-B/M3-C。
2. "47% 载荷"是字节数,不是时间或带宽数字;任何效率表述归 M4。
3. 本结果不反推 Track B / M1 / M2 / M3;失败也只指向"该机制在该
   配置下不成立"。

## 决策

1. **M3-A PASS → 待审核终判;建议 M3-B(深位置 continuation)**:
   16K/64K 上重放 M3 主门(表示两路是否仍等价,按审核定夺是否成对)。
2. M3-C(多节点 continuation)→ M4(rehydration tax,交替对照)
   按序。
3. Track E 正式命名待真源定夺。
