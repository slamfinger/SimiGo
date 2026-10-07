
# SRS-REAL-CLOSURE-01 — Database-Carrier Implementation Correction & Re-initialization Request v1.1

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE AUTHORIZED
> **Date:** 2026-10-08
> **Purpose:** remediate the blocking findings from Database-Carrier Implementation & Initialization Review Record 001 before any equivalence campaign.
> **Review binding:** 6ad78c765a761498e98d9b2ed602fe391ba5ab06
> **Prior implementation baseline:** 4588a9c4d936753b1897f6db251158bdb569b38a
> **Accepted design:** 21acba4e07f312fcb818968f33fd9e0c185fccf0 / blob 582c9b85c9ea1ec215a152d18d2ac0b6e0be1b25

## 1. Requested scope

Exactly one corrective work cycle:

    implementation correction;
    fresh empty re-initialization;
    provenance / selfcheck correction.

No equivalence campaign is requested or authorized by opening this Request.

## 2. Blocking corrections

### C-B1 — atomic logical write-group API

Correct the carrier so the accepted Design Package v0.1 §4.3 logical write groups can be composed through the declared DB interface without nested transaction failure.

Required:

    materialize: D object + dependency revision-1 = one atomic group;
    ES1: SRS object + SRS index append = one atomic group;
    ES2: continuation object + continuation index append = one atomic group;
    N1: D' object + dependency revision-2 = one atomic group.

The correction may use transaction-aware internal primitives or equivalent structure. It must not introduce new IS semantics.

Add fail-closed selfcheck coverage proving:

    group commit exposes all members together;
    group rollback exposes none of the members;
    single-operation writes remain atomic;
    no partial logical state is observable after failed groups.

### C-B2 — exact initialization provenance

After the corrected implementation is canonical, create a fresh empty SQLite-backed IS and a fresh initialization manifest.

The manifest must record at minimum:

    exact repaired implementation commit;
    final schema SHA256;
    implementation artifact SHA256 values;
    exact initialization command/argv;
    exact initialization cwd;
    UTC wall-clock start/end or equivalent execution time;
    process returncode;
    Python version;
    SQLite engine version;
    database file SHA256;
    database byte size;
    logical row counts;
    logical import = false;
    campaign state = NOT_AUTHORIZED.

The prior development database must not be reused as campaign evidence.

### C-C1 — exact interface name

Expose the Request-specified canonical method:

    get_dependency_history(dependency_id)

A compatibility alias such as dependency_history may exist only if it introduces no semantic behavior.

### C-C2 — authorizer / immutability claim

Resolve the mismatch between implementation documentation and actual behavior.

Preferred correction:

    install and test a fail-closed SQLite authorizer that prevents UPDATE,
    DELETE, destructive DDL, or equivalent carrier mutation against the
    committed logical stores through the carrier connection.

The selfcheck must verify the restriction rather than rely on source-text search alone.

### C-C3 — manifest naming reconciliation

Reconcile the v1.0 Request's manifest naming discrepancy:

    IMPLEMENTATION_MANIFEST.md vs IMPLEMENTATION_MANIFEST.json

The canonical correction record must declare the actual authoritative format and hash it.

## 3. Allowed paths

Only:

    database-carrier-replication/implementation/
    database-carrier-replication/initialization/
    relevant governance record(s) required to canonicalize the correction cycle

No runner, fixture, τN1, Schema Authority, EXEC-006 evidence, PALACE, LLM,
production integration, or broader research artifact may be modified.

## 4. Exact inherited bindings

    Design Package v0.1:
      commit 21acba4e07f312fcb818968f33fd9e0c185fccf0
      blob   582c9b85c9ea1ec215a152d18d2ac0b6e0be1b25
      sha256 73f80d26cd3bb6636b82edf29c71b57b9fc5fb028294d13edf519abb768c2cc4

    Review Record 001:
      commit 6ad78c765a761498e98d9b2ed602fe391ba5ab06

    Prior implementation baseline to correct:
      4588a9c4d936753b1897f6db251158bdb569b38a

    Prior initialization manifest to supersede:
      blob 6dbb53c369a797017beedaab120554759738722d
      database sha256 6baa7afa8b5c623c75b3111af267e270d76d663547e730af5e7ca62b7602d14d

The prior implementation and initialization are evidence inputs to the correction,
not reusable campaign evidence.

## 5. Forbidden scope

    NO equivalence campaign;
    NO equivalence adjudication;
    NO logical import;
    NO campaign IS mutation;
    NO runner modification;
    NO fixture modification;
    NO τN1 or Schema Authority modification;
    NO reinterpretation of EXEC-006;
    NO PALACE / production / LLM integration;
    NO broader carrier or Execution State claim;
    NO reuse of the prior development database as campaign evidence;
    NO automatic transition to campaign after completion.

## 6. Budget and stop condition

    correction work cycles          = 1
    equivalence campaign budget     = 0
    IS mutation budget              = 0
    observer budget                 = 0
    automatic follow-on             = FORBIDDEN

Completion STOP requires:

    corrected implementation commit;
    fresh initialization manifest;
    corrected selfcheck result;
    exact artifact hashes/provenance;
    explicit statement READY FOR EQUIVALENCE CAMPAIGN AUTHORIZATION;
    CarrierSQLite equivalence = NOT ESTABLISHED.

## 7. Required Human decision

    APPROVE CORRECTION + REINITIALIZATION
      authorize exactly one corrective work cycle, then STOP for review.

    APPROVE CORRECTION ONLY
      authorize implementation correction but no initialization execution.

    REVISE REQUEST
      return with registered defects.

    DENY REQUEST
      do not modify implementation or initialization.

Opening this Request authorizes no stage.
