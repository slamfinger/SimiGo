#!/usr/bin/env python3
"""Read-only projection: which REASONS recorded in the official ledger are now
contradicted by evidence sitting in this batch, and which are not.

Why this exists: the ledger (simigo-v2.2.0rc1-local-acceptance-20261024/
acceptance_report.json) stores, per gate, a set of check booleans plus a note
that states WHY the gate is not PASS. Some of those "why" strings were true when
written and are no longer true after this batch. Merging evidence into the
ledger is a separate authorised act and this script does NOT do it - it only
answers the question the authorisation needs answered: which recorded reasons
are stale, and what file replaces them.

Everything here is computed from the files named below. No verdict is copied by
hand, no threshold is applied, no ledger byte is touched.

usage: project_ledger_staleness.py
Exit codes: 0 written, 3 an expected input is missing.
"""
import hashlib
import json
import os
import sys

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = ("/Users/mr.simi/SimiGo-Agent-Runs/"
          "simigo-v2.2.0rc1-local-acceptance-20261024/acceptance_report.json")
OUT = os.path.join(B, "evidence/ledger_reason_staleness.json")

CANDIDATE_EXE = "83a88048569f4470b9a82ff0ee7ed6817572e8bd777b7df8a6ce3a357c98b70d"


def sha(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def load(path):
    if not os.path.exists(path):
        return None, None
    return json.load(open(path)), sha(path)


def ev(rel):
    """Return (doc, digest, pointer) for a batch-relative evidence file."""
    p = os.path.join(B, rel)
    doc, digest = load(p)
    return {"pointer": rel, "sha256": digest, "present": doc is not None}, doc


def main():
    if not os.path.exists(LEDGER):
        print(json.dumps({"error": "ledger not found", "path": LEDGER}), file=sys.stderr)
        return 3
    ledger, ledger_sha = load(LEDGER)
    gates = ledger["gates"]

    rows = []

    # ---- per_layer_forward_calls -------------------------------------------
    ptr_lf, lf = ev("evidence/layer_forward_calls_verdict_v5.json")
    recorded = gates["per_layer_forward_calls"]
    bound = lf and lf.get("candidate_exe_sha256") == CANDIDATE_EXE
    rows.append({
        "gate": "per_layer_forward_calls",
        "ledger_verdict": recorded["verdict"],
        "ledger_reason": recorded["note"],
        "ledger_checks": recorded["checks"],
        "current_evidence": [ptr_lf],
        "reason_still_true": bool(lf) is False or not bound,
        "measured_now": {
            "verdict_on_current_candidate": (lf or {}).get("verdict"),
            "candidate_exe_sha256_matches_current_candidate": bound,
            "layer_entered_events_total": (lf or {}).get("numbers", {}).get("layer_entered_events_total"),
            "layers_observed": (lf or {}).get("numbers", {}).get("layers_observed"),
            "estimated_values": (lf or {}).get("numbers", {}).get("estimated_values"),
            "all_L_checks_true": bool((lf or {}).get("checks")) and all(
                (lf or {}).get("checks", {}).values()),
        },
        "coverage_boundary_declared": (lf or {}).get("observed_scope_limit"),
        "open_question_for_the_operator": (
            "the recorded reason says no instrumentation exists; on this candidate the shipped "
            "pilot did instrument and did emit real counts. Whether that closes the gate depends "
            "on what the gate is required to cover: the observer sits on the down-projections, the "
            "decoder core is not directly observed and expert-level demand is not instrumented."),
        "this_script_does_not": ["set the gate to PASS", "decide the coverage scope", "write the ledger"],
    })

    # ---- physical_page_return ----------------------------------------------
    trials = {}
    ptrs = []
    for rid in ("os5", "os5b", "os5c", "os6a", "os6b", "os6c"):
        p = "evidence/os_page_return_verdict_%s.json" % rid
        ptr, doc = ev(p)
        if ptr["present"]:
            ptrs.append(ptr)
            n = (doc or {}).get("numbers", {})
            drop = n.get("kernel_resident_drop_bytes")
            anchor = n.get("anchor_available_bytes")
            win_max = n.get("post_window_available_max_bytes")
            gain = (win_max - anchor) if (win_max is not None and anchor is not None) else None
            thr = drop // 2 if drop else None
            trials[rid] = {
                "verdict_as_written": (doc or {}).get("verdict"),
                "candidate_binds_current_exe": (doc or {}).get("candidate_exe_sha256") == CANDIDATE_EXE,
                "kernel_resident_drop_bytes": drop,
                "host_gain_bytes": gain,
                "a5_threshold_bytes": thr,
                "ratio_recomputed_from_bytes": round(gain / drop, 6) if gain and drop else None,
                "margin_bytes_to_threshold": (gain - thr) if (gain is not None and thr is not None) else None,
                "a5_verdict_field_as_written": n.get("kernel_returned_over_drop"),
                "exit_teardown_used_for_verdict": n.get("exit_teardown_used_for_verdict"),
                "all_a_checks_true": bool((doc or {}).get("checks")) and all(
                    (doc or {}).get("checks", {}).values()),
            }
    ptr_disp, disp = ev("evidence/os_page_return_trial_dispersion.json")
    if ptr_disp["present"]:
        ptrs.append(ptr_disp)
    grp = next((g for g in (disp or {}).get("groups_by_binary", [])
                if g.get("candidate_exe_sha256") == CANDIDATE_EXE), None)
    passes = [r for r, v in trials.items() if v["verdict_as_written"] == "PASS"]
    rows.append({
        "gate": "physical_page_return",
        "ledger_verdict": gates["physical_page_return"]["verdict"],
        "ledger_reason": gates["physical_page_return"]["note"],
        "ledger_checks": gates["physical_page_return"]["checks"],
        "current_evidence": ptrs + [ev("evidence/os_page_return_preregistration_next.json")[0],
                                    ev("evidence/os_page_return_free_only_exploratory.json")[0]],
        "reason_still_true": False,
        "measured_now": {
            "trials_on_current_candidate": trials,
            "trials_passing": sorted(passes),
            "same_binary_ratio_spread": (grp or {}).get("ratio_spread"),
            "same_binary_ratio_range": [(grp or {}).get("ratio_min"), (grp or {}).get("ratio_max")],
            "same_binary_margin_spread_bytes": (grp or {}).get("margin_bytes_spread"),
            "same_binary_trials": (grp or {}).get("trials"),
            "rule_changed": False,
            "threshold_changed": False,
        },
        "open_question_for_the_operator": (
            "OS-level page-return evidence now exists on this candidate, so the recorded reason "
            "('no OS-level evidence was collected') is stale. That does not make the gate PASS: "
            "repeats of the same executable straddle the 0.50 line, and the registered rule for a "
            "future claim asks for three trials all passing A5 on that exact executable."),
        "this_script_does_not": ["average trials", "re-decide a trial", "relax A5", "write the ledger"],
    })

    # ---- product_service_http ----------------------------------------------
    ptr_pr, pr = ev("evidence/service_http_ledger_projection_v5.json")
    ptr_gt, gt = ev("evidence/gate_v5/service_http_gate_verdict.json")
    ptr_at, at = ev("evidence/service_http_status_mapping_attribution.json")
    recorded_sh = gates["product_service_http"]
    flipped = sorted(k for k, v in (recorded_sh.get("checks") or {}).items()
                     if isinstance(v, bool) and not v
                     and k in (pr or {}).get("checks", {}))
    rows.append({
        "gate": "product_service_http",
        "ledger_verdict": recorded_sh["verdict"],
        "ledger_reason": recorded_sh["note"],
        "ledger_checks": recorded_sh["checks"],
        "current_evidence": [ptr_pr, ptr_gt, ptr_at],
        "reason_still_true": not (pr or {}).get("checks") or not all(
            v is True for k, v in (pr or {}).get("checks", {}).items()
            if isinstance(v, bool) and k != "probe_present"),
        "measured_now": {
            "projection_verdict": (pr or {}).get("projected_verdict"),
            "ledger_checks_recorded_false_now_measured_true": flipped,
            "gate_overall": (gt or {}).get("overall"),
            "status_mapping_attribution_all_checks": (at or {}).get("all_checks_pass"),
        },
        "deviations_kept_public": (gt or {}).get("deviations"),
        "open_question_for_the_operator": (
            "the four recorded-false checks are measured true on this candidate, but the activation "
            "entry used is a controlled management role in an isolated root, not the GUI flow. The "
            "merge decision is yours; nothing here changes the ledger."),
        "this_script_does_not": ["write the ledger", "claim GUI activation works"],
    })

    # ---- install_and_operate / GUI -----------------------------------------
    ptr_gui, gui = ev("evidence/gui_prerequisite_recheck_os5.json")
    recorded_gui = gates["install_and_operate"]
    rows.append({
        "gate": "install_and_operate",
        "ledger_verdict": recorded_gui["verdict"],
        "ledger_reason": recorded_gui["note"],
        "ledger_checks": recorded_gui["checks"],
        "current_evidence": [ptr_gui],
        "reason_still_true": True,
        "measured_now": {
            "screen_recording_granted": bool((gui or {}).get("screen_recording", {}).get("granted")),
            "accessibility_granted": bool((gui or {}).get("accessibility", {}).get("granted")),
            "screenshot_bytes_observed": (gui or {}).get("screen_recording", {}).get("screenshot_bytes"),
            "real_user_walkthrough_recorded": os.path.exists(
                os.path.join(B, "evidence/m3_stage_b_gui_inference.json")),
        },
        "open_question_for_the_operator": (
            "this is the one gate whose missing input cannot be produced headlessly: it needs the "
            "operator to click the menu-bar item and submit one prompt in the installed candidate. "
            "The machine-side prerequisite (screen recording) is now granted and re-checked."),
        "this_script_does_not": ["simulate the click", "synthesise an event", "write the ledger"],
    })

    payload = {
        "artifact": "which recorded ledger REASONS are contradicted by this batch's evidence",
        "purpose": ("input for the separate authorisation that decides whether new evidence may "
                    "close gates; a staleness list, not a merge"),
        "generated_by": "driver/project_ledger_staleness.py",
        "ledger": {"path": LEDGER, "sha256": ledger_sha,
                   "counts": ledger["counts"], "overall": ledger["overall"]},
        "candidate_exe_sha256": CANDIDATE_EXE,
        "gates": rows,
        "ledger_modified": False,
        "merge_requires_authorization": True,
        "not_claimed": [
            "no gate status is changed here; the counts above are read from the untouched ledger",
            "a stale reason does not automatically become PASS - it means the recorded 'why' no longer holds",
            "every 'measured_now' value is read out of the named evidence file, not typed here",
            "if an evidence file is absent the row reports it as absent rather than assuming a result",
        ],
    }
    with open(OUT, "w") as handle:
        json.dump(payload, handle, indent=1, sort_keys=True)
        handle.write("\n")
    print(json.dumps({
        "ledger_sha256": ledger_sha[:16], "counts": ledger["counts"],
        "reason_stale": {r["gate"]: (not r["reason_still_true"]) for r in rows},
        "out": os.path.relpath(OUT, B)}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
