# CCVS-01 Phase B — Human Revision Ruling

Date: 2026-10-06  
Type: `HUMAN RULING / L2 AUTHORITATIVE`  
Subject: Review of `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_PHASEB_PROTOCOL_FREEZE_20261006.md` (CCVS-01-PB v1.0 draft)  
Ruling: `B — REVISE / NARROW PROTOCOL REVISION`

## Ruling text (registered content; long explanatory passages condensed,
## all operative rulings preserved)

> 我的裁定是：**B — REVISE。**
>
> 但这是一个**小范围、定向修订**，不是退回 Phase A，更不是 PARK。Phase B 的整体结构已经足够进入冻结状态；现在需要把几个会在 Phase C 造成"实验解释歧义"的地方先封死。
>
> 先说明审阅边界：当前我拿到的是你本次提交的冻结清单与关键条款，而不是该 Markdown 文件的逐行全文，因此下面是对**协议结构与冻结项的研究级审查**，不是逐行文档 review。
>
> ## 一、我为什么不批准 A
>
> ### 1. PB-B1..B14 目前最大问题不是"数值高低"，而是"数值来源"
>
> 你现在明确说明：
>
> > 这些绝对性能数值是提案，未经验证。
>
> 这本身没有问题；问题在于一旦它们被作为：
>
> ```text
> 硬失败门槛
> ```
>
> 就会产生一个危险逻辑：
>
> ```text
> candidate 性能不达标
>         ↓
> candidate FAIL
> ```
>
> 但我们实际上可能面对的是：
>
> ```text
> 测试机器 / OS / FS / runtime overhead
>         ↓
> 所有 candidate 都没有达到绝对值
> ```
>
> 此时我们无法区分：
>
> ```text
> 架构不行
> ```
>
> 还是：
>
> ```text
> bound 本身没有经过环境校准
> ```
>
> 尤其是这些数值不能脱离固定测试环境、数据规模、durability semantics、冷/热状态来解释。
>
> 所以我建议**不是删除 PB-B1..B14，而是修改它们的 gate semantics**：
>
> ```text
> PB-B1..B14
> = Frozen evaluation bounds
> ≠ Universal engineering guarantees
> ```
>
> 并明确加入：
>
> ```text
> Baseline-A feasibility / protocol-validity check
> ```
>
> 也就是：如果在固定、合格测试环境中连 Baseline A 都系统性无法满足某个绝对 PB，则该结果首先触发 **protocol/environment validity classification**，不能直接把这一 PB 当作 candidate architecture 的淘汰依据。
>
> ## 二、Anti-complexity rule 必须修
>
> 现在的 `OR` 太宽。候选可能满足单一 performance gate 却在 disk/memory/startup/seam latency 上大幅回归，仍"合法"击败 Baseline A。应冻结为：
>
> ```text
> 复杂拓扑只有在以下之一成立时才获得额外复杂度正当性：
>
> A. 明确的、端到端的性能收益 ≥ threshold
> B. 提供 Baseline A 在同一 semantic/correctness contract 下无法合法提供的能力
>
> 同时：
> - G1–G8 / I1–I13 / F1–F9 不得有失败
> - 不得出现未定义的关键资源或恢复回归
> - performance gain 必须是 architecture-level/end-to-end，
>   不能用单组件 benchmark 的提升充数
> ```
>
> 尤其要加一句非常重要的定义：
>
> > **30% P95 / 50% throughput 必须针对候选架构端到端 workload，而不是某个单独组件。**
>
> ## 三、WL6 作为 Binding Workload 可以保留，但不能成为唯一解释来源
>
> WL6 = primary architecture binding workload；WL1..WL7 其他 workload family = mandatory diagnostic / capability evidence。`WL6 PASS` 不能证明 large-file / relation-heavy / search rebuild / fault recovery PASS。
>
> ## 四、Phase C 还缺一个非常关键的"统计协议层"
>
> 至少应该冻结：一次 run 如何定义、一次 workload 需要多少 observation、多少次 independent runs 才能形成 candidate result、P50/P95/P99 如何从这些 run 聚合、异常 run 如何处理、什么情况下 result = INVALID 而不是 FAIL。尤其 P99 如果样本不足，本身就没有足够意义。
>
> ## 五、`ingest amplification ≤ 3×` 必须把分母/分子写死
>
> 必须明确 logical payload bytes vs physical durable footprint，后者是否包含 metadata、WAL、indexes、relation store、search index、temporary files、duplicate copies、object-store overhead。并且必须区分 steady-state amplification / peak amplification / rebuild amplification / crash-recovery amplification，至少指定 primary metric 是哪一个。
>
> ## 六、Crash / Recovery 条件还要再严一点
>
> F1–F9 方向很好，但必须明确 crash 的物理含义。如果 Phase C 实际只做 process crash / SIGKILL，那么结论应写成 process-crash recovery validated，不能写成 power-loss durability validated。
>
> ## 七、Candidate-level result 必须明确"怎么判架构胜负"
>
> 不要现在创造一个总分公式。更好的方式是分层：
>
> ```text
> Correctness   → Hard gates
> Capability    → Capability qualification
> Performance / resource / seam → Pareto / shortlist evidence
> Anti-complexity → Architecture justification
> ```
>
> 这样不会出现人为权重把不同性质的问题压成一个分数。
>
> ## 最终裁定
>
> 修改目标不是重新设计 Phase A、不增加新 candidate、不选择 backend、不执行 benchmark、不改 Frozen Contracts、不打开 ES↔IS，而是把"实验规则已经写出来"推进到"第三方按照规则执行，也不会在结果出来以后争论规则到底是什么意思"。达到这一点，将倾向于批准 `Phase B = FROZEN`、`Phase C = NOT AUTHORIZED`。修订本身不应触碰 carrier-neutral implementation。
>
> **当前 Human ruling：B / narrow protocol revision。**

## Mandatory revision items

```text
R1  PB-B1..B14 semantics = frozen evaluation bounds, not hard elimination
    gates; add Baseline-A feasibility / protocol-validity classification.
R2  Anti-complexity rule: end-to-end definition + non-regression conditions.
R3  WL6 = primary binding workload; WL1..WL7 = mandatory diagnostic /
    capability evidence.
R4  Statistical protocol layer: run definition, observation minimums,
    aggregation, invalid-run handling, P99 validity, warm-up, stabilization.
R5  Amplification: numerator/denominator frozen; amplification variants with
    a declared primary metric.
R6  Crash semantics: process-crash only; explicit claim boundary versus
    power-loss durability.
R7  Candidate verdict: layered decision, no weighted total score.
```

The Phase B protocol freeze document is revised to v1.1 against this ruling and
returns to `AWAITING HUMAN REVIEW`. This ruling does not authorize Phase C.
