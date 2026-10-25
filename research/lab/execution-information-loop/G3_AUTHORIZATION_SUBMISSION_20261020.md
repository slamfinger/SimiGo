# G3 authorization submission — 2026-10-20

This file is the external reference for the G3 acceptance package. It exists
because the report itself deliberately does not record its own hash
(`ACCEPTANCE_REPORT_20261020.md` §0); the value that identifies the current
revision of that report has to live outside the file it identifies, and be
recomputed here every time the report changes.

**This is a submission for authorization review. It does not start the formal
G3 run.** `model_execution_authorized` is `false` in the pre-registration; the
20 calculator slots in `G3_DRY_RUN_RESULT.json` remain a pre-execution design
count, `actual_model_starts` is `0`.

## 1 Package contents and current hashes

Every value below was recomputed from the bytes on disk at submission time,
not copied from an earlier summary.

| artefact | sha256 |
| --- | --- |
| `ACCEPTANCE_REPORT_20261020.md` | `ac45084bddb1da4e2bcca026bb4f6f5bfdfc1ee207785a76789c2b079c71a612` |
| `SETTLEMENT_CONTRACT_CHANGELOG.md` | `6698e06db937224e6522b8f8421251ca2253f215e17b46e193b9390062432cff` |
| `g3/G3_DRY_RUN_RESULT.json` | `96e2a30fd87035dd2a82c61bc480836d7da2f5a3528de76686ddb333d7c4f879` |
| `g3/preregistration/G3_PREREGISTRATION.json` | `30f977cc4def7d3951b78f2df209454916fca4884a19877d702180283b486972` |
| `g3/preregistration/G3_PREREGISTRATION.md` | `c670d0e297623e92358e8740ef387c6b3cdfc1b5e4bac9055ce6789047d2a789` |
| `g3/harness/g3_harness.py` | `1953dc75be4a199b1e1bf157145de020ec7ce9bf202beea2f396c12e67d464f1` |
| `g3/fixtures/g3-fixture-1.json` | `70deb456b0d8e27915f6221bb4886664884b8da86b08e50f3b38008ad46688a8` |
| `g3/fixtures/g3-fixture-2.json` | `750f502d48691eff10613819b5a4bef4f5dba110d0560eded322a291319fe1fe` |
| `g2/G2_CORE_API_REPLAY_RESULT.json` | `d119efb90f31eed4cd5c3e5498cfcd5eacd1e718607e67e9eaaa4215b6f61b6d` |

The `ACCEPTANCE_REPORT_20261020.md` value above is the revision that carries
the two bookkeeping corrections the review asked for:

- §6.3 now states the G3 dry-run total explicitly as **55 checks**
  (26 per fixture × 2 fixtures = 52 fixture-level checks, plus 3 run-level
  dependency-graph checks stored in a separate object; the two sets' names
  do not intersect);
- §0 and §9 state that the report does not embed its own hash, and that any
  external citation of that hash must be recomputed after every edit rather
  than fixed by editing the report.

Predecessor hash values are not current identifiers and must not be reused.
`c26c1e5af156f0bd87e9b94042f431f1c4ad1705686fa453bb403577cd21aa0d` identified
the report before this correction round. It is replaced by the value in the
table above.

The scope of the earlier "zero hits" search must be stated exactly. A
whole-tree search for `c26c1e5a…` returned zero matches **before** this
submission file was written; that is the result the review ruling accepted.
After this file exists, the only hit anywhere in the working tree is this
paragraph, and it is a historical-invalidation statement, not a live version
identifier. The accurate claim is therefore: there is no residual current-use
reference to the old hash, and the single present occurrence is the notice in
this authorization material that the old hash is no longer current.

## 2 What is being claimed for authorization

| item | status |
| --- | --- |
| W1–W5 | local implementation and local acceptance passed, per the report §3–§4 |
| W6 | pre-registration (revision 4) frozen as a document; dry run executed with a stub; dependency graph and logical isolation have falsifiable checks |
| G3 authorization | **requested here, not yet granted** |
| formal model run | **not started, not yet permitted**; blocked until authorization is granted, the resource-isolation condition below is actually checked at startup, and the budget/run-record plan is frozen |
| research conclusion | none. `DIVERGENCE_OBSERVED` in the dry run is a device-level observation under a stub calculator, not a measurement from a real model |

## 3 Open precondition that authorization alone does not close

`arm_isolation.model_resources` in the pre-registration is written as a hard
precondition for the formal run, and that framing is correct. But a clause
existing in a frozen plan is not the same as the gate having been checked and
passed. Before the first real arm launch, the run must additionally produce
evidence — not previously collected — that:

- the two arms run in separate processes or isolated execution units;
- each arm's KV cache, prefix cache, tokenizer handle and model runtime
  instance are not reachable from the other arm;
- read-only weight storage may be shared on disk, but no mutable buffer,
  execution state or cache that the pre-registration says must not be shared
  is in fact shared;
- the boundary actually enforced matches what revision 4 declares, and the
  check result is recorded in the run record, not only asserted in prose.

The stub dry run cannot and does not demonstrate any of this, because no model
instance existed during it (report §6.5, §9). Authorization review should treat
this as an acceptance condition on the formal run's own startup checks, not as
something already cleared by this package.

## 4 Repository state at submission

- Working tree is uncommitted on purpose; `HEAD` is
  `c0ac969427facecd35aae476a08ab3b54855671f`, unchanged from the start of the
  round. This is local implementation and local acceptance, not a merged or
  version-frozen deliverable (report §1, §2.5).
- Report §1 records "10 modified, 13 untracked" as of when the report was
  written. Adding this submission file is itself one more untracked path: the
  tree is now 10 modified, 14 untracked. Nothing tracked changed as a result.
- No code test was re-run for the two bookkeeping corrections in this
  submission; the earlier results in report §3 stand, since the corrections
  touched only prose and hash-citation bookkeeping, not code paths.
- The only working-tree occurrence of `c26c1e5a…` is the §1 invalidation
  notice in this file. No file uses it as a current identifier (§1).

## 5 Reproducing the hashes in this file

```bash
cd execution-information-loop
python3 - <<'PY'
import hashlib, pathlib
files = [
    'ACCEPTANCE_REPORT_20261020.md',
    'SETTLEMENT_CONTRACT_CHANGELOG.md',
    'experiment/continuous-calc-verification/model-level-validation/g3/G3_DRY_RUN_RESULT.json',
    'experiment/continuous-calc-verification/model-level-validation/g3/preregistration/G3_PREREGISTRATION.json',
    'experiment/continuous-calc-verification/model-level-validation/g3/preregistration/G3_PREREGISTRATION.md',
    'experiment/continuous-calc-verification/model-level-validation/g3/harness/g3_harness.py',
    'experiment/continuous-calc-verification/model-level-validation/g3/fixtures/g3-fixture-1.json',
    'experiment/continuous-calc-verification/model-level-validation/g3/fixtures/g3-fixture-2.json',
    'experiment/continuous-calc-verification/model-level-validation/g2/G2_CORE_API_REPLAY_RESULT.json',
]
for f in files:
    print(hashlib.sha256(pathlib.Path(f).read_bytes()).hexdigest(), f)
PY
```

If the report is edited again for any reason, its row in §1 is stale by
construction and must be recomputed before this submission is treated as
current.
