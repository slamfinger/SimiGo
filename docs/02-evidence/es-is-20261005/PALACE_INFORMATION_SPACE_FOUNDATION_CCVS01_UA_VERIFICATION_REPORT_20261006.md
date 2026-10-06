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

## 10. Correction round 4 — Human ruling on C (MA-7) + B instrumentation (2026-10-06)

Human round-3 review: A = ACCEPT (closed); B oracle = PASS but observation
coverage insufficient; C = BLOCKER, now DECIDABLE from frozen MA-7 text —
retry returns the RECORDED terminal outcome and performs NO new effects,
and "no new effects" extends to the POSIX entity layer. Deterministic
rejections are NOT crash orphans and are not legalizable by MA-4.

### 10.1 C — MA-7 zero-effect boundary now includes the entity layer: FIXED

```text
Ruling applied: replay preflight happens BEFORE any durable external
effect. New admission order inside ONE write transaction:

  begin carrier write transaction
    (1) operation_id lookup  → exists: return recorded outcome
                               (no entity write, no registry mutation,
                                no new ledger row)
    (2) CAS revision check   → stale: evidence row commits with THIS
                               transaction; typed error after commit;
                               no entity write
    (3) representation identity check (six properties; identical =
        idempotent replay; different = typed conflicting duplicate)
                               → conflict: evidence row commits with
                               THIS transaction; no entity write
    (4) all admission passed → ONLY NOW durable entity write
                               → representation + CAS bump + provenance
                               → COMMIT
  crash between (4)'s entity durability and COMMIT = the MA-4 crash-only
  orphan window (UA-C2 gate sits exactly there).

Deterministic rejections (replay/stale/identity-conflict) now leave ZERO
external side effects. Evidence rows for rejections commit with the
admission transaction (nothing rolls back on rejection paths — the
round-1 evidence-rollback bug pattern remains structurally absent).
```

Session replay (C3): same-operation retry returns the recorded terminal
outcome (`.applied`), no longer demoted to `.replayed`; "was this a
replay" is observation metadata, not a terminal outcome. The ma7
regression now asserts `.applied` with zero event-count and fingerprint
delta.

### 10.2 C verification (probe → verification, per directive)

```text
focusC1ReplayPreflightLeavesZeroExternalEffect:
  OP1(P1) → APPLIED; H1 = authority fingerprint INCLUDING entity files;
  OP1(P2) → .applied (recorded outcome); H2 == H1; P2 entity DOES NOT
  exist; exactly one OP1 ledger row.
focusC2StaleRejectionLeavesNoEntity:
  stale attempt with fresh payload → typed staleRevision; P3 entity
  absent; carrier/mappings unchanged; provenance complete; exactly one
  terminal CONFLICT ledger row for the attempt.
focusC3IdentityConflictLeavesNoEntity:
  conflicting duplicate with fresh payload → typed conflict; P4 entity
  absent; no registry/mapping mutation; fingerprint delta = the evidence
  row only.
```

### 10.3 B — deterministic interleave instrumentation: ADDED

```text
focusBDeterministicInterleaveReaderInsideRebuildCriticalSection:
  a second SQLite connection holds the EXACT rebuild transaction open
  (BEGIN IMMEDIATE + the same DELETE/INSERT statements); readers on the
  main connection execute INSIDE the forced critical section and must
  observe exactly BEFORE (WAL snapshot) — then COMMIT → AFTER. This is
  the "reader forced into the critical window" evidence the round-3
  review required; single-connection self-observation is impossible
  without a mechanism seam (out of scope by directive).
Concurrent-task search-during-rebuild test retained as supplementary
  (non-forced) coverage.
```

### 10.4 Runner alignment + registered divergence flag

```text
MA-DS-1 step 8 runner expectation updated to the round-4 convention
  (retry returns recorded outcome .applied; the MA-7 evidence remains
  the zero-effect checks: event count unchanged, authority fingerprint
  byte-identical). Run 11: 13/13 within manifest semantics, overall
  VALID.
REGISTERED DIVERGENCE (flagged for acceptance review; Manifest NOT
  modified per directive): U-A manifest §4.2's mechanism sentence
  describes the pre-correction ordering ("entity bytes written BEFORE
  the transaction"). The implemented mechanism is now
  admission-inside-transaction-then-entity-write-then-commit. MA-4
  crash semantics are preserved (crash-only orphan window between
  entity durability and COMMIT; registry all-or-nothing). Whether to
  fold this mechanism-sentence update into a manifest v1.2 is the
  Human's call at acceptance review.
```

### 10.5 Verification status after round 4

```text
UAVerificationTests   12/12 PASS (C1/C2/C3 verification + B instrumentation
                      replace the round-3 probe)
UAOperationTests      13/13 PASS (ma7 updated to recorded-outcome ruling)
CarrierSQLiteTests     4/4 PASS — A1 conformance 10/10 no-regression
Full package          32/32 target tests green
Targeted MA-DS-1      13/13 within manifest semantics — overall VALID
                      (run 11, round-4 semantics)
Manifest v1.1         UNCHANGED (divergence flagged, §10.4)
Gate C                STARTED / OPEN
U-A implementation    RESUBMITTED — per the round-3 review, passing this
                      round is the precondition for acceptance
                      consideration; acceptance remains the Human's call
```

## 11. Round 5 — Human acceptance ruling (2026-10-06): U-A Correctness Acceptance

The Human reviewed `b9d2ac1` (code level, against the frozen Manifest) and
ruled on mechanism correctness and frozen-document consistency SEPARATELY:

```text
A  legacy ownership            = ACCEPT (unchanged)
B  atomic visibility           = ACCEPT (with proof-boundary wording, §11.3)
C  MA-7 zero-effect replay     = ACCEPT
C3 session replay              = ACCEPT
U-A implementation             = ACCEPTED
Manifest v1.1                  = NOT modified (explicit ruling, §11.4)
Gate C                         = STARTED / OPEN → ready for closure review
```

定性（Human）：**U-A Correctness Acceptance achieved** — three boundaries
closed:

```text
Ownership  → legacy / U-A destructive operations do not cross-erase
Visibility → concurrent rebuild never half-visible
Effect     → replay / deterministic rejection produce no external
             side effects
```

### 11.1 Layered wording record (Human-mandated, for v1.2 non-ambiguity)

| Layer | Status |
|---|---|
| MA-4 guarantee | **unchanged** (registry all-or-nothing; complete provenance; no half-committed authoritative state) |
| orphan classification | **unchanged / crash-only** |
| deterministic rejection semantics | **strengthened** (zero external effect) |
| physical write ordering | **changed** (admission-inside-transaction → entity write → commit) |
| Manifest §4.2 mechanism wording | **temporarily stale** (v1.2 reconciliation item) |

### 11.2 Run 10 UA-DF retraction (evidence-chain hygiene)

Run 10's step-8 UA-DF is formally RETRACTED as a protocol/implementation
defect. Root cause: the runner's step-8 expectation still asserted the
`.replayed` marker after the round-4 ruling had fixed the canonical
semantics (retry returns the recorded terminal outcome `.applied`).

```text
run 10  = INVALID / runner-error (stale verification-harness expectation)
run 11  = VALID (13/13 within manifest semantics, aligned runner)
```

The classification history stands as: no MA-DS-1 protocol defect was ever
observed at step 8; the MA-7 evidence in both runs (event count unchanged,
authority fingerprint byte-identical across retry) was identical.

### 11.3 B proof boundary (registered wording)

The interleave instrumentation proves **atomic visibility under a
controlled interleave** (readers forced inside the open rebuild
transaction via a second connection). It does NOT claim a
scheduler-complete proof over all possible interleavings. As correctness
evidence for the derived-index visibility boundary this suffices; it must
not be cited as exhaustive scheduling verification. The registered
instrumentation boundary stands: single-connection self-observation has
no mechanism seam, and no artificial seam may be added to production
mechanisms for testing purposes.

### 11.4 Manifest divergence → acceptance condition (v1.2 reconciliation)

The Human explicitly ruled the frozen Manifest v1.1 stays UNCHANGED:

```text
v1.1 frozen
       ↓
implementation proved stronger / more precise
       ↓
accept implementation
       ↓
record documentation divergence (acceptance condition)
       ↓
future v1.2 reconciliation (NOT to be forced for Gate C)
```

Guarantee semantics did not regress — deterministic rejection semantics
were strengthened. The §10.4 layered table above prevents any future
"did v1.2 change MA-4?" ambiguity: MA-4 guarantee and orphan
classification are unchanged; only the physical write ordering sentence
in §4.2 is stale.
