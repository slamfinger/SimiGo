# SimiGo 2.0 — Runtime Engineering Validation Complete v1.0 (Gate A)

Status: RUNTIME_ENGINEERING_VALIDATION_COMPLETE / EXECUTION_STATE_ENGINEERING_GATE_REGISTERED_NEXT
Date: 2026-09-25
Anchor: repository `slamfinger/SimiGo-Lab`, branch `exp/simigo2-experimental`,
HEAD at registration `aa30eb2` (the earlier external observation of "branch
missing / SHA unverifiable" was made against the wrong repository —
`slamfinger/SimiGo` — and is voided; `aa30eb2` is the verified HEAD of the
correct repository).
Scope: formal closure of the Runtime Residency Engineering validation line
(L1/L2 → L4-C). This gate registers completed evidence; it opens no
research.

## 1. Validation chain (all executable evidence)

| Gate | Content | Evidence |
|---|---|---|
| Requirements | Contract v1.0 (efeb49c): 7 boundary domains, 2 run conditions, 14 acceptance points | `SIMIGO2_RUNTIME_RESIDENCY_ENGINEERING_REQUIREMENTS_v1.0.md` |
| Verification design | 35/35 requirements → verification items; INV-1/2/3; L1–L4 layers | `SIMIGO2_RUNTIME_RESIDENCY_VERIFICATION_DESIGN_v1.0.md` (022fd16) |
| L1/L2 | Planner contract + controller state-machine contract: 60→67 PASS | 942f0a9, 3042b70, 2f8bd0c, 254638b |
| Controller | Production `ResidencyController` (single writer, commit-after-effect, fail-fast overflow, windows) | 3d4fdd7 |
| L3 fault injection | F1–F8 + F7b: 76/76 PASS | 78af4f5 |
| B1/B2 | `SimiGoRuntimeContract` pure target (MLX-free by package graph) + 4 contract tests | ee07123 |
| L4-A | `MLXResidencyBackend` adapter; contract async amendment (semantic zero change) | 0774110 |
| L4-B | INV-3 real byte reconciliation, 5 models × 10 transitions: all within ε = 5 MiB | 250f683 |
| L4-C | Computational identity, 3 models × 3 prompts: token/logits/max_abs_diff = 0 | aa30eb2 |

Full suite at closure: **80/80 test cases PASS** (76 XCTest incl. L1/L2/L3
regression + 4 contract-target tests).

## 2. Verification-system quality improvements (registered as first-class)

Four defect classes were caught by the verification gates themselves and
fixed before results were accepted. They are registered as improvements to
the verification system, not incidental bug fixes:

1. **F-L1-1** — planner auto-retained UNHINTED optional groups (violated
   documented intent + R1.4). Fix: retention candidates are hinted groups
   only; verified behavior-preserving for all registered research artifacts
   (budget sweep / trace replay byte-identical re-runs).
2. **F-L2-1/F-L2-2** — state-machine skeleton: auditMismatch effect label;
   recovery replayed from an EMPTY initial state (latent INV-1 violation).
   Fixed; recovery replays from the stored original initial state; pinned by
   a new assertion.
3. **L4-C self-comparison** — the baseline/subject wiring initially compared
   the baseline against itself (vacuous identity). Fixed: controller-phase
   outputs are compared against genuinely separate baseline outputs.
4. **L4-C vacuous DIRTY cycle** — the injected-failure target was a group
   already evicted by the rotation, and `dirtyEvictSet` over-subtracted, so
   the DIRTY/recovery cycle never executed while
   `dirtyCycleRecoveryPass=true` held vacuously. Fix: the injection target
   is drawn from the admission's ACTUAL evict set, and `overallPass` now
   REQUIRES `dirtyCycleExecuted == true`.

Principle registered: a verification suite that cannot fail is not
evidence. Vacuous-pass shapes are defects of the verification system itself
and are fixed at that level.

## 3. The two-sided proof

```text
L4-B — the resource state is REAL:
  |idleBytes − (residentBookkeepingBytes + C_model)| ≤ ε
  on 5 models × 10 transitions across load committed, release committed,
  load failure, release failure → DIRTY, recovery, multi-group continuous
  transfers, and pressure response. C_model calibrated per model class
  (+0.037 / −851.057 / −851.455 / +2.319 / +4.939 MiB) and verified
  constant across all paths.

L4-C — the computation is UNCHANGED:
  baseline MLX vs Controller + Backend generation: token sequences
  identical, logits SHA-256 identical, max_abs_diff = 0.0 — across real
  residency transitions (retention rotation A → AB → ALL) and an executed
  DIRTY/recovery cycle, on Qwen3-Coder, Nail-Qwen3.6, and Gemma4-12B.
```

Together these ground the architecture statement:

> **SimiGo does not decide what the model computes; it decides in what
> resource state the model runs.**

## 4. Closure boundaries

The Residency Runtime validation line is CLOSED at L4-C. No L4-D/L4-E
extensions are opened. Future work items — long sessions, memory-pressure
policy, budget policy, production workloads, performance, concurrency — are
ENGINEERING EXTENSIONS requiring their own gates, not continuations of this
validation.

The research line remains CLOSED / FROZEN; nothing in this gate reopens
execution-locality, Predictor, Router/Expert, or A2.0 questions.

## 5. Successor

The next engineering gate is the **Execution State Engineering Gate**
(`SIMIGO2_EXECUTION_STATE_ENGINEERING_GATE_v1.0.md`): E1 Execution
Continuity Contract → E2 pure-Swift verification → E3 MLX adapter → E4
Continuity + Residency integration → E5 end-to-end identity. Its semantic
source is the frozen Track B invariant registered in
`SIMIGO2_EXECUTION_CONTINUITY_ARCHITECTURE_v1.0.md` (E0).
