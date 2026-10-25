# SRS-REAL-CLOSURE-01 — EXEC-005 Schema Authority Forensic Audit Record

> **Status:** READ-ONLY HUMAN EVIDENCE AUDIT CLOSED
> **Date:** 2026-10-07
> **Audit object:** canonical campaign evidence `5c5fcc4…` against exact
> post-completion execution state `fef0b2f…`
> **Authorization effect:** NONE

## 1. Audited chain

```text
request_v0_7 =
  commit e721f7a7460d3fbe0fe42c388bd4d07ce44709c2,
  blob e04a1219931327fc9a612d7e328a458f27085a8f,
  sha256 fa393cabb5af5f881c912d5b8b12c6791c25c33240bc166ec3b8e0c52998b577;

tau_interface_completion_commit =
  fef0b2fa5b3ac817a099bac885522fd17f4d3362;

records_005_commit =
  afca0d0519d40643fbfa279ec8fe3bc40f264d01;

campaign_evidence_commit =
  5c5fcc44e4d34742f45a2b492ac95b63e1101fff;

campaign_run_id = exec-005-fef0b2f;
campaign_outcome = INVALID;
stop_code = TAU_N1_D_PRIME_FIELD_PLACEMENT_MISMATCH.
```

This audit did not execute runner, observer, mutate-n1, ESN, or any campaign
stage; did not modify τN1, runner, fixture, authorization records, or IS state;
and did not draft a corrected Request.

## 2. Interface facts

Exact runner at `fef0b2f` consumes:

```text
tau["d_prime_seed_path"];
tau["dependencies"][0]["dependency_id"].
```

Completed τN1 schema approved by Request v0.7 declares:

```text
dependencies[0].d_prime_seed_path;
dependencies[0].dependency_id.
```

Thus the runner expects top-level `d_prime_seed_path`, while the completed
schema places it inside `dependencies[0]`.

## 3. Authority history

The original fixture preparation commit `d6507ff` introduced both sides of the
interface:

```text
1. runner mutate-n1 reading top-level tau["d_prime_seed_path"];
2. tauN1.json without that top-level field.
```

No Design v0.2 section, Manifest v1/v2/v3/v4, fixture preparation Request, or
completion record declared an authoritative τN1 interface schema assigning
field placement. Request v0.7 later called its nested schema “completed,” but
did not cite an authoritative schema source and did not reconcile the field
placement with exact runner consumption.

## 4. Ruling

```text
AUDIT_C = ACCEPTED;
root_cause_class =
  TAU_N1_RUNNER_SCHEMA_AUTHORITY_ABSENCE;
responsibility = SHARED / BILATERAL;
one_sided_request_schema_defect = REJECTED;
one_sided_runner_defect = REJECTED.
```

The defect is not merely that Request v0.7 chose the wrong schema. Nor is it
merely that the runner chose an inconvenient interface. The governing defect is
that two exact-bound artifacts were approved without a prior authoritative τN1
interface schema defining ownership and placement of `d_prime_seed_path`,
`dependencies`, D' SHA256, and revision.

## 5. Campaign classification

```text
campaign_result = INVALID;
semantic_experiment_result = PARTIALLY LAUNCHED / NOT VALIDLY COMPLETED;
materialize = PASS;
ES1 = PASS;
ES2 = PASS;
ES2 observed REUSE = INVALID AS CAMPAIGN EVIDENCE;
mutate-n1 = FAIL;
N1 mutation = NOT PERFORMED;
N1 BLOCK = ABSENT;
E1-E6 = INCOMPLETE / NOT JOINTLY ESTABLISHED;
semantic_hypothesis = NEITHER SUPPORTED NOR REFUTED;
core_claim = NOT ESTABLISHED.
```

## 6. Boundary

```text
execution_campaign_budget = consumed;
observer_use_budget = consumed;
IS_MUTATION_campaign_budget = consumed by partial lawful writes;
D'_addition/revision-2 write = NOT PERFORMED;
rerun = NOT AUTHORIZED;
τN1 repair = NOT AUTHORIZED;
runner repair = NOT AUTHORIZED;
automatic renewal = forbidden.
```

## 7. Next lawful object

The next lawful object is a Human decision whether to authorize a corrected
Request/record set. Any future correction must first establish an authoritative
τN1 interface schema, reconcile it with exact runner consumption, and add
fail-closed schema validation. This record does not draft, approve, or authorize
that correction.

## 8. Record integrity

```text
record_integrity_binding = registered by the governing commit introducing this
audit record on main; later modification creates a new content address and
voids this audit record.
```
