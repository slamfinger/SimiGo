# SRS-REAL-CLOSURE-01 Execution Evidence Package — exec-003-9966d31

> **Outcome:** `INVALID`
> **Stop point:** post-driver provenance completeness check
> **Stop code:** `EXECUTION_PROVENANCE_RECORDER_OUTPUT_PATH_INVALID`
> **Exact execution repository commit:** `9966d311e7e52ab3f5ca828e593ea569cddb008e`
> **Evidence interpretation:** NOT INTERPRETABLE FOR CORE CLAIM

## 1. Authorization consumed

This run consumed the new campaign authorized by corrected Request v0.5
(`888a6a7…`, SHA256 `bb3b9e42…`) after Human `APPROVE A+B+C`. The four records
were introduced by `bda7829…`:

```text
EXECUTION_PROVENANCE_AND_BINDING_CLOSURE_RECORD_003
EXECUTION SAR 003
IS_MUTATION SAR 003
OBSERVER AUTHORIZATION RECORD 003
```

All records exact-bind:

```text
9966d311e7e52ab3f5ca828e593ea569cddb008e
```

The execution worktree was detached exactly at that commit.

## 2. Step-0 and provenance precheck

Step 0 passed. Request v0.5, Manifest v3, Completion Record v3, Acceptance
Record 002, eleven fixture artifacts, and T-IMPL-01 sources matched their
bindings. The adapter matched:

```text
e88c996b9a64df10dd03f7622ffa8757551baf352908e4d7bf8704295eaffcc7
```

`ENV-PROBE-V1` matched corrected environment identity:

```text
ad2abb6809ead5a4d198f35d6f1b8a06624a803c6fc7e161dbb06f1f0838f15a
```

`EXECUTION_PROVENANCE_RECORDER_003` was reconstructed from Request v0.5
Appendix A and matched:

```text
492f6f0e5c4a7207a04365c008c0f0a61b841a621e1109c9ead0a88cd6438a79
```

## 3. STOP cause

The driver was launched through EPR003. EPR003 recorded the command and
required-artifact list, and the driver returned 0. However, materialize exited 1
after only `process_start`; no IS object or mapping entry was written.

The provenance plan shows the mechanical cause:

```text
driver cwd = /Users/mr.simi/Documents/SimiGo-Lab
exact worktree = /private/tmp/srs-exec3-9966d31.ztRput
tau1.seed_path = fixture/inputs/D.md
```

Thus the repository-relative seed path resolved against the host canonical root
rather than the detached exact execution worktree.

EPR003 then attempted to write its manifest to `output_path`, but the plan had
set that value to the run directory itself rather than a JSON file. The write
raised `IsADirectoryError`, EPR003 exited 1, and
`execution_provenance.json` was not produced.

Primary stop class:

```text
EXECUTION_PROVENANCE_RECORDER_OUTPUT_PATH_INVALID
```

Secondary registered failure:

```text
CAMPAIGN_CWD_SEED_PATH_MISMATCH
```

## 4. Stages not performed

Because materialize failed before any IS write, the following did not run:

```text
es1
es2
mutate-n1
esn
observer
semantic evidence evaluation
```

The execution campaign budget and provenance closure record were consumed. The
IS mutation budget and observer budget were not consumed.

## 5. Evidence boundary

No E1–E6 evidence exists. No positive REUSE decision exists. No N1 BLOCK
decision exists. The result is not interpretable for the semantic hypothesis.

```text
ES1 -> IS(SRS) -> independent ES2 lawful reuse = NOT ESTABLISHED
```

No rerun, provenance-recorder repair, runner repair, fixture repair, or reuse of
this campaign budget is authorized.
