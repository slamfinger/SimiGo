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
> advanced; adjacent pairs counted only when both ends are busy), and the
> cancel scenario samples continuously from the exact client-close timestamp
> until idle.
>
> Corrected results: decode throughput **11.9–13.9 tok/s** (from
> `next_token[0].n_decoded` deltas); decode-heavy same-task true stalls
> **0** across both runs (counter advanced every tick); the one true
> same-task no-progress window was **1.95 s** at the prefill-complete →
> first-token boundary (run 1; run 2 max was tick-bound 0.51 s);
> **cancel → idle: the first idle-observing sample landed 0.47–0.50 s after
> client close** — an observation-time bound (sample t brackets the /slots
> request), not the engine's exact internal release instant.
>
> The 10 s figure is a **candidate observation window** for the Round-2
> fault-injection experiments, NOT a validated production restart threshold.
> The watchdog-relevant stall metric is the **consecutive counter-static
> span** (time from the last sample where any counter advanced to the next
> such sample): the largest normal span in prefill-heavy was **~4.04 s in
> BOTH runs** (batched `-ub 512` prompt processing: counters update in
> batches, so consecutive ticks can be static without any engine fault).
> 10 s ≈ 2.5× that observed maximum — the margin is thinner than the
> retracted v1 claim, and the final threshold must be rate-relative
> (`max(10 s, K × token-time-scale)`, average-throughput reciprocal
> ~75–77 ms at 12.95–13.30 tok/s; not a measured per-token interval
> distribution). Single-model, single-machine evidence.
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

## ⚠ V1 RESULTS — RETRACTED, HISTORICAL RECORD ONLY

> The collector used here read a non-existent top-level `n_decoded`; decode
> counters were never observed. The decode "no-progress" row and the 10 s
> threshold margin below are **not valid evidence** — see the CORRECTION at
> the top of this file and `evidence_v2/` + `corrected_summary.json` for the
> corrected measurements. Kept verbatim so later readers do not mistake the
> archive for current results.

### Results (two independent runs) — V1, RETRACTED

| metric | observed |
|---|---|
| decode throughput | ~13.5 tok/s (12B Q4_K_M Metal) |
| prefill throughput | ~330 tok/s |
| max no-progress inside prefill | = sampling tick (0.5 s) |
| max no-progress inside decode (steady) | 0.51–0.57 s (tick-bound), p99 ≈ 0.6 s |
| max prefill→decode transition gap | 1.87 s (run 1) / 2.29 s (run 2) |
| cancellation → slot idle | prompt+partial decode window (~5.5 s) then idle; **no lingering `is_processing`** |
| concurrent (np=1) | requests queue; `id_task` advances sequentially (1426→1427→1428); no counter regression |

### Threshold implication for a busy-slot no-progress watchdog — V1, RETRACTED

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

## R2-A staged runbook (shim landed, execution next)

**Seam**: `defaults write <app-domain> LlamaServerBin <shim-path>` makes
`BackendConfig.executable` resolve to the shim (checked first, must exist and
be executable) — the Service then launches the shim with the production
argument vector. No Service code changes.

**Shim** (`issue15_engine_shim.py`): spawns the real engine on port P+1,
forwards /health and everything except /slots verbatim, serves /slots from
`SHIM_SLOTS_MODE` (frozen busy | passthrough). Owns the child lifecycle
(TERM→KILL escalation, atexit guard) — standalone-verified: /health 200,
frozen slots, zero leftovers.

**Acceptance** (record the FULL timeline from
`$SIMIGO_HOME/logs/native_mlx_trace.log`; the health loop waits 10s at
startup and busy protection sleeps 30s per cycle):

| step | operation | must observe |
|---|---|---|
| A1 | frozen busy /slots, /health 200 pass-through | preflight skip repeatedly (⏸ skip log every ~30s), no /health request reaches the real engine, no restart |
| A2 | same frozen busy + one-shot `SIMIGO_HEALTH_CHECK_FAILURE_INJECTION` (validation build; injects the check RESULT, not a real 503) | after the injected failure the loop re-reads slots, sees busy, logs defer (⏸ 暂不重启), no restart |
| A2 follow-up | injection consumed | loop returns to A1 preflight-skip, still no restart |

**Build note**: `SIMIGO_HEALTH_CHECK_FAILURE_INJECTION` is defined in no
xcconfig/scheme today — the validation build must override
`SWIFT_ACTIVE_COMPILATION_CONDITIONS` (e.g. `DEBUG SIMIGO_HEALTH_CHECK_FAILURE_INJECTION`).

**Out of scope for R2-A**: any restart-policy change. R2-B (counter monitor
four-quadrant validation) lands after a monitor exists; detection and
restart authorisation remain separate decisions.

## R2-A EXECUTED (2026-11-08) — verdict: PASS

The existing Service's two deferred-recovery branches were exercised on a
real process, a real engine (gemma-4-12B through the shim), and a controlled
`/slots` view — using the headless `serve-service` facade
(`SIMIGO_LOCALB_MGMT=serve-service` + `SIMIGO_LOCALB_SERVE_MODEL`), the
`LlamaServerBin` config seam for the shim, and `SIMIGO_TRACE_VERBOSE=1` for
the full timeline. No build-time injection was needed in the end: the shim
answers the loop's first post-observation `/health` with a REAL 503 (once),
which exercises branch 2 without touching product code.

**A1 — preflight skip (branch 1): PASS.**
Trace: 4 consecutive cycles at the 30.5 s rhythm
(11:59:31 → 12:00:01 → 12:00:32 → 12:01:02), each
`🔍 ⏸ llama.cpp 当前存在活动 slot，跳过健康检查。`, zero restarts.

**A2 — post-failure busy protection (branch 2): PASS.**
One timeline contains the full chain:
`12:07:30.561 GET /slots → [] (unknown, preflight stays active) →
12:07:30.563 GET /health → 503 →
12:07:30.563 GET /slots (re-read) → frozen busy →
12:07:30.564 ⚠️ ⏸ Health 检查失败但 llama.cpp 仍有活动 slot，暂不重启。`

Provenance precision (review 2026-11-08): the 503 is a **synthetic HTTP 503
generated by the shim on the Service's real HTTP probe path** — the Service
received a genuine transport-level failure response over HTTP and executed
its failure branch (slot re-read + busy protection). This proves the
Service's HTTP error-handling path; it does NOT prove that a real
llama-server failed on its own.

**A2 follow-up: PASS.** 12:08:01 / 12:08:31 / 12:09:01 return to the A1
preflight-skip path — the one-shot failure did not pollute later cycles.

**What this proves**: the Service DOES defer recovery on both paths exactly
as the Issue describes — preflight skip on branch 1, busy protection on
branch 2, with **no exit based on sustained no-progress time** in either
path's control flow. A1 observed ~1.5+ min of continuous skip cycles and A2
one defer plus three post-defer skip cycles within finite observation
windows; that the deferral is unbounded follows from the observed cycle
behaviour plus the control flow (as long as busy keeps being reported,
every cycle defers), not from an observed infinite run. This is the defect
half of Issue #15, now with process-level evidence.

**Scope limits**: the frozen `/slots` snapshot is a shim-controlled view —
R2-A proves what the SERVICE does with such an observation, not that a real
llama.cpp wedges this way. The shim forwards via full-buffered urlopen
(GET/POST only) — it is not a general llama-server proxy and must not be
used to judge streaming behaviour. Release-time and stall-detection
thresholds for any future monitor come from the R1-v2 numbers
(4.04 s normal consecutive-static max on this model) and stay a candidate
window until R2-style fault injection runs against the real monitor.

**Evidence**: `r2a_evidence/A1_trace.log`, `A2_trace.log` (verbatim Service
trace), `A1/A2_run_timeline_extract.txt` (auxiliary timeline extracts),
`A1/A2_process_snapshots.txt` (10 s ps + port-listen snapshots; A1 66 lines,
A2 72 lines, timestamps aligned with the traces).

## R2-B IMPLEMENTED (2026-11-08) — monitor-only, four-quadrant acceptance green

`SimiGo/Inference/SlotProgressMonitor.swift` (MONITOR ONLY — never restarts,
never terminates, never touches busy-protection policy) +
`SimiGoTests/SlotProgressMonitorTests.swift` (10 unit tests, all green).

Observation semantics per the owner ruling: identity = (engineGeneration,
slotID, idTask); prefill/decode/mixed progress with ONE progress per tick;
counter regression -> baseline_reset (never a stall); missing counters and
probe failures -> unobservable (they can neither create nor confirm a
stall — a span containing an unobservable sample is barred from
candidate_stall); prefill->decode boundary -> phase_transition_or_unknown
while accumulating monotonic time; idle/slot-gone/generation-change ->
baseline_reset.

Acceptance:
- Q1 normal progression (prefill -> boundary -> decode sequence): no
  candidate_stall anywhere; boundary labelled phase_transition_or_unknown. UNIT PASS.
- Q2 frozen counters: observing_no_progress then candidate_stall after the
  explicitly passed test window. UNIT PASS + **live PASS on the real
  Service**: candidate_stall at 30.1 s / 61.1 s / 92.7 s through the frozen
  shim on the running app, with the log line stating "monitor only; no
  restart is authorised" (`r2b_evidence/R2B_frozen_trace.log`).
- Q3 id_task change: baseline_reset, no inherited static time. UNIT PASS.
- Q4 phase transitions (sequential + mixed tick): progressing, phase
  correctly prefill/decode/mixed, no false stall. UNIT PASS.
- Protection: missing counters -> unobservable and candidate-barred;
  counter regression -> baseline_reset. UNIT PASS.

Wiring: `ManagedGGUFRuntime.slotActivity()` feeds the SAME `/slots` response
to the monitor (zero extra requests, busy-protection decisions untouched);
the runtime owns one monitor per engine instance (an engine restart changes
the generation and re-baselines). The candidate window is a LABEL — default
30 s via `SIMIGO_SLOT_PROGRESS_WINDOW_MS` (deliberately wider than R1's
observed 4.04 s normal maximum) and NOT a production restart threshold.
Automatic restart remains unauthorised and unimplemented.

**Known limitation (live coverage)**: the live E2E validated Q2 (frozen
detection) end-to-end; Q1/Q3/Q4 were validated on the decision table via
unit sequences. A live passthrough-with-real-generation run to observe
non-stall behaviour end-to-end is staged for the next window.

## Evidence redaction record (2026-11-08, release hygiene)

Four captures below carried this machine's local home-directory prefix.
`Release hygiene` scans the tracked tree, so that single token — in its
plain and JSON-escaped spellings — was replaced with the stable placeholder
`<HOME>`. Nothing else changed: 159 lines carry one replacement each, and
commands, results, timestamps, task ids, counters and error text are
byte-identical; line counts are unchanged. `<HOME>` is the placeholder the
release sanitizer already emits for home paths, so the tracked source and
the publishable copy now agree (sanitizing these files is a no-op).

The pre-redaction bytes stay retrievable from git and are the provenance
baseline: `git show 6c8e116:<path>` (the final head before this redaction;
those blobs are byte-identical to `main` at `98dea418`). Both hashes are
recorded here so a reviewer can trace redacted → original without putting
the machine identifier back into the tree. This is a tracked-tree change
only, not a Git history rewrite.

| file | original SHA-256 | bytes | redacted SHA-256 | bytes |
|---|---|---|---|---|
| `r2a_evidence/A1_process_snapshots.txt` | `0904317eb728c969625d78e197a9ecf0983c4186d74da079332865792bb83cf3` | 7825 | `8e4a72999d64362d9cf8f18a30f17ec97ce71436119b7986c47dc26b8c22b0be` | 7561 |
| `r2a_evidence/A2_app_stdout.log` | `064f8b035a8ec8f400b0888578870e81b9487d223841f31d6d4d32edafd6e33d` | 29061 | `3f2ca2ba5fb953d0580e1fffcb24e499d72a3c35eb3ec7c66acfc62dbc1d2b7e` | 28627 |
| `r2a_evidence/A2_process_snapshots.txt` | `89ae137a7c24b1427a37d0bdb95735e7d59649a580101ada922421d3e3ebfe9a` | 8540 | `b22e568805be7c75c445f632f55e09ba2b25670e3ee59d92946474bafb7745e2` | 8252 |
| `r2b_evidence/R2B_process_snapshots.txt` | `5b902582336d16c0d900d318a2b83e142f6eda1acd298ffbd48a2bfcef919b51` | 8504 | `f6adde78a9450e44cb8e3bc2593ad22472a30ac973342431b3b6f8601b76e202` | 8216 |
