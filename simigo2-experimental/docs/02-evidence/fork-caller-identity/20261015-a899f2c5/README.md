# FORK-HOOK-CALLER-IDENTITY-01 — implementation evidence

Authorization: c5c92ecc (bounded scope, registered verification).
Fork revision: slamfinger/mlx-swift-lm `release/v2.0-beta-ml@778ffb7`
(rebased onto fd5d1b4; the authorization's review baseline 6d01a13c is an
ancestor — recorded exactly per requirement). SimiGo integration commit:
this evidence's parent on `codex/fork-caller-identity-integration`.

## Fork-level tests (6/6 PASS, in-tree `swift test`)

Origin received from the calling session's own configuration; hub-id origin
arrives nil; foreign-directory refusal takes the cold path (generation
completes, no cross-session reuse); same-directory adoption reports
cross-session reuse (seeded through the PUBLIC savePromptCache→load round
trip); context slot precedence over legacy; legacy-only compatibility
unchanged.

## Host integration (real model, 30B↔35B)

- **Foreign caller refused at the REAL consultation point**: the probe now
  holds its own model-A container and, while model B is actually active, a
  RAW ChatSession (outside the host) generates "ping" — its evaluate
  consults the context hook carrying A's origin, which B's cache refuses
  (recorded miss, cold path). `foreignHookCold = true` is now the identity
  API's end-to-end evidence, not a direct static-hook call.
- Stale host session rejected (`sessionStale`), full-boundary re-adoption
  (512), switch round trip under release-first single residency with
  in-flight drain.
- Directory binding: nil origin and foreign directories refuse with a
  recorded miss; unbound installs stay identity-agnostic (legacy callers).
- Dual-slot lifecycle: uninstall releases the context slot without
  clobbering a foreign legacy owner; `ownsNoHookSlot` exposes complete
  release; GUI teardown fails on EITHER slot remaining.

## Regression

Canonical strict cold==warm equality under the new hook: stride 256 at
boundaries 512 and 768 — chunk sequences, completion token counts, texts
all equal, hits exactly at the boundaries. App builds; full suite
`369 executed / 3 skipped / 0 failures`.

## Status

Caller-identity residual: **evidence complete, submitted for review** —
closure of the residual is a review decision, not self-declared. Retained
boundaries: same-directory content drift stays an accepted sliver (fork
sees directory, not content); G-5/G-8/G-10, non-process-crash durability,
and universal concurrency remain outside; DCC-1 Tier-1 untouched; the five
GUI click-through items remain OPEN post-acceptance supplementary
verification, now to be run against THIS integrated build.

Note: the canonical regression JSON is bit-identical to the pre-integration
canonical run — expected: the strict record (chunk sequences, counts,
texts, hits) is deterministic for the same model/prompt/profile and the
report carries no timestamps. Identical bytes ARE the reproduction.

## FCI-OWN-01 correction (closure-review follow-up, same authorization)

The closure review accepted the identity mechanism but found two ownership
gaps; both fixed with a CONTROLLED ownership mechanism (nil/non-nil slot
checks alone are not ownership proof):

- Plain install now refuses when the CONTEXT slot is occupied by anyone the
  internal registry does not know — an external installer that assigned the
  static directly leaves `active` empty while the slot is taken; that is a
  foreign owner and a plain install fails closed. Explicit takeover remains
  the only overwrite path.
- Uninstall clears the context slot only after a PROBE verifies it still
  routes to THIS cache: the installed hook recognizes a private caller-
  origin marker (inert to real traffic, dedicated counter, recreated per
  install) and uninstall challenges the slot under the ownership lock. An
  externally replaced slot fails the probe: the replacement is PRESERVED
  (not cleared), `ownershipInconsistencyDetected` is set, and uninstall
  returns false.

New tests: foreign context-slot owner blocks plain install (takeover may
replace); externally replaced slot survives uninstall with the
inconsistency reported. Normal switch/takeover/foreign-legacy semantics
unchanged (existing tests). Suite 371/3/0; app and ctl build. The
real-model identity probe's execution path is unchanged (the probe branch
is inert to real callers), so its evidence stands; residual closure is
resubmitted for review.
