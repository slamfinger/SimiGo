# SimiGo-Lab — App Chat Path Wired Through Execution State — 2026-09-26

Status: APP_CHAT_STRICT_EXECSTATE_WIRED / SELFTEST_RESTORE_REPLAY_PASS
Phase: SimiGo 2.0 Experimental

## The question and the honest answer

User: "超规模大模型也严格进行 Execution State 了吗?" Answer at the time:
**NO** — the app chat path drove segmented materialization directly
(no Coordinator/Handle/lifecycle records); Execution State was validated
only as the standalone O6 scenario. That gap is now closed: the app chat
path runs strictly through the Execution State layer.

## What was wired

`OversizedSegmentedEngine` now hosts the O6 stack:
- `OversizedSegmentedStateBackend` decoupled from O6SegmentedCore via a
  release closure — releaseRepresentation = the oversized segment eviction.
- Session = a real Execution State: bootstrap turn binds the chat-template
  prefix at position 0 (`create` + `bindRepresentation`); every later turn
  consumes the bound representation with the RAW next user input (E5-v2
  encoding), advances the logical position (`continueExecution` — one
  authoritative lifecycle record per turn), and rebinds the advanced
  prefix (`bindRepresentation`).
- New session = `discard` (lifecycle record) + fresh state on the next
  message. `restoreSession(to:)` exposes logical rollback.
- UI: an Execution State readout (ID / position / turns / lifecycle
  records) beneath the residency gauges.

## Real-device verification (Apple M5, release bundle)

`--self-test-oversized` upgraded to STRICT semantics: pass 1 generates
turn 1; the session is logically RESTORED to the bootstrap position; pass
2 replays the SAME turn consuming the restored representation. PASS
requires bit-identical replay + lifecycle records ≥ 3 + position tracking
+ footprint/cache ≤ 16 GiB + swap 0 + pressure green:

```text
determinism (restore-replay)   PASS — pass1 == pass2 == [8420, 594, 264,
                               13027, 729, 429, 80953, 1378] (identical to
                               every prior run)
lifecycle records              4 (created + continued + restored + continued)
strictExecutionState           TRUE
peak footprint                 10,228 MiB / cache 0 MiB / swap 0 MiB
pressure                       level 1 (green)
mean token                     13,430 ms (22 GiB profile)
overallPass                    TRUE
```

Defects found and fixed in-flight before accepting results:
1. The executeTurn extraction accidentally dropped the bootstrap branch
   (every generate threw "engine not loaded") — caught immediately by the
   self-test, fixed, re-run.
2. The restore-replay determinism initially compared two DIFFERENT input
   sequences (checkpoint captured post-turn + duplicate next input) —
   corrected to the E5 authoritative shape (fork/bootstrap point
   checkpoint + `restoreSession(to: 0)` + empty next input) before
   accepting results.

## Boundary

Fork/branch conversations are supported by the underlying machinery
(O6) but not yet exposed in the UI. ResidencyController segment
accounting (INV-1 over segments) remains the registered follow-up.
Artifacts: `results/o5-sweep/app-realdevice-selftest-execstate.json`.
