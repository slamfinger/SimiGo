# Minimal PIR Probe v0.2 — Experiment Authorization Package / Run Manifest RM-001

> **Status:** PACKAGE / RUN MANIFEST SUBMITTED FOR HUMAN REVIEW
> **Date:** 2026-10-08
> **Package / manifest ID:** `MINIMAL-PIR-V0.2-EXP-PKG-RM-001`
> **Governing Request v2.4:** `01108b2`
> **Candidate future run ID:** `MINIMAL-PIR-EXP-001` — NOT AUTHORIZED
> **Frozen design:** Minimal PIR Probe v0.2 = ACCEPT / DESIGN FROZEN

## 1. Authorization boundary

Acceptance of this package would approve only the reviewability of the declared
experimental boundary. It would **not** authorize:

```text
implementation;
fixture creation;
filesystem access trial;
experiment execution;
IS mutation;
semantic inference;
whole-space scan;
model similarity or best-guess correlation;
new semantic entity;
CarrierRecord / RelationCore / Super Store change;
MCP or remote API use;
Database-Carrier campaign;
E9;
old evidence reuse;
automatic equivalence.
```

A separate explicit Human authorization would be required after package
acceptance, and even then may authorize only the next staged step.

## 2. Frozen design basis

```text
Minimal PIR Probe v0.2 SHA256 = 94667081704f8e27bcd3bbb5cdd1685ee004adf8cf762fa27e24bb3edff23bd1;
Minimal PIR Probe v0.1 SHA256 = be3e3139941bbdcbcf4178a23186ca5d46f70aedb3ac0a576aebd15a7c73c136;
PIR Design v0.2 SHA256 = d409c0d718691520ed558ae92b4c711eb9ad85cb2fc0afb00f2e52459facd5b0;
Clarification Addendum SHA256 = 310a29a9ab631e04f21e513df7db40c20bfa2a181743a6ed8be1bded95792980;
canonical predecessor main = 6aaf4ef777a12db1b64eb164117c70c9b3c271d2.
```

The frozen authority is Minimal PIR Probe v0.2 = ACCEPT / DESIGN FROZEN.

## 3. Candidate run shapes — not authorized

```text
E-L        N=10,000; R=20; M=5;
E-S        N=20;     R=20; M=5;
C-NOCHANGE same paired scope; M=0.
```

These are controlled synthetic boundaries. If later authorized, fixtures must
be isolated, synthetic and non-user-facing.

## 4. Binding run windows

```text
W_obs_age  = 60,000 ms;
W_latency  = 5,000 ms;
clock      = monotonic where available; controlled timestamps otherwise;
window application is identical for E-L and E-S.
```

These values are submitted for Human review. They are not commissioned by this
package.

## 5. Identity and isolation

The measured path receives only:

```text
opaque query identifier;
opaque fixture instance ID;
approved freshness policy;
registered non-semantic object registry;
declared Physical Scope descriptor;
bounded index/summary candidate source;
approved Fresh Closure output path.
```

It must not receive:

```text
fixture role P-POS / N-A / N-B;
planted-change ledger;
ground-truth relevant set;
expected verdicts;
oracle output;
control-side cost target;
conversation or model notes.
```

## 6. Information Scope

For each run:

```text
R accepted Information Scope objects are resolved from N through the declared
non-semantic index/summary/exact-reference path.
```

Required record per accepted object:

```text
stable opaque object identifier;
registered Information identity;
registered locator;
content SHA256;
byte size;
controlled metadata fields required by policy;
last lawful observation timestamp;
declared required checks.
```

Discovery may not scan unrelated N objects.

## 7. Physical Scope and candidate pool

```text
Physical Scope is one isolated synthetic root per fixture instance.
Allowed objects are regular synthetic files only.
Symlinks, directories-as-objects, remote resources and user files are forbidden.
Object names are generated from opaque stable IDs, never roles or expected verdicts.
Declared roots/depth/exclusions are fixed before review acceptance.
P_declared is the candidate count exposed by the declared scope.
```

Candidate discovery is bounded listing of the declared root only. It must not
scan all N, traverse outside scope, use watchers, fuzzy search, semantic search,
model inference, MCP, or remote API.

## 8. Required counters

The Run Manifest must report separately:

```text
P_declared;
P_materialized;
physical_check_targets;
physical_observations;
physical_changes;
false_positive_changes;
false_negative_changes;
unrelated_physical_touches;
information_scope_accepted;
total_registered_n.
```

`P_materialized` may equal `R` as an observed result, not as a definition.

## 9. Physical reconciliation operations

Only these checks are allowed for each accepted object:

```text
locator resolution;
existence / deletion test;
identity / locator correspondence;
content digest where policy requires it;
policy-required metadata comparison;
MOVE/RENAME correlation under the pre-registered rule.
```

No semantic interpretation, business judgment, model inference, ranking, or
carrier interpretation is permitted.

## 10. Typed verdicts

Exactly these verdicts are permitted:

```text
FRESH_WITHIN_WINDOW;
STALE_BEYOND_WINDOW;
PHYSICALLY_CHANGED;
PHYSICALLY_DELETED;
PHYSICALLY_MOVED;
CONFLICT;
INDETERMINATE.
```

Missing or ambiguous evidence must become `CONFLICT` or `INDETERMINATE` as
pre-registered, never a best-guess fresh result.

## 11. Fresh Closure required fields

Fresh Closure must contain:

```text
opaque query identifier;
accepted Information Scope references;
per-object physical reconciliation verdict;
per-object observation and evidence references;
required relations or explicit missing-reference blockers;
typed unresolved blockers;
W_obs_age calculation;
W_latency calculation;
zero unrelated-touch attestation;
closure completeness status.
```

A Fresh Closure may be complete only when every accepted object has a typed
verdict and all mandatory preceding evidence is present. Otherwise it must
carry typed blockers.

## 12. MOVE / RENAME deterministic correlation

The declared rule is:

```text
old locator missing
  + exactly one allowed candidate in the declared Physical Scope
  + identical content SHA256
  + identical byte size
  + identical stable opaque object ID
  → PHYSICALLY_MOVED / PHYSICALLY_RENAMED;

old locator missing + zero accepted candidate
  → PHYSICALLY_DELETED;

old locator missing + multiple accepted candidates
  → CONFLICT.
```

Required evidence:

```text
old locator absence check;
candidate locator check;
candidate content SHA256 and size;
stable opaque object ID correspondence;
declaration that no other candidate was accepted.
```

Model similarity, filename intuition, business intent and post-hoc selection are
forbidden.

## 13. Negative and ambiguity cases

```text
N-A physical case: required registered locator is unresolved.
Expected: PHYSICALLY_DELETED plus typed blocker; never stale continuation.

N-B physical case: two declared candidates satisfy the correlation rule.
Expected: CONFLICT plus typed blocker; never deterministic best guess.

C-NOCHANGE: all R accepted objects remain unchanged.
Expected: R observations, zero physical changes, complete Fresh Closure.
```

These cases are pre-registered. Runtime mutation from a positive fixture is
forbidden.

## 14. Phase-separated attribution

Each run must report these phases separately:

```text
S0 policy load;
S1 Information Scope Resolution;
S2 Physical Scope assembly / candidate discovery;
S3 Candidate Retrieval / accepted-scope assembly;
S4 Physical Reconciliation;
S5 Fresh Closure reconstruction;
S6 IS update — permanently NOT AUTHORIZED in this package.
```

Each phase must emit the ICAC vector from the accepted Clarification Addendum.
Heterogeneous units must not be summed into a scalar.

Pre-registered attribution rule:

```text
N-dependent growth may be attributed only to Scope Resolution / Index,
Candidate Retrieval or declared structural registry overhead.

N-dependent growth may NOT be attributed to Physical Reconciliation.
Physical Reconciliation is scope-bounded only when physical_check_targets are
within declared Physical Scope, unrelated_physical_touches = 0, and check count
is bounded by P_materialized plus the pre-registered candidate-resolution
allowance.
```

## 15. Evidence destinations — if later authorized

```text
EV-P01  fixture manifests and checksums;
EV-P02  query/freshness policy;
EV-P03  blinded measured-path input;
EV-P04  sealed oracle ledger;
EV-P05  phase-separated ICAC vector;
EV-P06  Information Scope resolution result;
EV-P07  Physical Scope resolution result;
EV-P08  Physical Reconciliation observations;
EV-P09  W_obs_age calculations;
EV-P10  W_latency calculations;
EV-P11  Fresh Closure;
EV-P12  evaluation join;
EV-P13  false positives / false negatives;
EV-P14  paired E-L / E-S comparison;
EV-P15  side-channel denial record;
EV-P16  raw object-touch audit logs;
EV-P17  MOVE/RENAME correlation evidence;
EV-P18  observations-versus-changes count record.
```

Evidence creation is not authorized by this package.

## 16. Fail-closed stop rules

Immediate fail-closed is required if:

```text
any mandatory destination is missing, nonregular, symlinked or empty;
fixture checksum mismatches;
accepted Information Scope misses or exceeds R;
a planted relevant change is missed;
an unchanged object is reported changed;
deleted or moved state is treated fresh;
W_obs_age or W_latency is exceeded;
Physical Reconciliation touches all N objects;
unrelated_physical_touches ≠ 0;
oracle or side-channel input enters the measured path;
IS mutation occurs;
semantic inference replaces physical evidence;
implementation occurs without separate authorization.
```

No rerun, repair, evidence reconstruction or partial-package continuation is
authorized.

## 17. Human decisions requested

```text
ACCEPT PACKAGE / RUN MANIFEST;
REVISE PACKAGE / RUN MANIFEST;
REJECT PACKAGE / RUN MANIFEST.
```

Acceptance does not authorize implementation, fixture creation, experiment
execution, IS mutation, or budget consumption. Any next staged authorization
must be separate and explicit.

## 18. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
package; later modification creates a new content address and voids this
submission.
```
