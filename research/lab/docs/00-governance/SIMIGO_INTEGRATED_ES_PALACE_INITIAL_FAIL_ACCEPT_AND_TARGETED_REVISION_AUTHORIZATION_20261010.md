# Initial non-D002 validation fail acceptance and targeted revision authorization

> **Status:** HUMAN RULING ACCEPTED / TARGETED REVISION AND ONE RUN AUTHORIZED
> **Date:** 2026-10-10

## 1. Ruling

The first non-D002 integrated validation remains valid and closed:

```text
terminal state = VALIDATION_FAIL;
executed runs = 1;
positive / reuse / lawful-block cases = PASS;
negative blocking actions = PASS;
negative precedence reason labels = FAIL;
repair / rerun / evidence rewrite = FORBIDDEN.
```

The Human ruling accepts this result and authorizes one narrowly scoped
runner correction plus one new fresh-entry validation run. It does not rewrite
the first failure as success and does not reopen Pilot v5 or Fixture
Preparation.

## 2. Authorized correction

Only the runner's derivation and output of the four registered negative
precedence reason labels may change:

```text
N-MISSING   -> MANDATORY_OBJECT_UNRESOLVABLE;
N-STALE     -> MANDATORY_EVIDENCE_SUPERSEDED;
N-AMBIGUOUS -> CONFLICTING_VALID_POINTERS;
N-ILLEGAL   -> REGISTERED_BOUNDARY_VIOLATION_PROVEN.
```

The reasons must continue to be derived from actual state:

```text
missing mandatory inventory object;
superseded mandatory evidence;
conflicting valid pointers;
proven unauthorized boundary.
```

The runner must not read expected results as decision input and must not use
case identity as a decision shortcut. Expected labels remain output-only
acceptance criteria.

## 3. New run authorization

```text
new Run Manifest = authorized;
new runner SHA256 binding = required;
original fixture bindings = unchanged;
seven cases = unchanged;
independent evidence directory = required;
authorized executions = 1;
terminal states = VALIDATION_PASS or VALIDATION_FAIL;
if FAIL again = STOP / no third run / no automatic repair.
```

## 4. Immutable first-run binding

```text
first Run Manifest SHA256 =
  b8a668ef482897b2cbe9b40e4aa6eb48868c613b76ef194338f89d7d22a59ef5;
first Run Manifest canonical content SHA256 =
  99ae73208ff6f6f4be9677ee1ee33e8c45b3ee2de76415a8b03612cd77b679f4;
first runner SHA256 =
  f27b1f055b6864445fb00d63fb9078744319964234a090648a28a4d1b5c1d8fb;
first evidence checksum list SHA256 =
  269083feee9e0b6fa9767f6c0509e7f5ec8142913913be147b039cba21747f82;
first validation record SHA256 =
  a6d3a4101f80eb072dbb98d691ada957460ff91bbc9a33ca6f031f9714fce55e;
first result governance record SHA256 =
  4bb8abe56f1c4613e4740e30b306ad45cea4c373248e0775ccc40da286eb15b3.
```

## 5. Continuing boundaries

```text
frozen design and P1–P7 = unchanged;
fixture package = unchanged;
canonical PALACE / Information Space mutation = FORBIDDEN;
D-002 rerun / repair = FORBIDDEN;
production deployment = NOT AUTHORIZED;
Integrated SimiGo full production proof = NOT ESTABLISHED.
```
