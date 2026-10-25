# FORK-HOOK-CALLER-IDENTITY-01 — follow-up ownership review

- Review ID: `FORK-HOOK-CALLER-IDENTITY-01-OWNERSHIP-FOLLOWUP`
- Reviewed baseline: `SimiGo-Lab main = c498f874f3ea6c8ec8deebac025983430e204d9b`
- Fork baseline: `slamfinger/mlx-swift-lm release/v2.0-beta-ml@778ffb78a6be39e9cce988054f714ae912e630a7`
- Decision: **REVISE — the two direct conflict tests pass by report, but slot ownership is not yet proven strongly enough for closure**
- GUI promotion ACCEPT remains unchanged.
- Identity-path real-model evidence and canonical regression evidence remain accepted; this finding does not invalidate them.

## Evidence retained as PASS

The reviewed commit implements:
- refusing plain installation when the internal registry is empty but the context slot is already populated;
- a per-install inert caller-origin marker and dedicated counter;
- preserving a simple external replacement whose closure does not route the marker to this cache;
- tests for that simple replacement and for a foreign context owner blocking plain install.

The previously evidenced real model-A session being refused at the actual `evaluate` consultation while model B is active remains valid for the tested flow (`foreignHookCold = true`). Canonical cold/warm strict equality and the submitted 369/3/0 run remain valid as the already-recorded evidence; this review did not rerun the experiment.

## Blocking finding FCI-OWN-02 — marker reachability is not slot ownership

### Case A: wrapper/decorator replacement can forward the marker

The new `uninstall()` takes the current static context hook and passes the ownership marker to it, then treats an increment in the original per-install probe counter as proof that the slot still belongs to this cache.

A replacement closure can wrap the original installed closure, forward the marker to it, and still be a distinct externally-owned slot value. The original closure increments the probe counter, so the ownership challenge succeeds; `uninstall()` then sets the global context slot to nil, removing the external wrapper. The new test only covers a simple replacement closure that returns nil and does not forward the marker; it does not cover decorator/wrapper composition.

The marker is orthogonal to ordinary model traffic, but its reaching the old closure proves reachability in the current call chain, not exclusive ownership of the slot itself. The marker is also a fixed documented URL value rather than an unforgeable identity token; do not treat its secrecy as an ownership guarantee.

### Case B: same-instance install fast path skips revalidation

In `install()`, the `Self.active === self` branch marks the cache installed and returns before verifying that the current context slot still routes to the current installation. If an external closure replaced the slot while this cache remained registered as active, another `install()` call on the same instance reports success even though the cache's caller-identity guard is no longer the active hook.

This is a fail-closed gap in an API whose contract says the same instance is idempotent only while it remains the owner. The existing tests do not cover “active registry still says self, static slot replaced, same-instance install called again”.

## Required narrow correction

The implementation needs an ownership representation that distinguishes the actual slot owner, rather than a behavioral canary that can be forwarded by a wrapper.

Preferred narrow direction:
1. Represent the new context slot through an identity-bearing hook holder/registration value with an owner token (or an equivalent controlled registry API) so the slot's current owner can be compared to this cache's installation identity.
2. Keep a stable per-install ownership token and require both the registry and slot identity to match before same-instance install reports success.
3. On uninstall, clear the slot only if the currently-installed holder/registration identity is the one installed by this cache. If a wrapper or another external owner replaced the slot, preserve it and report inconsistency.
4. Preserve explicit force-takeover semantics and the rule never to clear the foreign legacy hook.
5. Add tests:
   - external wrapper forwards the marker to the original closure → uninstall detects the replacement and preserves the wrapper;
   - the registry says this cache is active but the context slot has been replaced → repeated install fails closed;
   - ordinary install/uninstall and host-to-host switch still pass;
   - foreign context slot blocks plain install; explicit takeover still works;
   - foreign legacy hook is preserved.

Do not attempt to strengthen this by making the marker more obscure; an opaque marker is not a substitute for slot-owner identity.

## Closure status

`FORK-HOOK-CALLER-IDENTITY-01` remains **OPEN / mechanism PASS in tested identity flow, ownership closure pending** until FCI-OWN-02 is fixed and the focused tests pass. Re-running the real 30B↔35B identity probe is not required unless the final ownership representation changes the actual evaluate-to-hook path. If that path changes, repeat the foreign-caller leg in the true B-active window.

## Independent GUI verification and non-goals

The five GUI click-through items remain **OPEN post-acceptance supplementary verification**, to be executed on the final integrated build and recorded per item. The existing GUI promotion ACCEPT remains valid and is not reopened by this ownership finding.

Same-directory content drift remains the explicitly accepted residual. G-5 / G-8 / G-10, power-loss/media durability, universal concurrency, GUI feature expansion, and DCC-1 Tier-1 remain outside scope.
