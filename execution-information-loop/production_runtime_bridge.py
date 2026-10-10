#!/usr/bin/env python3
"""Bounded JSON bridge for the real SimiGo runtime integration test.

The Swift ExecutionContinuityCoordinator remains the lifecycle authority. This
bridge only exposes the already-accepted read-only PALACE adapter and D002
append-only Information Space carrier.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path
from typing import Optional

BRIDGE_ROOT = Path(__file__).resolve().parent
RUNTIME_ROOT = Path(
    os.environ.get(
        "SIMIGO_RUNTIME_ROOT",
        BRIDGE_ROOT.parent,
    )
).resolve()
sys.path.insert(0, str(RUNTIME_ROOT / "execution-information-loop"))
sys.path.insert(0, str(RUNTIME_ROOT / "database-carrier-replication" / "implementation"))
sys.path.insert(0, str(RUNTIME_ROOT / "lib"))

from carrier_loop import CarrierInformationLoop, digest, parse_utc  # noqa: E402
from real_palace_loop import RealPalaceConsumptionLoop, RealPalaceSource  # noqa: E402

SNAPSHOT_PATH = Path(
    os.environ.get(
        "SIMIGO_INFO_SNAPSHOT_PATH",
        RUNTIME_ROOT / "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite",
    )
).resolve()
SNAPSHOT_SHA256 = "8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444"
VALIDITY_POLICY_PATH = Path(
    os.environ.get("SIMIGO_INFO_VALIDITY_POLICY_PATH", "")
).expanduser()
CONTINUATION_POINT = "bounded-production-runtime-integration"
REQUIRED_ITEMS = [
    "REAL-COLLECTION",
    "REAL-SEGMENT",
    *[f"REAL-{index}" for index in range(1, 8)],
]


def emit(value: dict) -> None:
    print(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")))


def load_deployment_validity_policy() -> dict:
    """Load the deployment validity authority; production mode requires it."""
    if not VALIDITY_POLICY_PATH.is_file():
        raise ValueError(
            f"validity policy file missing: {VALIDITY_POLICY_PATH}"
        )
    try:
        policy = json.loads(VALIDITY_POLICY_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"invalid validity policy: {error}") from error
    if policy.get("schema_id") != "SIMIGO-INFO-VALIDITY-POLICY-V1":
        raise ValueError("validity policy schema must be SIMIGO-INFO-VALIDITY-POLICY-V1")
    if policy.get("missing_policy") != "REJECT":
        raise ValueError("validity policy missing_policy must be REJECT")
    if policy.get("dependency_propagation") != "ALL_TRANSITIVE":
        raise ValueError("validity policy dependency_propagation must be ALL_TRANSITIVE")
    for field in ["policy_version", "policy_source"]:
        if not isinstance(policy.get(field), str) or not policy.get(field):
            raise ValueError(f"validity policy {field} must be a nonempty string")
    parse_utc(policy["default_valid_until_utc"])
    policy["policy_sha256"] = hashlib.sha256(
        json.dumps(policy, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return policy


def deployment_default_validity(policy: dict) -> str:
    return policy["default_valid_until_utc"]


def current_deployment_policy() -> Optional[dict]:
    return (
        load_deployment_validity_policy()
        if os.environ.get("SIMIGO_INFO_VALIDITY_POLICY_PATH")
        else None
    )


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
    validity_policy = current_deployment_policy()
    if validity_policy:
        policy_valid_until = deployment_default_validity(validity_policy)
        if args.valid_until and args.valid_until != policy_valid_until:
            raise ValueError("command validity conflicts with deployment validity policy")
        valid_until = policy_valid_until
    else:
        valid_until = args.valid_until
    loop = CarrierInformationLoop.create(args.database)
    source = RealPalaceSource(str(SNAPSHOT_PATH), SNAPSHOT_SHA256)
    consumption = RealPalaceConsumptionLoop(loop, source)
    consumption.materialize_sources(
        CONTINUATION_POINT,
        count=7,
        valid_until_utc=valid_until,
        validity_policy=validity_policy,
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
    # The digest—not merely this pre-transaction read—is bound into the
    # carrier transaction. A committed concurrent policy change therefore
    # fails closed inside execute_demand before any calculator or settlement.
    policy = current_deployment_policy()
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
    result = source.execute_real_demand(
        CONTINUATION_POINT,
        args.advancement,
        count=7,
        evaluated_at_utc=args.evaluated_at,
        expected_validity_policy_sha256=(
            policy["policy_sha256"] if policy else None
        ),
        require_deployment_policy=True,
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


def confirm_runtime_application(args: argparse.Namespace) -> None:
    loop, source = open_loop(args.database)
    confirmation = loop.confirm_runtime_application(args.state_id)
    state = loop.latest_execution_state(CONTINUATION_POINT)
    value = {
        "ok": True,
        "command": "confirm-runtime-application",
        "confirmation": confirmation,
        "execution_state": state,
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
    policy = current_deployment_policy()
    if policy:
        default_validity = deployment_default_validity(policy)
        if args.valid_until != default_validity:
            authorized_probe = (
                policy.get("expired_source_revision_probe")
                == "ISOLATED_E2E_ONLY"
                and args.valid_until < default_validity
            )
            if not authorized_probe:
                close_loop(loop, source)
                raise ValueError(
                    "source validity conflicts with current deployment policy"
                )
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
            validity_policy=policy,
        ),
    }
    loop.commit()
    close_loop(loop, source)
    emit(value)


def record_blocked(args: argparse.Namespace) -> None:
    loop, source = open_loop(args.database)
    loop.record_execution_state(
        args.state_id,
        continuation_point=CONTINUATION_POINT,
        prior_state_id=args.prior_state_id or None,
        demand_id=CONTINUATION_POINT,
        status="BLOCKED",
        pending_obligations=[args.reason],
        next_continuation_point="await-operator-rollback-or-repair",
        result_digest=digest({"blocked_reason": args.reason}),
    )
    state = loop.latest_execution_state(CONTINUATION_POINT)
    value = {
        "ok": True,
        "command": "record-blocked",
        "execution_state": state,
    }
    loop.commit()
    close_loop(loop, source)
    emit(value)


def find_execution_state(loop: CarrierInformationLoop, state_id: str):
    row = loop.carrier.connection.execute(
        "SELECT record_object FROM is_index_entries "
        "WHERE srs_identity = ? "
        "ORDER BY append_order DESC LIMIT 1",
        (f"execution_state:{CONTINUATION_POINT}:{state_id}",),
    ).fetchone()
    if row is None:
        return None
    return json.loads(loop.carrier.get_object(row["record_object"]))


def rollback_to_state(args: argparse.Namespace) -> None:
    loop, source = open_loop(args.database)
    target = find_execution_state(loop, args.target_state_id)
    if target is None:
        raise ValueError(f"unknown rollback state: {args.target_state_id}")
    if target.get("status") != "ADVANCED":
        raise ValueError("rollback target is not an ADVANCED execution state")
    if target.get("demand_id") != CONTINUATION_POINT:
        raise ValueError("rollback target demand mismatch")
    if target.get("runtime_application_status") != "APPLIED_SWIFT":
        confirmation = find_execution_state(
            loop, f"{target['state_id']}:runtime-applied"
        )
        if confirmation is None or confirmation.get(
            "runtime_application_status"
        ) != "APPLIED_SWIFT":
            raise ValueError("rollback target has no runtime-application completion")
    prior = loop.latest_execution_state(CONTINUATION_POINT)
    loop.record_execution_state(
        args.new_state_id,
        continuation_point=CONTINUATION_POINT,
        prior_state_id=prior["state_id"] if prior else None,
        demand_id=CONTINUATION_POINT,
        status="ADVANCED",
        pending_obligations=target["pending_obligations"],
        next_continuation_point=target["next_continuation_point"],
        result_digest=target["result_digest"],
        runtime_application_status="APPLIED_SWIFT",
    )
    after = loop.latest_execution_state(CONTINUATION_POINT)
    value = {
        "ok": True,
        "command": "rollback-to-state",
        "target": target,
        "prior_execution_state": prior,
        "execution_state": after,
    }
    loop.commit()
    close_loop(loop, source)
    emit(value)


def diagnostics(args: argparse.Namespace) -> None:
    loop, source = open_loop(args.database)
    evaluated_at = parse_utc(args.evaluated_at)
    state = loop.latest_execution_state(CONTINUATION_POINT)
    settlements = {}
    missing_validity = []
    stale_validity = []
    invalid_validity = []
    for item_id in REQUIRED_ITEMS:
        item = loop.current_item(item_id)
        settlement = loop.current_settlement(item_id)
        settlements[item_id] = settlement.get("state") if settlement else None
        valid_until = item.get("valid_until_utc") if item else None
        if valid_until is None:
            missing_validity.append(item_id)
            continue
        try:
            if evaluated_at > parse_utc(valid_until):
                stale_validity.append(item_id)
        except ValueError:
            invalid_validity.append(item_id)
    object_rows = loop.carrier.connection.execute(
        "SELECT object_id FROM is_objects ORDER BY created_order"
    ).fetchall()
    integrity = loop.carrier.connection.execute("PRAGMA integrity_check").fetchone()[0]
    value = {
        "ok": True,
        "command": "diagnostics",
        "database_integrity": integrity,
        "execution_state": state,
        "current_settlement_states": settlements,
        "missing_validity_item_ids": missing_validity,
        "stale_validity_item_ids": stale_validity,
        "invalid_validity_item_ids": invalid_validity,
        "carrier_object_count": len(object_rows),
        "carrier_all_objects_verify": all(
            loop.carrier.verify_object(row["object_id"]) for row in object_rows
        ),
        "rollback_policy": (
            "APPEND_LAST_GOOD_ADVANCED_STATE; never mutate or delete history"
        ),
    }
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

    blocked_parser = subparsers.add_parser("record-blocked")
    blocked_parser.add_argument("--database", required=True)
    blocked_parser.add_argument("--state-id", required=True)
    blocked_parser.add_argument("--prior-state-id")
    blocked_parser.add_argument("--reason", required=True)
    blocked_parser.set_defaults(handler=record_blocked)

    rollback_parser = subparsers.add_parser("rollback-to-state")
    rollback_parser.add_argument("--database", required=True)
    rollback_parser.add_argument("--target-state-id", required=True)
    rollback_parser.add_argument("--new-state-id", required=True)
    rollback_parser.set_defaults(handler=rollback_to_state)

    confirmation_parser = subparsers.add_parser("confirm-runtime-application")
    confirmation_parser.add_argument("--database", required=True)
    confirmation_parser.add_argument("--state-id", required=True)
    confirmation_parser.set_defaults(handler=confirm_runtime_application)

    diagnostics_parser = subparsers.add_parser("diagnostics")
    diagnostics_parser.add_argument("--database", required=True)
    diagnostics_parser.add_argument("--evaluated-at", required=True)
    diagnostics_parser.set_defaults(handler=diagnostics)

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
