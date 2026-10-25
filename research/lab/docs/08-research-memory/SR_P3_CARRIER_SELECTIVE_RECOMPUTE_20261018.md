# P3 Carrier Selective-Recompute — Evidence-Closure Record

> **Review ID:** `REVIEW-SR-P3-20261018`
> **Date:** 2026-10-18 (Asia/Shanghai)
> **Nature:** READ-ONLY evaluation conclusion of the P3 selective-recompute experiment re-run 2026-10-18.
> Coordinates the three observation-set separation (`expected_invalidation_set` / `observed_invalidation_set` / `observed_call_set`)
> and closes the Arm-1/Arm-4 proxy evidence against independently-derived expected sets. Does NOT change code, rerun
> experiments, modify Frozen Contracts, commit, or push.

**Source artifacts (unchanged, verified on disk):**
- `execution-information-loop/experiment/continuous-calc-verification/model-level-validation/P3_recompute_sets.py`
- `execution-information-loop/experiment/continuous-calc-verification/model-level-validation/logs/p3-arm1.jsonl`, `p3-arm2.jsonl` (arm-3 chain), `p3-arm3.jsonl` (arm-4 diamond)
- `.carrier-p3-arm{1,2,3}.sqlite` settle-state records

---

## 1. Objective closure status (what the 2026-10-18 objective asked to accept)

| Objective claim | Evidence on disk | Verdict |
|---|---|---|
| Arm 1: no recompute on unchanged source | `p3-arm1.jsonl`: all 3 `swift-forward` rows precede `p3-rerequest-arm1`; zero new forwards after marker | **Supported** |
| Arm 4: E not in invalidation set | `p3-arm3.jsonl` rows 14-17 = {A,B,C,D} only; E absent from re-run window; E settle DB record has v1 only (no rev-2) | **Supported** |
| Three sets kept strictly separate | `P3_recompute_sets.py` `_match_arm`: expected/invalidation/call stored as three distinct fields, merged only in `overall` | **Supported** |
| Proxy forward is independent witness of actual call | `_swift_forward_units_this_run` parses swift-forward rows after last invalidate/rerequest marker; not the carrier's own dict | **Supported** |
| P3 OVERALL PASS (proxy layer) | `python3 P3_recompute_sets.py` → arm1/arm3/arm4 all `overall=True`; "P3 OVERALL: PASS" | **Verified** |

## 2. The decisive E reuse proof (no-over-propagation)

Proven from two **independent** signals that agree, not one:

1. **DB settle record** (`.carrier-p3-arm3.sqlite` `is_objects`): `E` has exactly one settle row, version **v1**, never a v2. A, B, C, D each have v1 **and** v2 (re-settled). E's settle digest is unchanged across the arm-4 run ⇒ never invalidated.
2. **Proxy call witness** (`p3-arm3.jsonl`): after the `p3-invalidate-arm4` marker, `swift-forward` rows are exactly {A, B, C, D}. The proxy iterates *all* settle-affected units (so E can appear in `observed_call`), but E has **no** re-settle row ⇒ E was reused, not recomputed.

Either signal alone is insufficient (empty `computed_item_ids` on a pure recompute by design, per carrier loop.py:685-686); the DB settle record resolves which half is observable. Both point to **E reused**.

## 3. H reclassification — unchanged at PASS-部分, but note the direction of change

The 2026-10-18 `results.md` already rated **H = PASS-部分** (carrier-supportive + executor uninstrumented). The 2026-10-18 P3 experiment does **not** re-derive H from scratch or downgrade it:

- It upgrades `H_Carrier` by proving selective-recompute matches the graph-derived set for **both** propagation directions — linear chain (arm-3) and diamond + unrelated sibling (arm-4), the latter the non-linear case that was previously a stated blocker.
- `H_Executor` stays **NOT VERIFIED** (no real Swift `Calculator` wired; proxy forward is a deterministic stub, not the executable executor).
- Net: `results.md` "H = PASS-部分" is preserved; the change is in the **evidence structure** (three-set separation over reading empty carrier arrays as a recompute set), not in the verdict. This is why H does **not** get "re-adjudicated" — it was already at this level.

## 4. Persistent caveats (unchanged from 2026-10-17, carried forward)

- Proxy-layer PASS on a deterministic `swift_forward` stub — proves executor-integration + settlement-reuse + selective-recompute **pattern**, not model-level continuous computation.
- `carrier reuse != LLM_inference / KV_cache hit`: cache-precision is observed via proxy, not a true model-work measurement.
- Real Swift `Calculator` integration through the Python carrier is still unverified — this record's boundary statement stands.

## 5. State note

Artifacts under `execution-information-loop/experiment/` and this review file are **untracked** (`git status ??`) as of 2026-10-18. Per instruction: Frozen Contracts untouched, no commit, no push — evidence kept in the working tree for downstream Swift-bridge round.

---

## 6. Coexistence coordinate (G1/G2 formalization)

This record coexists with `SR_P3_G1G2_BOUNDARY_FORMALIZATION_20261018`, the authority for: L1
(logical isolation, v1 design only) vs L2 (actual KV cache unreachable, NOT_OBSERVED);
**G1 ⇒ G2 guarded dependency**; `NOT_VERIFIED` boundary line (Swift no-new-forwards supports
L1-pattern only, silent on cache isolation; proxy self-validation risk); `not_computed_item_ids` /
`no_cache_penalty` are Carrier/proxy-layer evidence, cannot be sole L2 witness. This record's
proxy-layer verdicts unchanged; boundary semantics live in the addendum.
