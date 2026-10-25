# G-round source changes (non-empty, reviewable)

## Tracked production files — real `git diff` saved under `diffs/`
- `execution-information-loop/production_runtime_bridge.py` — TASK-U3 constants +
  `_validate_model_value` U3 branch (`diffs/bridge.diff`, 983 lines; before sha
  d87e045b… -> after cdc8b01c…).
- `simigo2-experimental/Sources/SimiGo2Experimental/ProductionRuntimeInformationIntegration.swift`
  — resolveTaskInput dependency-closure check relaxed from closure==declared set
  equality to `Set(declared).isSubset(of: Set(resolved))` so a pure transitive
  edge (U3 declares only U2) admits against the full recursive closure
  (`diffs/swift_production.diff`, 1026 lines; before 24d3daf3… -> after af0f68c7…).

## Untracked files — reconstructed via the workspace-before snapshot
These files were already untracked before the G round (F-round additions) or are
new G-round files; `git diff` is empty for untracked paths, so the change is
proven by the `workspace_guard` before/after sha256 recorded in
`manifests/workspace-before.json` and `manifests/workspace-verify.json`.

| path | tracked | before sha (workspace-before) | after sha (current) |
|---|---|---|---|
| execution-information-loop/admission_selftest.py | untracked (extended) | 3baead5f… | e152d542… |
| simigo2-experimental/Sources/SimiGoDetachedDriver/main.swift | untracked (extended) | 2951cfce… | 41356eca… |
| simigo2-experimental/scripts/ordinary_task/run_phase_g.py | new (G harness) | ABSENT | (see artifact-manifest) |
| simigo2-experimental/Tests/SimiGo2ExperimentalTests/MultihopContinuationEntryTests.swift | new (G tests) | ABSENT | (see artifact-manifest) |

The full per-file sha256 of every run-root artifact is in
`manifests/artifact-manifest.json` (its digest is `artifact_manifest_sha256` in
`summary.json`). The G-round delta is exactly the 6 files the `workspace_guard`
reported (changed_file_count=6): files whose current sha256 differs from the
`workspace-before.json` snapshot taken before any G edit. All 6 are within the
authorized allowlist. Pre-existing F-round and unrelated working-tree changes
(including `carrier_loop.py`, which this round did NOT modify) are byte-identical
to the before-snapshot and therefore not part of this delta.
