# Fresh-Agent L0→L1 Recovery — Entry-Surface Evaluation

Date: 2026-10-06  
Active route: `PALACE / INFORMATION SPACE FOUNDATION`  
Test: `FRESH-AGENT L0→L1 RECOVERY VALIDATION`  
Evaluation status: `DELIVERED / AWAITING HUMAN REVIEW`  
Test result classification: `NOT VALIDATED / WRONG ENTRY SURFACE`  
Gate baseline: `ab97244`  
Frozen Contracts: `UNCHANGED`  
Scope: `READ-ONLY EVALUATION · NO IMPLEMENTATION · NO BRANCH MERGE · NO CARRIER SELECTION · NO PROBE EXECUTION · NO EXPERIMENT · NO CONTRACT CHANGE`

## 1. Evaluation question

Did the fresh-Agent run actually test the accepted L0 Context Index and L1
Research State Capsules?

## 2. Verdict

```text
Fresh-Agent L0→L1 Recovery Test
  = NOT VALIDATED / WRONG ENTRY SURFACE
```

This is not a `FAIL` of L0/L1 quality or recovery capability. The run did not
enter the accepted L0/L1 surface.

## 3. Repository entry facts

```text
Intended research branch:
  codex/execution-state-research-20260929 @ d198a31

Intended L0:
  docs/RESEARCH_CONTEXT_INDEX.md

Intended L1:
  docs/research-capsules/v1/C01..C15

Default repository entry observed by fresh Agent:
  origin/main @ 6c3cf6a
  Freeze I-1c instantiate completeness conceptual design v0.3

Default branch index/capsule presence:
  docs/RESEARCH_CONTEXT_INDEX.md = absent
  docs/research-capsules/v1/C01..C15 = absent

Research branch index/capsule presence:
  docs/RESEARCH_CONTEXT_INDEX.md = present
  docs/research-capsules/v1/C01..C15 = present
```

Branch accounting:

```text
origin/main has 2 commits not present on the research branch:
  2b2e2ef Freeze IPAC Persistence Resolve conceptual design v0.3
  6c3cf6a Freeze I-1c instantiate completeness conceptual design v0.3

The research branch has 326 commits not present on origin/main.
These are different ancestry positions, not a simple fast-forward relation.
```

Therefore:

```text
Repository position ≠ current semantic/route authority.
```

## 4. Result interpretation

The fresh Agent recovered a coherent view of `main @6c3cf6a`. Many recovered
facts were historically correct for that node:

```text
ES I/P/A/C work
P4 / P7-1 bounded evidence
Contract v1.0-amended
backend-bounded evidence
E3 boundary
predictor frozen
IPAC conceptual boundary
```

But it did not recover the current route:

```text
PALACE / Information Space Foundation
PRQ-ISF-01
A4 Core Sufficiency Audit ACCEPTED / CLOSED
L0 Context Index
L1 Research State Capsules
Higher-Layer Continuation Graph Semantics as next entry
```

Thus the run exposed a discoverability and entry-surface problem:

```text
L0/L1 exist on the current research branch,
but they are not on the default entry surface.
```

## 5. What this run does and does not test

| Question | Result |
|---|---|
| Did L0/L1 content quality pass? | NOT TESTED |
| Did L0/L1 recovery capability pass? | NOT TESTED |
| Did default repository discoverability fail? | YES — FINDING |
| Did branch-to-current-state binding fail? | YES — FINDING |
| Should L0/L1 be rewritten because of this? | NO |
| Should capsules be expanded because of this? | NO |

## 6. New registered problem

The important question is no longer “add more capsules.” It is:

> How does the Information Place become the actual entry surface for a fresh
> Execution, rather than a side branch that the Agent must already know about?

This is directly relevant to the ES↔IS boundary:

```text
Information Place
        ↓
must be discoverable as current context
        ↓
Fresh Execution
        ↓
can reconstruct the correct current state
```

## 7. Candidate entry-surface decisions

No decision is made here. Human must explicitly select one.

```text
PATH A
  Merge / integrate the research branch state into the default entry surface so
  fresh Agents naturally see RESEARCH_CONTEXT_INDEX.md.

PATH B
  Preserve branch isolation, but make the target branch an explicit required
  input and prohibit default-main recovery.

PATH C
  Add a stable, branch-independent entry pointer that identifies the current
  Research Context State without making it the default branch.

PATH D
  Define another explicit mechanism, subject to separate Human ruling.
```

Human selected PATH A. Because `origin/main` and the research branch have diverged,
execution must use controlled integration, not a plain overwrite or assumed
fast-forward. The controlled integration plan is delivered at
`PALACE_INFORMATION_SPACE_FOUNDATION_PATH_A_INTEGRATION_PLAN_20261006.md`.

Machine probe result:

```text
Proposed merged tree = bac63b9d415e02bf9280311504c39479e8356d82
Conflicts            = NONE
I-1 / I-1c blobs     = unchanged from semantic authority
I-1d                 = introduced by research branch
```

Merge execution and default-main update still require explicit approval.

## 8. Non-claims

This evaluation does not claim that:

```text
L0/L1 content is invalid;
capsules failed;
Information Place failed;
MemPalace is rejected;
branch merging is authorized;
default-main state is worthless.
```

It also does not claim that the old main state was fabricated. It was a valid
recovery of an older repository node.

## 9. Next gate

Human must make the explicit entry-surface decision.

```text
AUTHORIZE PATH A      → integrate current research state into the default
                        entry surface, then rerun the fresh-Agent test.
AUTHORIZE PATH B      → rerun with explicit branch binding and no default-main
                        recovery.
AUTHORIZE PATH C/D    → design a branch-independent current-context pointer.
FINDINGS/PAUSE        → stop here without changing repository routing.
```
