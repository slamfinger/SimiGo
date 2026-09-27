# Runtime Resolution Contract — Definition Draft (IDENT-1 ⑤⑥⑦)

**Date**: 2026-09-27 · **Status**: DEFINITION_DRAFT / AWAITING_REVIEW
**Question to nail first (reviewer-flagged)**: if `ExecutionID` resolves
to an active Binding but the Binding's `AgentExecutionKey` has no live
session — is the defined state `detached`, `reattachable`, or
`rematerialization required`?

---

## 1. The answer: detached is an OPERATION, not a resolution outcome

`detached` = an explicit lifecycle action taken ON an Execution
(discard/detach). It can never be the RESULT of resolution — otherwise a
process restart would silently "detach" every execution, and the three
lifecycles conflate again.

Resolution over the durable Binding yields exactly one of:

```text
resolve(ExecutionID):
  b = current active Binding        (Gate B: B-R2, ≤1 by B-I5)
  if none                → UNBOUND          (never-bound, or explicitly
                                             detached by operation)
  live session at b.runtimeAddress
  and b.ref materialized in it
                         → ATTACHED_LIVE    (same-session reuse path)
  b.ref artifact available
  (pool / checkpoint)
                         → REATTACHABLE     (load = materialize:
                                             today's poolBind / restore)
  artifact evicted/missing
                         → REMATERIALIZATION_REQUIRED
                                            (recompute from execution
                                             history; Binding stays
                                             active; nothing lost
                                             semantically)
```

`detached` is therefore an ENTRY CONDITION (unbound) reached only by an
explicit operation — never a resolution branch.

## 2. Mapping to what already runs (this contract formalizes, not changes)

```text
ATTACHED_LIVE              = today's same-session reuse (cacheEff=1.00)
REATTACHABLE → load        = today's poolBind / cacheLoad / rollforward
REMATERIALIZATION_REQUIRED = today's cold path (mode=cold) — and, per
                             B-I6, the Binding SURVIVES with the
                             rematerialization obligation; LRU eviction
                             never mutates these states, only artifact
                             availability (P2 rule)
```

## 3. Invariants

```text
RR-I1  resolution is total: every (ExecutionID, time) resolves to
       exactly one of {UNBOUND, ATTACHED_LIVE, REATTACHABLE,
       REMATERIALIZATION_REQUIRED}
RR-I2  resolution is read-only: it never mutates Binding, Ref, artifact,
       or session state (materialization is a separate DECISION)
RR-I3  state changes have contract owners: ATTACHED_LIVE→REATTACHABLE
       only by process exit/eviction of the live session (lifecycle
       event); REATTACHABLE→REMATERIALIZATION_REQUIRED only by artifact
       eviction (P2 onEvict); UNBOUND→bound only by an explicit
       materialize/bind operation
RR-I4  REMATERIALIZATION_REQUIRED does not invalidate the Execution —
       history defines what must be recomputed (identity ≠ representation)
```

## 4. Open for Gate C

With this state machine pinned, runtime resolution (⑤⑥⑦) can be
specified without conflating the three lifecycles. Remaining: who OWNERS
the resolve call (product runtime vs coordinator), and where the
resolution table lives (Binding Registry, Gate C — still separated from
PrefixPool).
