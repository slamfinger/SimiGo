# SimiGo-Lab — R-C1 Attempt #4 Human Authorization Record

**Authorization Status:** AUTHORIZED
**Authorization Type:** Explicit Human Authorization for R-C1 execution
**Authorization Time:** 2026-10-03T11:54+08:00
**Execution Baseline:** `569fe540d1ff`
**Implementation Revision:** D-4
**C-Impl Audit:** PASS
**R-C1 Attempt #4:** AUTHORIZED / READY TO EXECUTE

---

## 1. Authorization Scope

本授权仅批准在冻结研究边界内执行 **R-C1 Attempt #4**。

本次授权不批准：

* 修改 C-Spec；
* 修改 C-Design；
* 修改 C-Impl；
* 修改 Core；
* 修改 preregistered protocol；
* 修改 evaluator；
* 修改 stop conditions；
* 根据执行中出现的问题临时扩大或改变研究问题。

执行必须以以下状态为唯一基线：

```text
B Track   = CLOSED

C Gate    = OPEN
C-Spec    = FROZEN / HUMAN RE-AUDIT PASS
C-Design  = CONFIRMED / HUMAN RE-AUDIT PASS WITH CONDITION
C-Impl    = D-4 REVISION AUDIT PASS
C-Execute = AUTHORIZED

R-C1 #1   = STOPPED / INVALID INCONCLUSIVE
R-C1 #2   = STOPPED / INVALID INCONCLUSIVE
R-C1 #3   = STOPPED / INVALID INCONCLUSIVE
R-C1 #4   = AUTHORIZED / EXECUTION PENDING
```

---

## 2. Fixed Baseline

本次执行固定使用：

```text
Commit:
569fe540d1ff

Message:
C-Impl: model staged C-C construction states
```

D-4 已通过 C-Impl audit。

D-4 的修订范围仅为 C-C staged construction validation：

```text
[]
task
task + s0
task + s0 + s1
task + s0 + s1 + progress
task + s0 + s1 + progress + relation
```

其中：

```text
Relation
    = only legal after complete base

Final
    = task + s0 + s1 + progress + relation
```

本次执行不得重新解释上述状态模型。

---

## 3. Previous Attempts

以下历史执行结果已经封存，本次不得重新分类：

```text
R-C1 #1 = STOPPED / INVALID INCONCLUSIVE
R-C1 #2 = STOPPED / INVALID INCONCLUSIVE
R-C1 #3 = STOPPED / INVALID INCONCLUSIVE
```

这些结果不是 continuation hypothesis 的支持或反驳证据。

本次 Attempt #4 必须建立新的独立 Run ID 和独立 evidence root。

---

## 4. Required Lifecycle

R-C1 #4 必须按照既定生命周期执行：

```text
old process
    ↓
required checkpoint formation
    ↓
external physical overwrite
    ↓
process termination
    ↓
fresh process
    ↓
continuation / restoration
    ↓
independent evaluator
```

C-A、C-B、C-C 均必须完成各自 preregistered lifecycle。

不得以单进程 continuation 替代 fresh-process continuation。

不得跳过 external physical-change / overwrite 阶段。

---

## 5. Required Tracks

### C-A

必须完成：

```text
old process
→ checkpoint
→ external overwrite
→ fresh process
→ continuation
→ evaluator
```

并保留：

* old-process evidence；
* fresh-process evidence；
* overwrite evidence；
* source / target physical-change hashes；
* timestamps；
* evaluator result。

### C-B

必须保持：

```text
Information persistence = ENABLED
Relation persistence    = DISABLED
```

C-B 必须继续使用 Information-only path。

不得因为 D-3 已修复而引入 Relation semantics。

Disabled Relation carrier 必须继续保持 fail-closed。

### C-C

必须使用 frozen Relation path。

本次特别验证 D-4 修订后的 staged construction sequence：

```text
[]
→ task
→ task + s0
→ task + s0 + s1
→ task + s0 + s1 + progress
→ task + s0 + s1 + progress + relation
```

不得通过 fallback bypass staged validation。

不得用 C-B 的 independent Information path 替代 C-C Relation path。

---

## 6. Evidence Requirements

本次执行必须产生足够证据证明：

### Lifecycle integrity

```text
old process
→ external overwrite
→ process termination
→ fresh process
→ continuation
```

能够被独立重建。

### Evidence preservation

old-process 与 fresh-process evidence 必须分别保留。

禁止：

```text
fresh evidence overwrites old evidence
```

### Physical change

必须记录：

* external overwrite；
* source hash；
* resulting/reference hash；
* relevant timestamps。

### Carrier separation

必须能够区分：

```text
C-B = Information-only carrier
C-C = Relation carrier
```

不得发生 semantic substitution。

### Forbidden-channel evidence

Forbidden-channel exclusion 必须通过 **实际 R-C1 #4 execution evidence** 建立。

静态检查、source inspection、implementation audit 均不得替代本项实验性证据。

---

## 7. Evaluator Requirement

R-C1 #4 的正式 continuation judgment 必须依据冻结 evaluator。

完整实验要求：

```text
C-A = completed
C-B = completed
C-C = completed
```

并满足各自的：

```text
X-1
X-2
X-3
X-4
X-5
```

规定。

任何单独 track 的成功不得自动升级为整个 R-C1 的 hypothesis-level conclusion。

特别是：

```text
C-B FULL SUCCESS
```

即使再次出现，也只能作为对应 track 的执行证据，不能单独构成 R-C1 总体结论。

---

## 8. Stop Conditions

以下任一条件出现，立即停止 R-C1 #4：

1. implementation baseline 改变；
2. C-Spec 改变；
3. C-Design 改变；
4. protocol 改变；
5. evaluator 改变；
6. evidence 被覆盖、丢失或无法区分 lifecycle；
7. C-C 出现 Relation fallback；
8. C-B 出现 Relation semantics；
9. forbidden-channel evidence 无法建立；
10. physical-change / carrier evidence 缺失；
11. 出现 semantic substitution；
12. 需要修改 implementation 才能继续；
13. 出现未被当前 frozen design 覆盖的新状态，而继续执行需要临时定义其语义；
14. 任一其他条件使 preregistered R-C1 protocol 无法保持原样执行。

Stop 后：

```text
STOP
→ preserve evidence
→ classify execution integrity
→ do not improvise repair
→ do not interpret hypothesis
```

---

## 9. No-Modification Rule

从本授权生效开始，到 R-C1 #4 完成或触发 stop condition 为止：

```text
Implementation = immutable
Protocol       = immutable
Core           = immutable
C-Spec         = immutable
C-Design       = immutable
Evaluator      = immutable
```

任何 defect 均不得在运行过程中现场修复。

如必须修改 implementation：

```text
R-C1 #4 = STOPPED
C-Impl   = REOPENED
```

随后重新执行：

```text
revision
→ audit
→ human authorization
→ new R-C1 attempt
```

---

## 10. Result Classification

R-C1 #4 完成后，结果必须按以下层次分类：

### Layer 1 — Evidence Integrity

```text
PRESERVED
PARTIAL
INVALID
```

### Layer 2 — Protocol Result

仅当 preregistered execution 完整完成时进行：

```text
VALID
INVALID
INCONCLUSIVE
```

### Layer 3 — Research Interpretation

仅在 Layer 1 与 Layer 2 均满足相应条件后，才允许讨论：

```text
continuation hypothesis
IPAC-related evidence
Execution State interpretation
```

不得由 implementation PASS 直接推导 research conclusion。

---

## 11. Authorization Decision

经当前 C-Impl D-4 re-audit：

```text
C-Spec    = FROZEN / PASS
C-Design  = CONFIRMED / PASS
C-Impl    = D-4 REVISION AUDIT PASS
```

因此，本授权正式批准：

```text
R-C1 Attempt #4 = AUTHORIZED
```

唯一执行基线：

```text
569fe540d1ff
```

执行期间不得进行任何 implementation、protocol 或 specification 修改。

新的 Run ID 必须在实际执行启动时生成，并与本 Authorization Record 建立一一对应关系。

---

## 12. Post-Authorization State

授权后、实际执行开始前：

```text
B Track   = CLOSED

C Gate    = OPEN
C-Spec    = FROZEN / HUMAN RE-AUDIT PASS
C-Design  = CONFIRMED / HUMAN RE-AUDIT PASS WITH CONDITION
C-Impl    = D-4 REVISION AUDIT PASS
C-Execute = AUTHORIZED / PENDING EXECUTION

R-C1 #1   = STOPPED / INVALID INCONCLUSIVE
R-C1 #2   = STOPPED / INVALID INCONCLUSIVE
R-C1 #3   = STOPPED / INVALID INCONCLUSIVE
R-C1 #4   = AUTHORIZED / NOT YET EXECUTED
```

**Authorization does not constitute an experimental result.**

**C-Impl audit PASS does not constitute continuation-hypothesis confirmation or rejection.**

**R-C1 #4 的研究解释必须等待实际 execution result。**
