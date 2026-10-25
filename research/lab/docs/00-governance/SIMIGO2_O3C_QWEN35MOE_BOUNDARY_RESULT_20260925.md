# SimiGo-Lab — O3-C″ Qwen35MoE Boundary Evidence Result — 2026-09-25

Status: PARTIAL / BOUNDARY_CONFIRMED / CAPACITY_EXCEEDED
Phase: Oversized Model Execution Investigation
Model: Nail-Qwen3.6-35B-A3B-MLX-6bit (~30 GiB on disk, ~32.7 GiB core
resident) on 32.0 GiB physical.
Probe: `simigo2ctl o3c-segmentwise` (G1.9-O3C.SEGMENTWISE.V1)

## Gate disposition

```text
STATUS:
PARTIAL / BOUNDARY_CONFIRMED / CAPACITY_EXCEEDED

Execution topology:
    segment-wise forward
        CONFIRMED

Release boundary:
    OBSERVED

Capacity:
    EXCEEDED — peak footprint 78,373 MiB (76.5 GiB)
    against 32.0 GiB physical

Determinism:
    NOT EVALUATED (single pass)

Full double-pass:
    NOT ATTEMPTED

Gate:
    NOT PASS
    NOT ADVANCE TO O4
```

## Measured trace (single pass, 4×10-layer segments, exit 0)

```text
AFTER_CORE_LOAD        active  33508 MiB  footprint  37226 MiB
AFTER_EMBED_PASS1      active  33509 MiB  footprint  37228 MiB
BEFORE_SEG0_FORWARD    active  33509 MiB  footprint  37228 MiB
AFTER_SEG0_MATERIALIZE active  40517 MiB  footprint  51253 MiB  (+7.0 GiB)
AFTER_SEG0_FORWARD     active  40518 MiB  footprint  51300 MiB
AFTER_SEG0_RELEASE     active  62597 MiB  footprint  74361 MiB  (+22 GiB cliff; peak 78373)
BEFORE_SEG1_FORWARD    active  55589 MiB  footprint  74361 MiB
AFTER_SEG1_MATERIALIZE active  55109 MiB  footprint  80679 MiB
AFTER_SEG1_RELEASE     active  55109 MiB  footprint  73357 MiB  (flat)
AFTER_SEG2_RELEASE     active  47749 MiB  footprint  73208 MiB  (-7.3 GiB)
AFTER_SEG3_RELEASE     active  40389 MiB  footprint  72985 MiB  (-7.3 GiB)
BEFORE_PROJECT_OUTPUT  active  33509 MiB  footprint  72985 MiB
AFTER_PROJECT_OUTPUT   active  33592 MiB  footprint  66175 MiB
```

## Two structural findings (independent)

**Finding 1: segment-wise execution produces a stable, observable
residency release boundary.** SEG1 through SEG3 then PROJECT each shed
approximately 7.3 GiB of active memory, returning to the core baseline.
This is direct evidence that `Qwen35Model.forwardLayerRange` execution
topology changes physical residency in a segment-lifecycle-correlated
manner. This is the first direct measurement of this property.

**Finding 2: capacity is exceeded by core load alone, independent of
segment policy.** The non-switch_mlp core for this model is 32.7 GiB —
already at physical capacity before any segment materialization. The
SEG0 release path then triggered an additional ~22 GiB materialization,
bringing peak footprint to 76.5 GiB (2.4x physical). The system survived
this run but required no further evidence: this model on this machine
cannot complete the full O3-C protocol.

## Direct peak trigger point (this run, not a universal claim)

In this run, the `eval(model.parameters())` call in the release path
corresponds directly to the +22 GiB active jump and the 78,373 MiB peak
footprint. For this Qwen35MoE model, this call forces materialization of
the full lazy parameter tree (all 40 layers x 256 experts switch_mlp
placeholders). This is a specific observation, not a claim about all MLX
models or all Qwen35 variants. It marks the optimization point for any
future run of a capacity-feasible model.

## Result statement (exact wording)

> Qwen35MoE segment-wise execution produced a stable residency release
> boundary in actual measurement; but this model's peak reached
> approximately 76.5 GiB under this machine's 32 GiB physical memory
> condition and cannot satisfy the capacity constraint.

Not claimed: that Qwen35MoE has been proven to run segmented on a 32 GiB
machine. That is not supported by this experiment.

## Disposition

This experiment is sealed as **mechanism evidence**. The Qwen35MoE model
on 32 GiB hardware will not be re-run. The research chain:

```
             O3-C
                |
       +--------+--------+
       |                 |
Qwen3-Coder-Next     Qwen35 MoE
 stress case         boundary case
       |                 |
whole graph         segment-wise
retention           release OK
capacity FAIL       capacity FAIL
       |                 |
       +--------+--------+
                |
                v
       capacity-feasible MoE
                |
                v
       boundary + capacity
       + double-pass
       + determinism
                |
                v
          O3-C gate decision
```

Next direction: a smaller sparse/MoE model that fits in 32 GiB physical
memory, to complete the combined boundary + capacity + determinism
evidence needed for the O3-C gate decision. Selection criteria and
candidate models are not yet declared.

Raw log: `/tmp/o3c-qwen35-segmentwise-pass1.log` (session-local, not
checked into the repository).

Probe code state: `O3CSegmentWiseProbe.swift` migrated from
`Qwen3NextModel` to `Qwen35MoEModel` (minimal migration, 5 changes);
`mlx-swift-lm` fork gained `Qwen35TextModelInner.forwardLayerRange` and
`Qwen35Model` public forwarding methods (`embedInputs`,
`forwardLayerRange`, `projectOutput`), math-equivalence validated 3/3
(bit-exact) in `Qwen35ForwardLayerRangeTests`.
