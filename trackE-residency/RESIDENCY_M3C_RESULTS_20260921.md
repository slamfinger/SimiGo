# Track E(命名待定)Residency M3-C 结果(2026-09-21)

> **状态:M3-C 多节点树 continuation 首跑语义 PASS(61.8s,待审核方
> 终判)。** 代码:`ResidencyM3CTopologyContinuation.swift`(exp 分支)。
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
