# SRS-REAL-CLOSURE-01 — FIXTURE_PREPARATION REVISION Authorization Request v0.1

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE AUTHORIZED
> **Date:** 2026-10-07
> **Request object:** a bounded REVISION of the frozen fixture, repairing the
> Layer-3 runner-semantics defects D-6/D-7/D-8/D-9 registered in
> `SRS_REAL_CLOSURE_01_EXECUTION_READINESS_DEFECT_REGISTER_20261007.md`
> (Human joint audit of c0c9cff). Precedent: I-1d implementation-finding
> repair cycles; AUTH-REQ-01 SAR work-cycle discipline.
> **Requested stage set:** `{ FIXTURE_PREPARATION (revision cycle) }`
> **Execution / IS mutation / experiment:** NOT AUTHORIZED
> **Design change:** NONE (Design v0.2 untouched; §6 post-exit observer and
> §9 read-instance plan are implemented at instrument level, not redesigned)
> **SimiGo code change / Package.swift / Frozen Contracts:** NOT AUTHORIZED

## 1. Exact bindings

```text
defect_register =
  SRS_REAL_CLOSURE_01_EXECUTION_READINESS_DEFECT_REGISTER_20261007
  (introduced by the same governing commit as this Request);

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
F-1  es_runner.py mapping_read(): implement LAST-entry-per-dependency_id
     resolution semantics, exactly as IS_LAYOUT.md (frozen) declares.
     Repairs D-6. This restores the pre-registered N1 expectation:
     after mutate-n1, ES-N resolves D'/revision 2 against the SRS-pinned
     D/revision 1 → resolved=false, blockingInvalidation=true.

F-2  es_runner.py run_step(): pass env=env to subprocess.run so that
     SRSVAL_ADAPTER_BIN, PYTHONPATH, and PYTHONDONTWRITEBYTECODE=1 actually
     reach the ES subprocesses. Repairs D-7 (all three failure paths:
     bytecode-cache channel into the read-only fixture subtree; import
     validate_srs; adapter binary discovery).

F-3  es_runner.py mode_driver(): after es1 completes, read the ES₁ event
     log's SRS_SETTLED_AND_PERSISTED event, extract the actual
     srs_identity, and write runtime τ copies (tau2-runtime.json,
     tauN1-runtime.json) into runs/<run_id>/ with the placeholder
     substituted; es2/esn are invoked with the runtime copies; the
     substitution is recorded as a driver event; fixture τ originals are
     never modified. Repairs D-8.

F-4  es_runner.py es2/esn: emit READ_INSTANCE evidence records into the
     process event logs — for the SRS record and each dependency read:
     read_instance_identity, declared_content_digest (from the SRS pin /
     index), read_time_content_digest, read begin/end ordinal boundaries,
     consumed_content_matches_declaration verdict. Implements the §9
     read-instance plan at instrument level (the binding plan itself is
     declared in EXECUTION Request v0.3 — not in this revision).

F-5  Verification-scope extension (repairs D-9): after the code repairs,
     run a SANDBOX CAMPAIGN VALIDATION in a temporary directory outside
     the repository — synthetic inputs, full driver sequence
     materialize→es1→es2→mutate-n1→esn→observer, outputs discarded.
     Pass criteria (pre-registered in this Request):
       a) es2 resolves and validates; SRS-VAL = REUSE with zero typed
          failures;
       b) esn resolves D'/revision 2 (LAST-entry semantics) and produces
          BLOCK / BLOCKED_NON_RECOMPUTE_PATH via DP-1 /
          dependencyBlockingInvalidation(D-1) / VALID_HIGHER_PRECEDENCE_
          RESOLVED;
       c) ES₁ ledger = 1 U-entry; ES₂/ES-N ledgers = 0;
       d) no file is written outside the sandbox; no __pycache__ is
          created in the fixture subtree (PYTHONDONTWRITEBYTECODE
          verified effective);
       e) observer verdict all-checks-pass in the sandbox.
     This is instrument validation, NOT the experiment: sandbox artifacts
     are discarded, establish nothing, and are not evidence.

F-6  FIXTURE_MANIFEST v2 + FIXTURE_PREPARATION_COMPLETION_RECORD v2
     (both inside the fixture subtree per R3 precedent): every changed
     artifact re-bound by git blob + SHA256; unchanged artifacts carried
     with their original bindings; revision changelog mapping each change
     to its defect ID (D-6/D-7/D-8/D-9); violation counts and scope
     verdict fields as before.
```

## 3. Out of scope (explicitly)

```text
- any change to Design v0.2, the frozen contracts, T-IMPL-01 canonical
  artifact, Package.swift, or repository sources;
- any change to the §6.2 observation classification (that is EXECUTION
  Request v0.3 scope, decision D-SEC-1);
- any change to adapter/BUILD.md, schema/validate_srs.py, is_layout,
  inputs, tau originals, or observer.py beyond what the four code repairs
  strictly require (expected: none of these files change);
- any execution of the experiment outside the sandbox validation;
- any governance-track expansion.
```

## 4. Authorized writable path set

```text
docs/02-evidence/srs-real-closure-01/fixture/
  (runner/es_runner.py; FIXTURE_MANIFEST.md;
   FIXTURE_PREPARATION_COMPLETION_RECORD.md);
plus the temporary sandbox directory outside the repository (discarded).
```

## 5. Budgets and validity

```text
fixture_revision_work_cycle_budget = 1;
execution_run_budget = 0 (sandbox validation is instrument verification,
  not an execution run);
is_mutation_budget = 0;
implementation_work_cycle_budget = 0;
automatic_renewal = forbidden;
validity_boundary = from Human approval until completion record v2,
  withdrawal, or expiry.
```

## 6. Required Human decision

```text
APPROVE FIXTURE_PREPARATION REVISION ONLY
      create the revision SAR; apply F-1..F-6; sandbox-validate; produce
      manifest v2 + completion record v2; push + ls-remote verify; STOP.
      EXECUTION Request v0.3 then exact-binds the revised manifest.

REVISE REQUEST     return with registered defects.
DENY REQUEST       no fixture revision (execution remains blocked).
```

No stage is authorized by opening this Request.
