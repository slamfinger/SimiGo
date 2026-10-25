# Minimal PIR Probe — v0.1 Design

> **Status:** DESIGN V0.1 CONDITIONAL PASS — SUPERSEDED BY V0.2 — IMPLEMENTATION / EXPERIMENT / FIXTURE NOT AUTHORIZED
> **Date:** 2026-10-06
> **Commissioned by:** PIR Design v0.2 + Clarification Addendum acceptance
> **Accepted design basis:** PIR Design v0.2 + Clarification Addendum at `c50978a`
> **Core question:** with large Information Space and small effective Query Scope, can SimiGo complete scope-bound reconciliation and form a Fresh Closure within `W_latency` without paying whole-Information-Space cost?
> **Review ruling:** CONDITIONAL PASS; see `docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_MINIMAL_PIR_PROBE_DESIGN_V0.1_REVIEW_RULING_20261006.md`.
> **Superseded by:** `docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_MINIMAL_PIR_PROBE_DESIGN_V0.2_20261006.md`.

## 1. Commission boundary

This document is design only.

It does not authorize:

```text
implementation;
fixture creation;
filesystem access;
experiment execution;
IS update execution;
SimiGo code change;
U-A / Manifest / UA / PB / Frozen Contract change;
user-file access or mutation.
```

It commissions only a reviewable experimental protocol.

## 2. Research question

```text
When Information Space is large and the current Query Scope is small,
can SimiGo resolve the effective scope, reconcile only its declared Physical
Scope, and form a Fresh Information Closure within W_latency — with cost
driven by R / P rather than N?
```

Symbols:

```text
N          total registered Information objects before query
R          accepted Information Scope size
P          bounded Physical Scope candidates exposed to reconciliation
M          relevant planted physical changes
W_age      observable freshness age threshold
W_latency  query-to-Fresh-Closure latency budget
```

## 3. Inherited definitions

This probe inherits PIR Design v0.2 and its Clarification Addendum:

```text
Query Scope = Information Scope + Physical Scope.
Scope Resolution and Physical Reconciliation are measured separately.
ICAC is a cost vector, not a weighted scalar.
W_age and W_latency are independent.
HOT/COLD is request-relative.
Information Space remains passive.
Reconciliation Sub-Agent has no business-judgment authority.
```

## 4. Initial shape, not final authorization

The initial design shape is:

```text
E-L  N=10,000, R=20, M=5
E-S  N=20,     R=20, M=5
```

`E-L` tests the large-space case. `E-S` is the paired small-space control with
the same relevant scope and planted changes.

Final numeric values, including `W_age`, `W_latency`, tolerance, and exact
change pattern, must be fixed in a separately reviewed fixture/run manifest.

## 5. Fixture domain

If later authorized, fixtures must be synthetic controlled objects in isolated
directories. They must not use user business files.

Each controlled object record has:

```text
stable object identifier;
registered Information identity;
registered locator;
content digest;
size/metadata fields;
controlled last-lawful-observation timestamp;
fixture scope tag;
planned change class.
```

The fixture harness may represent physical state as controlled file records.
If actual files are later authorized, they must still be synthetic and isolated.

## 6. Query Scope structure

The measured path receives only:

```text
query identifier;
freshness policy;
existing Information Space / fixture registry;
declared Physical Scope descriptor;
summary/index candidate source;
reconstruction output path.
```

It does not receive:

```text
planted-change list;
ground-truth relevant set;
expected verdicts;
evaluation oracle output;
fixture role;
control-side expected cost;
conversation or agent notes.
```

Query Scope is:

```text
Information Scope:
  known registered objects selected from N through index/summary/exact
  candidate sources.

Physical Scope:
  bounded locator set or descriptor for the accepted Information Scope.
```

The measured path must not scan unrelated objects to discover scope.

## 7. Change planting plan

For each paired fixture, plant exactly:

```text
M=5 relevant changes among R=20:
  2 × PC-MODIFY content digest;
  1 × PC-MODIFY policy-required metadata;
  1 × PC-DELETE;
  1 × PC-MOVE / PC-RENAME.
```

Rules:

```text
all M changes occur within R;
no unregistered-create case is required in v0.1;
outside-scope objects remain unchanged in the paired baseline;
each change receives a controlled observation timestamp in the fixture event
ledger;
the measured path does not receive this ledger.
```

`PC-CREATE` is intentionally deferred. Discovering unregistered objects inside
Physical Scope requires a later, separately reviewed extension.

## 8. Measured phases

The measured path must record these phases separately:

```text
P-A  Query / policy load
P-B  Information Scope Resolution:
       N → index/summary/exact candidates → accepted Information Scope R
P-C  Physical Scope assembly:
       accepted R → bounded Physical Scope candidates P
P-D  Physical Reconciliation:
       P → typed observations and freshness verdicts
P-E  Fresh Closure reconstruction:
       reconciled observations + required references → Fresh Closure
```

No phase may iterate unrelated objects as a normal query step. Opaque index
internals may be recorded separately, but the protocol must distinguish explicit
object touches from index implementation cost.

## 9. Reconciliation operations

For every accepted object, perform only policy-required checks:

```text
locator resolution;
existence / deletion test;
identity / locator correspondence;
content digest where required;
policy-required metadata comparison;
move/rename correspondence under the registered rule.
```

Typed verdicts:

```text
FRESH_WITHIN_WINDOW
STALE_BEYOND_WINDOW
PHYSICALLY_CHANGED
PHYSICALLY_DELETED
PHYSICALLY_MOVED
CONFLICT
INDETERMINATE
```

Missing evidence is `INDETERMINATE`, not a semantic guess.

## 10. Observable W_age rule

The probe must not claim to know the metaphysical instant when the physical
world changed.

Use only observable controlled timestamps:

```text
T_last_lawful_observation
  the timestamp of the last lawful controlled physical observation in the
  fixture event ledger.

T_query_reconciliation
  the timestamp of the current policy-scoped physical check.

observable_age =
  T_query_reconciliation − T_last_lawful_observation.
```

Pass requires a current lawful reconciliation observation for every accepted
object and:

```text
observable_age <= W_age
```

The numeric `W_age` must be fixed in the fixture/run manifest.

## 11. W_latency rule

`W_latency` is measured from:

```text
T_query_receipt
```

to:

```text
T_fresh_closure_available
```

It includes all measured phases P-A through P-E. It excludes fixture generation
and evaluation.

The numeric `W_latency` must be fixed in the fixture/run manifest and applied
equally to `E-L` and `E-S`.

## 12. ICAC vector

Each phase must emit the ICAC vector from the Clarification Addendum:

```json
{
  "latency_ms": {
    "scope_resolution": 0,
    "physical_scope_assembly": 0,
    "physical_reconciliation": 0,
    "is_update": 0,
    "closure_reconstruction": 0
  },
  "objects": {
    "total_registered_n": 0,
    "index_candidates": 0,
    "information_scope_accepted": 0,
    "physical_candidates": 0,
    "physical_checks": 0,
    "changed_found": 0,
    "closure_references": 0,
    "unrelated_object_touches": 0
  },
  "bytes": {
    "payload_bytes_read": 0,
    "digest_bytes_read": 0
  },
  "syscalls": {
    "stat": 0,
    "open": 0,
    "read": 0
  },
  "updates": {
    "is_update_records": 0
  },
  "blockers": {
    "typed_blocker_count": 0
  }
}
```

For v0.1, `is_update` is expected to be `NOT_AUTHORIZED / ZERO`. Fresh Closure
is reconstructed in memory unless IS update is separately authorized.

## 13. Controls

The paired design requires:

```text
C-SCALE
  E-L versus E-S with identical R/M/change pattern.

C-NOCHANGE
  same R with M=0; expected zero PC-* observations and complete Fresh Closure.

C-ORACLE-ISOLATION
  oracle knows planted truth; measured path does not.

C-SIDE-CHANNEL
  measured path receives no expected verdicts, planted-change list, or
  control-side cost target.
```

## 14. Evaluation join

After measured output, the evaluation oracle joins:

```text
instance → planted changes;
instance → expected relevant scope;
instance → expected typed verdicts;
instance → expected cost bounds.
```

It computes:

```text
true positive changes;
false negative changes;
false positive changes;
scope misses;
scope false positives;
unrelated touches;
phase latency vector;
W_age pass/fail;
W_latency pass/fail.
```

The measured path must not perform this join.

## 15. PASS criteria

For both `E-L` and `E-S`, PASS requires:

```text
PC-1  accepted Information Scope contains exactly R objects.
PC-2  all M planted relevant changes are detected with correct typed verdicts.
PC-3  no false positive physical change is reported for unchanged accepted
      objects.
PC-4  deleted and moved objects produce typed blockers, not stale continuation.
PC-5  every accepted object has a current lawful reconciliation observation.
PC-6  observable_age <= W_age for every accepted object.
PC-7  query-to-Fresh-Closure latency <= W_latency.
PC-8  unrelated_object_touches = 0 outside explicitly recorded index internals.
PC-9  physical_checks <= P and P is bounded by accepted scope, not N.
PC-10 no oracle or side-channel input enters the measured path.
```

`C-SCALE` PASS requires:

```text
PC-11  E-L and E-S have the same R/M correctness outcomes.
PC-12  phase cost vectors are reported separately.
PC-13  cost growth from E-S to E-L is attributable only to recorded index or
       declared structural costs, not to reconciliation over all N objects.
```

Numeric scaling tolerance and hardware policy must be fixed in the run manifest.

## 16. FAIL conditions

```text
FT-P01  relevant scope object missed.
FT-P02  planted relevant change missed.
FT-P03  unchanged object reported changed.
FT-P04  deleted or moved object treated as current/fresh.
FT-P05  stale or guessed state treated as fresh.
FT-P06  measured path reads planted-change ledger or oracle.
FT-P07  physical reconciliation touches all N objects.
FT-P08  unrelated object state is updated or materially inspected.
FT-P09  observable_age exceeds W_age.
FT-P10  latency exceeds W_latency.
FT-P11  ICAC vector merges heterogeneous units into a scalar.
FT-P12  fixture/harness defect prevents reliable measurement.
FT-P13  implementation or IS mutation occurs without separate authorization.
```

## 17. INDETERMINATE conditions

```text
IT-P01  fixture manifest checksum mismatch.
IT-P02  clock source is not monotonic or is unavailable.
IT-P03  controlled timestamp evidence is incomplete.
IT-P04  index implementation makes cost attribution impossible.
IT-P05  environment changes between paired runs.
IT-P06  protocol violation occurs.
```

## 18. Evidence requirements

If later authorized, each run must preserve:

```text
EV-P01 fixture manifest and checksums;
EV-P02 query/freshness policy;
EV-P03 blinded measured-path input;
EV-P04 oracle ledger sealed before execution;
EV-P05 phase-separated ICAC vector;
EV-P06 scope resolution result;
EV-P07 physical reconciliation observations;
EV-P08 Fresh Closure;
EV-P09 W_age calculations;
EV-P10 W_latency calculation;
EV-P11 evaluation join;
EV-P12 false positives / false negatives;
EV-P13 paired E-L/E-S comparison;
EV-P14 side-channel denial record;
EV-P15 raw logs sufficient to audit object touches.
```

## 19. Decision requested

This document requests Human design review only.

```text
ACCEPT PROBE DESIGN       permit a separately reviewed fixture/run manifest;
                          still no implementation or execution.
REVISE PROBE DESIGN       return with registered defects.
REJECT PROBE DESIGN       do not proceed.
```

No implementation, fixture creation, filesystem access, or experiment is
authorized by this document.
