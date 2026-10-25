# D-002 Postmortem / Replay-Adapter Audit Package v1.0

> **Status:** DELIVERED FOR HUMAN REVIEW — READ-ONLY AUDIT PACKAGE ONLY
> **Date:** 2026-10-09
> **Package ID:** `INTEGRATED-ES-PALACE-D002-POSTMORTEM-REPLAY-ADAPTER-AUDIT-V1.0`
> **Canonical base:** `fa1d284c21b9a56200eac886353b44e4f2f2fc8e`
> **Audit execution:** NOT AUTHORIZED
> **D-002 rerun:** FORBIDDEN
> **repair-run:** FORBIDDEN
> **evidence overwrite:** FORBIDDEN
> **canonical/PALACE mutation:** FORBIDDEN

## 1. Audit question

Why did the sealed D-002 manifest, complete package/evidence bindings, seven
real-source fixtures, and unchanged D-001 Decision Core still produce seven
unresolved D-001 reconstruction inputs?

The audit must determine where each required field or binding was:

```text
lost;
translated incorrectly;
bound to the wrong representation;
rejected by validation;
or intentionally encoded as unresolved.
```

## 2. Non-goals

This audit must not:

```text
rerun D-002;
invoke D-001 Decision Core decide();
execute an observer campaign;
consume experiment budget;
repair the adapter;
modify evidence;
modify fixtures;
modify PALACE source/snapshot;
modify D-001 Decision Core;
prove PALACE equivalence;
prove integrated SimiGo;
issue production or LLM-autonomy claims.
```

If ACCEPT, only a read-only static/evidence audit is authorized.

## 3. Frozen audit inputs

### 3.1 Source and snapshot

```text
PALACE source =
  palace-v0/palace/chroma.sqlite3;
  SHA256 = 3f790600bfa0ebb0eb7bd4e9f28ac1b6353bd6802d5eeb8f964e7edb8861bf0a;

D-002 snapshot =
  integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite;
  SHA256 = 8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444.
```

### 3.2 D-001 Decision Core baseline

```text
schemas.py        = a226522c60bb4352494d01992f09c34f546e56839c19de64440ec40449296216;
inventory.py      = 39508edee8826e9728d48ccb4f8a7c430890c7b5349d1424aaf10a756c071a27;
reconstruction.py = 78af949080c48a8ae01e015cded42464c4e970f94470e2c305e825b7b2c95b41;
continuation.py   = c4af004dbb8993cbaee40b145a95ae41c185e63d34316c574f85c2a3cb98038b;
carrier.py        = b377e8b5a933d5f9e4b3859f1dd0716be6d42df4634429c2378251c45f286e2e.
```

### 3.3 D-002 implementation under audit

```text
primitive_inventory.py = 9c83e4560c73b2da3020f3b74a79337232c22be3b74548475f7d33bb3f02a7e9;
typed_mapping.py       = 24a0d26983613d3ee336c62f82a52bcdcaac0e2d2f5a04fda0ec4b273c11c8de;
decision_replay.py     = a10fca25f94fc66ce52483a8967960df16a004904671ea2d114f734352c60c3b;
observer.py            = ef5febe3719a36cc49d68554521cb1d98fd4bf577c5bef1bac198a5683d1362d;
selfcheck.py           = db1529273ea67b6410bc400a1dfb62db92409e71a2cdaf4a0149ba75c72dd25d;
campaign.py            = 5f8555040c5e3cdbed697dc3ee7a499e0e6d0b1e925316e10cf7324fe584b331.
```

### 3.4 Final campaign evidence

```text
RUN_MANIFEST_INSTANCE.json SHA256 =
  49d389f2cfa5731d0fb285d92159b829c8ec9429a89bd06a81c98ccee8f0560e;
DECISION_REPLAY_RECORD.json SHA256 =
  a14bdba92d89ff0306edb1689ba450950439a2a83c1c54ba825fa47f070f8b4f;
EXPERIMENT_RECORD.json SHA256 =
  6291251389602958464cfe8d63bf1b4125712568743eb6755e082b67447c78bb;
CARRIER_LIFECYCLE_RECORD.json SHA256 =
  16072cba96f42227f71894931e02482896c9c342543e181ac13c0568b34b5ed4;
OBSERVER_RECORD.json SHA256 =
  b29db1c368a9d62908f27a6f9ddafd583190dd9ed8f7fdae0eedc43f9cbba9a9;
RECONCILIATION_RECORD.json SHA256 =
  e9441b7a935afb072d99e7c15a10155048500c493a1785f38752c0910df608dc;
CLAIM_RECORD.json SHA256 =
  a40954808d6a701027037d9532d027385b0728c9b0aead8aa57ea71470dc82bd;
EVIDENCE_SHA256SUMS SHA256 =
  65b8ad79529ec04634765ff0fafe80eff477b908794046853572ac6810d3980b.
```

## 4. Required trace matrix

For every case and every primitive family R-I1..R-I10, the audit must record:

```text
source field or structural origin;
snapshot-derived fixture representation;
fixture digest;
typed mapping interpretation;
replay adapter translation;
D-001 schema target field;
whether the value survived;
where loss or rejection occurred;
loss class;
whether the loss explains unresolved materialization;
evidence reference.
```

The required loss classes are:

```text
REPRESENTATION_LOSS;
BINDING_LOSS;
TRANSLATION_LOSS;
VALIDATION_REJECTION;
INTENTIONAL_UNRESOLVED_ENCODING;
EVIDENCE_CAPTURE_DEFECT;
NOT_ESTABLISHED.
```

## 5. Required audit layers

```text
A0 evidence integrity and baseline re-verification;
A1 real-source selection and ordered snapshot derivation;
A2 fixture representation and R-I1..R-I10 binding;
A3 typed mapping record and D-001 schema intent;
A4 replay adapter closure translation;
A5 replay adapter provenance translation;
A6 replay adapter NEXT_ACTION / boundary translation;
A7 replay adapter invocation translation;
A8 replay adapter carrier snapshot / REUSE translation;
A9 D-001 reconstruction validation sequence;
A10 D-001 unresolved fallback encoding;
A11 observer/reconciliation mismatch analysis;
A12 final first-fault and correction proposal.
```

The audit may read evidence, fixtures, snapshot metadata, source code, and D-001
code. It must not execute campaign or Decision Core paths.

## 6. Required outputs if accepted

```text
POSTMORTEM_AUDIT_RECORD.md;
FIELD_TRACE_MATRIX.json;
LOSS_CLASSIFICATION.json;
ROOT_CAUSE_HYPOTHESIS.json;
CORRECTION_PROPOSAL.md;
AUDIT_EVIDENCE_SHA256SUMS.
```

`CORRECTION_PROPOSAL.md` must remain non-executable. It may propose a redesigned
adapter or new experiment object, but cannot authorize either.

## 7. Evidence and write-once rules

The proposed evidence parent is:

```text
docs/02-evidence/integrated-es-palace-d002-postmortem-audit-v1/
```

All outputs are write-once. `AUDIT_EVIDENCE_SHA256SUMS` is final and must cover
the other five outputs exactly once.

## 8. Decision requested

Human review must return exactly one ruling:

```text
ACCEPT   authorize only the read-only postmortem audit outputs above;
REVISE   require a new audit package revision;
REJECT   close the D-002 postmortem pathway.
```

ACCEPT does not authorize repair, rerun, a new campaign, implementation changes,
canonical IS mutation, PALACE mutation, or equivalence claims.
