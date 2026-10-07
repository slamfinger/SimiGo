# SRS-REAL-CLOSURE-01 — Database-Carrier E3 Equivalence Campaign Invalid Completion Record 004

> **Status:** E3 EXECUTED / INVALID / STOP FOR HUMAN EVIDENCE AUDIT
> **Date:** 2026-10-08
> **Campaign ID:** `exec-dbcarrier-003-c6c8b6f`

## 1. Governing chain

```text
request_v1_5_commit = 079822841b3c1a482251fd24c9311e0242ae345;
r2_conditional_e3_authorization_commit =
  9119530459d27b56c586c591dcf27a41f2a9b710;
evidence_path_release_review_commit =
  712aee56c523845440276923ac7053dc3ea91b3c;
e3_execution_authorization_commit =
  1163eb10bbcdd94227a32dc2aef4aca616993199;

exact_execution_repository_commit =
  c6c8b6fb0b532aa94496ac860f4e5faaa8cd05e7;
exact_execution_tree =
  7b3ced36e169e7d529ce9da5c335082f145cf93e;
accepted_implementation_commit =
  7392fcb79fb7e8465b73f9e1837c4634e56c0409;
implementation_tree_unchanged = true;

authoritative_path_map_blob =
  git:blob:c89413a25879e7436f7db94e14c08ed9b28dc6fc;
authoritative_path_map_sha256 =
  b1adc52cdfb152f17d941d6214d24f393bdfc2fcdd9a7858bd37fe9c0b27ebb7.
```

## 2. Campaign result

The sole authorized E3 campaign started from a clean detached worktree at
`c6c8b6f…`. Authoritative path preflight passed all 29 destinations. The
accepted fresh database was copied and verified as O0 and working DB. The
frozen semantic sequence then reached O5:

```text
O0 objects/index/deps = 0/0/0;
CAMPAIGN objects/index/deps = 4/2/2;
O5 objects/index/deps = 4/2/2;
SQLite integrity = ok at O0, working DB and O5;
adapter invocations = 2;
ES2 observed primaryDecision = REUSE;
ESN observed primaryDecision = BLOCK;
observer executed before evidence persistence = false.
```

The campaign then stopped fail-closed while persisting the observer verdict:

```text
returncode = 1;
stop_code = CAMPAIGN_OBSERVER_VERDICT_KEY_BINDING_DEFECT;
stop_point = POST_O5_OBSERVER_VERDICT_PERSISTENCE;
root_cause_class = HARNESS_POST_SEQUENCE_EVIDENCE_KEY_BINDING_DEFECT;
faulting_expression = observer["C3"];
actual_observer_key =
  C3_persisted_vs_resolved_byte_equality;
observer_verdict.json = NOT WRITTEN.
```

This is a campaign harness post-sequence evidence-binding defect. It is not a
carrier semantic failure and does not by itself reject or establish
CarrierSQLite equivalence.

## 3. Evidence disposition

The preserved campaign output is canonical at:

```text
docs/02-evidence/database-carrier-equivalence-campaign-v1.5-20261008
```

Key hashes:

```text
O0_DATABASE.sqlite =
  6baa7afa8b5c623c75b3111af267e270d76d663547e730af5e7ca62b7602d14d;
CAMPAIGN_DATABASE.sqlite =
  ba323adc7f52f947d401b21c6ac65fcaf1bea81d057436477e32b54f3c3a1dec;
O5_DATABASE.sqlite =
  ba323adc7f52f947d401b21c6ac65fcaf1bea81d057436477e32b54f3c3a1dec;
ES2_OUTPUT.json =
  370396506039ff1b92845e5f902375f784ee7af7e4729cfae3f80be1d8409ee7;
ESN_OUTPUT.json =
  c35ea6826e14cd79c5fa61c09dba0660d3af73ac0fc686baa2467a923b502bf4;
EVIDENCE_PATH_BINDING_EXECUTION.json =
  640ac32c8670055d34f9b643a261ebd3cd3bfb4ea3e50225b1a41b65b225a022;
CAMPAIGN_PROCESS_RESULT.json =
  821c99eca44fe70c3bb9dc699366c072807a44420715c842fcc52af375cecaf4;
CAMPAIGN_STDERR.txt =
  120682304a2c6f1a7aa0d619d9f30b5b74a2af84600cbf2d38c3c0478cbf2602;
POST_STOP_SHA256SUMS =
  3923029588ddfb06236e0a5d6210750f6df753e877e052b3713dcbfc06ffadb1.
```

At stop, these authoritative destinations remained absent:

```text
PREFLIGHT_VERIFICATION;
RUNTIME_PROVENANCE;
OBSERVER_VERDICT;
EQ_REJ_MATRIX;
CAMPAIGN_OUTCOME;
CAMPAIGN_DB_VALIDATION;
CAMPAIGN_PROCESS_RESULT;
CAMPAIGN_STDERR;
SHA256SUMS.
```

`CAMPAIGN_PROCESS_RESULT` and `CAMPAIGN_STDERR` were added only after stop as
post-stop capture records; they are not claimed as harness-generated campaign
artifacts.

## 4. Formal research state

```text
E3 outcome                      INVALID;
semantic sequence               EXECUTED TO O5;
complete campaign evidence      NOT PRODUCED;
EQ-1..EQ-8 adjudication         NOT ESTABLISHED;
REJ-1..REJ-14 adjudication      NOT ESTABLISHED;
observed ES2 REUSE              RAW OBSERVATION ONLY;
observed ESN BLOCK              RAW OBSERVATION ONLY;
CarrierSQLite equivalence       NOT ESTABLISHED;
core broader claim              NOT ESTABLISHED.
```

The raw adapter observations may be audited but cannot be promoted to campaign
semantics because the required observer, EQ/REJ matrix, outcome, DB validation
and complete provenance artifacts were not produced.

## 5. Budget and authorization

```text
third campaign budget           CONSUMED;
third IS mutation budget        CONSUMED;
third observer budget           CONSUMED BY FAIL-CLOSED ATTEMPT;
harness repair                  NOT AUTHORIZED;
rerun                           NOT AUTHORIZED;
old campaign reuse              FORBIDDEN;
automatic renewal               FORBIDDEN;
automatic equivalence           FORBIDDEN.
```

## 6. Next lawful object

The next lawful object is Human evidence audit of this INVALID campaign,
followed by an explicit Human decision whether to authorize a further
independently budgeted corrected campaign. No correction, rerun, equivalence
claim, renewal, or broader claim is authorized by this record.
