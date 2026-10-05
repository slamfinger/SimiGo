# Cross-model Formal Runner Closure

Date: 2026-10-05  
Status: `FORMAL RUNNER READY / FORMAL RUNTIME NOT AUTHORIZED`

## 1. Provenance resolution

The earlier readiness mismatch is resolved without overwriting the frozen
manifest.

```text
4838f1cb... = pilot run_matrix.py at commit e8ec3e0;
c3b8f042... = uncommitted pilot-only endpoint fallback patch;
a102a1e4... = new separate formal_runner.py.
```

The pilot runner and its uncommitted modification remain untouched as pilot
evidence. The formal line now uses a separate runner.

## 2. Formal runner

```text
docs/02-evidence/cross-model-information-matrix-20261005/formal_runner.py
SHA-256 a102a1e422e26dd87e92821daed46ff5bb85d945d4bbebc5be8171d3918f2c25
```

It is separate from `run_matrix.py`, reads only frozen cross-model inputs, and
does not import pilot `runs/`.

It supports only these static modes in this closure:

```text
--check
--plan
--render
```

It can also support `--run`, but that mode requires a separate authorization
artifact whose scope is exactly `16_formal_cross_model_cells`.

## 3. Isolation evidence

For every one of the 16 cells, the runner requires a per-cell isolation manifest
asserting:

```text
fresh_process                 = true;
reload_completed              = true;
cache_prefix_excluded         = true;
concurrent_workload_excluded  = true;
round1_residue_excluded       = true;
other_cell_state_excluded     = true;
```

It also requires a valid time window, nonempty evidence paths, and matching
`cell_id`. If any item is false or missing, the cell is `INVALID_ISOLATION` and
no request is sent.

Each runtime record stores:

```text
execution_id;
session_id;
model/endpoint identity;
sample/prompt hashes;
raw response and final-answer hashes;
request started_at / finished_at;
elapsed seconds;
endpoint probe;
effective inference config;
input lineage;
isolation evidence.
```

## 4. Formal status enum

The runner implements exactly:

```text
FORMAL;
PILOT_ONLY_NOT_FORMAL;
INVALID_ISOLATION;
RUNTIME_ERROR;
INCOMPLETE.
```

Only `FORMAL` cells may later enter J3 stability adjudication.

## 5. Static verification performed

```text
--check   = PASS;
--plan    = 16 cells generated;
--render  = four deterministic sample prompts generated.
```

No completion request was sent.

The formal manifest verifies all frozen inputs, the formal runner, the rendered
prompts, and the plan:

```text
docs/02-evidence/cross-model-information-matrix-20261005/formal-artifacts/FORMAL_RUNNER_MANIFEST.sha256
```

## 6. Post-repair readiness

| Check group | Result |
|---|---|
| 16 unique cells | PASS |
| frozen inputs/prompts/models | PASS |
| endpoint identity rule/evidence | PASS |
| runner provenance | PASS |
| formal status enum | PASS |
| formal/pilot separation | PASS |
| I1–I9 evidence implementation | PASS |
| J-material retention | PASS |
| no runtime during closure | PASS |

```text
PASS    = 19;
PARTIAL = 0;
FAIL    = 0;
CROSS_MODEL_FORMAL_RUN = READY;
RUNTIME EXECUTION      = STILL NOT AUTHORIZED.
```

## 7. Boundary

```text
Observer                 = NOT RUN;
InformationCore store    = NOT RUN;
normalization            = NOT PERFORMED;
stability scoring        = NOT PERFORMED;
vertical decomposition   = NOT PERFORMED;
mapping to 846           = NOT PERFORMED;
minimal structure claim  = NOT MADE;
irreducibility claim     = NOT MADE.
```
