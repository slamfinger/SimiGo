---
name: sr-g1-p2-HARNESS_NAMEERROR_UNBOUNDLOCAL_20261019
description: P2 Swift proxy + P1 arm-5 harness have real defects (NameError in _advance_to_applied; selftest.py UnboundLocal) that weaken reuse evidence
metadata:
  type: project
---

2026-10-19 audit of `execution-information-loop/experiment/continuous-calc-verification/model-level-validation/` found TWO real defects in the harness that DON'T change the P2/P3 verdicts (swift_proxy stays PASS-部分 / executor-integration+settlement-reuse+selective-recompute, not real-model computation) but DO mean arm-5's reuse evidence was never proven through a clean PENDING_SWIFT→APPLIED boundary flip.

## Defect 1 — P1_selftest.py NameError in _advance_to_applied (line 134)
`_advance_to_applied(loop, db, cp, demand_id, adv_id)` at P1:132-138 calls `loop.execute_demand(demand_id, adv_id, calc, ...)` but no `calc` exists at module scope. The ONLY `def calc` in P1 is nested inside `run_arm_5_request_reuse` (line 188), which P1 does NOT enclose. Free-variable lookup finds nothing → `NameError: name 'calc' is not defined` at P1:134.

Evidence — arm5.jsonl lines 8 & 18 carry exactly this `execute-demand-note` (arm=5, unit=all). Both P1 `_advance_to_applied` call sites (main line 199 settle-once, line 269 rerequest) fire it; the try/except at P1:139 catches+logs, so arm-5 exits 0 with `p1_passed: true` despite the advance never completing.

Consequence for arm-5 specifically: settle-once populated A–E settlements (append_order 6–10 in `.carrier-arm5.sqlite`) via line 193's `execute_demand` (correct nested-calc scope) — BUT `_advance_to_applied`'s runtime-application confirmation never succeeded, so arm-5's "reuse" is proven by settle-once + counterfactual probes (lines 193-214), NEVER by a clean re-request-after-runtime-application. Arm-5 reuse evidence is the weakest in the suite; arm2/arm3's path (`ValueError: pending runtime application requires confirmation`) is the one that actually exercised the boundary and is trustworthy.

Note: arm4 does NOT call `_advance_to_applied` at all; its 2 `execute-demand-note` rows are pre-existing arm-2 noise ("unknown demand: doc-workflow-analysis") carried in logs/arm4.jsonl. `run_arm_4_diamond` settles the diamond directly via its own nested calc — no module-scope `calc` bug there. swift_proxy.py has the same `_advance_to_applied` pattern but DEFINES `calc` locally inside it (line 129) so swift_proxy has no NameError.

## Defect 2 — selftest.py UnboundLocalError (lines 896-897)
`h_carrier`/`h_executor` are assigned ONLY inside the `if arm3 and arm3.get("evidence"):` guard (guard starts at selftest.py:862) but referenced OUTSIDE that guard at lines 896-897 for `h_overall` computation. When an arm has no evidence dict, they're undefined → UnboundLocalError. Running `python3 selftest.py --arm 3` returns exit=1 (criterion FAIL/BLOCKED). This is an honest gate failing loudly; other arms exit 0 via the same guard-dependent logic.

## Trust ranking (empirical, from log+DB evidence)
- arm2/arm3: SETTLED states real, reuse path exercised through carrier (PENDING→confirmation boundary hit). Trustworthy-ish.
- arm4: settle-set proved via DB (A/B/C/D settled v2, E unchanged) but executor NOT_VERIFIED; no `_advance_to_applied` exercised.
- arm5: least trustworthy — NameError swallowed, runtime-application never confirmed via `_advance_to_applied`.

## Fix (not yet applied — left for owner)
- P1: define `calc` inside `_advance_to_applied` (mirroring swift_proxy.py:129) so the advance-attempt carries its own real-calc closure, OR pass calc as a param. Then re-run arm-5 and confirm the two NameError rows become `runtime-application` confirmation success OR a clean PENDING→APPLIED transition.
- selftest.py: move `h_carrier`/`h_executor` init before the guard (default "NOT VERIFIED") so `h_overall` always has both bound.

## Related
[[execution-information-loop-verification-20261016]] · [[small-scale-is-the-foundation]] · G1≠G2 boundary (model-level continuous computation stays NOT VERIFIED in every arm-done event, preserved verbatim).
