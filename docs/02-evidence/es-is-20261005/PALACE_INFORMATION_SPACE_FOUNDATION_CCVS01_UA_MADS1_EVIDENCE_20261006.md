# CCVS-01 U-A — MA-DS-1 Execution Evidence

> **Status:** MA-DS-1 EXECUTED — 13/13 PRE-REGISTERED STEPS CLASSIFIED WITHIN MANIFEST SEMANTICS — OVERALL VALID (no bound violation)
> **Date:** 2026-10-06
> **Basis:** U-A Manifest v1.1 §5 (13 steps, UNCHANGED; workload executed as pre-registered), Human MA-DS-1 authorization 2026-10-06
> **Scenario:** MA-DS-1 "Multi-Agent Research Day" — dual actor (agent-A research writer / agent-B lab organizer), clock-skew injection, three real process-SIGKILL crash episodes (gates UA-C1/C2/C3), retry/recovery episodes
> **Runner:** `trackD-memory/Sources/CarrierMADS1` (P8 pattern: prep phase → SIGKILL → verify phase); report artifacts: `trackD-memory/mads1-report.json`, `trackD-memory/mads1-final-state.json`
> **Crash model:** process SIGKILL only (PB v1.2 R6 scope), at the wired UA-C1/C2/C3 gates

## 0. Headline

```text
Step classifications: 11 PASS + 1 PASS (expected orphan state, explicitly
  detected; recovery via prescribed idempotent retry) + 1 REPAIR (prescribed
  recovery: rebuild re-run from authority) = 13/13 within manifest semantics.
UA-DF count: 0. Bound violations (I19-I25): 0.
Overall: VALID — the minimal SQLite + POSIX Unified Carrier withstood
  MA-DS-1 as executed. NOT a Gate C closure claim (Human audit pending).
Two runs: consecutive campaigns both VALID (deterministic classifications).
```

## 1. Per-step evidence chain

Format: Step → injected condition → observed outcome → evidence artifact →
applicable bound → classification → residual issue. Full machine-readable
detail lives in `mads1-report.json` (each step's `observed` dict).

```text
S1  create F1 (FILE carrier, entity bytes rev1)
    injected: none
    observed: UUIDv4 carrier id minted; revision 1; entity digest re-verified;
              dangling provenance 0
    artifact: mads1-report.json steps[0]; final-state.json
    bound:    CC-1/CC-2 identity minting + durable acknowledgement
    class:    PASS
    residual: none

S2  A opens S1 (SESSION carrier); JUDGMENT + EVIDENCE_LINK events;
    CC-5 mappings (formation-before-registration order)
    injected: none
    observed: events [0,1]; 2 mappings; EVIDENCE_LINK payload embeds F1@rev1
              digest
    artifact: steps[1]; final-state.json mappings
    bound:    CC-5 closed loop / I17-I18 reviewability basis
    class:    PASS
    residual: none

S3  B reads F1 and S1 concurrently
    injected: concurrent dual read
    observed: both snapshots coherent (F1 rev >= 1; S1 sequences contiguous)
    artifact: steps[2]
    bound:    MA-1 concurrent read
    class:    PASS
    residual: none

S4  B reorganizes: MOVE F1 + revise (locator transition, identity unchanged);
    cross-family append interleaved
    injected: cross-family concurrent write
    observed: carrier id unchanged; revision 2; locator
              research/q3-notes.md -> archive/2026/q3-notes.md; append landed
    artifact: steps[3]
    bound:    MA-2 concurrent write / MA-5 identity stability (MOVE)
    class:    PASS
    residual: none

S5  A commits from stale base (expected=1, current=2)
    injected: stale revision write
    observed: typed staleRevision(1,2) thrown; state unchanged; ledger CONFLICT
              row with observed_revision=2; NO blind overwrite
    artifact: steps[4]
    bound:    MA-3 / I19 no lost update
    class:    PASS
    residual: none

S6  A rebases: re-read (2), re-apply as NEW operation
    injected: rebase after conflict (new operation id per manifest §4.1)
    observed: APPLIED revision 3; from-version provenance recorded; content
              verified
    artifact: steps[5]
    bound:    MA-3 rebase path / MA-8 provenance
    class:    PASS
    residual: none

S7  A and B append concurrently with injected clock skew
    injected: 6 concurrent appends; timestamps injected through a fixed
              permutation (creation order and clock order decoupled)
    observed: all APPLIED; sequences contiguous; allocation order differs
              from timestamp order (carrier is the ordering authority)
    artifact: steps[6]
    bound:    MA-6 / I23 session ordering under concurrency
    class:    PASS
    residual: none

S8  retry after unknown commit outcome
    injected: UA-C1 SIGKILL AFTER the append commit
    observed: event + ledger APPLIED were durable before the kill
              (synchronous=FULL); retry with SAME operation_id -> REPLAYED;
              event count unchanged; authority fingerprint byte-identical
    artifact: steps[7]
    bound:    MA-7 / I24 idempotent retry
    class:    PASS
    residual: none

S9  crash inside A's compound operation
    injected: UA-C2 SIGKILL between entity fsync and registry transaction
    observed: durable before crash = entity bytes only; NOT established =
              representation row / revision bump / ledger-provenance row;
              orphan entity EXPLICITLY detected by integrity reporter;
              registry unchanged (rev 3, no row, no ledger entry, dangling
              provenance 0); retry (same operation_id) -> APPLIED rev 4;
              entity-orphan resolved (row now references the file)
    artifact: steps[8] incl. orphan_evidence
    bound:    MA-4 atomicity / I21 no dangling provenance
    class:    PASS (expected orphan state, explicitly detected; recovery via
              prescribed idempotent retry)
    residual: orphan transient existed between crash and retry, resolved by
              the retry itself; A1-reporter locator/availability findings on
              UA-path representations are a registered composition
              bookkeeping boundary, not a CC-MA bound violation (see §4)

S10 FTS rebuild during the C3 window
    injected: UA-C3 SIGKILL inside the rebuild transaction (after DELETEs);
              carrier advanced beforehand so the index was stale
    observed: rebuild transaction rolled back ATOMICALLY — old index intact
              and stale-DETECTABLE; authority fingerprint byte-identical
              across the crash; prescribed recovery = rebuild re-run from
              authority-derived documents; coverage (identity AND
              searchable-content) restored exactly; staleness clear;
              authority still byte-identical
    artifact: steps[9]
    bound:    MA-9 / I25 derived-index isolation + rebuild completeness gate
    class:    REPAIR (prescribed recovery path; all post-recovery
              constraints hold)
    residual: index stale-but-intact between crash and recovery (atomic
              rollback property)

S11 B multi-object reads during A's commits
    injected: concurrent commits + repeated snapshots
    observed: 8 snapshots, all single-committed-version coherent (contiguous
              sequences; readVersion == revision; event count consistent
              with version watermark); versions monotone
    artifact: steps[10]
    bound:    MA-10 / I22 no never-existed mixed state
    class:    PASS
    residual: none

S12 session summary materialization mid-stream
    injected: summary through sequence N, then raw append N+1
    observed: raw events intact (prefix preserved, contiguous); summary row
              derived-only
    artifact: steps[11]
    bound:    CC-4 / I14 (F13 vocabulary: summary derived, raw authoritative)
    class:    PASS
    residual: none

S13 full-day audit (rename+revision+reindex+summary replayed)
    injected: whole-day replay and identity review
    observed: identity sets stable (both carrier ids unchanged); exactly one
              applied CARRIER_CREATE per logical carrier (I20); distinct
              representation identities under one carrier; historical
              judgment REVIEWABLE (S1 EVIDENCE_LINK record -> CC-5 mapping
              -> F1@f1-rep-1 content, digest match); dangling provenance 0;
              staleness clear after reindex replay; entity orphans 0
    artifact: steps[12]; mads1-final-state.json (full state reconstruction:
              carriers, representations, 15 events, 3 mappings, 25 ledger
              rows, final authority fingerprint)
    bound:    MA-5 / I20 / I17 / I18
    class:    PASS
    residual: A1-reporter locator/availability findings on UA-path
              representations (bookkeeping boundary, §4)
```

## 2. Crash-gate narratives (the three required answers)

```text
UA-C1 (S8) — crash AFTER session-append commit.
  Where: after the append transaction committed, before the actor saw the
  acknowledgement.
  Durable facts established: the event row, the client_ref row, the carrier
  revision bump, the APPLIED ledger row with complete provenance.
  Not established: nothing — the operation had fully committed; the ACTOR's
  knowledge was the only missing piece (unknown outcome).
  Why no CC-MA violation: recovery re-drives the SAME operation_id; the
  ledger replays the recorded outcome with zero new effects (I24), so the
  committed prefix is neither duplicated nor reordered.

UA-C2 (S9) — crash INSIDE the compound revise, between entity fsync and
  the registry transaction.
  Where: the durable-acknowledgement boundary of MA-4.
  Durable facts established: entity bytes (fsync + rename + dir-fsync +
  digest re-read).
  Not established: representation row, carrier revision bump, ledger/
  provenance row — the entire registry half rolled back with the process.
  Why no CC-MA violation: the registry state is all-or-nothing per
  operation, so no half-committed provenance exists (I21); the transient
  orphan entity is a TYPED, detectable state (integrity reporter), and the
  prescribed idempotent retry completes the registry half and resolves the
  orphan by referencing the already-durable bytes.

UA-C3 (S10) — crash INSIDE the rebuild transaction, after the DELETEs.
  Where: mid-transaction of the derived-index rebuild.
  Durable facts established: authority tables and entity files (untouched —
  the rebuild is a derived-layer transaction; fingerprint identical).
  Not established: the new index build rows (rolled back).
  Why no CC-MA violation: atomic rollback leaves the PREVIOUS index intact
  (no partial index), staleness remains DETECTABLE (carrier watermark ahead
  of build version), and the prescribed recovery (rebuild re-run from
  authority) restores the promised coverage — identity AND
  searchable-content — with the authority still byte-identical (I25).
```

## 3. Registered findings (implementation corrections exposed by MA-DS-1)

Both corrections were driven by the manifest's own frozen text; zero
manifest-semantics change; zero protocol change. Registered here per the
standing discipline (mechanism misalignment -> correct implementation,
document, never touch criteria).

```text
UA-IF-1  index-build watermark granularity.
  Exposed: run 1 step 10/13 — staleness never cleared after rebuild.
  Cause: ua_index_builds was keyed by information_id alone, but the CC-5
  mapping is N:M by default — one information may be mapped to several
  carriers, each needing its OWN revision watermark.
  Manifest basis: §4.5 "per-carrier revision watermark" (frozen text).
  Fix: PRIMARY KEY (information_id, carrier_id); staleness join per pair.

UA-IF-2  staleness vs missing-coverage separation.
  Exposed: run 2 — mapping pairs that never had an index build (a
  provenance-only mapping such as the EVIDENCE_LINK pair) were reported
  stale.
  Cause: the staleness query used LEFT JOIN, treating "no build row" as
  stale. Manifest §4.5 defines staleness as "indexed revision < carrier
  revision watermark" — presupposing an indexed document; missing coverage
  belongs to the rebuild-completeness gate (rebuild-compare), not the
  staleness join.
  Fix: staleness = build rows whose carrier revision advanced past their
  build version (inner join over existing builds).

Runner corrections (test/fixture side, no mechanism change): kill-flag
  passing to recovery phases; step-7 timestamp permutation decoupling
  creation order from clock order.
```

## 4. Boundaries and honesty notes

```text
- Concurrency is exercised as concurrent tasks over the actor-owned
  single SQLite connection (the implemented composition property);
  physical write serialization at SQLite is the storage layer, not an
  application-level global lock (MA-2 evidenced as independent carrier
  streams settling under concurrency).
- Crash model: process SIGKILL only. No disk-failure, network-partition,
  or multi-node model is claimed.
- A1-reporter locator/availability invariants do not bind UA-operation
  representations: the U-A operation layer tracks locator state on the
  carriers row while the A1 runtime path maintains the locators/
  availability tables. This is a composition bookkeeping boundary
  registered as residual; it is not a CC-MA bound and is candidates for
  the U-2 integration consolidation — NOT silently reconciled here.
- No performance measurements (PB-U* UNCALIBRATED, U-3 scope).
- Gate C: NOT closed. This evidence chain is submitted for the Human's
  independent audit; closure is a separate Human action.
```

## 5. Verdict structure compliance

```text
Layered verdicts only — no weighted total, no cross-candidate ranking.
Classification vocabulary: PASS / REPAIR / DETACHED / INCOMPLETE / UA-DF-n.
Observed: PASS x12 (one with expected-orphan episode), REPAIR x1,
  DETACHED x0, INCOMPLETE x0, UA-DF x0.
Two consecutive campaign runs produced identical classifications.
```

## 6. Correction round — Human code-level audit (2026-10-06)

The Human performed a CODE-LEVEL independent audit (commit `d98d5c1`:
runner, SQLiteCore, SQLiteUnifiedCarrierOperations, machine-readable
results — not the evidence summary). Verdict:

```text
MA-DS-1 workload       = VALID (13/13 within registered semantics, 0 UA-DF,
                         0 bound violation observed)
U-A implementation     = BLOCKED (two gaps; Gate C NOT closed)
```

Both gaps are implementation-vs-manifest mismatches and were handled by
the agreed discipline (Manifest → implementation mismatch → code
correction → targeted conformance → targeted MA-DS-1 regression). The
Manifest was not modified. Neither finding was re-labelled a "boundary
residual".

### UA-IF-3 (BLOCKER, MA-9/I25) — carrier-scoped searchable representations

```text
Audit finding: UA-IF-1 fixed the build-watermark granularity to
  (information_id, carrier_id) but the derived searchable layer remained
  information-scoped: search_fts had no carrier_id and uaIndexDocument
  deleted by information_id alone — indexing Information I for Carrier B
  erased I's searchable representation for Carrier A. The implementation
  did not fully deliver the N:M / per-carrier rebuild semantics the
  manifest already writes.
Correction:
  - search_fts v2: carrier_id UNINDEXED column added (Information x
    Carrier); a stale-schema table is dropped and recreated — legitimate
    because FTS is derived and rebuildable from authority (CC-7).
  - uaIndexDocument deletes/inserts per (information_id, carrier_id)
    pair; uaRebuildIndex inserts carrier-scoped rows.
  - New scoped read surface: searchScoped(query, carrierID) ->
    UASearchHit (the carrier-neutral CarrierSearchResult type is
    unchanged). Runtime-path (pre-U-A) FTS writes use NULL carrier_id.
Targeted regression (new, manifest §4.5 semantics):
  ma9CarrierScopedSearchableRepresentations — I1 indexed for carriers A
  and B: both representations exist; re-indexing A does not erase B;
  staleness independently detectable per pair; full rebuild restores both.
Status: corrected; regression PASS; targeted MA-DS-1 re-run VALID.
```

### UA-IF-4 (HIGH) — Representation Identity conflict was silently swallowed

```text
Audit finding: uaReviseCarrierWithRepresentation used INSERT OR IGNORE:
a second registration of representation R with a DIFFERENT digest would
be silently ignored while the carrier revision still advanced and the
ledger recorded APPLIED — an impossible state (operation APPLIED, stored
bytes old), conflicting with CC-8 #7 (each recorded representation
version is immutable).
Correction:
  duplicate registration is now classified explicitly:
    same R + identical immutable properties (information_id, revision_id,
      digest, byte_count, media_type)
        -> idempotent/replay semantics: ledger row outcome REPLAYED, no
           revision bump, no duplicate row;
    same R + any different immutable property
        -> typed error conflictingDuplicateRepresentation(R), ledger
           CONFLICT evidence row in its own committed transaction,
           carrier state unchanged.
Targeted regression (new):
  representationIdentityConflictIsTyped — R1+D1 APPLIED; R1+D1 again ->
  REPLAYED (revision unchanged); R1+D2 -> typed conflict, carrier state
  unchanged, no silent IGNORE, no false APPLIED, provenance complete.
Status: corrected; regression PASS; targeted MA-DS-1 re-run VALID.
```

### Correction-process note (registered honestly)

While implementing UA-IF-3, the runtime-path FTS re-binding was initially
mis-aligned (three binds for four parameters), which crashed text reads
on NULL columns under the full parallel test suite. Caught by the suite
itself before any commit; binding fixed; recorded here because the
correction process is part of the evidence chain.

## 7. Precise MA-4 statement (audit item 3, adopted)

What the UA-C2 episode establishes is exactly:

> The SQLite authority/registry side of the compound operation is atomic
> (all-or-nothing per operation), and between the POSIX entity durable
> write and the registry transaction there is an ALLOWED, TYPED,
> DETECTABLE orphan window whose recovery path is prescribed by the
> manifest (idempotent retry with the same operation_id).

It does NOT claim more than that (e.g., not "MA-4 atomicity is proven
for all compositions"). The manifest itself reserves this
composition-specific boundary (§4.2: the entity-fsync-then-commit order
is a U-A composition mechanism; UA v1.0 requires the explicit atomic
boundary, not this physical order).

## 8. MA-3 / MA-7 operation state machine (audit item 5 — retained as research evidence)

Verified jointly by the code and the conformance tests; adopted as a
U-A research result:

```text
operation_id
     │
     ├── first attempt
     │       ├── APPLIED  → terminal (durable effects, ledger APPLIED)
     │       └── CONFLICT → terminal (no carrier-state change; ledger
     │                        CONFLICT evidence row)
     │
     └── retry with the SAME operation_id
             └── REPLAYED (recorded outcome returned verbatim; zero new
                 effects — covers the unknown-outcome window after crash)

CONFLICT recovery
    ↓  new operation_id (rebase = new operation with new expected_revision
    ↓  after re-read — manifest §4.1)
    new attempt
```

The boundary this pins: MA-7 idempotent replay covers re-driving an
operation with UNKNOWN outcome; a CONFLICT is a terminal outcome, and
re-execution requires a NEW operation identity.

## 9. Post-correction verification status

```text
UAOperationTests            13/13 PASS (11 original + 2 targeted)
CarrierSQLite target        17/17 PASS — includes A1 conformance 10/10
                            (NO REGRESSION) and full-suite parallel run
Full package                green (4 + 17 + 4 + 15)
Targeted MA-DS-1 regression 13/13 within manifest semantics — overall
                            VALID (run 6; classifications unchanged from
                            the audited run)
Artifacts refreshed         trackD-memory/mads1-report.json
```

The two audit blockers are corrected and regression-covered. The U-A
implementation is RESUBMITTED for the Human's code-level audit. Gate C
remains STARTED / OPEN — closure is a separate Human action and is not
claimed.
