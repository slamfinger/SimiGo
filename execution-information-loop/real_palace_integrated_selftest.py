#!/usr/bin/env python3
"""One-database real-source Execution/Information closed-loop acceptance test."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sqlite3
import tempfile
from pathlib import Path

from carrier_loop import CarrierInformationLoop, digest
from real_palace_loop import RealPalaceConsumptionLoop, RealPalaceSource

SEALED_SNAPSHOT = "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"
SEALED_SHA256 = "8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444"
VALID_UNTIL = "2030-12-31T23:59:59Z"


def sha256_file(path: str) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def actions(result: dict) -> dict:
    return {action["item_id"]: action["action"] for action in result["actions"]}


def open_loop(database: str, snapshot: str, snapshot_sha256: str):
    carrier = CarrierInformationLoop.open(database)
    source = RealPalaceSource(snapshot, snapshot_sha256)
    return carrier, RealPalaceConsumptionLoop(carrier, source)


def record_state(
    carrier: CarrierInformationLoop,
    state_id: str,
    prior_state_id: str | None,
    result: dict,
) -> dict:
    return carrier.record_execution_state(
        state_id,
        continuation_point="real-palace-integrated-closed-loop",
        prior_state_id=prior_state_id,
        demand_id="demand-real-001",
        status="ADVANCED",
        pending_obligations=["continue after verified information reconciliation"],
        next_continuation_point="await-next-execution-demand",
        result_digest=digest(result["result"]),
    )


def run() -> dict:
    checks = {}
    run_results = {}
    states = {}
    prior_state_id = None
    with tempfile.TemporaryDirectory(prefix="real-palace-integrated-") as temporary:
        database = str(Path(temporary) / "integrated_real_loop.sqlite")
        snapshot = str(Path(temporary) / "PALACE_SNAPSHOT.copy.sqlite")
        shutil.copyfile(SEALED_SNAPSHOT, snapshot)
        snapshot_sha256 = sha256_file(snapshot)
        checks["isolated_copy_matches_sealed_snapshot"] = snapshot_sha256 == SEALED_SHA256

        carrier = CarrierInformationLoop.create(database)
        source = RealPalaceSource(snapshot, snapshot_sha256)
        loop = RealPalaceConsumptionLoop(carrier, source)
        loop.materialize_sources(
            "demand-real-001", count=7, valid_until_utc=VALID_UNTIL
        )
        carrier.define_demand(
            "demand-real-001",
            continuation_point="real-palace-integrated-closed-loop",
            pending_obligations=[
                "restore execution",
                "verify valid information",
                "continue incrementally",
            ],
            continuation_conditions=[
                "structural relations, validity, dependencies and settlements pass"
            ],
            required_item_ids=[
                "REAL-COLLECTION", "REAL-SEGMENT",
                *[f"REAL-{index}" for index in range(1, 8)],
            ],
        )
        first = loop.execute_real_demand(
            "demand-real-001", "advance-001", count=7,
            evaluated_at_utc="2026-10-09T00:00:00Z",
        )
        run_results["first"] = first
        checks["first_run_computes_real_graph"] = len(first["computed_item_ids"]) == 9
        state = record_state(carrier, "state-001-initial", prior_state_id, first)
        states["initial"] = state
        prior_state_id = "state-001-initial"
        carrier.commit()
        carrier.close()
        source.close()

        carrier, loop = open_loop(database, snapshot, snapshot_sha256)
        continuation = carrier.restore_continuation(
            "real-palace-integrated-closed-loop"
        )
        restored = continuation["state"]
        checks["execution_state_restored"] = (
            restored is not None
            and restored["state_id"] == "state-001-initial"
            and restored["status"] == "ADVANCED"
        )
        checks["demand_derived_from_restored_execution_state"] = (
            continuation["demand"]["demand_id"] == "demand-real-001"
            and continuation["required_item_ids"][0] == "REAL-COLLECTION"
            and continuation["required_item_ids"][-1] == "REAL-7"
        )
        second = loop.execute_real_demand(
            continuation["demand"]["demand_id"], "advance-002", count=7,
            evaluated_at_utc="2026-10-09T00:01:00Z",
        )
        run_results["second"] = second
        checks["valid_settlements_reuse_all_nine"] = len(second["reused_item_ids"]) == 9
        state = record_state(carrier, "state-002-reuse", prior_state_id, second)
        states["reuse"] = state
        prior_state_id = "state-002-reuse"

        invalidation = loop.invalidate_settlement(
            "REAL-3", "integrated explicit invalidation"
        )
        third = loop.execute_real_demand(
            "demand-real-001", "advance-003", count=7,
            evaluated_at_utc="2026-10-09T00:02:00Z",
        )
        run_results["third"] = third
        checks["explicit_invalidation_propagates_to_child"] = (
            actions(third)["REAL-3"] == "COMPUTE"
            and actions(third)["REAL-4"] == "COMPUTE"
            and sum(action == "REUSE" for action in actions(third).values()) == 7
        )
        state = record_state(carrier, "state-003-invalidation", prior_state_id, third)
        states["invalidation"] = state
        prior_state_id = "state-003-invalidation"
        carrier.commit()
        carrier.close()

        connection = sqlite3.connect(snapshot)
        connection.execute(
            "UPDATE embedding_metadata SET string_value=? "
            "WHERE id=1 AND key='last_modified'",
            ("2026-10-09T00:02:30.000000",),
        )
        connection.commit()
        connection.close()
        changed_sha256 = sha256_file(snapshot)
        checks["isolated_source_changed"] = changed_sha256 != snapshot_sha256
        snapshot_sha256 = changed_sha256

        carrier, loop = open_loop(database, snapshot, snapshot_sha256)
        loop.materialize_sources(
            "demand-real-001", count=7, valid_until_utc=VALID_UNTIL
        )
        fourth = loop.execute_real_demand(
            "demand-real-001", "advance-004", count=7,
            evaluated_at_utc="2026-10-09T00:03:00Z",
        )
        run_results["fourth"] = fourth
        checks["source_change_recomputes_only_changed_item"] = (
            actions(fourth)["REAL-1"] == "COMPUTE"
            and sum(action == "REUSE" for action in actions(fourth).values()) == 8
        )
        state = record_state(carrier, "state-004-source-change", prior_state_id, fourth)
        states["source_change"] = state
        prior_state_id = "state-004-source-change"

        stale_source = carrier.current_item("REAL-3")
        carrier.update_source(
            "REAL-3",
            stale_source["source_version"],
            stale_source["source_payload"],
            "integrated validity-window change",
            valid_until_utc="2026-10-09T00:03:30Z",
        )
        fifth = loop.execute_real_demand(
            "demand-real-001", "advance-005", count=7,
            evaluated_at_utc="2026-10-09T00:04:00Z",
        )
        run_results["fifth"] = fifth
        checks["validity_expiration_propagates_to_child"] = (
            actions(fifth)["REAL-3"] == "COMPUTE"
            and actions(fifth)["REAL-4"] == "COMPUTE"
            and sum(action == "REUSE" for action in actions(fifth).values()) == 7
        )
        state = record_state(carrier, "state-005-expiration", prior_state_id, fifth)
        states["expiration"] = state
        prior_state_id = "state-005-expiration"
        carrier.commit()
        carrier.close()

        carrier, loop = open_loop(database, snapshot, snapshot_sha256)
        blocked = loop.execute_real_demand(
            "demand-real-001", "advance-malformed", count=7,
            evaluated_at_utc="not-a-time",
        )
        checks["malformed_observation_blocks_same_real_loop"] = (
            blocked["state"] == "BLOCKED_VALIDITY_FAILURE"
            and blocked["advanced"] is False
            and blocked["actions"] == []
        )

        carrier.put_source(
            "demand-real-001", "ROLLBACK-A", "controlled_failure", "v1", {"value": 1},
            valid_until_utc=VALID_UNTIL,
        )
        carrier.put_source(
            "demand-real-001", "ROLLBACK-B", "controlled_failure", "v1", {"value": 2},
            valid_until_utc=VALID_UNTIL,
        )
        carrier.define_demand(
            "demand-atomic-rollback",
            continuation_point="integrated-atomic-rollback",
            pending_obligations=["prove partial writes do not survive failure"],
            continuation_conditions=["first computes, second raises"],
            required_item_ids=["ROLLBACK-A", "ROLLBACK-B"],
        )

        def failing_consumer(item_id: str, source_payload: dict, dependencies: dict) -> dict:
            if item_id == "ROLLBACK-A":
                return {"value": source_payload["value"]}
            raise RuntimeError("planned integrated mid-demand failure")

        object_count_before = carrier.carrier.connection.execute(
            "SELECT COUNT(*) FROM is_objects"
        ).fetchone()[0]
        try:
            carrier.execute_demand(
                "demand-atomic-rollback", "advance-rollback", failing_consumer,
                evaluated_at_utc="2026-10-09T00:05:00Z",
            )
            raised = False
        except RuntimeError:
            raised = True
        object_count_after = carrier.carrier.connection.execute(
            "SELECT COUNT(*) FROM is_objects"
        ).fetchone()[0]
        checks["mid_demand_failure_rolls_back_atomically"] = (
            raised
            and object_count_before == object_count_after
            and carrier.current_settlement("ROLLBACK-A") is None
            and carrier.current_settlement("ROLLBACK-B") is None
        )
        carrier.commit()
        carrier.close()

        final = CarrierInformationLoop.open(database)
        final.carrier.validate_schema()
        object_rows = final.carrier.connection.execute(
            "SELECT object_id FROM is_objects ORDER BY created_order"
        ).fetchall()
        checks["carrier_objects_verify"] = all(
            final.carrier.verify_object(row["object_id"]) for row in object_rows
        )
        checks["execution_state_chain_latest_restorable"] = (
            final.restore_continuation("real-palace-integrated-closed-loop")["state"]["state_id"]
            == "state-005-expiration"
        )
        final.close()

    checks["real_palace_integrated_closed_loop"] = all(checks.values())
    return {
        "schema_id": "D002-REAL-PALACE-INTEGRATED-CLOSED-LOOP-SELFTEST-V1",
        "scope": "ONE_DATABASE_REAL_SOURCE_ISOLATED_COPY",
        "sealed_snapshot_sha256": SEALED_SHA256,
        "sealed_snapshot_mutated": False,
        "isolated_copy_mutated": True,
        "same_carrier_database": True,
        "same_real_source_copy": True,
        "execution_states": states,
        "invalidation": invalidation,
        "run_results": run_results,
        "vector_or_fulltext_reads": False,
        "model_or_cloud_calls": False,
        "d002_campaign_rerun": False,
        "d001_executed": False,
        "checks": checks,
        "result": "PASS" if checks["real_palace_integrated_closed_loop"] else "FAIL",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output")
    args = parser.parse_args()
    report = run()
    text = json.dumps(report, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    print(text, end="")
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
