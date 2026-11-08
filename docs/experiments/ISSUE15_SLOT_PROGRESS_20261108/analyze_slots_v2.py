#!/usr/bin/env python3
"""Issue #15 Round-1 corrected analysis (v3 tooling, review 2026-11-08).

Rules:
- Progress is compared WITHIN one id_task; an id_task change starts a new
  observation baseline and never counts as a stall.
- Only BUSY samples enter a run; adjacent pairs are compared only when both
  ends are busy, so post-task idle can never leak into no-progress.
- Counters: prefill progress = n_prompt_tokens_processed; decode progress =
  slot.next_token[0].n_decoded (top-level n_decoded does not exist).
- TWO stall metrics, distinct:
    * adjacent_static_max_s — longest single sampling interval with no
      counter advance (sampling-tick bound);
    * cumulative_static_max_s — longest span from the last sample where any
      counter advanced to the sample where one next advanced. THIS is what a
      no-progress watchdog experiences (batched counter updates make it
      larger than the tick bound; observed ~4.04 s in prefill-heavy).
- Phase attribution: last mover before the span ("from_phase") and the mover
  that closes it ("to_phase"); a span with from=prefill/to=decode crosses the
  prefill→decode boundary. Spans by construction never cross id_task or
  busy boundaries — runs are split on both.
- Both counters advancing in one tick are accounted separately (no elif).
- Throughput: per-phase counter deltas over summed tick durations, method
  stated in output.
"""
import json
import sys
from pathlib import Path

EV = Path(sys.argv[1] if len(sys.argv) > 1 else "/private/tmp/fifteen/evidence")


def load(name):
    rows = []
    p = EV / f"samples_{name}.jsonl"
    for line in open(p):
        r = json.loads(line)
        if "slots" in r and r["slots"]:
            rows.append(r)
    return rows


def task_runs(seq):
    runs = []
    current = None
    for r in seq:
        s = r["slots"][0]
        tid = s["id_task"]
        busy = bool(s["is_processing"])
        if tid is None or not busy:
            if current:
                runs.append(current)
                current = None
            continue
        if current is None or current["id_task"] != tid:
            current = {"id_task": tid, "samples": []}
            runs.append(current)
        # observation time = when the Service actually RECEIVED this progress
        # view: the sample's response-completion stamp on the monotonic clock;
        # archived v2 data without t_mono_resp falls back to t (review
        # 2026-11-08: the collector provides the field, the analyzer must use
        # it — the clock loop has to close on both sides).
        current["samples"].append({
            "t": r.get("t_mono_resp", r["t"]),
            "t_resp_wall": r.get("t_resp"),
            "busy": busy,
            "np": s["n_prompt_tokens_processed"] or 0,
            "nd": s["n_decoded"],
        })
    if current:
        runs.append(current)
    return [r for r in runs if len(r["samples"]) >= 2]


def analyze_run(name):
    seq = load(name)
    runs = task_runs(seq)
    out = {"scenario": name, "tasks": []}
    max_adjacent = 0.0
    max_cumulative = 0.0
    max_span_info = None
    prefill_tokens = prefill_time = decode_tokens = decode_time = 0.0

    for run in runs:
        s = run["samples"]
        info = {
            "id_task": run["id_task"], "busy_samples": len(s),
            "adjacent_static_max_s": 0.0,
            "cumulative_static_max_s": 0.0,
            "spans": [],
        }
        prev = s[0]
        t_last_progress = s[0]["t"]
        last_phase = None
        open_span = None
        for cur in s[1:]:
            if not (prev["busy"] and cur["busy"]):
                if open_span is not None:
                    open_span["censored"] = True
                    open_span = None
                prev = cur
                continue
            dt = cur["t"] - prev["t"]
            d_np = cur["np"] - prev["np"]
            nd_known = prev["nd"] is not None and cur["nd"] is not None
            d_nd = (cur["nd"] - prev["nd"]) if nd_known else 0
            np_adv = d_np > 0
            nd_adv = nd_known and d_nd > 0

            if np_adv:
                prefill_tokens += d_np
                prefill_time += dt
            if nd_adv:
                decode_tokens += d_nd
                decode_time += dt

            if np_adv or nd_adv:
                to_phase = "prefill" if np_adv else "decode"
                if open_span is not None:
                    span_duration = cur["t"] - t_last_progress
                    open_span["duration_s"] = round(span_duration, 2)
                    open_span["to_phase"] = to_phase
                    info["spans"].append(open_span)
                    # the closing tick's own dt must count too — the span
                    # ends AT an advancing sample, and that sample's dt is
                    # part of the no-progress window (off-by-one-tick fix,
                    # review 2026-11-08: 3.54 -> 4.04 on prefill-heavy).
                    info["cumulative_static_max_s"] = round(
                        max(info["cumulative_static_max_s"], span_duration), 2)
                    open_span = None
                t_last_progress = cur["t"]
                last_phase = to_phase
                if d_np > 0 and d_nd > 0:
                    info["spans"].append({
                        "note": "both counters advanced in one tick",
                        "from_phase": "prefill", "to_phase": "decode"})
            else:
                if open_span is None:
                    open_span = {
                        "from_offset": round(t_last_progress - s[0]["t"], 2),
                        "from_phase": last_phase or "unknown",
                        "censored": False}
                span_now = cur["t"] - t_last_progress
                info["cumulative_static_max_s"] = round(
                    max(info["cumulative_static_max_s"], span_now), 2)
                info["adjacent_static_max_s"] = round(
                    max(info["adjacent_static_max_s"], dt), 2)
            prev = cur
        if open_span is not None:
            open_span["duration_s"] = round(prev["t"] - t_last_progress, 2)
            open_span["censored"] = True
            info["spans"].append(open_span)
        if info["cumulative_static_max_s"] > max_cumulative:
            max_cumulative = info["cumulative_static_max_s"]
            max_span_info = {"scenario": name, **{
                k: v for k, v in info.items() if k != "tasks"}}
        max_adjacent = max(max_adjacent, info["adjacent_static_max_s"])
        out["tasks"].append(info)

    out["totals"] = {
        "max_adjacent_static_s": round(max_adjacent, 2),
        "max_cumulative_static_s": round(max_cumulative, 2),
        "max_span": max_span_info,
        "prefill_throughput_tok_s": (round(prefill_tokens / prefill_time, 1)
                                     if prefill_time else None),
        "decode_throughput_tok_s": (round(decode_tokens / decode_time, 1)
                                    if decode_time else None),
        "method": ("adjacent = single sampling interval with no counter "
                   "advance; cumulative = span from the last sample where any "
                   "counter advanced to the next such sample (watchdog "
                   "metric). Spans never cross id_task or busy boundaries by "
                   "construction; censored spans were cut by run end."),
    }
    return out


def main():
    result = {}
    for name in ["normal", "decode_heavy", "prefill_heavy", "cancel",
                 "concurrent"]:
        if (EV / f"samples_{name}.jsonl").exists():
            result[name] = analyze_run(name)
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()
