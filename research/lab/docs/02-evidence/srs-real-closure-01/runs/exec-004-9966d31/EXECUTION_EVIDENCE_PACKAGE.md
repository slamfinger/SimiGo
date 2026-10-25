# SRS-REAL-CLOSURE-01 Execution Evidence Package — exec-004-9966d31

> **Outcome:** `INVALID`
> **Stop point:** post-frozen-sequence evidence audit
> **Stop code:** `MUTATE_N1_TAU_D_PRIME_SEED_PATH_BINDING_DEFECT`
> **Exact execution repository commit:** `9966d311e7e52ab3f5ca828e593ea569cddb008e`
> **Evidence interpretation:** NOT INTERPRETABLE FOR CORE CLAIM

## 1. Authorization consumed

This run consumed the one new campaign authorized by corrected Request v0.6
(`8704c75…`, SHA256 `a6f0e2c3…`) after Human `APPROVE A+B+C`. The four new
records were introduced by `b80c17a…`:

```text
EXECUTION_PROVENANCE_AND_BINDING_CLOSURE_RECORD_004
EXECUTION SAR 004
IS_MUTATION SAR 004
OBSERVER AUTHORIZATION RECORD 004
```

All records exact-bound:

```text
9966d311e7e52ab3f5ca828e593ea569cddb008e
```

The execution worktree was detached exactly at that commit.

## 2. Step-0 and provenance result

Step 0 passed. Request v0.6, Manifest v3, Completion Record v3, Acceptance
Record 002, all eleven fixture artifacts, and the three T-IMPL-01 sources
matched. The deterministic adapter matched:

```text
e88c996b9a64df10dd03f7622ffa8757551baf352908e4d7bf8704295eaffcc7
```

`ENV-PROBE-V1` matched corrected environment identity:

```text
ad2abb6809ead5a4d198f35d6f1b8a06624a803c6fc7e161dbb06f1f0838f15a
```

EPR004 was reconstructed from Request v0.6 Appendix A and matched:

```text
c0aff998aabada80c87d6eec1cebdf35292e16f455e72389ec36e71ea99ee262
```

EPR004 successfully enforced exact command cwd
`<worktree>/docs/02-evidence/srs-real-closure-01`, repository-contained
D/D' input bindings, executable identity, argv, process facts, and required
artifacts. Its overall result was false because the bound driver returned 1.

## 3. Frozen sequence facts

The sequence ran through:

```text
materialize = PASS
es1         = PASS
es2         = PASS / expected REUSE = actual REUSE
mutate-n1  = FAIL
esn         = RAN INVALID / expected BLOCK = actual REUSE
observer    = PASS bounded checks
```

The positive path produced a REUSE decision and continuation write. However,
this occurred before the required N1 mutation, so the campaign cannot be
accepted as valid semantic evidence.

`mutate-n1` failed with:

```text
KeyError: d_prime_seed_path
```

The bound Request v0.6 inherited τ bindings did not provide the top-level
`d_prime_seed_path` expected by exact runner `mutate-n1`. Therefore D' was not
added and the revision-2 mapping entry was not written.

ESN subsequently read the unchanged revision-1 dependency and produced REUSE
rather than the pre-registered BLOCK. That ESN result is invalid because its
required prior mutation did not occur.

## 4. Evidence boundary

The ES2 REUSE observation is not sufficient campaign evidence because the
frozen sequence did not complete. E1–E6 are not jointly established. N1 BLOCK
is absent. The observer's bounded checks passed, but bounded observation is not
authoritative semantic acceptance.

```text
ES1 -> IS(SRS) -> independent ES2 lawful reuse = NOT ESTABLISHED
```

This outcome is also not a negative refutation of the semantic hypothesis. The
hypothesis was not validly tested through the pre-registered N1 counterexample.

## 5. Root-cause classification

```text
primary defect =
  MUTATE_N1_TAU_D_PRIME_SEED_PATH_BINDING_DEFECT;
defect_layer = fixture/runner τ contract mismatch;
runtime_environment_drift = NOT SUPPORTED;
EPR004 failure = NOT SUPPORTED;
semantic_refutation = NOT SUPPORTED.
```

No rerun, runner repair, fixture repair, τ repair, or authorization-text repair
is authorized. A new Human-authorized Request and record set is required before
any corrected campaign.
