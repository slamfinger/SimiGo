# Execution State chaos / multi-process acceptance — 2026-10-14 / f7b1283e

## Verdict

`PASS` on implementation HEAD `f7b1283e` (branch
`codex/execution-state-chaos-acceptance`), three consecutive runs, plus a full
suite run at `352 executed / 3 skipped / 0 failures`.

## What ran

Every mutation and every verification executed inside spawned
`ExecutionStateChaosChild` processes; the test process was only a driver, so
the evidence is process-restart evidence.

- Four concurrent processes reserved 100 generated identities against one
  ledger; a fresh process replayed it clean at exactly 100 unique
  reservations.
- A ready/go-barriered requested-ID race committed exactly one reservation:
  one winner, one explicit conflict, clean replay.
- A stale-view token retry recovered the committed identity instead of
  allocating a second one.
- SIGKILL sweep at five points of an 8-transition growth script: every
  restart observed the exact committed prefix (contiguous lifecycle sequence,
  handle position, one deterministic-prefix representation per position,
  physical rehydration verified in a fresh backend), then finished the
  script.
- 20 successive crash→restore→continue generations on one store: 20 SIGKILLs,
  20 independent verifications, final state 81 lifecycle records / position
  80 / 81 physically verified representations.
- Negative control: the verifier rejected a corrupted snapshot (exit 4, fail
  verdict).

## Defects found and fixed by this acceptance

- `931ce3c0` — reserve() arbitration used process-local in-memory maps only;
  a concurrent requested-ID race double-committed and the ledger failed
  closed as corrupt on the next open. Fixed by re-reading and re-checking the
  ledger under the exclusive flock.
- `4d8c3091` — first-ledger creation was two steps (`createFile` + open); the
  second `createFile` replaced the first process's inode, splitting the flock
  across two files (23/30 loss rate in a shell loop). Fixed with atomic
  `open(O_RDWR | O_CREAT)`.

## Scope

PROCESS-crash evidence only (SIGKILL). It does not certify power-loss or
storage-media durability, universal concurrency correctness, production
readiness, or a governance closure for G-5 / G-7 / G-8 / G-10.

## Files

- `manifest.json` — machine-readable acceptance manifest
- `acceptance-suite.log` — three suite runs (SHA-256 in manifest)
- `full-suite.log` — full XCTest run (SHA-256 in manifest)
