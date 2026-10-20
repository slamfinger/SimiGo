# SRS-REAL-CLOSURE-01 — Database-Carrier Replication Design Authorization Record 001

> **ARCHIVED** 2026-10-20 · line: E-I 连续计算 · original: docs/00-governance/SRS_REAL_CLOSURE_01_DATABASE_CARRIER_REPLICATION_DESIGN_AUTHORIZATION_RECORD_001_20261007.md
> Evidence status: unchanged (content frozen; moved only)


> **Status:** HUMAN-DIRECTED REQUEST AUTHORIZED — DESIGN / SCHEMA AUTHORITY
> ONLY
> **Date:** 2026-10-07
> **Stage:** Database-Carrier Replication — Design
> **Human ruling, exact form:** “选 **Database-Carrier Replication**，但第一步
> 只授权 **design / schema authority**，不要直接授权 execution campaign。”

## 1. Authorization identity

```text
authorization_identity =
  SRS_REAL_CLOSURE_01_DATABASE_CARRIER_REPLICATION_DESIGN_AUTHORIZATION_RECORD_001;
authorization_kind = HUMAN_DIRECTED_DESIGN_AUTHORIZATION_RECORD;
stage = Database-Carrier Replication — Design;
requested_stage_set = {
  design;
  schema authority;
  carrier equivalence criteria;
};
excluded_stage_set = {
  execution;
  mutation;
  implementation;
  campaign;
};
baseline_canonical_stop = feb0a61f2ef2ed87079c2a9e3572d0e1a3c9f9f0;
```

## 2. Frozen accepted baseline

```text
EXEC-006 = VALID;
Human Evidence Audit = ACCEPTED;
bounded finding = ACCEPTED;

accepted_bounded_finding =
  ES1 -> IS(SRS) -> independent ES2 lawful reuse = ESTABLISHED;

accepted_scope =
  round-1 instrumented form;
  deterministic substrate;
  document-form IS;
  registered detection boundary.
```

This authorization does not broaden the accepted finding. It does not state or
imply that PALACE, CarrierSQLite, arbitrary databases, arbitrary ES
implementations, LLM autonomy, production SimiGo, or a general Execution State
theorem are established.

## 3. Authorized research objective

The sole objective is to design a controlled carrier-substitution study:

```text
document-form IS
        ↓
database-backed IS
```

while freezing:

```text
ES semantics;
ES behavior;
τ contracts;
decision boundary;
detection boundary;
IS logical content and ordering;
write-once / append-only semantics;
E1-E6 and N1 acceptance criteria.
```

The design must answer:

```text
1. what exactly the database carrier replaces;
2. what document-form semantics must remain observable;
3. which database operations are equivalent to document-form writes and reads;
4. how write-once objects, append-only index, and LAST-entry mapping are
   represented;
5. how carrier failure, concurrency, durability, and partial write cases are
   handled;
6. how equivalence is measured and rejected;
7. what provenance and audit evidence the future campaign must produce.
```

## 4. Authorized design outputs

One design work cycle may produce:

```text
1. Database-Carrier Replication Design Package v0.1;
2. authoritative database-backed IS interface/schema;
3. document-IS ↔ database-IS semantic mapping;
4. carrier equivalence criteria and rejection criteria;
5. initialization / migration design;
6. provenance, observation, and audit requirements;
7. explicit non-goals and exclusions.
```

The initial reference candidate may be designed as SQLite-backed IS, but the
design must keep the carrier interface explicit enough that SQLite is not
smuggled in as a broader established claim.

## 5. Forbidden scope

```text
NO database implementation;
NO database initialization;
NO campaign execution;
NO IS mutation;
NO runner modification;
NO fixture modification;
NO τN1/τ contract modification;
NO semantic reinterpretation of EXEC-006;
NO PALACE/production/LLM integration;
NO broadening of the accepted finding.
```

## 6. Budget and stop

```text
database_carrier_design_work_cycle_budget = 1;
execution_campaign_budget = 0;
IS_MUTATION_budget = 0;
observer_budget = 0;
automatic_follow_on = forbidden.
```

After the design outputs are canonical, the stage stops for Human review.
Whether to authorize implementation or campaign requires a new explicit Human
decision.

## 7. Record integrity

```text
record_integrity_binding = registered by the governing commit introducing this
authorization on main; later modification creates a new content address and
voids this authorization.
```
