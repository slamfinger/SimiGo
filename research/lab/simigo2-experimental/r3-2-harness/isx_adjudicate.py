#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
IS-X adjudicator — separate process, reads ONLY this run's records.
Implements design §4 (mechanical interaction classification, fixed
priority) + §5 (controls) + §6 (no-patch) + §7 (outcome structure):
ALL-ADDITIVE / INTERACTION-FOUND / INCONCLUSIVE / STOP-INVALID.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r32_lib as L
import isx_lib as X


def classify_condition(actual: dict, p_comp: dict) -> str:
    """Condition-level classification (design §4 rev.2, mechanical)."""
    a_state, a_sig = actual["state"], actual["signature"]
    p_state = p_comp["state"]
    sig_set = p_comp["sig_set"]
    if a_state == "BROKEN" and not a_sig:
        return "ATTRIBUTION-FAILURE"
    if p_state == "BROKEN" and a_state == "SATISFIED":
        return "MASKING"
    if p_state == "SATISFIED" and a_state == "BROKEN":
        return "EMERGENT-BREAK"
    if p_state == "BROKEN" and a_state == "BROKEN":
        return "BROKEN-MATCH" if a_sig in sig_set else "SIGNATURE-SHIFT"
    return "HOLD-MATCH"  # p SATISFIED + a SATISFIED


def classify_cell(cond_classes: dict) -> str:
    """Cell-level fixed priority (design §4 rev.2): any result falls into
    exactly one class."""
    vals = list(cond_classes.values())
    if "ATTRIBUTION-FAILURE" in vals:
        return "ATTRIBUTION-FAILURE"
    if "SIGNATURE-SHIFT" in vals:
        return "SIGNATURE-SHIFT"
    if "MASKING" in vals:
        return "MASKING"
    if "EMERGENT-BREAK" in vals:
        return "EMERGENT-BREAK"
    return "ADDITIVE"


def main() -> int:
    run_dir = sys.argv[1]
    setup = L.read_json(os.path.join(run_dir, "setup_record.json"))
    summary = L.read_json(os.path.join(run_dir, "run-summary.json"))
    per_cell = []
    batch_flags = []
    interactions = []
    invalid_compositions = []
    sanity_failures = []
    n_inconclusive = 0

    for cell_id in summary["campaign_order"]:
        outcome = L.read_json(os.path.join(run_dir, "cells", cell_id,
                                           "outcome.json"))
        cls = outcome["op_class"]
        entry = {"cell_id": cell_id, "cell_op": outcome["cell_op"],
                 "op_class": cls}

        # INVALID-COMPOSITION (S-X1: pre-registered class, not stopping)
        if outcome["composition"] == "INVALID-COMPOSITION":
            entry["verdict"] = "INVALID-COMPOSITION"
            entry["reason"] = "construction failure: %s" % \
                              outcome["composition_error"]
            invalid_compositions.append(entry)
            per_cell.append(entry)
            continue

        # construction integrity (H-X4 / S-X2)
        ci = outcome["construction_integrity"]
        if ci["pass"] is False:
            entry["verdict"] = "INCONCLUSIVE"
            entry["reason"] = "S-X2 construction integrity %s" % ci["failures"]
            n_inconclusive += 1
            per_cell.append(entry)
            continue

        # integrity (I-5)
        if not outcome["integrity"]["es_unchanged"] or \
           not outcome["integrity"]["is0_unchanged"]:
            entry["verdict"] = "INCONCLUSIVE"
            entry["reason"] = "I-5 integrity violation"
            batch_flags.append(cell_id + ": integrity")
            n_inconclusive += 1
            per_cell.append(entry)
            continue
        # t₀ replication (§1a④)
        if not outcome["t0_matches_setup"]:
            entry["verdict"] = "INCONCLUSIVE"
            entry["reason"] = "t₀ replication inconsistent"
            batch_flags.append(cell_id + ": t0-inconsistency")
            n_inconclusive += 1
            per_cell.append(entry)
            continue
        # instrument doubt (I-2)
        if outcome["instrument_doubt"] == "YES":
            entry["verdict"] = "INCONCLUSIVE"
            entry["reason"] = "I-2 doubt %s" % outcome["doubt_signatures"]
            n_inconclusive += 1
            per_cell.append(entry)
            continue

        t1 = outcome["t1_evaluation"]

        if cls == "K-0":
            drift = any(t1[c]["state"] != "SATISFIED" for c in ("I", "A", "C"))
            if drift:
                entry["verdict"] = "INCONCLUSIVE"
                entry["reason"] = "I-1 K-0 drift"
                batch_flags.append(cell_id + ": K-0 drift")
                n_inconclusive += 1
            else:
                entry["verdict"] = "CONTROL-HOLD"
            per_cell.append(entry)
            continue

        if cls == "SANITY":
            pred = outcome["predicted"]
            dead = any(t1[c]["state"] != pred[c][0] or
                       t1[c]["signature"] != pred[c][1]
                       for c in ("I", "A", "C"))
            if dead:
                entry["verdict"] = "SANITY-FAILED"
                entry["reason"] = "S-N2 evaluator death signal"
                sanity_failures.append(cell_id)
            else:
                entry["verdict"] = "SANITY-OK"
            per_cell.append(entry)
            continue

        # IS-X pair cell: mechanical classification (design §4 rev.2)
        p_comp = outcome["p_comp"]
        cond_classes = {c: classify_condition(t1[c], p_comp[c])
                        for c in ("I", "A", "C")}
        cell_label = classify_cell(cond_classes)
        entry["condition_classes"] = cond_classes
        entry["verdict"] = cell_label
        if cell_label in ("MASKING", "EMERGENT-BREAK", "SIGNATURE-SHIFT"):
            interactions.append(entry)
        # H-X1 resolution expectation check for X-08/X-09
        res_exp = outcome.get("resolution_expectation")
        res_act = outcome.get("resolution_actual")
        if res_exp and res_exp.get("preregistered"):
            pre = res_exp["preregistered"]
            exp_n = pre["expected_candidate_count"]
            act = res_act or {}
            n_act = len(act.get("candidates", [])) \
                if act.get("status") == "found" else \
                (0 if act.get("status") == "not-found" else None)
            entry["resolution_expectation_met"] = (n_act == exp_n)
            if n_act != exp_n:
                entry["resolution_expectation_violated"] = True
        per_cell.append(entry)

    # campaign verdict per design §7 (rev.2)
    if sanity_failures:
        campaign = "INCONCLUSIVE"
        reason = "S-N2 evaluator death: %s" % sanity_failures
    elif batch_flags:
        campaign = "INCONCLUSIVE"
        reason = "batch flags: %s" % batch_flags
    elif n_inconclusive > 0:
        campaign = "INCONCLUSIVE"
        reason = "H-2/S-N4 contagion: %d INCONCLUSIVE cell(s)" % n_inconclusive
    elif interactions:
        campaign = "INTERACTION-FOUND"
        reason = "%d interaction cell(s): %s" % (
            len(interactions), [e["cell_id"] for e in interactions])
    elif invalid_compositions:
        campaign = "INCONCLUSIVE"
        reason = "only INVALID-COMPOSITION cells produced no valid joint " \
                 "evaluation: %s" % [e["cell_id"] for e in invalid_compositions]
    else:
        campaign = "ALL-ADDITIVE"
        reason = "all 12 pairs ADDITIVE (two-layer) + controls hold + " \
                 "construction integrity clean"

    report = {
        "run_uuid": setup["run_uuid"],
        "judgment_rule": setup["judgment_rule"],
        "per_cell": per_cell,
        "interactions": interactions,
        "invalid_compositions": invalid_compositions,
        "sanity_failures": sanity_failures,
        "batch_flags": batch_flags,
        "n_inconclusive": n_inconclusive,
        "campaign_verdict": campaign,
        "campaign_reason": reason,
        "note": "outcome structure per design §7 rev.2; no outcome "
                "auto-opens R3-4",
    }
    L.write_json(os.path.join(run_dir, "adjudication_report.json"), report)

    print("=== per-cell ===")
    for e in per_cell:
        extra = ""
        if e.get("condition_classes"):
            extra = " ".join("%s=%s" % (c, k) for c, k in
                             e["condition_classes"].items())
        print("%-24s %-22s %s %s" % (e["cell_id"], e["verdict"],
                                     e.get("reason", ""), extra))
    print("=== campaign ===")
    print(json.dumps({"campaign_verdict": campaign,
                      "campaign_reason": reason,
                      "n_inconclusive": n_inconclusive},
                     ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
