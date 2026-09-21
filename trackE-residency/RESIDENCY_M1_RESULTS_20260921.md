# Track E(命名待定)Residency M1 结果(2026-09-21)

> **状态:M1 首跑 PASS(五门全绿),待审核方终判。** 本文档只回答
> 一件事:Execution State 跨物理驻留边界后,ExecutionId 是否保持。

**性质**:Track E 第一实验,极小化——不碰性能,只问 identity。
**代码**:`Tests/MLXLMTests/ResidencyM1Identity.swift`(exp 分支,
基于 acbcb54;通过,21.3s)。
**配置**:真实 35B 模型(qwen3_5_moe:10 attention + 30 GDN 层),
resident 态 = P@4096(基座)→ fork(COW 段表 + GDN 引用)→ 后缀
512 → decode 8 步 → **position @4616**(首 attention 层锚定)、
nextInput=95933、LMOutput.State 2 数组。

## 探针设计(唯一问题)

```
Resident
   │  save(safetensors,84 tensors → 158,937,904 bytes)
   ▼
Externalized(驻留释放:GPU active 20677 → 20520 MiB,差值 ≈ KV+GDN 态)
   │  loadArrays → 40 层重建(attention→KVCacheSimple 连续表示;
   │  GDN 槽位重建; LMOutput.State 重组)
   ▼
Rehydrated → ExecutionId(before) == ExecutionId(after)?
```

**门(五项,全部状态接地)**:① position(逐层 offset + 单元元
数据);② next-input(**G2 迁移单元契约形式**——input 存入载荷、
从重建工件读回,禁止与本地变量自比);③ attention KV 全视图逐元素
(10 层);④ GDN 槽逐元素(30 层);⑤ LMOutput.State 键集合 + 逐键
逐元素。

## 结果:五门全过

| 门 | 结果 |
|---|---|
| ① position | ✓(4616 = 4616,逐层一致) |
| ② next-input | ✓(95933 = 95933,载荷回读路径) |
| ③ KV 逐元素(10 层) | ✓ |
| ④ GDN 槽逐元素(30 层) | ✓ |
| ⑤ LMOutput.State | ✓ |
| 冒烟步(诊断,非门) | 单步 decode 可运行(38.6ms,offset +1,token=3709) |

计时(externalize 48.9ms / rehydrate 物化 14.0ms)为**描述性记录,
不构成 M4 结论**(M4 = 交替对照,热节流纪律沿用)。

## v1 失败如实记录(又一例位置纪律)

首跑 gate1/gate5 失败,根因 = **position 锚点取 `r.first!.offset`,
而第 0 层是 GDN 层(offset 恒 0)**——混合架构下各层 offset 语义不
同,首层不是 attention 层。修正 = 锚定首个 attention 层
(closure `firstCowIdx` 先例)。**failure 本身再次演示同一不变式:
对照必须锚定在同一 execution position 上;层序≠层型。**

## 诚实性注记

1. **锚点快照保留说明**:resident 释放后保留 identity 锚点快照
   (物化全视图,用于 before/after 比较)——它是**记录**,不是
   continuation-capable 状态(无 cache 对象、无模型接线);真实
   continuation 属 M3。
2. **sha256 不作门**:safetensors 键序逐进程不定——两次运行载荷
   内容相同而 sha 不同(6e271daa…/…902B vs 6ba41812…/…904B),如实
   入档;字节级 artifact identity 留给 M2 用确定性序列化再问。
3. **表示变化是允许的**:COW 段表态 → 连续表示重建,正是统一不变
   式的语义(migration 可变表示,identity 不可变);段表形式的
   外化(私有页往返,F3 R2 型)属 M2 扩展配置。
4. **本结果不反推 Track B**:M1 PASS 与 Closure 无互证关系;M1
   FAIL 也只会指向"该机制不成立"。

## 决策

1. **M1 语义门 PASS → 建议开 M2(State Exactness)**:扩展配置 =
   COW 段表形式外化(私有页往返)、更深位置(16K/64K)、多节点
   (树上多个节点各自外化/回来不串 identity);组件级 exactness
   系统化(K/V/GDN/state/position/next-input 全清单)。
2. **M3(Continuation)、M4(Rehydration tax,交替对照)按序后续**,
   不跳门。
3. **待审核方对 M1 作终判**;Track E 正式命名待真源定夺。
