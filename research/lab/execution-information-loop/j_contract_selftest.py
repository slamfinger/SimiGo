#!/usr/bin/env python3
"""J-round model-free declarative-result-contract preflight gate.

The J round asks one narrow question: is result validation now driven by the
task's OWN declaration instead of a rule selected by its fixed task item id? The
cheapest honest way to answer that is to build the whole graph on ids generated
at run time (``J-<token>-U1/2/3``), so no source file has ever mentioned them,
and then exercise the SAME production machinery the real model uses
(``production_runtime_bridge.py`` over the carrier-loop signed settlement path).
No model is loaded here, so every model/tokenize/generate counter is honestly
zero for this gate.

It proves:
  A. an unseen-id chain (ORIGIN,DEST -> U1 -> U2 -> U3) settles, signs and is
     fully reusable, with dispatch recorded as ``declared_contract``;
  B. id independence: the same contract settled under two different runtime ids
     produces byte-identical contract validation reports (no id keys any rule);
  C. a missing declared field is refused and creates no reusable settlement;
  D. a value that contradicts an admitted input binding is refused;
  E. a value that contradicts a declared cross-field derivation is refused;
  F. an unknown contract schema version fails closed before any production work;
  G. U3's single declared dependency expands to the full signed closure;
  H. removing a transitive source makes U3 refuse with the database unchanged;
  I. a consumer holding only the trust anchor (no signing key) verifies it;
  J. the extraction view the native producer reads is DERIVED from the
     authoritative declaration, so the two cannot silently drift;
  K. static proof over the production source: the result gate takes no task item
     id, no task-id semantic branch survives, and no J id is hard-coded.

Usage:
  python3 j_contract_selftest.py --out <path/j-preflight.json>
"""
from __future__ import annotations

import argparse
import ast
import json
import os
import re
import secrets
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
    ENV, provision_trust, run_bridge, sha256_file, utc_now,
)
from declarative_result_contract import (  # noqa: E402
    CONTRACT_VERSION, derive_extraction_view,
)

BRIDGE = HERE / "production_runtime_bridge.py"
ORIGIN_SECTOR = "NORTH"
DEST_SECTOR = "EAST"
ORIGIN_PRIORITY = "3"
DEST_PRIORITY = "5"
ROUTE = "%s>%s" % (ORIGIN_SECTOR, DEST_SECTOR)
UNKNOWN_VERSION = "simigo.result-contract/v9"


def new_ids(database: Path, extra: list | None = None) -> dict:
    """Define a graph whose item ids exist only for this call."""
    token = secrets.token_hex(4)
    code, defined = run_bridge(
        "define-j-graph", "--database", str(database),
        "--evaluated-at", utc_now(), "--run-token", token,
        "--run-label", "j-preflight-%s" % token,
        "--sector-origin", ORIGIN_SECTOR, "--sector-dest", DEST_SECTOR,
        "--priority-origin", ORIGIN_PRIORITY, "--priority-dest", DEST_PRIORITY,
        *(extra or []),
    )
    if code != 0 or not defined.get("ok"):
        raise RuntimeError("define-j-graph failed: %s" % defined)
    if defined.get("expected_route_key") != ROUTE:
        raise RuntimeError("define-j-graph route mismatch: %s" % defined)
    # The bridge reports the full item records under u1/u2/u3; this gate only
    # needs their runtime ids, which model_item_ids carries in topological order.
    defined["u1"], defined["u2"], defined["u3"] = defined["model_item_ids"]
    return defined


def settle(directory, database, ids, item_id, demand_id, advancement, core_value):
    """Settle one model item through the ordinary production model-result path.

    The value is synthetic (model-free) but must satisfy the item's DECLARED
    contract, so the fixture reaches a lawful signed settlement. Returns
    ``(ok, payload)`` so a caller can assert a controlled rejection.
    """
    # Guard the fixture itself: this may only ever settle a runtime id that the
    # graph defined, never a frozen constant from a source file.
    if item_id not in (ids.get("model_item_ids") or []):
        raise RuntimeError("settling a non-graph item id: %s" % item_id)
    value = {
        "generated_token_ids": [7, 8, 9],
        "model_snapshot_revision": "j-fixture-revision",
        "model_weights_manifest_sha256": "j-fixture-weights",
        "model_call_index": 1,
        **core_value,
    }
    value_path = directory / ("%s-value.json" % advancement)
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
    provenance_path = directory / ("%s-provenance.json" % advancement)
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


def sha256_bytes(data: bytes) -> str:
    import hashlib
    return hashlib.sha256(data).hexdigest()


def u1_text():
    return {"origin_code": ORIGIN_SECTOR, "destination_code": DEST_SECTOR,
            "route_key": ROUTE, "priority": DEST_PRIORITY,
            "raw_generated_text": "ORIGIN=%s\nDEST=%s\nROUTE=%s\nPRIORITY=%s" % (
                ORIGIN_SECTOR, DEST_SECTOR, ROUTE, DEST_PRIORITY)}


def settle_chain(directory, database, ids):
    ok, one = settle(directory, database, ids, ids["u1"], ids["demand_u1"],
                     "jpf-u1", u1_text())
    if not ok:
        raise RuntimeError("settle U1 failed: %s" % one)
    ok, two = settle(directory, database, ids, ids["u2"], ids["demand_u2"],
                     "jpf-u2", {
                         "route_key": ROUTE,
                         "raw_generated_text": "FLOW=%s" % ROUTE})
    if not ok:
        raise RuntimeError("settle U2 failed: %s" % two)
    ok, three = settle(directory, database, ids, ids["u3"], ids["demand_u3"],
                       "jpf-u3", {
                           "route_key": ROUTE,
                           "raw_generated_text": "CONFIRMED=%s" % ROUTE})
    if not ok:
        raise RuntimeError("settle U3 failed: %s" % three)
    return one, two, three


def snapshot(database, destination):
    if destination.exists():
        destination.unlink()
    code, out = run_bridge("snapshot-database", "--database", str(database),
                           "--destination", str(destination))
    if code != 0 or not out.get("ok"):
        raise RuntimeError("snapshot-database failed: %s" % out)
    return destination


def remove_settlement(database, item_id):
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


def settlement_object(database, item_id):
    code, out = run_bridge("read-settlement", "--database", str(database),
                           "--item-id", item_id)
    if code != 0 or not out.get("ok"):
        return None
    return ((out.get("settlement") or {}).get("_object_id"))


def read_item_payload(database: Path, item_id: str) -> dict:
    code, out = run_bridge("read-item", "--database", str(database),
                           "--item-id", item_id)
    if code != 0 or not out.get("ok"):
        raise RuntimeError("read-item %s failed: %s" % (item_id, out))
    payload = (out.get("item") or {}).get("source_payload") or {}
    if not payload:
        raise RuntimeError("read-item %s returned no payload: %s" % (item_id, out))
    return payload


def static_proof(bridge_source: str) -> dict:
    """Prove the production gate is not selected by task item id."""
    tree = ast.parse(bridge_source)
    gate = next((n for n in tree.body
                 if isinstance(n, ast.FunctionDef)
                 and n.name == "_validate_model_value"), None)
    if gate is None:
        return {"gate_found": False}
    arg_names = [a.arg for a in gate.args.args]
    return {
        "gate_found": True,
        "gate_arguments": arg_names,
        "gate_takes_no_item_id": "item_id" not in arg_names,
        "no_task_id_semantic_branch": not re.search(
            r"item_id\s*==\s*[\"']TASK", bridge_source),
        "no_hardcoded_j_ids": not re.search(
            r"\"J-[0-9a-zA-Z]+-(?:U1|U2|U3)\"", bridge_source),
        "gate_body_single_delegation": len(gate.body) == 2,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    work = Path(tempfile.mkdtemp(prefix="simigo-j-preflight-"))
    checks = {}
    notes = []
    try:
        provision_trust(work / "trust")
        bridge_source = BRIDGE.read_text(encoding="utf-8")

        # Static proof first: it costs nothing and frames every runtime check.
        proof = static_proof(bridge_source)
        checks["K_gate_takes_no_task_item_id"] = bool(
            proof.get("gate_found") and proof.get("gate_takes_no_item_id"))
        checks["K_no_task_id_semantic_branch"] = bool(
            proof.get("no_task_id_semantic_branch"))
        checks["K_no_hardcoded_j_item_ids"] = bool(proof.get("no_hardcoded_j_ids"))
        notes.append("K_args=%s" % proof.get("gate_arguments"))

        # A. Baseline chain on ids that exist only for this run.
        database = work / "graph.sqlite"
        ids_a = new_ids(database)
        one, two, three = settle_chain(work, database, ids_a)
        checks["A_runtime_ids_are_unseen"] = bool(
            ids_a["u1"].startswith("J-") and ids_a["run_token"]
            and ids_a["u1"] not in ("TASK-IU1", "TASK-U1"))
        base_db = snapshot(database, work / "base-probe.sqlite")
        code, probe = run_bridge(
            "execute-probe", "--database", str(base_db),
            "--demand-id", ids_a["demand_chain"], "--advancement", "jpf-probe",
            "--evaluated-at", utc_now())
        actions = (probe.get("result") or {}).get("actions") or []
        computed = {a["item_id"] for a in actions if a.get("action") == "COMPUTE"}
        reused = {a["item_id"] for a in actions if a.get("action") == "REUSE"}
        checks["A_unseen_id_chain_all_reusable"] = (
            code == 0 and bool(probe.get("ok")) and computed == set()
            and {ids_a["u1"], ids_a["u2"], ids_a["u3"]}.issubset(reused))
        checks["A_dispatch_basis_recorded"] = all(
            r.get("contract_dispatch_basis") == "declared_contract"
            for r in (one, two, three))
        notes.append("A_ids=%s A_reused=%s" % (ids_a["model_item_ids"],
                                               sorted(reused)))

        # B. Same contract, different runtime ids -> identical validation report.
        database_b = work / "graph-b.sqlite"
        ids_b = new_ids(database_b)
        ok_b, settle_b = settle(work, database_b, ids_b,
                                ids_b["u1"], ids_b["demand_u1"], "jpf-u1-b",
                                u1_text())
        report_a = json.dumps(one.get("result_contract_validation"), sort_keys=True)
        report_b = json.dumps(settle_b.get("result_contract_validation"),
                              sort_keys=True)
        checks["B_id_independent_validation"] = bool(
            ok_b and ids_b["u1"] != ids_a["u1"] and report_a == report_b
            and "item" not in report_b.lower())
        notes.append("B_ids_differ=%s reports_equal=%s" % (
            ids_a["u1"] != ids_b["u1"], report_a == report_b))

        # C. Missing declared field (no PRIORITY line) -> refused, not reusable.
        database_c = work / "graph-c.sqlite"
        ids_c = new_ids(database_c)
        partial = {"origin_code": ORIGIN_SECTOR, "destination_code": DEST_SECTOR,
                   "route_key": ROUTE,
                   "raw_generated_text": "ORIGIN=%s\nDEST=%s\nROUTE=%s" % (
                       ORIGIN_SECTOR, DEST_SECTOR, ROUTE)}
        ok_c, refused_c = settle(work, database_c, ids_c, ids_c["u1"],
                                 ids_c["demand_contract"], "jpf-u1-nofield", partial)
        downstream_c = run_bridge(
            "resolve-model-input", "--database", str(database_c),
            "--item-id", ids_c["u2"], "--evaluated-at", utc_now())
        checks["C_missing_field_rejected"] = bool(
            not ok_c and "PRODUCER_RESULT_FIELD_MISSING" in str(
                refused_c.get("error") or "")
            and settlement_object(database_c, ids_c["u1"]) is None)
        checks["C_missing_field_result_not_reusable"] = bool(
            downstream_c[0] != 0 or not downstream_c[1].get("ok"))
        notes.append("C_error=%s" % (refused_c.get("error") or "")[:140])

        # D. Contradicts an admitted input binding (origin priority claimed as
        # the route priority, although the contract binds the destination's).
        database_d = work / "graph-d.sqlite"
        ids_d = new_ids(database_d)
        misbound = dict(u1_text())
        misbound["priority"] = ORIGIN_PRIORITY
        misbound["raw_generated_text"] = misbound[
            "raw_generated_text"].replace("PRIORITY=%s" % DEST_PRIORITY,
                                          "PRIORITY=%s" % ORIGIN_PRIORITY)
        ok_d, refused_d = settle(work, database_d, ids_d, ids_d["u1"],
                                 ids_d["demand_contract"], "jpf-u1-misbound",
                                 misbound)
        checks["D_binding_mismatch_rejected"] = bool(
            not ok_d and "PRODUCER_RESULT_BINDING_MISMATCH" in str(
                refused_d.get("error") or "")
            and settlement_object(database_d, ids_d["u1"]) is None)
        notes.append("D_error=%s" % (refused_d.get("error") or "")[:140])

        # E. Contradicts a declared cross-field derivation (reversed route).
        database_e = work / "graph-e.sqlite"
        ids_e = new_ids(database_e)
        derived = dict(u1_text())
        reverse = "%s>%s" % (DEST_SECTOR, ORIGIN_SECTOR)
        derived["route_key"] = reverse
        derived["raw_generated_text"] = derived["raw_generated_text"].replace(
            "ROUTE=%s" % ROUTE, "ROUTE=%s" % reverse)
        ok_e, refused_e = settle(work, database_e, ids_e, ids_e["u1"],
                                 ids_e["demand_contract"], "jpf-u1-derivation",
                                 derived)
        checks["E_derivation_mismatch_rejected"] = bool(
            not ok_e and "PRODUCER_RESULT_DERIVATION_MISMATCH" in str(
                refused_e.get("error") or "")
            and settlement_object(database_e, ids_e["u1"]) is None)
        notes.append("E_error=%s" % (refused_e.get("error") or "")[:140])

        # F. Unknown contract schema version fails closed before any work.
        database_f = work / "graph-f.sqlite"
        defined_f = new_ids(database_f, [
            "--u1-schema-version", UNKNOWN_VERSION])
        ok_f, refused_f = settle(work, database_f, defined_f, defined_f["u1"],
                                 defined_f["demand_contract"], "jpf-u1-version",
                                 u1_text())
        checks["F_unknown_version_fail_closed"] = bool(
            not ok_f and "CONTRACT_UNKNOWN_SCHEMA_VERSION" in str(
                refused_f.get("error") or "")
            and settlement_object(database_f, defined_f["u1"]) is None
            and defined_f.get("u1_declared_schema_version") == UNKNOWN_VERSION)
        notes.append("F_error=%s" % (refused_f.get("error") or "")[:140])

        # G. U3's single declared dependency expands to the full closure.
        code, resolved = run_bridge(
            "resolve-model-input", "--database", str(database),
            "--item-id", ids_a["u3"], "--evaluated-at", utc_now())
        closure = set()
        for dep in (resolved.get("dependencies") or []):
            if isinstance(dep, dict) and dep.get("item_id"):
                closure.add(dep["item_id"])
        checks["G_full_signed_closure"] = bool(
            code == 0 and resolved.get("ok")
            and {ids_a["u1"], ids_a["u2"], ids_a["origin"], ids_a["dest"]
                 }.issubset(closure)
            and bool(resolved.get("settlement_signatures")))
        notes.append("G_closure=%s" % sorted(closure))

        # H. Removing a transitive source refuses U3 with the database stable.
        h_db = snapshot(database, work / "missing-origin.sqlite")
        remove_settlement(h_db, ids_a["origin"])
        h_pre = sha256_file(h_db)
        code_h, refusal_h = run_bridge(
            "resolve-model-input", "--database", str(h_db),
            "--item-id", ids_a["u3"], "--evaluated-at", utc_now())
        h_post = sha256_file(h_db)
        checks["H_transitive_source_removal_refuses"] = bool(
            (code_h != 0 or not refusal_h.get("ok")) and h_pre == h_post)
        notes.append("H_stage=%s db_unchanged=%s" % (
            (refusal_h.get("refusal") or {}).get("stage"), h_pre == h_post))

        # I. A signing-key-free consumer still verifies the signed closure.
        consumer_db = snapshot(database, work / "consumer-no-key.sqlite")
        env_without_key = dict(ENV)
        env_without_key.pop("SIMIGO_SETTLEMENT_SIGNING_KEY", None)
        proc = subprocess.run(
            [sys.executable, str(BRIDGE), "resolve-model-input",
             "--database", str(consumer_db), "--item-id", ids_a["u3"],
             "--evaluated-at", utc_now()],
            capture_output=True, text=True, env=env_without_key, cwd=str(HERE),
            timeout=120)
        try:
            payload_i = json.loads(proc.stdout or "{}")
        except json.JSONDecodeError:
            payload_i = {"ok": False}
        checks["I_no_key_consumer_verifies"] = bool(
            proc.returncode == 0 and payload_i.get("ok")
            and (payload_i.get("checks") or {}).get("settlement_signatures_valid"))
        notes.append("I_no_key_ok=%s" % bool(payload_i.get("ok")))

        # J. The native producer's extraction view is derived, not handwritten.
        payload_u1 = read_item_payload(database, ids_a["u1"])
        expected_view = derive_extraction_view(payload_u1["semantic_contract"])
        stored_view = payload_u1.get("result_contract") or {}
        # The carrier stores items in canonical (key-sorted) JSON, so the list
        # ORDER of the derived view is not preserved; compare by field name and
        # require an exact one-to-one match with the authoritative declaration.
        as_map = {f["name"]: f["pattern"] for f in stored_view.get("fields", [])}
        expected_map = {
            name: spec["pattern"]
            for name, spec in payload_u1["semantic_contract"]["fields"].items()}
        checks["J_extraction_view_is_derived"] = bool(
            as_map == expected_map
            and len(stored_view.get("fields", [])) == len(expected_map)
            and stored_view.get("schema_version")
            == expected_view["schema_version"]
            and payload_u1["semantic_contract"]["schema_version"]
            == CONTRACT_VERSION)
        notes.append("J_view_fields=%s" % sorted(as_map))

        verdict = "PASS" if all(checks.values()) else "FAIL"
        out = {
            "schema_id": "SIMIGO-J-PREFLIGHT-DECLARATIVE-CONTRACT-V1",
            "created_at_utc": utc_now(),
            "terminal_state": "OBSERVED" if verdict == "PASS" else "FAILED",
            "contract_dispatch_basis": "declared_contract",
            "contract_schema_version": CONTRACT_VERSION,
            "model_loads": 0,
            "tokenize_text_calls": 0,
            "tokenize_seed_calls": 0,
            "model_generate_calls": 0,
            "runtime_generated_ids": {
                "baseline": ids_a["model_item_ids"],
                "id_independence_control": ids_b["model_item_ids"],
            },
            "static_proof": proof,
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
