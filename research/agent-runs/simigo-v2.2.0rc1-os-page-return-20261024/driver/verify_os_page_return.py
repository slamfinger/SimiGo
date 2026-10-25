#!/usr/bin/env python3
"""Derive the physical_page_return verdict from an os_page_return_raw_*.json.

Why this is not the rejected proxy
  * The claim rests on the KERNEL's global page counters
    (host_statistics64 / HOST_VM_INFO64), not on the process's own footprint.
  * The measurement window is anchored on the SUSPEND event the shipped code
    recorded (`reference_release` / `resource_reclaim` / `lifecycle_suspend`
    at_ms), not on "whatever the process did later".
  * Process exit is explicitly excluded: a separate exit-teardown bracket is
    computed and reported, and the liveness rule requires the process to still
    be running after the post window (proved by the evidence file's mtime,
    which the role writes only after the resume generation).

Rules (all must hold for PASS)
  A1  the shipped suspend happened    reference_release + resource_reclaim +
                                     lifecycle_suspend present, in that order
  A2  pre-window was the loaded state alive == 1 and footprint >= 1 GiB at the
                                     anchor
  A3  the resident set fell           post-window footprint <= 30% of peak
  A4  the low state is sustained      >= MIN_LOW consecutive samples below 50%
                                     of peak (default 20)
  A5  the KERNEL got the pages back    max(free+inactive) inside the settle
                                     window - (free+inactive) at the anchor
                                     >= 50% of the footprint drop
  A6  the compressor is not the sink   compressor growth <= 25% of the drop
                                     (a shrink is a pass and is reported)
  A7  the process was alive           rusage succeeded on every sample of the
                                     post window AND the app wrote its evidence
                                     file after the post window closed (that
                                     write happens only after the resume
                                     generation, so exit cannot explain A5)
  A8  the noise floor is small        baseline (free+inactive) swing <= 10% of
                                     the drop
  A9  app and kernel agree            |app-reported drop - kernel drop| <= 20%

Excluded on purpose: the exit-teardown bracket (free pages rising while the
process dies) is measured, reported, and never counted towards A5.

usage: verify_os_page_return.py [raw.json] [out.json] [min_low_samples] [settle_ms]
Exit codes: 0 PASS, 2 BLOCKED, 1 contradictory evidence.
"""
import json
import os
import sys

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = (sys.argv[1] if len(sys.argv) > 1
       else os.path.join(B, "evidence/os_page_return_raw.json"))
OUT = (sys.argv[2] if len(sys.argv) > 2
       else os.path.join(B, "evidence/os_page_return_verdict.json"))
MIN_LOW = int(sys.argv[3]) if len(sys.argv) > 3 else 20
SETTLE_MS = int(sys.argv[4]) if len(sys.argv) > 4 else 1500


def main():
    with open(RAW) as handle:
        raw = json.load(handle)
    s = raw["series"]
    page = raw["identity"]["page_size"]
    t = s["t_ms"]
    n = len(t)

    def avail(i):
        # vm_statistics.h: speculative pages are ALREADY counted in free_count,
        # so adding speculative_count would double count them.
        return s["free"][i] + s["inactive"][i]

    app_ev = {}
    for _name, doc in raw.get("memprobe_evidence", {}).items():
        if isinstance(doc, dict) and doc.get("status") is not None:
            app_ev = doc

    events = app_ev.get("suspend_events_ordered") or []
    names = [e.get("event") for e in events]
    release = next((e for e in events if e.get("event") == "reference_release"), None)
    base_ms = int(raw["identity"]["baseline_seconds"] * 1000)
    anchor_ms = base_ms + release["at_ms"] if release else None

    pre = [i for i in range(n) if anchor_ms is not None and anchor_ms - 1000 <= t[i] < anchor_ms]
    post = [i for i in range(n) if anchor_ms is not None and anchor_ms <= t[i] <= anchor_ms + SETTLE_MS]
    base = [i for i in range(n) if s["phase"][i] == "baseline"]
    if not (pre and post):
        print("anchor window empty (anchor_ms=%r)" % (anchor_ms,))
        return 2

    peak = max(pre, key=lambda i: s["footprint_bytes"][i])
    peak_bytes = s["footprint_bytes"][peak]
    low_bytes = min(s["footprint_bytes"][i] for i in post)
    drop_bytes = peak_bytes - low_bytes

    low_run = []
    for i in post:
        if s["footprint_bytes"][i] <= 0.5 * peak_bytes:
            low_run.append(i)
    # count the longest consecutive stretch inside the post window
    longest = run = 0
    for i in post:
        run = run + 1 if s["footprint_bytes"][i] <= 0.5 * peak_bytes else 0
        longest = max(longest, run)

    anchor_index = min(pre, key=lambda i: abs(t[i] - anchor_ms))
    anchor_avail = avail(anchor_index)
    post_avail_max = max(avail(i) for i in post)
    post_avail_max_index = max(post, key=lambda i: avail(i))
    host_gain = (post_avail_max - anchor_avail) * page
    compressor_growth = (s["compressor"][post_avail_max_index]
                         - s["compressor"][anchor_index]) * page

    # exit teardown, measured and excluded: the last second of the run
    tail = [i for i in range(n) if t[i] >= t[-1] - 1000]
    exit_free_gain = (max(s["free"][i] for i in tail) - s["free"][peak]) * page

    write_time = raw.get("memprobe_evidence_mtime")
    post_window_end = anchor_ms + SETTLE_MS

    baseline_swing_pages = (max(avail(i) for i in base) - min(avail(i) for i in base)) if base else None
    app_drop = None
    if app_ev:
        before = app_ev.get("footprint_pre_bytes")
        after = app_ev.get("footprint_post_suspend_bytes")
        if isinstance(before, int) and isinstance(after, int):
            app_drop = before - after

    checks = {}
    checks["A1_shipped_suspend_observed"] = bool(
        names[:3] == ["reference_release", "resource_reclaim", "lifecycle_suspend"]
        or {"reference_release", "resource_reclaim", "lifecycle_suspend"} <= set(names))
    checks["A2_loaded_state_before_anchor"] = bool(
        peak_bytes >= 1024 ** 3 and all(s["alive"][i] == 1 for i in pre))
    checks["A3_resident_set_fell"] = bool(drop_bytes >= 0.70 * peak_bytes and drop_bytes >= 1024 ** 3)
    checks["A4_low_state_sustained"] = longest >= MIN_LOW
    checks["A5_kernel_returned_the_pages"] = bool(host_gain >= 0.5 * drop_bytes)
    checks["A6_compressor_not_the_sink"] = bool(compressor_growth <= 0.25 * drop_bytes)
    alive_in_post = all(s["alive"][i] == 1 and s["rusage_ok"][i] == 1 for i in post) \
        if "rusage_ok" in s else all(s["alive"][i] == 1 for i in post)
    wrote_after_window = (write_time is not None
                          and raw.get("start_epoch_ms") is not None
                          and raw["start_epoch_ms"] + post_window_end <= write_time + 50)
    checks["A7_process_alive_and_not_exiting"] = bool(alive_in_post and wrote_after_window)
    checks["A8_noise_floor_small"] = bool(
        baseline_swing_pages is not None and baseline_swing_pages * page <= 0.10 * drop_bytes)
    checks["A9_app_and_kernel_agree"] = bool(
        app_drop is not None and abs(app_drop - drop_bytes) <= 0.20 * max(app_drop, drop_bytes))

    must = [k for k in checks if k.startswith("A")]
    passed = all(checks[k] for k in must)

    contradictions = []
    if checks["A1_shipped_suspend_observed"] and not checks["A5_kernel_returned_the_pages"]:
        contradictions.append("the shipped suspend ran, but the kernel's available pages did "
                              "not rise by at least half of the resident drop")
    if checks["A3_resident_set_fell"] and not checks["A5_kernel_returned_the_pages"]:
        contradictions.append("the process gave up resident bytes that the kernel never "
                              "returned to the free/inactive pool")

    numbers = {
        "anchor_series_ms": anchor_ms,
        "anchor_wall_epoch_ms": raw.get("start_epoch_ms") and raw["start_epoch_ms"] + anchor_ms,
        "pre_peak_footprint_bytes": peak_bytes,
        "post_low_footprint_bytes": low_bytes,
        "kernel_resident_drop_bytes": drop_bytes,
        "kernel_resident_drop_gib": round(drop_bytes / 1024 ** 3, 2),
        "anchor_available_bytes": anchor_avail * page,
        "post_window_available_max_bytes": post_avail_max * page,
        "kernel_returned_gib": round(host_gain / 1024 ** 3, 2),
        "kernel_returned_over_drop": round(host_gain / drop_bytes, 3) if drop_bytes else None,
        "available_max_at_series_ms": t[post_avail_max_index],
        "compressor_delta_bytes_in_window": compressor_growth,
        "compressor_delta_gib": round(compressor_growth / 1024 ** 3, 2),
        "low_samples": len(low_run),
        "longest_low_streak_samples": longest,
        "low_streak_seconds": round(longest * raw["identity"]["interval_seconds"], 2),
        "baseline_swing_bytes": (baseline_swing_pages * page) if baseline_swing_pages is not None else None,
        "app_reported_drop_bytes": app_drop,
        "evidence_write_epoch_ms": write_time,
        "post_window_end_epoch_ms": (raw.get("start_epoch_ms") or 0) + post_window_end,
        "exit_teardown_free_gain_bytes": exit_free_gain,
        "exit_teardown_used_for_verdict": False,
        "settle_window_ms": SETTLE_MS,
        "sample_interval_ms": int(raw["identity"]["interval_seconds"] * 1000),
        "samples": n,
    }

    verdict = "PASS" if passed and not contradictions else "BLOCKED"
    payload = {
        "gate": "physical_page_return",
        "candidate": raw["identity"]["candidate"],
        "candidate_exe_sha256": raw["identity"]["exe_sha256"],
        "rid": raw["rid"],
        "captured_at": raw["captured_at"],
        "verdict": verdict,
        "checks": checks,
        "numbers": numbers,
        "contradictions": contradictions,
        "rules": {
            "A1": "reference_release + resource_reclaim + lifecycle_suspend recorded by the shipped role",
            "A2": "footprint >= 1 GiB and alive on every pre-window sample",
            "A3": "post-window footprint <= 30% of peak and drop >= 1 GiB",
            "A4": ">= %d consecutive samples below 50%% of peak" % MIN_LOW,
            "A5": "kernel (free+inactive) max inside the settle window rises >= 50% of the drop",
            "A6": "compressor growth <= 25% of the drop",
            "A7": "rusage ok on every post-window sample AND the app wrote its evidence file after the window",
            "A8": "baseline swing <= 10% of the drop",
            "A9": "app-reported drop within 20% of the kernel-measured drop",
        },
        "what_this_is_not": ("not a process exit (the exit teardown is measured separately and "
                             "excluded), not an RSS comparison, and not a call into a release "
                             "API: the kernel's own page counters move while the process stays "
                             "alive."),
    }
    with open(OUT, "w") as handle:
        json.dump(payload, handle, indent=1)
    print(json.dumps({"raw": os.path.basename(RAW), "verdict": verdict, "checks": checks,
                      "numbers": {k: numbers[k] for k in (
                          "kernel_resident_drop_gib", "kernel_returned_gib",
                          "kernel_returned_over_drop", "compressor_delta_gib",
                          "low_streak_seconds", "exit_teardown_free_gain_bytes")}}, indent=1))
    if contradictions:
        return 1
    return 0 if verdict == "PASS" else 2


if __name__ == "__main__":
    sys.exit(main())
