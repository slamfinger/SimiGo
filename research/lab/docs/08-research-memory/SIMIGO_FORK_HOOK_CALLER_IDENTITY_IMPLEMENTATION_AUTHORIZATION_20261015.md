# FORK-HOOK-CALLER-IDENTITY-01 — implementation authorization

- Authorization ID: `FORK-HOOK-CALLER-IDENTITY-01-IMPL`
- Decision: **AUTHORIZED — bounded implementation and registered verification**
- Decision basis: the user explicitly delegated selection of the next lawful action to the reviewer; this decision authorizes only the scope below.
- Design basis: `docs/08-research-memory/SIMIGO_FORK_HOOK_CALLER_IDENTITY_REVIEW_20261015.md`
- Baseline: `SimiGo-Lab main = 83256a2bec996148d76d1f880a9b614d30ddae5f`
- Locked fork baseline: `mlx-swift-lm@6d01a13c8f54610054bc28f7163de740b43be4f8`
- Status ceiling: authorization is NOT implementation, NOT test evidence, and NOT closure of the residual.

## Authorized scope

1. Add an opt-in context-aware hook API alongside the legacy `ChatSession.crossSessionPrefixLookup`. The context must carry the calling session's model origin (`modelDirectory: URL?`).
2. At the `ChatSession.evaluate` consultation point, derive caller origin from that session's own retained `ModelConfiguration.id`: `.directory(URL)` yields the local model directory; unresolved/non-directory IDs yield nil.
3. When the context hook is installed, `evaluate` must prefer it and pass the caller context. When it is absent, the legacy hook path retains its prior signature and behavior.
4. The SimiGo host installs the context-aware hook and refuses adoption (returns nil, records a miss, performs no partial adoption) for nil caller origin, caller directory mismatch, or a stale host generation. Existing cache namespace/content identity, token-chain, and layer-count checks remain in force. Refusal must take the ordinary cold-prefill path.
5. Keep identity responsibilities separated: model-origin validation belongs in the fork consultation path; host generation and content-derived cache identity remain host-side. Normalize caller and active directory URLs consistently using the existing path-identity policy.
6. Adapt hook ownership, installation, switch/rollback, and deactivation for BOTH hook slots. The implementation must not overwrite a foreign owner, leave a stale context hook installed, or mistake `crossSessionPrefixLookup == nil` alone for complete hook release. The GUI's post-deactivation verification must account for the context hook too; a foreign owner in either slot must fail the bind closed.
7. Update the foreign-caller diagnostic to exercise the context-aware consultation path during the actual model-B-active window. A direct call to the old static hook is not sufficient evidence for the new API. Prefer an actual retained pre-switch ChatSession reaching `evaluate`; if the locked fork makes that impossible, document the exact limitation and add the narrowest test that proves caller context is derived at the consultation point.

## Required verification / acceptance criteria

### Fork-level tests
- Context hook receives the calling session's actual local directory at the consultation point.
- Same-directory caller can hit a matching snapshot when all existing checks pass.
- Different-directory caller and nil-origin caller both receive nil (miss/cold path), with no partial adoption.
- Stale generation and existing chain/layer rejection still fail closed.
- Context hook takes precedence when installed; legacy-only installation preserves prior behavior.
- Install/uninstall, failed install, switch, rollback, and deactivate correctly preserve ownership and release both hook slots without clobbering foreign owners.

### Host integration and regression
- In the correct model-B-active window, a retained model-A session reaching the actual context-aware consultation point is refused (nil/miss); the observation must not be taken before B is active or after A is restored.
- Same-model canonical cold/warm behavior remains strictly equal under the registered comparison contract, and the warm prefix hit remains at the configured boundary.
- Run the targeted fork tests, host integration probe, application build, and full applicable test suite. Record exact fork revision, SimiGo-Lab commit, commands, environment, and results. Do not report success before evidence exists.

## Explicit non-goals and retained boundaries

- No change to the legacy hook's signature or behavior.
- No host/generation/content-digest concept added to the fork API.
- No GUI feature expansion beyond the hook lifecycle checks required to safely install/release the new slot.
- No changes to `OversizedSegmentedEngine` or DCC-1 Tier-1 semantics.
- No G-5 / G-8 / G-10, power-loss/media durability, or universal-concurrency claim.
- Same-directory content drift remains an explicitly accepted residual: directory origin does not prove that the bytes on disk have not changed since a raw session loaded. Host-issued sessions remain protected by content-derived namespaces; do not claim the fork can verify content identity.

## Completion and next gate

Implementation completion requires code plus the evidence above. Keep the caller-identity residual OPEN until the integration observation and compatibility suite pass and are reviewed. The five GUI click-through items remain **OPEN post-acceptance supplementary verification**; run and record them against the integrated build after this change. This authorization does not mark those items PASS and does not reopen the already-issued GUI promotion ACCEPT.
