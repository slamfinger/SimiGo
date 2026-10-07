# SRS-REAL-CLOSURE-01 — Execution Readiness Defect Register

> **Status:** REGISTERED — EXECUTION BLOCKED UNTIL DEFECTS CLOSED
> **Date:** 2026-10-07
> **Source:** Human joint audit of frozen Authorization Package v0.6 + canonical
> fixture code at `c0c9cff` (EXECUTION Authorization Request v0.2 ruled B = REVISE)
> **Audit conclusion (registered verbatim in substance):**
> authorization closure → channel closure → actual runner semantics: defects
> found at the third layer mean the three SARs must NOT be created and the
> campaign must NOT run. **Current canonical fixture is not EXECUTION-ready.**

## 1. Verdict summary

```text
EXECUTION Authorization Request v0.2
  R1 Observer field closure            FAIL (two §4.5 ruling fields missing)
  R2 Channel/Environment closure       PARTIAL
  R3 eleven artifact exact binding     PASS
Frozen §6 observer boundary           FAIL (post-exit ≠ §6.2 prebound)
Frozen §9 read-instance closure       PARTIAL (binding plan missing)
Frozen §10 joint gate readiness       FAIL

Fixture runtime correctness:
  mapping latest-entry semantics       FAIL
  env propagation                      FAIL
  tau identity substitution            FAIL
  pipe/IPC classification              FAIL
  __pycache__ suppression              FAIL-by-propagation
```

## 2. Defects by layer

### Layer 1 — authorization closure (Execution Request v0.3 scope)

```text
D-1  Observer Authorization Record lacks §4.5 fields
     observer_human_ruling_identity and
     observer_human_ruling_integrity_binding;
     the Channel Universe's human_ruling_reference does not substitute
     for them. R1 = NOT CLOSED in v0.2.

D-2  §6.2 hard-rule conflict mis-registered as a "delta":
     the post-exit observer is a fundamentally different observation
     boundary, not a §6-compliant authoritative observer with a weaker
     claim. v0.2 wrongly kept the §6/§10 formal Observer Authorization
     gate while deviating from its hard rule. Requires an explicit
     structural choice (see §3 decision D-SEC-1).

D-3  §9 read-instance immutability closure missing: no
     declared_input_binding_kind / declared_content_digest /
     read_instance_identity / read_time_content_digest /
     snapshot-or-atomicity proof / read begin-end boundaries /
     consumed-matches-declaration plan. §10 lists the read-instance
     binding plan as a pre-run joint-gate condition.

D-4  Environment closure time-inversion: v0.2 defined
     environment_measurement_evidence as a post-run evidence-package item,
     but the Universe must be closed BEFORE the run. Pre-run exact
     binding required for: environment identity, measurement method,
     measurement artifact identity/content address, integrity binding.
```

### Layer 2 — channel closure (Universe reclassification)

```text
D-5  Anonymous pipes exist but are declared IMPOSSIBLE:
     run_step() uses subprocess.run(capture_output=True), which creates
     parent↔child stdout/stderr pipes and crosses the process boundary
     with file descriptors. v0.2's "IPC and shared memory = IMPOSSIBLE"
     and "inherited file descriptors = IMPOSSIBLE" contradict the actual
     process topology. Reclassification decision required (see §3
     decision D-SEC-2: COVERED as mechanical plumbing).
```

### Layer 3 — actual runner semantics (fixture revision scope)

```text
D-6  mapping_read() returns the FIRST matching entry; IS_LAYOUT.md (frozen)
     defines resolution reads as LAST entry per dependency_id. Consequence:
     after mutate-n1 (revision 2 → D'), ES-N still resolves D/revision 1 →
     resolved = True instead of resolved = False + blockingInvalidation =
     True → the pre-registered N1 expectation (BLOCK via DP-1
     dependencyBlockingInvalidation) is NOT produced. Single-handedly
     blocks EXECUTION.

D-7  env construction without propagation: mode_driver builds env
     (SRSVAL_ADAPTER_BIN, PYTHONPATH, PYTHONDONTWRITEBYTECODE=1) but
     run_step's subprocess.run does not pass env=env. Consequences:
     __pycache__ write channel into the read-only fixture subtree stays
     open; import validate_srs fails in es2/esn; invoke_adapter's
     os.environ["SRSVAL_ADAPTER_BIN"] raises → es2/esn runtime failure.

D-8  tau srs_identity substitution unimplemented: FIXTURE_MANIFEST
     declares "driver substitutes actual srs_identity into the τ files",
     but mode_driver contains no such logic — the placeholder
     RESOLVED_FROM_IS_INDEX_BY_ES1_OUTPUT is never resolved. Independent
     blocker.

D-9  Verification-scope gap (root cause register): fixture preparation
     validated components (adapter smoke, schema self-check, py_compile)
     but never a full runner campaign. The completion record is honest
     about this and does NOT claim campaign readiness — which validates
     the standing boundary "fixture completion ≠ execution readiness".
     Remedy: extend revision verification with a sandbox campaign
     validation (temporary directory, synthetic inputs, outputs
     discarded, not evidence, not the experiment).
```

## 3. Structural decisions proposed (pending Human ruling)

```text
D-SEC-1 (§6.2 choice, for EXECUTION Request v0.3):
  Option B — the round-1 observer is classified as SUPPLEMENTAL bounded
  evidence, permanently for this campaign. The campaign makes NO
  §6-authoritative observation claim; the Observer Authorization Record's
  authorized_observation_scope is exactly "supplemental evidence
  re-derivation (post-exit)"; the §10 joint gate is satisfied by a valid
  record FOR THAT DECLARED SCOPE, with the observation-class limitation
  carried by every claim. A §6-compliant prebound tamper-resistant OIB
  remains the prerequisite for any stronger-form reuse claim (carrier
  form, P3 Reality Mapping).
  Rationale: Option A would require redesigning the instrument mid-stream
  (watcher channels, sentinel coordination) against the minimality
  doctrine and against the ACCEPTED Design v0.2 §6, which specifies the
  post-exit observer; B is consistent with the accepted design and with
  §6.2's own vocabulary (subject self-logs supplementary; here the entire
  round-1 observation is declared supplemental-class).
  CORRECTION (Human ruling on the register, 2026-10-07 — wording binding
  for EXECUTION Request v0.3): the earlier sentence "the §10 joint gate is
  satisfied by a valid record FOR THAT DECLARED SCOPE" is REJECTED. The
  strict semantics are: Observer Authorization Record 001 = valid
  SUPPLEMENTAL-observation authorization, NOT a §6 authoritative
  Observation Integrity Boundary; a post-exit observer is not a
  §6-compliant observer; the round-1 bounded claim may use supplemental
  post-exit re-derivation, and a stronger authoritative-observation claim
  is NOT AVAILABLE in round 1.

D-SEC-2 (pipe classification):
  Reclassify driver↔child capture pipes and their file descriptors as
  COVERED — declared mechanical plumbing inside the driver process tree,
  carrying no experiment semantics; stderr tails recorded in the driver
  log; observed by the coverage contract. Removing capture would destroy
  evidence, not improve it.
```

## 4. Ownership split (registered)

```text
Fixture revision (code; requires FIXTURE_PREPARATION REVISION authorization —
cannot be repaired by authorization text):
  D-6  mapping_read latest-entry semantics;
  D-7  env propagation (env=env) incl. PYTHONDONTWRITEBYTECODE=1;
  D-8  tau runtime-copy substitution in the driver (fixture τ files
       untouched; runtime copies under runs/<run_id>/);
  F-5  read-instance evidence emission in es2/esn (implements the §9 plan
       at instrument level);
  D-9  sandbox campaign validation as the revision's verification gate.

Execution Request v0.3 (document; after fixture revision lands):
  D-1  Observer Record seventeen-field closure including the two ruling
       fields;
  D-2  D-SEC-1 Option B classification (supplemental observation scope);
  D-5  D-SEC-2 pipe reclassification (COVERED);
  D-3  §9 read-instance binding plan (pre-declared input bindings, digest
       verification, boundaries);
  D-4  pre-run environment closure (declared expected environment identity
       + measurement method bound in the request; measurement artifact
       produced as the first execution step and verified against the
       declared expectation; mismatch = stop).
```

## 5. Continuing boundary

```text
No SAR may be created. No campaign may run. The fixture subtree is frozen
until a FIXTURE_PREPARATION REVISION authorization is granted. The core
claim remains NOT ESTABLISHED. The three-layer lesson is registered:
authorization closure → channel closure → actual runner semantics —
governance text cannot repair instrument semantics.
```
