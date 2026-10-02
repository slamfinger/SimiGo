# C-SPEC Human Audit — Rulings and C-Design Input Constraints

Date: 2026-10-03  
Status: `CONDITIONAL PASS / REVISE EXECUTED / RE-AUDIT PASS / C-SPEC FROZEN`  
Audit object: `SIMIGO_LAB_C_QUESTION_SPEC_20261003.md`  
Scope: C-Spec research question, controls, and conclusion boundary only.

## 1. H rulings

| # | Item | Ruling |
|---|---|---|
| H-1 | C-Q1 testability | PASS WITH CONDITION |
| H-2 | C-A/B/C minimum controls | PASS WITH CONDITION |
| H-3 | Fair comparison | PASS WITH CONDITION |
| H-4 | Lifecycle wording | FAIL AS CURRENTLY WORDED |
| H-5 | Implicit-state leakage | PASS WITH CONDITION |
| H-6 | Conclusion boundary | PASS |

## 2. Lifecycle ruling

The broader C-Q1 may mention termination / restart / transfer, but this
experiment studies only:

```text
termination → restart → cold start → continue task
```

`transfer` is not covered, must not be inferred, and remains a separate
future lifecycle condition.

## 3. C-A boundary

C-A may keep Execution State's own persistence needed to resume execution,
but it must not have a persistent Information Space.

```text
C-A control variable = presence/absence of Information Space,
                       not presence/absence of all persistence.
```

## 4. C-B Information boundary

C-B may persist task-relevant facts, entity states, execution context,
task instructions, todo/progress, and factual change descriptions as
Information.

C-B must not have an independent persistent Relation carrier or Relation
semantic mechanism.

```text
Allowed:
  Information(S0)
  Information(S1)
  task facts / progress / factual descriptions

Forbidden in C-B:
  RelationStore
  ChangeRelation(S0, S1)
  equivalent dedicated relation object
```

The subject may infer relationships from independent Information at runtime.
That temporary inference does not make C-B into C-C. C-C is distinguished by
the persisted Relation carrier/mechanism.

## 5. Fairness constraint

All arms must share:

```text
same task
same initial input
same S0
same real external change
same S1
same termination point
same cold-start condition
same continuation task
same success/failure criteria
```

Only the systematic boundary differs:

```text
C-A = ES only
C-B = ES + Information
C-C = ES + Information + Relation
```

## 6. Cold-start constraint

Cold start must at least mean:

```text
new process
no old process memory
no old ExecutionCore runtime state
no old model context / KV / implicit run state
```

The verifier may obtain past information only through explicitly allowed
persistent carriers. Concrete forbidden channels must be made auditable in
C-Design.

## 7. Result

```text
C-SPEC = REVISE REQUIRED / revision executed
Human re-audit = PASS
C-SPEC = FROZEN
C-Design = OPEN / READY / NOT STARTED
C-Impl = NOT AUTHORIZED
C-Execute = NOT AUTHORIZED
```
