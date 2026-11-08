#!/usr/bin/env python3
"""Analyze Issue #15 Round-1 slot samples: phase segmentation, no-progress
gaps, cancellation->idle latency, task transitions."""
import json
import sys
from pathlib import Path

EV = Path(sys.argv[1] if len(sys.argv) > 1 else "/private/tmp/fifteen/evidence_run1")


def load(name):
    rows = []
    with open(EV / f"samples_{name}.jsonl") as fh:
        for line in fh:
            rows.append(json.loads(line))
    return [r for r in rows if "slots" in r and r["slots"]]


def timeline(name):
    """Flatten to per-slot-0 timeline: t, id_task, processing, nprompt, ndecoded."""
    out = []
    for r in load(name):
        s = r["slots"][0]
        out.append({
            "t": r["t"], "id_task": s["id_task"], "busy": bool(s["is_processing"]),
            "nprompt": s["n_prompt_tokens_processed"] or 0,
            "ndecoded": s["n_decoded"] or 0,
        })
    return out


def gaps(seq, key):
    """Consecutive sample intervals where `key` did not advance while busy."""
    stalls = []
    for a, b in zip(seq, seq[1:]):
        if a["busy"] and b["busy"]:
            dt = b["t"] - a["t"]
            if b[key] == a[key]:
                stalls.append(dt)
    return stalls


def phases(seq):
    """Segment busy periods into prefill (prompt rising) / decode (decoded rising)."""
    marks = []
    for a, b in zip(seq, seq[1:]):
        if not (a["busy"] and b["busy"]):
            continue
        if b["nprompt"] > a["nprompt"]:
            marks.append((b["t"], "prefill"))
        elif b["ndecoded"] > a["ndecoded"]:
            marks.append((b["t"], "decode"))
    return marks


def busy_periods(seq):
    periods = []
    start = None
    for r in seq:
        if r["busy"] and start is None:
            start = r["t"]
        elif not r["busy"] and start is not None:
            periods.append((start, r["t"]))
            start = None
    if start is not None:
        periods.append((start, seq[-1]["t"]))
    return periods


def summarize(name):
    seq = timeline(name)
    if not seq:
        return {"scenario": name, "error": "no samples"}
    periods = busy_periods(seq)
    prefill_gaps = gaps(seq, "nprompt")
    decode_gaps = gaps(seq, "ndecoded")
    tasks = []
    for r in seq:
        if not tasks or tasks[-1] != r["id_task"]:
            tasks.append(r["id_task"])
    res = {
        "scenario": name,
        "samples": len(seq),
        "busy_periods": [
            {"start_offset": round(p0 - seq[0]["t"], 2),
             "duration": round(p1 - p0, 2)} for p0, p1 in periods],
        "id_task_sequence": tasks,
        "max_prefill_stall_s": round(max(prefill_gaps), 2) if prefill_gaps else 0,
        "max_decode_stall_s": round(max(decode_gaps), 2) if decode_gaps else 0,
        "p95_decode_stall_s": (round(sorted(decode_gaps)[int(len(decode_gaps) * .95) - 1], 3)
                               if len(decode_gaps) > 20 else None),
    }
    if name == "cancel":
        # busy->idle latency after the client closed: find the last busy sample
        # following the first idle->busy transition, then the next idle sample.
        busy_after_cancel = [r["t"] for r in seq if r["busy"]]
        if busy_after_cancel and len(seq) > 1:
            idle_after = [r["t"] for r in seq if not r["busy"] and r["t"] > busy_after_cancel[-1] - 999]
            after = [t for t in idle_after if t > max(busy_after_cancel) - 0.6]
            if after:
                res["cancel_to_idle_latency_s"] = round(min(after) - busy_after_cancel[-1] + 0.5, 2)
    return res


def main():
    out = {}
    for name in ["normal", "decode_heavy", "prefill_heavy", "cancel", "concurrent"]:
        p = EV / f"samples_{name}.jsonl"
        if p.exists():
            out[name] = summarize(name)
    print(json.dumps(out, indent=1))


if __name__ == "__main__":
    main()
