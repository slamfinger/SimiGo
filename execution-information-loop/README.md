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
7 Real PALACE collection/segment/embedding relations are consumed structurally.
8 Missing information fails closed without guessing.
9 Malformed validity input fails closed without guessing.
10 Payload digest mismatch fails closed without settlement.
11 Every transition is appended to a SHA-256 hash-chained audit log.
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

## Final acceptance check

```bash
python3 execution-information-loop/verify_acceptance.py
```

This reruns all five selftests and verifies the primary evidence digest.
With `--skip-tests`, it performs static checks only and returns
`NOT_ACCEPTED_VERIFICATION_INCOMPLETE`; skipped tests cannot produce acceptance
`PASS`.

## Bounded production runtime integration

```bash
python3 execution-information-loop/verify_production_runtime_integration.py
```

The integration test drives real PALACE structural metadata through the real
Swift `ExecutionContinuityCoordinator`, reuses persisted settlements after
runtime restart, propagates invalidation, selectively recomputes an isolated
source revision, and blocks invalid information. Production deployment remains
unauthorized.

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

## Real PALACE structural graph

`real_palace_loop.py` reads only structural columns and metadata tables from the
sealed D002 snapshot. It materializes:

```text
REAL-COLLECTION
REAL-SEGMENT
REAL-1..REAL-7
```

Each metadata record depends on its physical `embeddings.segment_id`; chunk
records additionally use an already-seen declared `parent_drawer_id`. It does
not synthesize a linear chain from row order. Invalidation of the metadata
segment propagates to all seven metadata records while the collection remains
reused.

`real_palace_source_change_selftest.py` verifies source-change behavior on an
isolated byte-identical copy:

```text
first run computes nine items;
restored run reuses nine items;
REAL-1 metadata changes on the copy;
only REAL-1 recomputes;
collection/segment and REAL-2..REAL-7 remain reused;
the sealed canonical snapshot is untouched.
```

## Integrated real-source acceptance

`real_palace_integrated_selftest.py` runs all core behaviors against one SQLite
carrier and one byte-identical real-source copy:

```text
compute the real structural graph;
persist and restore Execution State;
derive the next demand from restored Execution State;
reject a same-ID demand contract rewrite after checkpoint;
reuse all valid settlements;
propagate explicit REAL-3 invalidation to REAL-4;
apply a REAL-1 source change without recomputing unaffected records;
expire REAL-3 and propagate to REAL-4;
block malformed observation time in the same loop;
missing information blocks in the same loop;
cross-segment source ambiguity fails closed;
roll back a mid-demand failure atomically;
roll back a SIGKILLed worker without partial settlement;
verify every carrier object.
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

For the bounded production-runtime bridge, an expired source validity window is
additionally a preflight rejection: `BLOCKED_STALE_VALIDITY` occurs before any
calculator call or new settlement. Refreshing the source's validity window is
required before continuation.

A missing or malformed validity policy is also a production preflight rejection;
undefined validity is `BLOCKED_VALIDITY_POLICY_MISSING`, and malformed validity is
`BLOCKED_INVALID_VALIDITY`.

Persisted production handles are recovery-validated: unknown and discarded
lifecycles are rejected rather than silently restored as `.active`.

## Integrated SimiGo isolated proof

```bash
python3 execution-information-loop/verify_integrated_simigo_proof.py
```

`IntegratedSimigoProofE2ETests` validates one isolated real-source flow:
Execution State recovery, persistent carrier reuse, explicit invalidation,
source-change recompute, stale/missing/malformed failure safety, corrupted
lifecycle rejection, and full carrier object verification.

## Production readiness / deployment preparation

```bash
python3 execution-information-loop/verify_integrated_simigo_proof.py
```

This command runs isolated proof, production integration, and production
readiness Swift suites. The readiness suite stages an explicit runtime bundle,
uses the system Python, rejects a missing bridge/snapshot/policy file, loads a
deployment-owned validity policy, records a blocked state, performs append-only
rollback to the last good ADVANCED state, and verifies rollback compatibility.

## Explicit invalidation

`CarrierInformationLoop.invalidate_settlement()` appends INVALID settlement
records for a target and all transitive dependents. The next demand run reuses
unaffected settlements and recomputes the invalidated dependency closure.
