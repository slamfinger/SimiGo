# SRS-REAL-CLOSURE-01 — Database-Carrier Replication Implementation & Initialization Request v1.0

> **Status:** OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW — NO STAGE
> AUTHORIZED
> **Date:** 2026-10-08
> **Human opening direction, exact form:** Human directed the next stage as
> **Database-Carrier Replication — implementation & initialization**, with
> campaign execution and broader claims explicitly excluded.
> **Requested stage set:**
>
> ```text
> implementation;
> initialization;
> provenance / audit preparation.
> ```
>
> **Excluded stage set:**
>
> ```text
> equivalence campaign;
> equivalence adjudication;
> IS mutation beyond initialization;
> runner modification;
> fixture modification;
> τ modification;
> semantic reinterpretation;
> PALACE integration;
> LLM integration;
> broader carrier or research claims.
> ```
>
> **No implementation, initialization, campaign, or run authority exists from
> opening this Request.**

## 1. Purpose

This Request authorizes, only after Human `APPROVE`, one scoped work cycle to
faithfully implement the accepted database-backed IS interface/schema and
initialize an auditable empty database-backed IS. It does **not** authorize an
equivalence campaign and does **not** claim CarrierSQLite equivalence.

Upon completion, the lawful result is only:

```text
database-backed IS implementation
+ canonical empty initialization
+ provenance / audit preparation
    ↓
READY FOR EQUIVALENCE CAMPAIGN
```

It is not:

```text
implementation → equivalence established ✗
```

## 2. Exact inherited bindings

```text
accepted_design_package =
  SRS_REAL_CLOSURE_01_DATABASE_CARRIER_REPLICATION_DESIGN_PACKAGE_V0_1
  @ 21acba4e07f312fcb818968f33fd9e0c185fccf0,
  git:blob:582c9b85c9ea1ec215a152d18d2ac0b6e0be1b25,
  sha256 73f80c26cd3bb6636b82edf29c71b57b9fc5fb028294d13edf519abb768c2cc4;

design_acceptance_record =
  SRS_REAL_CLOSURE_01_DATABASE_CARRIER_REPLICATION_DESIGN_PACKAGE_ACCEPTANCE_RECORD_001
  @ 9ac532025a24d49a88a7ebec492304dbc44af4ce,
  git:blob:1a96670fdea18eef5e7838c6d3144491eae52587,
  sha256 63f896c17fe57a2868652d048d0c26d2d20594f9a45ecc6ec3c3a4521386d75b;

schema_authority_v1 =
  SRS_REAL_CLOSURE_01_TAU_N1_INTERFACE_SCHEMA_AUTHORITY_V1
  @ a3e449cfaf92af76fec02f2dc2ca39d75c2ecbc6,
  git:blob:e180f305d335059be5986c2e3674927576578198,
  sha256 8bf913d9a2fc3843566f52fece1f2bdac5a375e2237d85c23e5fed47a764d564;

accepted_bounded_baseline =
  feb0a61f2ed87079c2a9e3572d0e1a3c9f9f0;

document_form_accepted_campaign =
  EXEC-006-69b2227, evidence cb365a44c48d4b7b90b4cc2155fcae00d3e01572.
```

The implementation shall faithfully realize accepted Design Package v0.1 §4–§7:
immutable SHA256 objects, append-only index and dependency history,
LAST-entry dependency resolution, exact logical reads, atomic logical write
groups, and all prohibited database-side semantics.

## 3. Authorized implementation scope

Upon Human `APPROVE`, one work cycle may create and modify only:

```text
database-carrier-replication/implementation/
database-carrier-replication/initialization/
```

The proposed implementation language is Python 3 standard library plus the
standard-library `sqlite3` module. No third-party dependency, network access,
daemon, server, ORM, migration framework, or background process is authorized.

Required implementation artifacts:

```text
database-carrier-replication/implementation/db_is.py;
database-carrier-replication/implementation/README.md;
database-carrier-replication/implementation/schema.sql;
database-carrier-replication/implementation/selfcheck.py;
database-carrier-replication/initialization/initialize_empty_db.py;
database-carrier-replication/initialization/INITIALIZATION_DESIGN.md.
```

`db_is.py` shall implement, without semantic additions:

```text
init_empty();
write_object(bytes);
get_object(object_id);
append_index_entry(entry);
resolve_srs_identity(srs_identity);
append_dependency_entry(entry);
resolve_current_dependency(dependency_id);
get_dependency_history(dependency_id);
verify_object(object_id);
transaction boundaries for each logical write group.
```

Required behavior is exactly accepted Design Package v0.1:

```text
object_id = lowercase hex SHA256(bytes);
same bytes to same object_id are idempotent;
different bytes to an existing object_id fail OBJECT_BYTE_MISMATCH;
objects are immutable after insert;
SRS index resolution preserves document-form first-match behavior;
dependency current resolution is LAST entry per dependency_id;
dependency history remains append-only and readable;
logical write groups are transactional;
crash before commit leaves no partial logical operation;
no update/delete/truncate/rewrite of committed logical rows;
no cascade, trigger, stored procedure, soft delete, or extra semantic state;
no database-generated identity or revision replaces SHA256/explicit revision;
no network, ORM, migration framework, daemon, telemetry, or third-party
  dependency.
```

`schema.sql` shall declare only the three logical stores from Design Package
v0.1 §4.2:

```text
is_objects;
is_index_entries;
dependency_entries.
```

Indexes for lookup are allowed, but are non-semantic implementation detail.

## 4. Authorized initialization scope

Upon Human `APPROVE`, the initialization tool may create exactly one new empty
database-backed IS in the authorized initialization directory:

```text
database-carrier-replication/initialization/empty_is.sqlite
```

It shall:

```text
refuse to overwrite an existing database file;
create only the three logical stores;
insert zero logical rows;
record database engine/version;
record final database file SHA256 and byte size;
record schema hash;
record exact implementation commit and implementation artifact hashes;
record initialization command, cwd, wall-clock time, and returncode;
fail closed if schema verification fails.
```

No SRS object, D object, D' object, index entry, dependency entry, continuation
entry, logical import, or campaign state may be created.

No database file needs to be committed; the initialization tool, schema, and
initialization manifest are canonical work products. A future equivalence
campaign must initialize a fresh database and may not reuse this development
database as evidence.

## 5. Provenance and audit preparation

The work cycle shall prepare, but not execute, the future equivalence audit by
delivering:

```text
database-carrier-replication/initialization/AUDIT_REQUIREMENTS.md;
database-carrier-replication/initialization/
  EQUIVALENCE_OBSERVATION_PLAN_DRAFT.md;
database-carrier-replication/initialization/IMPLEMENTATION_MANIFEST.md.
```

These shall enumerate:

```text
engine/version and file/container provenance fields;
schema hash and logical schema version;
transaction boundaries;
object/index/dependency observation points;
EPR004-equivalent process and artifact checks;
EQ-1 through EQ-8 observation mappings;
REJ-1 through REJ-14 fail-closed mappings;
explicit exclusions.
```

No equivalence judgment is authorized.

## 6. Forbidden scope

```text
NO equivalence campaign execution;
NO equivalence claim or adjudication;
NO IS mutation beyond creation of an empty initialized schema;
NO logical import;
NO D, D', SRS, continuation, index, or dependency rows;
NO runner modification;
NO document fixture modification;
NO τN1 modification;
No Schema Authority v1 modification;
NO PALACE / production / LLM integration;
NO network access;
NO third-party dependency or daemon;
NO semantic reinterpretation of EXEC-006;
NO broadening of the accepted bounded finding.
```

## 7. Work-cycle completion boundary

After implementation and initialization, STOP and submit:

```text
implementation commit;
post-implementation artifact hashes;
initialization manifest;
schema/implementation self-check results;
audit requirements and observation plan draft;
explicit statement:
  READY FOR EQUIVALENCE CAMPAIGN AUTHORIZATION;
  CarrierSQLite equivalence NOT ESTABLISHED.
```

No equivalence campaign may start until a new Human-directed Request/records
exact-bind the post-implementation commit and authorize the campaign.

## 8. Required Human decision

```text
APPROVE IMPLEMENTATION + INITIALIZATION
  authorize exactly one scoped work cycle; implement and initialize; STOP for
  review.

APPROVE IMPLEMENTATION ONLY
  authorize implementation artifacts but no initialization execution.

REVISE REQUEST   return with registered defects.
DENY REQUEST     do not implement or initialize.
```

Opening this Request authorizes no stage. CarrierSQLite equivalence remains
**NOT ESTABLISHED**, and the accepted EXEC-006 bounded result remains strictly
limited to document-form IS.
