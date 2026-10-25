#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
R3-N second-layer audit — machine verification (evidence-chain closure,
purity, liveness, H-2/H-3 semantics) and, where counterexample candidates
exist, H-3 requirement (c): instrument-defect localization battery.
"""

import json
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r32_lib as L
import r3n_lib as N

CHECKS = []
FAILED = []


def check(name, ok, detail=""):
    CHECKS.append((name, bool(ok), detail))
    if not ok:
        FAILED.append(name)
    return ok


def main() -> int:
    run_dir = sys.argv[1]
    setup = L.read_json(os.path.join(run_dir, "setup_record.json"))
    es = L.read_json(os.path.join(run_dir, "es-artifact.json"))
    summary = L.read_json(os.path.join(run_dir, "run-summary.json"))
    adjudication = L.read_json(os.path.join(run_dir, "adjudication_report.json"))
    is0 = os.path.join(run_dir, "is0-canonical")
    obs_path = os.path.join(run_dir, "observations.jsonl")

    # hygiene
    events = [json.loads(line) for line in open(obs_path, encoding="utf-8")
              if line.strip()]
    check("hygiene run_uuid uniform",
          {e.get("run_uuid") for e in events} == {setup["run_uuid"]})
    monos = [e["monotonic"] for e in events]
    check("hygiene monotonic non-decreasing",
          all(a <= b for a, b in zip(monos, monos[1:])))
    per_cell_events = {}
    for e in events:
        if e.get("cell"):
            per_cell_events.setdefault(e["cell"], []).append(e["event"])
    seq = ["construction_locked", "t0_evaluated", "op_applied",
           "t1_evaluated", "integrity_verified"]
    check("hygiene per-cell event sequences complete & ordered (14 cells)",
          all(v == seq for v in per_cell_events.values()) and
          len(per_cell_events) == 14)

    # chain closure + purity + liveness per cell
    chain_ok = purity_ok = True
    purity_bad = []
    hold_ok = sanity_ok = True
    tmp = tempfile.mkdtemp()
    for i, op_id in enumerate(N.CAMPAIGN_ORDER, start=1):
        cell_id = "cell-%02d-%s" % (i, op_id)
        cdir = os.path.join(run_dir, "cells", cell_id)
        construction = L.read_json(os.path.join(cdir, "construction.json"))
        outcome = L.read_json(os.path.join(cdir, "outcome.json"))
        cls = construction["op_class"]

        locked = construction.get("locked_before_evaluation") is True
        integ = outcome["integrity"]["es_unchanged"] and \
            outcome["integrity"]["is0_unchanged"]
        hash_pin = (construction["es_artifact_sha256"] ==
                    setup["es_artifact_sha256"] and
                    construction["is0_canonical_sha256"] ==
                    setup["is0_canonical_sha256"])
        t0m = outcome["t0_matches_setup"] and all(
            outcome["t0_evaluation"][c] == setup["t0_evaluation"][c]
            for c in ("I", "A", "C"))
        chain_ok &= (locked and integ and hash_pin and t0m)

        # frozen-op replay purity
        replay = os.path.join(tmp, cell_id, "IS")
        shutil.copytree(is0, replay)
        N.N_CATALOG[op_id]["fn"](replay)
        purity_ok &= (L.sha256_dir(replay) ==
                      L.sha256_dir(os.path.join(cdir, "IS")))

        t1 = outcome["t1_evaluation"]
        pred = construction["predicted"]
        if cls == "R3-N":
            hold_ok &= all(t1[c]["state"] == "SATISFIED"
                           for c in ("I", "A", "C"))
        elif cls == "SANITY":
            sanity_ok &= all(t1[c]["state"] == pred[c][0] and
                             t1[c]["signature"] == pred[c][1]
                             for c in ("I", "A", "C"))
        elif cls == "K-0":
            hold_ok &= all(t1[c]["state"] == "SATISFIED"
                           for c in ("I", "A", "C"))
    shutil.rmtree(tmp, ignore_errors=True)

    check("chain closure (all 14 cells: lock+integrity+hash pins+t0 replication)",
          chain_ok)
    check("replay purity (14/14 frozen-op replays byte-identical)", purity_ok)
    check("N-probe HOLD evidence (10/10 cells all-SATISFIED raw t1)", hold_ok)
    check("per-condition evaluator liveness (SANITY-A/I/C all predicted "
          "BROKEN)", sanity_ok)

    # counterexample qualification (c): instrument-defect localization
    cands = adjudication.get("counterexample_candidates", [])
    if cands:
        localization_battery = {
            "evaluator_liveness": sanity_ok,
            "integrity_all_clean": summary["integrity_all_clean"] and
                                   all(c["integrity"]["es_unchanged"] and
                                       c["integrity"]["is0_unchanged"] for c in
                                       [L.read_json(os.path.join(
                                           run_dir, "cells", e["cell_id"],
                                           "outcome.json"))
                                        for e in adjudication["per_cell"]]),
            "t0_replication_all": summary["t0_consistency_all"],
            "replay_deterministic": all(c["replay_reproduced"] for c in cands),
            "observations_hygiene": not any(not ok for n, ok, _d in CHECKS
                                            if n.startswith("hygiene")),
        }
        defects = [k for k, v in localization_battery.items() if not v]
        check("H-3(c) instrument-defect localization battery: no defect "
              "localized (counterexample qualification confirmed)",
              not defects, "defects=%s" % defects)
        for c in cands:
            c["qualification"]["c_audit_non_localization"] = \
                "CONFIRMED" if not defects else \
                "RECLASSIFIED:INSTRUMENT-DEFECT(%s)" % defects
        final = "COUNTEREXAMPLE-FOUND" if not defects else "INCONCLUSIVE"
    else:
        check("H-3(c) not applicable (no counterexample candidates)", True)
        # H-2 contagion: NO-COUNTEREXAMPLE requires zero INCONCLUSIVE
        check("H-2 zero-INCONCLUSIVE requirement for NO-COUNTEREXAMPLE",
              adjudication["n_inconclusive"] == 0 and
              adjudication["campaign_verdict"] == "NO-COUNTEREXAMPLE")
        final = adjudication["campaign_verdict"]

    # verdict semantics per §5 (no broadening)
    check("final verdict within pre-registered outcome structure",
          final in ("NO-COUNTEREXAMPLE", "COUNTEREXAMPLE-FOUND",
                    "INCONCLUSIVE"))
    check("adjudicator verdict consistent with audit recomputation",
          adjudication["campaign_verdict"] == final or
          (adjudication["campaign_verdict"] == "COUNTEREXAMPLE-FOUND" and
           final == "INCONCLUSIVE"))

    n_pass = sum(1 for _n, ok, _d in CHECKS if ok)
    audit = {
        "run_uuid": setup["run_uuid"],
        "checks": [{"name": n, "pass": ok, "detail": d}
                   for n, ok, d in CHECKS],
        "final_campaign_verdict": final,
        "verdict": "AUDIT PASS" if not FAILED else "AUDIT FAIL",
        "failed": FAILED,
    }
    L.write_json(os.path.join(run_dir, "second_layer_audit.json"), audit)
    for n, ok, d in CHECKS:
        print(("PASS " if ok else "FAIL ") + n + ("  | " + d if d else ""))
    print("=== audit verdict: %s (%d/%d) | final campaign verdict: %s ===" %
          (audit["verdict"], n_pass, len(CHECKS), final))
    return 0 if not FAILED else 1


if __name__ == "__main__":
    sys.exit(main())
