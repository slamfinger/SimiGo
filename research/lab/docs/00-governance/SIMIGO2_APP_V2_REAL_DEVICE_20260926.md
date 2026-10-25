# SimiGo-Lab — SimiGo 2.0 App v2 + Real-Device Verification — 2026-09-26

Status: APP_V2_DELIVERED / OVERSIZED_SELFTEST_PASS_ON_DEVICE
Phase: SimiGo 2.0 Experimental (post-O6 engineering delivery)

## What was built

**OversizedSegmentedEngine** (`OversizedSegmentedEngine.swift`) — the
O-line's verified mechanics productized as the app-facing engine:
- seg8 default (6×8-layer segments — the measured Pareto-best operating
  point: 7.7 s/token at 8.8 GiB peak, swap 0)
- placeholder-first load (the registered cliff fix) through the
  single-copy safetensors reader
- greedy cacheless generation, checkpoint chat-template multi-turn input,
  per-token streaming callbacks with live gauges
  (active/footprint/swap/resident-segment)

**SimiGo 2.0 App v2** (`Sources/SimiGo2App/SimiGo2App.swift`), borrowing
the SimiGo 1.7 app shape (chat session, streaming assistant output,
model loading) and adding the 2.0-specific capabilities:
- multi-turn chat UI over the oversized segmented engine (qwen3_next)
- live residency panel: per-token active/footprint/swap + resident-segment
  indicator; engine stats line (core GiB, segments, load time, capacity
  gate)
- new-session reset; legacy Gate 5 real-device self-test retained intact
- NEW `--self-test-oversized --model M [--tokens N]`: double-pass
  segmented generation; PASS requires token determinism, peak footprint
  ≤ 30 GiB, swap 0

## Real-device verification (Apple M5, 32.0 GiB, macOS 26.6.2)

Run from the built .app bundle binary
(`build/SimiGo2Experimental.app/Contents/MacOS/SimiGo2App`), release build:

```text
gate                O4_OVERSIZED_REAL_DEVICE_APP_SELFTEST
model               Qwen3-Coder-Next-4bit (41.76 GiB > 32 GiB physical)
engine              seg8 (6 segments), load 0.82 s
determinism         PASS — pass1 == pass2 == [8420, 594, 264, 13027, 729,
                    429, 80953, 1378] (identical to every O4/O5/O6 run of
                    this prompt since the reader fix)
peak footprint      8,293 MiB (gate 30,720)
max swap            0 MiB
mean token          9,075 ms
overallPass         TRUE
```

A unit defect in the engine's per-token timer (attoseconds→ms divided by
1e6 instead of 1e15) inflated the first run's meanTokenMs; fixed and the
self-test re-run before registering.

## Boundary

The GUI chat targets qwen3_next oversized models; fitting-model chat and
the legacy Gate 5 proof remain available. Execution State fork/restore
semantics live in the O6 components (not yet wired into the app session
layer — registered follow-up, along with ResidencyController segment
accounting). No performance/production claims.

Artifact: `simigo2-experimental/results/o5-sweep/app-realdevice-oversized-selftest.json`;
app `Sources/SimiGo2App/SimiGo2App.swift`; engine
`Sources/SimiGo2Experimental/OversizedSegmentedEngine.swift`.
