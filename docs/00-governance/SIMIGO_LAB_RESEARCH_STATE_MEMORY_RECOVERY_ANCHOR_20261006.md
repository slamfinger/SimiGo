# SimiGo-Lab Research State / Memory Recovery Anchor

> **Status:** RECOVERY ANCHOR
> **Recovery baseline:** GitHub `slamfinger/SimiGo-Lab@main` = `0508e26`
> **Research-state content revision:** `bcc6b81`
> **Metadata correction:** this commit; verify current `main` dynamically with `git rev-parse HEAD`
> **Post-closure authorization:** Human later opened `SRS-SEM-01`; verify current state dynamically. See `SRS-SEM-01 Design v0.1`.
> **Date:** 2026-10-06
> **Canonical source:** GitHub `slamfinger/SimiGo-Lab@main`
> **Purpose:** restore research state and research-memory entry without relying on chat memory, deleted branches, or superseded handoff paragraphs.
> **Boundary:** recovery only. This anchor does not start `SRS-SEM-01`, create a new mission/task tree, authorize implementation, fixture creation, experiment, IS mutation, or code change.

> **Current recovery override — 2026-10-07:** EXEC-005 schema authority audit
> at 9616133 supersedes generic INVALID-evidence state. Root cause is shared/
> bilateral `TAU_N1_RUNNER_SCHEMA_AUTHORITY_ABSENCE`; no authoritative τN1
> schema existed. The Research Focus Reset
> supersedes the older “SRS-VAL design is active” orientation. Read “Current recovery
> status — 2026-10-07” immediately below before using any later section.

## 0. Current recovery status — 2026-10-07 (updated after EXEC-005 schema authority audit)

```text
Governance track:
  maintenance-only. Completed this line (all canonical on main):
    T-IMPL-01 implemented (07176ec, completion record registered);
    SRS-REAL-CLOSURE-01 Design v0.2 ACCEPT;
    FIXTURE_PREPARATION Request v0.2 ACCEPT → SAR 001 (4c3def8) →
    fixture complete (d6507ff, manifest v1);
    EXECUTION Request v0.2 ruled B=REVISE (three-layer audit: authorization
    closure / channel closure / runner semantics) → Defect Register
    (D-1..D-9 + D-SEC-1/D-SEC-2 binding semantics) → FIXTURE_PREPARATION
    REVISION Request v0.1..v0.6 six-round closure → v0.6 ACCEPT →
    Revision SAR 001 (fdf45ea) → canonical revision work state (e729e32:
    F-1..F-4 repairs, SV-1..SV-6 30/30, FIXTURE_MANIFEST v2, completion
    record v2, zero path violations) → Human acceptance audit B=REVISE →
    Request v0.7 opened at 5cfcc16. SAR 001 chain/scope, F-1..F-3, snapshot
    mechanism, writer invariant, and claimed SV result PASS; final closure
    FAILS on RF-4.5 IMMUTABLE_REVISION payload and RF-4.6
    mapping_snapshot_seal_boundary.
    Human approved Request v0.7 → REVISION SAR 002 (5296d9f) → exactly one
    work cycle at 5eb1ec0 closed RF-4.5/RF-4.6/RF-4.6m; SV-1..SV-6 with
    SV-4.5/4.6/4.6m field-level assertions = 33/33 PASS in discarded
    sandbox; manifest v3, completion record v3, es_runner.py
    875cb1d9/bc393362 delivered and pushed. Final closure remains pending
    fresh Human acceptance.
    Human ruling “acceptance，继续” produced Acceptance Record 002 at
    d56ff1b: 5eb1ec0 = ACCEPTED/FROZEN; ACCP-1 pre-call gap and ACCP-2
    documentation residue are carried checkpoints, not silently erased.
    EXECUTION Request v0.3 opened at 1088a0c with exact Manifest v3 /
    Completion v3 / eleven-artifact / deterministic runtime e88c996b /
    D-SEC-1 / D-SEC-2 / ENV-PROBE-V1 / §9 ACCP-1 bindings.
    Human APPROVE A+B+C instantiated EXECUTION SAR 001, IS_MUTATION SAR 001,
    and OBSERVER AUTHORIZATION RECORD 001 at c454687, all exact-binding
    execution commit edf7d4a. Campaign exec-001-edf7d4a stopped INVALID at
    step-0 ENV-PROBE-V1: measured ad2abb68 versus expected 9048aed2; sole
    differing field swiftc_version wording. No materialize/ES/observer stage
    ran. Evidence canonical at 6b511da; execution budget consumed.
    Post-campaign audit fa597bc closed the root cause as pre-authorization
    environment-binding inconsistency: Request v0.3 expected swift-driver
    wording, while its ENV-PROBE-V1 faithfully recorded `/usr/bin/swiftc
    --version` output. Fixture/T-IMPL/adapter runtime are non-defective and
    the INVALID verdict remains binding.
    Human “授权 corrected EXECUTION Request” opened Request v0.4 at 79ce4e3:
    preserve ENV-PROBE-V1; sole contract correction aligns expected
    swiftc_version with `/usr/bin/swiftc --version` output, giving expected
    environment identity ad2abb68. Exact execution repository commit is
    9966d31. It requests new EXECUTION/IS_MUTATION/OAR records 002 with a new
    budget and authorizes no stage.
    Human “授权起草 corrected EXECUTION Request / record set” opened Request
    v0.5 at 888a6a7: exact execution state remains 9966d31; all inherited
    bindings remain unchanged. It adds EXECUTION_PROVENANCE_RECORDER_003 for
    exact executable identity/argv/process timing/stdout/stderr and fail-closed
    artifact completeness, plus a cross-binding closure record mapping legacy
    runner _001/V1 to OAR 003/CHANNEL-UNIVERSE-V2 without runner modification.
    It requests four new records and one new budget only after approval.
    Human APPROVE A+B+C instantiated four records 003 at bda7829, all
    exact-binding execution commit 9966d31. Campaign exec-003-9966d31 passed
    step0, adapter e88c996b, and environment identity ad2abb68; EPR003
    launched driver, but materialize exited 1 because repository-relative
    tau seed path resolved against host root. EPR003 then failed writing its
    manifest because plan output_path was the run directory. Evidence is
    canonical at a50ff8b.
    Read-only Human evidence audit 266e953 closed attribution as two
    independent defects: `PROVENANCE_RECORDER_OUTPUT_PATH_BINDING_DEFECT`
    and `EXECUTION_CWD_AND_SEED_PATH_BINDING_DEFECT`. B was causally earlier;
    A is the registered primary stop. Deeper OS-level mechanism remains
    unresolved.
    Human “授权新的 corrected Request / records” opened Request v0.6 at
    8704c75. It preserves execution commit 9966d31 and inherited bindings.
    EPR004 adds output-path preflight, exact repository-commit/cwd
    verification, repository-contained D/D' SHA256 input checks, executable
    identity/argv/process facts, and fail-closed outputs. Cross-binding
    record 004 maps `_001/V1` to OAR 004/V2 without runner modification. It
    requests four new records and one new budget only after approval.
    Human APPROVE A+B+C instantiated Closure Record 004, EXECUTION SAR 004,
    IS_MUTATION SAR 004, and OAR 004 at b80c17a, all exact-binding execution
    commit 9966d31. Campaign exec-004-9966d31 passed step0, EPR004 exact
    cwd/input/provenance enforcement, adapter e88c996b, and environment
    identity ad2abb68. Materialize, es1, and es2 passed; es2 observed REUSE.
    mutate-n1 failed `KeyError: d_prime_seed_path`; D' mutation/revision-2
    mapping was absent; ESN invalidly returned REUSE rather than BLOCK.
    Evidence is canonical at 4238529.
    Read-only Human evidence audit df508d4 closed contract responsibility as
    `FIXTURE_RUNNER_TAU_INTERFACE_CONTRACT_DEFECT` (shared/bilateral): exact
    runner consumed undeclared top-level `d_prime_seed_path` and
    `dependencies`, while bound τN1 runtime under-declared both. N1 D'
    addition and revision-2 mapping were absent; ESN REUSE was invalid
    derived behavior and neither semantic evidence nor refutation.
    Human “授权新的 corrected Request / records” opened Request v0.7 at
    e721f7a. It proposes one scoped τN1 interface completion work cycle:
    replace τN1 with exact schema SHA256 156fa091…, adding dependencies and
    d_prime_seed_path/D' SHA256/revision; update Manifest/Completion solely
    for rebinding; then create Closure Record 005, EXECUTION SAR 005,
    IS_MUTATION SAR 005, and OAR 005 exact-binding the post-completion commit
    and run one campaign through EPR004. No implementation or campaign is
    authorized yet.
    Human APPROVE T+E completed τN1 interface at fef0b2f and instantiated
    records 005 at afca0d0, exact-binding post-completion commit fef0b2f.
    Campaign exec-005-fef0b2f passed step0, EPR004 exact
    repository/cwd/input enforcement, adapter e88c996b, and environment
    identity ad2abb68. Materialize/es1/es2 passed with observed ES2 REUSE;
    mutate-n1 failed `KeyError: d_prime_seed_path` because completed τN1
    nested D' fields under dependencies[0] while runner expected top-level;
    D' mutation/revision-2 mapping absent; ESN invalidly returned REUSE
    instead of BLOCK. Evidence is canonical at 5c5fcc4.
    Read-only schema authority forensic audit 9616133 closed responsibility as
    shared/bilateral `TAU_N1_RUNNER_SCHEMA_AUTHORITY_ABSENCE`. Original
    fixture preparation introduced both exact runner top-level consumption and
    τN1 without that field; no authoritative τN1 interface schema existed.
    One-sided Request-schema or runner-defect attribution is rejected.

  NOT AUTHORIZED: EXECUTION, IS_MUTATION, Observer authorization
  (no request opened yet); implementation changes; governance expansion.

Research track:
  SRS-REAL-CLOSURE-01 = ACTIVE RESEARCH PRIORITY.
  Next lawful object = Human decision whether to authorize a corrected
  Request/records. Any future correction must first establish an authoritative
  τN1 interface schema, reconcile it with exact runner consumption, and add
  fail-closed schema validation. No rerun, τN1 repair, runner/fixture repair,
  old-record reuse, environment normalization, IS mutation, or observer action
  is authorized before that. Core claim remains NOT ESTABLISHED.

Core gap:
  ES₁ → IS(SRS) → independent ES₂ lawful reuse = NOT ESTABLISHED
  (T-IMPL-01 ESTABLISHED ≠ reuse established; instrument ready ≠ reuse
  established).

Frozen experiment contract:
  docs/02-evidence/es-is-20261005/
  SRS_REAL_CLOSURE_01_EXPERIMENT_DESIGN_AND_EVIDENCE_PLANNING_PACKAGE_V0.2_20261007.md
  (= ACCEPT; pre-registered expected decisions; E1–E6 + SRS-N1 evidence
  chain; four-state stop conditions; failure doctrine: no governance-text
  repair of failed results).

Current reset artifacts (2026-10-07):
  docs/00-governance/SRS_REAL_CLOSURE_01_FIXTURE_REVISION_AUTHORIZATION_REQUEST_V0.7_20261007.md
  docs/00-governance/SIMIGO_RESEARCH_FOCUS_REORIENTATION_20261007.md
  docs/00-governance/SIMIGO_SRS_REAL_CLOSURE_CRITICAL_PATH_V0.1_20261007.md
  docs/00-governance/SIMIGO_SRS_REAL_CLOSURE_COMMISSION_20261007.md
  docs/00-governance/SRS_REAL_CLOSURE_01_EXECUTION_READINESS_DEFECT_REGISTER_20261007.md
```

Standing disciplines (registered 2026-10-07): governance-critical commits
are pushed to canonical main and ls-remote verified immediately (local
completion ≠ canonical state); declared changes must be re-verified before
commit; governance text cannot repair instrument semantics; self-validation
PASS proves only its asserted coverage, never an unstated contract payload;
authorization
boundaries guard against disguised execution via validation as well as
open execution.

The older “SRS-VAL design is active” statement below is superseded by this
status. SRS-VAL Design v0.8, Authorization Package v0.6, Implementation Boundary
Audit v0.1, and Manifest Contract v1.0 are frozen governance infrastructure.

## 1. Canonical recovery order

A new session must recover in this order:

```text
1. This anchor.
2. docs/RESEARCH_CONTEXT_INDEX.md.
3. docs/RESEARCH_STATE.md — restored current-state section.
4. Issue #2 decomposition/control artifact.
5. ES–IS Settled Relation Coupling Architecture Audit Package.
6. Named Human rulings / frozen contracts / evidence artifacts when a claim is
   disputed.
```

Do not reconstruct state from conversation memory, agent recollection, deleted
branch names, or older handoff paragraphs that are explicitly marked as
superseded.

## 2. Global research goal

SimiGo is not a generic knowledge base or inference engine.

The current research goal is:

```text
Determine whether Execution State can form a real computational coupling with
a persistent Information Space, such that a relation settled by one Execution
State becomes lawful, verifiable, reusable computational state for an
independent later Execution State.
```

The reusable state must allow:

```text
validate dependency / revision / freshness / provenance;
reuse the settled relation without recomputation;
compute only genuinely new delta;
block or recompute when dependencies are stale, invalid, or unprovenanced.
```

This must be distinguished from an ordinary cache hit.

## 3. Canonical loop

```text
ES₁
  ↓ compute relation
Settled Relation State
  ↓ persist result + source relation + dependencies + revision + provenance +
    freshness + relation semantics + settlement status
Information Space
  ↓ independent resolution
ES₂
  ↓ validate dependency / revision / freshness / provenance
  ↓ if valid, reuse settled relation
  ↓ compute only Δ
New Settled Relation State
  ↓ persist
Information Space
  ↓
ES₃ ...
```

## 4. Canonical definitions

```text
ES = Execution State.
IS = Information Space.

ES and IS are mutually coupled computational state spaces.

SRS = Settled Relation State:
  settled result
  + source relation
  + dependency identities / revisions
  + provenance
  + validity / freshness conditions
  + relation semantics
  + settlement status.

SRS is not:
  opaque cache entry;
  bare result;
  mutable relation;
  runtime checkpoint;
  generic knowledge-graph edge.

SRS records are append-only.
Invalidation, supersession, or freshness change creates a new status/state
record; historical SRS must not be silently rewritten.

Information Topology =
  Information nodes
  + Relation / Settled Relation State edges
  + dependency / revision / freshness / provenance / policy validity
  accumulated by Execution State computation.

Information Topology is not:
  independent knowledge-graph product;
  similarity graph;
  vector index;
  separate PALACE semantic system.
```

## 5. Historical lineage

The current ES↔IS↔SRS architecture was progressively distilled from prior
research:

```text
Execution State
  → Information / Relation
  → relation persistence / identity / provenance / revision
  → ES continuation
  → Information Space foundation
  → PIR / physical reconciliation
  → Unified Carrier
  → ES↔IS coupling refinement
  → Settled Relation State
  → Information Topology
  → ES₁ → IS → independent ES₂ reuse
```

Authoritative lineage anchors:

```text
docs/00-governance/SIMIGO_LAB_PHASE2_RELATION_DECISIONS_SEALED_20261002.md
docs/00-governance/SIMIGO_LAB_PHASE2_RELATION_PERSISTENCE_SEMANTICS_GATE_RESULT_20261002.md
docs/00-governance/SIMIGO_LAB_IPAC_EXECUTION_STATE_RESEARCH_SYNTHESIS_20261003.md
docs/00-governance/SIMIGO_LAB_IPAC_SYNTHESIS_CLOSURE_REVIEW_20261003.md
docs/00-governance/SIMIGO_LAB_EXECUTION_INFORMATION_SPACE_BOUNDARY_SYNTHESIS_20261003.md
docs/00-governance/SIMIGO_LAB_RESEARCH_CONSTITUTION_20261005.md
docs/02-evidence/es-is-20261005/CORE_REFERENCE_SCENARIO.md
docs/02-evidence/es-is-20261005/ES_CSP_R01_EXECUTION/S3_COMPLETION_RECORD_20261006.md
docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_PIR_DESIGN_V0.2_20261006.md
docs/02-evidence/es-is-20261005/SIMIGO_ES_IS_SETTLED_RELATION_COUPLING_ARCHITECTURE_AUDIT_PACKAGE_20261006.md
docs/00-governance/SIMIGO_ES_IS_ARCHITECTURE_RESEARCH_DECOMPOSITION_CONTROL_20261006.md
```

## 6. Established conclusions

### 6.1 Constitutional core

```text
ES and IS are mutually coupled computational state spaces.
```

This is governance-level architecture, not yet a completed SRS-reuse
implementation or experiment.

### 6.2 Information / Relation foundation

```text
Information Identity is established.
Information is immutable.
Relation is an immutable semantic edge over InformationIDs.
Relation persistence has bounded two-store evidence.
Dependency / revision / provenance mechanisms exist at the carrier and
relation-prerequisite level.
```

### 6.3 R01 — ES Continuation Sufficiency

```text
S3                    PASS
C1                    PASS
C2                    PASS
P-POS                 PASS
N-A                   PASS
N-B                   PASS
I-1                   PASS
I-2                   PASS
C3                    OBSERVATION ONLY

Research verdict      PASS — CONTINUATION SUFFICIENT
Scope                 BOUNDED
Universal continuation   NOT ESTABLISHED
Production readiness     NOT ESTABLISHED
SRS reuse proof          NOT ESTABLISHED
```

R01 proves only that a prepared registered Information Closure was sufficient
for bounded continuation. It does not prove `ES₁ → IS → ES₂` SRS reuse.

### 6.4 U-A / CCVS

```text
Unified Carrier is established for FILE + SESSION under one contract and
guarantee set.

Information Identity ≠ Carrier Identity ≠ Representation Identity.

Revision, transaction, ledger, mapping, and provenance mechanisms are
established within U-A Gate C scope.

Gate C = CLOSED / ACCEPT.
```

U-A / CCVS support physical carrying correctness of Information Space. They do
not prove SRS reuse.

### 6.5 PIR

```text
PIR v0.2 path:
Query → Scope → Candidate Index → Relevant Objects → Physical Check →
Fresh Closure.

Query-Priority Reconciliation        PASS / ACCEPTED
PIR Design v0.2                      ACCEPTED
Clarification Addendum              ACCEPTED
F1–F5                                RESOLVED
PIR implementation                   NOT AUTHORIZED
PIR experiment                       NOT AUTHORIZED
PIR fixture                          NOT AUTHORIZED
Minimal PIR Probe v0.2               PAUSED pending central architecture ruling
```

PIR is the freshness / physical-reconciliation prerequisite architecture. It is
not SRS-reuse evidence.

## 7. Clarified but not demonstrated

### 7.1 Settled Relation State

The SRS semantic boundary is clarified, accepted, and frozen.

```text
SRS-SEM-01 was originally SELECTED / NOT STARTED.
Human later explicitly opened it after Recovery Anchor closure.
After iterative review, Design v0.5 is ACCEPT / FROZEN.
Accepted design artifact:
`docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_SEM_01_DESIGN_V0.5_20261007.md`.
Current commissioned design:
`docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_RUN_IMPLEMENTATION_MANIFEST_V1.0_20261007.md`.
Authorization package status = ACCEPT / FROZEN; next stage NOT OPENED.
Implementation Boundary Audit v0.1 = ACCEPT / FROZEN.
Manifest Contract v0.1 = REVISE / SUPERSEDED BY V0.2.
Manifest Contract v0.2 = REVISE / SUPERSEDED BY V0.3.
Manifest Contract v0.3 = REVISE / SUPERSEDED BY V0.4.
Manifest Contract v0.4 = REVISE / SUPERSEDED BY V0.5.
Manifest Contract v0.5 = REVISE / SUPERSEDED BY V0.6.
Manifest Contract v0.6 = REVISE / SUPERSEDED BY V0.7.
Manifest Contract v0.7 = REVISE / SUPERSEDED BY V0.8.
Manifest Contract v0.8 = REVISE / SUPERSEDED BY V0.9.
Manifest Contract v0.9 = REVISE / SUPERSEDED BY V1.0.
Manifest Contract v1.0 = ACCEPT / FROZEN.
AUTH-REQ-01 Human Authorization Request v0.2 and IMPLEMENTATION-only Filled
Manifest Instance v0.2 = OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW;
no Stage Authorization Record exists and no stage is authorized.
Research focus reset 2026-10-07:
Governance track = AUTH-REQ-01 v0.2 pending Human authorization review,
maintenance-only;
Research track = SRS-REAL-CLOSURE-01 ACTIVE RESEARCH PRIORITY;
Core gap = ES₁ → IS(SRS) → independent ES₂ lawful reuse, NOT ESTABLISHED.
Reset artifacts:
`docs/00-governance/SIMIGO_RESEARCH_FOCUS_REORIENTATION_20261007.md`;
`docs/00-governance/SIMIGO_SRS_REAL_CLOSURE_CRITICAL_PATH_V0.1_20261007.md`;
`docs/00-governance/SIMIGO_SRS_REAL_CLOSURE_COMMISSION_20261007.md`.
Accepted and frozen SRS-VAL design:
`docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_DESIGN_V0.8_20261007.md`.
Superseded SRS-VAL-01 design lineage:
V0.1 through V0.7 = REVISE / SUPERSEDED BY SUCCESSIVE REVISIONS.
```

The SRS-VAL authorization-package and Manifest Contract governance closures are
complete. Implementation, fixture preparation, execution, and experiment remain
unauthorized.

### 7.2 Information Topology

Information Topology is canonically defined but not demonstrated as accumulating
across independent Execution States.

## 8. Unproved core claims

```text
1.  ES₂ can lawfully adopt a relation settled by ES₁.
2.  ES₂ can validate dependency / revision / freshness / provenance.
3.  Valid reuse actually avoids re-executing the settled relation.
4.  ES₂ computes only genuinely new work.
5.  Stale dependency forces block or lawful recompute.
6.  Missing provenance fails validation.
7.  Bare result alone cannot authorize lawful reuse.
8.  Information Topology can accumulate and be reused across independent ES.
```

These claims must not be inferred from R01, PIR, U-A, or RelationCore.

## 9. Current governance / research tracks

### 9.1 Governance track — pending Human authorization review

```text
AUTH-REQ-01
Human Authorization Request v0.2
+
IMPLEMENTATION-only Filled Manifest Instance v0.2

Status = OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW
Requested stage set = { IMPLEMENTATION }
Stage Authorization Record = NOT_CREATED_PENDING_HUMAN_RULING
Authorized repository revision = eef3d24901e23b734bb887841528c0c7b4b42aa0

Next lawful action =
  Human authorization review of AUTH-REQ-01 v0.2; no stage authorized

Current request document =
  docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_AUTH_REQ_01_HUMAN_AUTHORIZATION_REQUEST_V0.2_20261007.md

Current filled manifest instance =
  docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_AUTH_REQ_01_IMPLEMENTATION_ONLY_FILLED_MANIFEST_INSTANCE_V0.2_20261007.md

Immutable bindings =
  docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_AUTH_REQ_01_IMMUTABLE_BINDINGS_V0.2_20261007.md
```

### 9.2 Research track — active priority

```text
SRS-REAL-CLOSURE-01 = ACTIVE RESEARCH PRIORITY
STATUS = PLANNING ONLY; no implementation, fixture, execution, or IS mutation is
authorized.

Core gap:
ES₁ → IS(SRS) → independent ES₂ lawful reuse = NOT ESTABLISHED.

Critical-path artifacts:
docs/00-governance/SIMIGO_RESEARCH_FOCUS_REORIENTATION_20261007.md
docs/00-governance/SIMIGO_SRS_REAL_CLOSURE_CRITICAL_PATH_V0.1_20261007.md
docs/00-governance/SIMIGO_SRS_REAL_CLOSURE_COMMISSION_20261007.md
```
