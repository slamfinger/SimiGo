#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
R3-2 adjudicator — separate process, reads ONLY this run's records
(Spec §4.3: judgment/input separation).

Checks per cell (design §7/§8, Spec §6.1/§6.2):
  - construction record integrity: class re-derived from frozen rule and
    compared; prediction re-derived and compared (H-F/H-1 enforcement)
  - t₀ consistency vs setup (instrument replication, design §1a④)
  - integrity: ES / canonical IS₀ hash drift (S-3 / I-5)
  - instrument_doubt (I-2), unattributable breaks (I-3), K-0 drift (I-1)
Campaign verdict per Spec §6.2 four-state definitions.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r32_lib as L


def main() -> int:
    run_dir = sys.argv[1]
    setup = L.read_json(os.path.join(run_dir, "setup_record.json"))
    es = L.read_json(os.path.join(run_dir, "es-artifact.json"))
    summary = L.read_json(os.path.join(run_dir, "run-summary.json"))
    L.build_region_cache(os.path.join(run_dir, "is0-canonical"))

    per_cell = []
    batch_inconclusive = False
    inconclusive_reasons = []
    rq34_material = []

    for op_id in L.CAMPAIGN_ORDER:
        idx = L.CAMPAIGN_ORDER.index(op_id) + 1
        cell_id = "cell-%02d-%s" % (idx, op_id)
        cdir = os.path.join(run_dir, "cells", cell_id)
        construction = L.read_json(os.path.join(cdir, "construction.json"))
        outcome = L.read_json(os.path.join(cdir, "outcome.json"))

        # class re-derivation (mechanical, H-F)
        cls_expected = L.derive_class(op_id)
        class_ok = construction["op_class"] == cls_expected

        # prediction re-derivation (mechanical, H-1)
        pred_expected = L.predict(op_id, es)
        pred_ok = construction["predicted"] == pred_expected

        entry = {"cell_id": cell_id, "op_id": op_id,
                 "op_class": construction["op_class"],
                 "class_ok": class_ok, "prediction_ok": pred_ok}

        # integrity
        if not outcome["integrity"]["es_unchanged"] or \
           not outcome["integrity"]["is0_unchanged"]:
            entry["verdict"] = "INCONCLUSIVE"
            entry["reason"] = "I-5 integrity violation"
            batch_inconclusive = True
            inconclusive_reasons.append(cell_id + ": integrity")
            per_cell.append(entry)
            continue

        # t₀ replication consistency (design §1a④)
        if not outcome["t0_matches_setup"]:
            entry["verdict"] = "INCONCLUSIVE"
            entry["reason"] = "t₀ replication inconsistent with setup"
            batch_inconclusive = True
            inconclusive_reasons.append(cell_id + ": t0-inconsistency")
            per_cell.append(entry)
            continue

        # instrument doubt (I-2)
        if outcome["instrument_doubt"] == "YES":
            entry["verdict"] = "INCONCLUSIVE"
            entry["reason"] = "I-2 instrument_doubt %s" % \
                              outcome["doubt_signatures"]
            per_cell.append(entry)
            continue

        t1 = outcome["t1_evaluation"]
        pred = outcome["predicted"]
        cls = construction["op_class"]

        # unattributable break check (I-3): any BROKEN without signature
        # or with a signature not derivable from the op's mechanism
        expected_sigs = {cond: pred[cond][1] for cond in ("I", "A", "C")}
        unattributable = False
        cross = []
        no_break = []
        matched = []
        for cond in ("I", "A", "C"):
            state, sig = t1[cond]["state"], t1[cond]["signature"]
            p_state, p_sig = pred[cond]
            if p_state == "BROKEN":
                if state == "BROKEN" and sig == p_sig:
                    matched.append(cond)
                elif state == "BROKEN":
                    unattributable = True  # broken but wrong signature
                else:
                    no_break.append(cond)  # targeted but did not break
            else:
                if state == "SATISFIED":
                    matched.append(cond)
                elif state == "BROKEN":
                    if sig:
                        cross.append("%s:%s" % (cond, sig))  # RQ3-4 material
                    else:
                        unattributable = True
                else:
                    unattributable = True  # unexpected NOT-EVALUABLE

        if unattributable:
            entry["verdict"] = "INCONCLUSIVE"
            entry["reason"] = "I-3 unattributable break/outcome"
            per_cell.append(entry)
            continue

        entry["matched_conditions"] = matched
        if cross:
            entry["cross_sensitivity"] = cross
            rq34_material.append({"cell_id": cell_id, "cross": cross})
        if cls == "K-0":
            # null control: t1 must be unchanged (all SATISFIED, as at setup)
            drift = any(t1[c]["state"] != "SATISFIED" for c in ("I", "A", "C"))
            if drift:
                entry["verdict"] = "INCONCLUSIVE"
                entry["reason"] = "I-1 K-0 drift"
                batch_inconclusive = True
                inconclusive_reasons.append(cell_id + ": K-0 drift")
            else:
                entry["verdict"] = "CONTROL-HOLD"
        elif cls == "K-1":
            entry["verdict"] = "CONTROL-HOLD" if not no_break and not cross \
                else "PREDICTION-MISMATCH"
        elif cls in ("IS-I", "IS-A", "IS-C"):
            tgt = cls[-1]
            if no_break:
                entry["verdict"] = "NO-BREAK"
                entry["no_break_conditions"] = no_break
            elif matched and not cross:
                entry["verdict"] = "PREDICTION-MATCH"
            elif matched and cross:
                entry["verdict"] = "PREDICTION-MATCH-WITH-CROSS"
            else:
                entry["verdict"] = "PREDICTION-MISMATCH"
        elif cls == "IS-B":
            entry["verdict"] = "DERIVATION-CONSISTENT" if not cross \
                else "CROSS-OBSERVED"
        else:
            entry["verdict"] = "UNEXPECTED-CLASS"
        per_cell.append(entry)

    # campaign four-state (Spec §6.2)
    targeted = [e for e in per_cell if e["op_class"] in ("IS-I", "IS-A", "IS-C")]
    no_break_cells = [e for e in targeted if e["verdict"] == "NO-BREAK"]
    match_cells = [e for e in targeted
                   if e["verdict"] in ("PREDICTION-MATCH",
                                       "PREDICTION-MATCH-WITH-CROSS")]
    if batch_inconclusive:
        campaign = "INCONCLUSIVE"
    elif no_break_cells:
        campaign = "PARTIALLY-SUPPORTED" if match_cells else "NOT-SUPPORTED"
    elif len(match_cells) == len(targeted) and all(
            e["verdict"] == "CONTROL-HOLD"
            for e in per_cell if e["op_class"] in ("K-0", "K-1")):
        campaign = "SUPPORTED"
    elif match_cells:
        campaign = "PARTIALLY-SUPPORTED"
    else:
        campaign = "NOT-SUPPORTED"

    report = {
        "run_uuid": setup["run_uuid"],
        "judgment_rule": setup["judgment_rule"],
        "per_cell": per_cell,
        "rq34_material": rq34_material,
        "batch_inconclusive": batch_inconclusive,
        "inconclusive_reasons": inconclusive_reasons,
        "campaign_verdict": campaign,
        "note": "campaign scope = single-variable campaign over the frozen "
                "catalog; IS-X not instantiated (design §3/§4a)",
    }
    L.write_json(os.path.join(run_dir, "adjudication_report.json"), report)

    print("=== per-cell ===")
    for e in per_cell:
        print("%-28s %-12s %s" % (e["cell_id"], e.get("verdict"),
                                  e.get("reason", "")))
    print("=== campaign ===")
    print(json.dumps({"campaign_verdict": campaign,
                      "batch_inconclusive": batch_inconclusive,
                      "rq34_material": rq34_material},
                     ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
