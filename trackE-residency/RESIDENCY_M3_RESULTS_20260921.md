# Track E(命名待定)Residency M3 结果(2026-09-21)

> **终审判定(2026-09-21):M3 Continuation——FINAL PASS,无需补跑。**
>
> **冻结表述(采用审核推荐句)**:**Identity → Exactness →
> Continuation 在本实验配置下形成闭环**;即 *Execution State 的
> Continuation Semantics 在当前 residency 配置下得到行为级验证*。
> 不使用"Execution State 定义的行为维度闭合"这类可能被脱离上下文
> 读成普遍证明的表述。
>
> **三层问题链(审核确认,不是一个问题)**:M1 = 回来之后还是谁;
> M2 = 回来之后状态是不是一样;M3 = 回来之后还能不能继续成为那个
> Execution。当前配置下三层闭合。
>
> **架构线索升级(审核批准表述)**:段表表示已获得
> **continuation-level evidence**(COW segmented → externalize →
> release → rehydrate 仍 segmented → continue 96 → 与 resident
> control 完全一致)。**架构结论仍未成立**:1 configuration /
> 1 depth / 1 node / 1 round / N=96——不得写"未来架构应采用
> segment-preserving externalization"。
>
> **Control = twin child(审核确认:保留,不修改)**:同父代同fork
> 同后缀同 decode 同 position 同 next-input,唯一变量 = residency
> boundary;从零 prefill control 已由 Track B 四路门承担,不重复。
>
> **Scope(冻结)**:已证明 = 当前测试配置(35B / depth≈4.6K /
> single node / same-parent twin / COW segmented child / private
> pages externalized / release / rehydrate without materializing /
> 96-step continuation)下,State(before) == State(ctrl),经
> residency boundary 后 Continuation(treat) == Continuation(control)
> 96/96,offset +96,parent intact,COW segmentation preserved。
> 尚未证明:深位置 continuation;多节点/Execution Tree continuation;
> 连续物化表示 continuation 与段表表示比较(M3-A);多次
> externalize→rehydrate→continue 循环;长期 residency;cross-device
> residency;rehydration performance/tax(M4);residency policy;
> segment-preserving externalization 是最终架构方案。
>
> **工程审计限制(审核方如实申报)及解析**:审核方在 SimiGo-Lab 仓
> 未找到 M3 代码提交 68daa06(代码实际在实验 fork 上,非 lab 仓)。
> 解析(2026-09-21 验证):`68daa06b7e3623f5ed22fe9a93167a866a8d0acc`
> = `slamfinger/mlx-swift-lm` 分支 `exp/execution-state-fork` HEAD
> (ls-remote + GitHub API 双验;文件清单恰为
> `Tests/MLXLMTests/ResidencyM3Continuation.swift` 一文件),
> https://github.com/slamfinger/mlx-swift-lm/commit/68daa06 。
> 审核方据此保持"未逐行复审代码"的诚实申报——判定基于结果文档的
> 实验契约,有效。
>
> **下一步(审核定序,不立刻冲 M4)**:M3-A 连续表示 continuation
> 对照(独立、成对实验,不修改已 PASS 的 M3;直接攻击架构分叉:
> "段表只是当前实现碰巧能跑"vs"residency 本身不需要 representation
> conversion")→ M3-B 深位置 continuation → M3-C 多节点
> continuation → M4 Rehydration Tax。

> **首跑记录(史料)**:本文档初版记录主门 96/96 一次通过与设计;
> 初版状态行"待审核方终判"已被上方终审取代;初版"Execution State
> 定义的行为维度闭合"表述按终判要求收紧为配置限定句。 代码:
> `ResidencyM3Continuation.swift`(exp 分支,通过,30.1s)。设计 =
> M2 终判块的第一轮单变量纪律:无多节点/64K/大树/性能/policy。

## 问题升级

M1/M2 证明"回来以后**看起来**还是原来的 Execution State"(snapshot
comparison);M3 问"回来以后**是不是还能成为原来的 Execution**"
(behavioral continuation)——树上的一个节点,离开物理世界一段时间,
回来还能不能**沿着原来的未来生长**。

## 设计(主配置 = m2b 段表路径)

```
P @4096(驻留父代)
  ├── treat = fork → 后缀512 → decode8 → 外化(私有页)→ 释放
  │        → 重挂回驻留父代(仍为 COW 段表,未物化)→ 继续 96 步
  └── ctrl  = fork → 后缀512 → decode8 → 驻留全程 → 继续 96 步
```

- **可证伪前置门**:外化前 treat ≡ ctrl(五类状态逐元素相等 +
  next-input 相等;同父代同操作 ⇒ 必须同态,不等 = 环境问题立即停)
  —— ✓
- **主门**:Continuation(treat) == Continuation(ctrl),N=96 逐
  token —— ✓ **96/96 全等**
- 辅门:重建核查(treat 仍为 COW 段表,sharedRows = 父代 offset,
  offset @4616,state 重建 2 数组)✓;offset 精确推进 +96 ✓;父代
  完好 ✓
- 载荷:私有页 520 行 / 73,292 KiB;7.6s 双侧 192 步 decode(描述性)

## 意义(待终判;措辞按纪律)

1. **架构观察升级为可继续执行的证据**:m2b 证明段表形式可以外化/
   回来且状态精确;M3 进一步证明这个**未物化**的段表子代回来后与
   驻留 control 沿**完全相同的 token 序列**继续——"residency 不要求
   表示转换"这条线索现在有了 continuation 证据。但**架构结论仍不
   下**:单配置、单深度、单轮;"residency architecture 应采用
   segment-preserving externalization"仍待更多配置(M3 后续轮/
   M4)支持。
2. **Execution State 定义的行为维度闭合**:KV + Identity + Position
   + Next Input + Continuation Semantics 中,Continuation 首次在
   residency 边界上被行为级验证(此前 F5-1/F5-2/Closure 验证的是
   表示迁移;这是第一次跨物理驻留)。
3. Identity → Exactness → Continuation 三级在本配置下形成闭环:
   回来的不只是"同样的字节",而是"同样的未来"。

## 诚实性注记

1. N=96、depth 4.6K、单节点、单轮——按单变量纪律,结果只覆盖此
   配置;深位置/多节点的 continuation 是后续轮。
2. 控制组为**同父代同操作的孪生子代**(前置门逐元素验证),非从零
   prefill;从零 control 的 continuation 已由 Track B 四路门覆盖,
   本实验聚焦外化变量本身。
3. 计时仅描述性;性能归 M4(交替对照,热节流纪律沿用)。
4. 本结果不反推 Track B / M1 / M2;失败也只指向"该机制在该配置下
   不成立"。

## 决策

1. **M3 主门 PASS → 待审核终判;建议 M3 后续轮**(审核定夺):连续
   表示重建的 continuation 对照(与段表路径成对)、深位置/多节点
   continuation(单变量逐个加回)。
2. M4(rehydration tax,交替对照)在 continuation 语义闭合后进行。
3. Track E 正式命名待真源定夺。
