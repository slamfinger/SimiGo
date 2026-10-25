# SimiGo G round — multi-hop cross-execution-instance continuation

**Round:** G · **Run root:** `~/SimiGo-Agent-Runs/es-is-multihop-continuation-20261022g/`
**Source head:** e7f63856 (branch main, not staged/committed/pushed)
**Terminal state:** `OBSERVED` (validate_g_evidence.py: PASS, 0 issues)

## What was proven

The F round established a single cross-process hop (`U1 settle -> old process
exits -> new process recovers U1 from IS -> compute U2`). The G round extends the
same production path to **two process boundaries with an intermediate settlement
reused by a third execution instance**:

`U1 (P1) real compute + signed settle -> P1 exits -> U2 (P2, fresh ES) reuses U1
from IS, computes + signs U2 -> P2 exits -> U3 (P3, fresh ES) recovers U2 and
recursively verifies U2->U1, computes only U3`.

### G0 — `CHAIN_3_HOPS` — OBSERVED
Three independent OS processes, three distinct execution states, one real model
generation per stage:

| stage | PID | execution_state_id | computed | reused | verified closure | gen |
|---|---|---|---|---|---|---|
| P1_U1 | 28775 | G-CHAIN-PRODUCER | TASK-U1 | TASK-SOURCE | [SOURCE] | 1 |
| P2_U2 | 28794 | G-CHAIN-CONSUMER | TASK-U2 | SOURCE, TASK-U1 | [SOURCE, U1] | 1 |
| P3_U3 | 28806 | G-CHAIN-THIRD  | TASK-U3 | SOURCE, U1, U2 | [SOURCE, U1, U2] | 1 |

- P2 **did not** regenerate U1; U1 appears in `reused_item_ids`, not `computed`.
- P3 declares **only** U2, yet its verified dependency closure is the full
  transitive set `[SOURCE, U1, U2]`; U1 and U2 are `reused`, only U3 is computed.
- Every downstream input came from the ordinary production `continueTask` ->
  `resolveTaskInput` -> bridge `resolve-model-input` -> signed-settlement
  admission. The driver/harness read **0** settlements and built **0** prompts.
- Exit order is observed: P2 started only after P1 exit was reaped; P3 started
  only after P2 exit was reaped; each state directory verified empty at start and
  entered at position 0; no prefix replay, no old-checkpoint reads.
- 31 driver checks all `true`; `verdict=OBSERVED` in `stages/chain/lifecycle.json`.

### G1 — `MISSING_TRANSITIVE_DEPENDENCY` — OBSERVED
Built from a **copy** of the G0 database (original G0 untouched). Removed only the
U1 settlement binding inside U2's dependency closure, keeping U2's own signed
object present, then attempted the ordinary U3 admission (model-free
`--admission-probe`, the same `resolveTaskInput` production gate).
- Refusal: stage `SETTLEMENT_NOT_ADMITTED`, item `TASK-U1`, reason
  `MISSING_OR_SUPERSEDED_SETTLEMENT` — the recursive closure was incomplete.
- `tokenize_text=0`, `tokenize_seed=0`, `model_generate=0`, `model_loaded=false`,
  `database_unchanged=true`, `state_unchanged=true`, no harness fallback read.
  Refusal happened **before** tokenization/generation.

### N4 — `NONCE_AND_PREFIX_ISOLATION_AUDIT` — OBSERVED
Scanned 15 files under the chain world plus the U2/U3 base templates and cold
seed. The 128-bit world nonce appears only in allow-listed signed surfaces
(carrier DB, per-stage signed evidence, state dirs, process logs). `unapproved=0`,
`cross_stage_nonce_leakage=0`, `unapproved_prefix_or_completion_copy=0`. Scan
scope + exclusions saved in `controls/n4-scan-scope.json`.

## Cost boundary (honest accounting)
- `model_generate_calls = 3`, `tokenize_text_calls = 3`, `tokenize_seed_calls = 3`,
  `model_loads = 3`, `prefix_replay_tokens = 0`. Each stage loads the model and
  performs one real generation for its own item. **Task-level reuse of U1/U2 does
  not mean zero FLOPs or zero prefill**; the reuse claim is that a completed,
  signed settlement is not re-derived, not that no model work happened.

## Model / identity
- mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit @ snapshot 6e302ea6…; identical
  revision and weights manifest across all three stages (`model_identity_sha256`
  recorded in `summary.json.identity`). No weight copy.

## Claim scope C1–C4 (separated)
- **C1 admission:** multi-hop recovery runs through the ordinary production entry
  in fresh execution states; the transitive-closure refusal is pre-tokenize.
- **C2 IS as source:** each downstream input is materialized from the verified IS
  settlement; no harness pre-read / template concat.
- **C3 recompute policy:** unchanged; a stage reuses a verified settlement or
  refuses. No new no-recompute/anti-rollback was introduced.
- **C4 trusted settlement:** signed provenance is a prerequisite; a valid
  signature is required for admission but does not prove semantic correctness;
  no store-wide anti-rollback was added this round.

## What is NOT claimed
- A single successful G0 chain supports multi-hop feasibility for this fixture and
  entry; it does not prove universal validity across models/backends/graphs.
- Old-context release is evidenced only by full OS process exit + empty downstream
  state directory (`PROCESS_ADDRESS_SPACE_DESTROYED_ONLY`), not an observed internal
  MLX/KV deinit.

## Guards
- workspace_guard: `PASS` (changed_file_count=6, all authorized; 0 issues).
- artifact_guard: `PASS` (0 issues; F round and A–E, run-20261022a, G2 frozen
  batch, docs/02-evidence, docs/00-governance all byte-identical before/after).

## Native code changed (non-empty, reviewable)
See `report/SOURCE_DIFF_SUMMARY.md` and `diffs/`. Production path changes:
`production_runtime_bridge.py` (TASK-U3 validation),
`ProductionRuntimeInformationIntegration.swift` (recursive-closure admission),
`SimiGoDetachedDriver/main.swift` (third process/ES + closure checks),
`admission_selftest.py` (multihop fixtures), plus `run_phase_g.py` (three-process
harness) and `MultihopContinuationEntryTests.swift` (4 model-free Swift tests, all
pass). No carrier_loop recompute semantics changed; nothing committed.
