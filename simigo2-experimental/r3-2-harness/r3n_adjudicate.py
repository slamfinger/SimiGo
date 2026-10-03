#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
R3-N adjudicator — separate process, reads ONLY this run's records.
Implements design §5 (rev.2): pre-registered outcome structure
NO-COUNTEREXAMPLE / COUNTEREXAMPLE-FOUND / INCONCLUSIVE, with
H-2 INCONCLUSIVE contagion and H-3 counterexample qualification
((a) attribution + (b) replay reproduction checked here; (c) instrument-
defect non-localization delegated to the second-layer audit).
"""

import json
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r32_lib as L
import r3n_lib as N


def main() -> int:
    run_dir = sys.argv[1]
    setup = L.read_json(os.path.join(run_dir, "setup_record.json"))
    es = L.read_json(os.path.join(run_dir, "es-artifact.json"))
    summary = L.read_json(os.path.join(run_dir, "run-summary.json"))
    is0 = os.path.join(run_dir, "is0-canonical")
    pinned_ts = setup["setup_pinned_timestamp"]

    per_cell = []
    batch_flags = []
    counterexamples = []
    sanity_failures = []
    n_inconclusive = 0

    tmp = tempfile.mkdtemp()
    for i, op_id in enumerate(N.CAMPAIGN_ORDER, start=1):
        cell_id = "cell-%02d-%s" % (i, op_id)
        cdir = os.path.join(run_dir, "cells", cell_id)
        construction = L.read_json(os.path.join(cdir, "construction.json"))
        outcome = L.read_json(os.path.join(cdir, "outcome.json"))
        cls = construction["op_class"]
        entry = {"cell_id": cell_id, "op_id": op_id, "op_class": cls,
                 "prediction_ok": construction["predicted"] ==
                                  N.predict(op_id, es)}

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
        pred = outcome["predicted"]

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
            # evaluator liveness: must produce predicted BROKEN + signature
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

        # R3-N counterexample probe cells: prediction = all HOLD
        broken = {c: (t1[c]["state"], t1[c]["signature"])
                  for c in ("I", "A", "C") if t1[c]["state"] == "BROKEN"}
        if not broken:
            entry["verdict"] = "HOLD"
            per_cell.append(entry)
            continue

        # candidate counterexample: H-3 qualification
        sigd = {c: s for c, (st, s) in broken.items() if s}
        if not sigd:
            entry["verdict"] = "INCONCLUSIVE"
            entry["reason"] = "I-3 unattributable break (no signature)"
            n_inconclusive += 1
            per_cell.append(entry)
            continue
        # (b) replay reproduction
        replay = os.path.join(tmp, cell_id, "IS")
        shutil.copytree(is0, replay)
        N.N_CATALOG[op_id]["fn"](replay)
        t1_replay = L.eval_cons(es, replay, pinned_ts, mode="t1")
        replay_ok = t1_replay == t1
        # (a) attribution: signature present (sigd non-empty)
        entry["verdict"] = "COUNTEREXAMPLE-CANDIDATE"
        entry["broken_conditions"] = {c: s for c, s in sigd.items()}
        entry["replay_reproduced"] = replay_ok
        entry["qualification"] = {
            "a_attribution": True,
            "b_replay": replay_ok,
            "c_audit_non_localization": "PENDING SECOND-LAYER AUDIT",
        }
        counterexamples.append(entry)
        per_cell.append(entry)

    shutil.rmtree(tmp, ignore_errors=True)

    # campaign verdict per design §5 (rev.2)
    if sanity_failures:
        campaign = "INCONCLUSIVE"
        reason = "S-N2 evaluator death: %s" % sanity_failures
    elif batch_flags:
        campaign = "INCONCLUSIVE"
        reason = "batch flags: %s" % batch_flags
    elif n_inconclusive > 0:
        campaign = "INCONCLUSIVE"
        reason = "H-2 contagion: %d INCONCLUSIVE cell(s)" % n_inconclusive
    elif counterexamples:
        campaign = "COUNTEREXAMPLE-FOUND"
        reason = ("%d qualified candidate(s); requirement (c) delegated to "
                  "second-layer audit" % len(counterexamples))
    else:
        campaign = "NO-COUNTEREXAMPLE"
        reason = "all %d probes HOLD + 3/3 SANITY BROKEN + K-0 hold" % \
                 sum(1 for e in per_cell if e["verdict"] == "HOLD")

    report = {
        "run_uuid": setup["run_uuid"],
        "judgment_rule": setup["judgment_rule"],
        "per_cell": per_cell,
        "counterexample_candidates": counterexamples,
        "sanity_failures": sanity_failures,
        "batch_flags": batch_flags,
        "n_inconclusive": n_inconclusive,
        "campaign_verdict": campaign,
        "campaign_reason": reason,
        "note": "outcome structure per design §5 rev.2; H-2 contagion "
                "applied; requirement (c) of H-3 delegated to second-layer "
                "audit where counterexamples exist",
    }
    L.write_json(os.path.join(run_dir, "adjudication_report.json"), report)

    print("=== per-cell ===")
    for e in per_cell:
        print("%-28s %-12s %s" % (e["cell_id"], e["verdict"],
                                  e.get("reason", "")))
    print("=== campaign ===")
    print(json.dumps({"campaign_verdict": campaign,
                      "campaign_reason": reason,
                      "n_inconclusive": n_inconclusive},
                     ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
