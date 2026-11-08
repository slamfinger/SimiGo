# Issue #15 Round 1 — real llama.cpp slot-progress measurement (2026-11-08)

Measurement-only run for Issue #15: while llama.cpp reports `is_processing`
indefinitely, the Service health loop defers recovery forever (pre-probe skip +
post-failure busy protection). A no-progress watchdog needs real thresholds;
this run measures slot-counter behaviour under four load profiles plus client
cancellation. **No recovery policy was modified or consulted during the run.**

## Setup

- Engine: SimiGo-managed `llama-server` 0.8.0-dev (b11720 family), run from a
  `/tmp` copy of the binary plus its dylibs (both layouts verified — run 1 from
  `~/.simigo/bin`, run 2 from `/private/tmp/fifteen/bin`; results agree).
- Model: `gemma-4-12b-it-Q4_K_M.gguf` (Metal, `-ngl 99`, ctx 8192).
- Launch flags mirror `BackendConfig.llama` production skeleton:
  `--parallel 1 --cache-prompt --slots --cache-type-k/v q4_0 -b 1024 -ub 512
  --flash-attn on`.
- `/slots` sampled every 500 ms into JSONL (timestamped `id_task`,
  `is_processing`, `n_prompt_tokens_processed`, `n_decoded`).

## Scenarios

| scenario | load |
|---|---|
| normal | short prompt, 256 max tokens |
| decode_heavy | long generation, 1024 max tokens |
| prefill_heavy | ~3.4k-token prompt, 64 max tokens |
| cancel | streaming client aborts ~6 s into decode |
| concurrent | 3 overlapping requests against `--parallel 1` |

## Results (two independent runs)

| metric | observed |
|---|---|
| decode throughput | ~13.5 tok/s (12B Q4_K_M Metal) |
| prefill throughput | ~330 tok/s |
| max no-progress inside prefill | = sampling tick (0.5 s) |
| max no-progress inside decode (steady) | 0.51–0.57 s (tick-bound), p99 ≈ 0.6 s |
| max prefill→decode transition gap | 1.87 s (run 1) / 2.29 s (run 2) |
| cancellation → slot idle | prompt+partial decode window (~5.5 s) then idle; **no lingering `is_processing`** |
| concurrent (np=1) | requests queue; `id_task` advances sequentially (1426→1427→1428); no counter regression |

## Threshold implication for a busy-slot no-progress watchdog

- Observed maximum no-progress across ~250 busy-seconds, both runs: **2.29 s**
  (a single prefill→decode boundary gap); everything else is tick-bound.
- A 10 s threshold = 4× observed max, ≈16× observed p99 stall → no false-kill
  exposure in these profiles.
- The final watchdog threshold must still be **rate-relative**
  (`max(10 s, K × expected inter-token time)`) and re-derived per model size —
  12B/Q4 numbers do not transfer to larger or slower models.

## Round 2 design (next, not yet run)

Busy-but-no-progress at the Service interface: a proxy on the engine port that
answers `/health` 200 while freezing `/slots` at a busy snapshot with static
counters. The Service must detect the frozen counters; a normal pass-through
profile must not trigger it (false-kill check). Thresholds come from this
document, not from a picked timeout.

## Files

- `measure_slots.py` / `analyze_slots.py` — harness and analysis.
- `threshold_summary.json` — combined summary (both runs).
- `evidence/run{1,2}_samples_*.jsonl` — raw 500 ms samples.
- `evidence/run1_scenarios.json` — wall-clock per scenario (run 1).
