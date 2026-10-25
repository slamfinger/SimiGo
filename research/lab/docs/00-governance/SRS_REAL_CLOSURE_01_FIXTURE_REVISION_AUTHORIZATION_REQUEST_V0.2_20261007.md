# SRS-REAL-CLOSURE-01 — FIXTURE_PREPARATION REVISION Authorization Request v0.2

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE AUTHORIZED
> **Date:** 2026-10-07
> **Supersedes:** FIXTURE_PREPARATION REVISION Authorization Request v0.1
> @ `fe990f5` (superseded lineage)
> **Review basis:** Human independent audit of v0.1 ruled **B = REVISE** with
> exactly one rejected item: **F-5 as written (full sandbox campaign) carried
> complete campaign execution semantics (materialize→ES1→ES2→mutate-N1→ESN→
> observer) into FIXTURE_PREPARATION authorization — reopening the
> authorization-text→execution boundary through the validation door.**
> F-5 is replaced in this version by **INSTRUMENT SELF-VALIDATION**: six
> mechanical, non-experiment, non-campaign verifications that cover all
> Layer-3 defects without running the full ES sequence. Everything else was
> accepted and is carried unchanged: Defect Register and ownership split;
> F-1 (LAST-entry semantics), F-2 (env propagation), F-3 (runtime τ copies),
> F-4 (READ_INSTANCE emission), F-6 (manifest/completion v2); D-SEC-2
> pipe=COVERED (exact coverage definition deferred to EXECUTION Request
> v0.3: stdout/stderr pipe, FD lifetime, parent-child direction, no
> semantic payload); D-SEC-1 Option B accepted in principle with the
> strict wording correction now applied to the Defect Register
> (supplemental-observation authorization ≠ §6 authoritative OIB;
> authoritative-observation claim NOT AVAILABLE in round 1); D-4 structure
> for v0.3 (expected environment identity + measurement method exact-bound
> pre-run; measurement artifact materialized at run step 0; measured ==
> expectation else STOP/INVALID).
> **Requested stage set:** `{ FIXTURE_PREPARATION (revision cycle) }`
> **Execution / IS mutation / experiment:** NOT AUTHORIZED — no full or
> partial ES campaign sequence may run under this authorization
> **Design change:** NONE
> **SimiGo code change / Package.swift / Frozen Contracts:** NOT AUTHORIZED

## 1. Exact bindings

```text
defect_register =
  SRS_REAL_CLOSURE_01_EXECUTION_READINESS_DEFECT_REGISTER_20261007
  (D-SEC-1 wording corrected per the Human ruling on Revision Request v0.1;
  correction carried in the register itself);

frozen_predicate_design =
  SRS_VAL_01_DESIGN_V0_8 @ 1170208,
  git:blob:dbbeb5cb4c5aa3a78ea9bf39029a21579d2244d4,
  sha256 1f661bdabcb511f811c9b653e27f1d2242241fca76ca7f2d7614c56ad5b30fd2;

frozen_governance_package =
  SRS_VAL_01_AUTHORIZATION_PACKAGE_V0_6 @ 6089f0b,
  git:blob:fb05a60dc950f2f592580cfbc079dff2aa0f91db,
  sha256 e16ca843999959c7583a1b34199c14ea083e456747a86bbb607c342bc493fe37;

experiment_design =
  SRS_REAL_CLOSURE_01_DESIGN_…_V0_2 @ 050b918,
  git:blob:a28e8d9b95b35bb287644a0bc04175e7e800e18e,
  sha256 d43792b53ce6830cf19bac387be6bc24fd1e0205e3b96f78a695e5976917b6fe;

fixture_manifest (to be superseded by manifest v2 of this revision) =
  FIXTURE_MANIFEST @ d6507ff,
  git:blob:b700942737fdf89ccc102b1f1629139c378e80c7,
  sha256 8d240a70d3397b7f60923463e28af9071deddfe3063229f5a5b48f078843169e;

t_impl_01_components (canonical, unchanged, @ 07176ec):
  SRSVALInvocation.swift  git:blob:0fd65bdf40b7c9885de2ada491d66348ebfa28fa
                          sha256 6583a80444848a3b42b55ea82f9de6cc1350af6154f6f23c3c3ab61427226c75
  SRSVALDecision.swift    git:blob:cbd24721a97f3c06e012fb02649feb19c2b9cb8b
                          sha256 e219aeeadceb74a2d37cb20fdb76ee18d23ee739a743ecf6309e7384b58b15de
  SRSVALCore.swift        git:blob:9f11ef1af45be6bc9450e0fbdc0117211f99a74a
                          sha256 9725217063b9aa560752e8485dac64aae41a314c429f6b9aa1d8808a4860d56e
```

## 2. Revision scope (exact; no other change permitted)

```text
F-1  es_runner.py mapping_read(): LAST-entry-per-dependency_id resolution
     semantics, exactly as IS_LAYOUT.md (frozen) declares. Repairs D-6.

F-2  es_runner.py run_step(): pass env=env to subprocess.run so that
     SRSVAL_ADAPTER_BIN, PYTHONPATH, and PYTHONDONTWRITEBYTECODE=1 reach
     the ES subprocesses. Repairs D-7.

F-3  es_runner.py mode_driver(): after es1 completes, read the ES₁ event
     log's SRS_SETTLED_AND_PERSISTED event, extract the actual
     srs_identity, and write runtime τ copies (tau2-runtime.json,
     tauN1-runtime.json) into runs/<run_id>/ with the placeholder
     substituted; es2/esn are invoked with the runtime copies; the
     substitution is recorded as a driver event; fixture τ originals are
     never modified. Repairs D-8.

F-4  es_runner.py es2/esn: emit READ_INSTANCE evidence records into the
     process event logs — read_instance_identity, declared_content_digest,
     read_time_content_digest, read begin/end ordinal boundaries,
     consumed_content_matches_declaration verdict. Implements the §9
     read-instance plan at instrument level.

F-6  FIXTURE_MANIFEST v2 + FIXTURE_PREPARATION_COMPLETION_RECORD v2
     (inside the fixture subtree per R3 precedent): changed artifacts
     re-bound by git blob + SHA256; unchanged artifacts carried with
     original bindings; revision changelog mapping each change to its
     defect ID (D-6/D-7/D-8/D-9); violation counts and scope verdict
     fields as before.
```

## 3. F-5 (v0.2): INSTRUMENT SELF-VALIDATION — not a campaign

Replaces the rejected full sandbox campaign. Six mechanical verifications,
each exercising the repaired unit in isolation, in a temporary directory
outside the repository, with synthetic inputs, outputs discarded:

```text
SV-1  mapping semantics
      synthetic append-only mapping file: D rev1 then D' rev2;
      assert mapping_read returns D' (LAST entry), and returns D when
      only rev1 exists;

SV-2  environment propagation
      spawn a TRIVIAL PROBE CHILD ONLY (e.g. python3 -c printing the three
      variables) with env=env; assert SRSVAL_ADAPTER_BIN present,
      PYTHONPATH as expected, PYTHONDONTWRITEBYTECODE=1;

SV-3  tau substitution
      synthetic ES₁ event log containing SRS_SETTLED_AND_PERSISTED with a
      known srs_identity; run the substitution routine; assert the runtime
      τ copies carry exactly that identity and the fixture τ originals are
      byte-unchanged;

SV-4  READ_INSTANCE emission
      synthetic immutable files; run the es2/esn read-instance recorder;
      assert declared/read-time digests and ordinal boundaries are emitted
      and the verdict logic matches/mismatches as constructed;

SV-5  adapter integration
      the existing temporary-directory synthetic adapter invocation
      (smoke-positive + smoke-n1 shaped graphs) — retained unchanged;

SV-6  channel hygiene
      assert no __pycache__ (or other generated cache) appears anywhere
      under the fixture subtree after SV-1..SV-5.
```

**Boundary statement (binding):** none of SV-1..SV-6 runs the full or
partial campaign sequence (materialize→ES1→ES2→mutate-n1→ESN→observer);
no observer campaign run occurs; no IS is materialized; no evidence artifact
is produced; sandbox outputs are discarded. Fixture revision proves fixture
mechanics are mechanically correct — it does not execute the experiment.
The campaign itself remains exclusively behind EXECUTION Request v0.3 and
its three authorization records.

## 4. Out of scope (explicitly)

```text
- any change to Design v0.2, frozen contracts, T-IMPL-01 canonical
  artifact, Package.swift, or repository sources;
- any change to adapter/BUILD.md, schema/validate_srs.py, is_layout,
  inputs, tau originals, or observer.py (expected: none of these change);
- any full or partial campaign sequence under any name;
- any governance-track expansion;
- the §6.2 classification and channel-universe reclassification decisions
  (EXECUTION Request v0.3 scope, per the corrected D-SEC-1/D-SEC-2).
```

## 5. Authorized writable path set

```text
docs/02-evidence/srs-real-closure-01/fixture/
  (runner/es_runner.py; FIXTURE_MANIFEST.md;
   FIXTURE_PREPARATION_COMPLETION_RECORD.md);
plus the temporary self-validation directory outside the repository
(discarded after SV-1..SV-6).
```

## 6. Budgets and validity

```text
fixture_revision_work_cycle_budget = 1;
execution_run_budget = 0;
is_mutation_budget = 0;
implementation_work_cycle_budget = 0;
automatic_renewal = forbidden;
validity_boundary = from Human approval until completion record v2,
  withdrawal, or expiry.
```

## 7. Required Human decision

```text
APPROVE FIXTURE_PREPARATION REVISION ONLY
      create the revision SAR; apply F-1..F-4 and F-6; run SV-1..SV-6
      instrument self-validation; produce manifest v2 + completion record
      v2; push + ls-remote verify; STOP.
      EXECUTION Request v0.3 then exact-binds the revised manifest.

REVISE REQUEST     return with registered defects.
DENY REQUEST       no fixture revision (execution remains blocked).
```

No stage is authorized by opening this Request.
