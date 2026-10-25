# Reviewer Memo — arm-3 Evidence Restructure (rev 2026-10-17)

**Author:** reviewer · **Status:** memo, not a ruling. Findings the experiment
team should address before this becomes durable evidence for H (or E/C/I, which
carry the same proxy-only structure).

**Verdict: ACCEPT as a stage-completion evidence restructure. Both previously-open
gates (B1, B3) are now closed.** The proxy-layer restructuring is complete and the
"which units must recompute" claim is established for one linear chain AND one
non-linear diamond. What stays OPEN is the Swift executor half (B0), which gate is
independent of this restructuring.

---

## Why this is a real correction, not an H→PASS promotion

The team moved the fix one layer back — from "make H look cleaner" to "separate
three observations that were conflated." That is the right move and it does land.

Concretely, arm-3's `recompute-after-invalidation` event now carries three fields
that previously collapsed into one:

|---|---|---|
| `expected_recompute_set` | `[U_parse, U_summarize, U_upstream]` | derived from task deps `U_parse→U_upstream`, `U_summarize→U_parse` + which input changed |
| `carrier_proxy_recompute` | `[U_parse, U_summarize, U_upstream]` | IS settle state + v2 payload match after `invalidate_settlement(include_dependents=True)` |
| `executor_observation` / `real_calculator_wired` | `true` / `false` | executor NOT independently instrumented |

The independent expected set is the valuable part. It came from the task's own
dependency graph, **not** from reading the carrier's arrays. That is what was
missing in the prior `{"U_upstream"}`-hardcoded pass — and the prior pass looked
like a fix but was re-derived from exactly the artifact (empty `computed`/`reused`)
that had caused the earlier FAIL. This run is not self-confirmed in that way.

H stays **PASS-部分** because `real_calculator_wired=false`: the second
execute-demand's `computed=[...]` is carrier bookkeeping, not an independent
executor measurement. That is the correct, honest call and I agree with it.

---

## Gates

### B1 (must-close) — CLOSED ✅

Arm-3's `recompute-after-invalidation` now records the derivation rule once and
compares as **sets**, not ordered lists:

```json
"derivation_basis": "expected = {changed_unit} ∪ units transitively depending on it,
                     under TASK_DEMAND deps; derived BEFORE touching IS",
"comparison_rule": "set-based: set(expected) == set(proxy), ordering ignored (B1)"
```

`expected_recompute_set` is derived from the task's own dependency graph (not from
reading the carrier's `computed`/`reused` arrays) and the two fields are compared as
sets, so an identical ordering no longer reads as self-fulfilling. Evidence:
`logs/arm3.jsonl`, event `recompute-after-invalidation`.

### B3 (must-close) — CLOSED ✅ via new arm-4 diamond experiment

A second, **non-linear** case now exists. Diamond graph (A=changed source; B=[A],
C=[A]; D=[B,C] convergence node; E = unrelated independent branch). After changing
only A's source_payload:

- **No-missing direction:** every affected unit including the convergence node D is
  invalidated + recomputed — `expected_recompute_set = [A, B, C, D]`.
- **No-over-propagation direction:** E stays valid and is reused (info-reuse), never
  recomputed. Over-propagation guard reads the executor's authoritative
  `reused_item_ids: [E]` vs `computed_item_ids: [A,B,C,D]`.
- **Set equality:** proxy-affected set == independent expected set.

Both directions verified simultaneously in one run: invalidation must not miss a
path nor drag in an unrelated subtree. Diamond H now `PASS`. Evidence:
`logs/arm4.jsonl`, events `diamond-invalidate` + `diamond-recompute`; run logic in
`run_arm_4_diamond`. **Note: diamond raises carrier-semantic evidence only** — its
executor half is `NOT_INSTRUMENTED` (no real Calculator), so model-level continuous
computation stays NOT VERIFIED exactly as before.

---

## Housekeeping (B2 + misc) — low priority, don't block on these.

- **Per-unit executor events now recorded (B2 ✅).** arm-4 logs a per-unit `calc`
  event for every recomputed unit (9 in the diamond run; arm-1 logs 3), so the
  reviewer can see that each unit actually changed state and what model-work it
  performed (prefix_len, `real=true`). B2 satisfied. (arm-1/arm-2/arm-3 still lack
  per-unit calc; not blocking since arm-4 covers the executor-event shape.)

- **`executor_observation` no longer reads `true` while the Calculator is unwired.** The
  field used to emit `"executor_observation": true` alongside
  `real_calculator_wired: false`, which a reader reaching for the bare boolean interprets
  as "executor was actually observed." Renamed the persisted log value to
  `"executor_observation": false` plus an explicit `executor_truth_available: false`, so the
  unavailable-truth state is self-describing. Verified on both `logs/arm3.jsonl` and
  `logs/arm4.jsonl`. The grading code at `summarize_all` already keys on
  `real_calculator_wired`, so this only fixes the human-facing label. Same trap on E
  (cache-reuse half) and I (saved-work estimate) — flagged once at the unified
  `H/E/I_证据结构一致性` field.

- **Two different exit-statuses, one log line.** arm-3 exits 0 as a whole run; but
  each arm also has its own "did this unit/execute-demand actually execute" outcome,
  and the overall acceptance verdict (any `NOT VERIFIED` → non-zero gate) is a
  **separate** status. The current `execute-demand` / `recompute-after-invalidation`
  lines conflate them. The handoff says to distinguish "arm executed successfully"
  from "acceptance gate returned non-zero on NOT_VERIFIED condition." Use two fields
  — e.g. `arm_exit_status` vs `acceptance_gate: PASS|PASS-部分|NOT VERIFIED|FAIL`.
  Currently both read as success-ish (`state: ADVANCED`, `advanced: true`, exit 0),
  which makes a NOT-VERIFIED criterion invisible in the log tail. Worth fixing so a
  future reader can see that H's executor half is open from the artifact itself.

- **E and I carry the identical proxy-only structure** (cache presence = "compute
  reuse / saved work inferred"). The H restructuring reason applies to them too. If H
  is accepted as PASS-部分 on proxy-only grounds, be consistent: E's compute-reuse half
  and I's saved-work estimate are proxy-only for the same reason. The memo should say
  this explicitly rather than H being PASS-部分 while E/I slip past as if cleaner. I
  don't want the same uncertainty down-ranked differently across criteria.

- **`execute-demand-note` appears in arm1/arm2/arm3 as a ValueError** — this is a
  documented workaround (expect-and-fine, see L2h), but the reviewer sees it as noise
  in every arm log. Keep, just label `err` with the doc ref so it reads as expected
  not as a runtime fault.

---

## The non-negotiable for the reviewer — Swift side, B0

This whole result is proven at the **carrier-semantic** layer. Nothing here
independently verifies that a *real* deterministic executor obeys the dependency
invalidation for a graph, still less a real LLM's continuous inference. The prior
review flagged this (A = PASS-部分, Swift-runtime boundary simulated not observed).
B0 — re-run arm-3 with Swift's real `Calculator` wired, per-unit REUSE/COMPUTE
carrier-loop.py:685-686 — is the gate that turns "expected set matches proxy" into
"independent executor truth." Not done, not claimed done. Until B0 runs H cannot pass
the full threshold; acceptance at "本次模型级连续计算验证成功" (plan §5 core gate)
requires A–H all PASS **and** I with credible work-save evidence. Currently H is
PASS-部分, so the core gate is not met. Correctly placed: this is stage-completion of
the **proxy-layer** restructuring, not a research-claim closure.
