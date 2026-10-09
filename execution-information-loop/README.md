# Execution–Information Loop — isolated vertical slice

This is a stdlib-only reference implementation of the newly agreed
Execution-State-driven Information Space closed loop.

## What it proves

```text
1 Information and settlements persist in SQLite.
2 ES defines a concrete continuation demand and required information closure.
3 Restored execution reads persisted state through SQLite only.
4 Valid settlements are reused without recomputation.
5 Source/dependency invalidation selectively recomputes affected items.
6 Missing information fails closed without guessing.
7 Payload digest mismatch fails closed without settlement.
8 Every transition is appended to a SHA-256 hash-chained audit log.
```

## Isolated scope

This slice is synthetic and does not touch:

```text
PALACE;
canonical Information Space;
D-001 Decision Core or evidence;
D-002 campaign or evidence;
sealed Instrumentation packages.
```

## Run

```bash
python3 execution-information-loop/selftest.py
```
