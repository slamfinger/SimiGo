#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
IS-X cell runner — per RATIFIED design rev.2:

  construction record LOCKED FIRST (P_comp mechanically composed from the
  frozen single-variable predictors; resolution expectation mechanically
  traced for X-08/X-09) → fresh IS₀ copy → per-cell t₀ replication →
  apply op_a then op_b (composition error ⇒ INVALID-COMPOSITION) →
  construction integrity CI-1..CI-5 → t₁ evaluation → resolution trace
  → outcome → dual hash re-verification.
"""

import datetime
import json
import os
import shutil
import sys
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r32_lib as L
import isx_lib as X

DOUBT_SIGNATURES = {"A-UNRESOLVABLE", "C-INVALIDATION-INDEX-MISSING",
                    "C-DECL-NON-MECHANICAL", "I-UNSTRUCT"}


def utc_now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc) \
        .strftime("%Y-%m-%dT%H:%M:%SZ")


def main() -> int:
    run_dir = sys.argv[1]
    setup = L.read_json(os.path.join(run_dir, "setup_record.json"))
    if setup["validity"] != "VALID":
        print("setup INVALID — cells must not run (design §1a③)",
              file=sys.stderr)
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

    L.build_region_cache(is0)

    cells = {}
    setup_t0 = setup["t0_evaluation"]
    order = []
    for i, cell_op in enumerate(X.CAMPAIGN_ORDER, start=1):
        cell_id = "cell-%02d-%s" % (i, cell_op)
        order.append(cell_id)
        cell_dir = os.path.join(run_dir, "cells", cell_id)
        work = os.path.join(cell_dir, "IS")
        shutil.copytree(is0, work)

        # --- construction record LOCKED FIRST ------------------------------
        if X.derive_class(cell_op) == "IS-X":
            pair = X.PAIRS[cell_op]
            p_comp = X.predict_pair(cell_op, es)
            res_exp = None
            if "resolution_key" in pair:
                # H-X1: construction-time state trace of the composed index
                # (mechanical trace of frozen op effects, pre-run)
                idx = L.load_index(is0)
                trace = {"index_entries_preregistered":
                         idx.get(pair["resolution_key"], [])}
                res_exp = {"key": pair["resolution_key"],
                           "preregistered": _resolution_expectation(cell_op),
                           "construction_trace": trace}
            construction = {
                "cell_id": cell_id, "run_uuid": setup["run_uuid"],
                "cell_op": cell_op, "op_a": pair["op_a"], "op_b": pair["op_b"],
                "op_class": "IS-X",
                "p_comp": p_comp,
                "resolution_expectation": res_exp,
                "es_artifact_sha256": es_sha,
                "is0_canonical_sha256": is0_sha,
                "locked_before_evaluation": True,
                "locked_at_utc": utc_now_iso(),
            }
        else:
            construction = {
                "cell_id": cell_id, "run_uuid": setup["run_uuid"],
                "cell_op": cell_op, "op_class": X.derive_class(cell_op),
                "predicted": X.predict_cell(cell_op, es),
                "es_artifact_sha256": es_sha,
                "is0_canonical_sha256": is0_sha,
                "locked_before_evaluation": True,
                "locked_at_utc": utc_now_iso(),
            }
        L.write_json(os.path.join(cell_dir, "construction.json"), construction)
        obs("construction_locked", cell=cell_id, cell_op=cell_op,
            op_class=construction["op_class"])

        # --- per-cell t₀ replication ----------------------------------------
        t0 = L.eval_cons(es, work, pinned_ts, mode="setup")
        obs("t0_evaluated", cell=cell_id, result=t0)

        # --- apply composition (error ⇒ INVALID-COMPOSITION, H-X3) ----------
        composition = "OK"
        comp_error = None
        t_apply0 = time.monotonic()
        try:
            if X.derive_class(cell_op) == "IS-X":
                for op_id in (construction["op_a"], construction["op_b"]):
                    X.get_op_fn(op_id)(work)
                    obs("op_applied", cell=cell_id, op_id=op_id)
            elif X.derive_class(cell_op) == "SANITY":
                import r3n_lib as N
                N.N_CATALOG[cell_op]["fn"](work)
                obs("op_applied", cell=cell_id, op_id=cell_op)
            else:
                obs("op_applied", cell=cell_id, op_id="R32-K-0")
        except Exception as exc:  # construction failure only (H-X3)
            composition = "INVALID-COMPOSITION"
            comp_error = "%s: %s" % (type(exc).__name__, exc)
            obs("composition_error", cell=cell_id, error=comp_error,
                trace=traceback.format_exc(limit=3))
        obs("composition_completed", cell=cell_id, composition=composition,
            duration_s=round(time.monotonic() - t_apply0, 6))

        # --- construction integrity CI-1..CI-5 (H-X4) ------------------------
        ci = {"pass": None, "failures": {}}
        if composition == "OK" and X.derive_class(cell_op) == "IS-X":
            pair = X.PAIRS[cell_op]
            replay = os.path.join(cell_dir, "replay-IS")
            shutil.copytree(is0, replay)
            X.get_op_fn(pair["op_a"])(replay)
            X.get_op_fn(pair["op_b"])(replay)
            ok, fails = X.construction_integrity(
                cell_op, pair["op_a"], pair["op_b"], work, is0, replay)
            ci = {"pass": ok, "failures": fails}
            obs("construction_integrity", cell=cell_id, ci_pass=ok,
                ci_failures=fails)
            shutil.rmtree(replay, ignore_errors=True)

        # --- t₁ evaluation (only if composition formed, H-X3) ----------------
        if composition == "OK":
            t1 = L.eval_cons(es, work, pinned_ts, mode="t1")
        else:
            t1 = None
        obs("t1_evaluated", cell=cell_id,
            result=t1, composition=composition)

        # --- resolution trace (H-X1: actual vs preregistered expectation) ---
        resolution_actual = None
        if composition == "OK" and X.derive_class(cell_op) == "IS-X" and \
           "resolution_key" in X.PAIRS[cell_op]:
            resolution_actual = X.resolution_trace(
                work, X.PAIRS[cell_op]["resolution_key"])
            obs("resolution_traced", cell=cell_id, **resolution_actual)

        # --- doubt + integrity ------------------------------------------------
        doubt_sigs = []
        if t1:
            for cond in ("I", "A", "C"):
                sig = t1[cond]["signature"]
                if sig in DOUBT_SIGNATURES:
                    doubt_sigs.append(sig)
        instrument_doubt = "YES" if doubt_sigs else "NO"

        es_hash_after = L.sha256_file(os.path.join(run_dir, "es-artifact.json"))
        is0_hash_after = L.sha256_dir(is0)
        integrity = {
            "es_hash_after": es_hash_after,
            "es_unchanged": es_hash_after == es_sha,
            "is0_canonical_hash_after": is0_hash_after,
            "is0_unchanged": is0_hash_after == is0_sha,
        }

        outcome = {
            "cell_id": cell_id, "cell_op": cell_op,
            "op_class": construction["op_class"],
            "p_comp": construction.get("p_comp"),
            "predicted": construction.get("predicted"),
            "resolution_expectation": construction.get(
                "resolution_expectation"),
            "resolution_actual": resolution_actual,
            "composition": composition,
            "composition_error": comp_error,
            "construction_integrity": ci,
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
        "campaign_order": order,
        "integrity_all_clean": all(c["integrity"]["es_unchanged"] and
                                   c["integrity"]["is0_unchanged"]
                                   for c in cells.values()),
        "t0_consistency_all": all(c["t0_matches_setup"]
                                  for c in cells.values()),
        "invalid_compositions": [cid for cid, c in cells.items()
                                 if c["composition"] ==
                                 "INVALID-COMPOSITION"],
        "ci_failures": [cid for cid, c in cells.items()
                        if c["construction_integrity"]["pass"] is False],
    }
    L.write_json(os.path.join(run_dir, "run-summary.json"), summary)
    obs("campaign_completed", **summary)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


def _resolution_expectation(cell_op: str) -> dict:
    """H-X1: construction-time resolution expectation, mechanically
    derived from the frozen op effects (design §2a) — NOT from t1."""
    if cell_op == "X-08":
        return {"index_key": "lineage-root",
                "expected_candidate_count": 1,
                "expected_resolved_target":
                    "lineage/lineage-root-conflict.json",
                "expected_surviving_anchor": "conflict record",
                "derivation": "Δ2 deletes orig+drops key; Δ3 writes "
                              "conflict+sets index [orig,conflict]; "
                              "existence filter leaves conflict only"}
    if cell_op == "X-09":
        return {"index_key": "lineage-root",
                "expected_candidate_count": 0,
                "expected_resolved_target": None,
                "expected_surviving_anchor": None,
                "derivation": "Δ3 sets index [orig,conflict]; Δ2 deletes "
                              "orig+pops key → key absent"}
    return {}


if __name__ == "__main__":
    sys.exit(main())
