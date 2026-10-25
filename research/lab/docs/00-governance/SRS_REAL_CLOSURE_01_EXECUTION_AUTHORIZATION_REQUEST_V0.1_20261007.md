# SRS-REAL-CLOSURE-01 — EXECUTION Authorization Request v0.1 (paired with scoped IS_MUTATION)

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE AUTHORIZED
> **Date:** 2026-10-07
> **Request object:** SRS-REAL-CLOSURE-01 EXECUTION Authorization Request v0.1,
> carrying TWO independent stage requests in one document:
> **Part A — EXECUTION** and **Part B — IS_MUTATION (exactly scoped)**.
> The stages remain independent (Authorization Package v0.6 §4.4); upon
> approval they become two separate Stage Authorization Records, cross-bound,
> neither implying anything beyond its declared scope.
> **Design basis:** Design v0.2 = ACCEPT; §9 requires exactly this structure
> ("an explicitly declared IS_MUTATION effect scope").
> **Execution / experiment:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED
> **Implementation / SimiGo code change / governance expansion:** NOT AUTHORIZED
> **Fixture:** COMPLETE AND FROZEN — this request does not modify any fixture
> artifact (Human audit direction: authorization_chain_history is distinct
> from execution_fixture_changed_path_set; see §4).

## 1. Authorization-chain history vs execution changed-path scope

```text
authorization_chain_history (governance commits, not experiment artifacts):
  38bda97 design v0.1 (REVISE) → 050b918 design v0.2 → 2be3477 index fix
  → f3c3e43 fixture request v0.1 (REVISE) → 7d590d7 fixture request v0.2
  → 4c3def8 FIXTURE_PREPARATION SAR 001 → d6507ff fixture delivery;

execution_fixture_changed_path_set (this request's future work):
  ONLY docs/02-evidence/srs-real-closure-01/runs/<run_id>/…
  (see Part A §A3 / Part B §B3 — the fixture subtree itself is read-only
  for execution);
```

## 2. Exact bindings

Commit identities do not replace content/integrity bindings. Any change to a
bound identity, commit, content address, integrity binding, or SHA256 voids
this Request and requires a new Request version.

```text
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

t_impl_01_components (canonical @ 07176ec):
  SRSVALInvocation.swift  git:blob:0fd65bdf40b7c9885de2ada491d66348ebfa28fa
                          sha256 6583a80444848a3b42b55ea82f9de6cc1350af6154f6f23c3c3ab61427226c75
  SRSVALDecision.swift    git:blob:cbd24721a97f3c06e012fb02649feb19c2b9cb8b
                          sha256 e219aeeadceb74a2d37cb20fdb76ee18d23ee739a743ecf6309e7384b58b15de
  SRSVALCore.swift        git:blob:9f11ef1af45be6bc9450e0fbdc0117211f99a74a
                          sha256 9725217063b9aa560752e8485dac64aae41a314c429f6b9aa1d8808a4860d56e

fixture_manifest =
  FIXTURE_MANIFEST @ d6507ff,
  git:blob:b700942737fdf89ccc102b1f1629139c378e80c7,
  sha256 8d240a70d3397b7f60923463e28af9071deddfe3063229f5a5b48f078843169e;

fixture_completion_record =
  FIXTURE_PREPARATION_COMPLETION_RECORD @ d6507ff,
  git:blob:ac279f2ef2f9c94c8e3273ab61ca11d86fc0fc4b,
  sha256 ded8aa97938f5e770d90e340aedb3305cd5ec7991d0eed196477704fc47c9ff5;

fixture_artifacts (eleven, bound transitively BY VALUE through the manifest
and restated here; execution step 0 verifies each against the manifest):
  es_runner.py            git:blob:93e99a25… sha256:68899010…
  srsval_adapter.swift    git:blob:1573ae9e… sha256:61b8ad39…
  BUILD.md                git:blob:8573c1a6… sha256:af2384b0…
  validate_srs.py         git:blob:8c8fd9e8… sha256:c1d75a75…
  IS_LAYOUT.md            git:blob:4ea38dd5… sha256:68f0590f…
  inputs/D.md             git:blob:f39361db… sha256:806fffad…
  inputs/D_prime.md       git:blob:daaeae4e… sha256:8553f524…
  tau/tau1.json           git:blob:678bdec2… sha256:bc31ce63…
  tau/tau2.json           git:blob:4b4aae59… sha256:bb8122d3…
  tau/tauN1.json          git:blob:eda97c2a… sha256:fe211518…
  observer/observer.py    git:blob:248d3003… sha256:787b70d9…
  (full sha256 values as registered in FIXTURE_MANIFEST §1; step 0
  verification is against the manifest itself, which is the binding
  registry — a mismatch stops execution before any step runs)
```

## Part A — EXECUTION stage request

### A1. Requested stage

```text
requested_stage_set (Part A) = {
  EXECUTION
}
```

Not requested: IMPLEMENTATION (complete, canonical), FIXTURE_PREPARATION
(complete, frozen), unscoped IS_MUTATION (Part B is exact), network access,
multi-backend/carrier/model runs, MCP/MemPalace/production integration,
modification of any bound artifact, Frozen Contract, or governance track.

### A2. Runtime artifact binding policy

The executable that invokes the Decision Core is built at execution time,
exactly per fixture/adapter/BUILD.md:

```text
1. export the three canonical sources from 07176ec;
2. verify SHA256 against §2 (mismatch = stop before any step);
3. swiftc same-unit compilation with the bound adapter source;
4. register the built binary's SHA256 as runtime_artifact_identity in the
   run record BEFORE first use;
5. all runs invoke only that binary.
```

No branch, working tree, floating tag, or latest pointer is referenced;
every input is pinned by §2. Exact repository commit for the run is recorded
in the run record.

### A3. Scope and writable path

```text
authorized_writable_path_set (Part A) = {
  docs/02-evidence/srs-real-closure-01/runs/<run_id>/
};
```

New subtree; one run_id per campaign. Contains: per-process event logs
(driver/es1/es2/esn), invocation_graph-es2.json, invocation_graph-esn.json,
decision outputs, observer_verdict.json, EXECUTION_EVIDENCE_PACKAGE.md.
The fixture subtree is READ-ONLY for execution.

### A4. Campaign (single, frozen sequence)

```text
execution_campaign_budget = 1 campaign:
  materialize → es1 → es2 → mutate-n1 → esn → observer → evidence package;
spawn order and exits recorded in driver-events.jsonl;
any instrument defect (hash mismatch, adapter failure, schema rejection,
unexpected crash) = INVALID stop (Design v0.2 §10); a re-run requires a
new authorization;
the frozen expected decisions (Design §5/§8/§11) are judged, never tuned:
  positive path expected REUSE / REUSE_PATH / VALID_NO_FAILURE_REMAINS;
  N1 expected BLOCK / BLOCKED_NON_RECOMPUTE_PATH via DP-1 /
  HARD_BLOCK.dependencyBlockingInvalidation(D-1) /
  VALID_HIGHER_PRECEDENCE_RESOLVED.
```

### A5. Effect set and prohibitions

```text
execution_effect_set = {
  RUN_INSTRUMENT_PROCESSES_PER_FROZEN_SEQUENCE;
  WRITE_EVENT_LOGS_INVOCATION_GRAPHS_DECISION_OUTPUTS_AND_EVIDENCE_PACKAGE
    _UNDER_RUNS_RUN_ID;
  BUILD_ADAPTER_IN_TEMPORARY_DIRECTORY_PER_BUILD_MD.
}

this EXECUTION effect set contains NO INFORMATION_SPACE_MUTATION (that
belongs exclusively to Part B);
forbidden: network; large models/corpora; multi-backend; production SimiGo;
MCP/MemPalace; modification of fixture, sources, manifest, contracts;
post-hoc reinterpretation of expected decisions; governance-text repair of
failed results (Design §10 doctrine, verbatim binding).
```

## Part B — IS_MUTATION stage request (exactly scoped)

### B1. Requested stage

```text
requested_stage_set (Part B) = {
  IS_MUTATION
}

is_mutation_scope = {
  docs/02-evidence/srs-real-closure-01/runs/<run_id>/is/
}

is_mutation_budget = 1 campaign's worth, consisting of exactly:
  1. materialize: D object write + initial resolution entry (revision 1);
  2. es1 settlement writes: SRS record object + index entry;
  3. es2 continuation-record write (on REUSE): record object + index entry;
  4. mutate-n1: D' object write (additive) + resolution-mapping entry
     (revision 2);
  nothing else; no object is ever overwritten or deleted; the SRS index is
  append-only; the original SRS continues to pin D (write-once IS property
  exercised, not violated — R1 semantics).
```

### B2. Executor binding

```text
is_mutation_executor = es_runner.py (bound, §2) modes
  materialize / es1 / es2 / mutate-n1 only;
every write follows the IS_LAYOUT.md invariants I-1..I-5;
the IS_MUTATION record binds the exact repository commit, the runner
artifact identity, the environment identity, and the observed-effect
evidence (object addresses + index entries as written).
```

## 3. Requester and destination

```text
requester_identity = SRS_REAL_CLOSURE_01_EXECUTION_REQUESTER;
requester_role = research agent acting on Human direction dated 2026-10-07;
request_destination_authority_chain =
  Runner Trust Anchor → Authorization Authority Root → Human Ruling;
destination_binding_status = PENDING_HUMAN_RULING;
stage_authorization_records = NOT_CREATED_PENDING_HUMAN_RULING
  (upon approval: EXECUTION 001 + IS_MUTATION 001, cross-bound, created as
  separate records).
```

## 4. Repository revision, environment, and budgets

```text
authorized_repository_revision = d6507ff (branch main);
environment_identity = darwin 25.6.0 arm64; Apple Swift 6.4; python3;
execution_campaign_budget = 1;
fixture_preparation_budget = 0;
implementation_work_cycle_budget = 0;
automatic_renewal = forbidden;
validity_boundary = from Human approval until evidence-package completion,
  Human withdrawal, or expiry.
```

## 5. Completion obligations

Upon campaign completion, the authorized work produces, inside
runs/<run_id>/:

```text
EXECUTION_EVIDENCE_PACKAGE.md registering:
  run_id; exact_repository_commit; runtime_artifact_identity (adapter
  binary SHA256, recorded before first use);
  step-0 verification results (eleven fixture artifacts vs manifest);
  per-process event logs; invocation graphs (es2/esn); decision outputs;
  expected-vs-actual records (frozen expectations, field by field);
  E1–E6 evidence items and N1 evidence per Design §11;
  observer_verdict.json reference;
  stop-condition outcome (PASS / INVALID / FAIL per Design §10);
  changed_path_set (runs/<run_id>/ only);
  forbidden_path_violation_count = 0; scope_compliance_verdict.

The evidence package is then delivered to canonical main and submitted for
Human audit. Judgment of the core claim belongs to the Human, per the
pre-registered bounded wording of Design §10.
```

## 6. Required Human decision

```text
APPROVE EXECUTION + IS_MUTATION (both Parts)
      create EXECUTION 001 and IS_MUTATION 001 as separate cross-bound
      Stage Authorization Records.

APPROVE Part A ONLY   create EXECUTION 001 only (experiment cannot run
                      lawfully without Part B; recorded as blocked).

REVISE REQUEST        return with registered defects.

DENY REQUEST          do not execute.
```

No stage is authorized by opening this Request. The core claim
ES₁ → IS(SRS) → independent ES₂ lawful reuse remains NOT ESTABLISHED until
the Human audits the evidence under the pre-registered bounded wording.
