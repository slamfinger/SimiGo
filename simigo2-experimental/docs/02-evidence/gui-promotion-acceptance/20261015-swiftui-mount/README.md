# GUI promotion — SwiftUI mount + five-item acceptance matrix — 20261015

## Mount (this unit)

`SimiGo2App` gains an EXPLICIT `ExecutionPath` picker (segmented control):
`oversized (segmented engine)` [default] | `small-scale (ChatSession host)`.
No silent switching: Load re-binds to the selected path; loading one path
tears the other down first. The small-scale path wires
`MLXSmallScaleChatHost` with a durable cache base in Application Support
(cross-session snapshots survive app restarts); turns run through
host-issued generation-checked sessions (stale sessions after a model switch
are rejected and surfaced, never silently evaluated); New Session drops the
conversation session but RETAINS the durable cache so the next conversation
adopts its prefix. The engine target and every DCC-1 Tier-1 semantic are
untouched (this unit modifies only SimiGo2App.swift + one access-level
change in the host). Build-verified (`swift build --product SimiGo2App`);
full suite 367/3/0.

Honest limit: there is no automated GUI-interaction harness in this repo —
interactive acceptance (click-through) remains a human step. Every runtime
behavior the UI depends on is evidenced at the model layer below.

## Five-item acceptance matrix (assembled evidence)

1. **Same-model cross-session hit & strict equality** — PASS, real model:
   canonical protocol strict cold==warm (chunk sequences, completion token
   counts, texts) across 2 strides × 2 distinct stable boundaries; adoption
   hit exactly at the boundary. Evidence:
   `canonical-prefill-f4/20261015-a4781328/`.
2. **Model identity isolation** — PASS: content-derived namespaces separate
   same-name/different-content models (unit); namespace-bound canonical
   profile isolates protocol changes (unit); foreign-hook probe in the
   B-active window returned nil for the other model's tokens (real model).
   Evidence: same directory + `f1-f4-diagnostics/20261015-e88eca5c/`.
3. **Invalidation & corruption fail-closed** — PASS (unit): corrupted
   artifact bytes → hook returns nil, miss recorded, no partial adoption;
   activation rescan fails closed on corrupt durable roots.
4. **Concurrent switching & lifecycle** — PASS, real model: 30B→35B→30B
   round trip under release-first single-residency with in-flight
   cancel+drain; stale-session rejection; full-boundary re-adoption.
   Registered open (non-blocking for the mount, documented): fork hook
   signature carries no caller identity — raw non-host sessions are a
   residual risk behind namespace/layer/token-chain mitigations.
5. **Actual benefit** — PASS, corrected instruments: paired canonical legs,
   48% wall savings (1.28-1.30 s → 0.66-0.68 s), TTFT 0.88 → 0.29 s, swap
   stable; the prior negative was a measurement bug, formally retracted.
   Evidence: `f3-benefit-protocol/20261015-8cbff75c/`.

## Promotion status

All five matrix items carry real-model evidence; the mount is build-verified
with the runtime layer fully evidenced. GUI promotion ACCEPT is submitted
for the human decision — this document is the evidence package, not the
acceptance itself. G-5 / G-8 / G-10 remain with independent governance
review; no durability/universal-concurrency claims are made.
