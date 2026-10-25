#!/usr/bin/env python3
"""Side-by-side page-return trials, without re-scoring any of them.

The question this answers is narrow: on the CURRENT candidate (83a880…) the same
pre-registered experiment was run more than once, and on the PREVIOUS candidate
(95224f06…) it failed A5 by 6,920,060 B while another build (60973e08…) passed.
Because A5 is a ratio against 0.50, one trial near the line tells you little
unless you know how far trials of the *same* binary move.

Rules are not touched here. Ratios are recomputed from byte counts (the verdict
field is rounded to 3 decimals and would show 0.4996 as 0.500), each trial keeps
the verdict its own verifier run produced, and nothing is averaged into a verdict.

usage: compare_os_trials.py [rid ...]      default: os4 os5
Exit codes: 0 written, 3 a verdict/record is missing.
"""
import hashlib
import json
import os
import sys

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OTHER_BATCH = ("/Users/mr.simi/SimiGo-Agent-Runs/"
               "simigo-v2.2.0rc1-os-page-return-20261024/evidence")
A5_NUM, A5_DEN = 1, 2  # unchanged pre-registered rule: gain >= 0.5 * drop
OUT = os.path.join(B, "evidence/os_page_return_trial_dispersion.json")


def paths(rid):
    for base in (os.path.join(B, "evidence"), OTHER_BATCH):
        v = os.path.join(base, "os_page_return_verdict_%s.json" % rid)
        r = os.path.join(base, "os_page_return_raw_%s.json" % rid)
        if os.path.exists(v) and os.path.exists(r):
            return v, r
    return None, None


def sha256_of(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def trial(rid):
    vpath, rpath = paths(rid)
    if not vpath:
        return {"rid": rid, "error": "verdict or raw record missing"}
    doc, raw = json.load(open(vpath)), json.load(open(rpath))
    n = doc["numbers"]
    drop = n["kernel_resident_drop_bytes"]
    gain = n["post_window_available_max_bytes"] - n["anchor_available_bytes"]
    threshold = drop * A5_NUM // A5_DEN
    return {
        "rid": rid,
        "verdict": doc["verdict"],
        "candidate_exe_sha256": doc["candidate_exe_sha256"],
        "candidate_exe_sha256_12": doc["candidate_exe_sha256"][:12],
        "captured_at": raw.get("captured_at"),
        "sample_interval_ms": n["sample_interval_ms"],
        "settle_window_ms": n["settle_window_ms"],
        "samples": n["samples"],
        "kernel_resident_drop_bytes": drop,
        "kernel_returned_bytes": gain,
        "a5_threshold_bytes": threshold,
        "margin_bytes_to_a5": gain - threshold,
        "ratio_recomputed_from_bytes": gain / drop,
        "ratio_field_in_verdict": n["kernel_returned_over_drop"],
        "low_streak_seconds": n["low_streak_seconds"],
        "exit_teardown_used_for_verdict": n["exit_teardown_used_for_verdict"],
        "process_alive_during_window": doc["checks"]["A7_process_alive_and_not_exiting"],
        "verdict_sha256": sha256_of(vpath),
        "raw_sha256": sha256_of(rpath),
    }


def main():
    rids = sys.argv[1:] or ["os4", "os5"]
    rows = [trial(r) for r in rids]
    bad = [r for r in rows if r.get("error")]
    if bad:
        print(json.dumps(bad, indent=1), file=sys.stderr)
        return 3

    by_binary = {}
    for r in rows:
        by_binary.setdefault(r["candidate_exe_sha256"], []).append(r)

    groups = []
    for exe, items in sorted(by_binary.items()):
        ratios = [i["ratio_recomputed_from_bytes"] for i in items]
        margins = [i["margin_bytes_to_a5"] for i in items]
        groups.append({
            "candidate_exe_sha256": exe,
            "trials": [i["rid"] for i in items],
            "verdicts": {i["rid"]: i["verdict"] for i in items},
            "ratio_min": round(min(ratios), 6),
            "ratio_max": round(max(ratios), 6),
            "ratio_spread": round(max(ratios) - min(ratios), 6),
            "margin_bytes_min": min(margins),
            "margin_bytes_max": max(margins),
            "margin_bytes_spread": max(margins) - min(margins),
            "same_binary_repeat": len(items) > 1,
        })

    payload = {
        "purpose": ("how far do page-return trials move, so a single number "
                    "next to 0.50 is read with its spread instead of as a verdict "
                    "about the product"),
        "rule_unchanged": True,
        "threshold": "gain >= 0.5 * drop (A5_NUM/A5_DEN), integer bytes",
        "recomputation": ("ratio and margin are recomputed from byte counts; the verdict "
                          "field kernel_returned_over_drop is rounded to 3 decimals"),
        "trials": rows,
        "groups_by_binary": groups,
        "not_claimed": [
            "no verdict is averaged, overwritten or re-decided here",
            "a pass in one trial is not a pass in the ledger; the ledger stays BLOCKED",
            "the observation window is the pre-registered settle window, not a longer one",
            "free+inactive as available capacity still counts the target's own inactive "
            "pages, which is why a free-only criterion was recommended before any rerun",
        ],
    }
    with open(OUT, "w") as handle:
        json.dump(payload, handle, indent=1, sort_keys=True)
        handle.write("\n")
    print(json.dumps({
        "trials": {r["rid"]: {"verdict": r["verdict"],
                              "ratio": round(r["ratio_recomputed_from_bytes"], 6),
                              "margin_bytes": r["margin_bytes_to_a5"],
                              "binary": r["candidate_exe_sha256_12"]} for r in rows},
        "groups": [{"binary": g["candidate_exe_sha256"][:12], "trials": g["trials"],
                    "ratio_spread": g["ratio_spread"],
                    "margin_spread_bytes": g["margin_bytes_spread"]} for g in groups],
        "out": os.path.relpath(OUT, B),
    }, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
