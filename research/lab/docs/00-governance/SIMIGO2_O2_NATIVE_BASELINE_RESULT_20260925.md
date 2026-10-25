# SimiGo-Lab — O2 Native MLX Baseline Result — 2026-09-25

Status: O2_BASELINE_MEASURED / NATIVE_PATH_H_EAGER_LOAD_INCOMPLETE / O3_SKELETON_LOAD_REQUIRED
Phase: Oversized Model Execution Investigation
Model: `mlx-community/Qwen3-Coder-Next-4bit` (`qwen3_next`, 41.76 GiB
weights, 9 shards) on 32.0 GiB physical memory machine
Probe: `simigo2ctl o2-baseline` (G1.9-O2.BASELINE.V1), ZERO SimiGo
intervention — the fork's native `LLMModelFactory.loadContainer` path only.

## Result: the native full-model load did NOT complete (H-eager)

The watchdog window was 9 minutes. During that window:

```text
process CPU      100–115% sustained (single-thread saturated)
process RSS      40–98 MB  (weights never resident in process-visible RSS)
system swap      ~0 → 22.6 → 23.5 GiB within the first ~2 minutes,
                 then pinned at 22.7–23.5 GiB for the whole window
probe report     never written (loadWeights never returned)
post-kill        swap draining slowly (23 GiB → 2.2 GiB residual)
```

Timeline (external polling, ~45 s resolution):

```text
T+0:00   process start, swap baseline ≈ 0
T+1:36   swap 22.6 GiB used — the load phase is already paging hard
T+2:21   swap 23.1 GiB, RSS collapsed to ~51 MB (thrash signature)
T+3..9m  swap pinned 22.7–23.5 GiB, CPU 100–115%, no completion
T+9m     watchdog kill; swap drains 23 → 2.2 GiB over the following
         minutes; no report file (the probe never passed the load phase)
```

## Verdict

```text
H-mmap vs H-eager  =  H-EAGER for the native full-model load path
```

The mmap-backed lazy MLXArrays at READ time (registered in the O1 load-
chain audit) do NOT survive the load path: `loadWeights` → `model.update
(parameters:, verify: .all)` binds all 41.76 GiB of weights into device
buffers eagerly. On a 32 GiB machine this exceeded the wired/unified-memory
working limit (~22 GiB), and the overflow went to encrypted swap. The load
phase itself never completed within the watchdog — the probe never reached
T3 (first forward), so O2-C (generations) is UNREACHABLE via the native
path on this model.

## Boundary classification (per the three-boundary frame)

```text
Capacity Boundary    = the native load never completed in 9 min → the
                       native path cannot deliver an executable model at
                       all on this machine (C outcome of the three-outcome
                       taxonomy: the current native MLX path cannot complete
                       oversized execution)
Stability Boundary   = already violated during load (22.9 GiB swap, system-
                       wide pressure; a shared machine cannot be left in
                       this state — hence the watchdog kill)
Performance Boundary = unreachable via this path (no forward ever ran)
```

Per the phase discipline, this is a COMPLETE and valuable O2 result: the
native MLX baseline is measured, and the answer for the native path is
outcome C. It does NOT pre-judge O3+: a skeleton-load path (construct
`Qwen3NextModel` without loading all weights, then per-group materialize —
the validated L4-A/B per-group materializer) bypasses exactly this failing
step.

## Registered caveats (measurement honesty)

1. The 9-minute watchdog was a safety bound, not a proven impossibility
   bound: whether `loadWeights` would EVENTUALLY complete was not measured.
   What IS measured: 9 minutes of sustained thrash at 23 GiB swap with no
   completion — the stability boundary was already violated, so continuing
   on a shared machine was refused by design.
2. RSS from `ps` does not capture GPU-wired unified-memory allocations; the
   decisive evidence is the system swap curve plus the CPU signature, not
   RSS.
3. The in-probe snapshot mechanism (which would have captured
   `phys_footprint` precisely at each phase) never executed because the
   load phase itself hung — a probe improvement (periodic snapshot flush on
   a background task) is registered for any O2 re-run.
4. Swap totals fluctuated (23.5/24.6/23.5/24.6 GB totals across polls) —
   macOS dynamically resizes swap; the used-volume curve is the signal.

## Direct consequences for O3

1. The O2-B selective-touch experiment (mapped ≠ resident) was REACHED for
   pure arrays in earlier probe iterations but is now moot for the native
   path: the load phase materializes everything eagerly. The selective-
   touch question moves INTO O3 (does the skeleton-load path preserve
   non-residency of untouched groups?).
2. O3's skeleton-load path is now REQUIRED, not optional: the native path
   cannot serve as the oversized-model baseline. The O2 "baseline" for this
   model on this machine is: full-load = FAIL (measured).
3. The natural experimental boundary points remain core+1 group ≈ 14.8 GiB
   and core+2 groups ≈ 28.3 GiB — both below the wired limit; O3 should
   target these residency levels for the first skeleton-load + group-
   materialize + forward experiment.
```
```
