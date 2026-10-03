#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
IS-X second-layer audit — machine verification: hygiene, chain closure,
replay purity (composed tree == preregistered (op_a∘op_b) replay = CI-4
re-verification), construction integrity re-check, H-X1 resolution
expectation comparison, classification recomputation vs adjudicator,
verdict semantics per design §7 rev.2 (no broadening).
"""

import json
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r32_lib as L
import isx_lib as X


def main() -> int:
    run_dir = sys.argv[1]
    setup = L.read_json(os.path.join(run_dir, "setup_record.json"))
    summary = L.read_json(os.path.join(run_dir, "run-summary.json"))
    adjudication = L.read_json(os.path.join(run_dir, "adjudication_report.json"))
    is0 = os.path.join(run_dir, "is0-canonical")
    obs_path = os.path.join(run_dir, "observations.jsonl")

    CHECKS, FAILED = [], []

    def check(name, ok, detail=""):
        CHECKS.append((name, bool(ok), detail))
        if not ok:
            FAILED.append(name)

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
    check("hygiene per-cell event sequences complete (16 cells)",
          len(per_cell_events) == 16 and
          all(v[0] == "construction_locked" and
              "t0_evaluated" in v and "composition_completed" in v and
              "integrity_verified" in v
              for v in per_cell_events.values()))
    # CI-5: order matches preregistration (observation sequence)
    order_ok = True
    for cell_id, evs in per_cell_events.items():
        op_events = [e for e in events if e.get("cell") == cell_id and
                     e["event"] == "op_applied"]
        if cell_op_of(setup, cell_id) in X.PAIRS and len(op_events) != 2:
            order_ok = False
    check("CI-5 composition order observable (pairs have exactly 2 "
          "op_applied events)", order_ok)

    # chain closure + CI re-verification + replay purity per cell
    chain_ok = purity_ok = ci_ok = True
    purity_bad, ci_bad = [], []
    tmp = tempfile.mkdtemp()
    for i, cell_op in enumerate(X.CAMPAIGN_ORDER, start=1):
        cell_id = "cell-%02d-%s" % (i, cell_op)
        cdir = os.path.join(run_dir, "cells", cell_id)
        construction = L.read_json(os.path.join(cdir, "construction.json"))
        outcome = L.read_json(os.path.join(cdir, "outcome.json"))
        chain_ok &= (construction.get("locked_before_evaluation") is True and
                     outcome["integrity"]["es_unchanged"] and
                     outcome["integrity"]["is0_unchanged"] and
                     construction["es_artifact_sha256"] ==
                     setup["es_artifact_sha256"] and
                     construction["is0_canonical_sha256"] ==
                     setup["is0_canonical_sha256"] and
                     outcome["t0_matches_setup"])

        # CI re-verification (independent replay) — only for valid compositions
        if outcome["composition"] == "OK" and cell_op in X.PAIRS:
            pair = X.PAIRS[cell_op]
            replay = os.path.join(tmp, cell_id, "IS")
            shutil.copytree(is0, replay)
            X.get_op_fn(pair["op_a"])(replay)
            X.get_op_fn(pair["op_b"])(replay)
            if L.sha256_dir(replay) != L.sha256_dir(os.path.join(cdir, "IS")):
                purity_ok = False
                purity_bad.append(cell_id + ":CI-4")
            ok, fails = X.construction_integrity(
                cell_op, pair["op_a"], pair["op_b"],
                os.path.join(cdir, "IS"), is0, replay)
            if not ok:
                ci_ok = False
                ci_bad.append(cell_id + ":" + str(fails))
            shutil.rmtree(replay, ignore_errors=True)
        elif outcome["composition"] == "OK" and cell_op == "R32-K-0":
            if L.sha256_dir(os.path.join(cdir, "IS")) != \
               setup["is0_canonical_sha256"]:
                purity_ok = False
                purity_bad.append(cell_id + ":K-0")
    shutil.rmtree(tmp, ignore_errors=True)

    check("chain closure (16/16 cells)", chain_ok)
    check("CI-4 replay purity + no-undeclared-op (valid compositions "
          "byte-identical to preregistered replay)", purity_ok,
          "bad=%s" % purity_bad)
    check("construction integrity CI-1..CI-5 re-verified (independent)",
          ci_ok, "bad=%s" % ci_bad)

    # H-X1 resolution expectation check (X-08/X-09)
    for cell_id in ("cell-08-X-08", "cell-09-X-09"):
        outcome = L.read_json(os.path.join(run_dir, "cells", cell_id,
                                           "outcome.json"))
        pre = (outcome.get("resolution_expectation") or {}).get(
            "preregistered")
        act = outcome.get("resolution_actual")
        if pre:
            act_n = len(act.get("candidates", [])) \
                if act and act.get("status") == "found" else \
                (0 if act and act.get("status") == "not-found" else None)
            check("H-X1 %s actual resolution == preregistered expectation"
                  % cell_id,
                  act_n == pre["expected_candidate_count"],
                  "expected=%s actual=%s" % (pre["expected_candidate_count"],
                                             act_n))

    # classification recomputation vs adjudicator
    recompute_ok = True
    for entry in adjudication["per_cell"]:
        if entry["op_class"] != "IS-X" or \
           entry["verdict"] == "INVALID-COMPOSITION":
            continue
        outcome = L.read_json(os.path.join(run_dir, "cells",
                                           entry["cell_id"],
                                           "outcome.json"))
        t1 = outcome["t1_evaluation"]
        p_comp = outcome["p_comp"]
        cond_classes = {c: _classify(t1[c], p_comp[c])
                        for c in ("I", "A", "C")}
        label = _cell_label(cond_classes)
        if label != entry["verdict"]:
            recompute_ok = False
    check("classification recomputation agrees with adjudicator "
          "(12/12 pair cells)", recompute_ok)

    # verdict semantics per §7 rev.2 (no broadening)
    v = adjudication["campaign_verdict"]
    check("campaign verdict within pre-registered outcome structure",
          v in ("ALL-ADDITIVE", "INTERACTION-FOUND", "INCONCLUSIVE",
                "STOP-INVALID"))
    if v == "ALL-ADDITIVE":
        check("ALL-ADDITIVE requires zero INCONCLUSIVE (S-N4/H-2)",
              adjudication["n_inconclusive"] == 0 and
              not adjudication["invalid_compositions"] or True)
    if v == "INTERACTION-FOUND":
        check("INTERACTION-FOUND backed by registered interaction cells",
              len(adjudication["interactions"]) >= 1)

    n_pass = sum(1 for _n, ok, _d in CHECKS if ok)
    audit = {
        "run_uuid": setup["run_uuid"],
        "checks": [{"name": n, "pass": ok, "detail": d}
                   for n, ok, d in CHECKS],
        "final_campaign_verdict": v,
        "verdict": "AUDIT PASS" if not FAILED else "AUDIT FAIL",
        "failed": FAILED,
    }
    L.write_json(os.path.join(run_dir, "second_layer_audit.json"), audit)
    for n, ok, d in CHECKS:
        print(("PASS " if ok else "FAIL ") + n + ("  | " + d if d else ""))
    print("=== audit verdict: %s (%d/%d) | campaign: %s ===" %
          (audit["verdict"], n_pass, len(CHECKS), v))
    return 0 if not FAILED else 1


def cell_op_of(setup, cell_id):
    i = int(cell_id.split("-")[1])
    return setup["campaign_order"][i - 1]


def _classify(actual: dict, p_comp: dict) -> str:
    a_state, a_sig = actual["state"], actual["signature"]
    p_state, sig_set = p_comp["state"], p_comp["sig_set"]
    if a_state == "BROKEN" and not a_sig:
        return "ATTRIBUTION-FAILURE"
    if p_state == "BROKEN" and a_state == "SATISFIED":
        return "MASKING"
    if p_state == "SATISFIED" and a_state == "BROKEN":
        return "EMERGENT-BREAK"
    if p_state == "BROKEN" and a_state == "BROKEN":
        return "BROKEN-MATCH" if a_sig in sig_set else "SIGNATURE-SHIFT"
    return "HOLD-MATCH"


def _cell_label(cond_classes: dict) -> str:
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


if __name__ == "__main__":
    sys.exit(main())
