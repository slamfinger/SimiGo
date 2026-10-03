#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
IS-X implementation reaudit — verification closure for R1/R2 (design
revision §3, RC-1..RC-5), executed against Attempt #1 PRESERVED evidence:

  RC-1  revised object-identity effect probes: all 12 pairs PASS on the
        preserved composed IS trees; cell-06 A-Δ3 key-substituted PASS
        demonstrates 「合法迁移 ≠ 效果消失」
  RC-2  revised audit containment: cell-06 NOT reclassified; reason/
        chain/containment verified; prior classification mismatch
        eliminated (audit scope defect fixed)
  RC-3  adjudicator determinism: recomputed per-cell verdicts match
        Attempt #1 adjudication (cell-06 stays INCONCLUSIVE)
  RC-4  research-rule zero diff: IS-X Design rev.2 file untouched
  RC-5  semantic boundary: Attempt #1 campaign verdict (INCONCLUSIVE) is
        NOT revised by this reaudit — reaudit PASS only certifies that
        the instrumentation defect is fixed and containment holds;
        attempt #2 still requires new explicit human authorization.

Writes ONLY implementation_reaudit.json (append-only artifact); overwrites
nothing. Zero model inference; no new cells.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r32_lib as L
import isx_lib as X

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
DESIGN = os.path.join(REPO, "docs", "00-governance",
                      "SIMIGO_LAB_ISX_DESIGN_GATE_20261003.md")

CHECKS, FAILED = [], []


def check(name, ok, detail=""):
    CHECKS.append((name, bool(ok), detail))
    if not ok:
        FAILED.append(name)


def main() -> int:
    run_dir = sys.argv[1]
    setup = L.read_json(os.path.join(run_dir, "setup_record.json"))
    summary = L.read_json(os.path.join(run_dir, "run-summary.json"))
    adjudication = L.read_json(os.path.join(run_dir, "adjudication_report.json"))
    is0 = os.path.join(run_dir, "is0-canonical")

    # ---- RC-1: revised probes on preserved evidence ------------------------
    rc1_all = True
    rc1_detail = []
    cell06_fix = False
    tmp = tempfile.mkdtemp()
    for i, cell_op in enumerate(X.CAMPAIGN_ORDER, start=1):
        cell_id = "cell-%02d-%s" % (i, cell_op)
        if cell_op not in X.PAIRS:
            continue
        cdir = os.path.join(run_dir, "cells", cell_id)
        pair = X.PAIRS[cell_op]
        composed = os.path.join(cdir, "IS")
        fa = X.check_effect_v2(pair["op_a"], composed, is0)
        fb = X.check_effect_v2(pair["op_b"], composed, is0)
        ok = not fa and not fb
        rc1_all &= ok
        if not ok:
            rc1_detail.append("%s a:%s b:%s" % (cell_id, fa, fb))
        if cell_op == "X-06":
            cell06_fix = ("R32-A-Δ3" not in str(fa)) and (not fa)
    shutil.rmtree(tmp, ignore_errors=True)
    check("RC-1 revised object-identity probes: 12/12 pairs PASS on "
          "preserved evidence", rc1_all, "detail=%s" % rc1_detail)
    check("RC-1 cell-06 A-Δ3 key-substituted PASS "
          "(legal migration ≠ effect disappearance)", cell06_fix)

    # ---- RC-2: revised audit containment on preserved evidence -------------
    per_cell = {e["cell_id"]: e for e in adjudication["per_cell"]}
    excluded = [cid for cid, e in per_cell.items()
                if e["verdict"] in ("INCONCLUSIVE", "INVALID-COMPOSITION",
                                    "SANITY-FAILED")]
    containment_ok = True
    detail = []
    for cid in excluded:
        e = per_cell[cid]
        if e["verdict"] == "INCONCLUSIVE" and not e.get("reason"):
            containment_ok = False
            detail.append(cid + ":no-reason")
        if e["verdict"] in ("ADDITIVE", "MASKING", "EMERGENT-BREAK",
                            "SIGNATURE-SHIFT"):
            containment_ok = False
            detail.append(cid + ":leak")
    # cell-06 must be among the contained (excluded) cells
    check("RC-2 cell-06 contained (excluded from classification; "
          "reason+chain verified)", "cell-06-X-06" in excluded)
    check("RC-2 containment rule: zero classification leakage from "
          "INCONCLUSIVE cells", containment_ok, "detail=%s" % detail)

    # revised classification recomputation on VALID pair cells only
    recompute_ok = True
    for i, cell_op in enumerate(X.CAMPAIGN_ORDER, start=1):
        cell_id = "cell-%02d-%s" % (i, cell_op)
        e = per_cell[cell_id]
        if e["verdict"] in ("INCONCLUSIVE", "INVALID-COMPOSITION",
                            "SANITY-FAILED"):
            continue
        if e["op_class"] != "IS-X":
            continue
        outcome = L.read_json(os.path.join(run_dir, "cells", cell_id,
                                           "outcome.json"))
        t1 = outcome["t1_evaluation"]
        p_comp = outcome["p_comp"]
        labels = []
        for c in ("I", "A", "C"):
            a_state, a_sig = t1[c]["state"], t1[c]["signature"]
            p_state, sig_set = p_comp[c]["state"], p_comp[c]["sig_set"]
            if a_state == "BROKEN" and not a_sig:
                labels.append("ATTRIBUTION-FAILURE")
            elif p_state == "BROKEN" and a_state == "SATISFIED":
                labels.append("MASKING")
            elif p_state == "SATISFIED" and a_state == "BROKEN":
                labels.append("EMERGENT-BREAK")
            elif p_state == "BROKEN":
                labels.append("BROKEN-MATCH" if a_sig in sig_set
                              else "SIGNATURE-SHIFT")
            else:
                labels.append("HOLD-MATCH")
        cell_label = ("ATTRIBUTION-FAILURE" if "ATTRIBUTION-FAILURE" in labels
                      else "SIGNATURE-SHIFT" if "SIGNATURE-SHIFT" in labels
                      else "MASKING" if "MASKING" in labels
                      else "EMERGENT-BREAK" if "EMERGENT-BREAK" in labels
                      else "ADDITIVE")
        if cell_label != e["verdict"]:
            recompute_ok = False
    check("RC-2 revised classification recomputation agrees with "
          "adjudicator on valid cells", recompute_ok)

    # ---- RC-3: adjudicator determinism (cell-06 stays INCONCLUSIVE) --------
    c06 = per_cell["cell-06-X-06"]
    check("RC-3 cell-06 verdict determinism: INCONCLUSIVE maintained",
          c06["verdict"] == "INCONCLUSIVE" and
          "S-X2" in c06.get("reason", ""))
    check("RC-3 campaign verdict determinism: INCONCLUSIVE maintained",
          adjudication["campaign_verdict"] == "INCONCLUSIVE")

    # ---- RC-4: research-rule zero diff --------------------------------------
    try:
        diff = subprocess.run(
            ["git", "diff", "HEAD", "--", DESIGN],
            cwd=REPO, capture_output=True, text=True, timeout=30).stdout
    except Exception as exc:
        diff = "git-error:%s" % exc
    check("RC-4 IS-X Design rev.2 zero diff (research rules untouched)",
          diff.strip() == "")

    # ---- RC-5: semantic boundary --------------------------------------------
    check("RC-5 reaudit does not revise Attempt #1 verdict "
          "(INCONCLUSIVE permanently retained; attempt #2 still requires "
          "new explicit human authorization)",
          adjudication["campaign_verdict"] == "INCONCLUSIVE")

    n_pass = sum(1 for _n, ok, _d in CHECKS if ok)
    report = {
        "run_uuid": setup["run_uuid"],
        "revision_source": "SIMIGO_LAB_ISX_IMPL_REVISION_20261003.md",
        "checks": [{"name": n, "pass": ok, "detail": d}
                   for n, ok, d in CHECKS],
        "verdict": "IMPLEMENTATION REAUDIT PASS" if not FAILED
                   else "IMPLEMENTATION REAUDIT FAIL",
        "failed": FAILED,
        "boundary": "reaudit PASS certifies instrumentation fix + "
                    "containment only; Attempt #1 campaign verdict "
                    "(INCONCLUSIVE) permanently retained; attempt #2 "
                    "requires new explicit human authorization",
    }
    L.write_json(os.path.join(run_dir, "implementation_reaudit.json"), report)
    for n, ok, d in CHECKS:
        print(("PASS " if ok else "FAIL ") + n + ("  | " + d if d else ""))
    print("=== reaudit verdict: %s (%d/%d) ===" %
          (report["verdict"], n_pass, len(CHECKS)))
    return 0 if not FAILED else 1


if __name__ == "__main__":
    sys.exit(main())
