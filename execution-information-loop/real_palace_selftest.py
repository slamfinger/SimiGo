#!/usr/bin/env python3
"""Real PALACE snapshot -> typed IS settlement isolated E2E test."""
from __future__ import annotations

import argparse
import hashlib
import json
import tempfile
from pathlib import Path

from carrier_loop import CarrierInformationLoop
from real_palace_loop import RealPalaceSource, RealPalaceConsumptionLoop

EXPECTED_SNAPSHOT_SHA256 = "8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444"


def actions(result):
    return {item["item_id"]: item["action"] for item in result["actions"]}


def run() -> dict:
    checks = {}
    run_results = {}
    with tempfile.TemporaryDirectory(prefix="real-palace-loop-") as temporary:
        database = str(Path(temporary) / "real_palace_information_space.sqlite")
        carrier = CarrierInformationLoop.create(database)
        source = RealPalaceSource(
            "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite",
            EXPECTED_SNAPSHOT_SHA256,
        )
        loop = RealPalaceConsumptionLoop(carrier, source)

        records = loop.materialize_sources(
            "demand-real-001",
            count=7,
            valid_until_utc="2030-12-31T23:59:59Z",
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
            RealPalaceSource(
                "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite",
                EXPECTED_SNAPSHOT_SHA256,
            ),
        )
        required = [f"REAL-{index}" for index in range(1, 8)]
        reopened_carrier.define_demand(
            "demand-real-001",
            continuation_point="real-palace-structural-consumption",
            pending_obligations=["consume seven real source records"],
            continuation_conditions=["metadata digest and source snapshot are stable"],
            required_item_ids=required,
        )
        first = reopened_loop.execute_real_demand(
            "demand-real-001",
            "advance-real-001",
            count=7,
            evaluated_at_utc="2026-10-09T00:00:00Z",
        )
        run_results["first"] = first
        checks["first_run_computes_all_seven"] = actions(first) == {
            item_id: "COMPUTE" for item_id in required
        }
        reopened_carrier.commit()
        reopened_carrier.close()

        reuse_carrier = CarrierInformationLoop.open(database)
        reuse_source = RealPalaceSource(
            "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite",
            EXPECTED_SNAPSHOT_SHA256,
        )
        reuse_loop = RealPalaceConsumptionLoop(reuse_carrier, reuse_source)
        second = reuse_loop.execute_real_demand(
            "demand-real-001",
            "advance-real-002",
            count=7,
            evaluated_at_utc="2026-10-09T00:01:00Z",
        )
        run_results["second"] = second
        checks["second_run_reuses_all_seven"] = actions(second) == {
            item_id: "REUSE" for item_id in required
        }
        reuse_carrier.commit()
        reuse_carrier.close()

        invalidation_carrier = CarrierInformationLoop.open(database)
        invalidation_loop = RealPalaceConsumptionLoop(
            invalidation_carrier,
            RealPalaceSource(
                "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite",
                EXPECTED_SNAPSHOT_SHA256,
            ),
        )
        invalidation = invalidation_loop.invalidate_settlement(
            "REAL-2", "explicit authorized invalidation"
        )
        third = invalidation_loop.execute_real_demand(
            "demand-real-001",
            "advance-real-003",
            count=7,
            evaluated_at_utc="2026-10-09T00:02:00Z",
        )
        run_results["third"] = third
        checks["explicit_invalidation_recomputes_B_and_all_dependents"] = (
            actions(third)["REAL-2"] == "COMPUTE"
            and actions(third)["REAL-3"] == "COMPUTE"
            and actions(third)["REAL-4"] == "COMPUTE"
            and actions(third)["REAL-5"] == "COMPUTE"
            and actions(third)["REAL-6"] == "COMPUTE"
            and actions(third)["REAL-7"] == "COMPUTE"
            and actions(third)["REAL-1"] == "REUSE"
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
