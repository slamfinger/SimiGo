#!/usr/bin/env python3
"""Bounded JSON bridge for the real SimiGo runtime integration test.

The Swift ExecutionContinuityCoordinator remains the lifecycle authority. This
bridge only exposes the already-accepted read-only PALACE adapter and D002
append-only Information Space carrier.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Optional

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "execution-information-loop"))

from carrier_loop import CarrierInformationLoop, digest, parse_utc  # noqa: E402
from real_palace_loop import RealPalaceConsumptionLoop, RealPalaceSource  # noqa: E402

SNAPSHOT_PATH = ROOT / "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"
SNAPSHOT_SHA256 = "8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444"
CONTINUATION_POINT = "bounded-production-runtime-integration"
REQUIRED_ITEMS = [
    "REAL-COLLECTION",
    "REAL-SEGMENT",
    *[f"REAL-{index}" for index in range(1, 8)],
]


def emit(value: dict) -> None:
    print(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")))


def open_loop(database_path: str) -> tuple[CarrierInformationLoop, RealPalaceConsumptionLoop]:
    loop = CarrierInformationLoop.open(database_path)
    source = RealPalaceSource(str(SNAPSHOT_PATH), SNAPSHOT_SHA256)
    return loop, RealPalaceConsumptionLoop(loop, source)


def close_loop(
    loop: CarrierInformationLoop,
    consumption: RealPalaceConsumptionLoop,
) -> None:
    loop.close()
    consumption.source.close()


def initialize(args: argparse.Namespace) -> None:
    loop = CarrierInformationLoop.create(args.database)
    source = RealPalaceSource(str(SNAPSHOT_PATH), SNAPSHOT_SHA256)
    consumption = RealPalaceConsumptionLoop(loop, source)
    consumption.materialize_sources(
        CONTINUATION_POINT,
        count=7,
        valid_until_utc=args.valid_until,
    )
    loop.define_demand(
        CONTINUATION_POINT,
        continuation_point=CONTINUATION_POINT,
        pending_obligations=[
            "restore bounded production execution",
            "consume real PALACE structural information",
            "continue only with verified settlements",
        ],
        continuation_conditions=[
            "structural relations, validity, dependencies and settlements pass"
        ],
        required_item_ids=REQUIRED_ITEMS,
    )
    loop.commit()
    loop.close()
    source.close()
    emit({"ok": True, "command": "initialize"})


def _open_status(loop: CarrierInformationLoop) -> dict:
    demand = loop.current_demand(CONTINUATION_POINT)
    try:
        restored = loop.restore_continuation(CONTINUATION_POINT)
        state: Optional[dict] = restored["state"]
        required = restored["required_item_ids"]
    except Exception:
        restored = None
        state = loop.latest_execution_state(CONTINUATION_POINT)
        required = list(demand["required_item_ids"]) if demand else []
    return {
        "ok": True,
        "command": "status",
        "demand": demand,
        "required_item_ids": required,
        "execution_state": state,
    }


def status(args: argparse.Namespace) -> None:
    loop, source = open_loop(args.database)
    value = _open_status(loop)
    close_loop(loop, source)
    emit(value)


def audit(args: argparse.Namespace) -> None:
    loop, source = open_loop(args.database)
    state = loop.latest_execution_state(CONTINUATION_POINT)
    settlements = {}
    for item_id in REQUIRED_ITEMS:
        settlement = loop.current_settlement(item_id)
        settlements[item_id] = settlement.get("state") if settlement else None
    object_rows = loop.carrier.connection.execute(
        "SELECT object_id FROM is_objects ORDER BY created_order"
    ).fetchall()
    value = {
        "ok": True,
        "command": "audit",
        "execution_state": state,
        "execution_state_dependency_count": len(
            loop.carrier.get_dependency_history(
                f"execution_state:{state['state_id']}" if state else "none"
            )
        ),
        "settlement_dependency_count": len([
            row for row in loop.carrier.connection.execute(
                "SELECT dependency_id FROM dependency_entries "
                "WHERE dependency_id LIKE 'settlement:%'"
            ).fetchall()
        ]),
        "current_settlement_states": settlements,
        "carrier_object_count": len(object_rows),
        "carrier_all_objects_verify": all(
            loop.carrier.verify_object(row["object_id"]) for row in object_rows
        ),
    }
    close_loop(loop, source)
    emit(value)


def execute(args: argparse.Namespace) -> None:
    loop, source = open_loop(args.database)
    evaluated_at = parse_utc(args.evaluated_at)
    prior_state = loop.latest_execution_state(CONTINUATION_POINT)
    if prior_state is None:
        demand = loop.current_demand(CONTINUATION_POINT)
        if demand is None:
            raise ValueError(f"unknown demand: {CONTINUATION_POINT}")
        required = list(demand["required_item_ids"])
    else:
        restored = loop.restore_continuation(CONTINUATION_POINT)
        prior_state = restored["state"]
        required = restored["required_item_ids"]
    stale_item_ids: list[str] = []
    missing_validity_item_ids: list[str] = []
    invalid_validity_item_ids: list[str] = []
    for item_id in required:
        item = loop.current_item(item_id)
        valid_until = item.get("valid_until_utc") if item else None
        if valid_until is None:
            missing_validity_item_ids.append(item_id)
            continue
        try:
            if evaluated_at > parse_utc(valid_until):
                stale_item_ids.append(item_id)
        except ValueError:
            invalid_validity_item_ids.append(item_id)
    if missing_validity_item_ids:
        result = {
            "demand_id": CONTINUATION_POINT,
            "state": "BLOCKED_VALIDITY_POLICY_MISSING",
            "validity_failure_item_ids": missing_validity_item_ids,
            "actions": [
                {
                    "item_id": item_id,
                    "action": "BLOCKED_VALIDITY_POLICY_MISSING",
                }
                for item_id in missing_validity_item_ids
            ],
            "advanced": False,
            "failure_reason": "validity policy is undefined; fail closed",
        }
        emit({
            "ok": True,
            "command": "execute",
            "prior_execution_state": prior_state,
            "restored_required_item_ids": required,
            "result": result,
        })
        close_loop(loop, source)
        return
    if invalid_validity_item_ids:
        result = {
            "demand_id": CONTINUATION_POINT,
            "state": "BLOCKED_INVALID_VALIDITY",
            "validity_failure_item_ids": invalid_validity_item_ids,
            "actions": [
                {
                    "item_id": item_id,
                    "action": "BLOCKED_INVALID_VALIDITY",
                }
                for item_id in invalid_validity_item_ids
            ],
            "advanced": False,
            "failure_reason": "validity policy is malformed; fail closed",
        }
        emit({
            "ok": True,
            "command": "execute",
            "prior_execution_state": prior_state,
            "restored_required_item_ids": required,
            "result": result,
        })
        close_loop(loop, source)
        return
    if stale_item_ids:
        result = {
            "demand_id": CONTINUATION_POINT,
            "state": "BLOCKED_STALE_VALIDITY",
            "validity_failure_item_ids": stale_item_ids,
            "actions": [
                {
                    "item_id": item_id,
                    "action": "BLOCKED_STALE_VALIDITY",
                }
                for item_id in stale_item_ids
            ],
            "advanced": False,
            "failure_reason": "source validity expired without refreshed authorization",
        }
        emit({
            "ok": True,
            "command": "execute",
            "prior_execution_state": prior_state,
            "restored_required_item_ids": required,
            "result": result,
        })
        close_loop(loop, source)
        return
    result = source.execute_real_demand(
        CONTINUATION_POINT,
        args.advancement,
        count=7,
        evaluated_at_utc=args.evaluated_at,
    )
    if result["advanced"]:
        loop.record_execution_state(
            args.advancement,
            continuation_point=CONTINUATION_POINT,
            prior_state_id=prior_state["state_id"] if prior_state else None,
            demand_id=CONTINUATION_POINT,
            status="ADVANCED",
            pending_obligations=[
                "continue after production-runtime information reconciliation"
            ],
            next_continuation_point="await-next-production-runtime-demand",
            result_digest=digest(result["result"]),
        )
    value = {
        "ok": True,
        "command": "execute",
        "prior_execution_state": prior_state,
        "restored_required_item_ids": required,
        "result": result,
    }
    loop.commit()
    close_loop(loop, source)
    emit(value)


def probe_missing(args: argparse.Namespace) -> None:
    loop, source = open_loop(args.database)
    demand_id = "integrated-proof-missing"
    loop.define_demand(
        demand_id,
        continuation_point="integrated-proof-missing-information",
        pending_obligations=["prove missing information blocks continuation"],
        continuation_conditions=["required source must exist"],
        required_item_ids=["MISSING-REAL-SOURCE"],
    )
    result = source.execute_real_demand(
        demand_id,
        "missing-information-probe",
        count=7,
        evaluated_at_utc=args.evaluated_at,
    )
    value = {
        "ok": True,
        "command": "probe-missing",
        "result": result,
    }
    close_loop(loop, source)
    emit(value)


def invalidate(args: argparse.Namespace) -> None:
    loop, source = open_loop(args.database)
    value = {
        "ok": True,
        "command": "invalidate",
        "invalidation": loop.invalidate_settlement(args.item_id, args.reason),
    }
    loop.commit()
    close_loop(loop, source)
    emit(value)


def source_change(args: argparse.Namespace) -> None:
    loop, source = open_loop(args.database)
    item = loop.current_item(args.item_id)
    if item is None:
        raise ValueError(f"unknown item: {args.item_id}")
    payload = item["source_payload"]
    metadata = payload.get("metadata", {})
    last_modified = metadata.get("last_modified", {})
    if last_modified:
        last_modified["string"] = args.version
    payload["integration_revision"] = args.version
    value = {
        "ok": True,
        "command": "source_change",
        "update": loop.update_source(
            args.item_id,
            args.version,
            payload,
            "bounded production integration isolated source revision",
            valid_until_utc=args.valid_until,
        ),
    }
    loop.commit()
    close_loop(loop, source)
    emit(value)


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    initialize_parser = subparsers.add_parser("initialize")
    initialize_parser.add_argument("--database", required=True)
    initialize_parser.add_argument("--valid-until")
    initialize_parser.set_defaults(handler=initialize)

    status_parser = subparsers.add_parser("status")
    status_parser.add_argument("--database", required=True)
    status_parser.set_defaults(handler=status)

    audit_parser = subparsers.add_parser("audit")
    audit_parser.add_argument("--database", required=True)
    audit_parser.set_defaults(handler=audit)

    execute_parser = subparsers.add_parser("execute")
    execute_parser.add_argument("--database", required=True)
    execute_parser.add_argument("--advancement", required=True)
    execute_parser.add_argument("--evaluated-at", required=True)
    execute_parser.set_defaults(handler=execute)

    invalidate_parser = subparsers.add_parser("invalidate")
    invalidate_parser.add_argument("--database", required=True)
    invalidate_parser.add_argument("--item-id", required=True)
    invalidate_parser.add_argument("--reason", required=True)
    invalidate_parser.set_defaults(handler=invalidate)

    source_change_parser = subparsers.add_parser("source-change")
    source_change_parser.add_argument("--database", required=True)
    source_change_parser.add_argument("--item-id", required=True)
    source_change_parser.add_argument("--version", required=True)
    source_change_parser.add_argument("--valid-until", required=True)
    source_change_parser.set_defaults(handler=source_change)

    missing_parser = subparsers.add_parser("probe-missing")
    missing_parser.add_argument("--database", required=True)
    missing_parser.add_argument("--evaluated-at", required=True)
    missing_parser.set_defaults(handler=probe_missing)

    args = parser.parse_args()
    try:
        args.handler(args)
    except Exception as error:
        emit({
            "ok": False,
            "command": args.command,
            "error_type": type(error).__name__,
            "error": str(error),
        })
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
