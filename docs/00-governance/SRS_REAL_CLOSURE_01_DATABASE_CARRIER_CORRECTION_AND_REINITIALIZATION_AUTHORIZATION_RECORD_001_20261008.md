# SRS-REAL-CLOSURE-01 — Database-Carrier Correction & Re-initialization Authorization Record 001

> **Status:** APPROVE CORRECTION + REINITIALIZATION
> **Date:** 2026-10-08
> **Human ruling, exact form:** “APPROVE CORRECTION + REINITIALIZATION” on
> Request v1.1.
> **Boundary:** exactly one corrective work cycle for implementation
> correction, fresh empty re-initialization, and provenance/selfcheck
> correction. No equivalence campaign, logical import, campaign IS mutation,
> runner/fixture/τ modification, or broader claim.

## 1. Authorization identity

```text
authorization_identity =
  SRS_REAL_CLOSURE_01_DATABASE_CARRIER_CORRECTION_AND_REINITIALIZATION_AUTHORIZATION_RECORD_001;
+authorization_kind = APPROVE CORRECTION + REINITIALIZATION;
+approved_request_identity =
+  SRS_REAL_CLOSURE_01_DATABASE_CARRIER_IMPLEMENTATION_CORRECTION_AND_REINITIALIZATION_REQUEST_V1_1;
+approved_request_commit = 94caee8093ee2341c60dda05e2f25e7d703dd69e;
+approved_request_git_blob_sha =
+  0d57564e1b443fc7c0ba01eb948825e9acda3dd1;
+approved_request_sha256 =
+  250c2bf3760e9910ff80540a32b3b439d4d5e3d7b0e8f43cf5a7fb5d97a06c78;
+human_ruling_identity =
+  HUMAN_RULING_20261008_CORRECTED_EXECUTION_REQUEST_V1_1_APPROVE_CORRECTION_PLUS_REINITIALIZATION;
+human_ruling_content = “APPROVE CORRECTION + REINITIALIZATION”;
+review_binding_commit = 6ad78c765a761498e98d9b2ed602fe391ba5ab06;
+prior_implementation_baseline = 4588a9c4d936753b1897f6db251158bdb569b38a;
+corrective_work_cycles = 1;
+equivalence_campaign_budget = 0;
+IS_MUTATION_budget = 0;
+observer_budget = 0;
+automatic_follow_on = forbidden.
+```
+
+## 2. Authorized corrective scope
+
+```text
+fix C-B1 atomic logical write-group API without nested transaction failure;
+fix C-C1 canonical interface get_dependency_history(dependency_id);
+fix C-C2 install/test fail-closed SQLite authorizer for UPDATE, DELETE and
+  destructive logical DDL;
+correct selfcheck coverage for atomic commit/rollback and authorizer denial;
+fresh empty SQLite-backed re-initialization;
+complete exact initialization provenance: repaired implementation commit,
+  final schema SHA256, implementation artifact hashes, exact argv/cwd,
+  UTC timing, returncode, Python/SQLite versions, database hash/size, row
+  counts, logical_import=false, campaign_state=NOT_AUTHORIZED;
+declare IMPLEMENTATION_MANIFEST.json as the authoritative implementation
+  manifest format and record its hash.
+```
+
+## 3. Allowed paths and boundary
+
+```text
+database-carrier-replication/implementation;
+database-carrier-replication/initialization;
+governance record(s) canonicalizing this authorization/correction.
+```
+
+No runner, fixture, τN1, Schema Authority v1, EXEC-006 evidence, PALACE, LLM,
+production integration, equivalence campaign, logical import, campaign IS
+mutation, observer execution, prior database reuse, or broader claim is
+authorized.
+
+## 4. Completion STOP
+
+After correction and fresh initialization:
+
+```text
+STOP for Human review.
+CarrierSQLite equivalence = NOT ESTABLISHED;
+core claim = NOT ESTABLISHED.
+```
+
+## 5. Record integrity
+
+```text
+record_integrity_binding = registered by the governing commit introducing this
+authorization on main; later modification creates a new content address and
+voids it.
+```
