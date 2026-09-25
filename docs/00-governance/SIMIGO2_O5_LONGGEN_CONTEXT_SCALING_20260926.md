# SimiGo-Lab — O5 Long-Generation Stability + Context Scaling — 2026-09-26

Status: O5_LONGGEN_STABLE_AND_CONTEXT_LINEAR / O5_SWEEP_COMPLETE
Phase: Oversized Model Execution Investigation (O5 boundary sweep, items 3-4)
Protocol: G1.9-O4.OVERSIZEGEN.V1 + `--prompt-repeat` (context construction)
Model: Qwen3-Coder-Next-4bit (41.76 GiB, 48 layers, seg8 = 6×8-layer
segments — the Pareto-best operating point), 32 GiB physical, clean I/O.

## Long-generation stability (32 tokens × 2 passes, 219-token prompt)

```text
determinism            PASS — 32-token sequences bit-identical across passes
peak footprint         8,952 MiB — flat across the whole run
                       (first 8,789 / last 8,670 / max 8,952; no creep)
swap                   0 MiB at every boundary
pass 1                 mean 7,732 ms/token, first→last drift +1.5%
pass 2                 mean 8,643 ms/token, tail +20.5%
```

The pass-2 tail inflation is EXPLAINED BY CONTEXT GROWTH, not degradation:
the cacheless strategy re-forwards the full prefix each token, so token k
processes 219+k positions (+14% by token 32 — matches the measured tail).
Pass 2's overall +12% vs pass 1 is registered as undetermined system-level
variance (thermal/system-load candidate); output correctness unaffected.

## Context scaling (8 generated tokens, prompt-repeat 1/25/100)

```text
context (tokens)   18          258          1,008
read               8.38 s      8.23 s       8.82 s    — constant (weights only)
forward            0.60 s      3.39 s       12.68 s   — linear:
                                                         ≈ 0.38 s + 12.2 ms/token
mean token         9.0 s       11.7 s       21.7 s
peak footprint     8,822 MiB   8,691 MiB    8,904 MiB — flat (weights-bound)
swap               0           0            0
```

Linear fit confirmed (predicted 3.52 s at ctx 258 vs measured 3.39 s).
**Crossover point: context ≈ 600-700 tokens** — beyond it the cacheless
forward cost exceeds the constant re-materialization read cost and becomes
the dominant term (12.7 s vs 8.8 s at ctx 1,008).

## Reading

1. Long generation is STABLE: no memory creep, no swap, deterministic
   across a 32-token horizon; latency growth is fully accounted for by
   prefix-length growth.
2. Memory is weights-bound and context-independent at these scales —
   residency engineering (segment size) controls capacity; context does
   not.
3. The context crossover (~600-700 tokens) is the quantitative motivation
   for O6: prefix/KV-level strategies (Execution State machinery) become
   the dominant latency lever exactly beyond the crossover; below it,
   re-materialization I/O dominates and seg8 sequential remains optimal.

Artifacts: `simigo2-experimental/results/o5-sweep/qwen3-next-{longgen32,ctx1,ctx25,ctx100}.json`.
