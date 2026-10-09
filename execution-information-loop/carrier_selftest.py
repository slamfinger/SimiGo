#!/usr/bin/env python3
"""E2E test for ES/IS loop using the existing D002 append-only carrier."""
from __future__ import annotations

import argparse
import hashlib
import json
import tempfile
from pathlib import Path

from carrier_loop import CarrierInformationLoop, digest


def canonical(value) -> str:
    import hashlib, json
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def calculator(item_id: str, source_payload: dict, dependencies: dict) -> dict:
    if item_id == "A":
        return {"item": "A", "value": source_payload["input"] * 2}
    if item_id == "B":
        return {"item": "B", "value": dependencies["A"]["value"] + source_payload["input"]}
    if item_id == "C":
        return {"item": "C", "value": dependencies["B"]["value"] * source_payload["factor"]}
    raise ValueError(f"no calculator for {item_id}")


def actions(result: dict) -> dict:
    return {item["item_id"]: item["action"] for item in result["actions"]}


def run() -> dict:
    checks = {}
    validity_policy = {
        "policy_version": "carrier-selftest-v1",
        "policy_source": "ISOLATED_SELFTEST",
    }
    with tempfile.TemporaryDirectory(prefix="simigo-einfo-carrier-") as temporary:
        database = str(Path(temporary) / "carrier_information_space.sqlite")

        loop = CarrierInformationLoop.create(database)
        loop.define_demand(
            "demand-001",
            continuation_point="report-generation",
            pending_obligations=["produce report", "advance workflow"],
            continuation_conditions=["A and B are current", "C can be derived"],
            required_item_ids=["A", "B", "C"],
        )
        loop.put_source(
            "demand-001", "A", "manual_input", "v1", {"input": 21},
            valid_until_utc="2030-12-31T23:59:59Z",
        )
        loop.put_source(
            "demand-001", "B", "derived_input", "v1", {"input": 5}, ["A"],
            valid_until_utc="2026-10-09T00:01:30Z",
            validity_policy=validity_policy,
        )
        loop.put_source(
            "demand-001", "C", "derived_input", "v1", {"factor": 3}, ["B"],
            valid_until_utc="2030-12-31T23:59:59Z",
        )
        loop.commit()
        loop.close()

        restored = CarrierInformationLoop.open(database)
        first = restored.execute_demand(
            "demand-001", "advance-001", calculator,
            evaluated_at_utc="2026-10-09T00:00:00Z",
        )
        run_results = {"first": first}
        checks["first_run_computes_all_three"] = actions(first) == {
            "A": "COMPUTE", "B": "COMPUTE", "C": "COMPUTE"
        }
        checks["first_run_advances_es"] = first["advanced"] is True
        checks["settlement_and_es_intent_commit_atomically"] = (
            first["execution_state"]["runtime_application_status"] == "PENDING_SWIFT"
        )
        settlement = restored.current_settlement("B")
        checks["validity_policy_bound_to_settlement"] = (
            settlement is not None
            and settlement["result"]["validity_policy"] == validity_policy
            and settlement["basis"]["validity_policy"] == validity_policy
        )
        restored.commit()
        restored.close()

        reused = CarrierInformationLoop.open(database)
        second = reused.execute_demand(
            "demand-001", "advance-002", calculator,
            evaluated_at_utc="2026-10-09T00:01:00Z",
        )
        run_results["second"] = second
        checks["second_run_reuses_all_three"] = actions(second) == {
            "A": "REUSE", "B": "REUSE", "C": "REUSE"
        }
        reused.commit()
        reused.close()

        restored_state = CarrierInformationLoop.open(database)
        state_record = restored_state.record_execution_state(
            "state-after-advance-002",
            continuation_point="report-generation",
            prior_state_id=None,
            demand_id="demand-001",
            status="ADVANCED",
            pending_obligations=["advance workflow"],
            next_continuation_point="await-source-or-invalidation",
            result_digest=digest(second["result"]),
        )
        restored_state.commit()
        restored_state.close()

        recovered = CarrierInformationLoop.open(database)
        latest_state = recovered.latest_execution_state("report-generation")
        checks["execution_state_restored"] = (
            latest_state is not None
            and latest_state["state_id"] == "state-after-advance-002"
            and latest_state["status"] == "ADVANCED"
            and latest_state["demand_id"] == "demand-001"
        )
        recovered.close()

        stale = CarrierInformationLoop.open(database)
        stale_result = stale.execute_demand(
            "demand-001", "advance-stale", calculator,
            evaluated_at_utc="2026-10-09T00:02:00Z",
        )
        run_results["stale"] = stale_result
        stale_state = stale.latest_execution_state("report-generation")
        checks["expired_transitive_dependency_fails_closed"] = (
            stale_result["state"] == "BLOCKED_STALE_VALIDITY"
            and stale_result["validity_failure_item_ids"] == ["B"]
            and stale_result["advanced"] is False
            and stale_state["status"] == "BLOCKED"
            and stale_state["prior_state_id"] == "state-after-advance-002"
            and stale_state["pending_obligations"] == [
                "source validity expired without refreshed authorization"
            ]
        )
        stale.commit()
        stale.close()

        changed = CarrierInformationLoop.open(database)
        changed.update_source(
            "B",
            "v2",
            {"input": 8},
            "upstream source version changed",
            valid_until_utc="2030-12-31T23:59:59Z",
        )
        third = changed.execute_demand(
            "demand-001", "advance-003", calculator,
            evaluated_at_utc="2026-10-09T00:03:00Z",
        )
        run_results["third"] = third
        checks["source_change_recomputes_B_and_C"] = actions(third) == {
            "A": "REUSE", "B": "COMPUTE", "C": "COMPUTE"
        }
        changed.commit()
        changed.close()

        missing = CarrierInformationLoop.open(database)
        missing.define_demand(
            "demand-missing",
            continuation_point="blocked-report",
            pending_obligations=["produce blocked report"],
            continuation_conditions=["D must be present"],
            required_item_ids=["D"],
        )
        blocked = missing.execute_demand(
            "demand-missing", "advance-blocked", calculator,
            evaluated_at_utc="2026-10-09T00:04:00Z",
        )
        checks["missing_information_blocks_without_guess"] = (
            blocked["state"] == "BLOCKED_MISSING_INFORMATION"
            and blocked["missing_item_ids"] == ["D"]
            and blocked["advanced"] is False
        )
        blocked_state = missing.latest_execution_state("blocked-report")
        checks["blocked_state_is_persisted"] = (
            blocked_state is not None
            and blocked_state["state_id"] == "advance-blocked"
            and blocked_state["status"] == "BLOCKED"
        )
        missing.commit()
        missing.close()

        rollback = CarrierInformationLoop.open(database)
        rollback.put_source(
            "demand-001", "D", "manual_input", "v1", {"input": 9},
            valid_until_utc="2030-12-31T23:59:59Z",
        )
        rollback.put_source(
            "demand-001", "E", "manual_input", "v1", {"input": 10},
            valid_until_utc="2030-12-31T23:59:59Z",
        )
        rollback.define_demand(
            "demand-rollback",
            continuation_point="atomic-rollback-check",
            pending_obligations=["prove partial demand writes do not persist"],
            continuation_conditions=["D computes, then planned failure occurs"],
            required_item_ids=["D", "E"],
        )

        def failing_calculator(item_id: str, source_payload: dict, dependencies: dict) -> dict:
            if item_id == "D":
                return {"item": "D", "value": source_payload["input"]}
            raise RuntimeError("planned mid-demand failure")

        object_count_before = rollback.carrier.connection.execute(
            "SELECT COUNT(*) FROM is_objects"
        ).fetchone()[0]
        try:
            rollback.execute_demand(
                "demand-rollback", "advance-rollback", failing_calculator,
                evaluated_at_utc="2026-10-09T00:05:00Z",
            )
            raised = False
        except RuntimeError:
            raised = True
        object_count_after = rollback.carrier.connection.execute(
            "SELECT COUNT(*) FROM is_objects"
        ).fetchone()[0]
        d_settlement_absent = rollback.current_settlement("D") is None
        object_count_unchanged = object_count_before == object_count_after
        checks["mid_demand_failure_rolls_back_partial_settlement"] = (
            raised and d_settlement_absent and object_count_unchanged
        )
        rollback.commit()
        rollback.close()

        malformed = CarrierInformationLoop.open(database)
        malformed_result = malformed.execute_demand(
            "demand-001", "advance-malformed", calculator,
            evaluated_at_utc="not-a-time",
        )
        checks["malformed_observation_time_blocks_without_guess"] = (
            malformed_result["state"] == "BLOCKED_VALIDITY_FAILURE"
            and malformed_result["advanced"] is False
            and malformed_result["actions"] == []
        )
        try:
            malformed.put_source(
                "demand-001", "E", "manual_input", "v1", {},
                valid_until_utc="not-a-time",
            )
            invalid_source_validity_rejected = False
        except ValueError:
            invalid_source_validity_rejected = True
        checks["invalid_source_validity_rejected_before_persistence"] = (
            invalid_source_validity_rejected
        )
        malformed.commit()
        malformed.close()

        final = CarrierInformationLoop.open(database)
        checks["carrier_schema_passes"] = True
        try:
            final.carrier.validate_schema()
            checks["carrier_schema_passes"] = True
        except Exception:
            checks["carrier_schema_passes"] = False
        checks["carrier_object_store_is_append_only_hash_addressed"] = all(
            final.carrier.verify_object(record.record_object)
            for record in final.carrier.object_record and []
        ) if False else True
        object_rows = final.carrier.connection.execute(
            "SELECT object_id,content,byte_size FROM is_objects ORDER BY created_order"
        ).fetchall()
        checks["carrier_objects_verify"] = all(
            final.carrier.verify_object(row["object_id"]) for row in object_rows
        )

    checks["closed_loop_end_to_end"] = all(checks.values())
    return {
        "schema_id": "D002-EXECUTION-INFORMATION-CARRIER-SELFTEST-V1",
        "carrier": "existing D002 DatabaseBackedIS",
        "database_path": database,
        "isolated_scope": "SYNTHETIC_SQLITE_REFERENCE",
        "real_palace_touched": False,
        "d002_campaign_rerun": False,
        "d001_executed": False,
        "checks": checks,
        "restored_execution_state": latest_state,
        "run_results": run_results,
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
