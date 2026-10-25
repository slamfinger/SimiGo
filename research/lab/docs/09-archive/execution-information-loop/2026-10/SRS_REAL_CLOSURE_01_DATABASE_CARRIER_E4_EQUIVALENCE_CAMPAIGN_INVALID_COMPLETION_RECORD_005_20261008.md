# SRS-REAL-CLOSURE-01 — Database-Carrier E4 Equivalence Campaign Invalid Completion Record 005

> **ARCHIVED** 2026-10-20 · line: E-I 连续计算 · original: docs/00-governance/SRS_REAL_CLOSURE_01_DATABASE_CARRIER_E4_EQUIVALENCE_CAMPAIGN_INVALID_COMPLETION_RECORD_005_20261008.md
> Evidence status: unchanged (content frozen; moved only)


> **Status:** RAW INVALID COMPLETION — HUMAN EVIDENCE AUDIT NOT OPEN
> **Date:** 2026-10-08
> **Campaign:** exec-dbcarrier-004-8c7aca5
> **Governing Request v1.6 commit:** b5f15cb5309d7619ba2e03eefaeac74712890462
> **R3 corrected execution base:** 8c7aca5c10dcd4ec3560897cb7537990d2bc9e6e

## 1. Ruling disposition

E4 is **INVALID / NON-ADJUDICATIVE**. It executed the frozen O0–O5 sequence
and corrected observer persistence succeeded, but the campaign then failed to
persist `preflight_verification.json`. Therefore the complete evidence chain
was not produced and the raw sequence cannot be promoted to an equivalence
result.

```text
outcome = INVALID / NON-ADJUDICATIVE;
stop_code =
  CAMPAIGN_PREFLIGHT_VERIFICATION_JSON_SERIALIZATION_DEFECT;
root_cause_class =
  HARNESS_POST_SEQUENCE_PREFLIGHT_JSON_PATH_SERIALIZATION_DEFECT.
```

## 2. Accepted raw campaign facts

```text
authoritative preflight before sequence = 30/30 PASS;
O0 logical state                        = 0 objects / 0 index / 0 dependencies;
O5 logical state                        = 4 objects / 2 index / 2 dependencies;
SQLite integrity                        = OK;
raw ES2 primaryDecision                 = REUSE / REUSE_PATH;
raw ESN primaryDecision                 = BLOCK / BLOCKED_NON_RECOMPUTE_PATH;
observer verdict                        = PERSISTED;
canonical C3 key                        = C3_persisted_vs_resolved_byte_equality;
byte persistence self-check             = PASS;
parsed-object equality self-check       = PASS.
```

The observer-persistence defect from EXEC-DB-003 is closed as a raw harness
fact. This does not authorize equivalence.

## 3. New fail-closed defect

After observer persistence, EQ/REJ derivation, campaign outcome and database
validation writes, the harness attempted to serialize the final preflight
record and raised:

```text
TypeError: Object of type PosixPath is not JSON serializable
```

The affected destination was `PREFLIGHT_VERIFICATION`. This is a campaign
evidence-layer serialization defect only. It is not attributed to carrier
semantics, schema, ES2/ESN semantics, decision boundary, tau, fixture, runner,
T-IMPL-01, or EQ/REJ criteria.

## 4. Evidence disposition

Raw O0–O5 observations and transaction facts are accepted as facts only. The
mechanically present `campaign_outcome.json`, `eq_rej_matrix.json` and
`runtime_provenance.json` are non-authoritative because the final campaign
evidence chain is incomplete.

Required authoritative artifacts absent at stop:

```text
preflight_verification.json;
campaign_process_result.json;
campaign_stderr.txt;
SHA256SUMS.
```

`campaign_process_result.json` and `campaign_stderr.txt` were added only as
post-stop capture records and are explicitly not harness-generated campaign
evidence.

## 5. Formal claims

```text
EQ-1..EQ-8 adjudication         = NOT ESTABLISHED;
REJ-1..REJ-14 adjudication      = NOT ESTABLISHED;
CarrierSQLite equivalence       = NOT ESTABLISHED;
broader SimiGo/ES claim         = NOT ESTABLISHED.
```

## 6. Budget disposition

```text
fourth campaign budget          = CONSUMED;
fourth IS-mutation budget       = CONSUMED;
fourth observer budget          = CONSUMED BY INVALID ATTEMPT;
repair                          = NOT AUTHORIZED;
rerun                           = NOT AUTHORIZED;
old evidence reuse              = FORBIDDEN;
automatic renewal               = FORBIDDEN.
```

## 7. Key raw-artifact bindings

```text
O0 database SHA256 =
  6baa7afa8b5c623c75b3111af267e270d76d663547e730af5e7ca62b7602d14d
O5 database SHA256 =
  ba323adc7f52f947d401b21c6ac65fcaf1bea81d057436477e32b54f3c3a1dec
observer_verdict.json SHA256 =
  afd91a737d479e6709ea48f9b20f0fc9910e05551f7300c390d5b6cc6df148a7
observer_persistence_binding.json SHA256 =
  fd6d0ac1f07e2342c52f94ede7d3f3d073f1ae51cda78e43560a8225da971fb5
eq_rej_matrix.json SHA256 =
  5c4f11b45f4879b200b95eaaa79a4078b29f1f18d04767f655b592905899b27e
campaign_outcome.json SHA256 =
  c887c29ab17f5252474849c7975ff31411075445498b991d6a57a9d87656062f
runtime_provenance.json SHA256 =
  b54c599bbddfe8a3d926a246b1805ada311e8ee251540747581501a567d7c61d
```

## 8. Next lawful object

The next lawful object is a Human evidence audit of this INVALID E4 campaign.
If another correction is desired, it requires a new independently budgeted
Human-directed Request. This record does not authorize repair, rerun, evidence
reuse, equivalence establishment, or budget renewal.
