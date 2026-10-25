# Track E(命名待定)Residency M3-B 结果(2026-09-21)

> **终审判定(2026-09-21):M3-B Deep Position Continuation——FINAL PASS。**
> 审核方完成双端核验(fork 上 1a142b5 实验源码 + lab 仓结果文档)。
>
> **冻结范围(审核原文)**:在当前 35B 模型、单节点、COW 段表路径、
> 16K 与 64K 两个测试深度、suffix 512、decode 8、continuation horizon
> 96 的配置下,rehydrated Execution State 均保持与 resident control
> 相同的 continuation。**边界继续保留**:这证明的是测试深度上的
> continuation correctness,不泛化为任意 context depth、任意 horizon
> 或任意 topology。
>
> **工程审计注记(不阻断 PASS,如实入档,不补跑)**:M3-B 重建
> GDN/Mamba cache 时未显式恢复 `m.offset`(attention COW cache 有),
> 且 offset 辅门只检查 `attnIdx`——故"offset +96"严格来说是
> **attention KV cache offset +96**,不是"所有 cache 类型"。不构成
> FAIL:主判定目标是 continuation,GDN state 重建后实际参与 96-step
> forward 且与 control 96/96 全等,若 GDN metadata 缺失实际影响
> continuation,主门应已暴露。处理 = 记录注记、不扩大当前结论、
> **不为注记补跑 M3-B**(否则破坏 axis isolation)。**前向修正:
> M3-C 起 GDN/Mamba offset 显式恢复并设独立门。**
>
> **实验链(审核判定表)**:M3 PASS(能不能继续)/ M3-A PASS(是否
> 只是 COW 段表碰巧能继续)/ M3-B PASS(是否只是浅位置碰巧能继续,
> 16K/64K)/ M3-C OPEN(topology:execution tree/多节点还能不能
> 继续)/ M4 OPEN(为此付出多少成本)。M3-A 打掉 representation
> coincidence,M3-B 打掉 shallow-position coincidence——M3-C 攻击
> topology coincidence 是自然推进,非重复实验。
>
> **M3-C 开题方向(审核建议,正式入档)**:开题时把三层 invariant
> 一起设计清楚——**sibling isolation + parent→child lineage + 各节点
> 独立 residency/continuation**;比单纯复制 M3 几份更有价值。

> **首跑记录(史料)**:本文档初版记录两深度 96/96 与设计;初版
> 状态行"待审核方终判"已被上方终审取代。 代码:`ResidencyM3BDeepContinuation.swift`
> (exp 分支)。设计按 M3-A 终判收紧:**只走段表路径**,depth 轴
> 单变量,轴分离 = M3-A representation / M3-B depth / M3-C topology /
> M4 cost。

## 靶子

"continuation correctness 是否只是浅位置 @4616 的偶然现象?"

## 设计与结果(每深度:M3 同型孪生双子代,段表路径)

| 深度 | treat 位置 | 私有页载荷 | 前置门 | 主门(N=96) | 辅门 |
|---|---|---|---|---|---|
| 16K | @16904 | 73,292 KiB | ✓ | **96/96 全等** | offset +96 ✓ 父代完好 ✓ |
| 64K | @66056 | 73,292 KiB | ✓ | **96/96 全等** | offset +96 ✓ 父代完好 ✓ |

每深度:前置门(外化前 treat ≡ ctrl 逐元素 + next-input)→ 私有页
外化/释放 → 重挂回驻留父代(重建核查:仍为 COW 段表,sharedRows =
父代 offset)→ 双侧各继续 96 步逐 token 对照。64K 侧双侧 192 步
25.7s(描述性;深位置 decode 更慢,性能归 M4)。

## 意义(待终判;措辞按纪律)

1. **"浅位置偶然"解释在测试的 16K/64K 深度上不成立**(配置限定,
   不外推"所有深度"):深至 @66056,段表外化/回来的子代仍与驻留
   control 沿相同未来继续。
2. **私有页载荷深度无关**:两深度载荷同为 73,292 KiB(520 行)——
   外化成本随 fork 后缀而非总深度(与 F3 R2 平坦性一脉相承)。
   字节数为结构性事实,时间/带宽归 M4。
3. 实验链现状:Identity(M1)→ Exactness(M2)→ Continuation(M3)
   → representation 无关(M3-A)→ depth 无关(M3-B,测试深度上),
   全部 config 级,不普遍化。

## 诚实性注记

1. N=96、suffix 512、decode 8、两个深度、单节点、单轮;其他深度与
   更长 horizon 属后续轮。
2. 两深度 nextInput 相同(96818)为后缀主导 argmax 的观察,门不依赖
   跨深度比较(各深度内部 treat==ctrl)。
3. 计时描述性;本结果不反推 Track B / M1 / M2 / M3 / M3-A。

## 决策

1. **M3-B PASS → 待审核终判;下一站 M3-C(多节点 continuation)**:
   Execution Tree 上多节点各自外化/回来后的 continuation 对照
   (topology 轴;设计待与审核确认是否含兄弟/谱系 invariant)。
2. M4(rehydration tax,交替对照)按序。
3. Track E 正式命名待真源定夺。
