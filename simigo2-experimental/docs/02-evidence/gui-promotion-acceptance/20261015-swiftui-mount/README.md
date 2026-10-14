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
   stable. NOTE: an earlier controlled run reported a NEGATIVE result
   ("warm 2.3x slower"); that was a Duration-conversion measurement bug and
   is formally RETRACTED — see
   `f3-benefit-protocol/20261015-8cbff75c/RETRACTION-and-fix.md` before
   reading any F3 timing numbers predating it. Corrected data:
   `f3-benefit-protocol/20261015-8cbff75c/f3-run3-corrected-positive.json`.

## Lifecycle correction (post-review, same unit)

The first mount left three path-binding gaps (reviewer findings): switching
back to oversized did not deactivate the small-scale host or clear the
UI-held session; switching models within the small-scale path did not clear
the UI-held `HostSession` before the host's release-first flow; and Send
branched on the SELECTOR rather than the actually-loaded path. All three
fixed:

- `loadedExecutionPath` / `loadedModelDirectory` record what is ACTUALLY
  bound; the selector is a request that only Load fulfills. Send and New
  Session are blocked with a "press Load first" prompt while selector and
  binding disagree (this also removes oversized send-before-load; the
  first-message lazy-load of an already-bound engine remains).
- Oversized bind: clear `chatSession` → `host.deactivate()` → drop the host
  → VERIFY `ChatSession.crossSessionPrefixLookup == nil` → build the engine
  (a foreign hook owner fails the bind loudly).
- Small-scale bind/model switch: clear `chatSession` (the HostSession
  retains the old model's container; the host cannot release what the GUI
  holds) BEFORE the host's drain/release/load flow.
- Small-scale load failure reports the SURVIVING binding (rolled-back model
  or deactivated host), never the requested one.

Verification mapping: selector/binding guard, teardown ordering, and hook
release check are code-verified (build + suite 367/3/0); stale-session
rejection, release-first switch with drain, and failed-switch rollback are
evidenced at the host layer (real-model probe runs above); the real SwiftUI
click-through of both directions, same-path model change, send-before-load,
and switch failure remains the pending HUMAN step — unchanged from the
matrix status below.

## Directory-level guard (second review round)

The path-type guard left a same-path hole (reviewer): changing the model
directory without Load passed it — small-scale would session against the
actually-active old model, oversized's first message would lazily load the
NEW directory, both bypassing the explicit Load. Send and New Session now
check one binding-validity predicate (loaded path == selected path AND
loaded model directory == standardized requested directory), which also
covers the failed-switch rollback case. Build + suite 367/3/0 at
`c5b4daa3`.

## Binding publishes only on confirmed load (third review round)

The oversized branch published `loadedExecutionPath`/`loadedModelDirectory`
synchronously, BEFORE the async recover + load completed; the failure branch
cleared neither, so a failed load could leave `bindingMatchesRequest == true`
and Send passing into the lazy-load path. Fixed per the minimal prescription:
every Load invalidates the binding at start; oversized re-publishes it only
in the async success block (after recover AND load succeed); small-scale
keeps publishing from the host's surviving active state (success or
rolled-back truth). A failed load therefore blocks Send/New Session until a
successful Load re-establishes the binding. Build + suite 367/3/0.

## Manual click-through checklist (pending — the human acceptance step)

1. Send before any successful Load (including after a failed oversized
   Load with an error model directory) — must be blocked with the
   "press Load first" prompt.
2. Bidirectional path switching oversized → small-scale → oversized — old
   path released, hook-release check passes, new path works.
3. Same-path model directory change without Load (both paths) — Send and
   New Session both blocked.
4. Switch to a deliberately unloadable model — rollback keeps A active
   while the request points at B; Send blocked.
5. Post-switch use of an old session errors visibly (never continues on the
   new model); after New Session the durable cache is retained and the next
   session re-hits it (hook counters in the status line).

Record per-item outcomes and actual error strings; on failure, record the
observed state instead of proceeding. ACCEPT is adjudicated only after this
walkthrough.

## Promotion status

All five matrix items carry real-model evidence; the mount is build-verified
with the runtime layer fully evidenced. GUI promotion ACCEPT is submitted
for the human decision — this document is the evidence package, not the
acceptance itself. G-5 / G-8 / G-10 remain with independent governance
review; no durability/universal-concurrency claims are made.
