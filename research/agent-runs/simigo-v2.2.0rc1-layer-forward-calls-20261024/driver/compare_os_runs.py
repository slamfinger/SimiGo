#!/usr/bin/env python3
"""Put the two page-return runs side by side, without re-scoring either one.

os3 was judged PASS on the previous candidate (60973e08…); os4 is this batch's
run on the new candidate (95224f06…), judged by the SAME pre-registered rules.
os4 fails A5 by 0.04 percentage points. This script exists so that fact is
stated with its arithmetic and not smoothed into "roughly the same".

It does not re-decide anything: it reads the two verdict documents the verifier
wrote and reports the margin to the threshold. The margin is recomputed from the
byte counts, not from the rounded `kernel_returned_over_drop` field, because that
field is rounded to 3 decimals and would hide exactly the difference at issue
(0.4996 -> 0.500). Nothing here changes a verdict.

usage: compare_os_runs.py
Exit codes: 0 written, 3 input missing.
"""
import hashlib
import json
import os
import sys

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OS3 = ("/Users/mr.simi/SimiGo-Agent-Runs/"
       "simigo-v2.2.0rc1-os-page-return-20261024/evidence/os_page_return_verdict_os3.json")
OS3_RAW = os.path.join(os.path.dirname(OS3), "os_page_return_raw_os3.json")
OS4 = os.path.join(B, "evidence/os_page_return_verdict_os4.json")
OS4_RAW = os.path.join(B, "evidence/os_page_return_raw_os4.json")
OUT = os.path.join(B, "evidence/os_page_return_cross_candidate.json")
A5_NUM, A5_DEN = 1, 2  # A5: host_gain >= 0.5 * drop_bytes, integer comparison


def sha256_of(path):
    if not os.path.exists(path):
        return None
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def pick(doc, raw_path):
    n = doc["numbers"]
    returned = n["post_window_available_max_bytes"] - n["anchor_available_bytes"]
    drop = n["kernel_resident_drop_bytes"]
    threshold_bytes = drop * A5_NUM // A5_DEN
    return {
        "verdict": doc["verdict"],
        "checks_a5": doc["checks"]["A5_kernel_returned_the_pages"],
        "candidate": doc["candidate"],
        "candidate_exe_sha256": doc["candidate_exe_sha256"],
        # os4's verdict carries the raw sha it was derived from; the os3 verdict
        # predates that field, so its raw bytes are hashed here, read-only.
        "raw_file": doc.get("raw_file") or os.path.basename(raw_path),
        "raw_sha256_recorded_by_verifier": doc.get("raw_sha256"),
        "raw_sha256": doc.get("raw_sha256") or sha256_of(raw_path),
        "kernel_resident_drop_bytes": drop,
        "kernel_resident_drop_gib": drop / 1024 ** 3,
        "anchor_available_bytes": n["anchor_available_bytes"],
        "anchor_available_gib": n["anchor_available_bytes"] / 1024 ** 3,
        "post_window_available_max_bytes": n["post_window_available_max_bytes"],
        "post_window_available_max_gib": n["post_window_available_max_bytes"] / 1024 ** 3,
        "kernel_returned_bytes_recomputed": returned,
        "kernel_returned_gib_recomputed": returned / 1024 ** 3,
        "kernel_returned_over_drop_recomputed": returned / drop,
        "kernel_returned_over_drop_as_stored": n["kernel_returned_over_drop"],
        "a5_threshold_bytes": threshold_bytes,
        "margin_bytes_to_a5": returned - threshold_bytes,
        "compressor_delta_bytes_in_window": n["compressor_delta_bytes_in_window"],
        "baseline_swing_bytes": n["baseline_swing_bytes"],
        "app_reported_drop_bytes": n["app_reported_drop_bytes"],
        "low_streak_seconds": n["low_streak_seconds"],
        "low_samples": n["low_samples"],
        "samples": n["samples"],
        "exit_teardown_free_gain_bytes": n["exit_teardown_free_gain_bytes"],
        "exit_teardown_used_for_verdict": n["exit_teardown_used_for_verdict"],
    }


def main():
    if not (os.path.exists(OS3) and os.path.exists(OS4)):
        print("missing one of the two verdicts", file=sys.stderr)
        return 3
    a = pick(json.load(open(OS3)), OS3_RAW)
    b = pick(json.load(open(OS4)), OS4_RAW)

    delta = {
        "ratio_difference": (b["kernel_returned_over_drop_recomputed"]
                             - a["kernel_returned_over_drop_recomputed"]),
        "ratio_difference_percentage_points": 100 * (
            b["kernel_returned_over_drop_recomputed"]
            - a["kernel_returned_over_drop_recomputed"]),
        "kernel_returned_bytes_difference": (b["kernel_returned_bytes_recomputed"]
                                             - a["kernel_returned_bytes_recomputed"]),
        "kernel_resident_drop_bytes_difference": (b["kernel_resident_drop_bytes"]
                                                  - a["kernel_resident_drop_bytes"]),
        "relative_kernel_returned_difference": (
            (b["kernel_returned_bytes_recomputed"]
             - a["kernel_returned_bytes_recomputed"])
            / a["kernel_returned_bytes_recomputed"]),
        "margin_bytes_difference": b["margin_bytes_to_a5"] - a["margin_bytes_to_a5"],
    }

    payload = {
        "purpose": ("show that os4 fails A5 by a margin far smaller than the run-to-run "
                    "variation of the quantities A5 is built from, and that no rule was "
                    "changed to accommodate it"),
        "a5_definition": ("max(free+inactive) inside the settle window minus (free+inactive) "
                          "at the anchor, over the process's kernel-resident drop; "
                          "A5 passes when that ratio is >= 0.50 (verifier compares "
                          "bytes: host_gain >= drop_bytes // 2)"),
        "rounding_note": ("the stored kernel_returned_over_drop is the ratio rounded to 3 "
                          "decimals; both margins below are recomputed from raw bytes, so "
                          "os4's stored 0.500 does not mean it reached the threshold"),
        "known_bias": ("the pool metric counts the process's own inactive pages, so it "
                       "structurally saturates near 0.5x of the drop - the threshold sits "
                       "inside its own artefact band, which is why os3's 0.508 passed while "
                       "os4's 0.4996 did not"),
        "os3_previous_candidate": a,
        "os4_new_candidate": b,
        "delta": delta,
        "what_this_does_not_say": ("it does not say the pages were not returned on the new "
                                   "candidate: A6 (compressor is not the sink), A7 (process "
                                   "alive, evidence written after the window), A9 (app and "
                                   "kernel agree to ~0.06%) and the free-pool numbers all "
                                   "point the same way. It says the pre-registered rule did "
                                   "not clear its own threshold on this run, so the gate "
                                   "stays BLOCKED for this candidate."),
        "rule_changed": False,
        "threshold_changed": False,
        "recommended_next_step": ("pre-register a free-pool-only criterion (free gain over "
                                  "the drop, instead of free+inactive) and re-run; that "
                                  "metric does not count the process's own inactive pages as "
                                  "returned capacity - but adopting it now, after seeing os4 "
                                  "miss by ~0.04 points, would be moving the goalposts. It "
                                  "has to be decided and registered before the next run."),
    }
    with open(OUT, "w") as handle:
        json.dump(payload, handle, indent=1)
        handle.write("\n")
    print(json.dumps({
        "os3": {"verdict": a["verdict"],
                "ratio": round(a["kernel_returned_over_drop_recomputed"], 6),
                "margin_bytes": a["margin_bytes_to_a5"]},
        "os4": {"verdict": b["verdict"],
                "ratio": round(b["kernel_returned_over_drop_recomputed"], 6),
                "margin_bytes": b["margin_bytes_to_a5"]},
        "ratio_difference_pp": round(delta["ratio_difference_percentage_points"], 4),
        "relative_returned_difference": round(delta["relative_kernel_returned_difference"], 6),
    }, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
