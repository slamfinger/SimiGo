# FORK-HOOK-CALLER-IDENTITY-01 — closure review ruling

- Review ID: `FORK-HOOK-CALLER-IDENTITY-01-CLOSURE-REVIEW`
- Reviewed baseline: `SimiGo-Lab main = 8384a63bdd5a92bfae06d2c18bcd672242188ba5`
- Fork: `slamfinger/mlx-swift-lm release/v2.0-beta-ml@778ffb78a6be39e9cce988054f714ae912e630a7`
- Decision: **REVISE — caller-origin mechanism evidenced, residual package NOT CLOSED**
- GUI promotion ACCEPT: unchanged and not reopened.
- GUI five-item click-through: remains OPEN post-acceptance supplementary verification.

## Evidence accepted

1. Fork implementation adds `CrossSessionCallerContext(modelDirectory: URL?)`; `ChatSession.evaluate` selects the context hook first and captures the calling container's local directory before rebinding the model object. Hub-ID/no-local-directory origin is nil. The legacy-only path remains available when the context slot is absent.
2. Six fork-level tests are recorded as passing: caller-origin propagation, nil hub origin, foreign-origin cold refusal, same-origin adoption, context precedence, legacy-only compatibility.
3. The real-model host probe holds a raw model-A ChatSession/container and generates while model B is active. The recorded `foreignHookCold: true` is based on an actual generation through the evaluate consultation path and the B-cache miss observation, not a direct static-hook invocation.
4. Canonical cold/warm strict comparison is recorded as passing at stable boundaries 512 and 768; stale-session rejection and full-boundary re-adoption remain passing. The app build and 369 executed / 3 skipped / 0 failures are recorded by the submitting engineer.
5. The implementation's main identity decision is correct for the registered cross-model residual: a directory-bound host cache refuses nil or foreign directory origins, returning nil and recording a miss. Host generation and content-derived namespace remain host-side.

## Blocking finding FCI-OWN-01 — context-slot ownership is not protected against an unregistered foreign owner

### Source evidence

In `MLXPrefixCrossSessionCache.install(...)` on `main = 8384a63b`:

- The conflict check is `if Self.active != nil && !forceTakeover`; when `Self.active == nil`, the method does not check whether `ChatSession.crossSessionPrefixLookupWithContext` is already populated by a foreign owner before assigning over it.
- The idempotent `Self.active === self` branch returns without establishing that the context slot still contains this cache's hook.
- `uninstall()` checks only `Self.active === self`, then sets `ChatSession.crossSessionPrefixLookupWithContext = nil` unconditionally. If another module replaced the public context slot while this cache remained registered as active, uninstall can clear that foreign hook.

The current new ownership test exercises a foreign **legacy** slot and proves it is not clobbered. It does not exercise a foreign **context** slot installed while there is no registered cache owner, or a context slot replaced during this cache's active lifetime.

### Why this blocks closure

The implementation authorization explicitly requires install/uninstall/switch/rollback/deactivate to preserve hook ownership and not overwrite a foreign owner, with a foreign owner in either slot causing fail-closed behavior. The identity rejection itself is evidenced, but the context slot's ownership lifecycle does not yet satisfy that full condition under an external-owner interleaving. This is not evidence that the A-during-B rejection failed; it is a separate gap in the authorized lifecycle contract.

### Required narrow correction

1. Establish a reliable ownership mechanism for the context slot. Installation must not silently take a populated slot unless the current owner is the registered cache being transitioned under the defined switch protocol.
2. Uninstall must clear the context slot only when it can prove the current slot is still owned by this cache; otherwise it must leave the external slot untouched and report/reject the ownership inconsistency.
3. Keep the existing rule that a foreign legacy slot is never cleared by this cache. GUI release verification must continue checking both slots and fail closed if either remains.
4. Add tests for: (a) foreign context slot present before install → no overwrite; (b) context slot replaced during an active installation → uninstall does not clear the replacement; (c) normal host-to-host switch/takeover still works and a displaced cache cannot clear the new owner's slot; (d) existing foreign legacy-owner preservation remains green.

A suitable implementation may use a controlled install/remove API or an explicit ownership token registry; a raw function-slot nil/non-nil check alone is not proof of ownership.

## Closure decision

`FORK-HOOK-CALLER-IDENTITY-01` is **not yet CLOSED**. The cross-model caller-origin behavior is evidenced and may be treated as mechanism-level PASS under the tested flow. FCI-OWN-01 must be corrected and tested, then closure can be reconsidered against the existing evidence; no need to repeat the successful 30B↔35B identity probe unless the fix changes its path.

The same-directory-content-drift sliver remains explicitly accepted and is not expanded by this finding. G-5 / G-8 / G-10, power-loss/media durability, universal concurrency, GUI feature scope, and DCC-1 Tier-1 remain unaffected.

## GUI click-through status

The five SwiftUI click-through checks are still OPEN post-acceptance supplementary verification. The available GitHub evidence does not execute or observe a real desktop GUI session. They must be run against the integrated build after FCI-OWN-01 is repaired; record application build/version, environment, per-item observed behavior, and raw error strings. Do not mark them PASS based solely on the 369/3/0 suite or the real-model CLI probe.
