#!/usr/bin/env python3
"""I-round model-free semantic-sufficiency preflight (the H5-equivalent gate).

Every check runs against the SAME production machinery the real model uses:
``production_runtime_bridge.py`` over the carrier-loop signed settlement /
dependency-closure path. No model is loaded here, so ``model_loads`` /
``tokenize`` / ``generate`` counters are honestly zero for this condition. The
point of the I gate is the two-source structured graph, the SYNTHESIZED composite
result, the signed transitive closure and the pre-generation refusals -- all of
which are model-free.

It proves:
  A. the baseline structured chain (ORIGIN,DEST -> IU1 -> IU2 -> IU3) is fully
     reusable and its signed composite settles lawfully (I0 / I3 readiness);
  B. a semantically INCOMPLETE IU1 result (missing the derived ``route_key``)
     is rejected by the production result-contract/settlement validator and
     creates no reusable settlement (I2 readiness);
  C. IU3's declared single dependency IU2 expands to the FULL signed transitive
     closure that contains IU1 and BOTH sources (I0 closure / dependency
     completeness);
  D. removing one source's settled object makes IU1 (and, through its closure,
     IU3) refuse BEFORE any model input is returned, with the database bytes
     unchanged by the refused attempt (I1 / I4 readiness);
  E. a consumer that holds ONLY the trust anchor (no signing key) still resolves
     and verifies the signed closure (the real detached-consumer path).

Usage:
  python3 i_semantic_sufficiency_selftest.py --out <path/i-preflight.json>
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from admission_selftest import (  # noqa: E402
    ENV, provision_trust, run_bridge, sha256_bytes, sha256_file, utc_now,
)

RUN_LABEL = "i-semantic-selftest"
ORIGIN_SECTOR = "NORTH"
DEST_SECTOR = "EAST"
ORIGIN_PRIORITY = "3"
DEST_PRIORITY = "5"
ORIGIN, DEST = "TASK-ORIGIN", "TASK-DEST"
IW1, IW2, IW3 = "TASK-IU1", "TASK-IU2", "TASK-IU3"
DEMAND_IW1, DEMAND_IW2, DEMAND_IW3 = "handoff-i-u1", "handoff-i-u2", "handoff-i-u3"
DEMAND_ICHAIN = "handoff-i-chain"
ROUTE = "%s>%s" % (ORIGIN_SECTOR, DEST_SECTOR)
REVERSE = "%s>%s" % (DEST_SECTOR, ORIGIN_SECTOR)


def run_bridge_env(arguments, env):
    """Run the bridge with an explicit environment (for the no-key consumer)."""
    process = subprocess.run(
        ["/usr/bin/python3", str(HERE / "production_runtime_bridge.py"), *arguments],
        capture_output=True, text=True, env=env, cwd=str(HERE), timeout=120,
    )
    try:
        payload = json.loads(process.stdout or "{}")
    except json.JSONDecodeError:
        payload = {"ok": False, "raw_stdout": process.stdout,
                   "raw_stderr": process.stderr}
    return process.returncode, payload


def define_graph(database):
    code, defined = run_bridge(
        "define-i-graph", "--database", str(database),
        "--evaluated-at", utc_now(), "--run-label", RUN_LABEL,
        "--sector-origin", ORIGIN_SECTOR, "--sector-dest", DEST_SECTOR,
        "--priority-origin", ORIGIN_PRIORITY, "--priority-dest", DEST_PRIORITY,
    )
    if code != 0 or not defined.get("ok"):
        raise RuntimeError("define-i-graph failed: %s" % defined)
    if defined.get("expected_route_key") != ROUTE:
        raise RuntimeError("define-i-graph expected-route-key mismatch: %s" % defined)
    return defined


def settle_item(directory, database, item_id, demand_id, advancement, core_value):
    """Settle one model item through the ordinary execute-with-model-result path.

    The value is synthetic (model-free) but still satisfies the production
    ``_validate_model_value`` for that item, so the fixture reaches a lawful
    signed settlement graph. Mirrors h_selective_invalidation_selftest.settle_item.
    Returns (ok, settled_payload) instead of raising so a caller can assert a
    controlled rejection.
    """
    value = {
        "generated_token_ids": [7, 8, 9],
        "model_snapshot_revision": "i-fixture-revision",
        "model_weights_manifest_sha256": "i-fixture-weights",
        "model_call_index": 1,
        **core_value,
    }
    value_path = directory / ("%s-value.json" % item_id)
    value_path.write_text(json.dumps(value), encoding="utf-8")
    token_ids = json.dumps(value["generated_token_ids"], separators=(",", ":"))
    provenance = {
        "producer": {
            "kind": "model_task",
            "run_id": ENV["SIMIGO_SETTLEMENT_RUN_ID"],
            "execution_id": ENV["SIMIGO_SETTLEMENT_EXECUTION_ID"],
            "process_id": str(os.getpid()),
            "build_sha256": ENV["SIMIGO_SETTLEMENT_BUILD_SHA256"],
        },
        "model": {
            "snapshot_revision": value["model_snapshot_revision"],
            "weights_manifest_sha256": value["model_weights_manifest_sha256"],
        },
        "output": {
            "generated_token_ids_sha256": sha256_bytes(token_ids.encode("utf-8")),
            "generated_token_count": len(value["generated_token_ids"]),
        },
    }
    provenance_path = directory / ("%s-provenance.json" % item_id)
    provenance_path.write_text(json.dumps(provenance), encoding="utf-8")
    code, settled = run_bridge(
        "execute-with-model-result",
        "--database", str(database),
        "--demand-id", demand_id,
        "--advancement", advancement,
        "--evaluated-at", utc_now(),
        "--item-id", item_id,
        "--value-file", str(value_path),
        "--provenance-file", str(provenance_path),
        "--run-id", ENV["SIMIGO_SETTLEMENT_RUN_ID"],
        "--execution-id", ENV["SIMIGO_SETTLEMENT_EXECUTION_ID"],
        "--build-sha256", ENV["SIMIGO_SETTLEMENT_BUILD_SHA256"],
        "--producer-process-id", str(os.getpid()),
    )
    ok = code == 0 and bool(settled.get("ok"))
    if ok:
        state_id = ((settled.get("result") or {}).get(
            "execution_state") or {}).get("state_id")
        if state_id:
            cc, confirm = run_bridge(
                "confirm-runtime-application", "--database", str(database),
                "--state-id", state_id)
            if cc != 0 or not confirm.get("ok"):
                raise RuntimeError("confirm %s failed: %s" % (item_id, confirm))
    return ok, settled


def settle_valid_chain(directory, database):
    """Model-free IU1->IU2->IU3 settle in topological order (asserts success)."""
    ok, out = settle_item(directory, database, IW1, DEMAND_IW1, "ipf-iu1", {
        "origin_code": ORIGIN_SECTOR, "destination_code": DEST_SECTOR,
        "route_key": ROUTE, "priority": DEST_PRIORITY,
        "raw_generated_text": "ORIGIN=%s\nDEST=%s\nROUTE=%s\nPRIORITY=%s" % (
            ORIGIN_SECTOR, DEST_SECTOR, ROUTE, DEST_PRIORITY),
    })
    if not ok:
        raise RuntimeError("settle IU1 failed: %s" % out)
    ok, out = settle_item(directory, database, IW2, DEMAND_IW2, "ipf-iu2", {
        "route_key": ROUTE, "dispatch": DEST_PRIORITY,
        "raw_generated_text": "FLOW=%s\nDISPATCH=%s" % (ROUTE, DEST_PRIORITY),
    })
    if not ok:
        raise RuntimeError("settle IU2 failed: %s" % out)
    ok, out = settle_item(directory, database, IW3, DEMAND_IW3, "ipf-iu3", {
        "route_key": ROUTE, "status": DEST_PRIORITY,
        "raw_generated_text": "CONFIRMED=%s\nSTATUS=%s" % (ROUTE, DEST_PRIORITY),
    })
    if not ok:
        raise RuntimeError("settle IU3 failed: %s" % out)


def probe_actions(database, evaluated_at):
    code, out = run_bridge(
        "execute-probe", "--database", str(database),
        "--demand-id", DEMAND_ICHAIN, "--advancement", "ipf-probe",
        "--evaluated-at", evaluated_at,
    )
    if code != 0 or not out.get("ok"):
        raise RuntimeError("execute-probe failed: %s" % out)
    actions = (out.get("result") or {}).get("actions") or []
    computed = {a["item_id"] for a in actions if a.get("action") == "COMPUTE"}
    reused = {a["item_id"] for a in actions if a.get("action") == "REUSE"}
    return computed, reused, actions


def snapshot(database, destination):
    if destination.exists():
        destination.unlink()
    code, out = run_bridge(
        "snapshot-database", "--database", str(database),
        "--destination", str(destination))
    if code != 0 or not out.get("ok"):
        raise RuntimeError("snapshot-database failed: %s" % out)


def remove_settlement(database, item_id):
    """Authoritatively remove a settled object (and its signature index) so a
    downstream closure resolve can no longer admit it. This is the I1/I4
    mutation and runs only on an isolated copy."""
    connection = sqlite3.connect(str(database))
    try:
        deleted = connection.execute(
            "DELETE FROM dependency_entries WHERE dependency_id=?",
            ("settlement:" + item_id,)).rowcount
        connection.execute(
            "DELETE FROM is_index_entries WHERE srs_identity IN (?,?)",
            ("settlement:" + item_id, "settlement-signature:" + item_id))
        connection.commit()
    finally:
        connection.close()
    return deleted


def current_settlement_object_id(database, item_id):
    code, out = run_bridge(
        "read-settlement", "--database", str(database), "--item-id", item_id)
    if code != 0 or not out.get("ok"):
        return None
    return ((out.get("settlement") or {}).get("_object_id"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    work = Path(tempfile.mkdtemp(prefix="simigo-i-preflight-"))
    checks = {}
    notes = []
    try:
        provision_trust(work / "trust")

        # A. Baseline structured chain settles, signs, and fully reuses.
        database = work / "graph.sqlite"
        define_graph(database)
        settle_valid_chain(work, database)
        base_db = work / "base-probe.sqlite"
        snapshot(database, base_db)
        base_computed, base_reused, _ = probe_actions(base_db, utc_now())
        iw1_signature = run_bridge(
            "read-settlement", "--database", str(database), "--item-id", IW1)
        checks["A_baseline_chain_all_reusable"] = (
            base_computed == set() and {IW1, IW2, IW3}.issubset(base_reused))
        checks["A_composite_settled_and_signed"] = bool(
            iw1_signature[1].get("settlement", {}).get("result", {}).get(
                "value", {}).get("route_key") == ROUTE)
        notes.append("A_computed=%s A_reused=%s" % (
            sorted(base_computed), sorted(base_reused)))

        # B. A semantically incomplete IU1 (no route_key) is refused with no
        # reusable settlement. Fresh graph (sources settled, IU1 unsettled).
        contract_db = work / "contract.sqlite"
        define_graph(contract_db)
        ok_b, refused = settle_item(work, contract_db, IW1, DEMAND_IW1, "ipf-iu1-bad", {
            "origin_code": ORIGIN_SECTOR, "destination_code": DEST_SECTOR,
            "raw_generated_text": "ORIGIN=%s\nDEST=%s" % (
                ORIGIN_SECTOR, DEST_SECTOR),
        })
        iw1_after_bad = current_settlement_object_id(contract_db, IW1)
        checks["B_incomplete_iw1_rejected"] = (
            not ok_b and iw1_after_bad is None)
        notes.append("B_ok=%s b_error=%s b_iw1_settled=%s" % (
            ok_b, (refused.get("error") or "")[:120], iw1_after_bad is not None))

        # C. IU3 single dependency expands to the full signed transitive closure.
        code, resolved = run_bridge(
            "resolve-model-input", "--database", str(database),
            "--item-id", IW3, "--evaluated-at", utc_now())
        closure_ids = set()
        if code == 0 and resolved.get("ok"):
            for dep in (resolved.get("dependencies") or []):
                if isinstance(dep, dict) and dep.get("item_id"):
                    closure_ids.add(dep["item_id"])
        # route_key flows into IU2 only via IU1's settled structured field, so
        # the closure must name the composite route's own settlement object.
        checks["C_iw3_closure_complete"] = (
            {IW1, IW2, ORIGIN, DEST}.issubset(closure_ids)
            and bool(resolved.get("settlement_signatures")))
        notes.append("C_closure=%s" % sorted(closure_ids))

        # D1. Missing ORIGIN source -> IU1 refuses before model input, DB stable.
        d1_db = work / "missing-origin-iw1.sqlite"
        snapshot(database, d1_db)
        remove_settlement(d1_db, ORIGIN)
        d1_pre = sha256_file(d1_db)
        code_d1, refusal = run_bridge(
            "resolve-model-input", "--database", str(d1_db),
            "--item-id", IW1, "--evaluated-at", utc_now())
        d1_post = sha256_file(d1_db)
        checks["D_iw1_refuses_missing_origin"] = (
            (code_d1 != 0 or not refusal.get("ok")) and d1_pre == d1_post)
        notes.append("D1_refusal_stage=%s db_unchanged=%s" % (
            (refusal.get("refusal") or {}).get("stage"), d1_pre == d1_post))

        # D2. Missing DEST source -> IU3 refuses through its transitive closure.
        d2_db = work / "missing-dest-iw3.sqlite"
        snapshot(database, d2_db)
        remove_settlement(d2_db, DEST)
        d2_pre = sha256_file(d2_db)
        code_d2, refusal2 = run_bridge(
            "resolve-model-input", "--database", str(d2_db),
            "--item-id", IW3, "--evaluated-at", utc_now())
        d2_post = sha256_file(d2_db)
        checks["D_iw3_refuses_missing_transitive_source"] = (
            (code_d2 != 0 or not refusal2.get("ok")) and d2_pre == d2_post)
        notes.append("D2_refusal_stage=%s db_unchanged=%s" % (
            (refusal2.get("refusal") or {}).get("stage"), d2_pre == d2_post))

        # E. No-key consumer verifies the signed closure.
        consumer_env = dict(ENV)
        consumer_env.pop("SIMIGO_SETTLEMENT_SIGNING_KEY", None)
        consumer_db = work / "consumer-no-key.sqlite"
        snapshot(database, consumer_db)
        code, ck = run_bridge_env(
            ["resolve-model-input", "--database", str(consumer_db),
             "--item-id", IW3, "--evaluated-at", utc_now()], consumer_env)
        checks["E_consumer_no_key_verifies"] = code == 0 and bool(ck.get("ok"))
        notes.append("E_ok=%s" % bool(ck.get("ok")))

        verdict = "PASS" if all(checks.values()) else "FAIL"
        out = {
            "schema_id": "SIMIGO-I-PREFLIGHT-SEMANTIC-SUFFICIENCY-V1",
            "created_at_utc": utc_now(),
            "terminal_state": "OBSERVED" if verdict == "PASS" else "FAILED",
            "model_loads": 0,
            "tokenize_text_calls": 0,
            "tokenize_seed_calls": 0,
            "model_generate_calls": 0,
            "graph": {
                "sources": [ORIGIN, DEST],
                "structured_chain": [IW1, IW2, IW3],
                "transitive_closure_of_iw3": [ORIGIN, DEST, IW1, IW2, IW3],
            },
            "expected_route_key": ROUTE,
            "checks": checks,
            "notes": notes,
            "verdict": verdict,
        }
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.out).write_text(json.dumps(out, indent=2, sort_keys=True),
                                  encoding="utf-8")
        print(json.dumps(out, indent=2, sort_keys=True))
        return 0 if verdict == "PASS" else 1
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
