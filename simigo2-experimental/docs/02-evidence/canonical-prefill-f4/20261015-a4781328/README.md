# Canonical prefill protocol + F4 lifecycle — 2026-10-15 / a4781328

Implements the F1 adjudication (single canonical execution shape, STRICT
cold==warm equality, no semantic-equivalence relaxation) and the F4 reopen
fixes.

## Canonical protocol result: STRICT PASS

`CanonicalPrefillProfile` = remainder chunking at a fixed stride; cache
boundaries only at positive stride multiples (prefix-stable by construction:
every full chunk [k·C,(k+1)·C) is the identical forward sequence regardless
of total prompt length). Artifacts are namespace-bound to (model content
digest, profile version+stride): a protocol change isolates old artifacts
in a new namespace instead of silently reusing them.

Real-model strict acceptance (Qwen3-Coder-30B-A3B-4bit @ 6e302ea6, greedy,
24 tokens, 968-token prompt):

| stride | boundary | hit | chunks | counts | text | strict |
| --- | --- | --- | --- | --- | --- | --- |
| 512 | 512 | 1 @ 512 | = | = | = | PASS |
| 256 | 512 | 1 @ 512 | = | = | = | PASS |
| 256 | 768 | 1 @ 768 | = | = | = | PASS |

Under one canonical profile the warm adoption path produces EXACTLY the cold
path's generation — chunk sequence, completion token count, and text all
equal, adoption hit exactly at the stable boundary. The F1-adjudicated
contract is achievable through the public ChatSession chunking API; no
fork-side prefill interface change was needed for equality.

Strictness caveat (registered fork API gap): ChatSession does not expose
generated token IDs; chunk sequence + `generationTokenCount` are the finest
public record. The earlier non-canonical flip is now explained: the warm
path ran under the DEFAULT chunking while artifacts came from differently
shaped sessions — under the canonical protocol both paths share one shape
and agree strictly.

## F4 reopen fixes

- `switchModel` captures the previous DIRECTORY only — the old code held
  the whole `ActiveModel` (including the container) in a local across the
  next load, defeating single residency at the switch itself.
- Host-issued generations register as in-flight; a switch invalidates the
  generation, then CANCELS and DRAINS them (bounded 120 s; overrun fails
  the switch with the old state untouched via
  `inFlightGenerationBlockedSwitch`) before dropping the container.
- The probe's foreign-hook residual measurement now runs in the B-active
  window (the previous post-switch-back placement was a recorded
  measurement defect).

Boundary notes: caller-held `HostSession`s still hold their `ChatSession`
(and thereby the container) until the caller drops them — the host cannot
reach caller references; the host-side guarantee is that IT does not extend
container lifetime and does not overlap the next load with host-tracked
generations. Peak-residency instrumentation (RSS sampling around the
switch) is follow-up evidence, not yet recorded.

## Files

- `canonical-stride512-boundary512.json`
- `canonical-stride256-boundaries512-768.json` (two distinct stable boundaries)
- `f4-probe-run2.json` — switch round trip with corrected-window foreign hook
- `manifest.json`
