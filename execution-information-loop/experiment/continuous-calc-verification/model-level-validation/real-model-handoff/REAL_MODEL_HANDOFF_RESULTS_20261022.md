# Real-model handoff: ES → IS → fresh ES (run-20261022a)

**Status: PASS on all six required criteria.** This record covers one controlled
run. It does not, by itself, change D1 to GO, and it does not reopen any frozen
G2/G3 batch.

## What was executed

Stage B is realised by process termination, not by an in-process session-destroy
API: the production runner has no "unload model" call, so the MLX session and
its KV cache end with the process (stage A's pid is confirmed gone). The
explicitly released resource is the execution carrier, which is tombstoned
before exit.

One declaratively split task with two unsettled steps, executed by the real
`MLXPrefixRecomputeExecutor` over the cached HF snapshot
`mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`
(`6e302ea604ad9ab206367e2c501d1571023e7b6d`), referenced in place (no copy, no
re-binding of the model directory or batch identity).

| Stage | Process | What happened |
| --- | --- | --- |
| A | pid 65085, 13.82 s | Fresh ES; step 1 (U1) computed by the model; result validated against the source digest and settled into the real IS database; ES + recoverable representation persisted; carrier released; process exits |
| B | (no process) | Old ES gone: carrier tombstoned before exit, then the process ends. Only the IS file, the ES state file and the evidence remain |
| C | pid 66383, 14.45 s | New process, new coordinator, new backend, new model load (3.19 s). Same IS file and state directory opened; recovery through the production entry point; step 2 (U2) computed by the model from the settled step-1 result |
| D | verifier | 81 checks across the six criteria, decided from the physical DB, the durable state file and a model-free closure probe on a copy |

Task material (defined by the bridge, not by the model): a registration source
`TASK-SOURCE` (`checksum=7cc0`, settled deterministically, no execution state),
`TASK-U1` (model must emit `SECRET=<value>` whose sha256 equals the source's
`secret_sha256`), `TASK-U2` (model must emit `ANSWER=<secret>-<checksum>` using
the settled step-1 and source values).

## Evidence per required criterion

Artifacts: `run-20261022a/evidence/stage-a.json`, `stage-c.json`,
`verification.json`; physical DB `run-20261022a/carrier.sqlite`; durable ES
`run-20261022a/state/execution-state.json`.

### 1. Model identity — PASS

- 4 safetensors blobs, each a git-lfs content sha256:
  `25c6d0a6…`, `7007ce49…`, `a14f5bfd…`, `0ea3484a…`; real sizes
  5 321 473 414 / 5 366 644 780 / 5 276 887 419 / 1 216 066 381 bytes,
  total **17 181 071 994 bytes**.
- Tokenizer `tokenizer.json` sha256 `aeb13307…`, `tokenizer_config.json`
  `05a2d456…`, `config.json` `82005453…`, `model.safetensors.index.json`
  `c100efb4…`; content manifest over `name:blob` = `f3585350…`.
- Both stages report the identical snapshot, weight list and tokenizer. The
  verifier re-resolved the snapshot itself and matched every digest; it did not
  rely on the stage self-report.

### 2. IS persistence — PASS

- Stage C compared the physical file **before any write**: sha256
  `eee54f87…` and inode `110192522`, both identical to stage A.
- Stage C read `TASK-U1` back as the *same* settlement object
  `e1b399b2…`, still `SETTLED`, with `advancement_id =
  handoff-a-u1-handoff-20261022a`.
- `PRAGMA integrity_check = ok`; all 12 carrier objects hash to their address;
  DB bytes and inode are still unchanged since stage C (nothing rewrote the run).

### 3. ES independence — PASS

- Different PID; stage A's PID is confirmed terminated.
- Durable lineage: `created@0 → continued@1 → reattached@1 → continued@2`.
  Exactly one `created` ever: stage C **reattached** to position 1 and did not
  create an execution.
- Stage C reloaded the weights (3.19 s) into a new backend; the persisted
  representation was rebound through `restorePersistedBinding` without
  re-tokenizing the seed (`tokenize_seed_calls = 0`).
- IS authorised the recovery with `APPLIED_SWIFT` on
  `handoff-a-u1-handoff-20261022a:runtime-applied`; the new advancement's
  `prior_state_id` is exactly that state.

### 4. Completed-work reuse — PASS

- Stage A: `computed = [TASK-U1]`, `reused = [TASK-SOURCE]`.
- Stage C: `computed = [TASK-U2]`, `reused = [TASK-SOURCE, TASK-U1]`; both reuse
  actions point at the *same* settlement objects stage A wrote.
- Model calls in stage C: exactly **1** continuation, 0 seed tokenizations. The
  single call produced the new step-2 work, not a replay of step 1.
- Durable representation at position 1 is 129 tokens and its tail equals stage
  A's generated tokens; the checkpoint references stage C's confirmation state
  and result digest.

### 5. Incremental continuation — PASS

- Stage C bound a 129-token prefix (stage A's), consumed it, appended 48
  next-input tokens, generated 32 new tokens
  (`"  ANSWER=KDC4AB-7cc0\nSECRET=KDC4AB\n…"`), and advanced to position 2
  (209 prefix tokens).
- The prompt was built from values read out of IS (`KDC4AB`, `7cc0`); the
  settled `TASK-U2` answer equals `<settled U1 secret>-<settled source checksum>`.

### 6. Dependency correctness — PASS

Model-free probe on a consistent copy of the DB (`run-20261022a/probe/`):

- invalidating `TASK-U1` propagated to `TASK-U1, TASK-U2`;
- re-executing `handoff-u2` recomputed exactly `[TASK-U1, TASK-U2]` and reused
  `[TASK-SOURCE]`, state `ADVANCED`;
- the authoritative DB was verified untouched afterwards.

## Three separate propositions (not merged into the main claim)

| Proposition | Record | Boundary |
| --- | --- | --- |
| ARC reference release | `UNPROVEN_NOT_INSTRUMENTED` | no ARC retain/release instrumentation was added |
| Old carrier not reusable | `PASS_BINDING_LEVEL_TOMBSTONE_VERIFIED` | verified inside the producing process (`boundPrefix` fails, tombstone set); no durable tombstone artifact exists, because this backend is in-memory only |
| GPU memory returned to OS | `UNPROVEN_NOT_A_SUCCESS_CONDITION` | explicitly not a success condition for this run |

## What this run does and does not prove

Proven: a real model computation, once settled in IS with source, version,
dependencies, validity basis and result digest, survives the death of the
execution stage; a new process with a new coordinator and backend recovers the
settled result through the production recovery entry point, does not re-run it,
and continues the remaining work with the real model.

Not proven: **physical KV/cache reuse.** The production continuation path stores
only `tokenPrefix` and replays it (`cache: nil`), so 129 prefix tokens were
re-encoded. `verification.json` therefore records
`physical_kv_reuse: UNPROVEN_PREFIX_REPLAY` with `prefix_replay_tokens: 129`.
The proven claim is *logical* reuse of settled computation, not tensor reuse.

## Known evidence defect (recorded, not papered over)

The stage CLI used `FileManager.attributesOfItem`, which does not follow symlinks,
so `weight_files[].size_bytes` in `stage-a.json`/`stage-c.json` is the symlink
length (76), not the blob size. Weight identity is unaffected: it is the blob
file name (a git-lfs content sha256). The verifier re-resolved the snapshot and
recorded real sizes under `resolved_snapshot` plus a `metadata_notes` entry. The
source is fixed for future runs; **this run was not re-executed** to overwrite
its first result.

## Failure classification

None. No criterion failed, so no classification (database recovery / ES recovery
/ carrier isolation / result reuse / real-model continuation) was needed, and no
retry was performed. The scene is preserved: DB, state, probe copy and evidence
are all left in place.

## Reproduce

```sh
swift build --product RealModelHandoff          # in simigo2-experimental
RealModelHandoff stage-a --run-dir <new-run> --model-dir <snapshot> --lab-root <lab> --run-label <label>
# stage B is the exit of the stage-a process; do not reuse it
RealModelHandoff stage-c --run-dir <same-run> --model-dir <snapshot> --lab-root <lab> --run-label <label>
python3 verify_real_model_task_handoff.py --run-dir <same-run> --lab-root <lab>
```

Each stage refuses to overwrite existing evidence, and the verifier refuses to
overwrite an existing probe directory.

## Changed for this experiment

- `execution-information-loop/production_runtime_bridge.py`: task definition,
  model-result settlement, dependency probe, DB snapshot.
- `simigo2-experimental/Sources/SimiGo2Experimental/ProductionRuntimeInformationIntegration.swift`:
  `continueTask` and task/IS accessors.
- `simigo2-experimental/Sources/RealModelHandoff/main.swift` + `Package.swift`:
  the two-stage CLI.
- `verify_real_model_task_handoff.py`: the stage-D verifier.

No frozen G2/G3 file, manifest, fixture or batch was modified, and nothing was
pushed.
