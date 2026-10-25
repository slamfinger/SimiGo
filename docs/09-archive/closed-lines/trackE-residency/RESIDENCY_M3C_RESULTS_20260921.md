# Track E(命名待定)Residency M3-C 结果(2026-09-21)

> **终审判定(2026-09-21):M3-C Topology Continuation——FINAL PASS
> (源码级)。** 审核方实际读取 `30b61e6` 的 commit/diff/完整实验文件
> `ResidencyM3CTopologyContinuation.swift`,确认:GDN offset 修正
> 全链路落实(捕获→外化→恢复→独立 gate,四节点全 GDN layer 进入);
> 树序重挂为源码实现而非文字描述(A1/B1 重挂到已重挂的 A/B);主
> continuation gate 无结构性问题(control 全程未外化,treat 消费
> 单元元数据 next-input)。
>
> **三条审计收紧注记(不阻断 PASS,不补跑,原样入档)**:
> 1. **post-continuation lineage/history gate 不对称**:当前显式覆盖
>    A/A1 分支,B/B1 未建立完全对称的独立历史 gate;B/B1 仍受主
>    continuation、前置 lineage、结构门、sibling isolation 约束。
>    属 observability completeness 问题,非实验路径错误。前向纪律:
>    后续 topology 实验采用双分支对称 gate。
> 2. **parent integrity 表述收窄**:该 gate 实际验证的是 parent
>    attention KV cache(`KVCacheSimple`),不应扩大为"整个 parent
>    Execution State bit-intact"(parent GDN/LMOutput.State 未纳入)。
>    冻结表述 = "parent attention cache remained element-exact"。
> 3. **"pairwise distinct"措辞过强**:代码检查 A≠B、A1≠B1、A≠A1,
>    未检查全部六对;准确表述 = "sibling trajectories distinct,
>    with A and A1 additionally distinguished"。
>
> **冻结结论(审核原文)**:在当前 35B 模型、单节点、COW segmented
> representation、给定 execution tree topology、各节点独立 residency
> cycle、suffix512、decode8、continuation horizon 96 的实验配置下,
> A/B/A1/B1 四个 execution node 在 externalize → release → tree-order
> reattach 后,均保持与各自 resident control 相同的 continuation;同时
> sibling isolation、parent→child lineage 与 parent history
> immutability 均成立。
>
> **边界继续保留**:该结果证明的是当前测试 topology 与 continuation
> horizon 下的 correctness,不泛化为任意 execution-tree 深度、任意
> 拓扑、任意 residency ordering、跨设备迁移或性能结论。
>
> **树序重挂 = 架构观察(非普遍命题,审核措辞冻结)**:对于当前这种
> COW segmented representation,descendant rehydration 可以依赖已
> rehydrated ancestor 的 segment state;因此 residency reattachment
> order 在该实现中遵循 execution-tree 的拓扑依赖顺序。**暂不升级为**
> "residency 本质上必须按 execution tree 拓扑序恢复"——未来可能存在
> child 自带 dependency descriptor / remote parent 等实现。
>
> **GDN offset 分离 = M3-C 正式实验 invariant**:attention offset 与
> GDN/Mamba offset 分开验证(KV temporal position vs GDN temporal
> position 不被笼统 offset 门掩盖);M3-C 相对 M3-B 不只是 topology
> 增加,也完成了 correctness observability 修正。
>
> **M3 系列终局(冻结)**:M3 PASS(能不能继续)/ M3-A PASS(
> representation)/ M3-B PASS(depth)/ M3-C PASS(topology)。实现
> 冻结点 = `30b61e6`;后续若无直接反证,不再回头修改 M3 系列。
> M3 回答的四个问题:迁移后还能继续吗 YES / 段表碰巧能继续吗 否(
> 两表示均可)/ 只有浅 context 吗 否(16K/64K)/ 只有单节点简单
> topology 吗 否(两代树)。
>
> **下一步:M4——Rehydration Tax。** 纪律:alternating control /
> treatment;same execution state;same continuation workload;
> hot-throttling awareness;不把 rehydration 与冷模型/不同 prefill/
> 不同 cache temperature 混在一起。核心问题 = 相同 execution state、
> 相同 continuation workload 下,rehydration 相对 resident
> continuation 的额外成本。

> **首跑记录(史料)**:本文档初版记录四节点 96/96×4 与三层 invariant;
> 初版状态行"待审核方终判"已被上方终审取代。 代码:`ResidencyM3CTopologyContinuation.swift`(exp 分支)。
> topology 轴单变量;三层 invariant 按 M3-B 终判开题方向一起设计;
> **前向修正落地**:GDN/Mamba offset 显式恢复 + 独立恢复门(承 M3-B
> 审计注记)。

## 靶子

topology coincidence:"continuation 只是单节点碰巧能继续"。

## 设计(树序重挂 + 三层 invariant)

```
P @8192(驻留父代)
  ├── A_t/A_c   fork+512+decode4(seed 132)→ @8708
  ├── B_t/B_c   fork+512+decode4(seed 133)→ @8708
  ├── A1_t/A1_c = fork A_* +256+decode4(seed 134)→ @8968
  └── B1_t/B1_c = fork B_* +256+decode4(seed 135)→ @8968
```

四节点 treat 各自独立外化(私有页+GDN+state+单元元数据)→ 全部释放
(ctrl 四臂驻留)→ **按树序重挂:A、B 重挂到 P;A1、B1 重挂到"已重挂
的 A/B"**(依赖链 = 树序,A1 forkDepth = A offset = 8708)→ 八臂各自
继续 96 步。

## 结果:全部门通过

| 门 | 结果 |
|---|---|
| 前置门 ×4(treat ≡ ctrl 逐元素 + next-input) | ✓✓✓✓ |
| ① sibling isolation:元素级(A≠B、A1≠B1)+ 轨迹级(continuation 互异) | ✓ ✓ |
| ② lineage:A1⊆A、B1⊆B(前缀+严格延伸);continuation 后历史行不可变;A1 仍含 A 前缀 | ✓ |
| 结构门:四臂仍为 COW 段表;树序链(A1 forkDepth=A offset) | ✓ |
| ③ GDN offset 显式恢复独立门(前向修正) | ✓ |
| 主门 ×4:A/B/A1/B1 各 vs 各自驻留 control,N=96 | **96/96 ×4** |
| 辅门:attention offset 八臂 +96;父代完好 | ✓ ✓ |

## 意义(待终判;措辞按纪律)

1. **topology coincidence 在本配置下不成立**:树上的多个节点(含
   二级子节点)可以各自独立跨越物理驻留边界并继续,互不串扰;
   Execution Tree 的 residency 语义首次在 continuation 级成立。
2. **树序重挂是新语义**:子节点的段表重挂依赖其父代先回到驻留
   (A1 挂到重挂后的 A)——residency 的依赖顺序 = 树的拓扑序;
   这是从实验里长出的第二条架构观察(第一条 = 外化不要求表示转换)。
3. **三层 invariant 在 continuation 级成立**:兄弟轨迹互异、父子
   前缀保持 + 历史行不可变、各节点独立往返——树不是"节点集合",
   是带关系不变式的结构。

## 诚实性注记

1. v1 记录:一次编译错误(var/字典类型),一次 crash(lineage 门把
   continuation 后的全视图与共享前缀切片直接比较——与 m2c 同族的
   "深度不齐比较"错误,第二次验证树的比较必须按语义分层),修复后
   全过。
2. 单配置:P@8192、两代树、每节点 horizon 96、段表路径、单轮;
   更多代/更宽树/表示对照属后续轮。
3. GDN offset 门 = 恢复完整性(restored == captured),GDN offset
   语义(是否随 decode 推进)仍未知,如实留白。
4. 本结果不反推 Track B / M1 / M2 / M3 系。

## 决策

1. **M3-C PASS → 待审核终判;下一站 M4(rehydration tax)**:
   交替对照、热节流纪律沿用;轴 = cost。M3 系(continuation 语义)
   至此在测试配置内闭环:能不能继续 / 表示无关 / 深度无关 /
   topology 无关。
2. Track E 正式命名待真源定夺。
