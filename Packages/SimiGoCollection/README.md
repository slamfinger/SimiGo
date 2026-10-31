# SimiGoCollection

MLX-free package for the Qoder transcript collection bridge. It is deliberately
kept out of `SimiGoRuntime` so `swift test` on the collector never compiles the
MLX research dependency chain.

## Responsibility and entry point

The collector reads Qoder transcript files beneath `~/.qoder-cn/projects`
(overridable with `QODER_PROJECTS_DIR`) without writing to that tree. Durable
state lives beneath `$SIMIGO_HOME/collectors/qoder`, or
`~/.simigo/collectors/qoder` when `SIMIGO_HOME` is unset.

`QoderCollectionRunner` is the only product entry. It owns the transcript
tailer, the durable candidate inbox, and the state-directory lease. Both
`QoderCandidateInbox` and the lease type are package-internal, so other product
modules cannot commit candidates or take the lease behind the runner's back.
The GUI app holds at most one runner, started at launch by
`QoderCollectionLifecycle` and stopped on normal termination.

## Runner, lease, and inbox

- **Runner** polls on one serial queue, commits reconstructed turn candidates
  and the transcript cursor in a single SQLite transaction, then optionally
  delivers. Polls never overlap.
- **Lease** is a process-level `flock` on the state directory. A second runner
  pointed at the same directory cannot acquire it while the first is alive.
  The operating system releases the lock when the owning process exits, so
  crash recovery does not depend on a termination callback. The next process
  rebuilds open-turn state from the persisted replay anchor and resumes from
  the durable cursor and pending inbox.
- **Inbox** is the durable candidate store (SQLite with WAL,
  `synchronous=FULL`, `BEGIN IMMEDIATE`). Candidate payloads and cursors commit
  atomically; a crash before commit replays the same transcript lines and the
  unique candidate keys absorb the retry.

State that exists but cannot be read or decoded is never re-baselined in place,
because that would silently skip turns that were never durably recorded.
The runner fails closed: the error becomes `unavailableReason`, collection
stops, and recovery is possible only through the explicit
`quarantineState()` entry.

## Collection-only and sink-enabled modes

`QoderCollectionRunner(configuration:onError:)` runs in **collection-only**
mode. Candidates stay pending in the inbox; there is no empty sink and no fake
delivery. The GUI app currently uses this mode.

`QoderCollectionRunner(configuration:sink:onError:)` runs in **sink-enabled**
mode. The sink is called only after the candidate and its cursor have committed
durably. Delivery has **at-least-once** semantics:

- After a normal stop and restart, candidates already marked delivered are not
  delivered again.
- If the sink accepted a candidate but the `markDelivered` transaction did not
  commit before a crash, the candidate may be delivered again under the same
  durable candidate key. Sinks must treat that key as their idempotency key.
  This is not exactly-once delivery.

These are two distinct behaviours with separate tests, not one combined claim.

## Payload integrity

Before a pending candidate can reach the sink, its SHA-256 digest is recomputed
over the exact payload BLOB bytes read from SQLite and compared with the stored
digest. A mismatch is corrupt durable state: the runner refuses delivery,
records no delivery mark, becomes sticky-unavailable, and does not continue
collection.

## Scanner diagnostics

A transcript root or subagent file that genuinely does not exist (ENOENT /
`NSFileNoSuchFileError` / `NSFileReadNoSuchFileError`) is reported as absent.
Any other listing or read error is reported as partial with the error retained;
it is not mistaken for an absent or complete scan.

## Status fields

`statusSnapshot` returns `QoderCollectionStatus`:

- `isRunning` — the poll timer is active and no failure is recorded. It is
  false while the runner is sticky-unavailable.
- `unavailableReason` — non-nil while durable state cannot be used. A state
  directory held by another runner needs that owner to stop or exit first;
  damaged state needs explicit quarantine.
- `pendingCount` — pending candidates in the inbox, or nil when the state
  directory is not owned or cannot be read.
- `lastDeliveryAt` — when the configured sink last accepted a delivery in this
  process. An operational observation only, not a settlement record.
- `lastFailureAt` — when a poll, delivery, or status read last reported an
  error.

The menu-bar display of these fields is read-only. The fields carry no
Information Space eligibility semantics.

## Tests

Run the package tests without building MLX:

```bash
swift test --package-path Packages/SimiGoCollection --filter SimiGoCollectionTests
```

App-level XCTest must go through the repository isolation entry, never an
unisolated `TEST_HOST` run:

```bash
tools/run_isolated_tests.sh --tag <name>
```

Package tests cover the collector boundary and do not launch the GUI app or
write to Information Space. They are not a substitute for the separate
real-Qoder/App quit-and-relaunch lifecycle acceptance.

## Boundary: collection is not settlement

Collected candidates are not Information Space settlements. `eligible` on a
`QoderTurnDisposition` is only the collector's classification; it is never
promoted to IS settlement eligibility. This slice writes no IS rows, performs
no `RULED_ALLOW`/WA authorization, and activates no frozen C-class policy.
Connecting collected candidates to IS settlement remains an unfinished,
separately authorized integration.
