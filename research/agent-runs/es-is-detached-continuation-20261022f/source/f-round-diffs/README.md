# F-round-only code diffs

The task pack's acceptance standard is the **actual code difference**, and its evidence list
names "源码 diff". The round's first diff set could not meet that standard for two reasons, and
this directory is the correction:

* `git diff` covers only tracked files, so the four files this round **created** — including
  `Sources/SimiGoDetachedDriver/main.swift`, the native cross-process orchestration itself — had
  no diff at all, only a full copy in `../files/`;
* `../diff-taskrun.patch` was 0 bytes: `Sources/SimiGoTaskRun/main.swift` is untracked, so
  `git diff` for it is empty even though the round grew that file by 1 089 bytes in place. It now
  carries the hash-verified F-round-only diff `simigo2-experimental__Sources__SimiGoTaskRun__main.swift.f-round.diff`.

## How each diff was produced

For every one of the 15 files the workspace guard reports as touched, the pre-F content was
reconstructed from independent earlier-round records and **accepted only if its SHA-256 equals
the `before` hash in `../../manifests/workspace-verify.json`**, the snapshot taken before any
F-round edit. Reconstruction sources, in the order tried:

| file class | pre-F source | result |
| --- | --- | --- |
| tracked, modified by F | `git show HEAD:<path>` + E-round `diffs/tracked-changes.diff` | hash-matched for 7 files |
| tracked, modified by F, untouched by E | `git show HEAD:<path>` + D-round `diffs/worktree-vs-head.diff` | hash-matched for `Package.swift` |
| untracked, modified by F | E-round `diffs/untracked-current/` copy | hash-matched for `Sources/SimiGoTaskRun/main.swift`, `Tests/…/ProductionInputAdmissionTests.swift` |
| untracked, modified by F, no E copy | `git apply` of the E-round `diffs/new-files.diff` creation hunk | hash-matched for `Sources/SimiGo2Experimental/SettlementProvenanceVerification.swift` |
| created by F | no pre-F content exists | diff is `dev/null` → current, i.e. the whole file |

`RECONSTRUCTION_MANIFEST.json` records, per file, the expected `before` hash, the reconstruction
method, the reconstructed hash, whether the current worktree file still matches the guard's
`after` hash, and the diff file name. 11 files are hash-verified F-round-only diffs; 4 are
full-content diffs of files created this round; **0 files could not be reconstructed**.
`before/` carries the reconstructed pre-F bytes so every patch is re-derivable without rerunning
the generator. `SHA256SUMS` covers the diffs, the manifest, this README, the generator and
`before/`. The manifest also confirms that all 15 worktree files still hash-equal the guard's
`after` values, i.e. nothing in the repository moved while these diffs were being produced.

Generator: `gen_f_round_diffs.py`, kept next to this README, run in the closing pass. Nothing in
the repository's production sources was touched to produce these diffs, so the delivered binaries
are unchanged (`../../build/delivered-binary-sha256.txt`).

## What the diffs show at a glance

* `…ProductionRuntimeInformationIntegration.swift.f-round.diff` — the identity plumbing: the
  static `executionID` stays as the default logical identity, a per-instance
  `taskExecutionID` is added and every `runtime.handle / settlementCheckpoint / create / rebind`
  site is switched to it. This is the whole F-round library change; it is what lets a consumer
  own a different Execution State through the same ordinary entry.
* `…Package.swift.f-round.diff` — registration of the `SimiGoDetachedDriver` executable target.
* `…Sources__SimiGoDetachedDriver__main.swift.created.diff` — the new native driver: subprocess
  ownership, refusal to reuse a non-empty consumer state directory, `waitUntilExit()` before the
  consumer starts, lifecycle and 14 native checks.
* `…Sources__SimiGoTaskRun__main.swift.f-round.diff` — per-process execution-id plumbing, the
  counting adapter and the `--admission-probe` entry.
* `…scripts__ordinary_task__run_phase_f.py.created.diff` — the experiment runner: worlds, nonces,
  fixture copies for the negative controls, 19 native checks per positive condition, aggregation.
  The last two checks (`u1_action_recorded_as_reuse`, `same_model_snapshot_and_revision`) and the
  observed `cost` / per-item-action fields were added by the final aggregation-only pass, so this
  directory is generated from the same runner the guard just hash-verified.
* `…Tests__SimiGo2ExperimentalTests__DetachedContinuationEntryTests.swift.created.diff` and
  `…SettlementTrustFixture.swift.created.diff` — the new model-free entry tests and the trust
  fixture they need.
* the six `…Tests…f-round.diff` files and `ProductionInputAdmissionTests.swift.f-round.diff` —
  test-side repairs only (installing the trust anchor, clearing a leaked environment export,
  shipping `settlement_provenance.py` in the staged deployment bundle).

## Limits of this artifact

* The reconstruction depends on the earlier rounds' own diff records. It is checkable, not
  self-evident: the check is the hash equality against the pre-F snapshot, which is recorded per
  file in the manifest.
* A diff proves which lines changed. It does not prove the changed code is semantically correct;
  the behavioural claims stay in `../EVIDENCE_REPORT.md` with their own claim limits.
* `diff-production-integration-and-package.patch` and `diff-tests.patch` one level up remain in
  place. They are `git diff` against `HEAD` and therefore also contain earlier rounds' work on
  the same files; this directory is the F-round-only view.
