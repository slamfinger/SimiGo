# ARES / Two-Layer Authorization Session Handoff

Date: 2026-10-05  
Branch: `codex/execution-state-research-20260929`  
Latest commit: `4c5354f research: design epistemic execution discrimination`  
Worktree: clean  

## 1. Current research chain

```text
846
 ↓
暂不触碰

Cross-model phenomena
 ↓
CI-C
 ↓
Relational Executable Function
 ↓
ARES hypothesis
 ↓
Authorization object = two-layer combination
 ↓
A_epistemic → A_execution discriminating design frozen
 ↓
等待 Human Review / 八格运行授权
```

## 2. Stable conclusions

1. **ARES remains hypothesis, not established Information Core.**

2. The strongest CI-C result is:

```text
K3_DELETED
        ↓
C4 absent

K3_PRECOMPUTED_F
        ↓
C4 preserved
```

This was replicated on C and N. A cannot serve as a positive control because its `FULL` baseline degraded.

3. Therefore the candidate invariant is:

> **relational executable admissibility function / relational executable function**

not `K1`, `K2`, or a particular `K3` representation.

4. Authorization boundary four-cell result was `AMBIGUOUS`:

```text
ALLOWED vs DENIED
        ↓
L1 source admission / declared provenance diverged
L4 surface C4 did not diverge
```

Reason: denied `F_content` remained visible, so actual consumption could not be resolved.

5. Human selected Authorization Object = **two-layer combination**:

```text
Information
    ↓
A_epistemic
    premise / evidence adoptability
    ↓
A_execution
    execution-path eligibility
    ↓
Relational Executable Function
    ↓
Continuation
```

## 3. Next authorized-through-design experiment

`A_EPISTEMIC_A_EXECUTION_EXPERIMENT_DESIGN.md` freezes an 8-cell design:

| Arm | E = A_epistemic | X = A_execution |
|---|---|---|
| 1 | E+ | X+ |
| 2 | E+ | X- |
| 3 | E- | X+ |
| 4 | E- | X- |

Models: C and N only.  
Total: 8 cells.

`F_content` remains identical and visible in all arms. No K1/K2/K3 deletion occurs.

Expected ordered-layer signature:

| Arm | adoption | C4 emission |
|---|---:|---:|
| E+ X+ | true | true |
| E+ X- | true | false |
| E- X+ | false | false |
| E- X- | false | false |

Critical separation cell: `E+ X-`.  
Critical bypass/leak cell: `E- X+`.

If `E-` emits C4, classify as leakage / model prior, not evidence for ordered layers.

## 4. Possible result labels

```text
ORDERED_SEPARATION_SUPPORTED
MERGED_BOUNDARY_SUPPORTED
REVERSE_DEPENDENCY_SUPPORTED
LEAK_DOMINATED
MODEL_SPECIFIC_LEAK
AMBIGUOUS
```

## 5. Next gate

Wait for human review, then explicit authorization for:

1. prompt implementation;
2. runner implementation;
3. 8-cell run.

No run is currently authorized.

## 6. Hard boundaries

Do not:

```text
touch 846
run Observer
write InformationCore
declare minimal Information Core
retry B
retry D
use A
run without explicit authorization
```

## 7. Key files

- `A_EPISTEMIC_A_EXECUTION_EXPERIMENT_DESIGN.md`
- `AUTHORIZATION_OBJECT_DECISION.md`
- `AUTHORIZATION_BOUNDARY_GATE.md`
- `authorization_boundary/AUTHORIZATION_BOUNDARY_RESULTS.md`
- `authorization_boundary/AUTHORIZATION_BOUNDARY_RESULTS.md`
- `PARTIAL_MATRIX_REPORT.md`
