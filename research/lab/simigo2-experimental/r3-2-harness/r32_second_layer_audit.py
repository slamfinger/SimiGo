#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
R3-2 second-layer results audit — machine verification of the evidence
chain (human second-layer directive, 2026-10-03).

Eight audit foci:
  A1  evidence chain closure per cell (construction → t0 → op → t1 →
      integrity, in append-only observation order)
  A2  signatures match construction-time predictions one-to-one
  A3  targeted cells: raw evidence that ONLY the targeted condition broke
  A4  IS-B "did not touch referenced objects" proven from CONSTRUCTION-TIME
      index (not reverse-inferred from outcomes)
  A5  K-1b equivalent migration preserved the binding invariant
      (resolution + formation digest) — verified against actual cell tree
  A6  cell independence/purity: replay each frozen op on a fresh IS₀ copy
      and require byte-identical result tree (no hidden cumulative state);
      K-0 cell IS tree must equal canonical IS₀
  A7  append-only observation hygiene: monotonic order, per-cell event sets,
      uniform run_uuid
  A8  campaign "SUPPORTED" strictly per Spec §6.2 (recomputed, compared
      with adjudication_report.json)
"""

import json
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r32_lib as L

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

    # ---- A7: observations hygiene -----------------------------------------
    events = [json.loads(line) for line in open(obs_path, encoding="utf-8")
              if line.strip()]
    run_uuids = {e.get("run_uuid") for e in events}
    check("A7 run_uuid uniform", run_uuids == {setup["run_uuid"]},
          str(run_uuids))
    monos = [e["monotonic"] for e in events]
    check("A7 monotonic non-decreasing",
          all(a <= b for a, b in zip(monos, monos[1:])))
    per_cell_events = {}
    for e in events:
        if e.get("cell"):
            per_cell_events.setdefault(e["cell"], []).append(e["event"])
    expected_seq = ["construction_locked", "t0_evaluated", "op_applied",
                    "t1_evaluated", "integrity_verified"]
    seq_ok = all(v == expected_seq for v in per_cell_events.values())
    check("A7 per-cell event sequence complete & ordered (14 cells)",
          seq_ok and len(per_cell_events) == 14,
          "cells=%d" % len(per_cell_events))
    # append-only: construction/event files must not have been rewritten —
    # verify construction.json still carries locked_before_evaluation and
    # that outcome.json exists for every cell (physical separation)
    check("A7 construction/outcome physically separate files",
          all(os.path.exists(os.path.join(run_dir, "cells", c, f))
              for c in per_cell_events
              for f in ("construction.json", "outcome.json")))

    # ---- A1/A2/A3: per-cell chain closure, signature match, only-target ---
    setup_t0 = setup["t0_evaluation"]
    is0_sha = setup["is0_canonical_sha256"]
    es_sha = setup["es_artifact_sha256"]
    chain_ok = True
    sig_ok = True
    only_target_ok = True
    per_cell_rows = []
    for i, op_id in enumerate(L.CAMPAIGN_ORDER, start=1):
        cell_id = "cell-%02d-%s" % (i, op_id)
        cdir = os.path.join(run_dir, "cells", cell_id)
        construction = L.read_json(os.path.join(cdir, "construction.json"))
        outcome = L.read_json(os.path.join(cdir, "outcome.json"))

        # A1 chain closure
        locked = construction.get("locked_before_evaluation") is True
        t0m = outcome.get("t0_matches_setup") is True
        integ = outcome["integrity"]["es_unchanged"] and \
            outcome["integrity"]["is0_unchanged"]
        hash_pin = (construction["es_artifact_sha256"] == es_sha and
                    construction["is0_canonical_sha256"] == is0_sha)
        t0_raw = all(outcome["t0_evaluation"][c] == setup_t0[c]
                     for c in ("I", "A", "C"))
        cell_chain = locked and t0m and integ and hash_pin and t0_raw
        chain_ok &= cell_chain

        # A2 signature one-to-one vs construction-time prediction
        pred = construction["predicted"]
        t1 = outcome["t1_evaluation"]
        match = all(t1[c]["state"] == pred[c][0] and
                    t1[c]["signature"] == pred[c][1]
                    for c in ("I", "A", "C"))
        sig_ok &= match

        # A3 only-targeted-broken raw evidence
        cls = construction["op_class"]
        if cls in ("IS-I", "IS-A", "IS-C"):
            tgt = cls[-1]
            others_sat = all(t1[c]["state"] == "SATISFIED"
                             for c in ("I", "A", "C") if c != tgt)
            tgt_broken = t1[tgt]["state"] == "BROKEN" and \
                bool(t1[tgt]["signature"])
            only_target_ok &= (others_sat and tgt_broken)
            per_cell_rows.append((cell_id, cls, t1[tgt]["signature"],
                                  "only-target" if others_sat else "LEAK"))
        else:
            all_sat = all(t1[c]["state"] == "SATISFIED"
                          for c in ("I", "A", "C"))
            per_cell_rows.append((cell_id, cls, "-",
                                  "all-SATISFIED" if all_sat else "UNEXPECTED"))

    check("A1 evidence chain closure (all 14 cells)", chain_ok)
    check("A2 signatures one-to-one vs construction-time predictions",
          sig_ok)
    check("A3 targeted cells: only targeted condition broke (raw t1)",
          only_target_ok)

    # ---- A4: IS-B construction-time proof (not outcome-inferred) ----------
    idx0 = L.load_index(is0)
    es_refs = set()
    for ev in ("I-EV-1", "I-EV-2"):
        ref = es["I_ev"][ev].get("is_reference")
        if ref:
            es_refs.add(ref["key"])
    es_refs |= set(es["C_ev"]["prerequisite_keys"])
    es_refs.add(es["A_ev"]["anchor_name"])
    region = "archive/"
    region_keys = {k for k, rels in idx0.items()
                   for rel in rels if rel.startswith(region)}
    touched = region_keys & es_refs
    check("A4 IS-B region∩referenced empty at CONSTRUCTION TIME "
          "(independent of outcomes)", touched == set(),
          "region_keys=%s referenced=%s" % (sorted(region_keys),
                                            sorted(es_refs)))
    b_outcomes_ok = True
    for i, op_id in enumerate(L.CAMPAIGN_ORDER, start=1):
        if op_id in ("R32-B-Δ1", "R32-B-Δ2"):
            cell_id = "cell-%02d-%s" % (i, op_id)
            outcome = L.read_json(os.path.join(run_dir, "cells", cell_id,
                                               "outcome.json"))
            b_outcomes_ok &= all(outcome["t1_evaluation"][c]["state"] ==
                                 "SATISFIED" for c in ("I", "A", "C"))
    check("A4 IS-B outcomes consistent with construction-time derivation",
          b_outcomes_ok)

    # ---- A5: K-1b binding invariant against the ACTUAL cell tree ----------
    k1b_is = os.path.join(run_dir, "cells", "cell-13-R32-K-1b", "IS")
    idx_k1b = L.load_index(k1b_is)
    anchor_rels = idx_k1b.get(es["A_ev"]["anchor_name"], [])
    inv_ok = False
    detail = ""
    if len(anchor_rels) == 1:
        rel = anchor_rels[0]
        full = os.path.join(k1b_is, rel)
        manifest = L.load_manifest(k1b_is)
        inb, reason = L.in_boundary(manifest, rel)
        digest = L.sha256_file(full) if os.path.exists(full) else None
        inv_ok = (inb and digest == es["A_ev"]
                  ["formation_target_content_sha256"])
        detail = "rel=%s in_boundary=%s digest_match=%s" % (
            rel, inb, digest == es["A_ev"]["formation_target_content_sha256"])
    check("A5 K-1b binding invariant preserved (resolution+digest+boundary)",
          inv_ok, detail)
    check("A5 K-1b original storage path vacated (migration really happened)",
          not os.path.exists(os.path.join(k1b_is, "objects/R-1.json")))

    # ---- A6: cell independence/purity via frozen-op replay ----------------
    purity_ok = True
    purity_detail = []
    tmp = tempfile.mkdtemp()
    for i, op_id in enumerate(L.CAMPAIGN_ORDER, start=1):
        cell_id = "cell-%02d-%s" % (i, op_id)
        replay = os.path.join(tmp, cell_id, "IS")
        shutil.copytree(is0, replay)
        L.CATALOG[op_id]["fn"](replay)
        replay_sha = L.sha256_dir(replay)
        cell_sha = L.sha256_dir(os.path.join(run_dir, "cells", cell_id, "IS"))
        ok = replay_sha == cell_sha
        purity_ok &= ok
        if not ok:
            purity_detail.append(cell_id)
    shutil.rmtree(tmp)
    check("A6 replay purity: frozen op on fresh IS₀ copy reproduces every "
          "cell IS tree byte-identically (no hidden cumulative state)",
          purity_ok, "mismatch=%s" % purity_detail)
    k0_sha = L.sha256_dir(os.path.join(run_dir, "cells",
                                       "cell-14-R32-K-0", "IS"))
    check("A6 K-0 cell IS tree identical to canonical IS₀",
          k0_sha == is0_sha)

    # ---- A8: campaign verdict strictly per Spec §6.2 ----------------------
    rep_by_cell = {e["cell_id"]: e for e in adjudication["per_cell"]}
    targeted = [e for e in adjudication["per_cell"]
                if e["op_class"] in ("IS-I", "IS-A", "IS-C")]
    controls = [e for e in adjudication["per_cell"]
                if e["op_class"] in ("K-0", "K-1")]
    spec622 = (
        adjudication["batch_inconclusive"] is False and
        all(e["verdict"] == "PREDICTION-MATCH" for e in targeted) and
        all(e["verdict"] == "CONTROL-HOLD" for e in controls) and
        len(targeted) == 9 and len(controls) == 3)
    check("A8 SUPPORTED strictly per Spec §6.2 pre-registered rule "
          "(9/9 targeted PREDICTION-MATCH + controls HOLD + no "
          "inconclusive)", spec622)

    def expected_adjudicator_verdict(row):
        cell_id, cls, _sig, outcome_shape = row
        if cls in ("IS-I", "IS-A", "IS-C"):
            return "PREDICTION-MATCH" if outcome_shape == "only-target" \
                else "PREDICTION-MISMATCH"
        if cls == "IS-B":
            return "DERIVATION-CONSISTENT" if outcome_shape == "all-SATISFIED" \
                else "CROSS-OBSERVED"
        return "CONTROL-HOLD" if outcome_shape == "all-SATISFIED" \
            else "PREDICTION-MISMATCH"

    agree = all(rep_by_cell[row[0]]["verdict"] ==
                expected_adjudicator_verdict(row) for row in per_cell_rows)
    check("A8 audit recomputation agrees with independent adjudicator "
          "(14/14 verdicts)", agree)
    check("A8 campaign verdict recorded as SUPPORTED (no broadening)",
          adjudication["campaign_verdict"] == "SUPPORTED")

    # ---- report ------------------------------------------------------------
    n_pass = sum(1 for _n, ok, _d in CHECKS if ok)
    audit = {
        "run_uuid": setup["run_uuid"],
        "checks": [{"name": n, "pass": ok, "detail": d}
                   for n, ok, d in CHECKS],
        "per_cell_rows": per_cell_rows,
        "verdict": "AUDIT PASS" if not FAILED else "AUDIT FAIL",
        "failed": FAILED,
    }
    L.write_json(os.path.join(run_dir, "second_layer_audit.json"), audit)
    for n, ok, d in CHECKS:
        print(("PASS " if ok else "FAIL ") + n + ("  | " + d if d else ""))
    print("=== audit verdict: %s (%d/%d checks passed) ===" %
          (audit["verdict"], n_pass, len(CHECKS)))
    return 0 if not FAILED else 1


if __name__ == "__main__":
    sys.exit(main())
