# Limitations — Model-Level Continuous-Calc Verification

**Run:** 2026-10-17 · `selftest.py --arm all`, single real local model + real
`carrier_loop.py`. Companion to `results.md`. Each item is labeled with the
criterion it qualifies so it maps directly onto a verdict line.

## L1 — No real Swift executor (`Calculator` interface)

The physical model work is injected via `unit_real_prefix` (physical quantity =
token-prefix length). This proxies "one unit of model computation." It lets the
counterfactual distinguish **info-reuse** (read a cached settlement) from
**compute-reuse** (skip work that would have run), which is the experiment's
core capability. But it does not invoke a real model, so anything that depends on
the *nature* of the computation is off-limits.

## L2 — "Which units recomputed" is cache-precision, not compute tracing (G/B/C/D/E/H/I)

The experiment records what Swift *would* do by observing cache precision and the
is_objects `byte_size`/content, not by tracing which units were actually
computed. Consequences:

- **E (avoid recompute)** proves *recomputable info stayed in IS and was not
  re-executed this stage* — cache presence, not the actual compute-skip. The
  "would have run but did not" counterfactual is inferred, not observed.
- **H (selective invalidation)** — the recompute set is derived from cache precision
  (changed-payload ⇒ re-settled, matching the IS settle state), not from tracing
  compute. The carrier's `invalidate_settlement(include_dependents=True)` DFS closure
  is *observed* (its `invalidated_item_ids`), but whether that same closure is the
  correct expected set was for years assumed equal to `{"U_upstream"}` by reading the
  empty executor arrays. This harness still cannot tell REUSE from COMPUTE per unit:
  **This is why H reads PASS-部分 and not PASS.** Swift's `Calculator` (which returns
  REUSE/COMPUTE per unit, carrier loop.py:685-686) can confirm it; the current harness
  cannot.

## L2a — Expected recompute closure now validated for one linear chain AND one non-linear graph (H)

The corrected harness derives the expected recompute set independently from the task's
dependency graph (`expected_recompute_set`) and compares it to the carrier's observed
DFS closure. That comparison is clean **only for a single linear chain** where all three
units transitively depend on one upstream change — the case arm-3 actually exercises.

Arm-4 (diamond) closes the previous gap: a non-linear graph with an independent sibling
subtree now exercises both directions — no missing propagation (the convergence node D is
invalidated via *both* B and C paths) and no over-propagation (unrelated E stays valid +
reused). The expected-set derivation (`expected_recompute_set == proxy-affected set`) is now
verified for a diamond + unrelated-branch shape, not just the linear chain.

Still unexercised: **a unit with a stale-but-live handle masked by an unrelated sibling's
live cache entry** (the masking scenario in L2b), where the expected-set contract could not
detect staleness from IS alone. The diamond's E stays-correct because E settles a distinct
digest; the subtle "live handle, stale value" case needs Swift's real evaluation.

## L2b — Expected-set derivation depends solely on TASK_DEMAND deps, not IS state (H)

`expected_recompute_set` is derived purely from the task definition's `TASK_DEMAND` deps
plus which input changed — deliberately, so carrier-proxy and executor-truth are judged
against one pre-computed contract. That independence is exactly the value, but it also
means the expected set does **not** consult IS state: if two units happened to settle the
same digest, or an unrelated unit's handle was still live but its value stale, the expected
set could not catch that from IS alone. The carrier-proxy layer validates the live-handle-
does-not-imply-stale value, but only for this chain. For a DAG where an unrelated sibling's
live handle could mask a stale result, that masking has not been exercised.

## L2c — Real-model path has a Swift-runtime boundary not exercised here (A)

The real carrier requires `confirm_runtime_application` to flip
PENDING_SWIFT → APPLIED_SWIFT (carrier loop.py:291-293). This experiment
models that boundary with `_advance_to_applied` but does not run a real Swift
loop's full runtime-confirmation cycle. The boundary is *simulated*, not observed,
so A reads PASS-部分.

## L2d — True model-work-saved counterfactual is inferred (I)

`calculate_real_cost()` estimates the theoretical baseline cost if Swift had to
recompute from scratch. Actual saved work is `theoretical - actual`, but "actual"
is derived from the cache-precision probe (L2). Saved model-work is therefore an
**estimate**, good for trend, not a measured wall-clock reduction.

## L2e — Single validity-policy shape only

VALID_UNTIL is far-future (`2099-12-31`); the policy exercised is a single
self-consistent shape (`policy_version=v1`, `policy_source=simulation://`). Cache
invalidation under a genuinely *expiring* policy and the carrier's expiry-time
validation (carrier loop.py:704-724, `valid_until_utc` / stale detection) are
not exercised.

## L2f — One per-request cache-invalidation scenario per arm; no concurrency / recovery injection

- Arm 3 exercises exactly one invalidation (U_upstream payload change). Partial
  recomputation and concurrent demand re-computation are not tested — they need
  multiple concurrent `execute_demand` calls and, crucially, Swift's atomicity /
  versioning (carrier loop.py:43-159) to be meaningful. The single-model harness
  cannot inject a second writer, so there is no "two stages racing" case.

## L2g — KV-prefix lifecycle not verified without Swift (C/I/J)

All timestamps are simulation-driven (`run_epoch`, `2026-10-17T…`); none are
real wall-clock, so:

- **C** — a Swift KV store's real key-prefix lifetime (does a stale cache entry
  actually persist and get dropped past its TTL?) cannot be observed. Only the
  *lifecycle isolation* (new-stage handle present) is verified; prefix-lifetime
  semantics are a Swift concern.
- **I** — actual save time is measured; model-work-saved is an estimate (L4).
- **J** — reproducibility is from timestamped logs, not re-run determinism across
  Swift invocations.

## L2h — `evaluate_demand` does not return settled results by default (API contract, documented workaround)

This is a documented carrier API shape, not an experiment defect. `evaluate_demand`
by default records lineage and **does not return settled results**. To observe the
results, this experiment calls it with `return_results=True` (selftest.py:276).
Downstream: because the result is only materialized via that extra call, it shows
as a separate log event — seen as `execute-demand-note` in arm2/arm3 logs
(ValueError: pending runtime application requires confirmation). Expected and fine;
it is a no-op once the demand has advanced.

## L2i — No model in real Swift runs → limited model-parallelism observation (plan item 6)

The plan's item 6 ("observe model parallelism in real Swift runs") presupposes a
real executor. Without one, this experiment cannot observe parallelism; the plan
document records it as explicitly deferred to when a real Swift/CX model is used.

## L2k — Two-stage, not full continuous; invalidation granularity coarse (plan item 2)

Arm 3 injects one big invalidation (a whole upstream payload change), not the
fine-grained single-unit or partial recomputation Swift would see in steady state.
This limits the *concrete recompute pattern* observation; more granular scenarios
need Swift's versioning + concurrency (see L6).
