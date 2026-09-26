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
bound-prefix length reported at that position.

## 2. Who owns it

The ExecutionStateBackend (the physical representation owner) — the
ledger is the token-level view of the representation history. The
Coordinator owns positions; the Backend owns prefixes; the LEDGER is
their join record, owned by the Backend, appended only by the commit
path (physical rebind + logical advance both succeeded).

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
