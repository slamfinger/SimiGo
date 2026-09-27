# SimiGo-Lab — O5 Segment-Size Sweep v1 — 2026-09-26

Status: O5_SEGMENT_SIZE_SWEEP_V1_MEASURED / FOOTPRINT_HALVED_LATENCY_NEUTRAL
Phase: Oversized Model Execution Investigation (O5 boundary sweep, first item)
Protocol: G1.9-O4.OVERSIZEGEN.V1 (`simigo2ctl o4-oversized-gen --segment-size N`)
Model: Qwen3-Coder-Next-4bit (41.76 GiB, 48 layers, 32 GiB physical)
Trigger: user question — can the partition be re-cut so that resident core +
one segment ≈ 8 GiB (motivated by a garbled secondary report of "setting
memory to 8 GiB significantly improves latency"; verified below that the
underlying paper is Apple's LLM-in-a-Flash 2024, not Google, and its 8 GB is
a device-RAM context, not a memory-cap knob).

## Measured (8 tokens × 2 passes, greedy, same prompt)

```text
segment-size 16 (3×13.5 GiB)  peak footprint 13,883 MiB  ~11.0 s/token
                              (read 8.6 s / forward 2.2 s)
segment-size 8  (6×6.75 GiB)  peak footprint  6,745 MiB  ~11.5 s/token
                              (read 9.1 s / forward 2.3 s, update+release 67 ms)
both                          swap 0 MiB, double-pass token sequences
                              identical ([8420, 594, ...])
```

## Findings

1. The 8 GiB-class re-partition is CORRECT and STABLE: 6×8-layer segments
   hold peak residency at 6.6 GiB — under the 8 GiB target — with zero
   swap and bit-identical outputs. Segment size is a free parameter of the
   validated machinery.
2. Re-partitioning trades FOOTPRINT, not LATENCY: total re-materialization
   I/O per token is unchanged (~40.5 GiB), so per-token latency is neutral
   (11.0 → 11.5 s, ~+4% = per-segment overhead under a concurrent download;
   not an improvement). In this zero-swap regime a memory cap has no latency
   to recover — the bottleneck is total re-read bytes ÷ I/O throughput.
   The "8 GiB improves latency" claim does not transfer to this system;
   where memory caps DO matter is when thrash exists (e.g., O2's native
   full-load collapse at 23 GiB swap) or to free page cache for other work.
3. Latency levers registered for later O5 items: prefetch pipelining
   (overlap read(seg i+1) with forward(seg i) — upper bound ≈ hide the
   2.2 s forward → ~8.6-9 s/token); persistent-window + active-expert-only
   loading (Apple LLM-in-a-Flash mechanism — blocked by the fused
   switch_mlp granularity, the tension registered at O0); faster storage.
   None of these is "set memory to 8 GiB".

Caveat: the user's concurrent 54.3 GB model download was running during the
sweep; read-throughput numbers are lower bounds under that contention.
8 tokens × 2 passes per configuration; sweep continues (O5).

Artifact: `simigo2-experimental/results/o4-generation/qwen3-coder-next-4bit-seg8-sweep.json`.
