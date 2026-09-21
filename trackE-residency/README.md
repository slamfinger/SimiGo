# Track E(命名待定)— Execution State Residency

**状态**:**M1–M4 全部 FINAL PASS;simulator v0 FINAL PASS(P1/P2 封口);P0 CONDITIONAL PASS(容量 PASS/经济闭合 Pending);P0.1 PASS(v0.1 Policy Objective Definition);P3 首跑 CONDITIONAL PASS;P3 后续轮 CONDITIONAL PASS(2026-09-21,待 FINAL 前两处文字清理已落)**——cost-aware reference = CONDITIONAL CLOSED(缩减模型边界内 Belady=DP 精确最优 0.0%,模型级解释:容量满后 #ext 与 miss 数直接对应);H-P1 首检阴性正式记录 = naive tree-neighbor retention FALSIFIED(H-P1 整体 OPEN,三可能 A/B/C 全开放不预设);残差升级 = 缩减模型边界内 LFU→Belady 即 LFU→exact optimum 实测残差。源码清理两处已落(stale print/RNG 消耗注记仅注释不改行为)。记录:RESIDENCY_M1/M2/M3/M3A/M3B/M3C/M4/P0/P01/P3/P3R2_RESULTS + P01_COST_UNIT_DRAFT + POLICY_OPENING + SIM_V0_RESULTS_20260921.md。**——
记录:`RESIDENCY_M1_RESULTS_20260921.md`;代码:
`ResidencyM1Identity.swift`(exp 分支,基于 acbcb54)。M1 失败教训
如实入档:position 锚点误取第 0 层(GDN,offset 恒 0),修正 = 首
attention 层锚定(closure firstCowIdx 先例)。M2(State Exactness:
段表形式外化/深位置/多节点)待审核后开;M3/M4 按序,不跳门。
**命名**:暂用 Track E——与真源报告 §5.3 Track C(= Multi-device)
冲突,正式命名待维护者在真源更新时定夺;定夺前本目录名不变。
**性质**:独立新研究问题,**不是 Track B 的尾巴**。

## 研究问题(新墙)

Execution State 能否**离开当前物理驻留**而不丢失 Identity / State /
Continuation?

```
Resident
   ↓ Externalized
   ↓ Rehydrated
   ↓ Continue
```

**背景与依据**:Track B CLOSED / FROZEN(4184aa6)证明的是所测执行
位置下的生命周期语义正确性,范围纪律钉死**不证 Residency 行为**
(Residency ≠ Closure);#629 follow-up 技术报告已发布
(issuecomment-5754644625),residency 在其中被明确写为"declared next
research question, not a claim"。同构映射承 Track B 入档:
resident/non-resident ↔ COW/continuous、传输税 ↔ 表示税、
prefetch/materialize ↔ reattach、evict ↔ discard、在线带宽/延迟估计
↔ 在线税估计。Prior art(external baseline,非竞争):TurboFieldfare /
DeepSpeed / FlexGen。

## 与 Track B 的边界纪律(不可协商)

Residency 实验结果**不得反推修改 Track B 冻结结论**。若某
Externalize/Rehydrate 方案无法保持 continuation,结论 = "该 Residency
mechanism 不成立",而非 "Track B Closure 不成立"——除非直接反证
已冻结 invariant(目前无此证据)。

## M1(唯一目标,克制)

**门(仅一道,一票否决)**:

```
ExecutionId(before) == ExecutionId(after)
```

流程:resident state → Externalize → Rehydrate → Continue(greedy
decode,与同 chunking from-scratch control 对照)。**M1 不过(身份
保持失败)→ M2–M4 全部不启动,止损入档。**

## M2–M4(M1 通过后才开,预注册)

| 门 | 内容 | 判据 |
|---|---|---|
| M2 | State exactness | KV/GDN 态逐元素 exact |
| M3 | Continuation correctness | 逐 token 对照 from-scratch(同 chunking) |
| M4 | Rehydration tax | 时间/带宽数字;**交替对照**(热节流纪律沿用),不设优劣预设 |

## 纪律与工程注意(承 Track B 全部有效)

统一不变式延伸:**Residency migration must preserve execution
identity and continuation**(Execution State = KV + Identity +
Position + Next Input + Continuation Semantics,整体迁移)。τ̂ 热敏感
教训沿用:凡在线估计器,鲁棒性先入边界再谈数字。重型测试(20GB
模型)前必查 `vm_stat` / `vm.swapusage`;性能对比必须交替运行(M5 Air
无风扇)。

**代码**:`~/Documents/mlx-swift-lm`,承接
`exp/execution-state-fork` 分支;如需另立 residency 实验分支,**先问**
(远端纪律:slamfinger fork = 批准备份,上游 ml-explore 永不推)。
**三段式**:本 README = 开题;探针跑后增补结果与决策文档。
