# SimiGo-Lab — O5 Prefetch Pipelining + Clean Segment-Size Matrix — 2026-09-26

Status: O5_PREFETCH_MEASURED / NEGATIVE_AT_SCALE / SEG8_SEQUENTIAL_IS_PARETO_BEST
Phase: Oversized Model Execution Investigation (O5 boundary sweep, item 2)
Protocol: G1.9-O4.OVERSIZEGEN.V1 + `--prefetch` flag (background read of
segment i+1 overlapping forward(seg i); pipeline state resets per token)
Model: Qwen3-Coder-Next-4bit (41.76 GiB, 32 GiB physical), clean I/O
conditions (no concurrent download).

## Measured matrix (8 tokens × 2 passes, greedy)

```text
config            mean ms/token   read/wait   forward   peak footprint   swap
seg16 sequential     11,310-11,407   9.2 s      2.1 s     15,722 MiB      0
seg16 prefetch       12,448-13,211   8.8-10.0   2.9-3.3   15,715 MiB      0
seg8  sequential      7,668-7,726    7.1 s      0.53 s     8,821 MiB      0
seg8  prefetch        7,499-7,537    6.6-6.7 s  0.85 s     9,575 MiB      0
```

All four configurations: double-pass token sequences bit-identical
([8420, 594, 264, 13027, 729, 429, 80953, 1378]) and cross-config
identical — the greedy function is execution-order-robust at this
granularity.

## Findings

1. **Prefetch pipelining is NEGATIVE at coarse granularity**: seg16
   prefetch is 10-16% SLOWER than sequential (forward phase inflated
   2.1 → 2.9-3.3 s). At seg8 it recovers only ~2.3% (170 ms). The naive
   "hide forward behind read" model fails on Apple Silicon unified
   memory: disk DMA + page-cache copies + buffer construction consume the
   same memory bandwidth the GPU forward needs — the overlap taxes the
   very phase it is supposed to hide, and the tax grows with segment
   size. Prefetch costs +0.75 GiB peak for its (small) gain at seg8.
2. **Clean-condition seg8 sequential is the Pareto best measured**:
   7.7 s/token at 8.8 GiB peak — 32% faster AND 50% smaller-residency
   than the seg16 default (11.3 s / 15.7 GiB). Mechanism: smaller
   segments re-read at higher effective throughput (5.7 vs 4.4 GB/s —
   cyclic page-cache hit-rate on the 40.5 GiB/token working set).
   The O5 sweep v1 "latency neutral" conclusion was a download-
   contamination artifact; under clean conditions segment size DOES move
   latency through read efficiency.
3. **Measurement hygiene registered**: the concurrent 54.3 GB download
   inflated I/O-bound timings ~50% (seg8: 11.5 → 7.7 s/token clean).
   I/O-bound probes must run with the network/disk idle; earlier
   contaminated numbers stand only as worst-case bounds.
4. Probe defect fixed in-flight: the prefetch pipeline state was not
   reset per token (token 2 hit a nil unwrap → SIGTRAP). Fixed and
   re-run before accepting numbers.

## Revised O5 outlook

- Current best operating point: **seg8 sequential** (7.7 s/token,
  8.8 GiB peak, zero swap) on this machine/storage.
- Prefetch re-enters only if the compute/I-O ratio grows (longer
  contexts, bigger forward share) or storage decouples from memory
  bandwidth; its memory cost (+1 segment) is real.
- The dominating term remains re-materialization bytes ÷ effective
  throughput; granularity tuning moves the throughput constant, not the
  bytes.

Artifact: `simigo2-experimental/results/o4-generation/qwen3-coder-next-4bit-{seg8-,baseline16,prefetch16,seg8-prefetch}*.json`;
probe `O4OversizedGenerationProbe.swift` (+`--prefetch`).
