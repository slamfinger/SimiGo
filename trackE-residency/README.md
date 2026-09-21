# Track E(命名待定)— Execution State Residency

**状态**:**M1–M4 全部 FINAL PASS;simulator v0 FINAL PASS(P1/P2 封口);P0 CONDITIONAL PASS(容量 PASS/经济闭合 Pending);P0.1 正式确认 PASS(v0.1 Policy Objective Definition);P0.2 CONDITIONAL PASS(悬崖首轮证据);P3 首跑+后续轮 CONDITIONAL PASS。**P3-A v2 重跑完成 + provenance 闭合(2026-09-21,W=200 修复后;终判 PASS 盖章=审核方二次复核 ff52943:首轮机制验证/v2 provenance/结果口径全 PASS,Cost-aware 形态决策 UNLOCKED)**:机制验证 PASS(五通道/双情景/确定性);判别数据(v2 实跑入档)——cost_aware_greedy(H=8)= 547.3,vs lru −43.8%(hot)/ −18.7%(tree),逼近 lfu_aging(hot −44.0%/tree −23.7%)与 belady reference(−51.2%/−48.0%)——v1 "+20.8%/+14.3% 劣于 lru"与"H 强主导"系 W-bug 伪象;H≥8 收敛(H=4=815.2 有界收敛);P_pressure 通道结构性饱和(raw excess-steps 口径,ms 校准 NOT YET)。v1 lfu 漏递增 bug 与 v2 表 tree/lfu_aging stale 格(provenance 审计捕获:pre-decay 残留 1084.5,实跑修正 1085.9)均如实入档。记录:RESIDENCY_P3A_RESULTS + runs/P3A_V2_RERUN_PROVENANCE_20260921 + 前序各文档。**下一刀=P3-B cost-aware 形态决策(先设计不改基线;动机禁止引用 H=8 失败=W-bug 伪象;设计问题=在正确 W=200 与频率信号下 min(1,n/H) 饱和形态是否值得保留/非饱和形态解决什么可观测问题)**:设计 DRAFT 待审核 `RESIDENCY_P3B_DESIGN_CAG_SHAPE_20260921.md`(三因子消融 V0–V4:分数饱和形态/计数底座/tie-break;S_cont=n/(n+H) 冻结;V0 回归门;R1–R4 预注册判读)。**——
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
