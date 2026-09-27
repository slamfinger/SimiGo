# FORK-3 Structural Contract — Shared-Representation Fork — Definition Draft

**Date**: 2026-09-27 · **Status**: DEFINITION_DRAFT / AWAITING_REVIEW
(no implementation code — per the ruled order: FORK-3 structural
contract → Gate D eviction/reference semantics → implementation
boundary)

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
F-I1  shared identity, not copied state   Child binds Ref X itself —
      fork does NOT copy, re-serialize, or re-materialize the
      representation at fork time
F-I2  parent non-interference             fork leaves E_p's binding,
      position, lineage, and deltas bit-identical to pre-fork
F-I3  child starts at the boundary        E_c.position = T ==
      Ref X.boundLength (R-I5 holds at bind)
F-I4  delta independence                  ΔP/ΔC never interact; each
      side's future exports are new content-addressed Refs
F-I5  binding cardinality grows           after fork, Ref X carries
      ≥2 active bindings (B-I5's "Ref → N" realized)
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
```

## 6. Gate D handoff (next gate in the ruled order)

FORK-3 makes Gate D mandatory: with Ref X under ≥2 active bindings, the
eviction/reference semantics must be pinned — pin-while-referenced vs
rematerialization-required-per-execution, contract-decided (never LRU
accident). Gate D cannot close until FORK-3's cardinality exists.

## 7. Relationship to registered items

```text
FORK-1 (file atomicity)       orthogonal; still registered
FORK-2 (fork point            SUBSUMED by FORK-3: the fork point IS
        persistence)          Ref X @ T persisted as a Binding
FORK-3 (this gate)            structural semantics
IDENT-1                       closes only when ③④⑥⑦ resolve through
                              this contract end-to-end
```
