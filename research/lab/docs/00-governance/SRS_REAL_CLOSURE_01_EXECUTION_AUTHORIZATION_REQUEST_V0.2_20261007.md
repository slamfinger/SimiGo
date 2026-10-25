# SRS-REAL-CLOSURE-01 — EXECUTION Authorization Request v0.2 (paired IS_MUTATION + Observer Authorization)

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE AUTHORIZED
> **Date:** 2026-10-07
> **Supersedes:** EXECUTION Authorization Request v0.1 @ `0c0306d` (superseded lineage)
> **Review basis:** Human independent audit of v0.1 ruled **B = REVISE** with
> three corrections, applied in this version:
> **R1** — the approval structure must include an independent
> **Observer Authorization Record 001** (Auth Package v0.6 §4.5): an
> authorization record type, NOT a third experiment stage;
> **R2** — the Channel Universe / Environment Closure must be pre-authorized
> BEFORE the run (§5.1 field set, every channel class COVERED or IMPOSSIBLE,
> unclassified forbidden), and the Observer Record must exact-bind it;
> **R3** — the eleven fixture artifact bindings must be stated in FULL
> (abbreviated values in v0.1 contradicted the request's own binding
> discipline; the manifest transitively binds the artifacts, but the
> restatement must be exact).
> Confirmed by the same audit and carried unchanged: the two-Part structure
> (EXECUTION ≠ IS_MUTATION, two separate cross-bound SARs); the
> runtime_artifact_identity = TO_BE_REGISTERED_BEFORE_FIRST_USE policy with
> STOP/INVALID on unregistered or mismatched binary digest; no fixture
> modification; no experiment redesign.
> **Design basis:** Design v0.2 = ACCEPT
> **Execution / experiment:** NOT AUTHORIZED
> **IS mutation:** NOT AUTHORIZED
> **Observer authorization:** NOT AUTHORIZED
> **Implementation / SimiGo code change / governance expansion:** NOT AUTHORIZED

## 1. Authorization-chain history vs execution changed-path scope

```text
authorization_chain_history (governance commits, not experiment artifacts):
  38bda97 design v0.1 (REVISE) → 050b918 design v0.2 → 2be3477 index fix
  → f3c3e43 fixture request v0.1 (REVISE) → 7d590d7 fixture request v0.2
  → 4c3def8 FIXTURE_PREPARATION SAR 001 → d6507ff fixture delivery
  → 0c0306d this request v0.1 (REVISE);

execution_fixture_changed_path_set (this request's future work):
  ONLY docs/02-evidence/srs-real-closure-01/runs/<run_id>/…
  (Part A §A3 / Part B §B3 — the fixture subtree is READ-ONLY for execution;
  the only execution-time writes touching the fixture tree are Python
  bytecode caches, which are eliminated as a channel class in Part C §C2);
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

fixture_artifacts (eleven, FULL bindings per R3; each is verified against
the manifest as execution step 0):
  runner/es_runner.py
    git:blob:93e99a259054697891b153034dcfdc6f219f9651
    sha256:68899010c2edafd86f41df31ba77feed68475ff9ab73e1ed57ccdcbd8abb1427
  adapter/srsval_adapter.swift
    git:blob:1573ae9eb7c7b334589a6ac901ea1889a20703a0
    sha256:61b8ad39c467ed7ff90e4d8670ea903bf7be12e20166c7cff21df4bdbf0231ac
  adapter/BUILD.md
    git:blob:8573c1a60ce304323e582db6f5073e9435303740
    sha256:af2384b0bf20ae73d8fdcee1a929a273d6e052666cc36ac2b3314ae38779d2ba
  schema/validate_srs.py
    git:blob:8c8fd9e8f87175debf77c485d7169e4e46c5e50b
    sha256:c1d75a7592652ba8eeb3831d734701b4494e6be0b14b0a6a295261fbe8822422
  is_layout/IS_LAYOUT.md
    git:blob:4ea38dd5b81bb5a99f8e82ee5379939a30008d6b
    sha256:68f0590f273f644f75c8120f5721220b027d345b9bde1f9ef079bc71a9bdf113
  inputs/D.md
    git:blob:f39361db5ac4c583287b1ae15d75e928f3bedfab
    sha256:806fffadef09d3ad491d75c6b42738e99626ee1961ed1aecf2d593aefd55980c
  inputs/D_prime.md
    git:blob:daaeae4eb3dab4ad52bba2214ea29eddeee0a2b8
    sha256:8553f52449b67de21021bb50ad6380c455bf686ee2a06cc77ed51e9f30060955
  tau/tau1.json
    git:blob:678bdec2fd2911e9df317a2a0cac16b8de1ce5d1
    sha256:bc31ce63e764aa79068fccf232767648d3b79eb1c15a57faf25dd0da465f63b0
  tau/tau2.json
    git:blob:4b4aae5986abca0505306fd28cab51eec99b95c5
    sha256:bb8122d34d3bec16494cdeeee840f45140645eb54ae232dfb47721e02531e464
  tau/tauN1.json
    git:blob:eda97c2ae1ff6e1c74e464ee6c30d36413180ea4
    sha256:fe211518e4082636b4ce3c34aabf96406308b68719ce4be47d6e3f66564fdd3f
  observer/observer.py
    git:blob:248d3003c08609bbe3823ae7c05fb5c8747e2b52
    sha256:787b70d9cc291cfab081d9313877c58e375249875857f36dd93da45a44a80aaa
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

```text
runtime_artifact_identity =
  TO_BE_REGISTERED_BEFORE_FIRST_USE
  (built at execution time exactly per fixture/adapter/BUILD.md:
   export canonical sources from 07176ec → verify SHA256 against §2 →
   swiftc same-unit compilation with the bound adapter source → register
   the built binary's SHA256 in the run record BEFORE first use);

stop_rule =
  if the runtime binary digest is not registered, or does not match the
  authorized build procedure or any §2 binding: STOP / INVALID
  (RUNTIME_ARTIFACT_UNREGISTERED_OR_DRIFTED) before any campaign step runs;

exact_repository_commit for the run is recorded in the run record;
no branch, working tree, floating tag, or latest pointer is referenced.
```

### A3. Scope and writable path

```text
authorized_writable_path_set (Part A) = {
  docs/02-evidence/srs-real-closure-01/runs/<run_id>/
};
```

Contains: per-process event logs (driver/es1/es2/esn), invocation_graph
files, decision outputs, observer_verdict.json,
EXECUTION_EVIDENCE_PACKAGE.md. The fixture subtree is READ-ONLY (bytecode
cache elimination: Part C §C2).

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

### A5. Runtime dependency sets (Auth Package §7/§10)

```text
expected_semantic_runtime_dependency_set =
  { T-IMPL-01 three canonical sources; srsval_adapter.swift; es_runner.py;
    validate_srs.py; tau1/tau2/tauN1; IS objects and index content as
    resolved at run time; BUILD.md build procedure };
authorized_mechanical_runtime_dependency_set =
  { python3 interpreter + its standard library; swiftc toolchain + Swift
    runtime libraries (build-time); macOS OS support artifacts };
dependency_closure_verdict rules (§7.1):
  observed_semantic == expected_semantic; observed_mechanical ⊆ authorized
  mechanical; undeclared_dependency_detected = false; else
  SEMANTIC_RUNTIME_DEPENDENCY_MISMATCH / MECHANICAL_RUNTIME_DEPENDENCY_
  UNAUTHORIZED / RUNTIME_DEPENDENCY_CLOSURE_INCOMPLETE → stop / INVALID.
```

### A6. Effect set and prohibitions

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

## Part C — Observer Authorization (an authorization record, NOT a third stage)

Per Auth Package v0.6 §4.5: observation is an authorized ROLE. Approval of
Parts A+B therefore also creates **OBSERVER AUTHORIZATION RECORD 001**,
binding the exact observer artifact, runtime, environment, scope, channel
universe, and coverage contract. The Observer Record authorizes observation;
it adds no experiment stage and no effect beyond reading.

### C1. Observer Authorization Record (pre-declared values, §4.5 fields)

```text
observer_authorization_identity =
  SRS_REAL_CLOSURE_01_OBSERVER_AUTHORIZATION_RECORD_001;

authorization_kind = OBSERVER_AUTHORIZATION_RECORD;

observer_identity = SRS-REAL-CLOSURE-01-ROUND1-BOUNDED-OBSERVER;

observer_artifact_content_address =
  observer/observer.py (git:blob:248d3003…, sha256:787b70d9…, §2);

observer_runtime_artifact_identity =
  python3 interpreter, environment identity below (stdlib-only execution);

observer_environment_identity =
  darwin 25.6.0 arm64; Apple Swift 6.4 (build chain); python3 (system);

observer_execution_boundary =
  POST-EXIT RE-DERIVATION WINDOW — the observer starts only after every
  subject process has exited and stops after observer_verdict.json is
  written. REGISTERED ROUND-1 DELTA (Design v0.2 §6, §13): this deviates
  from §6.2's prebound start rule; the consequence is registered, not
  hidden — the observation is evidence-separation-class, every campaign
  claim carries the round-1 bounded status, and a prebound tamper-resistant
  OIB remains the obligation for any stronger-claim execution;

observer_trust_boundary =
  no write channel to any subject process; no shared mutable state or
  writable evidence storage with subjects; artifact bound above;

authorized_observation_scope =
  read-only: runs/<run_id>/ artifacts + runs/<run_id>/is/ objects, index,
  resolution mapping;

authorized_observation_sources =
  { per-process event logs; driver-events.jsonl; IS objects/index/mapping;
    invocation graphs; decision outputs; adapter binary digest record };

approved_channel_universe_identity =
  SRS-REAL-CLOSURE-01-CHANNEL-UNIVERSE-V1 (§C2);

approved_coverage_contract_identity =
  SRS-REAL-CLOSURE-01-COVERAGE-CONTRACT-V1 (§C3);

observer_record_integrity_binding =
  registered by the governing commit introducing this record;
validity_boundary = this campaign only; use_budget = 1.
```

### C2. Channel Universe Contract (§5.1 fields; pre-authorized BEFORE the run)

```text
channel_universe_identity = SRS-REAL-CLOSURE-01-CHANNEL-UNIVERSE-V1;
environment_identity      = darwin 25.6.0 arm64; Apple Swift 6.4; python3;
environment_measurement_evidence =
  step-0 verification (eleven artifacts vs manifest; canonical source
  SHA256 vs §2) + code audit of the bound artifacts recorded in the
  evidence package;
runner_and_runtime_inventory =
  es_runner.py (driver + es1/es2/esn/mutate-n1/materialize modes);
  srsval_adapter binary (built per BUILD.md, digest registered before use);
  observer.py; python3 + stdlib; swiftc (build-time only);
unclassified_channel_set = {} (forbidden non-empty — §5.1);
universe_completeness_method =
  closed-world enumeration over (a) the code paths of the bound artifacts,
  (b) the driver spawn graph, (c) the §5.1 minimum class list below;
  same discipline as the registered E1 closed-world assumption;
  a discovered channel outside this universe does not pass by omission:
  runner stop; CHANNEL_UNIVERSE_INCOMPLETE_OR_DRIFTED;
universe_integrity_binding = registered with the governing commit;
human_ruling_reference = this Request's approval ruling;
```

Minimum class list (§5.1), each COVERED or IMPOSSIBLE with evidence:

```text
COVERED (by the authorized observer + coverage contract):
  filesystem files/directories (run dir + IS reads — re-hashed, re-derived);
  IS/SRS reads and writes (exactly Part B's four classes; invariants I-1..5);
  Information-Space mutations (same; observed-effect evidence recorded);
  process/fork/exec/child boundaries (driver spawn graph is the declared
    boundary; adapter subprocess is the declared in-process call);
  runtime loading and callbacks (stdlib imports + fixture validate_srs;
    statically compiled Swift binary; no plugins/dlopen);
  environment variables and injected resources (DECLARED, governance/
    observation control inputs only: SRSVAL_ADAPTER_BIN, PYTHONPATH
    pointing at fixture/schema, PYTHONDONTWRITEBYTECODE=1 — the bytecode-
    cache write channel into the read-only fixture subtree is eliminated
    by this declaration; none are decision inputs to the core);
  clock/entropy sources relevant to evidence (monotonic ordinals only;
    wall-clock is not a decision input — H3);
  state hashes and mutation effects (observer re-derivation + I-1..5).

IMPOSSIBLE (with closed-world code-audit + environment evidence):
  network and socket traffic; localhost and external services;
  IPC and shared memory; named pipes; memory-mapped files;
  file descriptors inherited across subject boundaries (driver spawns with
    captured pipes; no fd passing);
  signals (no handlers/sends in bound artifacts);
  device-backed state; GPU/shared-accelerator state;
  credential/helper services; launch agents or service registrations;
  filesystem watchers; kernel communication objects beyond stdlib file IO;
  persistent caches (PYTHONDONTWRITEBYTECODE=1; no other caches created).
```

### C3. Coverage Contract and Observation Integrity Record

```text
coverage_contract_identity = SRS-REAL-CLOSURE-01-COVERAGE-CONTRACT-V1;
coverage = the observer covers every COVERED class above (re-hash objects,
  re-derive ledgers, verify driver-log temporal order, verify persisted-vs-
  resolved byte equality, emit observer_verdict.json) and never writes
  subject-controlled evidence;
observation_integrity_record = produced per §6.1 at run time with fields:
  observation_source; channel_universe_identity; covered_channel_set;
  impossible_channel_set; uncovered_channel_set = {};
  observer_to_subject_separation_proof (no write channel + temporal);
  observer_artifact_integrity_binding (digest re-verified at run start);
  completeness_verdict = BOUNDED_EVIDENCE_SEPARATION (registered round-1
  delta per §C1 — not full prebound OIB; §6.2 failure vocabulary applies
  if the delta is violated: OBSERVER_NOT_AUTHORIZED / OBSERVER_ARTIFACT_
  DRIFT / OBSERVATION_COVERAGE_INCOMPLETE → stop / INVALID).
```

## 4. Requester and destination

```text
requester_identity = SRS_REAL_CLOSURE_01_EXECUTION_REQUESTER;
requester_role = research agent acting on Human direction dated 2026-10-07;
request_destination_authority_chain =
  Runner Trust Anchor → Authorization Authority Root → Human Ruling;
destination_binding_status = PENDING_HUMAN_RULING;
records_on_approval = three, cross-bound, created as separate records:
  EXECUTION SAR 001; IS_MUTATION SAR 001; OBSERVER AUTHORIZATION RECORD 001;
  none implies any scope beyond its own declared set.
```

## 5. Repository revision, environment, and budgets

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

## 6. Completion obligations

Upon campaign completion, the authorized work produces, inside
runs/<run_id>/:

```text
EXECUTION_EVIDENCE_PACKAGE.md registering:
  run_id; exact_repository_commit; runtime_artifact_identity;
  step-0 verification results (eleven artifacts vs manifest; canonical
  sources vs §2);
  per-process event logs; invocation graphs (es2/esn); decision outputs;
  expected-vs-actual records (frozen expectations, field by field);
  E1–E6 evidence items and N1 evidence per Design §11;
  observer_verdict.json; observation integrity record (§C3);
  channel-universe integrity statement (no post-hoc channel discovery,
  or CHANNEL_UNIVERSE_INCOMPLETE_OR_DRIFTED);
  stop-condition outcome (PASS / INVALID / FAIL per Design §10);
  changed_path_set (runs/<run_id>/ only);
  forbidden_path_violation_count = 0; scope_compliance_verdict.

The evidence package is then delivered to canonical main and submitted for
Human audit. Judgment of the core claim belongs to the Human, per the
pre-registered bounded wording of Design §10.
```

## 7. Required Human decision

```text
APPROVE A + B + C
      create EXECUTION SAR 001, IS_MUTATION SAR 001, and OBSERVER
      AUTHORIZATION RECORD 001 as three separate cross-bound records.

APPROVE PARTIAL     approve Part A only, or A+B without C (recorded as
                    blocked — no lawful run without the Observer Record).

REVISE REQUEST      return with registered defects.

DENY REQUEST        do not execute.
```

No stage is authorized by opening this Request. The core claim
ES₁ → IS(SRS) → independent ES₂ lawful reuse remains NOT ESTABLISHED until
the Human audits the evidence under the pre-registered bounded wording.
