# Track E(命名待定)Residency M4 结果(2026-09-21)

> **终审判定(2026-09-21):M4 Rehydration Tax——FINAL PASS。**
> 审核方实读实验源码 `16972cb` 与结果文档 `6f7f902`。
>
> **计量精确化(审核修正,冻结)**:一次性边界成本按入档数字重算 =
> 28.9/40.36 ≈ 0.716 与 34.9/48.42 ≈ 0.721 → **冻结表述 =
> ≈0.72 resident decode-token equivalent(约 1 token 数量级)**;
> "≈1"仅作数量级描述保留。
>
> **measurement-scope 注记(本次审核最重要一条,不阻断,不补跑)**:
> 本次 rehydrate 计时覆盖 serialized-array load、KV/GDN cache 重建及
> 段表重挂(含 GDN offset 恢复);**`LMOutput.State` 对象重建发生于
> 计时区间之外**——因此"一次性成本"结论不等同于完整 Execution
> State object reconstruction cost。continuation/steady-state 结论
> 不受影响(state 实际重建后参与 decode)。
>
> **冻结范围(审核原文)**:在当前 35B 模型、单节点、COW segmented
> representation、in-memory residency boundary、@4616 与 @16904 两个
> 测试位置、相同 execution state 与 continuation workload 的配置下,
> 外化 + rehydrate/re-attach 的一次性测量成本约为 0.72 个 resident
> decode-token(约 1 token 数量级);在 8-step warmup 后的交替
> 6×16-step continuation 测量中,未观察到超出轮间噪声的稳态 decode
> tax。
>
> **边界**:结果仅适用于当前模型、设备、in-memory implementation、
> representation、两个测试 depth 与 workload;不外推到磁盘 residency、
> 跨设备迁移、不同硬件或其他 serialization format。稳态表述冻结 =
> "No steady-state decode tax was measured above round-to-round
> noise"。载荷深度无关 = observed structural property,不升级为
> general residency property。
>
> **M 链正式封口(七问七答)**:是谁(M1)/ 状态是不是它(M2)/
> 还能继续吗(M3)/ 换表示还能吗(M3-A)/ 深一点呢(M3-B)/ 树状
> execution 呢(M3-C)/ 付出多少(M4)= **0.72 token 等价 + 稳态无
> 超噪声税**。
>
> **下一阶段(审核开题):Residency Policy。** 研究纪律:M4 证明的是
> "外化/召回的 cost 可接受性边界",**不证明"应该什么时候外化"**;
> M4 数字(0.72 token 边界成本 + 无稳态税)自此成为 policy 的输入。

> **首跑记录(史料)**:本文档初版记录双 config 交替对照数字与设计;
> 初版状态行"待审核方终判"已被上方终审取代;初版"≈1 decode-token
> 等价"按终审精确化为 0.72。 代码:`ResidencyM4RehydrationTax.swift`(exp 分支)。
> 纪律:M3-C 终判定序——交替对照、同 execution state、同 continuation
> workload、热节流感知;不混冷模型/不同 prefill/cache temperature。

## 靶子

相同 execution state、相同 continuation workload 下,跨越 residency
边界(rehydrate)相对 resident continuation 的**额外成本**。

## 设计

- 双 config(base 4096 / 16384 → position @4616 / @16904),段表路径;
- 每配置:孪生双子代 → 可证伪前置门 → treat 私有页外化/释放/重挂
  (GDN offset 显式恢复)→ 双臂 warmup 8 步(排除首触)→ **交替
  稳态 6 轮 × 16 步**(偶轮 ctrl 先、奇轮 treat 先,抵消顺序热偏差)
  → 轮均值取中位;
- 正确性守卫:全部测量步两臂 token 逐 token 相等(非门,测量有效性
  前提)—— ✓。

## 结果

| 配置 | 一次性边界成本 | 载荷 | 稳态 ctrl 中位 | 稳态 treat 中位 | 稳态税 | token 守卫 |
|---|---|---|---|---|---|---|
| @4616 | 27.7 + 1.2 ms | 73,292 KiB | 40.36 ms/tok | 40.07 ms/tok | **−0.7%** | ✓ |
| @16904 | 33.4 + 1.5 ms | 73,292 KiB | 48.42 ms/tok | 47.72 ms/tok | **−1.5%** | ✓ |

一次性边界成本折合 ≈ **1 个 decode-token 等价**(两 config 同)。

## 解读(措辞按纪律,待终判)

1. **一次性边界成本 ≈ 1 decode-token 等价**:在本实现(内存内页
   往返 + 段表重挂)下,离开再回来的固定代价约等于多生成一个 token。
   **限定**:这是同进程内存语义;磁盘/跨设备 residency 的成本结构
   不同(跨设备属真源 Track C 问题域),不得外推。
2. **稳态无超出噪声的税**:|税| < 1.5%,与交替轮间波动同量级——
   既不声称"零税",也不声称存在税;正确表述 = **未测得超出轮间
   噪声的稳态 decode 税**。rehydrate 后的状态参与 decode 与从未离开
   的 control 无行为与成本可分辨差异(本配置)。
3. **载荷深度无关再次印证**:两 config 私有页载荷同为 73,292 KiB
   (520 行),与 M3-B 一致;一次性成本亦深度近平(27.7→33.4 ms,
   差值主要在 save 路径),承 F3 R2 平坦性。
4. M4 无成本 gate——数字即结果;"哪种 residency 策略更优"属
   Residency Policy(需要 M4 数字 + 场景假设,不在本实验范围)。

## 诚实性注记

1. 单机(无风扇,热节流敏感)、单模型、单轮、两个 build 配置;
   中位数为交替设计下的公平点估计,非统计置信区间。
2. v1 记录:一次 crash(`treat = []` 后取 `treat.count`——与 M3-C
   "释放后引用"同族教训的重复,layerCount 释放前捕获修复)。
3. 本结果不反推 Track B / M1 / M2 / M3 系;不构成 Residency Policy
   结论。

## 决策

1. **M4 数字入档 → 待审核终判**。M 链(M1 Identity → M2 Exactness
   → M3 Continuation + A/B/C 轴 → M4 Cost)在测试配置内全部完成。
2. **下一阶段建议:Residency Policy 开题**(消费 M4 数字:一次性
   token 等价成本 + 稳态零税 → 何时外化/何时召回的策略问题),
   Track E 正式命名仍待真源定夺。
