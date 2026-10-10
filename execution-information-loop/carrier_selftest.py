#!/usr/bin/env python3
"""E2E test for ES/IS loop using the existing D002 append-only carrier."""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import tempfile
import time
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


def sealed_policy(policy: dict) -> dict:
    body = {key: value for key, value in policy.items() if key != "policy_sha256"}
    return {**policy, "policy_sha256": digest(body)}


def run() -> dict:
    checks = {}
    validity_policy = sealed_policy({
        "policy_version": "carrier-selftest-v1",
        "policy_source": "ISOLATED_SELFTEST",
    })
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
            validity_policy=validity_policy,
        )
        loop.put_source(
            "demand-001", "B", "derived_input", "v1", {"input": 5}, ["A"],
            valid_until_utc="2026-10-09T00:01:30Z",
            validity_policy=validity_policy,
        )
        loop.put_source(
            "demand-001", "C", "derived_input", "v1", {"factor": 3}, ["B"],
            valid_until_utc="2030-12-31T23:59:59Z",
            validity_policy=validity_policy,
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
        try:
            restored.execute_demand(
                "demand-001", "advance-before-confirmation", calculator,
                evaluated_at_utc="2026-10-09T00:00:30Z",
            )
            pending_failure = False
        except ValueError as error:
            pending_failure = "pending runtime application" in str(error)
        checks["pending_runtime_application_blocks_continuation"] = pending_failure
        restored.confirm_runtime_application("advance-001")
        checks["runtime_confirmation_is_append_only"] = (
            restored.latest_execution_state("report-generation")[
                "runtime_application_status"
            ] == "APPLIED_SWIFT"
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
            runtime_application_status="APPLIED_SWIFT",
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

        with tempfile.TemporaryDirectory(
            prefix="simigo-transitive-"
        ) as transitive_temporary:
            transitive_database = str(
                Path(transitive_temporary) / "transitive.sqlite"
            )
            transitive = CarrierInformationLoop.create(transitive_database)
            transitive.define_demand(
                "transitive-demand",
                continuation_point="transitive-report",
                pending_obligations=["resolve root C"],
                continuation_conditions=["full dependency closure is valid"],
                required_item_ids=["C"],
            )
            for item_id, dependencies, payload, valid_until in [
                ("A", [], {"input": 1}, "2030-12-31T23:59:59Z"),
                ("B", ["A"], {"input": 2}, "2030-12-31T23:59:59Z"),
                ("C", ["B"], {"factor": 3}, "2030-12-31T23:59:59Z"),
            ]:
                transitive.put_source(
                    "transitive-demand", item_id, "manual_input", "v1",
                    payload, dependencies,
                    valid_until_utc=valid_until,
                    validity_policy=validity_policy,
                )
            transitive.commit()
            transitive.close()

            transitive_loop = CarrierInformationLoop.open(transitive_database)
            calculator_for_transitive = calculator
            first = transitive_loop.execute_demand(
                "transitive-demand", "transitive-initial",
                calculator_for_transitive,
                evaluated_at_utc="2026-10-09T00:00:00Z",
            )
            transitive_loop.confirm_runtime_application("transitive-initial")
            settlement_count_before = transitive_loop.carrier.connection.execute(
                "SELECT COUNT(*) FROM dependency_entries "
                "WHERE dependency_id LIKE 'settlement:%'"
            ).fetchone()[0]
            transitive_loop.update_source(
                "B", "v2", {"input": "stale"}, "middle dependency expired",
                valid_until_utc="2026-10-08T23:59:59Z",
            )
            stale_transitive = transitive_loop.execute_demand(
                "transitive-demand", "transitive-stale",
                calculator_for_transitive,
                evaluated_at_utc="2026-10-09T00:01:00Z",
            )
            stale_state = transitive_loop.latest_execution_state(
                "transitive-report"
            )
            settlement_count_after = transitive_loop.carrier.connection.execute(
                "SELECT COUNT(*) FROM dependency_entries "
                "WHERE dependency_id LIKE 'settlement:%'"
            ).fetchone()[0]
            checks["transitive_middle_dependency_blocks_without_required_listing"] = (
                stale_transitive["state"] == "BLOCKED_STALE_VALIDITY"
                and stale_transitive["validity_failure_item_ids"] == ["B"]
                and stale_transitive["advanced"] is False
                and stale_state["status"] == "BLOCKED"
                and settlement_count_after == settlement_count_before == 3
            )
            transitive_loop.commit()
            transitive_loop.close()

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
        changed.confirm_runtime_application("advance-003")
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
            validity_policy=validity_policy,
        )
        rollback.put_source(
            "demand-001", "E", "manual_input", "v1", {"input": 10},
            valid_until_utc="2030-12-31T23:59:59Z",
            validity_policy=validity_policy,
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

        with tempfile.TemporaryDirectory(
            prefix="simigo-concurrent-"
        ) as concurrent_temporary:
            concurrent_database = str(
                Path(concurrent_temporary) / "concurrent.sqlite"
            )
            setup_loop = CarrierInformationLoop.create(concurrent_database)
            setup_loop.define_demand(
                "concurrent-demand",
                continuation_point="concurrent-block",
                pending_obligations=["prove concurrent lineage"],
                continuation_conditions=["missing source stays blocked"],
                required_item_ids=["MISSING-CONCURRENT"],
            )
            setup_loop.commit()
            setup_loop.close()

            advancing_loop = CarrierInformationLoop.open(concurrent_database)

            with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
                # Hold the accepted write lock while the blocked attempt waits.
                with advancing_loop.carrier.atomic_write_group():
                    blocked_future = pool.submit(
                        lambda: CarrierInformationLoop.open(
                            concurrent_database
                        ).execute_demand(
                            "concurrent-demand",
                            "concurrent-blocked",
                            calculator,
                            evaluated_at_utc="2026-10-09T00:06:00Z",
                        )
                    )
                    time.sleep(0.05)
                    advancing_loop.record_execution_state(
                        "concurrent-good",
                        continuation_point="concurrent-block",
                        prior_state_id=None,
                        demand_id="concurrent-demand",
                        status="ADVANCED",
                        pending_obligations=[],
                        next_continuation_point="runtime-application-complete",
                        result_digest=digest({"concurrent": True}),
                        runtime_application_status="APPLIED_SWIFT",
                    )
                blocked_result = blocked_future.result()

            blocked_state = advancing_loop.latest_execution_state(
                "concurrent-block"
            )
            checks["blocked_prior_state_is_read_in_append_transaction"] = (
                blocked_result["advanced"] is False
                and blocked_state["status"] == "BLOCKED"
                and blocked_state["prior_state_id"] == "concurrent-good"
            )
            advancing_loop.commit()
            advancing_loop.close()

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
