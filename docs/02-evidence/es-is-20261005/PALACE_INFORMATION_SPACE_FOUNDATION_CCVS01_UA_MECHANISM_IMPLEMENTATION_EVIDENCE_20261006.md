# CCVS-01 U-A — Mechanism Implementation Evidence

> **Status:** U-A MECHANISM IMPLEMENTATION DELIVERED — CONFORMANCE + ADMISSION RUN
> **Date:** 2026-10-06
> **Basis:** U-A Unified Minimal Composition Manifest v1.1 (APPROVED FOR IMPLEMENTATION by Human 2026-10-06)
> **Execution order observed:** manifest v1.1 → mechanism implementation → mechanism-level conformance → admission (build/test) — **MA-DS-1 NOT RUN** (next separate step)

## 1. What was implemented

Composition-level mechanisms on the A1 base (SQLite registry + POSIX
entity store), per manifest §2-§4. No carrier-neutral protocol surface
changed; no Frozen Contract changed; all evidence handles remain
layer-②③④ fields (self-audit A2 bounding respected in code comments and
schema).

```text
Sources/CarrierSQLite/SQLiteCore.swift
  + ua_* schema: carriers (logical Carrier + monotone revision),
    ua_operations (operation ledger = carrier_provenance),
    ua_mapping (CC-5, append-only), ua_session_client_refs
    (MA-6/MA-7 idempotency keys), ua_index_builds (MA-9 IndexSource
    tracking: source revision + build version)
  + withTransaction (one IMMEDIATE transaction scope — MA-4),
    withReadSnapshot (one DEFERRED WAL snapshot — MA-10),
    statement/changes primitives

Sources/CarrierSQLite/SQLiteUnifiedCarrierOperations.swift (new)
  - carrier identity minting (UUIDv4, registry-side; explicit-id
    duplicate = I20 rejection)
  - uaReviseCarrier: CAS via expected_revision; CONFLICT recorded as
    ledger evidence in its own committed transaction, then typed error
    (carrier state untouched — no blind overwrite, MA-3/I19)
  - uaReviseCarrierWithRepresentation: MA-4 compound boundary — entity
    durable write (temp+fsync+rename+dir-fsync+digest re-read) FIRST,
    then ONE transaction commits representation row + carrier CAS bump
    + complete provenance; crash gate UA-C2 at the durable-acknowledgement
    point
  - uaAppendSessionEvent: carrier-side sequence allocation inside the
    append transaction (client timestamps never ordering source),
    client_event_ref dedupe, operation_id replay — crash gate UA-C1 at
    the unknown-outcome point (MA-6/MA-7/I23/I24)
  - uaRecordMapping: CC-5 append-only mapping entry with provenance
  - uaConsistentSnapshot: carrier + ordered events + mappings under one
    read_version (MA-10/I22)
  - uaIndexDocument/uaIndexStaleness/uaRebuildIndex: build-version
    tracking; staleness detectable (carrier revision > build version);
    rebuild never writes authority — crash gate UA-C3 (MA-9/I25)
  - authorityFingerprint: hash of authority tables + entity files for
    the rebuild audit; danglingProvenanceCount: I21 evidence query

Sources/CarrierSQLite/POSIXEntityStore.swift
  durableWrite + entitiesRoot exposed module-internally for the
  compound operation (no behavioral change to the protocol surface)

Sources/CarrierSQLite/SQLiteCarrierFactory.swift
  SQLiteCarrierBundle.operations — the U-A operation facade mounted on
  the composition root
```

## 2. Test-to-criterion mapping (pre-registered chains → checks)

`Tests/CarrierSQLiteTests/UAOperationTests.swift` — 11 tests, each
deriving mechanically from a manifest §4 chain criterion:

```text
ma3StaleReviseDetectedWithNoOverwrite        MA-3/I19  CONFLICT typed error,
                                             zero state change, ledger
                                             evidence row, rebase applied
                                             with from-version provenance
ma7SameOperationIDReplaysWithZeroStateDelta  MA-7/I24  replay = recorded
                                             outcome, authority fingerprint
                                             byte-identical across retry
ma6SameClientRefAcrossOperationsYieldsOneEvent  MA-6   (session, clientRef)
                                             resolves to ONE event
ma6ConcurrentAppendsProduceGaplessTotalOrder MA-6/I23  12 concurrent appends
                                             (reverse clock skew injected)
                                             -> sequences exactly 0..11,
                                             order != timestamp order
ma4CompoundReviseCommitsAllPartsAtomically   MA-4/I21  representation +
                                             carrier bump + provenance all
                                             present; dangling count = 0
ma4ConflictInsideCompoundWritesEvidenceOnly  MA-4/MA-3 stale compound base ->
                                             evidence-only, no partial rows
i20DuplicateCarrierIdentityRejected          I20       second registration of
                                             the same logical carrier id
                                             rejected
identityNamespacesAndMappingClosedLoop       §2/§3     UUID carrier id != info
                                             id; forward walk information →
                                             mapping → carrier → bytes and
                                             backward via digest; mapping
                                             correction = new entry
ma9StalenessDetectableAndRebuildRestoresCoverage  MA-9/I25 + rebuild gate:
                                             staleness observable after
                                             carrier advance; authority
                                             fingerprint identical across
                                             rebuild; identity AND
                                             searchable-content coverage
                                             restored exactly
ma10SnapshotIsOneCommittedVersionView        MA-10/I22 read_version coherence
                                             across commits; no mixed state
ma2ConcurrentWritesAcrossCarriersAllSucceed  MA-2      independent carrier
                                             streams settle under
                                             concurrency; every outcome in
                                             the allowed set
```

## 3. Results

```text
UAOperationTests                11/11 PASS (3 consecutive runs)
CarrierInterfaceTests            4/4 PASS
CarrierSQLiteTests              15/15 PASS — includes
   sqliteCarrierPassesFullConformance          A1 conformance 10/10
   (NO REGRESSION — frozen A1 surface unchanged)
CContinuation/CImpl/CB legacy   15/15 PASS
Full suite: stable across repeated runs; no flaky failures.
```

## 4. Registered finding: conflict-terminal semantics exercised

The first MA-2 test draft retried a CAS revise after CONFLICT **reusing
the same operation_id** and silently received the recorded CONFLICT
outcome (MA-7 replay). Checked against the manifest text: §4.1 fixes
"rebase = **new operation** with new expected_revision after re-read" —
a CONFLICT is a terminal, ledger-recorded outcome; the idempotent-retry
guarantee (MA-7) covers re-driving an operation with UNKNOWN outcome,
not re-executing a terminally conflicted one. **Mechanism confirmed
correct against the manifest; the TEST was corrected** (fresh
operation_id per rebase attempt). This is the reverse of the
anti-pattern the Human flagged: no manifest semantics were changed to
fit the implementation.

## 5. Boundaries and honesty notes

```text
- Crash gates UA-C1/C2/C3 are registered and wired but the multi-process
  SIGKILL exercises (all-or-nothing under real crashes, MA-DS-1 steps 8-9)
  belong to the MA-DS-1 run, using the established P8 crash-runner
  pattern. In-process tests here verify transaction-scope atomicity and
  replay semantics, not SIGKILL durability.
- In-process concurrency serializes on the single SQLite connection
  (composition property: actor-owned connection). MA-2 is evidenced as
  independent carrier streams settling under concurrency; WAL
  multi-connection parallelism is exercised in MA-DS-1.
- No performance measurements of any kind were taken (round-one
  exclusion; PB-U* stays UNCALIBRATED for U-3).
- No MA-DS-1 step has been executed; no Gate C progress is claimed.
```

## 6. Next step (within the authorized U-A sequence)

```text
admission build/test      DONE (this document, §3)
MA-DS-1 execution         NEXT — 13 pre-registered steps (manifest §5),
                          including the multi-process crash and retry
                          episodes via UA-C1/C2/C3 gates
evidence chain package    after MA-DS-1, for Human audit
```
