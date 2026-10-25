# Execution State Architecture Contract — Opening Draft

日期：2026-09-30  
状态：`PARTICIPANT PROPOSAL / AWAITING EXTERNAL REVIEW`  
前置 gate：Seam stability = `PASS / REGISTERED / CLOSED`（`d9d1f33`，
STABLE-AS-REGISTERED 有界）；Round 1 = REGISTERED / CLOSED；Phase C =
REGISTERED；Phase B = REGISTERED  
基线：`d9d1f33`  
登记依据：route redefinition `SIMIGO_LAB_EXECUTION_STATE_RESEARCH_ROUTE_
REDEFINITION_20260929.md` §16——「Execution State Architecture Contract：
`NEXT SYNTHESIS GATE`」  
性质：participant proposal，不是 repository registration

```text
observed code fact ≠ inferred contract text ≠ selected implementation
```

## 1. Opening purpose 与研究问题

**本 gate 不是重新发明 Execution State，也不重新设计代码**——route 对
synthesis gate 的原始定义就是「从已经验证的 Runtime 代码中提炼最小架构
契约；首轮只做 code audit / synthesis，不写生产实现」。Round 1 与 seam
stability 已经提供了「工程事实侧」的全部输入；本 gate 把它们第一次提升为
唯一的上游语义契约。

> 在已登记的 E1+E3+B1 seam、Execution Semantic Snapshot 边界以及 PALACE-1
> durable-state boundary 基础上，能否定义一份独立于 MLX、具体 backend、
> model format 和 physical representation 的 Execution State Architecture
> Contract，使「同一 Execution State」的语义不依赖具体实现，并为后续
> PALACE durable-state 与 Backend Independence 提供唯一上游语义基准？

核心追问：**如果明天 MLX 换掉、KV representation 换掉、model format 换掉、
backend 换掉，什么东西还必须保持不变？**

## 2. 与既有登记的关系（合成，不覆盖）

本 gate 的产出是一份**合成契约**：每一条语义陈述必须可追溯到已登记工件；
任何在合成过程中发现的语义缺口或工件间冲突，登记为 open point，不得静默
解决。关系图：

```text
Phase B（Execution Semantic Snapshot + recoverable set）──┐
Phase C（E1+E3+B1 seam，61/61）                           ├─→ [本 Contract]
Seam stability（STABLE-AS-REGISTERED + S2/S6 纪律）       │      = 唯一上游语义锚点
Round 1（真实穿透证据 + M-1…M-5）────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    ▼                               ▼
            PALACE durable-state             Backend Independence
            （未来消费方）                   （未来判定标准）
```

## 3. Registered inputs

| 工件 | 状态 | 本 gate 用法 |
|---|---|---|
| Phase A boundary audit（D/R/P/O/T 分类 + 45/45） | REGISTERED | AC-1 的分类基准 |
| Phase B minimal durable unit audit + registration | REGISTERED | AC-1/AC-2 的 snapshot/tombstone 语义 |
| Phase C seam audit（E1+E3+B1，61/61） | REGISTERED | AC-3 的边界语义 |
| Adapter Round 1（SUFFICIENT 有界，75/75） | REGISTERED / CLOSED | AC-4 的首个判例（非定义的普遍性证明） |
| Seam stability audit（STABLE-AS-REGISTERED + S2 十二信号 + S6 standing 面） | REGISTERED / CLOSED | Contract 的漂移检测挂钩 |
| PALACE hypothesis（`04c608e`） | SEPARATELY SCOPED | 不读取不依赖；Contract 是其未来上游锚点 |

## 4. Proposed subquestions AC-1…AC-4（含 route 六问收口）

### AC-1 — Semantic Core（route Q2/Q3 收口）
逐项冻结状态本体：identity / lineage / position / continuation /
lifecycle / recovery semantics。每项回答：State 本体（D）？runtime binding
（R）？physical representation（P）？observability（O）？可重建（T）？
全部引 Phase A/B 已登记 disposition；出现任何与登记冲突处 → open point。

### AC-2 — Identity / Continuity（route Q1 收口；本 Contract 最关键一刀）
回答「什么情况下换了 representation 仍是同一个 Execution State、什么情况
下是新 State」：

```text
same State ⟺ id / lineage / position / continuation / lifecycle 语义保持，
              representation 侧仅发生已登记的显式结果变化
              （reattach / rematerializationRequired / recompute）
new State  ⟺ 仅由 create / fork 产生的新 ExecutionID
```

已登记先答：identity = opaque ExecutionID（reservation/tombstone 规则，
Phase B B1/B7）；continuation.nextInput 维持 D（Phase B B2——transcript
等价性仍是 open point，合成不得弱化或假设等价）；跨重启 reservation（G-7）
与 durable lineage closure 是 open points。**AC-2 的产出 = same/new State
判据的契约化表述 + open points 清单，不发明新身份规则。**

### AC-3 — Representation Boundary（route Q4/Q5/Q6 收口）
固定 `Execution State →(RepresentationRef)→ Physical Representation` 的
语义关系与四态结果（available→reattach；unavailable→rematerialize→
recompute→fail closed）——全部引 Phase B B4/B5/B6 与 ResolutionState；
BindingRegistry 保持 execution-scoped separately-typed relation（Phase B
B4）；runtimeAddress 恒为 R。**不选数据库、不选文件格式、不定义协议。**

### AC-4 — Backend Independence 判定标准
一个新 backend 满足什么才算「实现了 SimiGo Backend Independence」：

```text
✔ implements representation capability（E3 或 B1，按真实物理所有权）
✔ does not own / mutate Execution semantics（sovereignty：C-4 信号恒否）
✔ can explicitly degrade representation（四态结果，无静默换语义）
✔ preserves semantic continuity（AC-2 判据在同一 battery 下成立）
✔ passes the standing conformance battery without semantic assertion change
  （M-1…M-5 + evidence-source-state 纪律适用于其工程轮次）
```

Round 1 是该标准的**第一个判例**，不是定义的普遍性证明（Round 1 适用域
钉死条款继续有效）。

## 5. Contract 文档要求（registration 后的产出定义）

1. 四章对应 AC-1…AC-4；版本化（v1.0）；每条语义陈述带登记引用；
2. 不可追溯的陈述 = open point（ledger 化），不进契约正文；
3. 契约自身的变更纪律：修订只能经 contract gate（S2 十二信号 + S6 面
   适用）；
4. open points ledger：transcript 等价性（Phase B 条件 2）、G-7 durable
   reservation、G-10 durable store 交互、其余继承 gaps——携带不关闭；
5. 契约文本不含 storage/format/API 选择、不含 performance 数值。

## 6. Allowed / prohibited

```text
允许：
✔ code/doc-level synthesis audit（AC-1…AC-4）
✔ 既有证据引用与（如需）既有 battery 的 hash 级绑定 re-run
✔ 契约文档与 open points ledger 起草
禁止：
❌ 代码重设计 / 生产实现
❌ 修改任何已登记语义（冲突 → open point → contract gate）
❌ storage / persistence format / API / protocol 选择或定义
❌ 新增测试设计（re-run 除外，hash 级绑定）
❌ PALACE 消费（Contract 是其未来上游锚点；接口须显式 bridging registration）
❌ performance / universal portability claim
❌ 关闭任何 inherited gap
```

## 7. Inherited conditions

Phase B 六条件、Phase C 四 strengthening、M-1…M-5、G-1…G-10、Round 1 四
strengthening（containment 术语 / 能力边界原则 / stub-live 分层 / 适用域）、
seam stability 四 strengthening + S2/S6 standing 纪律、evidence-source-state
纪律——全部继承，无一因本 opening 关闭。

## 8. Acceptance criteria

1. AC-1…AC-4 全部有合成回答，route 六问逐条收口（含其登记先答的引用）；
2. 契约草稿零不可追溯陈述；open points ledger 完整；
3. AC-2 的 same/new State 判据与 Phase B 全部条件相容（尤其条件 2 不被
   弱化）；
4. AC-4 判定标准可被 S2/S6 机制机械检验；
5. 若发生测试复跑，证据绑定 commit-hash 级源码状态；
6. 最终契约文档达到 §5 的五项要求。

## 9. Gate sequence

```text
本草案 → external review → explicit human registration
  → Architecture Contract synthesis/audit（AC-1…AC-4 → 契约文档 v1.0 草案）
  → external review → registration（契约 v1.0 成为登记上游锚点）
```

## 10. Relationship to other lines

```text
PALACE = SEPARATELY SCOPED；Contract 是其 durable-state 工作的未来上游
         锚点，消费前须显式 bridging registration
BACKEND-1 后续 rounds = NOT OPENED；AC-4 成为未来 activation 的判定标准
RQ1/RQ2/RQ3 = 维持各自登记状态；AC-4 与 RQ2（跨架构）的衔接属未来 gate
oversized = FROZEN / validation payload，不变
```
