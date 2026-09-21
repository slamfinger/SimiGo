# Track E(命名待定)Residency P0 结果(2026-09-21)

> **状态:P0 Cost Model Closure(C_resident 计价)首跑完成(23.9s,
> 待审核方终判)。** 代码:`ResidencyP0ResidentCost.swift`(exp 分支)。
> 定位:v0 终判钉死——P0 先于 P3,否则 New Policy = 在成本模型未闭合
> 的目标上优化。

## 靶子

补齐 policy 不等式左边:

```
Keep Resident(C_resident)vs Externalize + Future Rehydrate(≈0.72 token)
```

## 方法(计价基础 = nbytes 精确,非 memory 推断)

对 520 逻辑行的标准子代逐组件取 `nbytes` 实测;GPU activeMemory 降为
粗交叉验证(v1 教训:统一内存计账含 prefill 瞬态,曾出现负增量读数,
不作为定价基础;尾部拟合斜率与 nbytes 差 <1%,量级交叉确认)。

## 结果

**① 每节点驻留字节(520 逻辑行,nbytes 精计)= 78,246 KiB:**

| 组件 | 字节 | 占比 |
|---|---|---|
| attention 私有页(分配 768 行/层,step-256 对齐) | 15,360 KiB | 19% |
| GDN 槽(30 层 × 2 槽) | 62,880 KiB | **80%** |
| LMOutput.State(2 数组) | 6 KiB | ~0% |

GDN 槽形态分解:conv `[1,3,8192]` bf16 × 30 = 1,440 KiB;recurrence
`[1,32,128,128]` fp32 × 30 = **61,440 KiB(驻留成本主体)**。

**② padding 披露**:attention 分配 7,680 行(step-256 对齐)/ 使用
5,200 逻辑行(1.48×)——外部化载荷按逻辑行(73,292 KiB),驻留按
分配行(78,246 KiB);**外化反而省掉 padding**。

**③ 交叉验证**:activeMemory 尾部拟合 78,890 KiB/节点 vs nbytes
78,246 KiB(差 <1%)。

**④ 真实预算上限**:memoryLimit − 权重(20,126 MiB)= 4,449 MiB 可用
→ 折合 **≈58 个 520 行节点**。simulator 的 budget 参数自此有真实
映射(100% 预算 ≈ 4.3 GiB 驻留字节)。

**⑤ policy 不等式(数字闭合)**:

```
Keep(n, T) = 78,246 KiB × T 字节占用 + 0 ms/token 计算成本(M4)
Leave(n)  = C_ext 0.69 + C_rehy 0.03 ≈ 0.72 token-equivalent(一次性)
            + 外部存储 73,292 KiB(逻辑行)
```

## 意义(待终判;措辞按纪律)

1. **C_resident 本体 = 字节机会成本,计算成本为零**(M4);不等式
   两边首次都有数。
2. **重大结构发现:GDN recurrence state(fp32,61,440 KiB/节点)是
   驻留成本主体(80%)**——混合架构下每节点 O(1) 的 GDN 态是不可
   压缩的固定驻留底价;attention 私有页(19%)才是随深度增长的部分。
   直接喂给 H-P1(**state size 是 decision-relevant 信号**的具体
   形态:节点间驻留成本差异由 GDN 底价 + attention 深度共同决定)。
3. v0 的"低预算 = 策略无关区"获得物理解释:预算绑定时的字节之争
   才是 policy 的用武之地——现在预算有了真实字节数(4,449 MiB /
   ≈58 节点)。
4. 外化省 padding(驻留 78,246 vs 载荷 73,292 KiB)——小而真实的
   结构观察。

## 诚实性注记

1. v1 记录:activeMemory 计账含 prefill 瞬态,曾出现负增量读数——
   计价基础改为 nbytes,activeMemory 降级为交叉验证(不再作为结论
   基础);
2. 单机、单模型、单 config(520 行节点);字节=MLX 分配口径
   (含 fp32 GDN/fp16 KV/bf16 conv 的真实 dtype);
3. 驻留字节的"机会成本换算率"(bytes→token)依赖场景,留白给
   Residency Policy;
4. 本结果不反推 Track B / M1–M4 / simulator v0。

## 决策

1. **P0 数字入档 → 待审核终判;cost model 至此闭合**,P3(New
   Policy discrimination)解锁——其 cost-aware oracle 与 state-size
   信号设计应消费本探针的 GDN 主体发现;
2. Track E 命名继续待定(等 P3 证据)。
