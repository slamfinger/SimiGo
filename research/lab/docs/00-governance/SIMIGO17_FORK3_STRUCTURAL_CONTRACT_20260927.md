# FORK-3 Structural Contract — Shared-Representation Fork — Definition Draft

**Date**: 2026-09-27 · **Status**: PASSED (reviewer: four non-blocking
refinements applied — §8; this document is FINAL for FORK-3)

---

## 1. The proof object

```text
Parent Execution
    │
    └─ Binding ──→ Ref X @ T          (boundPositionAtBind == X.boundLength == T)
                      │
                     fork
                      │
          ┌───────────┴───────────┐
          ↓                       ↓
 Parent Execution          Child Execution
     Position T             Position T
          │                       │
       ΔP...                    ΔC...
          │                       │
          └── shared Ref X ──────┘
```

To prove: **two Executions share the SAME RepresentationRef (X @ T)
while holding INDEPENDENT Execution Positions and independent
subsequent deltas.** The proof object is NOT a replacement of
`forkSessionBranch()` — it is the semantics a conforming fork must
satisfy.

## 2. Fork operation semantics (structural)

```text
precondition   Parent E_p holds an ACTIVE Binding → Ref X @ T
operation      fork(E_p) creates Child E_c:
                 new canonical ExecutionID (never E_p's; identity
                 separation — sharing lives ONLY in the Ref layer)
                 new runtimeAddress (AgentExecutionKey; B-R1 applies)
                 Binding → Ref X @ T  (SAME Ref, SAME boundary;
                 zero re-materialization at fork time — fork cost
                 ≈ O(binding metadata))
post           E_p position = T, resumes with ΔP
               E_c position = T, continues with ΔC
               ΔP and ΔC are fully independent; each future turn
               export creates NEW Refs (X remains the shared ancestor)
```

## 3. Invariants

```text
F-I1  shared Ref ≠ shared physical materialization   Child binds
      Ref X itself — fork does NOT copy, re-serialize, or
      re-materialize the representation at fork time. Ref X is the
      common Representation identity / content-boundary FACT; Parent
      and Child's Execution State, Position, delta, and LIVE
      MATERIALIZATION remain fully independent. 「同一 Ref」绝不意味着
      两个 Session 必须持同一套 live KV —— 「语义上共享、物理上各自
      物化」是 v1 的明确约束。
F-I2  parent non-interference             fork leaves E_p's binding,
      position, lineage, and deltas bit-identical to pre-fork
F-I3  child starts at the boundary        E_c.position = T ==
      Ref X.boundLength (R-I5 holds at bind)
F-I4  delta independence (tightened)      ΔP/ΔC 的 Execution 推进完全
      独立；只有当某一分支将其推进后的 Representation 导出/形成新的
      RepresentationRef 时，才产生该分支的新 Ref（Ref P @ T' /
      Ref C @ T''，不再是共同祖先 Ref X）。**禁止规定「每次 Δ 都必须
      产生 Ref」**——否则 Representation 生命周期会反过来绑架
      Execution State。
F-I5  Fork Sharing POSTCONDITION (not a universal invariant)   after
      a SUCCESSFUL FORK-3 operation, Parent and Child active bindings
      both point to Ref X ⇒ Ref X has ≥2 active bindings at that
      moment. Normal Route B (Ref X → Execution A only, pre-fork) is
      equally legal. B-I5 (Ref → N) remains the general Binding
      contract; F-I5 is the first REALIZED N=2 instance, not a
      universal N≥2 requirement.
F-I6  identity separation                 E_c.ExecutionID ≠ E_p.ExecutionID;
      E_c.runtimeAddress ≠ E_p.runtimeAddress; sharing exists ONLY at
      the RepresentationRef layer
```

## 4. What FORK-3 deliberately does NOT claim

```text
NO live-KV COW in v1        sharing is at the SNAPSHOT/BOUNDARY level;
                            each execution materializes its own working
                            copy when it next advances
                            (copy-on-derive, compute-on-diverge).
                            Live-KV page-level COW = upstream primitive
                            (RFC mlx-swift-lm#629), explicitly deferred
NO forkSessionBranch edit   the checkpoint-copy fork stays as-is
                            (v1 semantics, FORK-1/2 gaps still
                            registered); FORK-3 lands as its own
                            binding-based mechanism, gated separately
NO silent semantic drift    「分支 checkpoint fork」and「Execution-State
                            shared-prefix fork」remain two named,
                            distinct things (terminology red line)
```

## 5. Acceptance criteria (what would prove the contract)

```text
structural battery (zero-MLX, contract level)
  fork creates child Binding → Ref X @ T (same Ref identity)
  parent non-interference (F-I2, bit-level on parent records)
  independent position advance (E_p→T+ΔP, E_c→T+ΔC)
  Ref X eviction-with-bindings → rematerialization-required for BOTH
    (Gate D constraint realized; no silent invalidation)
  binding audit trail complete and append-only
device battery
  fork at T under real load; child's next forward prefills only its
  own delta (cacheEff on the shared portion ~1.00); parent timing
  unchanged; determinism across both branches
eviction acceptance (CONDITIONAL, per reviewer)
  Parent/Child → REMATERIALIZATION_REQUIRED only when
    (a) Ref X's only available artifact is evicted/invalidated AND
    (b) that execution has no live materialization
  If artifact evicted but both hold live materializations → both stay
    ATTACHED_LIVE (Pool eviction ≠ Binding invalidation ≠ Execution
    state mutation — Gate C continuity)
  Mixed (Parent live / Child not) → Parent ATTACHED_LIVE, Child
    REMATERIALIZATION_REQUIRED
```

## 6. Gate D handoff (next gate in the ruled order)

FORK-3 makes Gate D mandatory: with Ref X under ≥2 active bindings, the
eviction/reference semantics must be pinned — pin-while-referenced vs
rematerialization-required-per-execution, contract-decided (never LRU
accident). Gate D cannot close until FORK-3's cardinality exists.

## 7. Cost model + implementation boundary (reviewer notes)

"fork 成本 ≈ O(binding metadata)" is a CONTRACT GOAL / semantic cost
model — NOT a proven performance promise; implementation tests must
prove it. Order preserved: FORK-3 Contract → Binding/Ref semantics →
Gate D → implementation boundary → only then decide how the existing
fork API plugs in. NEVER: edit forkSessionBranch → poolBind →
reverse-engineer the contract.

## 7. Relationship to registered items

```text
FORK-1 (file atomicity)       orthogonal; still registered
FORK-2 (fork point            SUBSUMED by FORK-3: the fork point IS
        persistence)          Ref X @ T persisted as a Binding
FORK-3 (this gate)            structural semantics — PASSED
IDENT-1                       closes only when ③④⑥⑦ resolve through
                              this contract end-to-end
```

## 8. Reviewer verdict — 2026-09-27 — PASS

Four non-blocking refinements applied above (F-I1 shared-Ref≠shared-
live-KV; F-I4 delta independence ≠ mandatory per-delta export; F-I5 =
Fork Sharing Postcondition, not a universal invariant; eviction
acceptance made conditional on artifact availability AND live-
materialization state). Cost-model caveat and implementation-boundary
ordering registered (§7). Gate D next: its core is no longer "how the
pool LRU works" but **who owns the Representation Artifact lifecycle
when multiple Execution references exist, and when physical reclamation
is permitted**.
