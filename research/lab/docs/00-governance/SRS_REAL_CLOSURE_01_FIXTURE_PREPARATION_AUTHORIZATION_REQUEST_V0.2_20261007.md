# SRS-REAL-CLOSURE-01 — FIXTURE_PREPARATION Authorization Request v0.2

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE AUTHORIZED
> **Date:** 2026-10-07
> **Supersedes:** FIXTURE_PREPARATION Authorization Request v0.1 @ `f3c3e43`
> (retained as superseded lineage)
> **Review basis:** Human independent audit of v0.1 (canonical `f3c3e43`)
> ruled **B = REVISE** with exactly one required correction, applied in this
> version: **R3** — the stage completion record must be written INSIDE the
> authorized fixture subtree (`fixture/FIXTURE_PREPARATION_COMPLETION_RECORD.md`),
> closing the §5.1/§8 authorization paradox (a governance-directory completion
> record would mechanically violate the single-writable-path rule; its absence
> would violate the completion requirements). All other aspects of v0.1 were
> confirmed PASS by the same audit: stage set and exclusions, content-level
> bindings, clean diff, inherited R1/R2 boundaries, honest commit message.
> **Design basis:** SRS-REAL-CLOSURE-01 Design and Evidence Planning Package v0.2 = **ACCEPT**
> (Human ruling of 2026-10-07; v0.1 = REVISE / superseded lineage at `38bda97`; R1/R2 CLOSED)
> **Requested stage set:** `{ FIXTURE_PREPARATION }`
> **Implementation:** COMPLETE / NOT PART OF THIS REQUEST (canonical artifact `07176ec`)
> **Execution:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED
> **SimiGo code change:** NOT AUTHORIZED

## 1. Exact frozen-baseline and artifact bindings

Commit identities do not replace these content/integrity bindings. Any change
to a bound identity, commit, content address, integrity binding, or SHA256
voids this Request and requires a new Request version.

```text
frozen_predicate_design =
  SRS_VAL_01_DESIGN_V0_8 @ 1170208bee91faf34bed5eb0f3359ab6009372ba,
  git:blob:dbbeb5cb4c5aa3a78ea9bf39029a21579d2244d4,
  sha256 1f661bdabcb511f811c9b653e27f1d2242241fca76ca7f2d7614c56ad5b30fd2;

frozen_governance_package =
  SRS_VAL_01_AUTHORIZATION_PACKAGE_V0_6 @ 6089f0bf630af6e85e705fe42f8de2d2327e5200,
  git:blob:fb05a60dc950f2f592580cfbc079dff2aa0f91db,
  sha256 e16ca843999959c7583a1b34199c14ea083e456747a86bbb607c342bc493fe37;

experiment_design =
  SRS_REAL_CLOSURE_01_DESIGN_AND_EVIDENCE_PLANNING_PACKAGE_V0_2
  @ 050b918 (introduced; unchanged through 2be3477),
  git:blob:a28e8d9b95b35bb287644a0bc04175e7e800e18e,
  sha256 d43792b53ce6830cf19bac387be6bc24fd1e0205e3b96f78a695e5976917b6fe;

implementation_completion_record =
  AUTH_REQ_01_IMPLEMENTATION_COMPLETION_RECORD_T_IMPL_01 @ 07176ec,
  git:blob:0d75ef9bf7b072b91b960d733c3ba7dfcc155c66,
  sha256 4a40492e9be09b1bf3ccfc38fbe06badf50243225ccbf6af89c4e1fbbc81e5f1;

t_impl_01_artifact_components (canonical, per completion record §2):
  SRSVALInvocation.swift  git:blob:0fd65bdf40b7c9885de2ada491d66348ebfa28fa
                          sha256 6583a80444848a3b42b55ea82f9de6cc1350af6154f6f23c3c3ab61427226c75
  SRSVALDecision.swift    git:blob:cbd24721a97f3c06e012fb02649feb19c2b9cb8b
                          sha256 e219aeeadceb74a2d37cb20fdb76ee18d23ee739a743ecf6309e7384b58b15de
  SRSVALCore.swift        git:blob:9f11ef1af45be6bc9450e0fbdc0117211f99a74a
                          sha256 9725217063b9aa560752e8485dac64aae41a314c429f6b9aa1d8808a4860d56e
```

## 2. Request

This is a request for Human review and, only if approved, a separate
`FIXTURE_PREPARATION`-only Stage Authorization Record.

```text
requested_stage_set = {
  FIXTURE_PREPARATION
}
```

This request does **not** request:

```text
IMPLEMENTATION (already complete and canonical; not re-opened);
EXECUTION (no ES process may run under this authorization);
IS_MUTATION (no Information Space may be materialized under this
  authorization — the IS layout is declared, not instantiated);
RUN_VALIDATION_EXPERIMENT (the positive path and SRS-N1 remain unrun);
network access;
modification of the T-IMPL-01 canonical artifact or its completion record;
modification of any Frozen Contract, ruling, or unrelated repository path;
authorization, implication, or estimation of any later stage.
```

## 3. Requester and destination

```text
requester_identity =
  SRS_REAL_CLOSURE_01_FIXTURE_REQUESTER;

requester_role =
  research agent acting on Human direction dated 2026-10-07
  (Design v0.2 ACCEPT ruling, following Commission 2026-10-07);

request_destination_authority_chain =
  Runner Trust Anchor
    → Authorization Authority Root
    → Human Ruling;

request_destination_binding_rule =
  exact concrete anchor/root/ruling identities must be registered and
  verified before any Stage Authorization Record is created
  (precedent: AUTH_REQ_01_SAR_IMPLEMENTATION_001 §2);

destination_binding_status =
  PENDING_HUMAN_RULING;

stage_authorization_record =
  NOT_CREATED_PENDING_HUMAN_RULING.
```

## 4. Authorized repository basis

```text
authorized_repository_revision =
  f3c3e43 (v0.1 opening revision; this v0.2 revision is the correction
  lineage f3c3e43 → v0.2 introduction commit, main branch, working tree
  clean except this Request and the index pointer update);

design_ruling_lineage =
  38bda97 (design v0.1 = REVISE) → 050b918 (design v0.2)
  → 2be3477 (index correction) → f3c3e43 (this request v0.1 = REVISE);
```

## 5. Requested fixture-preparation scope

### 5.1 Authorized writable path set

```text
authorized_writable_path_set = {
  docs/02-evidence/srs-real-closure-01/fixture/
};

explicitly included within this single path set (R3):
  fixture/FIXTURE_PREPARATION_COMPLETION_RECORD.md
  — the stage completion artifact lives INSIDE the authorized fixture
  subtree. FIXTURE_PREPARATION never gains write access to
  docs/00-governance/ or any other repository path.
```

No file outside this path set may be created, modified, or deleted.
`Package.swift` is **not** in the writable set: the T-IMPL-01 adapter
compiles against the canonical artifact sources in a temporary build
directory; no repository manifest or source change occurs.

### 5.2 Fixture artifacts to be prepared (fixture manifest plan)

Per Design v0.2 §5/§9, fixture preparation produces exactly:

```text
fixture/runner/es_runner.py
  deterministic ES process runner (ES₁ / ES₂ / ES-N modes); process spawn
  and exit recording; monotonic ordering evidence; per-process append-only
  event log with write-before-return U ledger entries;

fixture/adapter/srsval_adapter.swift + fixture/adapter/BUILD.md
  thin adapter invoking the Decision Core through the canonical artifact
  components; BUILD.md pins the compile command against the three canonical
  source bindings (§1);

fixture/schema/validate_srs.py
  SRS schema validator implementing the anti-masquerade rejection rule
  (Design §2) and the canonical serialization + identity hash (D-SRS-ID-1);

fixture/is_layout/IS_LAYOUT.md
  the IS layout DECLARATION only — objects/, index.jsonl,
  current/dependencies.jsonl as the sole mutable state; declares that
  materialization happens only under the later EXECUTION authorization;

fixture/inputs/D.md, fixture/inputs/D_prime.md
  the two dependency document contents as fixture files (seeds for the
  content-addressed objects materialized at execution time; D′ ≠ D byte-wise
  by construction);

fixture/tau/tau1.json, fixture/tau/tau2.json, fixture/tau/tauN1.json
  frozen task declarations (τ1 computation+settlement; τ2 resolve+reuse
  continuation; τ2-N1 same-srs negative-control request);

fixture/observer/observer.py
  the round-1 bounded observer (Design §6): post-exit re-hashing, ledger
  re-derivation, temporal-order verification, persisted-vs-resolved byte
  equality, observer_verdict.json emission;

fixture/FIXTURE_MANIFEST.md
  produced after all other artifacts except the completion record;
  exact-binds every fixture artifact above by content address and SHA256,
  plus the computation parameters (N = 50000, procedure identity/version);

fixture/FIXTURE_PREPARATION_COMPLETION_RECORD.md
  produced last (R3): the stage completion artifact, authored inside the
  authorized fixture subtree per §8.
```

### 5.3 Allowed fixture self-verification (not experiment execution)

```text
allowed = fixture build verification: compiling the adapter against the
          three canonical T-IMPL-01 source bindings in a TEMPORARY build
          directory outside the repository, and executing the schema
          validator against SYNTHETIC schema examples contained in the
          fixture itself;
forbidden = any ES process execution; any IS materialization; any ledger,
          event-log, or verdict generation; any positive-path or N1 run.
```

### 5.4 Forbidden path set

```text
forbidden_path_set =
  every repository path outside authorized_writable_path_set, including:
  all source modules and Package.swift; all Frozen Contract documents;
  all governance rulings and authorization records; all existing evidence
  directories; the implementation completion record; docs/00-governance/
  in its entirety.
```

## 6. Requested effect set

```text
requested_effect_set = {
  CREATE_FIXTURE_FILES_UNDER_DOCS_02_EVIDENCE_SRS_REAL_CLOSURE_01_FIXTURE;
  CREATE_FIXTURE_MANIFEST_AFTER_PREPARATION;
  CREATE_FIXTURE_STAGE_COMPLETION_RECORD_WITHIN_FIXTURE_SUBTREE;
  FIXTURE_BUILD_VERIFICATION_IN_TEMPORARY_DIRECTORY.
}

forbidden_effect_set = {
  RUN_VALIDATION_EXPERIMENT;
  MATERIALIZE_INFORMATION_SPACE;
  ACCESS_NETWORK;
  MODIFY_T_IMPL_01_ARTIFACT_OR_COMPLETION_RECORD;
  MODIFY_FROZEN_CONTRACT;
  MODIFY_REPOSITORY_SOURCES_OR_MANIFEST;
  WRITE_OUTSIDE_THE_AUTHORIZED_FIXTURE_SUBTREE;
  AUTHORIZE_ANY_LATER_STAGE.
}
```

## 7. Dependency and environment policy

```text
allowed_dependency_set = {
  Python 3 standard library;
  Swift toolchain (swiftc) for the §5.3 build verification only;
};

forbidden_dependency_set = {
  third-party packages; network access; MLX/LLM stack; any SimiGo module
  beyond reading the canonical T-IMPL-01 sources for compilation;
  persistent state outside the fixture path set.
}

environment_identity =
  darwin 25.6.0 arm64; Apple Swift 6.4; python3 (system).
```

## 8. Required completion artifact (R3-closed)

No fixture artifact exists in this Request. The following values are
deliberately absent and are not placeholders for future authorization:

```text
fixture_manifest_identity =
  NOT_PRESENT_BEFORE_FIXTURE_PREPARATION_AUTHORIZATION;

fixture_manifest_content_address =
  NOT_PRESENT_BEFORE_FIXTURE_PREPARATION_AUTHORIZATION;

completion_record_identity =
  NOT_PRESENT_BEFORE_FIXTURE_PREPARATION_AUTHORIZATION;

fixture_artifact_bindings =
  NOT_PRESENT_BEFORE_FIXTURE_PREPARATION_AUTHORIZATION
  (every fixture artifact exact-bound in FIXTURE_MANIFEST.md).
```

If Human grants FIXTURE_PREPARATION only, the authorized work must produce,
**inside the authorized writable path set** (§5.1):

```text
fixture/FIXTURE_MANIFEST.md
  per-artifact content addresses and SHA256 bindings; computation
  parameters; IS layout declaration reference;

fixture/FIXTURE_PREPARATION_COMPLETION_RECORD.md
  registering:
    fixture_stage_completion_record_identity;
    fixture_stage_completion_record_content_address;
    fixture_manifest_identity + content address + integrity binding;
    per-artifact bindings (from the manifest);
    changed_path_set (all within the authorized fixture subtree);
    forbidden_path_violation_count = 0 (required);
    forbidden_dependency_violation_count = 0 (required);
    scope_compliance_verdict = PASS (required);
    completion_validity_boundary.
```

**Authorization-scope note (R3 closure):** the completion record is a
fixture-subtree artifact. Delivering it to canonical main uses the ordinary
governance commit mechanism — the authorization governs which repository
tree paths the authorized work may create or modify, and the fixture stage's
answer is: only `docs/02-evidence/srs-real-closure-01/fixture/`. No file in
`docs/00-governance/` is created, modified, or required by this stage. This
closes the paradox identified by the Human audit: under v0.1, a
governance-directory completion record would have mechanically violated
§5.1, while omitting the record would have violated §8.

The completion record may not authorize EXECUTION or IS_MUTATION. The later
EXECUTION authorization request must exact-bind the completed fixture
manifest and completion record, and declare the explicitly scoped
IS_MUTATION effect set (Design v0.2 §9), before any process runs.

## 9. Validity and budget

```text
validity_boundary =
  from Human approval, if granted, until Human withdrawal, expiration, or
  the authorized fixture completion record;

automatic_renewal = forbidden;

fixture_preparation_work_cycle_budget = 1;

execution_run_budget = 0;

is_mutation_budget = 0;

implementation_work_cycle_budget = 0.
```

## 10. Required Human decision

```text
APPROVE FIXTURE_PREPARATION ONLY
      create a FIXTURE_PREPARATION-only Stage Authorization Record
      exact-binding this Request (per the AUTH-REQ-01 SAR precedent).

REVISE REQUEST
      return with registered defects.

DENY REQUEST
      do not prepare fixtures.
```

No stage is authorized by opening this Request.
