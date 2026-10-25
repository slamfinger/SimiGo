# Execution State Seam Stability Opening Draft

日期：2026-09-30  
状态：`PARTICIPANT PROPOSAL / AWAITING EXTERNAL REVIEW`  
前置 gate：BACKEND-1 adapter engineering Round 1 = `PASS / REGISTERED / CLOSED`
（`b36525a`）；Phase C seam audit = `PASS / REGISTERED`（`afdf30f`）  
基线：`716de52`  
性质：participant proposal，不是 repository registration

本草案不实现第二个 backend，不修改 contract，不扩大测试面，不选存储，
不做 performance claim，不吸收 PALACE 线。全程区分：

```text
observed code fact ≠ inferred stability criterion ≠ selected implementation
```

## 1. Opening purpose 与研究问题

本 gate 响应 Round 1 封口时登记的方向性判断：下一阶段的研究价值不在「还能
不能接一个 adapter」，而在回答——

> 已登记的 E1 + E3 + B1 seam 与 Execution Semantic Snapshot 边界，能否作为
> SimiGo 长期 backend-independence 的稳定架构边界——即 contract 变更只由
> 真实语义需求驱动，而不由实现便利、backend 差异、存储选型或并线研究
> （PALACE）牵引驱动？

**Stability ≠ immutability**（预钉死，防概念膨胀）：seam 可以经登记的
contract gate 演化；stability 指的是「变更被纪律约束、可机械检测、且有
真实的语义必要性」，不是「永不改变」。

## 2. Registered inputs（只引用，不重跑、不吸收）

| 资产 | 状态 | 本 gate 用法 |
|---|---|---|
| Execution Semantic Snapshot 边界（Phase B） | `PASS / REGISTERED` | 被保护对象 |
| E1+E3+B1 seam（Phase C，61/61） | `PASS / REGISTERED` | 被保护对象 |
| Round 1 SUFFICIENT（有界）+ 75/75（`b36525a`） | `PASS / REGISTERED / CLOSED` | 穿透性证据先证 |
| Seam 能力边界原则（非强制组件清单） | 随 Round 1 登记 | S1 稳定性判据的输入 |
| adapter-level cancellation containment（G-9 NOT CLOSED） | 随 Round 1 登记 | 术语与边界输入 |
| M-1…M-5 强制检查项 | 随 opening 登记继承 | S6 候选 standing check |
| G-1…G-10 | INHERITED / NOT CLOSED | S3 分类对象，不解决 |
| Evidence-source-state 对应纪律（`716de52`） | human 正式规则 | 本 gate 一切测试复跑的约束 |
| PALACE 线（`04c608e`） | RESEARCH HYPOTHESIS / SEPARATELY SCOPED | 不读其内容、不依赖；并发事实 |

## 3. Proposed subquestions

### S1 — Stability definition
「稳定架构边界」在操作层意味着什么？提出四个可审计的稳定性轴，逐轴定义
判据（判据先于证据，与三分法同纪律）：

```text
轴 a  semantic ownership — D/R/P/O/T 归属不被实现便利改写
轴 b  extension — 新 backend/新能力经既有显式降级表达，无需 contract 变更
      （Round 1 已提供一例；本轴审计其可推广性判据，不实现新例）
轴 c  change discipline — contract 变更必须有登记的语义必要性证明
轴 d  composition — 与已登记未来层（durable store、productization）叠加时
      不要求重构语义所有权
```

### S2 — Contract-change classification（drift detection taxonomy）
把 Round 1 的三分法（SUFFICIENT / INSUFFICIENT-BUT-LOCAL /
CONTRACT-BLOCKED）操作化为**常备机械检查表**：列出构成 contract 变更的
全部可判定信号（handle 字段变更、契约协议方法变更、payload 类型进入
contract target、coordinator 所有权转移、B1 强制化……），使未来任何轮次
可以机械回答「这是不是 contract change」。

### S3 — Gap-contract-impact audit
对 G-1…G-10 逐项回答：「若未来解决此 gap，是否必然构成 contract 变更？」
输出 LOCAL-FIXABLE / CONTRACT-BLOCKING-FUTURE 分类。**只分类，不解决，
不关闭**——本审计产出的是稳定性风险地图，不是修复计划。

### S4 — Second-backend demand analysis（审计级 thought experiment）
不实现第二个 backend；仅在审计层面回答：一个 client-side 物理状态型
backend（如本地 KV 复用策略——仅作为分析对象，非选型）将对 seam 提出
什么需求？其中哪些落 B1（预期行使者）、哪些已被显式降级覆盖、是否存在
 Round 1 未暴露的 seam 缺口。产出：需求清单 + 既有 seam 覆盖判定。

### S5 — Productization boundary criteria
Lab seam 成为产品架构边界的判据是什么（identity/ownership/测试面/演进
流程在产品仓的对应物）？**只定义判据**；产品仓工作不在本 gate 范围。

### S6 — Standing drift-detection surface
从既有工件组装（不新设计）常备回归面：conformance battery（已有）、
contract tests（已有）、M-1…M-5、S2 检查表。任何未来 contract 相关变更
必须过此面。**本轮不新增测试**；既有测试的复跑（regression re-run）不算
扩张。

## 4. Deliverable 与 verdict taxonomy

Deliverable：seam stability audit 文档（结构沿用 A1–A8 模式），最终三分
裁决：

```text
STABLE-AS-REGISTERED    现有 seam 在四轴上满足判据，无需预先修改
STABILITY-CONDITIONAL   稳定性成立但依赖已登记条件（如 G-gap 的解决顺序）
UNSTABLE                存在可证明的边界缺陷，须开独立 contract gate
```

## 5. Allowed / prohibited

```text
允许：
✔ 代码级与文档级 stability audit（S1–S6）
✔ 既有测试的 regression re-run（遵守 evidence-source-state 纪律）
✔ S4 审计级 thought experiment（不落地实现）
✔ 判据/检查表/分类法等定义性工件

禁止：
❌ 第二个 backend 的任何实现（含 skeleton）
❌ E1/E3/B1 / ExecutionStateHandle / Execution Semantic Snapshot 变更
❌ 新增测试设计（re-run 除外）
❌ storage / persistence format / API / protocol 设计
❌ performance claim（测量归 RQ3）
❌ oversized 特殊语义
❌ 解决或关闭 G-1…G-10（只分类）
❌ 读取或依赖 PALACE 线内容（如需接口，须先开显式 bridging registration）
```

## 6. Inherited conditions

Phase B 六条件、Phase C 四 strengthening、Round 1 M-1…M-5 与四条
strengthening（containment 术语 / 能力边界原则 / stub-live 分层 /
SUFFICIENT 适用域）、G-1…G-10、evidence-source-state 纪律——全部继承，
无一因本 opening 关闭。

## 7. Acceptance criteria

1. S1–S6 全部有审计级回答，区分三种陈述层级；
2. S2 产出可机械执行的 contract-change 检查表；
3. S3 产出 G-gap 稳定性风险地图（分类，不解决）；
4. S4 产出需求清单与覆盖判定，不产生实现工件；
5. S5 产出判据，不产生产品仓工作；
6. S6 产出从既有工件组装的 standing 面清单；
7. 最终给出三分裁决，边界声明与本草案 §5 逐字一致；
8. 若有测试复跑，证据对应确切源码状态（commit hash 级）。

## 8. Gate sequence

```text
本草案（participant proposal）
  → external review（PASS / FAIL / RETURN FOR REVISION）
  → explicit human registration（激活 seam stability audit）
  → audit（S1–S6）→ external review → registration
```

## 9. Relationship to other lines

```text
BACKEND-1 后续 engineering rounds = NOT OPENED；优先级被本 gate 取代
（非关闭；stability 结论若指向需要新工程轮次，届时另行 activation）
PALACE = SEPARATELY SCOPED；本 gate 不消费其内容
RQ1/RQ2/RQ3 = 维持各自登记状态，不吸收
```
