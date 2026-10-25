# Experiment / Design Register

**Purpose:** 为不同 Agent 提供实验资产的统一导航。此表不替代实验原文，也不改变实验状态。

## 1. Registered historical lines

| Asset family | Scope | Status | Authoritative source |
|---|---|---|---|
| Track B F1–F5 | Execution-state fork / restore / representation transition | CLOSED / FROZEN | `trackB-execution-state/TRACK_B_CLOSURE_RESULTS_20260921.md` |
| Track E M1–M4 | Residency baseline / mechanism experiments | FINAL / archived | `trackE-residency/RESIDENCY_M*_RESULTS_*.md` |
| P3 | Residency policy frequency mechanisms | CLOSED / sealed by subline | `trackE-residency/RESIDENCY_P3*_*.md` + state |
| H-P1 | Structure signal existence / strategy chain | CLOSED / SEALED | `trackE-residency/RESIDENCY_H-P1_RESULTS_20260922.md` |
| nodes-out | externalization pathway / mechanism accounting | CLOSED / archived | `trackE-residency/NODES_OUT_RESEARCH_ENDPOINT_DECISION_v0.1.md` |
| exp06 | Roofline / kernel-bandwidth opening gate | preregistered, not executed | `exp06-roofline/MEASUREMENT_PLAN_20260920.md` |
| Runtime2 | conceptual skeleton | NOTE-ONLY / FUTURE | `runtime2-skeleton/README.md` |

## 2. Lifecycle model

```
Question
  ↓
Design
  ↓
External Review
  ↓
Design Lock
  ↓
Implementation / Collection (only if authorized)
  ↓
Evidence
  ↓
Finding
  ↓
Decision
  ↓
Endpoint / Closure
  ↓
Frozen archive
```

Not every candidate reaches implementation. A design can terminate at a gate.

## 3. Reuse rule

Historical experiment code, runners and artifacts may be reused only through a new provenance anchor when the current research gate authorizes reuse. Reuse does not reopen the original question.

## 4. Current prohibition

No experiment in this register is authorized merely because it appears here. Current authorization remains in `RESEARCH_STATE.md` and the relevant active design.
