# D-001 Attempt-001 Failure Acceptance and Comparator Correction Authorization

> **Status:** AUTHORIZED — COMPARATOR CORRECTION + ONE NEW BOUNDED CAMPAIGN
> **Date:** 2026-10-08
> **Authorization ID:** `D001-ATTEMPT-001-ACCEPT-COMPARATOR-CORRECTION-001`
> **Canonical base:** `efc27887ed989e6d9861503a53acbe23214a08be`

## 1. Human ruling

```text
ACCEPT D001 ATTEMPT-001 FAILURE CLASSIFICATION
  = CAMPAIGN COMPARATOR DEFECT

AUTHORIZE D001 COMPARATOR CORRECTION ONLY

CORRECTION SCOPE:
  campaign comparison / reconciliation layer only

MUST PRESERVE:
  S0-S2 preparation evidence
  P1-P7
  frozen seven-case expected vectors
  EXPECTED.json
  decide() / Decision Core semantics
  fixture contents
  observer semantics
  Run Manifest Contract v1.0
  canonical IS = untouched

AUTHORIZE ONE NEW D001 BOUNDED EXPERIMENT
AUTHORIZE ONE NEW D001 OBSERVER CAMPAIGN

REQUIRED STOP:
  any fixture/pre-registration drift
  any Decision Core semantic change
  any observer disagreement
  any forbidden channel
  any canonical IS mutation

MUTATION = NOT AUTHORIZED
E9 = NOT AUTHORIZED
EXP-004 = NOT AUTHORIZED
PIR = CLOSED
```

## 2. Frozen adjudication basis

The frozen three-component decision vector is:

```text
top-level decision == expected.decision;
continuation_class == expected.continuation_class;
precedence_reason == expected.precedence_reason.
```

The four negative runners may continue to emit the more specific output labels:

```text
MISSING_INFORMATION_BLOCK;
STALE_INFORMATION_BLOCK;
AMBIGUOUS_INFORMATION_BLOCK;
ILLEGAL_CONTINUATION_BLOCK.
```

Those labels are output representations. They must not replace the frozen
coarse `BLOCK` decision basis.

## 3. Attempt-001 evidence preservation

Attempt-001 remains immutable:

```text
docs/02-evidence/integrated-es-palace-d001-bounded-experiment-v1/
```

Its key bindings are:

```text
RUN_MANIFEST_INSTANCE.json SHA256 =
  85b69e9454bdfd7ad7eb41145915ae5316e85058cd2150bd58263c58e495697a;
EXPERIMENT_RECORD.json SHA256 =
  093ff2c41dc332875d4e7d58dc547a1edca1b0f0e9799847e66d5ce15ac14c13;
OBSERVER_RECORD.json SHA256 =
  2e7c1c86f666fa679de585d61e6deb40fad51ea18184fa869444551344ca81cf;
RECONCILIATION_RECORD.json SHA256 =
  fb65fdeed19556e229784e81de682887e01a8a7d80a07f5c89af055b2f7059fb;
CLAIM_RECORD.json SHA256 =
  abdb3ea4109971718064fb0e72a76b18e40c637ad18345e1bc3c503d478e26d7;
EVIDENCE_SHA256SUMS SHA256 =
  ebdf3397fcced462b97a1ae5ad2ce206eb45fbbe54dbcf3f1860ada08a1983b9.
```

No Attempt-001 evidence object may be rewritten.

## 4. New campaign budget

The correction authorizes exactly:

```text
one new bounded experiment;
one new independent observer campaign;
one new manifest instance;
one new evidence parent;
zero repairs after entry;
zero reruns after entry.
```

The new evidence parent is:

```text
docs/02-evidence/integrated-es-palace-d001-bounded-experiment-attempt-002/
```

## 5. Continuing prohibitions

```text
canonical IS mutation       = NOT AUTHORIZED;
E9                          = NOT AUTHORIZED;
EXP-004                     = NOT AUTHORIZED;
PIR                         = CLOSED / VALIDATION DEFERRED;
fixture/pre-registration drift = FORBIDDEN;
Decision Core semantic change  = FORBIDDEN;
observer semantic change       = FORBIDDEN;
PALACE equivalence claim       = FORBIDDEN;
integrated SimiGo proof        = FORBIDDEN;
general ES theorem             = FORBIDDEN;
production SimiGo validity     = FORBIDDEN;
LLM autonomy                   = FORBIDDEN.
```

## 6. Record integrity

This authorization is registered by the canonical commit introducing it. Later
modification creates a new content address and does not silently revise the
Human ruling.
