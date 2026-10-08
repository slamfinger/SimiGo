# SRS-REAL-CLOSURE-01 — Database-Carrier E4 Human Evidence Audit Record 001

> **Status:** CLOSED — HUMAN-DIRECTED READ-ONLY EVIDENCE AUDIT; E4 CONFIRMED
> INVALID / NON-ADJUDICATIVE
> **Date:** 2026-10-08
> **Campaign:** exec-dbcarrier-004-8c7aca5
> **Authorization:** explicit Human `授权进行` issued at the stated E4 audit
> gate
> **Audit base:** `1dbae93882e34e7571763f190b8f4367e5f63d86`
> **Governing Request v1.6:** `b5f15cb5309d7619ba2e03eefaeac74712890462`
> **R3 correction commit:** `8c7aca5c10dcd4ec3560897cb7537990d2bc9e6e`
> **E4 evidence/invalid record:** `5ca190c68f386d29bd691c671b181e7e2027d563`

## 1. Ruling

E4 is confirmed **INVALID / NON-ADJUDICATIVE**.

The E3 observer-key defect is confirmed **corrected**. A second, independent
evidence-chain serialization defect then prevented canonical closure. The new
defect is confined to campaign harness evidence/provenance serialization:

```text
stop_code = CAMPAIGN_PREFLIGHT_VERIFICATION_JSON_SERIALIZATION_DEFECT;
root_cause_class =
  HARNESS_POST_SEQUENCE_PREFLIGHT_JSON_PATH_SERIALIZATION_DEFECT.
```

The failure occurred when serializing `preflight_verification.json` after the
complete O0–O5 sequence and after several post-sequence artifacts had already
been written. Python rejected a `PosixPath` value. The audit does not attribute
the stop to CarrierSQLite semantics, database schema, ES2/ESN semantics, the
decision boundary, fixture, runner, or EQ/REJ criteria.

## 2. Read-only verification result

The audit verified the canonical commit chain, clean worktree, path map, R3
scope, implementation immutability, evidence-only E4 recording scope, raw
sequence, databases, observer persistence, transaction log, and fail-closed
capture.

```text
HEAD = origin/main = 1dbae93882e34e7571763f190b8f4367e5f63d86;
worktree = CLEAN;
Request/R3/invalid-record ancestry = PASS;
path-map destination count/version = 30 / v2;
initial evidence-path preflight = 30/30 PASS;
implementation unchanged from accepted baseline = PASS;
R3 changed campaign instrumentation only = PASS;
E4 recording changed evidence/governance docs only = PASS;
transaction events = 8 (four BEGIN/COMMIT pairs);
SQLite integrity for O0/campaign/O5 = OK / OK / OK.
```

## 3. Accepted raw campaign facts

```text
O0 logical state = 0 objects / 0 index entries / 0 dependencies;
O5 logical state = 4 objects / 2 index entries / 2 dependencies;
O0 database SHA256 = 6baa7afa8b5c623c75b3111af267e270d76d663547e730af5e7ca62b7602d14d;
campaign database SHA256 = ba323adc7f52f947d401b21c6ac65fcaf1bea81d057436477e32b54f3c3a1dec;
O5 database SHA256 = ba323adc7f52f947d401b21c6ac65fcaf1bea81d057436477e32b54f3c3a1dec.
```

Raw adapter observations remain observations only:

```text
ES2 = REUSE / REUSE_PATH;
ES2 output SHA256 = 370396506039ff1b92845e5f902375f784ee7af7e4729cfae3f80be1d8409ee7;
ESN = BLOCK / BLOCKED_NON_RECOMPUTE_PATH;
ESN output SHA256 = c35ea6826e14cd79c5fa61c09dba0660d3af73ac0fc686baa2467a923b502bf4.
```

## 4. R3 observer correction verification

The former E3 observer-key binding defect is closed as a raw campaign fact.

```text
canonical C3 key =
  C3_persisted_vs_resolved_byte_equality;
observer verdict = PERSISTED;
serialized canonicalization = PASS;
byte-for-byte reread = PASS;
parsed-object equality = PASS;
persistence self-check = PASS;
observer verdict SHA256 = afd91a737d479e6709ea48f9b20f0fc9910e05551f7300c390d5b6cc6df148a7;
observer persistence binding SHA256 =
  fd6d0ac1f07e2342c52f94ede7d3f3d073f1ae51cda78e43560a8225da971fb5.
```

## 5. Complete-chain failure

At campaign stop, the following authoritative chain destinations were absent:

```text
preflight_verification.json;
CAMPAIGN_PROCESS_RESULT.json;
CAMPAIGN_STDERR.txt;
SHA256SUMS.
```

Current process-result and stderr files are post-stop captures only. They are
failure evidence and are not harness-generated completion artifacts. Therefore
the complete evidence chain does not close.

The mechanically present `campaign_outcome.json`, `eq_rej_matrix.json`, and
`runtime_provenance.json` remain non-authoritative. Their mechanical fields do
not override the incomplete chain.

```text
campaign outcome field = VALID / NON-AUTHORITATIVE;
EQ matrix count = 8 / NON-AUTHORITATIVE;
REJ matrix count = 14 / NON-AUTHORITATIVE;
runtime provenance = PRESENT / NON-AUTHORITATIVE.
```

## 6. Observation bindings

| Point | SHA256 |
|---|---|
| O0 | `4a032a960559d584a64465c9a8b9bd4cf7175013a46d7c4e3e5e933b1585a779` |
| O1 | `defbe8d2eaed00260ea45018ca107cd7edb7584ad1f0de2ce1ee88624ee4d8f9` |
| O2 | `22f619674e93c8aab9dba24787b976eb0f000398996045fab989e0543dfa79d3` |
| O3 | `bf1e74458e1c76885b0d2c1660c607ca7d0fe9d22c55f6a1e06eec404e3eae5c` |
| O4 | `649c85817a9fe1da47926e11c209d8a4b0051065dd51a4319042f9c8d83c5af0` |
| O5 | `649c85817a9fe1da47926e11c209d8a4b0051065dd51a4319042f9c8d83c5af0` |

Authoritative path map at audit time:

```text
database-carrier-replication/campaign/EVIDENCE_PATH_BINDING_MANIFEST.json
  SHA256 = e72cba10cc77ea18c9e51df28f40fc6fbe46f3329cbaf869fe325b8097bed52c.
```

## 7. Adjudication and claim disposition

```text
raw O0–O5 facts              = ACCEPTED;
raw ES2 REUSE                = NON-AUTHORITATIVE;
raw ESN BLOCK                = NON-AUTHORITATIVE;
EQ-1..EQ-8                   = NOT ESTABLISHED;
REJ-1..REJ-14                = NOT ESTABLISHED;
CarrierSQLite equivalence    = NOT ESTABLISHED;
broader SimiGo/ES claim      = NOT ESTABLISHED.
```

E4 is not converted to VALID. Its O5 state cannot be used to retrofit
adjudication.

## 8. Budget disposition

```text
fourth campaign budget       = CONSUMED;
fourth IS-mutation budget    = CONSUMED;
fourth observer budget       = CONSUMED BY INVALID ATTEMPT;
repair                       = NOT AUTHORIZED;
rerun                        = NOT AUTHORIZED;
old campaign/evidence reuse  = FORBIDDEN;
automatic budget renewal     = FORBIDDEN.
```

## 9. Next lawful object

This audit closes the Human evidence audit gate for INVALID E4.

If further work is desired, the next lawful object is an explicit Human
decision to authorize a **new independently budgeted Request** scoped to
harness evidence/provenance serialization correction and a potential fifth
frozen campaign. This record does not authorize drafting, repair, rerun,
evidence reuse, budget renewal, or equivalence establishment.

## 10. Record integrity

```text
record_integrity_binding = registered by the canonical commit introducing
this record; later modification creates a new content address and voids this
audit closure.
```
