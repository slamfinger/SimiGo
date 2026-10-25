#!/usr/bin/env python3
"""Write evidence/physical_page_return_gate_addendum.json.

This file is the ONLY thing this batch offers to the v2.2.0rc1 acceptance ledger.
It is generated, not hand-written: every number is copied out of the os3 verdict
that driver/verify_os_page_return.py produced, and both source files are hashed
here so a reader can prove the addendum still describes them.

It deliberately does NOT touch the ledger. simigo-v2.2.0rc1-local-acceptance-
20261024/acceptance_report.json keeps its own counts (12 PASS / 3 BLOCKED /
0 FAIL / 1 NOT_INSTRUMENTED) until a separately authorised run feeds this
addendum into that batch's generator and re-runs its verifier.
"""
import hashlib
import json
import os
import sys
import time

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERDICT = os.path.join(B, "evidence/os_page_return_verdict_os3.json")
RAW = os.path.join(B, "evidence/os_page_return_raw_os3.json")
OUT = os.path.join(B, "evidence/physical_page_return_gate_addendum.json")


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    with open(VERDICT) as handle:
        v = json.load(handle)
    with open(RAW) as handle:
        raw = json.load(handle)
    if v["verdict"] != "PASS":
        print("refusing to write an addendum for a non-PASS verdict (%s)" % v["verdict"])
        return 2

    n = v["numbers"]
    payload = {
        "gate": "physical_page_return",
        "batch": os.path.basename(B),
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "applies_to_candidate": {
            "exe_sha256": v["candidate_exe_sha256"],
            "app_path": v["candidate"],
            "note": "the installed candidate built for the Service/HTTP batch; this batch changed no source",
        },
        "verdict": v["verdict"],
        "derived_from": {
            "verdict_file": "evidence/os_page_return_verdict_os3.json",
            "verdict_sha256": sha(VERDICT),
            "raw_file": "evidence/os_page_return_raw_os3.json",
            "raw_sha256": sha(RAW),
            "raw_captured_at": raw.get("captured_at"),
            "raw_samples": len(raw["series"]["t_ms"]),
            "sample_interval_ms": int(raw["identity"]["interval_seconds"] * 1000),
        },
        "checks": v["checks"],
        "numbers": {k: n[k] for k in (
            "kernel_resident_drop_gib", "kernel_returned_gib", "kernel_returned_over_drop",
            "compressor_delta_gib", "low_streak_seconds", "baseline_swing_bytes",
            "app_reported_drop_bytes", "kernel_resident_drop_bytes",
            "evidence_write_epoch_ms", "post_window_end_epoch_ms",
            "exit_teardown_free_gain_bytes", "exit_teardown_used_for_verdict")},
        "why_this_is_os_level": (
            "host_statistics64(HOST_VM_INFO64) is the kernel's own global page accounting "
            "(the numbers vm_stat prints); the process is proven alive at every sample and its "
            "evidence file is written after the measurement window, so neither a process exit "
            "nor a call into a release API can explain the free-pool gain. The exit-teardown "
            "bracket is measured separately and excluded."),
        "ledger_state": {
            "ledger_file": "simigo-v2.2.0rc1-local-acceptance-20261024/acceptance_report.json",
            "modified_by_this_batch": False,
            "current_counts": {"PASS": 12, "BLOCKED": 3, "FAIL": 0, "NOT_INSTRUMENTED": 1},
            "current_physical_page_return_verdict": "BLOCKED",
            "counts_if_applied_by_an_authorised_regeneration": {
                "PASS": 13, "BLOCKED": 2, "FAIL": 0, "NOT_INSTRUMENTED": 1},
            "how_to_apply": (
                "feed this addendum into the local-acceptance batch's report generator as an "
                "input, regenerate acceptance_report.json, re-run that batch's verifier and "
                "verify_manifest.sh; do not hand-edit the JSON."),
        },
        "does_not_close": [
            "product_gui_ordinary_prompt: still BLOCKED_PREREQUISITE (screen recording not granted)",
            "per_layer_forward_calls: still NOT_INSTRUMENTED (no instrumentation exists)",
            "v2.2.0rc1 overall: still BLOCKED",
        ],
    }
    with open(OUT, "w") as handle:
        json.dump(payload, handle, indent=1)
    print(json.dumps({"wrote": OUT, "verdict": payload["verdict"],
                      "counts_if_applied": payload["ledger_state"]
                      ["counts_if_applied_by_an_authorised_regeneration"]}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
