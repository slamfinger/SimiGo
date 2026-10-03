#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
R3-2 cell runner — per design §1/§4/§4a/§6:

  for each frozen-catalog op:
    construction record LOCKED FIRST (class mechanically derived, prediction
    mechanically derived, `locked_before_evaluation: true`) →
    fresh IS₀ copy → per-cell t₀ (instrument-consistency replication) →
    apply ΔIS → t₁ evaluation → outcome record → dual hash re-verification.

Appends to observations.jsonl; writes construction.json and outcome.json as
physically separate files (evaluation can only append outcomes).
"""

import datetime
import json
import os
import shutil
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r32_lib as L

EVIDENCE_ROOT = os.path.join(
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")),
    "docs", "02-evidence", "r3-2-execution")

DOUBT_SIGNATURES = {"A-UNRESOLVABLE", "C-INVALIDATION-INDEX-MISSING",
                    "C-DECL-NON-MECHANICAL", "I-UNSTRUCT"}


def utc_now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc) \
        .strftime("%Y-%m-%dT%H:%M:%SZ")


def main() -> int:
    run_dir = sys.argv[1]
    setup = L.read_json(os.path.join(run_dir, "setup_record.json"))
    if setup["validity"] != "VALID":
        print("setup INVALID — cells must not run (design §1a③)", file=sys.stderr)
        return 1
    es = L.read_json(os.path.join(run_dir, "es-artifact.json"))
    es_sha = setup["es_artifact_sha256"]
    is0 = os.path.join(run_dir, "is0-canonical")
    is0_sha = setup["is0_canonical_sha256"]
    pinned_ts = setup["setup_pinned_timestamp"]
    log_path = os.path.join(run_dir, "observations.jsonl")

    def obs(event, cell=None, **kw):
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps({"run_uuid": setup["run_uuid"], "event": event,
                                "cell": cell,
                                "monotonic": round(time.monotonic(), 6),
                                "wall_utc": utc_now_iso(), **kw},
                               ensure_ascii=False, sort_keys=True) + "\n")

    # construction-time region∩referenced knowledge (design §9 predictor)
    L.build_region_cache(is0)

    cells = {}
    setup_t0 = setup["t0_evaluation"]
    for i, op_id in enumerate(L.CAMPAIGN_ORDER, start=1):
        cell_id = "cell-%02d-%s" % (i, op_id)
        cell_dir = os.path.join(run_dir, "cells", cell_id)
        work = os.path.join(cell_dir, "IS")
        shutil.copytree(is0, work)

        # --- construction record LOCKED FIRST (design §4/§4a) --------------
        construction = {
            "cell_id": cell_id,
            "run_uuid": setup["run_uuid"],
            "op_id": op_id,
            "op_class": L.derive_class(op_id),
            "es_artifact_sha256": es_sha,
            "is0_canonical_sha256": is0_sha,
            "predicted": L.predict(op_id, es),
            "locked_before_evaluation": True,
            "locked_at_utc": utc_now_iso(),
        }
        L.write_json(os.path.join(cell_dir, "construction.json"), construction)
        obs("construction_locked", cell=cell_id, op_id=op_id,
            op_class=construction["op_class"])

        # --- per-cell t₀: instrument-consistency replication (§1a④) --------
        t0 = L.eval_cons(es, work, pinned_ts, mode="setup")
        obs("t0_evaluated", cell=cell_id, result=t0)

        # --- apply ΔIS (frozen catalog) ------------------------------------
        t_apply0 = time.monotonic()
        L.CATALOG[op_id]["fn"](work)
        obs("op_applied", cell=cell_id, op_id=op_id,
            duration_s=round(time.monotonic() - t_apply0, 6))

        # --- t₁ evaluation --------------------------------------------------
        t1 = L.eval_cons(es, work, pinned_ts, mode="t1")
        obs("t1_evaluated", cell=cell_id, result=t1)

        # --- instrument_doubt determination (Spec §5.3 / design §8) ---------
        doubt_sigs = []
        for cond in ("I", "A", "C"):
            sig = t1[cond]["signature"]
            if sig in DOUBT_SIGNATURES:
                doubt_sigs.append(sig)
            if t0[cond]["signature"] in DOUBT_SIGNATURES:
                doubt_sigs.append("t0:" + t0[cond]["signature"])
        instrument_doubt = "YES" if doubt_sigs else "NO"

        # --- dual hash re-verification (design §6 H-E) ----------------------
        es_hash_after = L.sha256_file(os.path.join(run_dir, "es-artifact.json"))
        is0_hash_after = L.sha256_dir(is0)
        integrity = {
            "es_hash_after": es_hash_after,
            "es_unchanged": es_hash_after == es_sha,
            "is0_canonical_hash_after": is0_hash_after,
            "is0_unchanged": is0_hash_after == is0_sha,
        }

        outcome = {
            "cell_id": cell_id,
            "op_id": op_id,
            "op_class": construction["op_class"],
            "predicted": construction["predicted"],
            "t0_evaluation": t0,
            "t0_matches_setup": t0["cons"] == setup_t0["cons"] and
                                all(t0[c] == setup_t0[c]
                                    for c in ("I", "A", "C")),
            "t1_evaluation": t1,
            "instrument_doubt": instrument_doubt,
            "doubt_signatures": doubt_sigs,
            "integrity": integrity,
        }
        L.write_json(os.path.join(cell_dir, "outcome.json"), outcome)
        obs("integrity_verified", cell=cell_id, **integrity)
        cells[cell_id] = outcome

    summary = {
        "run_uuid": setup["run_uuid"],
        "cells_run": len(cells),
        "campaign_order": L.CAMPAIGN_ORDER,
        "integrity_all_clean": all(c["integrity"]["es_unchanged"] and
                                   c["integrity"]["is0_unchanged"]
                                   for c in cells.values()),
        "t0_consistency_all": all(c["t0_matches_setup"] for c in cells.values()),
    }
    L.write_json(os.path.join(run_dir, "run-summary.json"), summary)
    obs("campaign_completed", **summary)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
