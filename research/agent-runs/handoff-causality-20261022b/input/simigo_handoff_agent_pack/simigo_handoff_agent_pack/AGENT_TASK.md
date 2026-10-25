# SimiGo Handoff-Causality — Autonomous Implementation Task

## Mission

Implement the missing experiment code and run the real-model experiments needed to close the current SimiGo ES + PALACE Information Space research gap. **Code implementation and observed experimental evidence are the deliverables; do not stop after producing a plan or another governance document.** Run unattended through source inspection, implementation, build/tests, isolated experiments, and post-run verification. Use the current local working tree as the source of truth; the GitHub remote may not contain uncommitted native/runtime work.

Research question: can a settled, semantically sufficient result detach from the old execution context and be restored through physical Information Space in a genuinely new execution instance for incremental continuation?

Keep four conclusions separate:
- **C1 — recovery/admission authority:** the production recovery contract permits or rejects continuation under its current implementation.
- **C2 — information source:** the value actually supplied to U2 came from the corresponding IS settlement object in the tested handoff path.
- **C3 — missing-settlement behavior:** the path recomputes or rejects; record the behavior without judging it.
- **C4 — settlement/source authenticity:** byte/digest/dependency checks do not prove that the value genuinely resulted from the declared U1 computation.

## Autonomy and implementation requirement

Do not stop after discovering blockers or writing documentation. Inspect the actual local source and existing tests, implement the minimum compatible code, build, test, run each experimental condition once, inspect failures, make in-scope fixes, and rerun affected build/tests. Do not silently retry a scientific condition. If a model/tool prerequisite is unavailable, still finish source implementation and automated tests; record the experiment as `BLOCKED_NOT_RUN` with the exact blocker, never as PASS. Do not ask the user to re-approve routine implementation, test, or isolated run steps.

## Hard boundaries

1. Do not edit, rename, delete, regenerate, or write into `run-20261022a`.
2. Do not alter the frozen G2 batch, `docs/02-evidence`, existing evidence, the restored five SRS-VAL-01 DELIVERY files, frozen governance sets, or G3/D1 evidence.
3. Do not change the generic `execute_demand`/`carrier_loop` recompute semantics. Do not implement the separate “missing settlement must never recompute” policy (A2/no-recompute); this run only observes the existing behavior.
4. Do not reset, clean, stash, checkout over, rebase, commit, or push. Preserve every pre-existing tracked modification and untracked artifact. Do not stage changes.
5. Do not copy model weights into a new long-lived copy. Reuse the existing local/HF snapshot via its canonical resolved path and record the exact model/tokenizer identity.
6. Do not claim logical ES identity merely because an `executionID` string is reused. Report logical ES lineage and OS process/runtime instance separately.
7. Do not add governance reports. Store run metadata and raw results in the isolated run-output directory below.
8. Keep result labels honest: use `OBSERVED`, `BLOCKED_NOT_RUN`, `INVALID_CONDITION`, or a condition-specific outcome; never pre-label a run PASS.

## Run layout

Use a new isolated output root outside the repository where practical:
`$HOME/SimiGo-Agent-Runs/handoff-causality-20261022b/`

Create `phase1/`, `phase2a/`, `phase2b/`, `controls/`, `manifests/`, `logs/`, and `summary.json`. Do not put experimental outputs in `run-20261022a`. Copy SQLite state using SQLite's backup/snapshot mechanism (or the repository's validated snapshot utility), not a blind database-file copy when WAL may contain live changes. Each mutation operates on its own database/state copy.

Before editing, run `workspace_guard.py snapshot` (see the included tool) and record `git status --short --branch`, HEAD, staged-diff fingerprint, dirty target-file diffs, model identity, Swift version, Python version, and the existing experiment entry points. After the run, run the guard's `verify` command. If it detects protected-path changes or unrelated changes, stop further experiments and report the exact paths; do not attempt automatic restoration.

## Implementation work — do not leave as pseudocode

### 1. Production recovery entry / Phase 1 driver

Use `simigo2-experimental/Sources/RealModelHandoff/main.swift` and the actual production runtime integration/tests as found in the local tree. Reuse `recoverExecutionState` directly; do not substitute the G2 Python restore gate or a CLI-only `readSettlement` guard as proof of production recovery behavior.

Implement a small testable entry/driver that:
- generates a **new stage-A-only baseline** by running U1 and settling at position 1; `run-20261022a` is already at position 2 and must not be used as this baseline;
- creates independent A0–A4 copies from that baseline;
- invokes the production `recoverExecutionState` gate and emits structured JSON before any `continueTask` call;
- counts/records `continueExecutionCallCount`, model-generation calls, seed/text tokenization calls, `continueTask` entry, IS latest state, durable handle, checkpoint fields, database/state digests, and side effects;
- ensures the failure branches exit before `continueTask` and before model generation;
- keeps the baseline and each condition immutable after its own run and records pre/post manifests.

Conditions:
- **A0:** valid settled IS + valid durable state/checkpoint. Restore succeeds; U2 generates once.
- **A1:** delete only the settlement checkpoint. Expect `settlementCheckpointMissing`.
- **A2a:** change only checkpoint `result_digest`. Expect `settlementCheckpointMismatch(field: result_digest)`.
- **A2b:** change only checkpoint `validity_basis`. Expect `settlementCheckpointMismatch(field: validity_basis)`.
- **A3:** on a DB copy, remove the latest `:runtime-applied` index entry so the latest IS state is non-settled. Expect `informationSpaceHasNoSettledExecution`. This is the direct IS-settlement-state intervention.
- **A4:** use an empty state directory/no durable handle. Expect `durableExecutionStateMissing`.

For A1/A2a/A2b/A3/A4 require: no generation call, `continueExecutionCallCount == 0`, no `continueTask`, no task side effects, and state/DB contents unchanged by the attempted recovery. A0 must restore and run U2 exactly once. Model loading itself is not a generation call. Record each actual error and associated field; do not translate unrelated failures into the expected error.

### 2. Real handoff / Phase 2 implementation

Add an isolated experiment mode to the existing real-model handoff path. It must use the actual local interfaces and compile; avoid building a parallel fake backend. Record the path boundary explicitly: the current handoff reads settlement, interpolates U2 input, then calls `continueTask`; this does not prove that the generic execution loop independently sources U2 input from IS.

Use two independent lineage-complete worlds:
- Generate a cryptographically random 128-bit nonce at runtime per world. It may appear in U1's source payload and the legitimate U1 settlement; it must not appear in U2's base template, cold seed, command line, environment, unrelated logs/temp files, or the other world.
- Run U1, write and settle its actual result, then exit the U1 OS process. Run U2 in a separate new OS process with a clean state directory, position 0, no durable handle/checkpoint, no inherited prompt or prior prefix. Record both PIDs and prove U1 is no longer alive when U2 starts.
- W_A settles nonce A; W_B settles nonce B. U2 base-template bytes and hash must be identical across worlds and contain neither nonce. Prefer a deterministic extraction prompt/decoding configuration supported by the actual model runner. Do not silently retry formatting failures.
- For U2 record settlement object ID, result/source digests, dependencies, actual interpolated input text/hash/token IDs, output token IDs/text, actual generation-call count, `reused_item_ids`, `computed_item_ids`, bridge read sequence, ES lifecycle, DB/state manifests, model/tokenizer/weights identity, and relevant decode parameters.
- Report lifecycle as `created@0 → continued@1` for a fresh U2 instance if that is what the implementation observes; explicitly report no `reattached@1`. Do not infer ES identity from the `executionID` string alone.

Required conditions:
- **B0-A / B0-B:** each valid world returns its own nonce. U1 generation count 0 during the U2 phase; U2 generation count exactly 1. If U1 is computed during U2, mark `INVALID_CONDITION`.
- **B2:** compare the two independent worlds with byte-identical U2 templates. Output must follow the corresponding IS settlement. This is the primary C2 differential test.
- **B1-harness:** remove the U1 settlement but retain other U1 item/source records. Observe the actual handoff behavior. The known expected path is `readSettlement` refusal with U1/U2 generation 0/0 and no fallback to U1 item/source. Record rather than reinterpret this as generic loop behavior.
- **B1-loop (separate, if the existing generic loop can be exercised without semantic changes):** observe whether it recomputes or rejects, and count per-item generations. Do not modify `execute_demand` semantics to force a desired result. Keep this a separately named path.
- **B3a:** byte-tamper an object on an isolated copy. Expect a read/verification failure and no use of the tampered value; expected generation 0/0 if refusal precedes model work.
- **B3b:** create a clearly labeled *digest-valid semantic substitution* by changing value and recomputing its digest while retaining original source/dependency/validity metadata. This is intentionally NOT a lineage-authentic result. If accepted, record whether U2 follows the substituted value and mark the C4 authenticity limitation; never call this proof of true U1 provenance.
- **B3c:** mismatch a dependency pointer. Observe whether the bridge rejects/blocks after U2 generation (generation can be 0/1); capture the actual error and blocked state. Do not mislabel post-generation rejection as a pre-generation gate.
- **B4:** audit all U2-visible surfaces before U2 starts. Only U1 source payload and its corresponding IS settlement may contain the world nonce. Scan base template, cold seed, state files, env/config, command arguments, temporary files, alternate DB/cache, logs that are exposed to U2, and the other world. Use an explicit allowlist for legitimate nonce occurrences. Any other occurrence is cross-contamination and invalidates that world.

Remove the proposed B2-swap control: swapping only a settlement breaks lineage and is B3b; swapping the entire source/item is simply another world. Do not use the current KDC4AB extraction task for C2, because its prompt already contains the answer.

### 3. Authenticity/integrity distinction

Keep C4 separate from C2 in source code and summaries. A digest validates bytes against a digest; dependencies and validity metadata validate declared constraints only to the degree implemented. They do not establish that a value genuinely came from the declared U1 model computation. B3b must explicitly show this limit. Do not add execution-signature/provenance schema as part of this task; that is a separate design change.

## Automated execution and validation

- Run Swift build and focused XCTest suite after each implementation unit; run relevant Python self-tests without editing frozen harness files.
- Run the experiment conditions once each, with explicit timeouts and child-process termination/cleanup that never kills unrelated processes. Record exit code, wall time, and full logs. No silent experimental retries.
- Run Phase 1 before Phase 2. After a fix, rerun affected tests; only rerun a scientific condition if its first run is clearly marked invalid due to an implementation defect, preserve the original run, and label the replacement run distinctly.
- Use existing model cache/snapshot directly; no model-download fallback or new weights copy. Before each model run check available disk/memory and ensure the configured model path resolves to the intended local model/tokenizer.
- Keep all JSON records machine-readable and include schema/version, `run_id`, condition, `terminal_state`, implementation revision/dirty-tree fingerprint, model identity, inputs/artifact hashes, expected vs observed behavior, generation counters, errors, timestamps, and log paths.
- A condition is never PASS solely because a CLI guard printed the expected string; the instrumented production function and generation counters must support it.

## End-of-task deliverable

Do not just summarize intended work. Finish with:
1. source files actually added/modified and a terse description of the implemented path;
2. build/test results;
3. each condition's actual `OBSERVED` result, or precise `BLOCKED_NOT_RUN` / `INVALID_CONDITION` status;
4. the C1/C2/C3/C4 evidence boundary, including contradictory results;
5. paths to run manifests, hashes, raw token IDs/text, logs and database/state copies;
6. post-run workspace-guard result.

Do not commit or push. Do not modify frozen evidence to make outputs fit the hypothesis. Negative or contradictory results are valid research outcomes.
