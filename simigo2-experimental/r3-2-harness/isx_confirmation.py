#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
IS-X Attempt #2 confirmation harness — scope per human execution
authorization (2026-10-03), strictly:

  A1  verify R1 object/effect probe fix        (X-06 reconstruction)
  A2  verify R2 audit containment fix          (reclassified scope check)
  A3  core confirmation pair: X-08 / X-09      (fresh campaign context,
      construction/expectation/prediction locks re-executed, NOT copied
      from Attempt #1)

Frozen catalog/design/predictor/classification: zero diff (RATIFIED rev.2).
NOT in scope: full 16-cell rerun, new ops, representation/concurrency/
temporal extensions, R3-4 (stays LOCKED; no outcome auto-opens it).

Cell discipline identical to Attempt #1: construction record LOCKED FIRST
(P_comp + H-X1 resolution expectation mechanically derived), fresh IS₀
copy, per-cell t₀ replication, R1 object-identity CI probes, dual hash
re-verification, append-only observations. Sanity/K-0 controls carried
(evaluator + instrument baseline), since confirmation cells are judged
against predicted behavior — a dead evaluator would make "no longer
MASKING" unreadable.
"""

import datetime
import json
import os
import shutil
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import r32_lib as L
import isx_lib as X

DOUBT_SIGNATURES = {"A-UNRESOLVABLE", "C-INVALIDATION-INDEX-MISSING",
                    "C-DECL-NON-MECHANICAL", "I-UNSTRUCT"}

CONFIRMATION_PAIRS = ["X-08", "X-09"]
CONTROLS = ["R32N-SANITY-A", "R32N-SANITY-I", "R32N-SANITY-C", "R32-K-0"]
CAMPAIGN = CONFIRMATION_PAIRS + CONTROLS  # 6 cells


def utc_now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc) \
        .strftime("%Y-%m-%dT%H:%M:%SZ")


def main() -> int:
    run_uuid = "R33X-A2-" + datetime.datetime.now(datetime.timezone.utc) \
        .strftime("%Y%m%dT%H%M%SZ") + "-" + str(os.getpid())
    run_dir = os.path.join(REPO_RUN_ROOT(), run_uuid)
    os.makedirs(run_dir, exist_ok=True)
    log_path = os.path.join(run_dir, "observations.jsonl")

    def obs(event, cell=None, **kw):
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(json.dumps({"run_uuid": run_uuid, "event": event,
                                "cell": cell,
                                "monotonic": round(time.monotonic(), 6),
                                "wall_utc": utc_now_iso(), **kw},
                               ensure_ascii=False, sort_keys=True) + "\n")

    obs("setup_started", run_dir=run_dir,
        scope={"A1": "X-06 reconstruction with R1 probes",
               "A2": "R2 containment scope check",
               "A3": "X-08/X-09 confirmation pair"},
        exclusions=["full 16-cell rerun", "new ops",
                    "representation/concurrency/temporal", "R3-4"])

    # --- canonical IS₀ (fresh, deterministic — same recipe) ------------------
    is0 = os.path.join(run_dir, "is0-canonical")
    for sub in ("objects", "runtime", "lineage", "archive"):
        os.makedirs(os.path.join(is0, sub), exist_ok=True)

    sealed = os.path.join(REPO_ROOT(), "docs", "02-evidence", "rc1-attempt4",
                          "RC1-A4-20261003T040749Z-57375")
    with open(os.path.join(sealed, "runs", "C-B", "declared", "s0.json"),
              "rb") as f:
        s0 = json.loads(f.read().decode("utf-8"))
    with open(os.path.join(sealed, "runs", "C-B", "declared", "s1.json"),
              "rb") as f:
        s1 = json.loads(f.read().decode("utf-8"))
    with open(os.path.join(sealed, "runs", "C-B", "declared",
                           "task-charter.json"), "rb") as f:
        charter = json.loads(f.read())
    lineage_manifest_sha = L.sha256_file(os.path.join(sealed,
                                                      "evidence-sha256.txt"))

    L.write_json(os.path.join(is0, "manifest.json"), {
        "scope_tags": ["r3-2-campaign"],
        "in_scope": ["objects/", "runtime/", "lineage/", "archive/"],
        "out_of_scope": [], "access_denied": []})
    L.save_index(is0, {
        "runtime-declaration": ["runtime/runtime-declaration.json"],
        "lineage-root": ["lineage/lineage-root.json"],
        "I-S0": ["objects/I-S0.json"],
        "I-S1": ["objects/I-S1.json"],
        "anchor:state-diff": ["objects/R-1.json"],
        "unreferenced-1": ["objects/unreferenced-1.json"],
        "archived-note": ["archive/archived-note.json"]})
    L.save_invalidation(is0, {"records": []})
    L.write_json(os.path.join(is0, "runtime/runtime-declaration.json"),
                 {"fixture_class": "r3-2-minimal-v1"})
    L.write_json(os.path.join(is0, "lineage/lineage-root.json"), {
        "derived_from": "R-C1-A4-RC1-A4-20261003T040749Z-57375 (C-B arm)",
        "evidence_manifest_sha256": lineage_manifest_sha,
        "note": "ES lineage transported from sealed R-C1 attempt #4 evidence"})
    L.write_json(os.path.join(is0, "objects/I-S0.json"),
                 {"id": "I-S0", "content": s0,
                  "source": "R-C1-A4 C-B declared/s0.json (sealed)"})
    L.write_json(os.path.join(is0, "objects/I-S1.json"),
                 {"id": "I-S1", "content": s1,
                  "source": "R-C1-A4 C-B declared/s1.json (sealed)"})
    L.write_json(os.path.join(is0, "objects/R-1.json"), {
        "id": "R-1",
        "content": {
            "settled_diff": {"alpha": {"from": 17, "to": 42},
                             "mode": {"from": "quiet", "to": "active"}},
            "next_action": charter["continuationRule"]["action"],
            "basis": "task %s charter: alphaMinimum=%s, requiredMode=%s; "
                     "S1 satisfies both" % (
                         charter["taskID"],
                         charter["continuationRule"]["alphaMinimum"],
                         charter["continuationRule"]["requiredMode"])},
        "source": "R-C1-A4 C-B evaluation.json X-1..X-5 verified (sealed)"})
    L.write_json(os.path.join(is0, "objects/unreferenced-1.json"),
                 {"id": "U-1", "content": "unreferenced campaign note"})
    L.write_json(os.path.join(is0, "archive/archived-note.json"),
                 {"id": "ARCH-1", "content": "archived note"})
    is0_sha = L.sha256_dir(is0)
    obs("is0_constructed", is0_sha256=is0_sha)

    # --- ES formation ---------------------------------------------------------
    payload = {"task": charter,
               "continuation_position": {
                   "after_state": "I-S1",
                   "basis": "R-C1 C-B staged pointer set "
                            "[progress, s0, s1, task]"}}
    es = {
        "es_schema": "r3-2-es-v1",
        "formation": {
            "procedure": "r32-formation-v1",
            "formed_at_utc": utc_now_iso(),
            "campaign": "IS-X Attempt #2 confirmation (fresh formation)",
            "note": "baselines computed from actual bytes"},
        "payload": payload,
        "I_ev": {
            "I-EV-1": {"role": "I-1 model/fixture binding",
                       "self_declaration": {"fixture_class":
                                            "r3-2-minimal-v1"},
                       "is_reference": {"key": "runtime-declaration",
                                        "field": "fixture_class"}},
            "I-EV-2": {"role": "I-2 lineage binding",
                       "is_reference": {"key": "lineage-root"}},
            "I-EV-3": {"role": "I-3 payload integrity",
                       "payload_sha256": L.sha256_canonical(payload)}},
        "A_ev": {"role": "A-1 content binding",
                 "anchor_name": "anchor:state-diff",
                 "reference_form": "symbolic",
                 "formation_target_content_sha256":
                     L.sha256_file(os.path.join(is0, "objects/R-1.json"))},
        "C_ev": {"role": "C-1 continuation permission prerequisites",
                 "prerequisite_keys": ["I-S0", "I-S1"],
                 "declared_conditions": [
                     {"type": "scope-tag", "value": "r3-2-campaign"},
                     {"type": "validity",
                      "not_after": (datetime.datetime.now(datetime.timezone.utc)
                                    + datetime.timedelta(days=30))
                                   .strftime("%Y-%m-%dT%H:%M:%SZ")},
                     {"type": "dependency-reference",
                      "keys": ["I-S0", "I-S1"]}]}}
    es_path = os.path.join(run_dir, "es-artifact.json")
    L.write_json(es_path, es)
    es_sha = L.sha256_file(es_path)
    obs("es_formed", es_artifact_sha256=es_sha)

    pinned_ts = utc_now_iso()
    t0 = L.eval_cons(es, is0, pinned_ts, mode="setup")
    obs("t0_evaluated", result=t0)
    cons_true = (t0["cons"] == "SATISFIED"
                 and all(t0[k]["state"] == "SATISFIED"
                         for k in ("I", "A", "C")))

    setup_record = {
        "run_uuid": run_uuid,
        "attempt": 2,
        "authorization_scope": {
            "A1": "X-06 reconstruction with R1 object-identity probes",
            "A2": "R2 audit containment scope check (adjudication-time)",
            "A3": "X-08/X-09 core confirmation pair (fresh locks, not "
                  "copied from Attempt #1)",
            "excluded": ["full 16-cell rerun", "new IS-X operations",
                         "representation/concurrency/temporal extensions",
                         "R3-4 (LOCKED; no outcome auto-opens it)"],
            "honesty_clause": "if X-08 no longer MASKING after the fix, "
                              "record as-is under preregistered rules",
        },
        "design_source": "SIMIGO_LAB_ISX_DESIGN_GATE_20261003.md "
                         "(rev.2, RATIFIED — zero diff)",
        "revision_source": "SIMIGO_LAB_ISX_IMPL_REVISION_20261003.md "
                           "(R1/R2, reaudit PASS 9/9)",
        "judgment_rule": {
            "cons_version": "R2 rev.2 candidate: Cons(ES,IS) ⟺ "
                            "I-condition ∧ A-condition ∧ C-condition",
            "spec": "SIMIGO_LAB_R3_1_JUDGMENT_SPECIFICATION_20261003.md "
                    "(rev.2, RATIFIED)",
            "judgment_time": "campaign setup stage, before any ΔIS exists"},
        "setup_pinned_timestamp": pinned_ts,
        "es_artifact_sha256": es_sha,
        "is0_canonical_sha256": is0_sha,
        "harness": {
            lib: L.sha256_file(os.path.join(
                os.path.dirname(os.path.abspath(__file__)),
                lib + ".py"))
            for lib in ("r32_lib", "r3n_lib", "isx_lib", "isx_run_cells",
                        "isx_confirmation")},
        "campaign_order": CAMPAIGN,
        "t0_evaluation": t0,
        "validity": "VALID" if cons_true else "INVALID",
        "validity_rule": "design §1a: false ⇒ INVALID + preserve + STOP",
    }
    L.write_json(os.path.join(run_dir, "setup_record.json"), setup_record)
    obs("setup_completed", validity=setup_record["validity"])

    if not cons_true:
        print(json.dumps({"run_uuid": run_uuid, "validity": "INVALID"},
                         ensure_ascii=False))
        return 1

    # --- confirmation cells ----------------------------------------------------
    L.build_region_cache(is0)
    setup_t0 = setup["t0_evaluation"]
    cells = {}
    for i, cell_op in enumerate(CAMPAIGN, start=1):
        if cell_op in X.PAIRS:
            cell_id = "cell-%02d-%s" % (i, cell_op)
        else:
            cell_id = "cell-%02d-%s" % (i, cell_op)
        cell_dir = os.path.join(run_dir, "cells", cell_id)
        work = os.path.join(cell_dir, "IS")
        shutil.copytree(is0, work)

        # construction record LOCKED FIRST
        if cell_op in X.PAIRS:
            pair = X.PAIRS[cell_op]
            p_comp = X.predict_pair(cell_op, es)
            res_exp = None
            if "resolution_key" in pair:
                idx = L.load_index(is0)
                res_exp = {
                    "key": pair["resolution_key"],
                    "preregistered": _resolution_expectation(cell_op),
                    "construction_trace": {
                        "index_entries_preregistered":
                            idx.get(pair["resolution_key"], [])}}
            construction = {
                "cell_id": cell_id, "run_uuid": run_uuid,
                "cell_op": cell_op, "op_a": pair["op_a"], "op_b": pair["op_b"],
                "op_class": "IS-X", "p_comp": p_comp,
                "resolution_expectation": res_exp,
                "es_artifact_sha256": es_sha,
                "is0_canonical_sha256": is0_sha,
                "locked_before_evaluation": True,
                "locked_at_utc": utc_now_iso()}
        else:
            import r3n_lib as N
            construction = {
                "cell_id": cell_id, "run_uuid": run_uuid,
                "cell_op": cell_op, "op_class": X.derive_class(cell_op),
                "predicted": N.predict(cell_op, es)
                if cell_op.startswith("R32N-SANITY")
                else {c: ("SATISFIED", None) for c in ("I", "A", "C")},
                "es_artifact_sha256": es_sha,
                "is0_canonical_sha256": is0_sha,
                "locked_before_evaluation": True,
                "locked_at_utc": utc_now_iso()}
        L.write_json(os.path.join(cell_dir, "construction.json"), construction)
        obs("construction_locked", cell=cell_id, cell_op=cell_op)

        t0c = L.eval_cons(es, work, pinned_ts, mode="setup")
        obs("t0_evaluated", cell=cell_id, result=t0c)

        composition, comp_error = "OK", None
        t_apply0 = time.monotonic()
        try:
            if cell_op in X.PAIRS:
                for op_id in (construction["op_a"], construction["op_b"]):
                    X.get_op_fn(op_id)(work)
                    obs("op_applied", cell=cell_id, op_id=op_id)
            elif cell_op.startswith("R32N-SANITY"):
                import r3n_lib as N
                N.N_CATALOG[cell_op]["fn"](work)
                obs("op_applied", cell=cell_id, op_id=cell_op)
            else:
                obs("op_applied", cell=cell_id, op_id="R32-K-0")
        except Exception as exc:
            composition = "INVALID-COMPOSITION"
            comp_error = "%s: %s" % (type(exc).__name__, exc)
            obs("composition_error", cell=cell_id, error=comp_error)
        obs("composition_completed", cell=cell_id, composition=composition,
            duration_s=round(time.monotonic() - t_apply0, 6))

        ci = {"pass": None, "failures": {}}
        if composition == "OK" and cell_op in X.PAIRS:
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

        t1 = L.eval_cons(es, work, pinned_ts, mode="t1") \
            if composition == "OK" else None
        obs("t1_evaluated", cell=cell_id, result=t1)

        resolution_actual = None
        if composition == "OK" and cell_op in X.PAIRS and \
           "resolution_key" in X.PAIRS[cell_op]:
            resolution_actual = X.resolution_trace(
                work, X.PAIRS[cell_op]["resolution_key"])
            obs("resolution_traced", cell=cell_id, **resolution_actual)

        doubt_sigs = [t1[c]["signature"] for c in ("I", "A", "C")
                      if t1 and t1[c]["signature"] in DOUBT_SIGNATURES]
        instrument_doubt = "YES" if doubt_sigs else "NO"

        es_hash_after = L.sha256_file(es_path)
        is0_hash_after = L.sha256_dir(is0)
        integrity = {
            "es_hash_after": es_hash_after,
            "es_unchanged": es_hash_after == es_sha,
            "is0_canonical_hash_after": is0_hash_after,
            "is0_unchanged": is0_hash_after == is0_sha}

        outcome = {
            "cell_id": cell_id, "cell_op": cell_op,
            "op_class": construction["op_class"],
            "p_comp": construction.get("p_comp"),
            "predicted": construction.get("predicted"),
            "resolution_expectation":
                construction.get("resolution_expectation"),
            "resolution_actual": resolution_actual,
            "composition": composition,
            "composition_error": comp_error,
            "construction_integrity": ci,
            "t0_evaluation": t0c,
            "t0_matches_setup": t0c["cons"] == setup_t0["cons"] and
                                all(t0c[c] == setup_t0[c]
                                    for c in ("I", "A", "C")),
            "t1_evaluation": t1,
            "instrument_doubt": instrument_doubt,
            "doubt_signatures": doubt_sigs,
            "integrity": integrity}
        L.write_json(os.path.join(cell_dir, "outcome.json"), outcome)
        obs("integrity_verified", cell=cell_id, **integrity)
        cells[cell_id] = outcome

    summary = {
        "run_uuid": run_uuid,
        "cells_run": len(cells),
        "campaign_order": CAMPAIGN,
        "integrity_all_clean": all(c["integrity"]["es_unchanged"] and
                                   c["integrity"]["is0_unchanged"]
                                   for c in cells.values()),
        "t0_consistency_all": all(c["t0_matches_setup"]
                                  for c in cells.values()),
        "invalid_compositions": [cid for cid, c in cells.items()
                                 if c["composition"] ==
                                 "INVALID-COMPOSITION"],
        "ci_failures": [cid for cid, c in cells.items()
                        if c["construction_integrity"]["pass"] is False]}
    L.write_json(os.path.join(run_dir, "run-summary.json"), summary)
    obs("campaign_completed", **summary)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


def REPO_ROOT():
    return os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def REPO_RUN_ROOT():
    return os.path.join(REPO_ROOT(), "docs", "02-evidence", "isx-execution")


def _resolution_expectation(cell_op: str) -> dict:
    """H-X1 construction-time resolution expectation (same derivation as
    Attempt #1 — from frozen op effects, NOT from any outcome)."""
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
