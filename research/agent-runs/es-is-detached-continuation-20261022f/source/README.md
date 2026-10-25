# Delivered source snapshot (F round)

`files/` holds full copies of every file this round touched, named by repository path with `/`
replaced by `__`. 15 authoritative copies plus 6 earlier-session copies kept as-is. `SHA256SUMS`
(21 entries) covers every file in this directory.

| artifact | content |
| --- | --- |
| `files/simigo2-experimental__*` | **authoritative** delivered source, taken after the last edit |
| `files/<short legacy names>` | the six copies taken earlier in the session, kept rather than deleted. They are byte-identical to the authoritative copies except `scripts__ordinary_task__run_phase_f.py`, which is stale: the aggregation note in `summarize_only()` was edited after that copy was made |
| `diff-production-integration-and-package.patch` | `git diff` against `HEAD` for `ProductionRuntimeInformationIntegration.swift` + `Package.swift`; therefore also contains earlier-round work on those files |
| `diff-taskrun.patch` | the **hash-verified F-round-only diff** of `Sources/SimiGoTaskRun/main.swift` (identical to `f-round-diffs/simigo2-experimental__Sources__SimiGoTaskRun__main.swift.f-round.diff`). Earlier in this round it was 0 bytes, because this file is untracked and `git diff` emits nothing for untracked files |
| `diff-tests.patch` | `git diff` against `HEAD` for the six tracked test suites this round had to repair |
| `f-round-diffs/` | **F-round-only code diff for all 15 touched files**: 11 hash-verified before→after diffs, 4 full-content diffs of files created this round, the reconstructed pre-F bytes in `before/`, a per-file `RECONSTRUCTION_MANIFEST.json`, the generator and `SHA256SUMS` |

## What the F round itself changed

The workspace guard compares against the snapshot taken before any F-round edit, so
`../manifests/workspace-verify.json` is the authority on which files this round touched: 15 in
total, of which

* production / experiment code (6): `Package.swift`,
  `Sources/SimiGo2Experimental/ProductionRuntimeInformationIntegration.swift`,
  `Sources/SimiGo2Experimental/SettlementProvenanceVerification.swift`,
  `Sources/SimiGoDetachedDriver/main.swift`, `Sources/SimiGoTaskRun/main.swift`,
  `scripts/ordinary_task/run_phase_f.py`;
* test code (9): the six suites in `diff-tests.patch` plus
  `SettlementTrustFixture.swift`, `ProductionInputAdmissionTests.swift` and
  `DetachedContinuationEntryTests.swift` (the F-round identity suite added last).

The three `git diff` patches are against `HEAD`, so two of them also contain work from earlier
rounds on the same files; `diff-tests.patch` is F-round-only because those six files were
unmodified in the pre-F snapshot, and `diff-taskrun.patch` is F-round-only by reconstruction
(see `f-round-diffs/README.md` for how each pre-F content was obtained and hash-checked).

Files this round created — `Sources/SimiGoDetachedDriver/main.swift`,
`scripts/ordinary_task/run_phase_f.py`,
`Tests/SimiGo2ExperimentalTests/SettlementTrustFixture.swift`,
`Tests/SimiGo2ExperimentalTests/DetachedContinuationEntryTests.swift` — have no pre-F content, so
their diff is the whole file (`f-round-diffs/*.created.diff`) and the full copy in `files/` is the
record. The same holds for the earlier-round untracked files this round edited in place
(`Sources/SimiGoTaskRun/main.swift`,
`Sources/SimiGo2Experimental/SettlementProvenanceVerification.swift`,
`Tests/SimiGo2ExperimentalTests/ProductionInputAdmissionTests.swift`), except that their pre-F
content was recovered from the E round's own records and hash-checked, so a true before→after diff
exists for them too.

Nothing was staged, committed or pushed: the guard reports `head_unchanged: true`,
`branch_unchanged: true`, `staged_diff_unchanged: true`.

## Binary identity

The evidence in `../world-a`, `../world-b`, `../controls` was produced by the binaries built
from this source:

```
322c4855ae634e62fc178c9ff6e0733a1354ea90414f32291bf7fb33d29c3ffc  simigo2-experimental/.build/debug/SimiGoTaskRun
c6b4c469feaddb31eccdba70586c48f289dab331e2107b4d81f4bdf7bea03af4  simigo2-experimental/.build/debug/SimiGoDetachedDriver
```

`../build/delivered-binary-sha256.txt` records the same pair, and both were re-verified after
the last edit of the closing pass (`build/swift-build-after-test-side-additions.log`): the
production sources in this snapshot are byte-identical to what produced those binaries.
`scripts/ordinary_task/run_phase_f.py` was edited twice in those passes, both times only in the
aggregation functions: `positive_condition` and the control builder now copy the runner's own
per-process-instance id into `processes` (plus one distinctness check), and the final pass added
the fields the per-process records already carried but the aggregator had dropped — the Runtime's
per-item action list, the observed `computed_item_ids` / `reused_item_ids`, a `cost` block with the
measured model-load and wall-clock seconds, an `argv_env_nonce_free_scope` disclosure, and two
checks derived from those observations (17 → 19 runner checks). No condition was re-executed and no
model was loaded — `summary.json` states that in its `aggregation` block, and the pass log is
`../logs/summarize-only.aggregation-refresh.log`.

`files/` and `f-round-diffs/` were both re-taken after that last edit, so the snapshot, the
diff set and `../manifests/workspace-verify.json` describe the same worktree bytes; the short
legacy copies in `files/` are still the earlier-session ones, of which
`scripts__ordinary_task__run_phase_f.py` is the stalest.
