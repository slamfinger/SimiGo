# SimiGo-Lab — Token Ledger Gate Definition (Model First, No Code) — 2026-09-26

Status: TOKEN_LEDGER_GATE_DEFINITION / AWAITING_REVIEW
Predecessor ruling: GA0_FLOOR_POLICY = TARGET_DEPENDENT (floor = policy-
level pressure exemption; core = structural residency; target=0 = release
all non-core). No code in this round.

## 1. What the ledger records

Per Execution State, an append-only record of CONFIRMED token-prefix
facts, one entry per committed transition:

```text
entry = {
    executionID
    position            // == the coordinator position at commit
    kind                // bootstrap | turn
    prefixLength        // total confirmed prefix tokens AFTER this entry
    nextInputLength     // tokens consumed from the request (turn entries)
    generatedLength     // tokens produced this turn
}
```

Invariant I-L1: entries exist ONLY for committed transitions — bootstrap
(position 0) and successful turn commits. Failed turns append nothing.
Invariant I-L2: prefixLength is strictly increasing along the chain;
after a logical restore to position J, the next committed turn at J+1
continues from the entry at J (the superseded tail is retained, marked
superseded by the restore — append-only audit trail).
Invariant I-L3 (cross-check): the entry's prefixLength equals the backend
bound-prefix length reported at that position. ENFORCED at append — the
ledger consults the backend's own binding record (authority closure) for
every entry; a wrong length, a missing binding, or a binding at another
position throws divergence-class and the entry is never recorded.

## 2. Who owns it

Conceptual owner: the Execution State representation layer — the prefix
IS the physical representation; the ledger is its token-level view. The
Coordinator owns positions; the Backend owns prefixes; the LEDGER is
their join record, appended only by the commit path (physical rebind +
logical advance both succeeded).

Current implementation owner (beta): the OversizedSegmentedEngine hosts
the ledger as an engine-side representation audit structure, with the
I-L3 authority wired directly to the backend binding record. Sinking the
ledger into the ExecutionStateBackend abstraction is deferred until that
abstraction stabilizes — this keeps the beta implementation honest about
where the code lives while preserving the conceptual ownership above.

## 3. Which transitions update it

```text
bootstrap (position 0)     append {kind: bootstrap, prefixLength: P0}
committed turn (N→N+1)     append {kind: turn, position: N+1,
                                   prefixLength, nextInputLen, generatedLen}
restore (to J)             NO append — a restore marker is recorded; the
                           superseded tail (J+1…) remains, marked
discard                   ledger CLOSED — no further entries; retained
```

## 4. Boundaries (what the ledger is NOT)

```text
NOT a KV cache record        no physical residency semantics
NOT a UI transcript          no text; no presentation role
NOT a usage report           usage is a PRODUCT-LAYER projection of the
                             ledger (this is what closes the beta
                             "usage = 0" gap honestly)
NOT a position source        positions come from the Coordinator; the
                             ledger ANNOTATES them with token facts
```

## 5. What it enables

```text
- oversized usage accounting: prompt_tokens / completion_tokens from
  confirmed committed prefixes (closes the beta known limitation)
- position ↔ token auditability: prefix drift between the logical chain
  and the physical prefix becomes detectable (I-L3 cross-check)
- reconciliation gains a token dimension: INV-3 detects resident-byte
  drift; the ledger detects prefix-length drift
```

## 6. Implementation order (after review)

1. Backend-side append-only ledger with the three invariants.
2. Turn commit appends one entry (inside the atomic section, after the
   logical advance — in-memory, infallible).
3. Engine/uptime accessors: promptTokens / completionTokens projection
   into GenerationUsageReport (closes the beta usage=0 limitation).
4. Restore marker on logical restore.
5. Regression: 89+ tests + E2E (usage now non-zero; determinism
   unchanged).

## 7. Deliberately deferred

- Segment KV (physical residency granularity) — deferred per review.
- Cancellation token pipeline — DONE (Step 1).
- Floor structural-immunity option — rejected (GA-0 ruling: floor is a
  pressure policy parameter, not structural immunity).

---

Review disposition requested: approve the ledger model (scope/ownership/
transition set/boundaries/invariants) — implementation follows in the
next round.

---

## Amendment — 2026-09-27 — I-L3 enforcement + ownership wording

Registered from the code-level audit at e29fce7 (no code changed during
the audit). Two findings dispositioned:

1. **I-L3 was cross-referenced, not cross-checked.** The original
   wording ("equals the backend bound-prefix length reported at that
   position") was satisfied only on the happy path: `append()` checked
   position ordering but never `prefixLength`, and the restore marker's
   value was derived from the ledger's own entries (self-referential).
   The invariant is now ENFORCED: the ledger is constructed with a
   required authority closure over the backend binding record
   (`OversizedSegmentedStateBackend.boundPrefixLength(
   executionID:position:)` — no-binding and position-mismatch guards
   included); every append of every kind cross-checks against it and
   throws divergence-class on mismatch, recording nothing. The restore
   marker's prefixLength is now derived from the backend's re-bound
   representation (coordinator.restore re-binds the historical prefix
   before returning), not from ledger entries; the ledger-self-derived
   helper is deleted. Unit battery: 4 deliberate-mismatch cases
   (value mismatch / missing binding / position drift / marker
   mismatch) — 96 → 100, all green.

2. **Ownership wording unified.** The definition claimed the
   ExecutionStateBackend owns the ledger; the code had it engine-side.
   §2 now states both layers (conceptual owner: Execution State
   representation layer; current implementation owner:
   OversizedSegmentedEngine, engine-side audit structure with the I-L3
   authority wired to the backend record). No ownership migration now —
   sinking the ledger into the backend abstraction stays deferred until
   that abstraction stabilizes.

Also registered (P2, defensive consistency gap, no redesign): the
restore sequence still has a theoretical post-commit window
(restore committed → markSuperseded → marker append throws). With the
I-L3 authority in place the marker append fails only under genuine
backend/ledger divergence — which is exactly the loud failure the gate
wants; the superseded flags are idempotent under retry.
