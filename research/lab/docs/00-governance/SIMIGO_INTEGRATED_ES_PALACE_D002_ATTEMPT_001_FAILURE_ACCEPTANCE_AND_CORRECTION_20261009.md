# D-002 Attempt-001 Failure Acceptance and Correction Authorization

> **Status:** ACCEPT / CORRECTION + ONE NEW CAMPAIGN AUTHORIZED
> **Date:** 2026-10-09
> **Authorization ID:** `D002-ATTEMPT-001-ACCEPT-CORRECTION-AUTH-001`
> **Canonical base:** `bf6eaabd1c4e6a304f794c5a15afbe226fc00d0c`

## 1. Human ruling

```text
ACCEPT D-002 ATTEMPT-001 FAILURE CLASSIFICATION

CLASSIFICATION ACCEPTED:
  D002_REPLAY_ADAPTER_CLOSURE_DIGEST_BINDING_DEFECT
  D002_OBSERVER_BOUNDARY_DIGEST_COMPARATOR_DEFECT

AUTHORIZE:
  replay adapter correction ONLY
  observer comparator correction ONLY

THEN AUTHORIZE:
  one new D-002 DECISION REPLAY
  one new D-002 BOUNDED EXPERIMENT
  one new independent D-002 OBSERVER CAMPAIGN

BUDGET:
  replay = 1 / 1
  experiment = 1 / 1
  observer = 1 / 1
  repair-run after entry = NOT AUTHORIZED
  rerun = NOT AUTHORIZED
```

## 2. Correction boundaries

The replay adapter correction must compute the translated D-001 closure digest
only after all required closure fields are resolved. The placeholder must not
enter the digest.

The observer correction must use the pre-registered canonical structured
boundary representation. Observer logic must remain independent of the subject
runner and must not reuse the runner's error helper.

Must remain unchanged:

```text
D-001 Decision Core implementation;
D-001 fixtures and evidence;
D-002 snapshot;
D-002 source;
seven-case expected vectors;
EXPECTED.json files;
canonical IS;
PALACE source.
```

## 3. Required entry gates

Before budget consumption:

```text
correction_scope_clean      = PASS;
D001_CORE_DIGESTS_UNCHANGED = PASS;
FIXTURE_EXPECTED_UNCHANGED  = PASS;
SNAPSHOT_SOURCE_BINDINGS    = PASS.
```

## 4. New campaign

New manifest instance:

```text
D1326CC7-6A02-43B6-A169-717EBB777864
```

New evidence parent:

```text
docs/02-evidence/integrated-es-palace-d002-consumption-attempt-002/
```

Budget:

```text
decision replay = 1 / 1;
bounded experiment = 1 / 1;
independent observer campaign = 1 / 1;
repair-run after entry = 0;
rerun = 0.
```

## 5. Continuing prohibitions

```text
canonical IS mutation      = NOT AUTHORIZED;
PALACE source mutation     = NOT AUTHORIZED;
E9                         = NOT AUTHORIZED;
EXP-004                    = NOT AUTHORIZED;
PIR reopening              = NOT AUTHORIZED;
D-001 rerun                = NOT AUTHORIZED;
semantic search            = FORBIDDEN;
embedding/vector traversal = FORBIDDEN;
cloud/model participation  = FORBIDDEN;
PALACE equivalence claim   = FORBIDDEN;
integrated SimiGo proof    = FORBIDDEN;
general ES theorem         = FORBIDDEN;
production validity        = FORBIDDEN;
LLM autonomy               = FORBIDDEN.
```

## 6. Record integrity

This authorization is registered by the canonical commit introducing it. Later
modification creates a new content address and does not silently revise the
Human ruling.
