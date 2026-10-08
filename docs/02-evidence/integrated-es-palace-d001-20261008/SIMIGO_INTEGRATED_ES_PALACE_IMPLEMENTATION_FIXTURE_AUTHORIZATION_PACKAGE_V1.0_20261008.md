# SimiGo Integrated ES–PALACE Implementation / Fixture Preparation Authorization Package v1.0

> **Status:** DELIVERED FOR HUMAN REVIEW — PACKAGE ONLY
> **Date:** 2026-10-08
> **Package ID:** `INTEGRATED-ES-PALACE-D001-AUTH-PACKAGE-V1.0`
> **Governing Request:** SimiGo Integrated ES–PALACE Implementation / Fixture Preparation Request v1.0
> **Frozen design:** Integrated ES–PALACE Validation Design Package 001 Revision v1.1
> **Canonical base:** `d4b02b2fa045b9a78b0659b26491dab03592e320`
> **Implementation:** NOT AUTHORIZED
> **Fixture creation or mutation:** NOT AUTHORIZED
> **Experiment execution:** NOT AUTHORIZED
> **Canonical IS mutation:** NOT AUTHORIZED
> **E9 / EXP-004:** NOT AUTHORIZED

## 1. Authority and non-composition boundary

This Package responds only to the opened Request v1.0. It does not modify,
reinterpret, broaden, or supersede frozen Design Package 001 v1.1.

The binding predecessor boundary is:

```text
E8  = bounded CarrierSQLite carrier equivalence evidence;
R01 = bounded continuation-sufficiency evidence;
D   = NEW integrated semantic-closure object;
P1–P7 remain frozen and independent of predecessor composition.
E8 + R01 ≠ integrated SimiGo proof.
```

E8 and R01 may be cited only as non-composing predecessor limits. They do not
supply proof for any D case, identity, mapping, side-channel denial, negative
precedence, Carrier lifecycle, or integrated claim.

## 2. Approved lifecycle and stage separation

If and only if a Human ACCEPTS this Package, a separate Human authorization may
open the implementation / fixture preparation stage. That stage must stop before
any integrated experiment execution.

```text
PACKAGE REVIEW
  ↓ Human ACCEPT / REVISE / REJECT
IMPLEMENTATION / FIXTURE PREPARATION
  ↓ separately authorized and validated
STOP
  ↓ separate Human experiment authorization decision
INTEGRATED EXPERIMENT — NOT AUTHORIZED BY THIS PACKAGE
```

The following stages are in scope only as separately reviewable future actions:

```text
S0 IMPLEMENTATION        create approved implementation artifacts only;
S1 FIXTURE_PREPARATION   create approved isolated fixtures only;
S2 PREPARATION_VALIDATION run implementation self-checks against isolated
                         fixtures and persist validation evidence only;
S3 STOP                  request a separate integrated-experiment decision.
```

S2 is not an integrated experiment. It must not generate an integrated claim,
success equivalence ruling, production claim, PALACE equivalence claim, or
general Execution State claim.

## 3. Exact implementation scope

The only approved implementation root is:

```text
integrated-es-palace/d001/implementation/
```

The only approved implementation artifacts are:

```text
IMPLEMENTATION_MANIFEST.json
README.md
schemas.py
inventory.py
reconstruction.py
continuation.py
carrier.py
preflight.py
selfcheck.py
```

No other implementation path may be created. The implementation tree must not
modify:

```text
database-carrier-replication/
boundary-study/
docs/02-evidence/es-is-20261005/
canonical Information Space state;
E8 evidence;
R01 evidence;
PIR evidence.
```

### 3.1 Module responsibility boundaries

```text
schemas.py
  defines and validates the only typed record schemas in Section 4.

inventory.py
  resolves I1–I10 mechanically through registered references only.

reconstruction.py
  consumes only a registered opaque locator and inventory-resolved objects to
  produce RecoveredInformationContext.

continuation.py
  derives ContinuationAuthorityView, ESContinuationInput, continuation identity,
  REUSE / BLOCK / terminal continuation decisions, and negative precedence.

carrier.py
  persists, retrieves, digest-verifies, and emits lifecycle records only.

preflight.py
  validates manifest identity, repository state, paths, fixture roots, digests,
  permissions, and evidence write-once conditions.

selfcheck.py
  performs S0–S2 self-checks and evidence closure. It must refuse integrated
  experiment mode.

IMPLEMENTATION_MANIFEST.json
  binds module paths, schema IDs, Python version, standard-library policy,
  fixture-root names, evidence-root name, and forbidden-channel checks.

README.md
  states the limited preparation-only boundary and forbidden claims.
```

### 3.2 Runtime policy

The implementation must use Python 3 and the Python standard library only. The
Carrier may use `sqlite3`. The implementation must not:

```text
use third-party packages;
open network sockets;
invoke models or ranking systems;
discover fixtures by semantic search, embedding, similarity, filename search,
filesystem exploration, fixture role labels, process environment, model context,
or mutable global state;
probe physical freshness, mtime, device identity, or PIR state;
alter files outside its approved roots and evidence destinations;
rewrite an existing write-once evidence object;
treat E8 + R01 as proof of D.
```

Approved invocation fields are exactly:

```text
manifest_instance_id;
package_id;
stage;
schema_version;
opaque_locator.
```

No additional invocation field may affect semantic state. The allowed process
inputs are executable selection, Python runtime, the manifest instance, and the
approved opaque locator. No environment lookup may enter
`ESContinuationInput`, continuation identity, or decision state.

## 4. P1 primitive inventory bindings

Every fixture manifest must mechanically expose all primitive families I1–I10.
References must be repository-relative, canonical, digest-bound, provenance-
bound, revision-bound, non-symlink, and confined to the selected fixture root.
An object outside the inventory is not discoverable and resolves as missing.

| ID | Primitive family | Required binding |
| --- | --- | --- |
| I1 | Lawful Information Closure identity | `closure_id`, `closure_revision`, canonical `closure_digest` |
| I2 | Closure membership references | ordered member refs, digests, roles confined to inventory |
| I3 | CarrierRecord / CC-5 mapping | carrier record ref, CC-5 mapping ref, information and mapping identity, revision, digest |
| I4 | Provenance and revision records | per-object provenance, revision, validity, integrity digest |
| I5 | NEXT_ACTION continuation records | pointer identity, target digest, registered boundary, class |
| I6 | Approved opaque reconstruction locator | repository-relative fixture-root locator, no role or expected verdict |
| I7 | Approved carrier snapshot/read binding | read-only carrier ref and expected integrity digest |
| I8 | Approved continuation-input schema | `ES-CONTINUATION-INPUT-D001-V1` |
| I9 | Approved continuation-output schema | `ES-CONTINUATION-OUTPUT-D001-V1` |
| I10 | Approved evidence destination set | repository-relative evidence paths and write-once policy |

Mechanical completeness requires exactly these ten family IDs. An absent,
unresolvable, malformed, duplicate-conflicting, symlinked, outside-root, or
digest-invalid mandatory object produces the designated negative result rather
than a fallback.

## 5. P2 typed PALACE → ES schemas

All persisted semantic records must use the following schema IDs and field
contracts. Unknown fields are invalid. Canonical JSON representation is UTF-8,
object keys sorted lexicographically, separators `,` and `:`, no insignificant
whitespace, and no nondeterministic serialization.

### 5.1 LawfulInformationClosure

```text
schema_id               = "LAWFUL-INFORMATION-CLOSURE-D001-V1"
closure_id              = nonempty stable string
closure_revision        = nonempty revision string
members[]               = ordered inventory references and digests
closure_digest          = SHA256(canonical JSON of schema_id, closure_id,
                                  closure_revision, members)
```

### 5.2 RecoveredInformationContext

```text
schema_id               = "RECOVERED-INFORMATION-CONTEXT-D001-V1"
closure_id              = exact closure identity
closure_revision        = exact closure revision
recovered_objects[]     = inventory-resolved objects, provenance, revisions,
                          digests, and context-only / authoritative classes
context_digest          = SHA256(canonical JSON of schema_id, closure_id,
                                  closure_revision, recovered_objects)
```

Context-only data remains in this view unless a registered P2 rule promotes it
to `ContinuationAuthorityView`.

### 5.3 ContinuationAuthorityView

```text
schema_id                 = "CONTINUATION-AUTHORITY-VIEW-D001-V1"
closure_id                = exact closure identity
closure_revision          = exact closure revision
recovered_context_digest  = exact recovered-context digest
authority_objects[]       = only registered continuation-authoritative objects
next_action               = optional registered pointer, present only when
                            uniquely resolvable and lawful
boundary_digest           = digest of the governing continuation boundary
```

### 5.4 ESContinuationInput

```text
schema_id                 = "ES-CONTINUATION-INPUT-D001-V1"
closure_id                = exact closure identity
closure_revision          = exact closure revision
recovered_context_digest  = exact recovered-context digest
next_action_id            = exact registered pointer identity or null
target_digest             = exact registered target digest or null
continuation_class        = SETTLED_CONTINUATION |
                            BLOCKED_LAWFUL_CONTINUATION |
                            BLOCKED_DEFECT |
                            NON_CONTINUABLE
authorization_boundary    = "D001-PACKAGE-V1.0"
```

No model-derived, ranking-derived, hidden-context, physical-probe, environment-
derived, or Carrier-interpreted field is permitted.

### 5.5 ContinuationOutput

```text
schema_id                 = "ES-CONTINUATION-OUTPUT-D001-V1"
input_digest              = SHA256(canonical ESContinuationInput)
decision                  = CONTINUE | REUSE | BLOCK
continuation_class        = exact P3 class
typed_reason              = registered reason identifier
secondary_defects[]       = zero or more typed secondary observations
continuation_output_digest = SHA256(canonical ContinuationOutput)
```

`CONTINUE` may occur only for a lawful fresh continuation. `REUSE` may occur
only under P3.1. `BLOCK` must preserve the exact negative class under P5.

## 6. P3 continuation identity and digest rules

The mandatory identity tuple is:

```text
identity_version           = "D001-CONTINUATION-IDENTITY-V1"
closure_id
closure_revision
recovered_context_digest
next_action_id
target_digest
continuation_class
authorization_boundary
continuation_output_digest
```

Derivation:

```text
continuation_identity_digest
  = lowercase_hex_sha256(canonical_json(identity_tuple))
```

The tuple and all referenced digests use lowercase SHA-256 hexadecimal encoding.
A change to any tuple field creates a different identity.

### 6.1 REUSE predicate

`REUSE` is lawful only when all six conditions hold:

```text
1 registered continuation identity is present;
2 mandatory provenance, revision, and integrity bindings validate;
3 recovered-context digest matches;
4 NEXT_ACTION identity and target digest match;
5 governing boundary remains lawful;
6 no rule requires fresh semantic computation.
```

REUSE must be persisted as a typed digest-bound `ContinuationOutput` and
identity record before success closure.

### 6.2 BLOCKED-LAWFUL predicate

`BLOCKED_LAWFUL_CONTINUATION` is preserved only when:

```text
1 the Information Closure is structurally lawful;
2 provenance and revision validate;
3 the continuation boundary is registered;
4 a registered blocking condition applies.
```

It must not be silently recomputed, upgraded, downgraded, guessed, replaced, or
converted into a defect block without changing the registered input.

### 6.3 Terminal persistence

Every terminal semantic state must produce:

```text
ContinuationIdentityRecord
ContinuationOutput
Carrier lifecycle record
closing evidence object digest
```

before any final preparation-validation success. A nonpersistable terminal
state is invalid.

## 7. P4 side-channel denial checks

The implementation manifest must require all eight checks. A preparation-
validation run fails if any check is missing, untyped, bypassed, or inconclusive.

| Check | Required proof |
| --- | --- |
| SC-1 fixture role denial | invocation binding contains locator only; no expected role or verdict |
| SC-2 search denial | target discovery uses deterministic inventory traversal; no search, embedding, similarity, ranking, or filename inference |
| SC-3 model denial | no model field or model process participates in the authority path |
| SC-4 physical denial | no PIR, mtime, freshness, device, or physical reconciliation probe |
| SC-5 environment denial | approved invocation fields only; environment input cannot enter semantic state |
| SC-6 unregistered-object denial | every semantic object resolves through I1–I10; outside objects resolve missing |
| SC-7 Carrier semantic denial | Carrier persists, retrieves, and verifies only; no Carrier-produced semantic verdict |
| SC-8 global-state denial | same locator and context digest reproduce the same `ESContinuationInput` without mutable global dependency |

Any denied-channel influence on recovered context, continuation input, identity,
REUSE/BLOCK choice, or success closure is an INVALID run.

## 8. P5 negative precedence and typed outputs

Evaluation is deterministic and stops at the first applicable class:

```text
1 ILLEGAL_CONTINUATION_BLOCK
2 MISSING_INFORMATION_BLOCK
3 STALE_INFORMATION_BLOCK
4 AMBIGUOUS_INFORMATION_BLOCK
```

Required decision record fields:

```text
schema_id = "D001-NEGATIVE-DECISION-V1"
case_id
trigger
mandatory_inventory_result
evidence_references_and_digests
precedence_reason
typed_decision
continuation_class = BLOCKED_DEFECT
secondary_defects[]
closure_artifact_digest
fallback_attempted = false
partial_continuation_created = false
semantic_repair_attempted = false
silent_recompute_attempted = false
stale_success_created = false
```

All negative paths are fail-closed. Secondary defects must be recorded but must
not change precedence.

## 9. P6 Carrier lifecycle checks

The Carrier contract is restricted to persistence, retrieval, integrity
verification, digest/identity binding, and lifecycle evidence. It must not
interpret semantics, generate `NEXT_ACTION`, assign REUSE/BLOCK authority,
infer PALACE state, repair invalid input, or assert physical authority.

Required lifecycle states:

```text
PERSISTED
PERSIST_FAILED
POST_WRITE_CHECK_FAILED
INVALID_RUN
```

Required invariants:

```text
LC-1 FINAL_SUCCESS exists only after S0, S1, S2, all seven fixture decisions,
     all SC checks, all identity checks, and all Carrier closure checks pass.
LC-2 persistence failure invalidates the run and creates no success artifact.
LC-3 post-write verification failure invalidates the run and persists failure.
LC-4 final process-result evidence reflects the final lifecycle, not an earlier
     optimistic status.
LC-5 success and failure artifacts remain separately typed.
LC-6 immutable evidence objects are write-once; correction requires a new
     governance object and a new evidence root.
```

## 10. P7 review and claim boundary

No automated outcome of this Package or S0–S2 may issue any of the following:

```text
PALACE equivalence;
integrated SimiGo proof;
general Execution State theorem;
production SimiGo validity;
LLM autonomy;
arbitrary IS, ES, schema, carrier, or scope validity;
E9 or EXP-004 authorization;
PIR reopening;
E8 or R01 closure change.
```

The only permitted future D claim remains bounded to a separately authorized,
fresh, pre-registered integrated configuration.

## 11. Required fixture roots and matrix

The only approved fixture parent is:

```text
integrated-es-palace/d001/fixtures/
```

The only approved case roots are:

```text
P-LAWFUL/
P-SETTLED/
P-BLOCKED/
N-MISSING/
N-STALE/
N-AMBIGUOUS/
N-ILLEGAL/
```

Each root must contain:

```text
fixture-manifest.json
information-closure/
provenance/
next-action/
carrier/
invocation.json
EXPECTED.json
```

Fixture roots must be mutually isolated, repository-relative, symlink-free, and
readable as data. They must not contain absolute paths, external dependencies,
network references, expected verdicts in the opaque locator, or canonical IS
state.

### 11.1 Positive cases

| Case | Registered trigger | Required terminal state | Decision |
| --- | --- | --- | --- |
| P-LAWFUL | complete current lawful closure with one registered lawful `NEXT_ACTION` | `SETTLED_CONTINUATION` after lawful continuation | `CONTINUE` |
| P-SETTLED | existing identity and all six REUSE conditions match | `SETTLED_CONTINUATION` | `REUSE` |
| P-BLOCKED | lawful current closure and registered blocking condition | `BLOCKED_LAWFUL_CONTINUATION` | `BLOCK` |

### 11.2 Negative cases

| Case | Registered trigger | Required typed decision | Precedence reason |
| --- | --- | --- | --- |
| N-MISSING | mandatory inventory object, mapping, revision, digest, or pointer is absent/unresolvable | `MISSING_INFORMATION_BLOCK` | legality cannot be determined |
| N-STALE | mandatory evidence is present but invalidated, expired, superseded, or outside revision window | `STALE_INFORMATION_BLOCK` | present evidence is not current |
| N-AMBIGUOUS | valid current evidence yields zero or conflicting pointers/mappings | `AMBIGUOUS_INFORMATION_BLOCK` | valid evidence cannot select one lawful continuation |
| N-ILLEGAL | present evidence proves boundary, authority, or identity violation | `ILLEGAL_CONTINUATION_BLOCK` | violation is proven by present evidence |

Every case must bind trigger, typed decision, identity/digest expectation,
precedence reason, closure artifact reference, and the explicit assertions:

```text
no fallback guess;
no partial continuation;
no semantic repair;
no silent recompute;
no stale-success persistence.
```

## 12. S0–S2 validation gates

### 12.1 S0 fresh-entry preflight

A future Run Manifest instance must prove all of the following before S0 PASS:

```text
PF-1 current worktree is clean;
PF-2 current branch and origin/main resolve to the registered canonical commit;
PF-3 package, manifest contract, request, frozen design, and acceptance ruling
     paths exist, parse, and match registered SHA-256 digests;
PF-4 implementation root and fixture parent are exactly approved;
PF-5 no preexisting destination evidence object is overwritten;
PF-6 fixture roots are isolated, symlink-free, repository-relative, and
     digest-complete;
PF-7 implementation manifest binds Python version, standard-library-only policy,
     schemas, module paths, and SC-1–SC-8;
PF-8 stage is `IMPLEMENTATION_FIXTURE_PREPARATION_ONLY`;
PF-9 integrated experiment mode is absent and refused;
PF-10 no canonical IS mutation path is opened.
```

### 12.2 S0–S2 PASS

`PREPARATION_VALIDATION_PASS` requires:

```text
1 ten P1 families mechanically complete in every fixture;
2 P2 schemas validate with exact authority separation;
3 P3 identities and digests are deterministic;
4 SC-1 through SC-8 pass;
5 P5 precedence produces the seven registered decisions exactly;
6 P6 lifecycle evidence is complete and write-once;
7 E8 + R01 remain non-composing predecessor evidence;
8 no forbidden claim, experiment claim, or equivalence claim exists;
9 canonical IS remains unchanged;
10 SHA256SUMS exactly covers the evidence tree.
```

Any missing check, unexpected extra semantic object, digest mismatch, path
escape, symlink, stale status, duplicate success/failure aggregate, or attempt to
rewrite evidence yields:

```text
PREPARATION_VALIDATION_FAIL
```

If a required evidence object cannot be interpreted, is internally inconsistent,
or lifecycle state cannot be established, the result is:

```text
PREPARATION_VALIDATION_INVALID
```

`FAIL` records an evaluated adverse condition. `INVALID` records inability to
establish a trustworthy result. Neither may be upgraded to success.

## 13. Evidence destinations and write-once closure

The only approved evidence parent is:

```text
docs/02-evidence/integrated-es-palace-d001-validation-v1/
```

The only approved evidence objects are:

```text
RUN_MANIFEST_INSTANCE.json
PREFLIGHT.json
IMPLEMENTATION_SELF_CHECK.json
FIXTURE_PREPARATION.json
PREPARATION_VALIDATION_RECORD.json
CARRIER_LIFECYCLE_RECORD.json
NEGATIVE_DECISIONS.json
IDENTITY_CHECKS.json
EVIDENCE_SHA256SUMS
```

Rules:

```text
EV-1 every JSON object is canonical, parseable, schema-bound, and digest-bound;
EV-2 every write-once object is absent immediately before creation;
EV-3 creation is atomic from temporary storage outside the evidence tree;
EV-4 an existing destination object causes INVALID;
EV-5 no symlink may occur in the evidence tree;
EV-6 EVIDENCE_SHA256SUMS is written last and must cover every other evidence
     object exactly once;
EV-7 correction requires a new Run Manifest instance and new evidence parent.
```

## 14. Explicit prohibitions

This Package does not authorize:

```text
implementation artifact creation before separate Human acceptance;
fixture creation or mutation before separate Human acceptance;
integrated experiment execution;
canonical IS mutation;
PIR reopening;
E9 or Database-Carrier campaign work;
EXP-004;
CarrierSQLite semantic change;
E8 formal ruling change;
R01 closure change;
P1–P7 semantic change;
PALACE equivalence claim;
general Execution State theorem;
integrated SimiGo proof;
production SimiGo validity;
LLM autonomy;
experiment budget consumption;
observer campaign budget consumption;
automatic Run Manifest approval;
automatic transition from preparation validation to experiment.
```

## 15. Decision requested

Human review must return exactly one ruling:

```text
ACCEPT   permit only a separate, explicitly recorded implementation / fixture
         preparation stage under the frozen Package boundary;
REVISE   require a new reviewed package revision;
REJECT   close this package pathway without implementation or fixture work.
```

ACCEPT does not approve the Run Manifest instance, authorize execution of S2,
authorize integrated experiment execution, or broaden any preserved state.
