# PALACE / ES — PIR Design Review Reconciliation Record

> **Status:** RECONCILIATION COMPLETE — NO NEW PIR DESIGN REVIEW REQUIRED
> **Date:** 2026-10-08
> **Registered predecessor gap:** PIR — Physical–Information Reconciliation
> **Trigger:** post-E8 routing after bounded CarrierSQLite equivalence was established
> **E8 bounded equivalence:** ESTABLISHED
> **PIR implementation:** NOT AUTHORIZED
> **PIR experiment:** NOT AUTHORIZED
> **PIR fixture creation:** NOT AUTHORIZED

## 1. Purpose

Reconcile the already-completed PIR design-review chain with the newly completed
E8 bounded CarrierSQLite equivalence line. This record does **not** reopen the
PIR design review and does **not** commission implementation, fixtures, or an
experiment.

## 2. Canonical PIR review status

```text
PIR Design v0.1        SUPERSEDED / RETAINED AS AUDIT INPUT;
Human direction        Query-Priority Reconciliation ACCEPTED;
PIR Design v0.2        CONDITIONAL PASS;
Clarification Addendum ACCEPTED;
PIR Design v0.2        ACCEPTED;
Minimal PIR Probe v0.1 CONDITIONAL PASS;
Minimal PIR Probe v0.2 DELIVERED FOR HUMAN REVIEW / PAUSED;
PIR implementation     NOT AUTHORIZED;
PIR experiment         NOT AUTHORIZED;
PIR fixture creation   NOT AUTHORIZED.
```

The prior Human rulings already resolved the requested design-review object.
Therefore this record is a reconciliation and current-gate statement, not a new
design ruling.

## 3. Required question — physical source

The accepted PIR model bounds physical facts to a pre-declared local filesystem
Physical Scope. Relevant facts are limited to typed observations needed for the
current query:

```text
PC-CREATE
PC-MODIFY
PC-DELETE
PC-MOVE / PC-RENAME
```

Required observable facts include registered locator status, controlled
content/metadata checks, identity/revision/correlation evidence, candidate
membership, observation age, and the pre-declared freshness policy. Facts outside
the declared Physical Scope do not create an incomplete reconciliation for that
query.

## 4. Required question — information representation

PALACE / Information Space already represents the continuation-relevant objects
through existing UA/U-A primitives:

```text
Information;
CarrierRecord;
NEXT_ACTION;
CC-5 mapping;
Information-to-Information Relation semantics when needed;
Representation Identity;
existing provenance and revision rules.
```

PIR must not introduce new semantic entities, new CarrierRecord kinds, new
RelationCore rules, a new relation engine, a new Super Store, semantic ranking
authority, MCP, or a new backend.

## 5. Required question — reconciliation mapping

The accepted path is Query-Priority Reconciliation:

```text
Query
  → Execution State
  → Information Scope Resolution
  → Physical Scope Resolution / bounded candidate discovery
  → Candidate Retrieval
  → Physical Reconciliation
  → Fresh Closure
  → Main Agent / continuation
```

The accepted clarifications require:

```text
Query Scope = Information Scope + Physical Scope;
Scope Resolution and Physical Reconciliation measured separately;
typed verdicts for every accepted object;
auditable candidate / accepted / verified / rejected / deferred records;
Fresh Closure or typed blockers;
no whole-space scan and no unrelated-object touches.
```

## 6. Required question — loss and ambiguity

PIR must fail closed rather than guess:

```text
unresolved locator ≠ proven deletion unless policy checks prove it;
missing old locator with zero accepted candidate → PHYSICALLY_DELETED;
missing old locator with multiple candidates → CONFLICT or INDETERMINATE;
stale or guessed state must not become FRESH;
W_obs_age and W_latency are independently bounded;
unregistered objects outside Physical Scope are not silently adopted.
```

Fresh Closure must carry typed blockers such as
`STALE_BEYOND_WINDOW`, `PHYSICALLY_CHANGED`, `PHYSICALLY_DELETED`,
`PHYSICALLY_MOVED`, `CREATED_UNREGISTERED`, `CONFLICT`, or `INDETERMINATE`.

## 7. Required question — update semantics

Information Space remains passive. PIR is query-time and scope-priority, not
continuous synchronization.

```text
HOT / QUERY PATH = scope-relevant objects requiring physical reconciliation;
COLD / BACKGROUND = deferred, historical, unrelated, or low-priority state.
```

HOT/COLD is request-relative, not a new backend, store, schema, or consistency
protocol. IS update is not authorized by the current design gate. If separately
authorized later, update records must be provenance-bearing and auditable.

## 8. Required question — authority boundary

```text
Physical World  supplies observations only;
Information Space remains passive and lawful;
Reconciliation Sub-Agent performs constrained observation/correlation;
Execution State orchestrates query/continuation but does not mutate user files;
Carrier layer provides durable storage/integrity, not semantic interpretation;
model or semantic similarity must not replace physical evidence.
```

No business judgment, no guessed physical fact, and no carrier-specific behavior
may become a PIR authority.

## 9. Relation to E8 bounded equivalence

E8 established bounded CarrierSQLite equivalence for the exact implementation,
database, objects, adapter runtime, invocation and O0–O5 configuration. It does
not establish PIR, PALACE equivalence, or whole-SimiGo continuation.

Conversely, PIR addresses a different gap:

```text
physical/material state may change after a previously lawful closure exists.
```

Therefore E8 and Probe R01 are complementary:

```text
E8  = bounded CarrierSQLite carrier equivalence;
R01 = bounded continuation sufficiency when lawful closure exists;
PIR = freshness/reconciliation when physical state may have changed.
```

## 10. Current gate

```text
PIR Design Review                 ALREADY COMPLETE;
PIR Design v0.2 + Addendum        ACCEPTED;
Minimal PIR Probe v0.2            DELIVERED FOR REVIEW / PAUSED;
PIR implementation                NOT AUTHORIZED;
PIR experiment                    NOT AUTHORIZED;
PIR fixture creation              NOT AUTHORIZED;
automatic resumption              FORBIDDEN.
```

The next lawful object is a separate explicit Human decision whether to resume
review of Minimal PIR Probe v0.2 or keep the PIR branch paused. This record does
not make that decision.

## 11. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing this
record; later modification creates a new content address and voids this
reconciliation record.
```
