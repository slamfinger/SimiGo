# Issue #15 Round 1 — real llama.cpp slot-progress measurement (2026-11-08)

> ## CORRECTION (2026-11-08 review — read this first)
>
> The original collector below read `n_decoded` from the slot TOP LEVEL. In
> the b11720 schema that field lives at **`slot.next_token[0].n_decoded`**;
> the top-level key does not exist, so every v1 decode sample was `null` and
> the v1 decode claims (0.51–0.57 s decode no-progress intervals, the 10 s
> watchdog threshold with 4× margin) are **RETRACTED**. The 1.87 s / 2.29 s
> "transition gaps" were also not proven stalls: the raw prefill-heavy data
> shows `n_prompt_tokens_processed` advancing during those windows (3416→3420),
> and the v1 cancel sampling had a 10 s blind window right after client close,
> so the "≤2 s release" claim was unproven.
>
> **What stands from v1**: both binary layouts ran real models, busy state and
> prefill counters were captured, cancellation and concurrency scenarios
> executed. The raw v1 data below is preserved untouched as the archive.
>
> **Corrected re-run** (`measure_slots_v2.py` / `analyze_slots_v2.py` /
> `corrected_summary.json` / `evidence_v2/`): reads
> `next_token[0].n_decoded`; analyses segment per `id_task` with phase
> attribution (prefill = prompt counter advanced, decode = n_decoded
> advanced); the cancel scenario samples continuously from the exact
> client-close timestamp until idle.
>
> Corrected results: decode throughput **11.9–13.9 tok/s** (from
> `next_token[0].n_decoded` deltas); decode-heavy same-task true stalls
> **0** across both runs (counter advanced every tick); the one true
> same-task no-progress window was **1.95 s** at the prefill-complete →
> first-token boundary (run 1; run 2 max was tick-bound 0.51 s);
> **cancel → idle release latency 0.47–0.50 s** (client close → first idle
> sample, tick-bound upper bound); concurrent requests hold per-task
> baselines with no cross-task counter confusion. A no-progress watchdog
> threshold must be **rate-relative** (`max(10 s, K × median inter-token)`);
> with ~72 ms median inter-token, 10 s ≈ 139 median intervals ≈ 5× the
> largest observed boundary stall — single-model, single-machine evidence.
>
> **R2 split (revised)**: the current Service only parses `is_processing` and
> cannot see progress counters, so R2 is two phases — **R2-A** proves the
> existing defect (engine-port proxy: `/health` 200 + frozen busy `/slots`;
> record the Service deferring recovery indefinitely); **R2-B** validates the
> NEW counter-monitoring (pass-through must not false-kill; frozen snapshot
> must be detected; id_task change resets the baseline; phase transitions are
> not stalls). Detecting a stall and authorising a restart are separate
> decisions; recovery policy stays under separate ruling.



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
