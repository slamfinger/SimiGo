# Session Status — A_epistemic / A_execution

Date: 2026-10-05
Branch: `codex/execution-state-research-20260929`
Latest commit: `ef34f39`
Worktree: clean

## Completed this session

```text
design frozen (8b6b9b5)
    ↓
human authorized run
    ↓
8-cell experiment implemented and run (e191067)
    ↓
C/N replication: all 8 cells match expected signature
    ↓
primary label: ORDERED_SEPARATION_SUPPORTED
    ↓
evidence freeze + result report + rival-explanation review (ef34f39)
    ↓
HUMAN REVIEW — ACTIVE STOP
```

## Human Review framing (from the human, 2026-10-05)

Three judgments under review:

1. C4 is accepted as a **behavioral** execution-layer outcome, not a mechanistic proof.
2. Factorial separation (`E+X-`) is moderate–high confidence evidence against a single hidden mechanism.
3. E-X+ non-bypass means "no bypass observed in this construction," not "all bypass paths excluded."

The strongest untested rival explanation is **prompt metadata ordering** (E listed before X).

## Next minimal experiment (proposed, NOT authorized)

Same 8 cells. Only change: reverse prompt metadata order to `X → E`.
Everything else frozen: models C+N, same arms, same metrics, same template except ordering.

Question: does the behavioral pattern reverse with metadata order?

## Hard boundaries (unchanged)

No 846 mapping. No Observer. No InformationCore write. No minimal Information Core claim.
No A. No B retry. No D retry. No run without explicit authorization.

## Key files

- `a_e_execution/results/RESULT_REPORT.md`
- `a_e_execution/results/RIVAL_EXPLANATION_REVIEW.md`
- `a_e_execution/results/EVIDENCE_FREEZE_MANIFEST.sha256`
- `a_e_execution/runs/20261005-093200-a-e-execution/` (frozen)
- `A_EPISTEMIC_A_EXECUTION_EXPERIMENT_DESIGN.md`
