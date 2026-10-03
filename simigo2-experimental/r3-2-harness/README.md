# R3-2 Harness — Single-change Boundary Study (design rev.2, RATIFIED)

Design source : `docs/00-governance/SIMIGO_LAB_R3_2_DESIGN_20261003.md` (rev.2)
Judgment rule : `docs/00-governance/SIMIGO_LAB_R3_1_JUDGMENT_SPECIFICATION_20261003.md` (rev.2)
Study         : R3 — Information Space Change and Execution-State Consistency
                Boundary Study (R3-0, GIT SEALED @1c8c463)

## What this is

A zero-dependency (Python 3 stdlib only), zero-model-inference harness that
executes the RATIFIED R3-2 design: fixed ES, controlled ΔIS per frozen
catalog, condition-level judgment per the R3-1 Spec rev.2. R3-2 judges
**condition satisfiability, not continuation behavior** (design §1 scope
statement); no model is invoked anywhere.

Medium rationale: the study is pure mechanical evaluation over file-backed
artifacts — no backend, no MLX/llama, no inference. Python stdlib was chosen
for zero-build reviewability (evidence discipline: committed, reviewable
source).

## Files

| file | role |
|---|---|
| `r32_lib.py` | fixture structures, frozen ΔIS catalog, CLASS_RULE (mechanical derivation), predictor, Spec rev.2 evaluation procedures (I/A/C + Cons with NOT-EVALUABLE propagation) |
| `r32_setup.py` | campaign setup lock (§1a): one-shot (ES,IS₀) selection + one-shot t₀ judgment; pins Cons version / judgment rule / judgment time + harness SHA-256 |
| `r32_run_cells.py` | cell runner: construction record LOCKED FIRST → fresh IS₀ copy → per-cell t₀ replication → apply ΔIS → t₁ → outcome → dual hash re-verification |
| `r32_adjudicate.py` | separate adjudication process: reads only this run's records; re-derives classes/predictions; enforces K-0 drift / instrument_doubt / unattributable / integrity rules; emits Spec §6.2 campaign four-state verdict |

## Determinism pins (design §5a)

- reference resolution = exact-key match on `index.json`; multi-candidate
  with byte-identical content collapses to one; differing content =
  ambiguous
- C-DECL check types restricted to the mechanical allowlist
  (scope-tag / validity-vs-setup-pinned-timestamp / dependency-reference)
- I-STRUCT-REMOVED (in-cell t₁ structural missing) = **I BROKEN**, not
  instrument doubt (H-C); instrument-doubt reading is setup-stage only

## Run

```bash
python3 r32_setup.py                 # prints run_uuid; exits 1 if INVALID
python3 r32_run_cells.py <run_dir>
python3 r32_adjudicate.py <run_dir>
```

Run artifacts land under `docs/02-evidence/r3-2-execution/<run_uuid>/`:
`setup_record.json`, `es-artifact.json`, `is0-canonical/`,
`cells/<cell>/{construction,outcome}.json`, `observations.jsonl` (append-only),
`run-summary.json`, `adjudication_report.json`.
