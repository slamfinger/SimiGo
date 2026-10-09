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
6 Expired settlements recompute instead of being treated as permanent truth.
7 Missing information fails closed without guessing.
8 Malformed validity input fails closed without guessing.
9 Payload digest mismatch fails closed without settlement.
10 Every transition is appended to a SHA-256 hash-chained audit log.
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

## D002 carrier integration

`carrier_loop.py` reuses the existing D002 `DatabaseBackedIS` append-only carrier.
Current item versions are resolved from the latest index entry; settlements are
current dependency objects. Reused settlements no longer create duplicate
settlement entries. Source updates append a new version and force dependent
settlements to recompute while unaffected settlements remain reused.

`carrier_selftest.py` verifies:

```text
first run computes A/B/C;
restored second run reuses A/B/C;
B source update recomputes B/C while A remains reused;
expired B recomputes dependent C while A remains reused;
missing D fails closed;
malformed observation time fails closed;
carrier schema and all objects verify.
```

## Persisted Execution State recovery

The carrier-backed loop now records explicit Execution State transitions. After a
successful demand run, it can close/reopen the database and restore the latest
state for a continuation point. Source updates then invalidate dependent
settlements while unaffected settlements remain reused.

The full carrier selftest sequence is:

```text
first run computes A/B/C;
restored second run reuses A/B/C;
Execution State is persisted and restored after restart;
B source update recomputes B/C while A remains reused.
```

## Validity gates

`put_source()` and `update_source()` persist an optional `valid_until_utc` on
the information item. Every settlement records that condition in its result and
basis. Each demand supplies `evaluated_at_utc`. Reuse requires source/version/
dependency identity and a still-valid settlement window. Expired items recompute;
malformed validity input blocks without a calculator call.

## Explicit invalidation

`CarrierInformationLoop.invalidate_settlement()` appends INVALID settlement
records for a target and all transitive dependents. The next demand run reuses
unaffected settlements and recomputes the invalidated dependency closure.
