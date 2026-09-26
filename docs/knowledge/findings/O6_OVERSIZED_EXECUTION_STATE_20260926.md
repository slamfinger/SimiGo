<!-- Publicly curated from SimiGo-Lab. Source: docs/00-governance/SIMIGO2_O6_EXECUTION_STATE_OVERSIZED_20260926.md on exp/simigo2-experimental. Internal recovery/governance material has been excluded. -->

# SimiGo-Lab — O6 Execution State × Oversized Model — PASS — 2026-09-26

Status: O6_EXECSTATE_OVERSIZED_PASS / SEVEN_OF_SEVEN_CHECKS
Phase: Oversized Model Execution Investigation (O6)
Protocol: G1.9-O6.EXECSTATE.V1 (`simigo2ctl o6-execstate`)
Model: Qwen3-Coder-Next-4bit (41.76 GiB, 48 layers, seg8 = 6×8-layer
segments) on 32.0 GiB physical.

## Design (layering — who owns what)

```text
ExecutionContinuityCoordinator   identity/lineage/position/continuation
                                 sovereignty (E-line, unchanged)
OversizedSegmentedStateBackend   ExecutionStateBackend over a prefix payload
                                 (OversizedPrefixPayload); the oversized
                                 eviction = releaseRepresentation (drops the
                                 binding AND releases every segment weight;
                                 the logical record survives)
SegmentedCore (O6SegmentedCore)  the verified physical machinery:
                                 placeholder-first load; per segment
                                 materialize -> forwardLayerRange -> release
OversizedSegmentedExecutor       representation-consuming execution (E5-v2
                                 semantics): cacheless greedy re-forward of
                                 bound prefix + next input
```

First-run scenario defect (fixed before accepting results): the D-I
checkpoint was captured AFTER run 1 (advanced prefix) and run 2 appended
the same next input — two different computations. Corrected to the E5
authoritative shape: the fork-point representation survives eviction in
the coordinator's history; `coordinator.restore` rolls the logical
position back to the fork point; run 2 re-runs the same next input from
the restored representation.

## Measured result (7/7 PASS)

```text
PARENT_IDENTITY_STABLE                    PASS
CHILD_LINEAGE_TRACEABLE                   PASS
FORK_DIVERGENCE                           PASS
RESTORE_TO_FORK_POINT                     PASS (logical pos -> 1, .restored;
                                          segments re-materialize on demand)
CHILD_DETERMINISM_THROUGH_SEGMENT_
  EVICT_RESTORE                           PASS — run2 == run1 (tokens+text)
PARENT_NON_INTERFERENCE                   PASS — parent turn 2 == pre-fork
                                          reference
RESIDENCY_BOUNDED_ZERO_SWAP               PASS — peak 8,111 MiB <= 30 GiB,
                                          max swap 0 MiB
SEGMENT_TRANSITIONS_EXECUTED              121 materialize/release transitions
```

## Reading

The E4 invariant — an evicted Execution State IS still the same Execution
State — now holds at oversized scale: across a full segment eviction
(every switch_mlp weight released, buffers purged) and an on-demand
re-materialization restore, the child execution resumed from the restored
fork-point representation bit-identically, and the parent remained
unaffected. Execution semantics (identity/lineage/position/continuation)
and physical residency (core + one segment at a time) are cleanly
separated on a model 30% larger than physical memory.

Scope notes: v1 covers Execution State semantics through segment
eviction/restore without the ResidencyController (segment release is
performed by the backend directly; Controller-composition with transfer
log/INV-1 accounting is the registered follow-up). Harness-level probe;
no performance claims. Greedy cacheless execution (no KV authority).

Artifact: `simigo2-experimental/results/o5-sweep/qwen3-next-o6-execstate.json`;
probe `O6ExecutionStateOversized.swift`.
