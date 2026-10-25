# C Track — R-C1 正式执行授权单

**Execution Authorization Record**

* Track: C
* Experiment: R-C1
* Implementation baseline: `bae68a852cfc`
* Branch: `codex/execution-state-research-20260929`
* Authorization state: **AUTHORIZED / CONSUMED**
* Current execution state: **STOPPED / IMPLEMENTATION DEFECT**
* Attempt #2 baseline: **`df7a6246c7a8`**

---

## 1. Pre-Execution Gate

本执行单确认以下前置条件已经满足：

```text
B Track
= CLOSED

C Gate
= OPEN

C-Spec
= FROZEN / HUMAN RE-AUDIT PASS

C-Design
= CONFIRMED / HUMAN RE-AUDIT PASS WITH CONDITION

C-Impl
= AUDITED / PASS

C-Execute
= NOT AUTHORIZED → 待本授权单批准

R-C1
= NOT RUN
```

C-Impl Re-audit 针对 revision：

```text
bae68a852cfc
```

审计结论为：

```text
C-Impl = PASS
```

因此该 implementation 已达到执行前 implementation audit 门槛。

---

## 2. Execution Authorization Boundary

本授权仅批准：

> 在冻结的 C-Spec、已确认的 C-Design 以及通过 implementation audit 的 `bae68a852cfc` 基线上执行 R-C1。

本授权**不批准**：

* 修改 C-Spec；
* 修改 C-Design；
* 修改 C-Impl；
* 修改 ExecutionCore / InformationCore / RelationCore；
* 修改 R-C1 的 X-1 ～ X-5 protocol；
* 为获得预期结果而增加 fallback；
* 在执行过程中改变 semantic path；
* 将执行结果预先解释为对 IPAC、Execution State 或 continuation hypothesis 的证明。

任何发现的新问题，都必须作为 execution evidence / defect / deviation 记录，而不是在 R-C1 运行期间直接修改 protocol。

---

## 3. Frozen Execution Baseline

R-C1 唯一 implementation baseline：

```text
commit = bae68a852cfc
```

执行前不得在该 baseline 上追加未审计的 implementation change。

如工作树存在与 R-C1 无关的本地修改：

```text
不得将其纳入 R-C1 execution baseline。
```

如必须修改 implementation：

```text
R-C1 = STOP
C-Impl = REOPEN
重新进入 implementation audit
```

---

## 4. Required Lifecycle

R-C1 必须保持真实的 lifecycle separation：

```text
OLD PROCESS
    ↓
execute / establish required state
    ↓
persist required evidence
    ↓
TERMINATE OLD PROCESS
    ↓
FRESH PROCESS
    ↓
load / continue
    ↓
collect continuation evidence
```

不得使用同一进程继续运行来替代 fresh-process continuation。

必须保留能够区分 lifecycle phase 的证据，包括：

```text
old process
  invocation-evidence.jsonl
  command = old

fresh process
  continuation-evidence.json
  command = continue
```

并保留必要的 PID / lifecycle markers，使后续可以验证 old process 与 fresh process 确实是两个生命周期阶段。

---

## 5. R-A1 Constraint

R-A1 已通过 audit。

R-C1 执行时：

```text
old evidence
≠
fresh evidence
```

fresh-process evidence 不得覆盖 old-process evidence。

任何 evidence overwrite、缺失或 lifecycle 无法区分的情况：

```text
→ execution evidence integrity issue
→ 不得静默修复后继续
```

---

## 6. R-A2 Constraint — C-C Relation Fail Closed

C-C 必须使用其规定的 Relation path。

以下任一情况：

```text
Relation pointer missing
Relation fetch returns nil
Relation cannot be resolved
```

均必须得到：

```text
relationMissing = true
blocker = relation_not_found
```

并保持：

```text
C-C s0/s1 pointer fallback = FORBIDDEN
```

不得通过独立 `s0` / `s1` pointer 替代 Relation 以制造成功结果。

---

## 7. C-B Independence

C-B 保持：

```text
Information-only path
```

C-B 不得引入 C-C Relation semantics。

因此：

```text
C-B
  → Information

C-C
  → Relation
```

两条路径必须保持实验上的独立性。

C-C Relation failure 不得通过修改 C-B semantics 来补偿。

---

## 8. Forbidden-Channel Evidence

当前 implementation audit **没有证明** forbidden channels 在实际执行中不存在。

因此该问题只能由 R-C1 execution evidence 判断。

R-C1 必须记录：

```text
method
observed
passed
```

以及 protocol 所要求的相关 execution evidence。

不得将：

```text
static absence
+
unit test PASS
```

解释为：

```text
runtime forbidden-channel exclusion = proven
```

只有实际 R-C1 evidence 才能支持该结论。

---

## 9. Physical-Change / Carrier Evidence

R-C1 执行必须保留 protocol 要求的：

* Physical Space source reference；
* overwrite / physical-change reference；
* S0 / S1 snapshot correspondence；
* carrier identity；
* 必要的 timestamps；
* lifecycle evidence。

这些证据用于证明实验实际经历了 protocol 所规定的 physical / carrier conditions，而不是仅在逻辑对象层面模拟变化。

---

## 10. Execution Integrity Rules

R-C1 运行期间：

### Allowed

* 按冻结 protocol 执行；
* 记录 evidence；
* 记录环境事实；
* 记录 failure；
* 记录 blocker；
* 记录 deviation；
* 终止因安全或完整性问题而无法继续的 execution。

### Forbidden

* 修改 C-Spec；
* 修改 C-Design；
* 修改 implementation；
* 添加 fallback；
* 删除失败 evidence；
* 覆盖旧 lifecycle evidence；
* 修改答案常量；
* 将实验预期写入 runtime；
* 根据中间结果改变 protocol。

---

## 11. Result Classification

R-C1 完成后，结果必须分层判断。

### A. Evidence Integrity

首先判断：

```text
Evidence complete?
Lifecycle reconstructable?
Required artifacts preserved?
```

若否：

```text
R-C1 = INVALID / INCONCLUSIVE
```

不得直接解释为 hypothesis failure。

### B. Protocol Result

若 evidence integrity 满足，再逐项判断冻结 protocol 中的 X-1 ～ X-5。

可能结果包括：

```text
PASS
PARTIAL PASS
FAIL
BLOCKED
INCONCLUSIVE
```

具体含义以冻结 protocol 为准，不在执行后临时重新定义。

### C. Research Interpretation

只有在 execution evidence 完整后，才讨论其对：

```text
Execution State
continuation
IPAC candidate closure
```

等研究问题的支持、限制或反证意义。

R-C1 本身不自动证明：

```text
IPAC minimality
backend independence
universal applicability
PALACE completeness
```

这些仍属于更高层研究问题。

---

## 12. Stop Conditions

出现以下任一情况，应停止 R-C1 或进入明确的 blocked/deviation 状态：

```text
1. Frozen implementation baseline 被改变
2. C-Spec / C-Design 被改变
3. old/fresh lifecycle 无法区分
4. evidence 被覆盖或丢失
5. C-C Relation 缺失却出现 fallback
6. forbidden-channel evidence 无法建立
7. physical-change / carrier condition 无法证明
8. runtime 出现 protocol 未定义的 semantic substitution
9. 为继续实验必须修改 implementation
```

停止后：

```text
R-C1 ≠ 自动失败
```

应先判定是：

```text
execution invalidity
implementation defect
protocol deviation
or genuine experimental failure
```

---

## 13. Authorization Decision

本执行单准备进入 Human Authorization。

授权人确认：

```text
[ ] 已确认 C-Spec 为 frozen
[ ] 已确认 C-Design 为 confirmed
[ ] 已确认 C-Impl audit = PASS
[ ] 已确认 implementation baseline = bae68a852cfc
[ ] 已确认 R-C1 protocol 不在本次执行中修改
[ ] 已确认 R-C1 尚未执行
[ ] 已确认 execution evidence 必须真实记录
[ ] 已确认 execution result 不得预先解释
```

### Human Authorization

```text
R-C1 = AUTHORIZED
```

授权时间：

```text
____________________________
```

授权人：

```text
____________________________
```

Implementation baseline：

```text
bae68a852cfc
```

---

## 14. Post-Authorization State

授权完成后：

```text
C-Impl
= AUDITED / PASS

C-Execute
= AUTHORIZED

R-C1
= READY TO RUN
```

只有实际开始执行后，才将：

```text
R-C1 = RUNNING
```

执行完成并完成 evidence audit 后，再进入结果判定。

---

## 15. Final Boundary

本授权单的核心边界：

> **授权的是一次受冻结 protocol 约束的实验执行，而不是对实验结果的预授权。**

因此：

```text
C-Impl PASS
        ↓
Human Authorization
        ↓
R-C1 Execution
        ↓
Evidence
        ↓
Protocol Result
        ↓
Research Interpretation
```

不得跳过中间层级。

## 16. Execution Consummation Addendum — 2026-10-03

Human authorization was received in chat as:

```text
R-C1 = AUTHORIZED
```

Authorization time: `2026-10-03T04:18:37+0800`.
Authorized implementation baseline: `bae68a852cfc`.
Authorized run root:
`docs/02-evidence/rc1-execution/RC1-20261002T202144Z-42754`.

Execution stopped at C-B because the frozen implementation raised:

```text
invalid state: C-B carrier pointer set is invalid
```

The run is classified `INVALID / INCONCLUSIVE — IMPLEMENTATION DEFECT`.
No implementation, Core, C-Spec, C-Design, X-1…X-5, or protocol semantics
were changed during execution. Evidence is preserved in the run root.
C-Impl is reopened for revision. A new C-Execute authorization is required
after C-Impl audit.

## 17. Attempt #2 Consummation Addendum — 2026-10-03

A new explicit authorization was issued for Attempt #2 with implementation
baseline `df7a6246c7a8`. Run root:

```text
docs/02-evidence/rc1-attempt2/RC1-A2-20261002T204925Z-45791
```

Attempt #2 stopped at C-B because the frozen implementation force-unwrapped a
nil `relationStore` for an arm with Information persistence enabled but
Relation persistence disabled. Crash evidence, partial C-A evidence, and the
empty C-B checkpoint are preserved. No implementation or protocol change was
made during execution. Attempt #2 is classified:

```text
INVALID / INCONCLUSIVE / IMPLEMENTATION DEFECT
```

## 18. Attempt #3 Consummation Addendum — 2026-10-03

A new explicit authorization was issued for Attempt #3 with implementation
baseline `806dd3eea55c`. Two earlier orchestration roots aborted before an
R-C1 protocol result and were preserved as orchestration-invalid. Official
run root:

```text
docs/02-evidence/rc1-attempt3/RC1-A3-20261002T211332Z-48860
```

C-A completed with partial X-1-only recovery. C-B completed with X-1…X-5.
C-C stopped before its awaiting marker because construction validation
rejected the legal staged C-C state. No implementation or protocol change was
made during execution. Attempt #3 is classified:

```text
INVALID / INCONCLUSIVE / IMPLEMENTATION DEFECT
```

## 19. Attempt #4 Consummation Addendum — 2026-10-03

Attempt #4 authorization was consumed at implementation baseline
`569fe540d1ff`. Run root:

```text
docs/02-evidence/rc1-attempt4/RC1-A4-20261003T040749Z-57375
```

Layer 1 = `PRESERVED`.
Layer 2 = `VALID THREE-ARM EXECUTION COMPLETED`.

Protocol observations:

```text
C-A = PARTIAL SUCCESS / X-1 only
C-B = FULL SUCCESS / X-1…X-5
C-C = FULL SUCCESS / X-1…X-5
```

C-C used the persisted Relation path and no fallback occurred. C-B remained
Information-only. Runtime forbidden-channel checks all passed. No
implementation, protocol, Core, C-Spec, or C-Design change occurred during
execution.
