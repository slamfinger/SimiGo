#!/usr/bin/env python3
"""Real PALACE snapshot -> typed IS settlement isolated E2E test."""
from __future__ import annotations

import argparse
import hashlib
import json
import tempfile
from pathlib import Path

from carrier_loop import CarrierInformationLoop
from real_palace_loop import (
    RealPalaceConsumptionLoop, RealPalaceSource, structural_validity_policy,
)

EXPECTED_SNAPSHOT_SHA256 = "8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444"
# Resolve the sealed snapshot from the repository root, never from the caller's
# working directory: the harness must be runnable from anywhere.
REPO_ROOT = Path(__file__).resolve().parents[1]
SEALED_SNAPSHOT = REPO_ROOT / "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"
VALID_UNTIL = "2030-12-31T23:59:59Z"


def actions(result):
    return {item["item_id"]: item["action"] for item in result["actions"]}


def record_advance(prefix: str, result: dict, loop, checks: dict) -> None:
    """Record whether a demand advanced and whether its runtime was confirmed.

    A non-ADVANCED result is reported with its own state and failure_reason
    instead of being indexed blindly: a blocked demand has no computed or
    reused item list, and reading one would hide the real cause.
    """
    checks[f"{prefix}_advanced"] = result.get("state") == "ADVANCED"
    if checks[f"{prefix}_advanced"]:
        checks[f"{prefix}_runtime_confirmed"] = loop.confirm_runtime(result) is not None
    else:
        checks[f"{prefix}_runtime_confirmed"] = False


def run() -> dict:
    checks = {}
    run_results = {}
    with tempfile.TemporaryDirectory(prefix="real-palace-loop-") as temporary:
        database = str(Path(temporary) / "real_palace_information_space.sqlite")
        carrier = CarrierInformationLoop.create(database)
        source = RealPalaceSource(str(SEALED_SNAPSHOT), EXPECTED_SNAPSHOT_SHA256)
        loop = RealPalaceConsumptionLoop(carrier, source)

        # The isolated harness declares the window and the policy it is judged
        # against, so the forward path never starts out as BLOCKED.
        policy = structural_validity_policy()
        records = loop.materialize_sources(
            "demand-real-001",
            count=7,
            valid_until_utc=VALID_UNTIL,
            validity_policy=policy,
        )
        checks["seven_real_sources"] = len(records) == 7
        checks["all_real_records"] = all(
            item["source"] == "REAL_PALACE_SNAPSHOT" for item in records
        )
        carrier.commit()
        carrier.close()
        source.close()

        reopened_carrier = CarrierInformationLoop.open(database)
        reopened_loop = RealPalaceConsumptionLoop(
            reopened_carrier,
            RealPalaceSource(str(SEALED_SNAPSHOT), EXPECTED_SNAPSHOT_SHA256),
        )
        required = ["REAL-COLLECTION", "REAL-SEGMENT"] + [
            f"REAL-{index}" for index in range(1, 8)
        ]
        reopened_carrier.define_demand(
            "demand-real-001",
            continuation_point="real-palace-structural-consumption",
            pending_obligations=["consume one real collection, segment and seven records"],
            continuation_conditions=[
                "collection/segment/embedding structural relations are stable"
            ],
            required_item_ids=required,
        )
        first = reopened_loop.execute_real_demand(
            "demand-real-001",
            "advance-real-001",
            count=7,
            evaluated_at_utc="2026-10-09T00:00:00Z",
        )
        run_results["first"] = first
        record_advance("first", first, reopened_loop, checks)
        checks["first_run_computes_real_structural_graph"] = actions(first) == {
            item_id: "COMPUTE" for item_id in required
        }
        reopened_carrier.commit()
        reopened_carrier.close()

        reuse_carrier = CarrierInformationLoop.open(database)
        reuse_source = RealPalaceSource(str(SEALED_SNAPSHOT), EXPECTED_SNAPSHOT_SHA256)
        reuse_loop = RealPalaceConsumptionLoop(reuse_carrier, reuse_source)
        second = reuse_loop.execute_real_demand(
            "demand-real-001",
            "advance-real-002",
            count=7,
            evaluated_at_utc="2026-10-09T00:01:00Z",
        )
        run_results["second"] = second
        record_advance("second", second, reuse_loop, checks)
        checks["second_run_reuses_real_structural_graph"] = actions(second) == {
            item_id: "REUSE" for item_id in required
        }
        reuse_carrier.commit()
        reuse_carrier.close()

        invalidation_carrier = CarrierInformationLoop.open(database)
        invalidation_loop = RealPalaceConsumptionLoop(
            invalidation_carrier,
            RealPalaceSource(str(SEALED_SNAPSHOT), EXPECTED_SNAPSHOT_SHA256),
        )
        invalidation = invalidation_loop.invalidate_settlement(
            "REAL-SEGMENT", "explicit structural segment invalidation"
        )
        third = invalidation_loop.execute_real_demand(
            "demand-real-001",
            "advance-real-003",
            count=7,
            evaluated_at_utc="2026-10-09T00:02:00Z",
        )
        run_results["third"] = third
        record_advance("third", third, invalidation_loop, checks)
        checks["structural_invalidation_propagates_segment_closure"] = (
            actions(third)["REAL-COLLECTION"] == "REUSE"
            and actions(third)["REAL-SEGMENT"] == "COMPUTE"
            and all(actions(third)[f"REAL-{index}"] == "COMPUTE" for index in range(1, 8))
        )
        invalidation_carrier.commit()
        invalidation_carrier.close()

        final = CarrierInformationLoop.open(database)
        final.carrier.validate_schema()
        object_rows = final.carrier.connection.execute(
            "SELECT object_id FROM is_objects ORDER BY created_order"
        ).fetchall()
        checks["carrier_objects_verify"] = all(
            final.carrier.verify_object(row["object_id"]) for row in object_rows
        )
        final.close()

    checks["closed_loop_real_source_mapping"] = all(checks.values())
    return {
        "schema_id": "D002-REAL-PALACE-CONSUMPTION-SELFTEST-V1",
        "scope": "ISOLATED_REAL_SNAPSHOT_READONLY_METADATA",
        "dependency_graph_origin": "REAL_PALACE_COLLECTION_SEGMENT_PARENT_METADATA",
        "vector_column_reads": False,
        "snapshot_sha256": EXPECTED_SNAPSHOT_SHA256,
        "vector_or_fulltext_reads": False,
        "model_or_cloud_calls": False,
        "palace_mutation": False,
        "validity_condition_origin": "ISOLATED_TEST_DECLARED_WINDOW",
        "d002_campaign_rerun": False,
        "d001_executed": False,
        "checks": checks,
        "invalidation": invalidation,
        "run_results": run_results,
        "declared_validity": {
            "valid_until_utc": VALID_UNTIL,
            "validity_policy_sha256": policy["policy_sha256"],
        },
        "result": "PASS" if checks["closed_loop_real_source_mapping"] else "FAIL",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output")
    args = parser.parse_args()
    report = run()
    text = json.dumps(report, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
    print(text, end="")
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
