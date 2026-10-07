
# SRS-REAL-CLOSURE-01 — Database-Carrier Implementation & Initialization Review Record 001

> **Status:** TECHNICAL REVIEW COMPLETE — REVISE REQUIRED
> **Date:** 2026-10-08
> **Review basis:** Human-directed review of the scoped implementation + initialization outputs
> **Reviewed implementation:** 4588a9c4d936753b1897f6db251158bdb569b38a
> **Canonical navigation at review start:** b6114287e8834ecdd09bc5836e3d17c34a71fc90
> **Accepted design binding:** 21acba4e07f312fcb818968f33fd9e0c185fccf0 / blob 582c9b85c9ea1ec215a152d18d2ac0b6e0be1b25

## 1. Review ruling

The implementation / initialization work cycle is **NOT ACCEPTED AS CAMPAIGN-READY**.

The work produced a plausible database-backed IS carrier and a fresh empty SQLite file, but two blocking defects prevent the result from serving as an exact-bound implementation/provenance baseline for a future equivalence campaign.

    implementation output        = REVISE REQUIRED
    empty initialization         = REVISE REQUIRED
    equivalence campaign         = NOT AUTHORIZED
    CarrierSQLite equivalence    = NOT ESTABLISHED
    EXEC-006 bounded finding     = unchanged / ACCEPTED

## 2. Blocking defect B1 — logical write-group atomicity is not expressible through the public API

Accepted Design Package v0.1 §4.3 requires logical write groups to become visible atomically, including:

    materialize: D object + dependency revision-1
    ES1:         SRS object + SRS index append
    ES2:         continuation object + continuation index append
    N1:          D' object + dependency revision-2

The implementation exposes DatabaseBackedIS.transaction(), but every public mutation method independently enters BEGIN IMMEDIATE.

Therefore an outer logical group such as:

    with carrier.transaction():
        carrier.write_object(...)
        carrier.append_index_entry(...)

causes a nested transaction attempt. The README itself presents this pattern, so the documented logical write-group API is not executable as written.

Consequence:

    public DB.* methods
            ↓
    cannot express the accepted compound atomic write groups
            ↓
    Design Package §4.3 is not faithfully realized

This is a carrier-semantic blocker, not merely a documentation issue.

Required correction:

    provide transaction-aware internal primitives or equivalent API structure;
    allow one outer logical transaction to compose object/index/dependency writes;
    retain single-operation atomicity;
    add selfcheck coverage proving commit-together / rollback-together behavior;
    do not introduce new IS semantics.

## 3. Blocking defect B2 — initialization provenance is not exact-bound to implementation 4588a9c

The committed initialization manifest records:

    exact_execution_repository_commit = 177ca64fd6b6e4d3ff2e81b2a131b936ab9bd6af

while the implementation work cycle was canonicalized at:

    4588a9c4d936753b1897f6db251158bdb569b38a

The manifest therefore does not prove that the initialized database was created from the final implementation work-cycle commit.

The Request v1.0 additionally required initialization provenance for:

    schema hash
    exact implementation commit
    initialization command
    cwd
    wall-clock time
    returncode
    engine/version
    database SHA256
    database byte size

The committed manifest contains engine/version, database SHA256/size, time, implementation artifact hashes, and row counts, but does not record the required schema hash, initialization command, cwd, or returncode.

Consequence:

    fresh database file
            +
    current manifest
            ↓
    cannot establish exact implementation/runtime provenance

Required correction:

    repair implementation first;
    freshly initialize a new empty database after the repaired implementation commit;
    record exact repaired implementation commit;
    record final schema SHA256;
    record exact command, cwd, UTC time, returncode, engine/version;
    record database SHA256 and byte size;
    do not reuse the existing development database as campaign evidence.

## 4. Additional conformance findings

### C1 — requested interface name mismatch

Request v1.0 required:

    get_dependency_history(dependency_id)

The implementation provides:

    dependency_history(dependency_id)

The two are semantically aligned, but the requested interface name is not exact. The correction cycle shall expose the requested canonical method; a compatibility alias may be retained only if it adds no semantic behavior.

### C2 — false authorizer claim

db_is.py documentation states that UPDATE/DELETE statements are denied by the connection's SQLite authorizer, but the implementation does not install such an authorizer.

This is not accepted as evidence of immutability. The correction cycle must either:

    implement the claimed fail-closed authorizer restriction

or

    remove the claim and provide an explicitly bounded equivalent

The preferred correction is the former because it makes the carrier boundary auditable.

### C3 — governance deliverable naming mismatch

Request v1.0 §5 names IMPLEMENTATION_MANIFEST.md, while the actual artifact is IMPLEMENTATION_MANIFEST.json.

This does not alter carrier semantics, but it is a canonical request/output mismatch and must be reconciled in the next governance record before the campaign gate.

## 5. Passed / retained findings

The following remain supported by the reviewed artifacts:

    accepted Design Package v0.1 is exact-bound in IMPLEMENTATION_MANIFEST.json;
    schema contains the three intended logical stores;
    object addressing uses lowercase SHA256;
    SRS resolution uses first matching append entry;
    dependency resolution uses LAST entry;
    empty initialization contains zero logical rows;
    no logical import occurred;
    18/18 storage selfcheck was reported PASS;
    equivalence campaign was not run;
    CarrierSQLite equivalence remains NOT ESTABLISHED.

These findings do not override B1/B2.

## 6. Scope ruling

No runner, fixture, τN1, Schema Authority, EXEC-006 evidence, PALACE integration, LLM integration, or broader claim is implicated.

The accepted EXEC-006 result remains:

    ES1 -> persisted document-form IS(SRS) -> independent ES2 REUSE
    = ACCEPTED bounded finding

No semantic reinterpretation is made.

## 7. Required next governance object

The lawful next object is a new Human authorization Request scoped only to:

    implementation correction;
    fresh empty re-initialization;
    provenance / selfcheck repair.

It must exact-bind:

    accepted Design Package v0.1
    implementation baseline 4588a9c
    current initialization manifest to be superseded

and must retain:

    equivalence campaign budget = 0
    IS mutation budget          = 0
    runner/fixture/τ            = 0
    automatic campaign follow-on = FORBIDDEN

Until that Request is approved and completed:

    equivalence campaign = NOT AUTHORIZED
    CarrierSQLite equivalence = NOT ESTABLISHED
