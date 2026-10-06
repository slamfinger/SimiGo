# CCVS-01 U-A — Code-Level Verification Report (Audit Round 2)

> **Status:** SIX-FOCUS CODE-LEVEL VERIFICATION EXECUTED — 3 SECOND-LAYER DEFECTS FOUND AND CORRECTED — ALL VERIFICATION TESTS GREEN
> **Date:** 2026-10-06
> **Basis:** Human audit-round-2 directive (six focus areas; no new mechanisms; verification only)
> **Instruments:** `Tests/CarrierSQLiteTests/UAVerificationTests.swift` (10 tests) + full-line FTS touchpoint trace + targeted MA-DS-1 re-run
> **Gate C:** remains STARTED / OPEN — this report is input to the Human's next code-level review; no acceptance claimed

## 0. Executive result

```text
Focus 1 (carrier_id chain)     → 2 second-layer defects FOUND and FIXED (F-1, F-2/UA-IF-3b)
Focus 2 (migration CC-7)       → verified: no free clean PASS; authority untouched; rebuild restores promised coverage
Focus 3 (replay boundary)      → verified: six-field strictness; effects exactly bounded; object provenance singular
Focus 4 (conflict atomicity)   → verified: evidence committed outside the rolled-back work; state machine continues
Focus 5 (legacy NULL boundary) → verified: NULL never attributed to a carrier; legacy writes confined to their own rows
Focus 6 (concurrency battery)  → 5 scenarios: all settle legally; no corruption; provenance complete
Defects this round             → F-1, F-2 (UA-IF-3b), plus a NULL-read crash in the unscoped search path (fixed pre-commit)
Test status                    → 27/27 target tests (4 CarrierSQLite + 13 UAOperation + 10 UAVerification);
                                 A1 conformance 10/10 no-regression; targeted MA-DS-1 re-run 13/13 VALID
```

## 1. Focus 1 — carrier_id through the full chain

Full FTS touchpoint trace (every statement that touches the derived
search layer, post-correction):

```text
uaIndexDocument            DELETE … WHERE information_id=? AND carrier_id=?
                           INSERT … (information_id, carrier_id, …)     [pair-scoped]
uaRebuildIndex             DELETE FROM search_fts (whole index — full
                           rebuild by definition) + INSERT per doc with
                           explicit carrier_id                          [pair-scoped rows]
uaSearchScoped             MATCH + optional carrier_id=? filter          [pair-scoped read]
uaIndexStaleness           join on (information_id, carrier_id)          [pair-scoped]
runtime upsert/delete      … AND carrier_id IS NULL                      [legacy-scoped, UA-IF-3b]
runtime clear/rebuild      whole-index (NULL rows only in scope of the
                           legacy path's own documents)                  [registered boundary]
MA-DS-1 coverageOf         searchScoped aggregation per (info|carrier)   [pair-scoped, F-1 fixed]
```

Second-layer defects found exactly as the audit predicted ("writes
carrier-scoped, deletes/coverage still information-scoped"):

```text
F-1  MA-DS-1 coverageOf compared coverage via the UNSCOPED search — an
     information-scoped comparison could mask a missing carrier-scoped row
     behind the other carrier's row.
     Fix: coverage aggregation via searchScoped at (information|carrier)
     granularity. (Runner/verification instrument.)

F-2  (= UA-IF-3b) Legacy runtime-path upsert/delete still deleted by
     information_id alone — a legacy operation would erase U-A
     carrier-scoped rows of the same information.
     Fix: legacy writes scoped to their own rows
     (`AND carrier_id IS NULL`).
     Correction-process note: the delete-side fix initially did not apply
     (pattern mismatch in the scripted edit); the verification test
     focus1 caught the surviving information-scoped DELETE and the fix
     was reapplied — the verification layer did its job.
```

Verification: `focus1LegacyWritesCannotEraseCarrierScopedRows` (legacy
upsert/delete never touch UA rows; UA rows survive), `focus1RebuildAndStalenessArePairScoped`
(advancing only carrier A flags exactly pair (A, info); rebuild restores
both pairs).

## 2. Focus 2 — FTS v2 migration satisfies CC-7

`focus2MigrationDiscardsDerivedStateWithoutTouchingAuthority` simulates a
pre-correction database (old FTS shape with legacy rows), then reopens:

```text
(a)  authority fingerprint byte-identical across the migration
     (carriers/revisions/representations/locators/relations/pins/
      session_events/mappings/ledger — none touched);
(b)  old derived state fully discarded — no ghost rows survive into v2;
(c)  the EMPTY index does NOT pass a rebuild-compare against the promised
     coverage — migration grants no free clean PASS (the gap is visible);
(d)  rebuild from the authority-derived document restores exactly the
     promised coverage; staleness clear.
```

Honest rebuild-completeness status carried from the registered record:
the LEGACY path's searchable text lives only in the derived FTS (P8 F7
architecture property) — after any whole-index loss the legacy path can
restore identity coverage only, i.e. its rebuild capability is
INCOMPLETE under the U-A hard gate. The UA path's searchable content is
extracted from authority-retained bytes, so its full-rebuild claim is
valid and is verified by rebuild-compare (S10/S13).

## 3. Focus 3 — Representation Identity replay boundary

The identical-registration check compares ALL SIX immutable properties —
`representation_id` (the lookup key) plus `information_id`, `revision_id`,
`digest`, `byte_count`, `media_type`. It is NOT digest-only: the test
proves that the same R with the same digest but a different media_type is
a typed conflict.

`focus3IdempotentReplayChangesNothingButItsOwnAttemptRecord` verifies the
effect bound exactly:

```text
unchanged: representation row (digest + created_at), entity bytes,
           carrier revision, mapping rows;
appended:  exactly ONE ledger row (the no-op attempt's own record,
           outcome REPLAYED);
singular:  the object's registration provenance (the original APPLIED
           row for R-replay) — never duplicated.
```

Provenance layering made explicit: OBJECT provenance (how this
representation came to exist) is singular; ATTEMPT provenance (who tried
what, including no-op duplicates) is append-only by design — conflating
the two would either hide operations (I21 violation) or forbid retries.

## 4. Focus 4 — CONFLICT atomicity

Code pattern (both the MA-3 stale path and the UA-IF-4 representation
path): the main transaction performs READS ONLY on the conflict
detection route and returns a typed result; the evidence ledger row is
written in a SEPARATE committed transaction; the typed error is thrown
after that commit. The first-round bug pattern (evidence inside the
transaction that then rolls back) is structurally absent, and the
pattern is now guarded by tests that assert the evidence row EXISTS
after the throw:

```text
focus4ConflictEvidenceSurvivesAndStateContinues:
  - CONFLICT ledger row present after the typed error;
  - carrier revision unchanged by the conflict;
  - a NEW valid revise proceeds afterwards (state machine continues);
  - dangling provenance 0.
representationIdentityConflictIsTyped (round-1 regression) retains the
  same assertions.
```

## 5. Focus 5 — A1 legacy NULL boundary

```text
- Scoped queries (carrier_id=?) NEVER match NULL rows — SQL NULL
  comparison semantics put legacy rows outside every carrier scope;
- unscoped reads (carrierID: nil) surface legacy rows with an EMPTY
  carrier scope, explicitly marked — never attributed to a carrier;
  (this assertion forced a NULL-safe read fix in uaSearchScoped — a
  text() on a NULL carrier_id would crash; fixed pre-commit and
  registered as part of UA-IF-3b);
- staleness and rebuild bookkeeping join on build rows only — NULL rows
  carry no build rows and no watermark;
- legacy upsert/delete confined to NULL rows (UA-IF-3b) — the legacy
  path can no longer erase U-A state;
- whole-index rebuilds remain whole-index (a rebuild replaces the entire
  derived index). Mixed-path rebuild ownership is a registered
  composition boundary for U-2 integration; round one exercises one
  path at a time.
```

## 6. Focus 6 — concurrency battery

Five scenarios (single actor-owned connection is the implemented
composition property; the battery verifies legal linearization and
state consistency under concurrent task interleaving):

```text
1  rebuild vs scoped indexing        → no corruption; surviving index is
                                       a legal linearization (full
                                       rebuild replaces the whole index;
                                       later incremental writes re-add
                                       their own pair); staleness
                                       computable throughout.
2  two carriers, same information    → both carrier-scoped representations
   (concurrent indexDocument)          coexist; no cross-erase.
3  representation conflict racing    → exactly one bump lands (the normal
   a normal revision                   revision); the conflict leaves a
                                       CONFLICT evidence row; provenance
                                       complete; final revision == base+1.
4  replay racing a new operation     → replay returns the recorded outcome;
                                       the new operation appends exactly one
                                       event; no duplicates; sequences
                                       contiguous.
5  search during rebuild             → every observed view is a complete
                                       committed state (never a partial row
                                       set — the rebuild is one
                                       transaction under WAL isolation).
All: dangling provenance 0.
```

## 7. Verification-round correction ledger

```text
F-1   MA-DS-1 coverage comparison → carrier-scoped aggregation
      (verification instrument; no mechanism change).
UA-IF-3b (F-2) legacy runtime upsert/delete confined to NULL-carrier rows
      (second-layer completion of UA-IF-3; scoping correction, no new
      mechanism).
F-3   uaSearchScoped NULL-carrier read → NULL-safe (empty scope marker)
      (crash fix caught by the verification suite pre-commit).
Process note: the F-2 delete-side fix initially did not apply in the
      scripted edit; focus1 caught the surviving unscoped DELETE and the
      fix was reapplied — recorded as evidence that the verification
      layer catches exactly this class of second-layer miss.
```

## 8. Status

```text
Gate C                    STARTED / OPEN (unchanged)
U-A implementation        VERIFIED per the six focus areas; corrections
                          from this round are regression-covered; the
                          package is resubmitted for the Human's
                          code-level review.
Manifest v1.1 / PB v1.2 / Frozen Contracts   UNCHANGED
MA-DS-1 workload          VALID (13/13, targeted re-run after corrections)
No new mechanisms         — this round added verification instruments,
                          two scoping corrections inside the UA-IF-3
                          envelope, and one NULL-read crash fix.
```
