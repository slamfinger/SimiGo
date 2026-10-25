# SRS-REAL-CLOSURE-01 — Database-Carrier Replication Design Package Acceptance Record 001

> **ARCHIVED** 2026-10-20 · line: E-I 连续计算 · original: docs/00-governance/SRS_REAL_CLOSURE_01_DATABASE_CARRIER_REPLICATION_DESIGN_PACKAGE_ACCEPTANCE_RECORD_001_20261008.md
> Evidence status: unchanged (content frozen; moved only)


> **Status:** DESIGN PACKAGE v0.1 ACCEPTED — DESIGN ONLY
> **Date:** 2026-10-08
> **Human ruling, exact form:** “批准Design Package v0.1” on Design Package
> v0.1 = ACCEPT.

## 1. Acceptance identity

```text
acceptance_record_identity =
  SRS_REAL_CLOSURE_01_DATABASE_CARRIER_REPLICATION_DESIGN_PACKAGE_ACCEPTANCE_RECORD_001;
accepted_design_package =
  SRS_REAL_CLOSURE_01_DATABASE_CARRIER_REPLICATION_DESIGN_PACKAGE_V0_1;
accepted_design_commit = 21acba4e07f312fcb818968f33fd9e0c185fccf0;
accepted_design_git_blob_sha =
  582c9b85c9ea1ec215a152d18d2ac0b6e0be1b25;
accepted_design_sha256 =
  73f80c26cd3bb6636b82edf29c71b57b9fc5fb028294d13edf519abb768c2cc4;
design_navigation_commit_at_submission =
  0522f5566c361b4711e360c3c3dc6f915f573b2a;
human_ruling_identity =
  HUMAN_RULING_20261008_DATABASE_CARRIER_DESIGN_PACKAGE_V0_1_ACCEPT;
human_ruling_content = “批准Design Package v0.1” = ACCEPT.
```

## 2. Accepted design boundary

The accepted package establishes the authoritative design-only contract for a
future database-carrier substitution study:

```text
carrier substitution:
  document-form IS -> database-backed IS;

carrier-independent IS logical model:
  immutable SHA256 content-addressed objects;
  append-only SRS / continuation index;
  LAST-entry dependency resolution;
  exact logical reads only;

database-backed interface/schema:
  init_empty, write_object, get_object, append_index_entry,
  resolve_srs_identity, append_dependency_entry,
  resolve_current_dependency;
  required tables and immutable/append-order constraints;
  atomic logical write groups;

prohibited database-side semantics:
  implicit identity or revision generation;
  order-changing or collation-dependent matching;
  cascade/trigger/stored-procedure semantic mutation;
  soft delete;
  carrier-specific conflict resolution;
  eventual consistency;
  extra observable semantic state;

equivalence assertions:
  EQ-1 object set/bytes/hash;
  EQ-2 object immutability;
  EQ-3 index records/order;
  EQ-4 dependency history;
  EQ-5 current resolution;
  EQ-6 read results;
  EQ-7 ES2 REUSE and ESN BLOCK;
  EQ-8 no extra observable state;

reject conditions:
  REJ-1 through REJ-14;

initialization:
  preferred empty database-backed IS;
  optional explicit logical import only under future authorization;

non-goals:
  PALACE, production, LLM, multi-carrier federation, distributed consensus,
  performance/concurrency certification, backup certification,
  general database abstraction, or broad carrier-equivalence claims.
```

## 3. Review ruling

```text
review_item_1 = ACCEPTED: document-form and database-form share logical IS
  semantics only;
review_item_2 = ACCEPTED: database interface/schema expresses the existing IS
  without introducing extra execution semantics;
review_item_3 = ACCEPTED: EQ-1 through EQ-8 can adjudicate carrier
  equivalence rather than mere equal final results;
review_item_4 = ACCEPTED: REJ-1 through REJ-14 cover registered hidden-state,
  metadata, ordering, recovery, and extra-state rejection classes;
review_item_5 = ACCEPTED: scope containment prevents implementation,
  SQLite candidate, CarrierSQLite equivalence, PALACE, and broader SimiGo
  claims from being conflated.
```

## 4. Acceptance boundary

```text
ACCEPT means:
  Design Package v0.1 is accepted as the design-only contract;
  carrier equivalence remains NOT ESTABLISHED;
  SQLite remains only a design reference candidate;
  implementation remains NOT AUTHORIZED;
  initialization remains NOT AUTHORIZED;
  campaign remains NOT AUTHORIZED;
  IS mutation remains NOT AUTHORIZED;
  automatic follow-on remains FORBIDDEN.

NOT AUTHORIZED:
  database implementation or initialization;
  campaign execution;
  IS mutation;
  runner/fixture/τ modification;
  semantic reinterpretation of EXEC-006;
  PALACE/production/LLM integration;
  broader carrier-equivalence or research claims.
```

Any implementation, initialization, or campaign requires a new explicit Human
authorization exact-binding accepted Design Package v0.1, the implementation
commit, and all runtime/carrier provenance.

## 5. Record integrity

```text
record_integrity_binding = registered by the governing commit introducing this
acceptance record on main; later modification creates a new content address
and voids this acceptance.
```
