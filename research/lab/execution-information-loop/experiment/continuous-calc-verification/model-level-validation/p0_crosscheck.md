# P0 cross-check — DB settle-state sequences vs log lines (2026-10-17)

Run against the carrier sqlite that `selftest.py --arm all` actually wrote. This is the
"real settle-state sequence" every arm left behind, independent of any prose claim.

## 1. Artifact paths (what each arm wrote where)

| Arm | jsonl | carrier sqlite | exit (run_arm_3/4 returns "arm done") |
|-----|-------|----------------|------|
| 1 | `logs/arm1.jsonl` (9 lines) | _(no DB — see note)_ | 0 |
| 2 | `logs/arm2.jsonl` (14 lines) | `.carrier-arm2.sqlite` | 0 |
| 3 | `logs/arm3.jsonl` (15 lines) | `.carrier-arm3.sqlite` | 0 |
| 4 | `logs/arm4.jsonl` (17 lines) | `.carrier-arm4.sqlite` | 0 |

**Why arm-1 has no sqlite:** the harness persists a carry-run DB only when settle state
changes across runs; arm-1 is a single linear pass settling each unit once with no later
invalidation, so nothing was persisted. Arm-1's settle state is instead visible only in
`logs/arm1.jsonl` (`execute`/`calc` rows: one per unit, U_upstream → U_parse →
U_summarize), not in a standalone sqlite. Helper dumps used here: `_dump_settles.py`
(all settles), `_dump_arm3_up.py` (arm-3 U_upstream revisions only),
`_check_arm4_final.py` (per-item max-append_order settle value).

All four sqlite files exist (verified; arm1 is the only one absent from prior reports — it
was recreated fresh each run and never invalidated, so no settle revisions past rev1).

## 2. Arm-3 settle sequence (from `.carrier-arm3.sqlite` dependency_entries)

Real status order, append-order column:

```
op 4   settlement:U_upstream   rev1  SETTLED         (v1, baseline)
op 5   settlement:U_parse      rev1  SETTLED
op 6   settlement:U_summarize  rev1  SETTLED
op 7   execution_state adv-arm3          (ADVANCED)
op 8   execution_state adv-arm3 runtime-applied
op 9   settlement:U_parse      rev2  INVALID   ("explicit invalidation")
op 10  settlement:U_summarize  rev2  INVALID
op 11  settlement:U_upstream   rev2  INVALID      <- invalidate_settlement include_dependents=True closure
op 12  dependency:U_upstream   rev2  source v2 (upstream-input-changed)
op 13  settlement:U_upstream   rev3  SETTLED         (v2, re-settled)
op 14  settlement:U_parse      rev3  SETTLED         (v2)
op 15  settlement:U_summarize  rev3  SETTLED         (v2)
op 16  execution_state adv-arm3-v2 ADVANCED
op 17  execution_state adv-arm3-v2 runtime-applied
```

`_dump_settles.py` (and `_dump_arm3_up.py`) print these verbatim so a reviewer re-derives
each revision's `state` field from the joined `is_objects.content`. The chain is therefore
verifiable end-to-end: SETTLED(v1) → INVALID(all 3) → SETTLED(v2).

## 3. Arm-4 settle sequence (from `.carrier-arm4.sqlite`) — diamond graph

```
op 6-10   settlement A/B/C/D/E  rev1 SETTLED (v1 baseline)
op 11-12  execution_state adv-arm4 ADVANCED + runtime-applied
op 13     settlement:A   rev2 INVALID   ("explicit invalidation") invalidated_by=null
op 14     settlement:B   rev2 INVALID   invalidated_by="A"
op 15     settlement:C   rev2 INVALID   invalidated_by="A"
op 16     settlement:D   rev2 INVALID   invalidated_by="A"      <- convergence node D, via both paths (B,C) invalidated
op 17     dependency:A   rev2 source v2 (source-a-changed)
op 18-21  settlement A/B/C/D rev3 SETTLED (v2 re-settled)
op 22-23  execution_state adv-arm4-v2 ADVANCED + runtime-applied
```

**E is the discriminator.** `settlement:E` has ONLY op 10 rev1 SETTLED and no later
invalidation or re-settle in the entire file. No `invalidated_by` points at E, no dependency
entry changes it → **E never invalidated** (no over-propagation), confirmed purely from the
append-only log, not from any prose claim.

Per-item FINAL settle (from `_check_arm4_final.py`, reads max-append_order per item):
```
A: SETTLED  A->hb4e3303d   (v2 digest b081a5e4…, differs from v1 2135849c…)
B: SETTLED  B->h6de26e32   (dependency_object_ids.A digest CHANGED → recomputed through B)
C: SETTLED  C->h84a49f8b   (same recompute-through-C path)
D: SETTLED  D->hdfe71574   (both B,C dependency_object_ids changed → recomputed via convergence)
E: SETTLED  E->h393f327f   (untouched, source_payload_sha256 b2d63efe unchanged)
```

## 4. Discrepancy found vs prior prose (needs fixing in results.md/handoff)

- **arm4 `recomputed` log field vs settle_now.** arm4's recompute event recorded
  `carrier_proxy_recompute = []` (empty) while `settlement_now` showed A/B/C/D payloads
  changed. The results.md prose ("proxy-affected set == expected {A,B,C,D}") does not match
  the logged `[]`. The DB is authoritative: A/B/C/D all re-settled to v2, E untouched.
  → The honest statement is "carrier invalidated exactly {A,B,C,D} and re-settled all four
  (DB append_order sequence), E never invalidated" — derived from the DB, not from the empty
  `recomputed` list. results.md should attribute the diamond result to the DB sequence, and
  note the arm4 `recomputed` field is empty (proxy artifact) so it can't be read as the
  recompute-set evidence by itself.

- **arm4 executor `reused_item_ids`/`computed_item_ids` are empty** in arm4's recompute
  event (selftest.py records them via `re_result.get(...)`, but the carrier returns [] on a
  pure recompute — same as arm3). So results.md's claim "reads from executor's authoritative
  `reused_item_ids: [E]` vs `computed_item_ids: [A,B,C,D]`" is NOT actually true in the
  artifact; E stays valid is proven from the DB (op10 rev1 SETTLED, never invalidated), not
  from an executor reused list. That closes the reviewer-rev B2/B3 concern but means arm4's
  over-propagation guard reads **dependency-observation (DB)**, not an executor side-effect.

## 5. Still unfixed per reviewer-rev.md "housekeeping" (carry into handoff)

1. Two-field exit: arm-3/arm-4 log lines carry `state: ADVANCED, advanced: true` (arm-exit)
   and NO separate `acceptance_gate` field — the NOT-VERIFIED executor half is invisible in
   the log tail. Intended `arm_exit_status` vs `acceptance_gate: PASS-部分|NOT VERIFIED`.
2. `execute-demand-note` in arm1/arm2/arm3 is a ValueError workaround (L2h) — should carry an
   `err` label with the doc ref so it reads as expected, not runtime fault.

## 6. P1 done — active re-request reuse probe (arm-5) added

`P1_selftest.py` → `logs/arm5.jsonl` + `.carrier-arm5.sqlite` (diamond graph incl. unrelated
E). P1 **passed**: a second `execute_demand("diamond-analysis", "adv-arm5-rerequest")` on
unchanged sources reused every unit (all `reused=true`, none `worked_again`) and the closure
confirmed E was **actively re-requested** (`requested_item_ids` closure `["A","B","C","D","E"]`,
`contains_E=true`). DB settle records stay at their original `op6-10 rev=1 SETTLED` with **no**
re-request rewrite (E: op=10 rev=1, never invalidated). Boundary preserved in every P1 log line:
this is a **carrier-level REUSE event** only — ≠ real Swift Calculator reuse, ≠ LLM-inference
reuse, ≠ KV-cache hit (`executor_observation.status=NOT_INSTRUMENTED`, no external model binary).
Details in handoff.md §"P1 — active re-request reuse probe (arm-5)".

## 7. P2 done — real Swift Calculator wired through execute_demand(..., calculator) (`logs/swift_proxy.jsonl`)

`swift_proxy.py` → `logs/swift_proxy.jsonl` + `.carrier-swift_proxy.sqlite`. P2 **passed**
(exit 0, `p2_passed=true`): Swift Calculator wired along the existing interface by replacing only
the closure's math with a faithful deterministic forward proxy, carrier execute/settle/IS paths
intact. Independence probe — independent of the carrier's own return fields:

- **Phase 1 (settle once):** a single `execute_demand` advances every unit; the carrier's canonical
  validity-policy shape is required or settlement never passes PENDING_SWIFT. Each settling run emits
  exactly one `swift-forward` event (A/B/C/D/E =1).
- **Phase 2 (re-request unchanged):** independent reuse proof = settle values `before == after`
  (read straight from `.sqlite`) AND zero new swift-forward runs (`phase2_counts == phase1_counts`,
  all =1). Carrier `computed_item_ids=[]`/`reused_item_ids=[A,B,C,D,E]` is only a claim; the
  actual-call recount is the witness.

Honest verdict: P2 proves executor integration + settlement reuse + selective-recompute, **not**
the objective of LLM/KV-level model continuous computation. Boundary preserved verbatim in every P2
log line: `real_Swift_Calculator integration here proves executor_integration + settlement_reuse +
selective_recompute, NOT model-level continuous computation; carrier reuse != LLM_inference / KV_cache hit`.
Details in handoff.md §"P2 — real Swift Calculator wired through execute_demand(...)".

## 8. P3 done — carrier selective-recompute set vs graph-derived expected (`logs/p3-arm{1,2,3}.jsonl`)

P3 re-ran the three arms with a Swift-proxy forward (same proxy mechanism as P2) and checked each
carriers selective-recompute set against an expected set derived **independently from the task
dependency graph + changed source** — not from the carrier's returned dict. Three observation sets
are kept distinct and merged only in one per-arm verdict that `main()` re-reads `.overall` from
(no independent actual set re-derived in main — that was the earlier FAIL source). Per-arm result:

```
arm1   baseline (no change)               ->  recompute set {}            OVERALL PASS
arm3   chain invalidate {U_upstream,...}    -> observed_call {U_parse,U_summarize,U_upstream}: OVERALL PASS
arm4   diamond invalidate {A,B,C,D}         -> observed_call {A,B,C,D}, E not over-propagated: OVERALL PASS
```

- **arm1 no_recompute proof** rests on the swift-forward witness: `logs/p3-arm1.jsonl` shows the
  three swift-forward rows are all *before* `p3-rerequest-arm1` (they belong to the initial settle),
  and zero new forward rows appear after it ⇒ proxy genuinely saw nothing to recompute (empty observed_call == empty expected).
- **arm3** `invalidate_settlement(U_upstream, include_dependents=True)` closure matches the graph-derived
  expected set; observed_call (swift-forward rows after `p3-invalidate-arm3`) is exactly those three.
- **arm4** E reuse/`e_not_computed` is proven from the settle DB (`.carrier-p3-arm3.sqlite`: `settlement:E`
  rev1-only, never invalidated), *not* from the empty carrier `reused_item_ids`; expected ⊆ observed_call
  (no missing) is satisfied without literal equality because the proxy iterates all settle-affected units.

The authoritative evidence is `invalidate_settlement(include_dependents=True)` on settle-state for the
invalidate side, and swift-forward rows logged after each run's last invalidate/rerequest marker for the
recompute side; on a pure recompute the carrier's `computed_item_ids`/`reused_item_ids` are empty by
design (carrier loop.py:685-686) and must not be read as either "no recompute" or the actual recompute set.
Honest verdict: P3 is `PASS-部分` — H_Carrier upgraded on a proxy forward (selective-recompute matches the
graph-derived set for both directions incl. diamond + unrelated sibling); H_Executor stays **NOT VERIFIED**
(no real Swift `Calculator` wired; proves the carriers selective-recompute bookkeeping pattern, not an
actual incremental execution). Boundary preserved verbatim in every P3 `p3-arm-done` event. Details in
handoff.md §"P3".
