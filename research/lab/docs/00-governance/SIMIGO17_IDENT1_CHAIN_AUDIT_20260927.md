# IDENT-1 Chain Audit — ExecutionID → Handle → Key → storageKey → Representation

**Date**: 2026-09-27 · **Status**: CHAIN AUDIT ROUND 1 COMPLETE / IDENT-1 OPEN
**Method**: per the ruling — walk every arrow, ask three questions
(type exists? mapping exists? does runtime addressing actually use it?),
hunt 同名不同义 and 身份存在但寻址不用.

---

## Arrow 1 — External Execution Identity → Canonical ExecutionID

| | product | Lab contract |
|---|---|---|
| type | `ExecutionControlling.ExecutionID` (triple: agentId?/sessionId/branch) | `RuntimeContract.ExecutionID` (opaque `String`, Hashable) |
| mapping from external | HTTP identity → **`AgentExecutionKey.resolve`** — NOT through ExecutionID | oversized engine: literal `ExecutionID("S")` — NOT from the request |
| runtime addressing use | **ZERO** — the S4 protocol surface has **no conformer** (grep: only the defining file references `ExecutionControlling`); generate() addresses via AgentExecutionKey directly | oversized sessions only; identity is the CONSTANT `"S"` (OversizedSegmentedEngine:818) — request identity never enters the strict-ES layer |

**F1（同名不同义，确认）**: two `ExecutionID` types — a triple-mapping
protocol identity (product) vs an opaque contract identity (Lab).
Different semantics, different instance spaces. Cannot merge; a canonical
choice is a design ruling, not a rename.

**F2（身份存在但寻址不用，教科书案例）**: the product's S4 surface maps
checkpoint/restore/fork through `ExecutionID`, but **no type conforms to
the protocol and no conversion `ExecutionID → AgentExecutionKey` exists**.
Its own doc says identity is "AgentExecutionKey 三元组的直映射" — the
mapping is declared, not implemented. The product calls
`saveSessionCache`/`forkSessionBranch` with `AgentExecutionKey` directly.

**F4（身份孤岛）**: the two identity systems are disconnected —
daily path: `AgentExecutionKey → storageKey → ManagedSession`;
oversized path: constant `ExecutionID("S") → coordinator → handle`.
A request's identity never crosses between them.

## Arrow 2 — Canonical ExecutionID → Execution State Handle

| | product | Lab contract |
|---|---|---|
| handle type | ABSENT — the analog is `ManagedSession` (private, NativeMLX) | `ExecutionStateHandle` (id+lineage+position+continuation+lifecycle) — real binding via `ExecutionContinuityCoordinator` |
| mapping | none; the dict key is `storageKey` | coordinator-owned, per `ExecutionID` |

Handle semantics exist ONLY on the oversized path.

## Arrow 3 — Execution State Handle / identity → AgentExecutionKey

**No mapping exists in either direction.** The two systems never meet:
the coordinator is constructed inside the oversized engine, the sessions
dict lives in NativeMLX. `AgentExecutionKey.storageKey` is
`"\(agentId)/\(sessionId)/\(logicalBranchId)"` — **F3**: the sole
physical addressing unit is a STRING JOIN (33 refs in NativeMLX).
Normalization exists (trim/≤128/long→SHA256 head+tail) but components
are not delimiter-escaped: `agent "a/b" + session "x"` and
`agent "a" + session "b/x"`…-style joins are theoretically collidable
(registered hazard; single-user beta mitigates).

## Arrow 4 — identity → RepresentationRef

**ABSENT everywhere** (product, Lab, oversized). `RepresentationRef`
does not exist as a type. The binding that does exist is EPHEMERAL: a
sessions-dict entry holds a materialized KV copy; nothing records
"execution X is bound to representation R".

## Arrow 5 — RepresentationRef → Physical Representation

**Nascent, identity-free by design**: the prefix pool's
`DiskPrefixArtifact` + claims (content chain hash, namespace, token
count) IS a content-addressed representation address, deliberately
keyed WITHOUT execution identity (E-line principle: states consume
representations by content). The fork's `PromptCacheSnapshot` is the
in-memory form. What is missing is not the address — it is the BINDING
CONTRACT from executions to these addresses.

---

## Verdict

**Red line confirmed with stronger evidence**: Execution identity ≠
physical representation identity. Today:

```text
IDENTITY ISLANDS (disconnected):
  daily:     AgentExecutionKey → storageKey → ManagedSession → KV
  oversized: ExecutionID("S") → coordinator → handle → KV
DEAD SURFACE: ExecutionControlling.ExecutionID (declared, no conformer,
  no mapping implementation, zero addressing use)
MISSING: RepresentationRef + explicit verifiable binding
  (execution → representation)
PRESENT AND CLEAN: content-addressed reuse that bypasses identity
  (prefix pool) — which is WHY the missing binding has not bitten yet
```

**Recommendations (for the canonical-identity ruling, not renames):**

1. S4 surface: either implement the declared `ExecutionID →
   AgentExecutionKey` mapping + a conformer, or formally retire the dead
   protocol surface (S5 decision). Carrying declared-but-dead identity
   is worse than neither.
2. Oversized multi-session (GA): thread request identity into the engine
   (`ExecutionID` derived from `AgentExecutionKey`) — today every
   oversized session is identity `"S"`.
3. RepresentationRef = a THIRD identity kind (content-addressed), bound
   to executions by an explicit table — this is the IDENT-1/FORK-3
   convergence point, not a merger of the two ExecutionID types.
4. storageKey: keep as session-addressing, register the join-collision
   hazard; do not overload it into representation addressing.
