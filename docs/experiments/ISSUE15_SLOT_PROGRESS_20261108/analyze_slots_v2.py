#!/usr/bin/env python3
"""Issue #15 Round-1 corrected analysis.

Rules (per the 2026-11-08 review):
- Progress is compared WITHIN one id_task; an id_task change starts a new
  observation baseline and never counts as a stall.
- Counters: prefill progress = n_prompt_tokens_processed (top level); decode
  progress = next_token[0].n_decoded (b11720 schema; top-level n_decoded does
  not exist). A missing next_token on a busy slot means "no decode token this
  tick" — during prefill that is normal, not decode evidence.
- Phase attribution: a pair is prefill if the prompt counter advanced, decode
  if only n_decoded advanced, transition-static if neither advanced (reported
  separately with its duration — NOT silently merged into stall numbers).
- A stall candidate = consecutive busy samples, same id_task, neither counter
  advanced. Reported per task with phase context (last counter that moved).
- Throughput: computed from counter deltas over busy time, method stated.
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
    """Split the timeline into maximal runs of one non-null id_task."""
    runs = []
    current = None
    for r in seq:
        s = r["slots"][0]
        tid = s["id_task"]
        if tid is None:
            if current:
                runs.append(current)
                current = None
            continue
        if current is None or current["id_task"] != tid:
            current = {"id_task": tid, "samples": []}
            runs.append(current)
        current["samples"].append({
            "t": r["t"],
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
    max_static = 0.0
    max_transition = 0.0
    prefill_tokens = 0
    prefill_time = 0.0
    decode_tokens = 0
    decode_time = 0.0

    for run in runs:
        s = run["samples"]
        info = {"id_task": run["id_task"], "busy_samples": len(s),
                "static_max_s": 0.0, "static_at": None,
                "transitions": [], "last_phase": None}
        prev = s[0]
        for cur in s[1:]:
            dt = cur["t"] - prev["t"]
            np_adv = cur["np"] > prev["np"]
            nd_adv = (prev["nd"] is not None and cur["nd"] is not None
                      and cur["nd"] > prev["nd"])
            if np_adv:
                phase = "prefill"
                prefill_tokens += cur["np"] - prev["np"]
                prefill_time += dt
            elif nd_adv:
                phase = "decode"
                decode_tokens += cur["nd"] - prev["nd"]
                decode_time += dt
            else:
                phase = info["last_phase"] or "unknown"
                info["static_max_s"] = round(max(info["static_max_s"], dt), 2)
                if dt > max_static:
                    max_static = dt
                    out["max_static_context"] = {
                        "id_task": run["id_task"], "at_t": round(cur["t"], 2),
                        "duration_s": round(dt, 2),
                        "last_phase": phase,
                        "nd_known": prev["nd"] is not None}
                if prev["nd"] is None or cur["nd"] is None:
                    # no decode token visible this tick: boundary/transition
                    # region (prefill ending or first token pending) — reported
                    # separately from same-phase stalls.
                    max_transition = max(max_transition, dt)
                    info["transitions"].append(round(dt, 2))
                prev = cur
                continue
            info["last_phase"] = phase
            prev = cur
        if prev is not None:
            info["last_counters"] = {"np": prev["np"], "nd": prev["nd"]}
        out["tasks"].append(info)

    out["totals"] = {
        "max_static_same_task_s": round(max_static, 2),
        "max_transition_region_s": round(max_transition, 2),
        "prefill_throughput_tok_s": (round(prefill_tokens / prefill_time, 1)
                                     if prefill_time else None),
        "decode_throughput_tok_s": (round(decode_tokens / decode_time, 1)
                                    if decode_time else None),
        "method": ("sum of per-tick counter deltas divided by summed tick "
                   "durations, within same-id_task runs; prefill attributed "
                   "when n_prompt_tokens_processed advanced, decode when "
                   "next_token[0].n_decoded advanced"),
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
