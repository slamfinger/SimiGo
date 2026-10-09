#!/usr/bin/env python3
"""End-to-end acceptance selftest for the isolated ES/IS continuation loop."""
from __future__ import annotations

import argparse
import json
import tempfile
from pathlib import Path

from loop import InformationLoop


def canonical(value) -> str:
    import json
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def calculator(item_id: str, source_payload: dict, dependencies: dict) -> dict:
    if item_id == "A":
        return {"item": "A", "value": source_payload["input"] * 2}
    if item_id == "B":
        return {"item": "B", "value": dependencies["A"]["value"] + source_payload["input"]}
    if item_id == "C":
        return {"item": "C", "value": dependencies["B"]["value"] * source_payload["factor"]}
    raise ValueError(f"no calculator for {item_id}")


def action_map(result: dict) -> dict:
    return {item["item_id"]: item["action"] for item in result["actions"]}


def run() -> dict:
    checks = {}
    temporary = Path(tempfile.mkdtemp(prefix="simigo-einfo-"))
    database = str(temporary / "information_space.sqlite")

    # S0/S1: create physical IS and define ES continuation demand.
    loop = InformationLoop.create(database)
    loop.define_demand(
        "demand-001",
        continuation_point="report-generation",
        pending_obligations=["produce report", "advance workflow"],
        continuation_conditions=["A and B are current", "C can be derived"],
        required_item_ids=["A", "B", "C"],
    )
    loop.put_source("demand-001", "A", "manual_input", "v1", {"input": 21})
    loop.put_source("demand-001", "B", "derived_input", "v1", {"input": 5}, ["A"])
    loop.put_source("demand-001", "C", "derived_input", "v1", {"factor": 3}, ["B"])
    loop.connection.commit()
    loop.close()

    # Persistence/restoration: open a new instance from SQLite only.
    restored = InformationLoop.open(database)
    first = restored.execute_demand("demand-001", "advance-001", calculator)
    checks["first_run_computes_all_three"] = action_map(first) == {
        "A": "COMPUTE", "B": "COMPUTE", "C": "COMPUTE"
    }
    checks["first_run_advances_es"] = first["advanced"] is True
    restored.connection.commit()
    restored.close()

    # Reopen again: all valid settlements are reused without computation.
    reused = InformationLoop.open(database)
    second = reused.execute_demand("demand-001", "advance-002", calculator)
    checks["second_run_reuses_all_three"] = action_map(second) == {
        "A": "REUSE", "B": "REUSE", "C": "REUSE"
    }
    reused.connection.commit()
    reused.close()

    # Source/dependency invalidation: B becomes stale; C must also recompute;
    # unaffected A must remain reused.
    changed = InformationLoop.open(database)
    invalidation = changed.invalidate_source("B", "upstream version changed")
    third = changed.execute_demand("demand-001", "advance-003", calculator)
    checks["invalidation_marks_B_and_dependent_C"] = set(invalidation["affected_item_ids"]) == {"B", "C"}
    checks["selective_recompute_B_C_reuse_A"] = action_map(third) == {
        "A": "REUSE", "B": "COMPUTE", "C": "COMPUTE"
    }
    changed.connection.commit()
    changed.close()

    # Failure safety: missing required information blocks without guessing.
    missing = InformationLoop.open(database)
    missing.define_demand(
        "demand-missing",
        continuation_point="blocked-report",
        pending_obligations=["produce blocked report"],
        continuation_conditions=["D must be present"],
        required_item_ids=["D"],
    )
    blocked = missing.execute_demand("demand-missing", "advance-blocked", calculator)
    checks["missing_information_blocks_without_guess"] = (
        blocked["state"] == "BLOCKED_MISSING_INFORMATION"
        and blocked["missing_item_ids"] == ["D"]
        and blocked["advanced"] is False
    )
    missing.connection.commit()
    missing.close()

    # Failure safety: a payload digest mismatch blocks reuse/computation.
    tampered = InformationLoop.open(database)
    tampered.connection.execute(
        "UPDATE information_items SET source_payload_json=? WHERE item_id='A'",
        (canonical({"input": 999, "tampered": True}),),
    )
    tampered.connection.commit()
    tampered_result = tampered.execute_demand(
        "demand-001", "advance-tampered", calculator
    )
    checks["digest_mismatch_blocks_without_settlement"] = (
        tampered_result["state"] == "BLOCKED_VALIDITY_FAILURE"
        and "A" in tampered_result["validity_failure_item_ids"]
    )
    tampered.connection.rollback()
    tampered.close()

    # Re-open the original database and verify persisted audit chain.
    final = InformationLoop.open(database)
    audit = final.audit_verify()
    checks["audit_chain_passes"] = audit["result"] == "PASS"

    checks["closed_loop_end_to_end"] = all(
        value for key, value in checks.items()
        if key != "database_path"
    )
    return {
        "schema_id": "D002-EXECUTION-INFORMATION-LOOP-SELFTEST-V1",
        "isolated_scope": "SYNTHETIC_SQLITE_REFERENCE",
        "real_palace_touched": False,
        "d002_rerun": False,
        "d001_executed": False,
        "database_path": database,
        "checks": checks,
        "result": "PASS" if checks["closed_loop_end_to_end"] else "FAIL",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output")
    args = parser.parse_args()
    report = run()
    text = canonical(report) + "\n"
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
    print(text, end="")
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
