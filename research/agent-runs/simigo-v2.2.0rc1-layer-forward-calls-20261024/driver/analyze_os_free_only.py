#!/usr/bin/env python3
"""Exploratory, NON-BINDING decomposition of the page-return gain.

A5 counts `free + inactive`. The operator raised a methodological concern: pages
the target process just released but the kernel has not yet reclaimed sit in
inactive and would be counted as "returned to the pool". This script puts that
concern to arithmetic instead of leaving it as a plausible-sounding argument: it
measures, for each recorded trial, how much of the gain came from each bucket,
using the SAME anchor and settle window the verifier used, so the numbers are
comparable to the verdict they decompose.

It does not create a rule and it does not re-decide anything:
  * `binding: false`, `pre_registered: false`
  * no threshold is applied to the free-only ratio
  * verdicts for these trials stay exactly as their own verifier run wrote them

If a free-only criterion is ever to be used to PASS a gate, it has to be written
down BEFORE the run it scores (see evidence/os_page_return_preregistration_next.json).

usage: analyze_os_free_only.py [rid ...]     default: os3 os4 os5 os5b os5c
Exit codes: 0 written, 3 a raw record is missing.
"""
import hashlib
import json
import os
import sys

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OTHER_BATCH = ("/Users/mr.simi/SimiGo-Agent-Runs/"
               "simigo-v2.2.0rc1-os-page-return-20261024/evidence")
OUT = os.path.join(B, "evidence/os_page_return_free_only_exploratory.json")


def raw_path(rid):
    for base in (os.path.join(B, "evidence"), OTHER_BATCH):
        p = os.path.join(base, "os_page_return_raw_%s.json" % rid)
        if os.path.exists(p):
            return p
    return None


def verdict_path(rid):
    for base in (os.path.join(B, "evidence"), OTHER_BATCH):
        p = os.path.join(base, "os_page_return_verdict_%s.json" % rid)
        if os.path.exists(p):
            return p
    return None


def decompose(rid, settle_ms):
    path = raw_path(rid)
    if not path:
        return {"rid": rid, "error": "raw record missing"}
    with open(path, "rb") as handle:
        digest = hashlib.sha256(handle.read()).hexdigest()
    raw = json.loads(open(path).read())
    vpath = verdict_path(rid)
    verdict = json.load(open(vpath)) if vpath else {}
    # the window the trial was actually scored with, not the default of this script
    settle_ms = (verdict.get("numbers") or {}).get("settle_window_ms", settle_ms)
    s, page = raw["series"], raw["identity"]["page_size"]
    t = s["t_ms"]
    base_ms = int(raw["identity"]["baseline_seconds"] * 1000)
    ev = {}
    for doc in (raw.get("memprobe_evidence") or {}).values():
        if isinstance(doc, dict) and doc.get("status") is not None:
            ev = doc
    events = ev.get("suspend_events_ordered") or []
    release = next((e for e in events if e.get("event") == "reference_release"), None)
    if release is None:
        return {"rid": rid, "error": "no reference_release event in the record"}
    anchor_ms = base_ms + release["at_ms"]
    pre = [i for i in range(len(t)) if anchor_ms - 1000 <= t[i] < anchor_ms]
    post = [i for i in range(len(t)) if anchor_ms <= t[i] <= anchor_ms + settle_ms]
    if not (pre and post):
        return {"rid": rid, "error": "anchor window empty"}

    peak = max(pre, key=lambda i: s["footprint_bytes"][i])
    drop_bytes = s["footprint_bytes"][peak] - min(s["footprint_bytes"][i] for i in post)
    anchor_index = min(pre, key=lambda i: abs(t[i] - anchor_ms))

    free_at_anchor = s["free"][anchor_index]
    inact_at_anchor = s["inactive"][anchor_index]
    free_max = max(s["free"][i] for i in post)
    inact_max = max(s["inactive"][i] for i in post)
    inact_min = min(s["inactive"][i] for i in post)
    both_max = max(s["free"][i] + s["inactive"][i] for i in post)
    free_gain = (free_max - free_at_anchor) * page
    inact_gain = (inact_max - inact_at_anchor) * page
    both_gain = (both_max - (free_at_anchor + inact_at_anchor)) * page
    inact_drain = (inact_at_anchor - inact_min) * page

    return {
        "rid": rid,
        "candidate_exe_sha256_12": (verdict.get("candidate_exe_sha256") or "")[:12],
        "verdict_as_written": verdict.get("verdict"),
        "a5_ratio_as_scored": (verdict.get("numbers") or {}).get("kernel_returned_over_drop"),
        "raw_sha256": digest,
        "settle_window_ms": settle_ms,
        "kernel_resident_drop_bytes": drop_bytes,
        "host_state_at_anchor": {
            "free_bytes": free_at_anchor * page,
            "inactive_bytes": inact_at_anchor * page,
            "free_plus_inactive_bytes": (free_at_anchor + inact_at_anchor) * page,
        },
        "host_state_in_window": {
            "free_peak_bytes": free_max * page,
            "inactive_peak_bytes": inact_max * page,
            "inactive_trough_bytes": inact_min * page,
            "free_plus_inactive_peak_bytes": both_max * page,
            "inactive_drained_in_window_bytes": inact_drain,
        },
        "gain_free_only_bytes": free_gain,
        "gain_inactive_only_bytes": inact_gain,
        "gain_free_plus_inactive_bytes": both_gain,
        "ratio_free_only": round(free_gain / drop_bytes, 6),
        "ratio_inactive_only": round(inact_gain / drop_bytes, 6),
        "ratio_free_plus_inactive": round(both_gain / drop_bytes, 6),
        "share_of_gain_from_inactive": round(inact_gain / both_gain, 4) if both_gain else None,
    }


def main():
    settle = int(os.environ.get("OS_PROBE_SETTLE_MS", "1500"))
    rids = sys.argv[1:] or ["os3", "os4", "os5", "os5b", "os5c"]
    rows = [decompose(r, settle) for r in rids]
    bad = [r for r in rows if r.get("error")]
    if bad:
        print(json.dumps(bad, indent=1), file=sys.stderr)
        return 3
    shares = [r["share_of_gain_from_inactive"] for r in rows
              if r.get("share_of_gain_from_inactive") is not None]
    free_only = [r["ratio_free_only"] for r in rows if r.get("ratio_free_only") is not None]
    scored = [r["ratio_free_plus_inactive"] for r in rows
              if r.get("ratio_free_plus_inactive") is not None]
    drops = [r["kernel_resident_drop_bytes"] for r in rows
             if r.get("kernel_resident_drop_bytes")]
    payload = {
        "purpose": ("how much of the capacity A5 credits to the kernel is really just the "
                    "target's own not-yet-reclaimed inactive pages"),
        "binding": False,
        "pre_registered": False,
        "windows": "same anchor (reference_release.at_ms) and same settle window as the verifier",
        "trials": rows,
        "headline": {
            "inactive_share_of_gain_min": round(min(shares), 4) if shares else None,
            "inactive_share_of_gain_max": round(max(shares), 4) if shares else None,
            "ratio_free_plus_inactive_range": [min(scored), max(scored)] if scored else None,
            "ratio_free_only_range": [min(free_only), max(free_only)] if free_only else None,
            "kernel_resident_drop_range_bytes": [min(drops), max(drops)] if drops else None,
            "hypothesis_tested": ("free+inactive over-credits the kernel by counting pages the "
                                  "target released that the kernel has not reclaimed yet"),
            "hypothesis_result": (
                "NOT supported by these records. The inactive component contributes "
                f"{round(max(shares), 4) if shares else 'n/a'} at most of the scored gain, because "
                "inactive falls during the settle window instead of rising: the host arrives at "
                "the anchor with a nearly empty free pool (~0.13-0.25 GiB) and a large "
                "pre-existing inactive backlog (~13 GiB), and reclaiming that backlog is what "
                "fills free. free+inactive therefore nets the backlog off and is the CONSERVATIVE "
                "of the two readings."),
            "free_only_direction_if_adopted": (
                "looser, not stricter: free-only lands at ~0.997-0.998 of the drop on the same "
                "records where free+inactive scores 0.4965-0.5173. Switching to it after seeing "
                "BLOCKED trials would move the goalpost in the passing direction."),
            "what_the_numbers_actually_track": (
                "gain = peak(free+inactive) - anchor(free+inactive). Across the five trials the "
                "resident drop is stable (~16.1 GiB) while the gain spans ~8.00-8.34 GiB and the "
                "threshold is ~8.05 GiB, i.e. the 0.50 line sits INSIDE the trial-to-trial spread "
                "and the starting pool state of the host is in the measurement. That is why the "
                "remedy registered for future claims is repetition on the same executable, not a "
                "different numerator."),
        },
        "not_claimed": [
            "no verdict is re-decided here; each trial keeps what its own verifier run wrote",
            "the free-only ratio is reported without a threshold on purpose",
            "adopting free-only after seeing these numbers would be moving the goalposts; it "
            "can only be used if it is registered before a future run",
            "this is a decomposition of already-recorded bytes, not a new experiment",
            "no claim here says the product did or did not return pages; A1-A9 carry that",
        ],
    }
    with open(OUT, "w") as handle:
        json.dump(payload, handle, indent=1, sort_keys=True)
        handle.write("\n")
    print(json.dumps({"trials": {r["rid"]: {"verdict_as_written": r["verdict_as_written"],
                                            "a5": r["ratio_free_plus_inactive"],
                                            "free_only": r["ratio_free_only"],
                                            "inactive_share": r["share_of_gain_from_inactive"]}
                              for r in rows},
                      "out": os.path.relpath(OUT, B)}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
