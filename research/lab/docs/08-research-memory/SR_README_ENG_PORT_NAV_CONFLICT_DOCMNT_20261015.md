# README E4/E5 Navigation Conflict — Documentation Maintenance Item

> **Doc ID:** `DOCMNT-ENGPOR-NAVCONFLICT-20261015`
> **Date:** 2026-10-15 (Asia/Shanghai)
> **Repository HEAD:** `1f80d50e` (main)
> **Nature:** DOCUMENTATION MAINTENANCE ONLY. Does NOT change a research gate, close E4, extend authorization, or modify any contract or code. Reads authoritative state from `docs/RESEARCH_STATE.md`; it does not override it.
> **Relationship:** Parallel to (and deliberately separate from) the read-only audit `SR_AUTHORIZATION_STATE_AUDIT_20261015.md`. Documentation maintenance is not a research-gate change.

---

## 1. The Conflict (as found in `main`)

| Location | Current text |
|---|---|
| `README.md` line 70 | `- **E4 — Continuity + Residency Integration：NEXT` |
| `README.md` line 71 | `- **E5 — End-to-End Execution State scenario：未开始` |
| `docs/RESEARCH_STATE.md` line 5412 | `E4 / E5 : NOT STARTED` (older snapshot stratum) |
| `docs/RESEARCH_STATE.md` line 5415–5445 | `### E4 Continuity + Residency Integration — Verified — 2026-09-25` |

**Conflict:** Root README marks E4 `NEXT` and E5 `未开始`. Authoritative state file documents E4 as **VERIFIED (2026-09-25, 87/87 XCTest PASS)** under the composed ExecutionContinuityCoordinator + MLXExecutionStateBackend × ResidencyController + mock-materializer cycle.

---

## 2. Authoritative Record of E4 (per `RESEARCH_STATE.md`)

- Gate status: `E4 → VERIFIED`.
- Cycle verified: Create → Generate → Resident → Evict (to core floor AND release of live representation) → Re-materialize → Restore from pre-eviction checkpoint → Reattach → Continue.
- Identity / Lineage unchanged; Position / Continuation preserved; Representation and Residency changed (record systems verified independent; residency INV-1 holds at every step).
- Suite: **87/87 XCTest PASS** (106 test cases incl. the contract target).
- Registered next-gate at verification time was **E5** — not a restart of E4.

---

## 3. Three Things to Separate (do NOT conflate)

1. **E4 was previously gated VERIFIED** — a real integration gate that existed and passed, using the mock materializer.
2. **Its evidence is a *mock* residency simulation** — it does NOT prove the real MLX eviction / reload full chain has been proven end to end.
3. **README still marks `E4 NEXT / E5 未开始`** — an outdated navigation record that conflicts with the authoritative state file.

Therefore:
- E4's mock residency evidence must NOT be upgraded to "real MLX eviction/reload full chain proven."
- E4 should NOT be re-opened on this alone.
- The README navigation is stale and should be corrected as documentation maintenance, NOT as a research-gate change.

---

## 4. Do It In TWO Steps (per user directive)

- **Step A — Read-only audit** (`SR_AUTHORIZATION_STATE_AUDIT_20261015.md`): separates authorization changes-over-time from current state, bounded results from open claims, consumed budget from forbidden auto-extension. This audit is NOT a research conclusion and does NOT start a new fix cycle.
- **Step B — This documentation-maintenance item** (this file): corrects the README E4/E5 navigation conflict and flags the `NOT STARTED` residual in `RESEARCH_STATE.md`. It is documentation maintenance, not a research-gate change.

---

## 5. Recommended Documentation Corrections (do NOT execute now — flag only)

1. Root `README.md`: restate E4 status as VERIFIED (2026-09-25, mock-materializer cycle; 87/87 PASS) with a caveat that the *real* MLX full-chain is not proven; restate E5 `未开始` as-is but note it was the registered next-gate, not a re-start of E4.
2. `RESEARCH_STATE.md` line 5412: flag the older `E4 / E5 : NOT STARTED` stratum as a superseded snapshot that must be reconciled — documentation maintenance should mark BOTH the README AND this internal residual, so it is not mistaken for current state.
3. Add a one-line provenance anchor: "E4 VERIFIED 2026-09-25 is documentation state; its mock-materializer evidence does not establish the real MLX eviction/reload full chain."

---

## 6. Guardrails (this maintenance item does NOT)

- Not a research-gate change; E4 remains VERIFIED as previously recorded, with the mock-evidence caveat explicit.
- Not a new authorization; E5 scenario remains `未开始` (new budget/records required).
- No contract, no code, no test modified by this item.
- Evidence boundary preserved: existing E4 evidence = mock-materializer integration cycle; real full-chain remains unproven.
