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

## 9. Correction round 3 — Human code-level re-audit (2026-10-06)

The Human's second code-level review found one more substantive
second-layer scope gap and two verification-strength weaknesses. This
round executed tasks A–D exactly: no new mechanisms, no Manifest change.

### 9.1 Result 1 — legacy clear/rebuild ownership (was BLOCKER): FIXED

```text
Audit finding: F-2 covered upsert/delete only; legacy clear() and
  rebuild() still executed `DELETE FROM search_fts` unscoped — a legacy
  rebuild would erase every U-A carrier-scoped row while rebuilding its
  own NULL-scope documents.
Fix (UA-IF-3c):
  legacy clear()     → DELETE … WHERE carrier_id IS NULL
  legacy rebuild()   → DELETE … WHERE carrier_id IS NULL (replaces only
                       the legacy portion of the index)
  uaRebuildIndex     → DELETE … WHERE carrier_id IS NOT NULL (mirror
                       symmetry: a U-A rebuild never erases legacy rows)
Regression (new):
  focus1ALegacyClearAndRebuildNeverEraseCarrierScopedRows — UA rows
  (I1×A, I1×B) survive legacy upsert, legacy delete, legacy CLEAR and
  legacy REBUILD; after a legacy rebuild the legacy portion is exactly
  the rebuilt result; after a UA rebuild the legacy portion survives
  (mirror). PASS.
Complete unscoped-DELETE sweep: `DELETE FROM search_fts` now has ZERO
  unscoped occurrences across both paths.
```

### 9.2 Result 2 — replay external side-effect: PROBED (characterized; Human ruling required, no solution designed)

`focusCReplayAndConflictEntitySideEffectProbe` characterizes the code
order `durableWrite → ledger/revision/identity checks`:

```text
Probe 1  OP1(P1) → APPLIED;  OP1(P2) → REPLAYED semantics
  registry delta: revision unchanged; ledger for OP1 unchanged (one
    APPLIED row; no duplicate); mappings unchanged;
  EXTERNAL side effect: entity bytes of P2 ARE durably written and
    remain as an UNREFERENCED entity (integrity-report orphan detail
    matches digest(P2)).
Probe 2  stale-revision attempt with fresh payload P3
  → typed staleRevision; EXTERNAL side effect: P3 entity orphan present.
Probe 3  representation-conflict attempt with fresh payload P4
  → typed conflictingDuplicateRepresentation; EXTERNAL side effect: P4
    entity orphan present.
Registry-side invariants strict across all three probes (dangling
  provenance 0).
```

ADDITIONAL FINDING (caught by the probe): the two replay paths report
retries inconsistently —

```text
compound revise, same operation_id → returns the RECORDED outcome
  (.applied) — literal manifest §4.1 "returns the RECORDED outcome";
session append, same operation_id → returns an explicit .replayed
  marker (ma7 regression).
```

Registry delta is zero under both conventions. Which convention is
canonical (and whether replay preflight should precede the durable
entity write, or the orphan window is allowed with prescribed cleanup
semantics) is a HUMAN RULING — deliberately not designed this round.

### 9.3 Result 3 — concurrency oracle strength: STRENGTHENED

```text
focus6SearchDuringRebuildSeesOnlyOldCompleteOrNewComplete — strict
  atomic-visibility oracle: BEFORE = {I1×A, I2×C}, AFTER = {I1×A, I3×C}
  (distinguishable); every concurrent reader observation must equal
  BEFORE or AFTER exactly — ∅, partial (one pair) and mixed (three
  pairs) all fail. PASS after fixing the instrument itself: the rebuild
  task's placeholder empty-set return was being counted as an
  observation (a test-construction bug, registered honestly — it was
  the ORACLE that was wrong, not the mechanism).
focus6RebuildAndScopedIndexInterleaveLegally — racing writes now
  content/revision-distinguishable (v1 by rebuild, v2 by racing index);
  exactly one row survives, revision identifies the linearization; the
  weak `staleness.isEmpty || count <= 2` assertion replaced by a strict
  close-out (final rebuild → staleness MUST be empty).
```

### 9.4 Verification status after round 3

```text
UAVerificationTests   12/12 PASS (10 + ownership regression + probe)
UAOperationTests      13/13 PASS
CarrierSQLiteTests     4/4 PASS — A1 conformance 10/10 no-regression
Full package          29/29 target tests green
Targeted MA-DS-1      13/13 within manifest semantics — overall VALID
                      (run 9; classifications unchanged)
Gate C                STARTED / OPEN — not closed
U-A implementation    NOT ACCEPTED (pending Human review of: UA-IF-3c
                      fix, replay side-effect ruling, strengthened
                      oracles)
```
