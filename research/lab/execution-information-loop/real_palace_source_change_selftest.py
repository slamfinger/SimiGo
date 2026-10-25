#!/usr/bin/env python3
"""Real-source source-change test on an isolated copy of the sealed snapshot."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sqlite3
import tempfile
from pathlib import Path

from carrier_loop import CarrierInformationLoop
from real_palace_loop import (
    RealPalaceConsumptionLoop, RealPalaceSource, structural_validity_policy,
)

# Resolve the sealed snapshot from the repository root, never from the caller's
# working directory: the harness must be runnable from anywhere.
REPO_ROOT = Path(__file__).resolve().parents[1]
SEALED_SNAPSHOT = str(
    REPO_ROOT / "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"
)
EXPECTED_SHA256 = "8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444"
VALID_UNTIL = "2030-12-31T23:59:59Z"


def sha256_file(path: str) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def actions(result: dict) -> dict:
    return {action["item_id"]: action["action"] for action in result["actions"]}


def open_loop(database: str, snapshot: str, snapshot_sha256: str):
    carrier = CarrierInformationLoop.open(database)
    source = RealPalaceSource(snapshot, snapshot_sha256)
    return carrier, RealPalaceConsumptionLoop(carrier, source)


def record_advance(prefix: str, result: dict, loop, checks: dict) -> None:
    """Record whether a demand advanced and whether its runtime was confirmed.

    A non-ADVANCED result carries neither computed nor reused item ids; reading
    them blindly would replace the real blocking cause with a KeyError.
    """
    checks[f"{prefix}_advanced"] = result.get("state") == "ADVANCED"
    if checks[f"{prefix}_advanced"]:
        checks[f"{prefix}_runtime_confirmed"] = loop.confirm_runtime(result) is not None
    else:
        checks[f"{prefix}_runtime_confirmed"] = False


def item_ids(result: dict, key: str) -> list:
    return result.get(key) or []


def run() -> dict:
    checks = {}
    run_results = {}
    with tempfile.TemporaryDirectory(prefix="real-palace-source-change-") as temporary:
        database = str(Path(temporary) / "source_change_loop.sqlite")
        copied_snapshot = str(Path(temporary) / "PALACE_SNAPSHOT.copy.sqlite")
        shutil.copyfile(SEALED_SNAPSHOT, copied_snapshot)
        initial_sha256 = sha256_file(copied_snapshot)
        checks["isolated_copy_matches_sealed_snapshot"] = initial_sha256 == EXPECTED_SHA256

        carrier = CarrierInformationLoop.create(database)
        source = RealPalaceSource(copied_snapshot, initial_sha256)
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
        carrier.define_demand(
            "demand-real-001",
            continuation_point="real-palace-source-change",
            pending_obligations=["consume current real records"],
            continuation_conditions=["structural and metadata digests are current"],
            required_item_ids=[
                "REAL-COLLECTION", "REAL-SEGMENT",
                *[f"REAL-{index}" for index in range(1, 8)],
            ],
        )
        first = loop.execute_real_demand(
            "demand-real-001",
            "advance-real-001",
            count=7,
            evaluated_at_utc="2026-10-09T00:00:00Z",
        )
        run_results["first"] = first
        record_advance("first", first, loop, checks)
        checks["first_run_computes_all_nine"] = len(item_ids(first, "computed_item_ids")) == 9
        carrier.commit()
        carrier.close()
        source.close()

        reuse_carrier, reuse_loop = open_loop(database, copied_snapshot, initial_sha256)
        second = reuse_loop.execute_real_demand(
            "demand-real-001",
            "advance-real-002",
            count=7,
            evaluated_at_utc="2026-10-09T00:01:00Z",
        )
        run_results["second"] = second
        record_advance("second", second, reuse_loop, checks)
        checks["second_run_reuses_all_nine"] = len(item_ids(second, "reused_item_ids")) == 9
        reuse_carrier.close()

        connection = sqlite3.connect(copied_snapshot)
        connection.execute(
            "UPDATE embedding_metadata SET string_value=? "
            "WHERE id=1 AND key='last_modified'",
            ("2026-10-09T00:01:30.000000",),
        )
        connection.commit()
        connection.close()
        changed_sha256 = sha256_file(copied_snapshot)
        checks["isolated_source_changed"] = changed_sha256 != initial_sha256

        changed_carrier, changed_loop = open_loop(database, copied_snapshot, changed_sha256)
        changed_loop.materialize_sources(
            "demand-real-001",
            count=7,
            valid_until_utc=VALID_UNTIL,
            validity_policy=policy,
        )
        third = changed_loop.execute_real_demand(
            "demand-real-001",
            "advance-real-003",
            count=7,
            evaluated_at_utc="2026-10-09T00:02:00Z",
        )
        run_results["third"] = third
        record_advance("third", third, changed_loop, checks)
        checks["changed_source_recomputes_only_REAL_1"] = (
            actions(third)["REAL-COLLECTION"] == "REUSE"
            and actions(third)["REAL-SEGMENT"] == "REUSE"
            and actions(third)["REAL-1"] == "COMPUTE"
            and all(actions(third)[f"REAL-{index}"] == "REUSE" for index in range(2, 8))
        )
        current_source = changed_carrier.current_item("REAL-1")
        checks["changed_version_persisted"] = (
            current_source is not None
            and current_source["source_version"] == "2026-10-09T00:01:30.000000"
        )
        changed_carrier.commit()
        changed_carrier.close()

        final = CarrierInformationLoop.open(database)
        final.carrier.validate_schema()
        object_rows = final.carrier.connection.execute(
            "SELECT object_id FROM is_objects ORDER BY created_order"
        ).fetchall()
        checks["carrier_objects_verify"] = all(
            final.carrier.verify_object(row["object_id"]) for row in object_rows
        )
        final.close()

    checks["real_source_change_loop_end_to_end"] = all(checks.values())
    return {
        "schema_id": "D002-REAL-PALACE-SOURCE-CHANGE-SELFTEST-V1",
        "scope": "ISOLATED_REAL_SNAPSHOT_COPY_READONLY_ADAPTER",
        "sealed_snapshot_untouched": True,
        "isolated_copy_mutated": True,
        "snapshot_sha256": EXPECTED_SHA256,
        "vector_or_fulltext_reads": False,
        "model_or_cloud_calls": False,
        "d002_campaign_rerun": False,
        "d001_executed": False,
        "checks": checks,
        "run_results": run_results,
        "declared_validity": {
            "valid_until_utc": VALID_UNTIL,
            "validity_policy_sha256": policy["policy_sha256"],
        },
        "result": "PASS" if checks["real_source_change_loop_end_to_end"] else "FAIL",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output")
    args = parser.parse_args()
    report = run()
    print(json.dumps(report, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    if args.output:
        Path(args.output).write_text(
            json.dumps(report, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n",
            encoding="utf-8",
        )
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
