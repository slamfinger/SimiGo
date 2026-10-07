# SRS-REAL-CLOSURE-01 Execution Evidence Package — exec-005-fef0b2f

> **Outcome:** `INVALID`
> **Stop point:** post-frozen-sequence evidence audit
> **Stop code:** `TAU_N1_D_PRIME_FIELD_PLACEMENT_MISMATCH`
> **Exact execution repository commit:** `fef0b2fa5b3ac817a099bac885522fd17f4d3362`
> **Evidence interpretation:** NOT INTERPRETABLE FOR CORE CLAIM

## 1. Authorization consumed

This run consumed the one new campaign authorized by corrected Request v0.7
(`e721f7a…`, SHA256 `fa393cab…`) after Human `APPROVE T+E`. The τN1 interface
completion was canonical at `fef0b2f`, and the four campaign records 005 were
introduced by `afca0d0…`.

## 2. Step-0 and provenance result

Step 0 passed. Request v0.7, Manifest v4, Completion Record v4, completed
τN1, Acceptance Record 002, all fixture artifacts, and T-IMPL-01 sources
matched. Adapter runtime matched:

```text
e88c996b9a64df10dd03f7622ffa8757551baf352908e4d7bf8704295eaffcc7
```

`ENV-PROBE-V1` matched corrected environment identity:

```text
ad2abb6809ead5a4d198f35d6f1b8a06624a803c6fc7e161dbb06f1f0838f15a
```

EPR004 successfully enforced exact repository commit, exact cwd, D/D'
repository-contained input bindings, executable identity, argv, process facts,
and required outputs. Its overall result was false because driver returned 1.

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

ES2 produced REUSE and a continuation write, but this occurred before the
required N1 mutation and cannot count as campaign evidence.

`mutate-n1` failed with:

```text
KeyError: d_prime_seed_path
```

The completed τN1 schema placed D' binding fields at:

```text
dependencies[0].d_prime_seed_path
```

but exact runner `mutate-n1` reads:

```text
top-level d_prime_seed_path
```

The runtime τN1 copy preserved the nested placement. Therefore D' was not
created and revision-2 mapping was not written.

## 4. Evidence boundary

ESN's REUSE is invalid derived behavior because its required N1 precondition
was absent. No E1–E6 joint evidence exists. Positive REUSE is not campaign
evidence. N1 BLOCK is absent.

```text
ES1 -> IS(SRS) -> independent ES2 lawful reuse = NOT ESTABLISHED
```

This outcome is not a semantic refutation; the pre-registered counterexample
did not validly execute.

## 5. Root-cause classification

```text
primary defect =
  TAU_N1_D_PRIME_FIELD_PLACEMENT_MISMATCH;
defect_layer = residual bilateral fixture-runner τ interface mismatch;
runtime_environment_drift = NOT SUPPORTED;
EPR004 failure = NOT SUPPORTED;
semantic_refutation = NOT SUPPORTED.
```

No rerun, τN1 repair, runner repair, fixture repair, or authorization-text
repair is authorized. A new Human-authorized Request and record set is required
before any corrected campaign.
