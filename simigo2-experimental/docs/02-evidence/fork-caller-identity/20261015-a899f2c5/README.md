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

## Status: CLOSED (fourth review round, bc50ce14)

FORK-HOOK-CALLER-IDENTITY-01 closed within the original authorization
scope. OWN-03/04/05 all ACCEPT; the ownership residual (FCI-OWN-01 through
05) closed across four review rounds. Evidence boundary recorded verbatim
from the adjudication: OWN-03's closure rests on STATIC access-control
review (private storage, no public accessor — the same-token wrapper is
unconstructible by API shape); the runtime test covers different-token
non-impersonation, not a same-token attack (which has no constructible
instance). The standing real-model identity rejection and canonical strict
equality evidence remain valid under the no-rerun exemption. Retained
boundaries unchanged: GUI promotion ACCEPT intact; five click-through
items OPEN pending local human execution; G-5/G-8/G-10, power-loss
durability, and universal concurrency gain nothing from this closure;
same-directory content drift remains the accepted sliver. Retained
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

## FCI-OWN-02 correction (second closure-review round)

The marker probe proved REACHABILITY, not slot ownership: a wrapper closure
that forwards calls (including any probe) still bumps our counters, and the
idempotent install fast path did not re-verify the slot at all. Fixed with
a COMPARABLE owner identity as directed:

- Fork (0a291ab): the context slot holds a `CrossSessionPrefixLookup`
  struct — the lookup closure PLUS an `OwnerToken` identity compared with
  `===`, which a forwarding wrapper cannot carry. The legacy bridge uses a
  private sentinel token no host can hold. Consultation call semantics
  unchanged (same closure, same arguments) — the standing real-model
  identity-probe and canonical evidence remain valid per the review's
  instruction.
- Host: install/idempotent-return/uninstall all verify the CURRENT slot's
  owner token before claiming, fast-returning, or clearing. A slot held by
  anyone else (bare-closure era or struct with a foreign token) blocks a
  plain install; only explicit takeover replaces it. Uninstall clears only
  when the slot carries OUR token; otherwise the replacement is preserved,
  `ownershipInconsistencyDetected` is set, and false is returned. The probe
  machinery is removed (superseded).

New tests: the FCI-OWN-02 core counterexample — a wrapper forwarding our
own lookup under a foreign token remains fully FUNCTIONAL (reachability
intact) yet plain reinstall refuses and uninstall preserves it; idempotent
reinstall verifies slot ownership. Existing takeover/legacy-protection
tests unchanged. Suite 373/3/0; app builds. Residual closure resubmitted.

## FCI-OWN-03/04/05 correction (third ownership review round f050e7de)

- OWN-03 (token transferability): the fork token storage is now PRIVATE
  with no accessor (eab6895); ownership answers only through
  `isOwned(by:)`, which returns true solely to a party already holding the
  exact token. The review's same-token wrapper — read `original.owner`,
  rebuild with it — is UNCONSTRUCTIBLE: there is nothing to read. Host
  comparison switched to `isOwned(by:)`.
- OWN-04 (registry desync): the registry check is restored as an
  INDEPENDENT authority — a live `Self.active` instance blocks a plain
  install even when the static slot was externally cleared; only explicit
  takeover displaces. New test: active → slot cleared externally → plain
  install refused.
- OWN-05 (ownsNoHookSlot semantics): restored to its documented meaning —
  actual slot EMPTINESS (`active !== self && slot == nil`). A preserved
  external wrapper keeps it false until the slot is truly cleared. New
  test covers both phases.

Suite 376/3/0; app builds. Consultation call path and arguments unchanged
(ownership comparison only), so the standing real-model identity and
canonical evidence remain valid per the review's standing instruction.
The prior different-token wrapper counterexample test is retained.
