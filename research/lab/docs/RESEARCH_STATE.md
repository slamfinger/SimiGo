# SimiGo-Lab Research State

> **This file is the authoritative snapshot of the current SimiGo-Lab research state. Conversation memory must not override it.**

> **2026-10-16 navigation update:** active lines are Execution–Information cache-release validation, Persistent SRS / LOCAL-PRODUCTION-SIGNER-01, and the small-scale runtime/GUI line; priority is not inferred here. The E-I separation is a working research baseline, not proof of real-model long-term continuity. Actual MLX Smoke V6 is a bounded real-model `compute → settle` pass, not a cache-release/incremental-fork proof. Production remains unauthorized. Historical sections below retain their original authority and do not supersede this navigation note without a later Human ruling.

**Last updated**: 2026-10-25
**State layer updated**: 2026-10-25

> **2026-10-20 state-layer map:** this file is the only state authority. The other
> navigation files are pointers, not state: `NEXT_SESSION_ENTRY.md` and
> `SESSION_CONTINUITY.md` are pointer pages (full pre-2026-10-20 text is archived
> under `docs/09-archive/state-layer/`); `RESEARCH_CONTEXT_INDEX.md` routes the
> L0/L1 layers; `RESEARCH_ESTATES_SUMMARY.md` is a 2026-10-06 historical synthesis
> (explicitly not authoritative); `RESEARCH_ESTATE_COVERAGE.md` is a coverage
> ledger. Stale strata inside this file remain as written: the older
> `E4 / E5 : NOT STARTED` block is superseded by
> `### E4 Continuity + Residency Integration — Verified — 2026-09-25`.
> Sections are appended at the head and are not strictly chronological; locate by
> title, not by position.

## Current continuity — 2026-10-25 (persistent checkpoint `01b5606b`)

> **Status:** `G2 batch PASS (10-20) + core-API replay recorded` ·
> `G3-C CLOSED (10-21, with stated concurrency/settlement-ordering limits)` ·
> `G3 D1 NOT AUTHORIZED / NO-GO (entry-boundary decision Rev.5: Phase 1 is execution-infrastructure binding only)` ·
> `E/J/K/K2 settlement-contract line landed (K2 aligned native digest_equals_binding to production, 10-23)` ·
> `real MLX carrier ES→IS→fresh-ES handoff tested end-to-end (e7f63856)`.
> None of this closes the core question; no ruling below is changed by commits landing in `main`.

- **Fact (git):** research code and evidence now have a persistent, GitHub-readable
  checkpoint: `main` pushed at `01b5606b` (2026-10-25), carrying the 10-21/10-22 commits
  (`69178b7f`…`e7f63856`) and six organizing commits: `7e1c8785` (untrack transient
  selftest state; ignore `/.transfer/`, profraw), `f95bf961` (E-round settlement
  contract + provenance), `cab05e4f` (J/K/K2), `d3130321` (G3-C closure + D1 decision +
  freeze evidence), `a46f5cc8` (G3 Phase 1 implementation), `01b5606b` (G2 replay record).
- **Verification boundary (binds every commit above):** the 10-25 round was transport
  only. Python `py_compile` passed for the covered files; **no Swift build or selftest
  was re-run this round**, so these commits are not full-regression-verified by this
  round. The K/K2 runs were executed at `e7f63856` (staged = 0). G3 D1 stays NO-GO;
  production remains unauthorized; the R27 STOP stands.
- **Pointers:** `docs/06-closure/G3_C_CLOSURE_20261021.md` ·
  `docs/00-governance/SIMIGO2_G3_D1_ENTRY_BOUNDARY_DECISION_V0.1_20261021.md` ·
  `execution-information-loop/K2_EVIDENCE_REPORT_20261023.md` ·
  `docs/02-evidence/settlement-provenance-e-20261022/`.
- **Rulings recorded here (10-25):** `/private/tmp` worktrees not pruned for now;
  `materialization-hardening` worktree (single-flight test line) kept untouched.
- **Next line (product repo; NOT done in this round, and Lab commits must not be read
  as product progress):** admission increment as an independent new candidate build with
  identity record, preserving the RC1 `83a880…` candidate and its evidence; then the
  `output → native result contract → IS settlement` edge.

## Current continuity — 2026-10-20 (G1 CLOSED; 10-17/10-18 records entered)

> **Status:** `G1 CLOSED (2026-10-20 Human handoff ruling; test-only Swift oracle)` ·
> `E-I mechanism layer evidenced` · `model layer: one G2 batch PASS on three synthetic fixtures` ·
> `G2 BATCH EXECUTED ONCE — G2-A / G2-B / G2-C PASS` (P0 gate `PASS` on 2026-10-20 under the A2
> copy; batch `G2-BATCH-AUTH-20261020-01`, run `20261020T082124Z`, 9 model starts, 0 retries;
> independent review accepted at summary level, settlement invariants re-audited read-only).
> Three work records between
> 2026-10-17 and 2026-10-20 had been produced but not entered here; they are
> recorded below in the order they occurred. None of them closes the core question.
>
> **Closure:** `docs/06-closure/G1_CLOSURE_20261020.md` carries the terminal gate
> positions, the commit anchors (`7c9662bc` source, `932d8b21` evidence, `a0c019c0`
> state — local only, not pushed) and the binding citation limits. G1 closure does
> not authorize G2, does not release any freeze, and does not change the R27 STOP
> or the non-implementation status of the signer line.

**G2 design frozen (execution not authorized).** `docs/01-questions/G2_PREREGISTRATION_20261020.md`
separates three claims — old-KV inaccessibility, Information-Space restoration and
real-model continuation — and fixes three fixtures, a five-row matrix (A / B phase 1 /
B phase 2 / C-missing / C-tampered), 9 planned model starts with a hard cap of 15, and
pre-registered `PASS` / `FAIL` / `INCONCLUSIVE` rules. Status: `FROZEN —
EXECUTION NOT AUTHORIZED` (2026-10-20 ruling: D1 conditional, D2–D5 accepted). The
artifact is pinned in `docs/01-questions/G2_MODEL_BINDING_20261020.json`: 17 files,
17,197,118,924 bytes, aggregate SHA-256
`4c1bd7596b9480864ca7c5ac949fbb051c47b182b853a8219c80a171b22f6678`. Two audit facts
remain binding on any later execution: the weights pinned by `ACTUAL_MLX_SMOKE_MANIFEST_V6`
are no longer on disk (V6 stays closed and cannot be re-run), and
`MLXPrefixRecomputeExecutor.continueExecution` forwards the full prefix with `cache: nil`,
so that path is disqualified as evidence for work avoidance. P0 and the G2 batch each
need their own authorization; the batch authorization is not granted, and the A2 successor P0 needs
its own authorization as well.

**P0 executed — `FAIL` on artifact identity (1 model start, consumed).**
`docs/01-questions/G2_P0_AUTHORIZATION_20261020.md` was exercised once by
`model-level-validation/g2/p0/run_p0.py`; run `20261020T072607Z`, revision `0162465b`, clean at
build. Load, prompt render, both generations, and the cache hook all worked
(`calls = 1`, `hits = 0` on an empty store). The gate failed on one check:
`weights_digest_matches_binding`.

Root cause (read-only diagnostic, `g2/p0/20261020T072607Z-analysis/`):
`EngineModelIdentity.compute` keeps a directory entry only when
`.isRegularFile == true`, which is `false` for the symlinks that make up a Hugging Face snapshot.
On a 17-file all-symlink artifact it reads **zero bytes** and returns
the empty-string digest `e3b0c442…`. Consequently
`MLXPrefixCrossSessionCache.namespace`'s `combinedDigest` is the constant `188a16c5…` for any such
directory, and the namespace is path-scoped rather than content-scoped — contrary to
pre-registration §2.1. The same function is the model-identity input for `EngineSessionBaseline`
commits, so HF-cached models record an empty model identity there too (reported, not re-adjudicated).

Per the frozen P0 terms the design now returns for amendment: A1 accept and re-scope the namespace
claim, A2 run against a dereferenced 17.2 GB copy (same bytes ⇒ same aggregate), or A3 repair the
reader. None was adopted at that point; the G2 batch remains unauthorized and no second P0 start is
licensed by the consumed authorization. P0 `PASS` was never claimed and no G2 arm was run.

**A2 ruling — offline materialization only (2026-10-20).** The amendment was decided: A1 is not
adopted as the G2 treatment, A2 is adopted **for offline verification first**, A3 stays a separate
engineering gate (the reader is not repaired and still does not support HF symlink layouts). The
17.2 GB dereferenced copy lives at `g2/artifact-model-qwen3-coder-30b-a3b-instruct-4bit-6e302ea6`
(git-ignored). `g2/a2-materialization-20261020/MATERIALIZATION_RECORD_20261020.md` records the
result: `PASSED — OFFLINE ONLY` — 17/17 relative paths present, all regular files, zero symlinks,
byte counts and SHA-256 identical, no added/missing/renamed entry, aggregate still
`4c1bd759…`. That establishes content identity of the copy, **not** that the engine will compute a
matching identity for it, and not that it will load. The rule replica predicts weights digest
`d1f01c0c…`; the previous run shows such a prediction can still disagree with the engine.

The successor execution condition is frozen in
`docs/01-questions/G2_P0_A2_EXECUTION_CONDITION_20261020.json` (explained by
`G2_P0_SUPPLEMENT_A2_20261020.md`): same binding rows and aggregate, different `model_dir` and
`modelID`, budget 1 start / 0 retries / 2 generations. `g2/p0/run_p0.py` is now **v2** — it refuses
`--model-dir` without a frozen `--condition`, rejects any symlink in the target, and records its
own version and digest in `build.json`. The predecessor run `20261020T072607Z` stays `FAIL`,
unchanged and never backfilled. The successor P0 then ran once under
`G2-P0-A2-AUTH-20261020-01` (`docs/01-questions/G2_P0_A2_AUTHORIZATION_20261020.md`).

**P0-A2 executed — `PASS` (run `20261020T075257Z`, 1 start, 0 retries).** Source revision
`7deecd89`, runner v2 `44f88161…`, product `ec7bb6ca…`, condition `58cbf9e9…`, child exit 0,
13.247 s. All 12 probe checks and all 14 independently re-derived checks agree. The engine now
reports `weights_digest = d1f01c0c…` — matching the binding — plus `tokenizer_digest = 9bada7c8…`
and `combined_digest = bb0b2711…`, i.e. the namespace is content-scoped again instead of the
constant `188a16c5…` seen on the symlinked snapshot. Load 3.64 s, prompt 16 tokens, both
generations returned `ready`, hook `calls = 1` / `hits = 0`, store empty before and after, and this
time `launch.json` and the child exit code are present. `g2/p0/P0_A2_RESULT_20261020.md` records it.

The `PASS` opens the P0 gate only: it does not authorize the batch, does not prove G2-A (process
death, isolated store and canaries were not run), does not measure peak memory, and does not
repair `EngineModelIdentity` on symlink layouts (A3 stays a separate gate). The earlier `FAIL`
remains the record for the symlinked directory; the two runs are separate conclusions under
different execution conditions.

**G2 batch executed once — `PASS` on G2-A / G2-B / G2-C (2026-10-20).** Authorization
`G2-BATCH-AUTH-20261020-01` (`docs/01-questions/G2_BATCH_AUTHORIZATION_20261020.md`) covered one
manifest and one batch; the manifest `g2/manifest/G2_MANIFEST.json` has
`sha256 fd5146968f01a8b2…` and its token was consumed by atomic rename before the first child
launch. Run `20261020T082124Z` used the full budget — 9 model starts, 6 negative-control
processes, 15 total, 0 retries — and ended `PASS`: G2-A 15/15 rows, G2-B 17/17 rows and G2-C 7/7
rows on each of the three fixtures. Each phase-2 host restored `R1` from the carrier and emitted
`ANSWER=<secret>-<checksum>` from a 70–72-token prompt (phase-1 prompts were 437–524 tokens), so
the secret necessarily came from the restored record; the hook reported `calls = 1`, `hits = 0`,
no matched prefix, and the phase-2 store stayed empty. Phase-1 hosts exited by `SIGTERM` with
`ESRCH` on both pid and process group. C-missing refused `SETTLEMENT_MISSING` and C-tampered
refused `OBJECT_DIGEST_MISMATCH`, both before any model load and with byte-identical copies.
Result record `g2/G2_BATCH_RESULT_20261020.md`; parent re-derivation
`g2/G2_BATCH_REVERIFICATION_20261020.json` (`verdict_agrees: true`, no problems). Boundaries: peak
memory was not measured, the symlink reader (A3) is unrepaired, tokenizer digest reproducibility
across directories is reported not proven, the result covers three synthetic fixtures only, no
production authorization follows, and G1 stays `CLOSED`. A first manifest draft was superseded
before any token consumption; the final manifest records it in `freeze_history`.

Independent review accepted this result on 2026-10-20 **at summary level only** — explicitly not a
line-by-line audit of the 98 evidence files — and required that
`canonical_carrier… = false` not be waved through as "not part of the verdict". The gap was real:
`run_batch.py --verify-only` re-derives claim rows from the checks the runner itself recorded and
never reopens a carrier, so `settlement_object_id_unchanged` and `no_new_settlement_in_phase2`
were self-reported. `g2/batch/audit_settlement_invariants.py` now recomputes, directly from
carrier bytes with `mode=ro&immutable=1` and without reading `terminal.json` or
`verification.json`: the settlement object address and `byte_size`, its single-revision dependency
history (`1 → 1`), all six dependency edges (target identity, revision, reason, and target
bytes hashing back to the address), the source and S1 identities, the exact three
`execution_state` appends after settlement (one phase-1, two phase-2), the restored/advanced state
digests, both negative-control copies, the U2 answer against the settled secret, and the absence of
S1/canary in phase 2. Snapshot completeness is measured, not assumed: every audited database is
`journal_mode=delete` with no `-wal`/`-shm`/`-journal` sidecar and `integrity_check=ok`, so the
single `.sqlite` file is the complete committed state and the gate's file digest covers it. All 36
checks × 3 fixtures pass; twelve injected violations (extra settlement revision, extra `item:`
append, settlement byte flip, in-place retarget of `dependency:u1-result`) are each caught on temp
copies — the retarget fails only `dependency_edges_match_sources`, so the audit is not vacuous.
Record: `g2/G2_SETTLEMENT_INVARIANT_AUDIT_20261020.json`; the result record's §9 states this is a
post-hoc audit of stored evidence, not a re-run, and that `journal_mode=delete` is a measured fact
about these nine files, not a guarantee for other runs or backends.

**2026-10-17 — continuous-calc model-level arms.** One real local model plus the
real `carrier_loop.py`; no second model, no external runner. All ten criteria
resolved: `A/C/E/H/I = PASS-部分`, `G/B/D/F/J = PASS`. H is split into `H_Carrier`
(the invalidated set equals the independently derived expected set, linear chain and
diamond arm-4) and `H_Executor` (`NOT_INSTRUMENTED` — the carrier returns
`computed_item_ids` / `reused_item_ids`, but no real `Calculator` was wired in). The
run exits non-zero on `NOT_VERIFIED` by design, so a green exit is not available to
misread. Evidence: `execution-information-loop/experiment/continuous-calc-verification/model-level-validation/`
(`results.md`, `limitations.md` L1/L2/L2a/L2b, `handoff.md`).

**2026-10-18 — P3 selective-recompute closure and the G1/G2 boundary.**

- `REVIEW-SR-P3-20261018`: three observation sets separated
  (`expected_invalidation_set` / `observed_invalidation_set` / `observed_call_set`);
  arm-1 (no change ⇒ no recompute) and arm-4 (E sibling not invalidated, A–D
  re-settled to rev-2) both `Supported` against independently derived expectations.
- `REVIEW-SR-P3-G1G2-20261018`: formalizes **G1 = logical isolation** (different
  Execution State ⇒ different `state_scope`) versus **G2 = physical isolation** (the
  old KV cache is actually unreachable), and separates test-lifecycle
  `NOT_VERIFIED` from argument-lifecycle `PASS-部分` / `NOT_ESTABLISHED`. G2 remains
  `NOT_INSTRUMENTED`.
- `V2-P04-NOT-VALID-LM-WRONG(1)`: one external-review statement corrected; L1/L2,
  the G1 ⇒ G2 guarded dependency, and `H_Executor` at `PASS-部分 / NOT_OBSERVED`
  are retained.

**2026-10-20 — G1 Swift Reference Calculator gate (PASS).** Requested as the next
step after the Python Carrier's reuse / recompute / rollback evidence was accepted.

- **G1.0 (read-only):** the repository has **no Swift `Calculator` type** and no
  `ReferenceEchoCalculator`. The only Swift continuation entries
  (`MLXPrefixRecomputeExecutor.continueExecution(_:nextInputTokens:maxTokens:)`,
  `ExecutionContinuityCoordinator.continueExecution(_:continuation:)`) take an
  `ExecutionStateHandle` and tokens and return generated tokens; they cannot express
  the frozen `(item_id, payload, dependencies) -> {swift_value}` entry, its five
  stable error codes, or its no-side-effect rule. Wrapping them would fabricate an
  equivalence claim, so G1 builds a **test-only Swift oracle** instead.
  Record: `model-level-validation/SWIFT_CALCULATOR_BRIDGE_SPIKE.md`.
- **G1.1:** 9 success + 6 error + 1 canonicalization vectors, all PASS through the
  compiled executable; the frozen `input_sha256` / `dependencies_sha256` /
  `expected_result_sha256` are reproduced verbatim in Swift-written events; 16
  invocations produced exactly 32 events (one `started` + one terminal each).
- **G1.2:** the accepted Carrier sequence was re-run with the module-level
  `reference_calculator` replaced by the Swift adapter. Cold start A=6 B=11 C=24
  D=42 E=26; after A:3→4, `COMPUTE {A,B,C,D}` / `REUSE {E}`, values 8/13/32/52/26,
  E keeps its `object_id`, the four recomputed nodes get new content-addressed ids;
  a forced `ARITHMETIC_OVERFLOW` leaves the three Carrier tables bit-identical with
  no surviving settlement. No Python fallback exists.
- Build identity: source `7c9662bc` (clean tree), `swift build -c release`, Swift
  6.4, executable SHA-256 `a1d05d24e3f5b4e96a5af6ae478785002fce773aeaab205bf3a31bb3ce59387f`
  (190,120 bytes), identical across two independent clean builds.
  Evidence: `model-level-validation/g1-evidence/20261020/`.

**Boundary of the 2026-10-20 record.** G1 proves cross-language consistency between a
Swift implementation of the frozen contract and the Python Carrier. It does **not**
prove that any pre-existing project Calculator was executed (none was identified), it
invokes no model, and it says nothing about KV-cache release, Information-Space
restoration, or incremental model continuation. Those are G2 and are still unproven.


> **2026-10-26 治理归档**：2026-10-15 及更早的全部 continuity 层已原样移至
> `09-archive/state-layer/RESEARCH_STATE_ARCHIVED_LAYERS_20261026.md`（内容未删改）。
