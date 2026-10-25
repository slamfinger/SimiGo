#!/usr/bin/env python3
"""Independently audit signature-object identity against the signed settlement.

The E round reports two distinct identities for every settled item:

* the detached signature object's own content address, and
* the settlement object that signature covers.

This audit re-reads both from the world databases, re-verifies the Ed25519
signature against the out-of-database trust anchor, and compares them with the
identities the production entry wrote into its evidence. It never writes to a
database or a state directory.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

RUN_ROOT = Path(__file__).resolve().parents[1]
RUNNER = Path(
    "/Users/mr.simi/Documents/SimiGo-Lab/simigo2-experimental/scripts/"
    "ordinary_task/run_phase_e.py"
)
ITEMS = ("TASK-SOURCE", "TASK-U1", "TASK-U2")


def load_runner():
    spec = importlib.util.spec_from_file_location("phase_e_runner", RUNNER)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def action_for(evidence: dict, item_id: str) -> dict:
    for action in (evidence.get("settlement") or {}).get("actions") or []:
        if action.get("item_id") == item_id:
            return action
    return {}


def database_for(world: str, item_id: str) -> Path:
    # U2 is executed against a copy of the world database, so its settlement
    # and signature live in a different file than U1's.
    suffix = "-u2" if item_id == "TASK-U2" else ""
    return RUN_ROOT / "worlds" / (world + suffix) / "carrier.sqlite"


def main() -> int:
    runner = load_runner()
    summary = json.loads((RUN_ROOT / "summary.json").read_text(encoding="utf-8"))
    anchor_path = Path(summary["trust_root"]["anchor_path"])
    anchor = json.loads(anchor_path.read_text(encoding="utf-8"))
    report = {
        "schema_id": "SIMIGO-E-ROUND-SIGNATURE-IDENTITY-AUDIT-V1",
        "run_root": str(RUN_ROOT),
        "anchor_path": str(anchor_path),
        "anchor_sha256": runner.sha256_file(anchor_path),
        "key_id": anchor["key_id"],
        "cases": [],
    }
    failures = []
    for world in ("world-a", "world-b"):
        evidences = {
            name: json.loads(
                Path(summary["worlds"][world][name]["evidence_path"]).read_text(
                    encoding="utf-8"))
            for name in ("u1", "u2")
        }
        for item_id in ITEMS:
            connection = runner.connect_readonly(database_for(world, item_id))
            try:
                settlement = runner.current_object(
                    connection, "settlement:" + item_id)
                envelope = runner.current_signature(connection, item_id)
            finally:
                connection.close()
            checks = {
                "settlement_present": settlement is not None,
                "signature_present": envelope is not None,
            }
            row = {
                "world": world,
                "item_id": item_id,
                "database": str(database_for(world, item_id)),
                "settlement_object_id": (settlement or {}).get("_object_id"),
                "signature_object_id": (envelope or {}).get("_object_id"),
                "checks": checks,
            }
            if settlement is None or envelope is None:
                checks["all_true"] = False
                failures.append("%s/%s missing object" % (world, item_id))
                report["cases"].append(row)
                continue
            settlement_id = settlement["_object_id"]
            signature_id = envelope["_object_id"]
            checks.update({
                # A signature object and the settlement it covers are two
                # different content addresses; conflating them would make
                # the evidence unable to say which one was verified.
                "identities_are_distinct": signature_id != settlement_id,
                "signature_covers_this_settlement":
                    envelope.get("settlement_object_id") == settlement_id,
                "signature_item_matches": envelope.get("item_id") == item_id,
                "signature_key_matches_anchor":
                    envelope.get("key_id") == anchor["key_id"],
            })
            checks.update(runner.verify_envelope(
                envelope, anchor, settlement_id, item_id))
            # The entry evidence must name the same pair. TASK-SOURCE is
            # consumed by the U1 entry, TASK-U1 by the U2 entry; the executed
            # item also carries the top-level report fields.
            action = action_for(evidences["u1"] if item_id != "TASK-U2"
                                else evidences["u2"], item_id)
            checks["evidence_action_present"] = bool(action)
            if action:
                checks["evidence_action_settlement_matches"] = (
                    action.get("settlement_object_id") == settlement_id)
                checks["evidence_action_signature_matches"] = (
                    action.get("settlement_signature_object_id")
                    == signature_id)
            if item_id != "TASK-SOURCE":
                evidence = (evidences["u1"] if item_id == "TASK-U1"
                            else evidences["u2"])
                settlement_evidence = evidence.get("settlement") or {}
                checks["evidence_report_task_is_item"] = (
                    evidence.get("task_item_id") == item_id)
                checks["evidence_report_signature_matches"] = (
                    settlement_evidence.get("settlement_signature_object_id")
                    == signature_id)
                checks["evidence_report_signed_settlement_matches"] = (
                    settlement_evidence.get("signed_settlement_object_id")
                    == settlement_id)
            checks["all_true"] = all(
                value for key, value in checks.items() if key != "all_true")
            if not checks["all_true"]:
                failures.append("%s/%s identity checks failed" %
                                (world, item_id))
            row["checks"] = checks
            report["cases"].append(row)
    report["case_count"] = len(report["cases"])
    report["failures"] = failures
    report["verdict"] = "PASS" if not failures else "FAIL"
    output = RUN_ROOT / "logs" / "signature-identity-audit.json"
    output.write_text(
        json.dumps(report, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"verdict": report["verdict"], "cases": report["case_count"],
                      "failures": failures, "report": str(output)},
                     ensure_ascii=False, indent=1))
    return 0 if not failures else 2


if __name__ == "__main__":
    raise SystemExit(main())
