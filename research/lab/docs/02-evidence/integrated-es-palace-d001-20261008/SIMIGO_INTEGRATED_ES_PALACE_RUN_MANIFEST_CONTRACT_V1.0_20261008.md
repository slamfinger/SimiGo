# SimiGo Integrated ES–PALACE Run Manifest Contract v1.0

> **Status:** DELIVERED FOR HUMAN REVIEW — MANIFEST CONTRACT ONLY
> **Date:** 2026-10-08
> **Manifest Contract ID:** `INTEGRATED-ES-PALACE-D001-RUN-MANIFEST-V1.0`
> **Bound Package:** Integrated ES–PALACE Implementation / Fixture Preparation Authorization Package v1.0
> **Package SHA-256:** `3ef5967074b2231e9c8c65f093a51464893320f0bf2a74914d35e6f9b6800f43`
> **Canonical base:** `d4b02b2fa045b9a78b0659b26491dab03592e320`
> **Integrated experiment execution:** NOT AUTHORIZED
> **Automatic Run Manifest approval:** DENIED

## 1. Scope

This contract defines the only form of a future Run Manifest instance for
implementation / fixture preparation. It does not create a manifest instance,
execute a stage, create implementation code, create fixtures, or authorize an
integrated experiment.

The sole allowed future mode is:

```text
IMPLEMENTATION_FIXTURE_PREPARATION_ONLY
```

A manifest instance or runner that requests any other mode is invalid.

## 2. Immutable governance bindings

Every future instance must bind the following paths and SHA-256 digests:

| Object | Path | SHA-256 |
| --- | --- | --- |
| Request | `docs/00-governance/SIMIGO_INTEGRATED_ES_PALACE_IMPLEMENTATION_FIXTURE_PREPARATION_REQUEST_V1.0_20261008.md` | `d4b1598df5366143488a63baa3bf463d9951aaebc7237e9752605806bb77726a` |
| Frozen design | `docs/00-governance/SIMIGO_INTEGRATED_ES_PALACE_VALIDATION_DESIGN_PACKAGE_001_REVISION_V1.1_20261008.md` | `3c28c4699150414b90ebee7916f6e1a18214c5e27b08005dd0851b59e88fd34b` |
| Design acceptance | `docs/00-governance/SIMIGO_INTEGRATED_ES_PALACE_VALIDATION_DESIGN_PACKAGE_001_REVISION_V1.1_ACCEPTANCE_RULING_20261008.md` | `e762c1df2dc4acc64d40c46c9db4a6369b57ec777629fc5cf8a7e1b356b19b21` |
| Authorization Package | `docs/02-evidence/integrated-es-palace-d001-20261008/SIMIGO_INTEGRATED_ES_PALACE_IMPLEMENTATION_FIXTURE_AUTHORIZATION_PACKAGE_V1.0_20261008.md` | `3ef5967074b2231e9c8c65f093a51464893320f0bf2a74914d35e6f9b6800f43` |

The instance must also bind the immutable canonical commit that registers this
manifest contract and prove that commit is reachable from both local `main` and
`origin/main` at entry.

## 3. Required manifest instance fields

A valid future instance is canonical JSON and contains exactly these top-level
groups. Unknown top-level groups are invalid.

```json
{
  "manifest_instance_id": "UUIDv4",
  "manifest_contract_id": "INTEGRATED-ES-PALACE-D001-RUN-MANIFEST-V1.0",
  "package_id": "INTEGRATED-ES-PALACE-D001-AUTH-PACKAGE-V1.0",
  "mode": "IMPLEMENTATION_FIXTURE_PREPARATION_ONLY",
  "schema_version": "D001-RUN-MANIFEST-INSTANCE-V1",
  "repository_binding": {},
  "governance_bindings": {},
  "implementation_binding": {},
  "fixture_binding": {},
  "evidence_binding": {},
  "stage_plan": {},
  "stop_rule": {}
}
```

The semantic fields required inside each group are:

```text
repository_binding:
  canonical_commit; branch=main; origin_main; worktree_clean=true;
  no_untracked_stage_artifacts=true

governance_binding:
  the four immutable path/digest records in Section 2;
  human_package_acceptance_reference

implementation_binding:
  root=integrated-es-palace/d001/implementation;
  exact artifact list;
  python_version;
  stdlib_only=true;
  schemas=LAWFUL-INFORMATION-CLOSURE-D001-V1,
          RECOVERED-INFORMATION-CONTEXT-D001-V1,
          CONTINUATION-AUTHORITY-VIEW-D001-V1,
          ES-CONTINUATION-INPUT-D001-V1,
          ES-CONTINUATION-OUTPUT-D001-V1,
          D001-NEGATIVE-DECISION-V1;
  side_channel_checks=SC-1..SC-8

fixture_binding:
  parent=integrated-es-palace/d001/fixtures;
  cases=P-LAWFUL,P-SETTLED,P-BLOCKED,N-MISSING,N-STALE,N-AMBIGUOUS,N-ILLEGAL;
  per-case manifest path, primitive families I1-I10, invocation locator,
  expected typed decision, expected continuation class, and no-fallback flags

evidence_binding:
  parent=docs/02-evidence/integrated-es-palace-d001-validation-v1;
  exact evidence object list;
  write_once=true;
  final_object=EVIDENCE_SHA256SUMS

stage_plan:
  stages=S0-PREFLIGHT,S1-FIXTURE_PREPARATION,S2-PREPARATION_VALIDATION,STOP;
  integrated_experiment=false;
  observer_campaign=false

stop_rule:
  after=S2-PREPARATION_VALIDATION;
  action=REQUEST_SEPARATE_HUMAN_EXPERIMENT_DECISION
```

The instance must not contain execution budgets, model identifiers, ranking
rules, physical-probe rules, role labels, expected verdicts inside the opaque
locator, or any permission for canonical IS mutation.

## 4. Stage gates and commands

No command below may run before:

```text
1 Human ACCEPT of Authorization Package v1.0;
2 a separate Human implementation / fixture preparation authorization record;
3 creation of a conforming Run Manifest instance.
```

### 4.1 S0 — PREFLIGHT

Required command shape:

```bash
python3 integrated-es-palace/d001/implementation/preflight.py \
  --manifest <RUN_MANIFEST_INSTANCE.json>
```

S0 PASS requires Package preflight gates PF-1 through PF-10. The command must
create only `PREFLIGHT.json`. It must not create implementation files, fixture
files, or semantic evidence.

### 4.2 S1 — FIXTURE_PREPARATION

Required command shape:

```bash
python3 integrated-es-palace/d001/implementation/selfcheck.py \
  --manifest <RUN_MANIFEST_INSTANCE.json> \
  --stage S1-FIXTURE_PREPARATION
```

S1 may create only the eight approved implementation artifacts and only the
seven approved fixture roots with their approved file families. It must verify
every created file digest against the manifest and create only
`FIXTURE_PREPARATION.json` in evidence.

### 4.3 S2 — PREPARATION_VALIDATION

Required command shape:

```bash
python3 integrated-es-palace/d001/implementation/selfcheck.py \
  --manifest <RUN_MANIFEST_INSTANCE.json> \
  --stage S2-PREPARATION_VALIDATION
```

S2 may execute only isolated fixture validation. It must produce the seven
registered decisions, identity checks, SC-1–SC-8 results, Carrier lifecycle
evidence, negative-decision evidence, and final SHA-256 closure. It must not
issue an integrated claim or execute an integrated experiment.

### 4.4 STOP

After S2 reaches any terminal state, the runner must stop and emit:

```text
REQUEST_SEPARATE_HUMAN_EXPERIMENT_DECISION
```

No automatic experiment, observer campaign, canonical IS mutation, E9, EXP-004,
or equivalence ruling may follow.

## 5. Required seven-decision vector

The observed decision vector must exactly equal:

```text
P-LAWFUL    CONTINUE   / SETTLED_CONTINUATION
P-SETTLED   REUSE      / SETTLED_CONTINUATION
P-BLOCKED   BLOCK      / BLOCKED_LAWFUL_CONTINUATION
N-MISSING   BLOCK      / MISSING_INFORMATION_BLOCK
N-STALE     BLOCK      / STALE_INFORMATION_BLOCK
N-AMBIGUOUS BLOCK      / AMBIGUOUS_INFORMATION_BLOCK
N-ILLEGAL   BLOCK      / ILLEGAL_CONTINUATION_BLOCK
```

Each entry must bind case ID, trigger, inventory result, evidence references and
digests, precedence reason, typed output, continuation class, secondary defects,
identity digest, and closure artifact digest. A missing, extra, reordered,
downgraded, repaired, guessed, silently recomputed, or stale-success entry fails.

## 6. Fresh-entry repository gate

At every stage entry the runner must revalidate:

```text
git status --porcelain is empty;
HEAD = registered canonical_commit;
refs/heads/main = HEAD;
refs/remotes/origin/main = HEAD;
the manifest instance is present and digest-stable;
no destination evidence object already exists;
the stage is the registered next stage;
mode remains IMPLEMENTATION_FIXTURE_PREPARATION_ONLY.
```

A changed worktree, changed HEAD, changed remote main, missing binding, reused
manifest instance, or existing write-once destination produces INVALID. The
runner must not fetch, rebase, merge, commit, reset, clean, or mutate the
repository during a stage.

## 7. Side-channel, identity, and Carrier gates

The Run Manifest instance must require:

```text
SC-1..SC-8 from Authorization Package v1.0;
deterministic P3 identity derivation;
SHA-256 canonicalization for all semantic and evidence digests;
seven persisted terminal identity records;
separate success and failure lifecycle records;
no Carrier semantic verdict;
no stale-success artifact;
write-once evidence closure.
```

If identity recomputation differs at any point, or a Carrier record cannot be
verified, the stage is INVALID. No repair or rewrite is allowed within the same
manifest instance.

## 8. Terminal states

Only these terminal states may be emitted:

```text
PREPARATION_VALIDATION_PASS
PREPARATION_VALIDATION_FAIL
PREPARATION_VALIDATION_INVALID
```

Meanings:

```text
PASS    all registered preparation checks passed; no integrated claim is made;
FAIL    a registered preparation check evaluated false;
INVALID trustworthy evaluation could not be established.
```

PASS still requires a separate Human decision before integrated execution.

## 9. Evidence closure

The final evidence tree must contain exactly the nine objects bound in the
Authorization Package. `EVIDENCE_SHA256SUMS` must be written last, cover every
other object exactly once, use repository-relative paths, and use lowercase
SHA-256 hexadecimal digests. The tree must be symlink-free and parse-complete.

Post-closure modification voids the manifest instance. Any correction requires a
new manifest instance, a new evidence parent, and a new governance record.

## 10. Acceptance criteria for this contract

Human review should verify that this contract:

```text
1 binds Request v1.0 and frozen D v1.1 without semantic change;
2 binds Authorization Package v1.0 byte-for-byte;
3 separates package review, implementation / fixture preparation, and
  integrated experiment authorization;
4 requires a fresh clean canonical repository entry;
5 permits only the seven approved fixture cases and nine evidence objects;
6 enforces P1–P7, SC-1–SC-8, seven-decision closure, and Carrier lifecycle;
7 preserves E8 + R01 as non-composing predecessor evidence;
8 forbids automatic manifest acceptance and automatic experiment execution;
9 uses FAIL and INVALID without success upgrading.
```

## 11. Decision requested

Human review must return exactly one ruling:

```text
ACCEPT   this manifest contract is reviewable as part of the delivered Package;
REVISE   require a new manifest contract revision;
REJECT   reject the delivered package/manifest pathway.
```

Acceptance of this contract does not authorize any stage command, create a valid
Run Manifest instance, or authorize an integrated experiment.
