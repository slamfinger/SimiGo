# CCVS-01 U-A — Unified Minimal Composition Manifest

> **Status:** U-A COMPOSITION MANIFEST v1.0 — EXECUTION BASIS FOR THE AUTHORIZED U-2
> **Date:** 2026-10-06
> **Authorization:** Human U-2 authorization 2026-10-06 (after Gate B ACCEPT / FREEZE, UA v1.0 FROZEN, ruling `PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_UA_V1_0_FREEZE_RULING_20261006.md`)
> **Governing protocol:** UA v1.0 (`PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_U1_UNIFIED_ADDENDUM_PROTOCOL_V1.0_20261006.md`) — §3 UA-CC, §3A CC-MA, §11 candidate U-A, §14 phase sequence
> **Predecessor base:** Baseline A / A1 CarrierSQLite (Phase C File side, conformance 10/10, P8 G2 PASS) — evolved, not replaced
> **Execution principle (Human):** Manifest FIRST, then mechanisms, then experiment. No implementation expansion before this manifest is on record.
> **Round-one exclusions (Human):** no horizontal carrier-topology comparison; no backend selection; no carrier migration; no MemPalace integration; no UA v1.0 / PB v1.2 / Frozen Contract modification; no larger performance benchmark (PB-U* calibration stays UNCALIBRATED and belongs to U-3).

---

## 1. What U-A IS (composition definition)

U-A = **Unified Minimal** (UA v1.0 §11): the FIRST implementation of the
Unified Carrier Contract INCLUDING CC-MA, evolved from the A1 adapter.

```text
U-A composition (one Carrier database, one contract, two instance families):

  Layer ①  Information / Relation semantics
           InformationCore + RelationCore, UNCHANGED, cited not redefined
           (frozen: A1-A5/B1-B3/S1-S6, D1(a)/D2(a)/D3(a)/R1-R6, A2′, D7(a))

  Layer ②  Unified Carrier layer (U-A core work)
           ONE SQLite carrier database (registry, records, mapping,
           provenance, operations, index-source) under ONE concurrency
           contract / guarantee set (CC-MA)
             ├─ FILE carrier family
             │    locator = POSIX path + fingerprint (POSIXEntityStore
             │    bytes: temp-write + fsync + rename + dir-fsync +
             │    digest re-read; atomic MOVE = new locator + retire,
             │    identity unchanged — A1 semantics inherited)
             └─ SESSION carrier family
                  locator = session identity; records = ordered events
                  (append-only (SessionID, sequence), CC-4)

  Layer ③  Carrier Representation / Record layer
           physical difference per family ALLOWED (different tables,
           different record shapes) — beneath ONE contract (CC-9)

  Layer ④  Derived Access layer (ALL derived, CC-7)
           L1 exact lookup (MANDATORY)
           L2 FTS lexical search (MANDATORY, derived-only; registry is
              the rebuild authority)
           L3 semantic search (pluggable seam; ABSENT in U-A round one,
              registered N/A-with-reason — not a gap)
```

Mandatory surface additions over A1 (the CC-MA mechanisms, §4 of this
manifest): object versioning, operation identity, CAS conflict
detection, idempotent-retry registry, snapshot read-version, index
build-version isolation, CC-5 mapping with provenance, and the
rebuild-completeness gate (P8 F7 promoted to hard gate).

## 2. Identity model — three identities, three namespaces, one ≠ chain

The three identity kinds are SEPARATE namespaces with separate minting
rules and separate storage columns. No column is ever reused across
kinds. The mandated ≠ chain (CC-8) holds at clause level:

```text
Information Identity ≠ Carrier Identity ≠ Representation Identity
                     ≠ Physical Locator ≠ Record/Event Identity
                     ≠ Derived Index Entry
```

| Kind | Minting (mechanism-side, U-2 manifest obligation A-1) | Storage | Mutability |
|---|---|---|---|
| Information Identity | EXISTING frozen semantics (A2′): formed AT FORMATION by the existing mechanism-side recipe (registered first-implementation input = content + source + chunkIndex; digest MAY participate). U-A adds NO recipe change. | InformationCore (unchanged) | immutable forever; never changes due to path/name/carrier/revision |
| Carrier Identity (logical) | minted ONCE by the carrier registry at carrier creation: opaque random `CarrierID` (UUIDv4); NEVER derived from path, name, digest, or Information identity | `carriers.carrier_id` | stable for the carrier's life; locator and content revision are mutable attributes, not identity |
| Representation Identity | content-derived: `SHA-256(bytes)` + per-carrier revision number; a new revision of the same carrier is a NEW representation identity and the SAME carrier identity | `representations(rep_digest, revision)` | immutable once recorded; append-only |
| Record/Event Identity | carrier-internal: FILE = (carrier_id, record_id, revision); SESSION = (SessionID, sequence) | per-family record tables | SESSION append-only, never renumbered; FILE stable under representation revision |

Same-carrier-across-MOVE/RENAME/REVISION (FILE family, the A-1
obligation): `carriers.carrier_id` is minted at registration; MOVE =
atomic locator transition (new path + retire old, one transaction, with
carrier_provenance row); REVISION = new representation row, same
carrier_id. Identity coverage after any such transition is verified by
conformance (inherited A1 checks) and re-exercised in MA-DS-1 step 13.

Registry-uniqueness rule (I20, narrowed form): one logical Carrier
instance = one `carrier_id`. A second registration claiming the same
logical carrier (same authoritative locator family + creation
provenance) is a CONFLICTING DUPLICATE and is rejected; legitimate
distinct carriers and legitimate distinct Informations are outside this
bound.

## 3. Mapping / Locator / Provenance closed loop

Not three isolated fields. One walkable chain, provenance-bearing at
every hop (CC-5 + CC-8 #4 + MA-8):

```text
FORWARD (Information → bytes):
  Information.InformationID
    → CC-5 mapping row (mapping_id, information_id, carrier_id,
       record_id, representation_revision_at_formation,
       mapping_provenance: actor_id / operation_id / when / from-version)
    → carriers row (carrier_id, carrier_kind, current locator,
       current revision)
    → representation row (rep_digest, revision)
    → entity store bytes at locator (digest re-verified on read)

BACKWARD (bytes → Information):
  bytes → digest → representation (which carrier/revision)
        → record (locatability unit) → CC-5 mapping rows
        → Information(s) formed from this content

RULES:
  - mapping is append/annotate ONLY; corrections = NEW entries with
    provenance; history never rewritten (CC-5);
  - cardinality N:M by default (UA v1.0 frozen default, A-2 flag
    carried);
  - every committed carrier operation has a complete
    carrier_provenance row (who / when / from which version / resulting
    version / operation_id) — I21 no-dangling-provenance;
  - record deletion NEVER equals Information deletion (ruling B.1 /
    A1 immutability): already-formed Informations persist; typed loss
    semantics per UA v1.0 §5.
```

**Compound-operation order (UA-P7 mechanism decision):** within one
logical operation that spans semantic persistence and carrier state,
FORMATION PRECEDES CARRIER REGISTRATION: (1) form Information through
existing semantics (idempotent, first-write-wins); (2) carrier
transaction writes record + mapping + provenance atomically. The
reverse order is FORBIDDEN (it would create a mapping referencing a
nonexistent Information). Crash between (1) and (2) leaves Information
formed with no carrier claim — a safe prefix; retry with the SAME
operation_id completes the carrier side without duplicating formation.
This is how a compound operation remains atomic/consistent WITHOUT
making the semantic layer transaction-aware (layer ① stays untouched).

## 4. CC-MA mechanisms — the six mandated chains

Each chain: **Requirement → Mechanism → Observable Evidence →
Pass/Fail Criterion → MA-DS-1 Exercise.** Mechanisms are U-2
mechanism-side decisions under UA v1.0 §3/§3A; none modifies layer ①.

### 4.1 MA-3 — Lost-Update Prevention

```text
Requirement      stale write detection + no blind overwrite; allowed
                 outcomes ONLY: accept / rebase / conflict / retry
Mechanism        optimistic CAS: every carrier row carries a monotone
                 `revision`; every mutating operation carries
                 `expected_revision` (the base the actor read); commit
                 rejects (CONFLICT, read-only error surface) when
                 current != expected; NO write path may omit the check
Evidence         operation ledger row per attempt:
                 (operation_id, actor_id, carrier_id, expected_revision,
                  observed_revision, outcome ∈ {APPLIED, CONFLICT});
                 conflict never mutates state; rebase = new operation
                 with new expected_revision after re-read
Pass/Fail        PASS: every stale attempt observable as CONFLICT with
                 state unchanged; zero silent overwrites in any run.
                 FAIL: any state change without matching CAS.
                 (I19 violation = protocol failure of the candidate.)
MA-DS-1 step     step 5 (Agent A stale write on F1 rejected) +
                 step 6 (rebase applied with from-version provenance)
```

### 4.2 MA-4 — Atomicity (incl. compound operations, UA-P7)

```text
Requirement      explicit atomic boundary for updates spanning related
                 objects; no "unexplainable state" (subject committed,
                 provenance/reference half-committed); compound
                 operations spanning semantic persistence + carrier
                 state do NOT escape atomicity (freeze condition 1)
Mechanism         ONE SQLite transaction per compound carrier operation:
                 registry revision bump + record write + CC-5 mapping
                 + carrier_provenance + index-source invalidation
                 commit together or not at all. Entity bytes are
                 written BEFORE the transaction (temp+fsync+rename,
                 digest re-read) — durable acknowledgement point =
                 entity fsync THEN registry commit; a crash between
                 leaves an orphan entity detected by the integrity
                 reporter, never a half-committed registry.
                 Cross-layer order per §3: formation first, carrier
                 transaction second, one operation_id spanning both.
Evidence         per-operation transaction record; integrity report
                 (orphan/detached scan) after injected crashes;
                 provenance-completeness query: zero committed
                 operations without complete provenance rows
Pass/Fail        PASS: after every injected crash point, registry state
                 is all-or-nothing per operation; every committed
                 operation has complete provenance (I21); orphan
                 entities are typed and detected.
                 FAIL: any observable half-commit; any committed
                 operation with missing provenance/reference.
MA-DS-1 step     step 9 (crash injection inside the compound operation)
```

### 4.3 MA-6 — Session Ordering Under Concurrency

```text
Requirement      (SessionID, sequence) stable; concurrent appends get
                 carrier-defined ordering; duplicate prevention;
                 client timestamps NEVER the ordering source
Mechanism        ordering authority = the carrier, allocation inside
                 the append transaction (sequence = counter read+write
                 under SQLite write lock; serialized allocation);
                 client-supplied `client_event_ref` = idempotency key
                 with a UNIQUE constraint per session; retry with the
                 same ref returns the already-allocated event; sequence
                 values never renumbered, survive restart / summary
                 materialization / reindex / derived rebuild (CC-4)
Evidence         append ledger: allocated (SessionID, sequence) per
                 event with actor + operation_id; concurrent-append
                 runs show a total order with no gaps and no duplicates;
                 timeline read = sequence order regardless of arrival
                 order or client clock skew (skew deliberately injected)
Pass/Fail        PASS: concurrent appends produce one gapless total
                 order; equal client_event_ref retried = one event
                 (I23/I24 hold); reordering never observable.
                 FAIL: any gap, duplicate, reorder, or
                 timestamp-inferred order.
MA-DS-1 step     step 7 (A and B append concurrently; skew injected)
```

### 4.4 MA-7 — Idempotent Retry

```text
Requirement      after crash / unknown commit outcome, retry produces
                 NO duplicates of Information, Representation,
                 SessionEvent, Relation, or provenance records
Mechanism        `operation_id` (stable identity, client-supplied or
                 minted at first admission) recorded UNIQUE in the
                 operation ledger with its terminal outcome; retry with
                 the same operation_id returns the RECORDED outcome and
                 performs no new effects; combined with layer ①
                 first-write-wins stores (semantic side cannot
                 duplicate) and §3 formation-before-registration order
Evidence         operation ledger: one terminal outcome per
                 operation_id; retry trace shows "REPLAYED outcome"
                 with zero state delta; byte-level state hash before/
                 after retry identical
Pass/Fail        PASS: N retries of the same operation_id = exactly the
                 original effects, once (I24).
                 FAIL: any duplicate object or effect after retry.
MA-DS-1 step     step 8 (retry after injected unknown-outcome crash)
```

### 4.5 MA-9 — Derived Index Isolation (+ rebuild completeness hard gate)

```text
Requirement      index lags but never overwrites authority, never
                 becomes a fact/identity source, is stale-detectable,
                 rebuildable, and never corrupts authority during
                 concurrent rebuilds; U-A REBUILD COMPLETENESS GATE:
                 full-rebuild claims require authoritative searchable
                 source content sufficient for the promised
                 searchable-content coverage (P8 F7 promoted)
Mechanism        index rows carry IndexSource (source carrier_id,
                 rep_digest, revision, extractor id + version) +
                 build_version; staleness detection = indexed revision
                 < carrier revision (per-carrier revision watermark);
                 rebuild = deterministic re-extraction from
                 AUTHORITATIVE bytes (entity store), run in a read-only
                 snapshot of authority; registry remains rebuild
                 authority (A1 architecture property inherited); index
                 writes never touch authority tables
Evidence         rebuild-compare report: identity coverage AND
                 searchable-content coverage (destroyed index vs
                 rebuilt index set equality); staleness probe during
                 concurrent writes; authority-digest audit before/
                 after rebuild (byte-identical)
Pass/Fail        PASS: rebuild from authority reproduces promised
                 coverage; concurrent writes + rebuild leave authority
                 byte-identical and the index stale-DETECTABLE (I25).
                 INCOMPLETE (no full PASS): any promised searchable
                 coverage whose source content is not retained in
                 authority. FAIL: authority corruption or undetectable
                 staleness.
MA-DS-1 step     step 10 (rebuild during concurrent writes) + step 13
```

### 4.6 MA-10 — Snapshot / Recovery Consistency

```text
Requirement      a reader during concurrent modification obtains a
                 consistent snapshot or explicit version view; no
                 "seemingly legal but never-existed" mixed state
Mechanism        readers run in one SQLite read transaction (WAL):
                 every multi-object read resolves ONE committed
                 read_version; a reader's view of {carriers, records,
                 mappings} is the committed state at that version;
                 writers proceed concurrently (no reader blocks writer,
                 MA-1 preserved)
Evidence         snapshot probe: concurrent writer commits mid-read;
                 reader's multi-object view hashes to a state that
                 exists in the commit history; cross-version mixed
                 states (record from V2 + mapping referencing V1-only
                 state) never observable
Pass/Fail        PASS: every observed multi-object view corresponds to
                 some single committed version (I22).
                 FAIL: any never-existed mixed state observed.
MA-DS-1 step     step 11 (snapshot during Agent A's commit) + step 12
```

### 4.7 Remaining MA items (chains in short form; still mandatory)

```text
MA-1 Concurrent Read   mechanism: WAL readers never block writers or
                       each other. Evidence: N-reader runs, zero
                       read-side serialization. Criterion: concurrent
                       reads all succeed with consistent snapshots.
                       Exercise: MA-DS-1 step 3.
MA-2 Concurrent Write  mechanism: per-carrier CAS + per-session append
                       serialization; NO global write lock across the
                       Information Space (different carriers commit
                       independently). Evidence: cross-carrier
                       concurrent commits proceed; ledger shows
                       interleaved carriers. Criterion: no
                       whole-space serialization observable.
                       Exercise: MA-DS-1 steps 4-7 (F and S carriers
                       interleaved).
MA-5 Identity Stability  mechanism: §2 namespaces + A1 atomic MOVE +
                       append-only records; no code path mutates
                       InformationID/CarrierID. Evidence: identity
                       audit across rename/move/revision/reindex/
                       summary (before/after identity sets equal
                       where required). Criterion: no forbidden
                       equivalence (path change == new Information,
                       event append == new Session identity, index
                       entry == identity) ever observable; I20 holds.
                       Exercise: MA-DS-1 step 13.
MA-8 Provenance Under Concurrency  mechanism: every operation writes
                       complete carrier_provenance (actor/when/
                       from-version/resulting-version/operation_id) in
                       the same transaction. Evidence: provenance
                       completeness query = zero dangling (I21);
                       concurrent operations each answer who/when/
                       from-what-version. Criterion: PASS iff I21
                       holds under concurrency. Exercise: steps 5-9.
```

Correctness bounds coverage (UA v1.0 §6): I19←4.1, I20←§2/4.7(MA-5),
I21←4.2/4.7(MA-8), I22←4.6, I23←4.3, I24←4.4, I25←4.5.
I14-I18 and G9-G12 are inherited conformance obligations re-run on the
evolved A1 (ordering stability, raw/derived separation, IndexSource
determinism, cross-domain integrity, judgment reviewability, SESSION/
cross-family capability conformance, unified restart/continue).

## 5. MA-DS-1 "Multi-Agent Research Day" — round-one operationalization

Binding DESIGN scenario (UA v1.0 §3A), exercised as a deterministic,
fixture-generated correctness scenario under the PB v1.2 master-seed
discipline. It is NOT a performance benchmark and NOT a completed
validation until executed and audited. Two actors, two families, one
carrier database:

```text
Fixture:  FILE carrier F1 (research file, K representation revisions)
          SESSION carrier S1 (research-day session)
          Actor identities A (research writer), B (lab organizer)
          Injected: clock skew; crash points C1-C3; retry episodes

 1  A creates F1 rev1 (POSIX entity bytes + registry + provenance)
 2  A opens S1, appends events (JUDGMENT, EVIDENCE_LINK → F1@rev1;
       formation + CC-5 mapping per §3 compound order)
 3  B reads F1 and S1 concurrently (MA-1)
 4  B reorganizes: MOVE F1 (locator transition, identity unchanged) and
       revises F1 → rev2 (MA-2 cross-family interleave)
 5  A, working from base rev1, attempts revise(expected=1) → CONFLICT,
       state unchanged, both authoritative histories intact (MA-3/I19)
 6  A rebases: re-reads rev2, reapplies → rev3, provenance
       from-version=2 (MA-3 rebase path)
 7  A and B append to S1 concurrently with injected clock skew →
       gapless total order by carrier allocation (MA-6/I23)
 8  A retries step-7 append after injected unknown-outcome (C1) with
       same operation_id → replayed outcome, zero duplication (MA-7/I24)
 9  Crash injection C2 inside A's compound operation (record+mapping+
       provenance) → all-or-nothing; integrity report typed; provenance
       completeness query clean (MA-4/I21)
10  FTS rebuild runs while writes continue (C3 window) → authority
       byte-identical, staleness detectable, rebuild-compare = identity
       + searchable-content coverage (MA-9/I25 + rebuild gate)
11  B multi-object read during A's commit → single committed version
       view (MA-10/I22)
12  Session summary materialization mid-stream → raw events intact,
       (SessionID, sequence) unchanged (CC-4/I14; F13 vocabulary)
13  Full-day audit: rename+revision+reindex+summary replayed → identity
       sets stable everywhere (MA-5/I20); historical judgment in S1
       remains reviewable against F1@rev1 via mapping (I17/I18)
```

Observation discipline: every step emits a structured evidence record
(step id, actors, operation ledger entries, state hashes, integrity
report, verdict field). Step-to-bound mapping is fixed above BEFORE
execution (pre-registration). Crash verdicts use the inherited
vocabulary PASS / REPAIR / DETACHED (FAIL forbidden as a crash
classification). Any suspected protocol defect STOPS the affected
judgment and requires a new Human ruling (PB v1.2 mid-run rule).

## 6. Verdict structure (layered, no total score)

```text
Per-mechanism verdicts:    §4.1-§4.7 chains (PASS / FAIL per criterion)
Per-bound verdicts:        I19-I25 (violation = candidate protocol
                           failure, never a reason to relax a bound)
Conformance:               inherited A1 suite (10/10 must not regress) +
                           G9/G10/G12 + new CC-MA conformance checks
                           derived mechanically from §4 criteria
Rebuild completeness:      PASS or INCOMPLETE (no full PASS without
                           authoritative searchable source coverage)
Scenario verdict:          MA-DS-1 per-step + whole-scenario verdict
INVALID:                   predefined protocol/environment violations
                           only (PB v1.2 §3.5 inherited)
No weighted total. No cross-candidate ranking in round one.
```

Defect protocol: if execution exposes a real UA v1.0 gap or defect, it
is RECORDED as a typed defect (UA-DF-n: description, evidence,
affected bound) and reported — never explained into a PASS, never
resolved by editing UA v1.0 or PB v1.2 in-round.

## 7. Execution order within the authorized U-A

```text
1  THIS MANIFEST (on record; requirement→mechanism→evidence→
   criterion→exercise chains fixed)
2  Mechanism implementation: evolve A1 (SQLite registry + POSIX entity
   store) with the §4 mechanisms; FILE + SESSION families; CC-5
   mapping; derived access L1+L2; no scope beyond the chains above
3  Conformance: A1 suite regression (10/10) + new CC-MA checks
4  Admission: build/test + integrity + pre-registration check
5  MA-DS-1 execution → structured evidence chain
6  Evidence chain packaged for Human audit (the Human audits the
   chain, not unevaluable code)
```

Steps 2-5 are inside the present authorization; the Human audit
(acceptance list items 1-8) follows step 6. Gate C is NOT declared
passed by any of this; Gate C closure is a separate Human action.

## 8. Negative space (standing, unchanged)

```text
no FileStore/SessionStore core semantic stores (one contract, two
  families; per-family physical tables are implementation detail);
no session fields on Information or Relation; no CarrierRecord→
  Information substitution; no derived artifact as fact/identity
  source; no Agent semantic object (AgentInformation/AgentRelation/
  AgentStore); no two-family concurrency split; no Universal Lock
  Manager; no client-timestamp ordering; no MemPalace integration or
  object-model copy; no UA v1.0/PB v1.2/Frozen Contract change; no
  backend selection/migration/Lab reorganization; no PB-U*
  calibration or larger benchmark in round one; MA-DS-1 is design+
  validation scenario, never retroactively "completed validation"
  evidence before execution.
```

Registered open decision inputs carried (not blockers): A-2 N:M
mapping default flagged for Human confirmation; A-3 FILE-family record
kinds remain opaque implementation kinds until Human decides; L3
semantic search absent with registered reason.

## 9. Change log

```text
v1.0 (2026-10-06): initial manifest under the Human U-2 authorization.
All mechanism decisions herein are U-2 mechanism-side decisions under
UA v1.0 §3/§3A; zero Frozen Contract change; zero protocol change.
```
