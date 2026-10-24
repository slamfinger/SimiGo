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
import re
import secrets
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
from settlement_provenance import signature_descriptor as _settlement_signature_descriptor  # noqa: E402
from declarative_result_contract import (  # noqa: E402
    CONTRACT_VERSION,
    declared_contract,
    derive_extraction_view,
    validate_declared_result,
)

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

# Real-model handoff task (isolated run): one registered source, two model
# items. The continuation point is deliberately the production one so the
# existing Swift status/recovery/checkpoint authority reads the same lineage.
TASK_SOURCE_ID = "TASK-SOURCE"
TASK_U1_ID = "TASK-U1"
TASK_U2_ID = "TASK-U2"
TASK_U3_ID = "TASK-U3"
TASK_DEMAND_U1 = "handoff-u1"
TASK_DEMAND_U2 = "handoff-u2"
TASK_DEMAND_U3 = "handoff-u3"

# H round (selective invalidation) adds an INDEPENDENT branch beside the
# U-chain so a source update on the U side can be shown to leave this branch
# reused. SOURCE-B is registered with its own run label / nonce; TASK-V1 is a
# model item that consumes only SOURCE-B. These ids never enter REQUIRED_ITEMS
# and never change define-task, so the E/F/G production lineage is untouched.
TASK_SOURCE_B_ID = "TASK-SOURCE-B"
TASK_V1_ID = "TASK-V1"
TASK_DEMAND_V1 = "handoff-v1"
TASK_DEMAND_GRAPH = "handoff-graph"
SOURCE_B_RUN_LABEL = "selective-baseline-source-b"

# I round (semantic sufficiency) is a distinct graph. Two INDEPENDENT structured
# sources (origin sector, destination sector) feed a single U1 that SYNTHESIZES
# a composite route key (origin>destination) which appears verbatim in neither
# source; U2 restates U1's settled structured field and U3 restates U2's, so a
# three-process restore must consume the settled structured results and keep the
# full transitive closure (U3 -> U2 -> U1 -> {ORIGIN, DEST}). These ids never
# enter REQUIRED_ITEMS and never change define-task, so the E/F/G/H lineage and
# carrier recompute semantics are untouched.
TASK_ORIGIN_ID = "TASK-ORIGIN"
TASK_DEST_ID = "TASK-DEST"
TASK_IW1_ID = "TASK-IU1"
TASK_IW2_ID = "TASK-IU2"
TASK_IW3_ID = "TASK-IU3"
TASK_DEMAND_IW1 = "handoff-i-u1"
TASK_DEMAND_IW2 = "handoff-i-u2"
TASK_DEMAND_IW3 = "handoff-i-u3"
TASK_DEMAND_ICONTRACT = "handoff-i-u1-contract"
TASK_DEMAND_ICHAIN = "handoff-i-chain"

# J round (declarative result contract) exercises exactly the semantic chain of
# the I round but under item ids that are generated at run time and therefore
# unseen by any source file. Result validation dispatches on the item's declared
# ``semantic_contract`` alone, so a brand new id needs no code change; the ids
# here are only argparse defaults for the isolated J database.
J_ITEM_SUFFIXES = ("-U1", "-U2", "-U3")
J_DEMAND_SUFFIXES = ("-u1", "-u2", "-u3", "-u1-contract", "-chain")


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


def open_loop(
    database_path: str, *, require_provenance: bool = False
) -> tuple[CarrierInformationLoop, RealPalaceConsumptionLoop]:
    loop = CarrierInformationLoop.open(
        database_path,
        provenance_policy="required" if require_provenance else "off",
    )
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
        # A real-model handoff may use its own demand on the same continuation
        # point; report that demand rather than an unrelated one.
        demand = restored["demand"]
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
    loop, source = open_loop(args.database, require_provenance=True)
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


def _task_material(
    run_label: str,
    secret_override: str | None = None,
    random_secret: bool = False,
) -> dict:
    """Deterministic task material, so the run is reproducible from its label.

    ``secret_override`` lets a controlled experiment bind a high-entropy nonce
    to the SAME task shape.  It changes only the material, not the task graph.
    ``random_secret`` generates a 128-bit nonce inside this process, so the
    nonce never appears in a command line, environment variable or temp file;
    it exists only in process memory and the source/settlement objects.
    """
    if random_secret and secret_override is not None:
        raise ValueError("use either --random-secret or a secret override, not both")
    if random_secret:
        secret = secrets.token_hex(16)
    elif secret_override is not None:
        secret = secret_override
        if not secret or len(secret) > 64 or not secret.isalnum():
            raise ValueError("secret override must be 1-64 alphanumeric characters")
    else:
        secret = "K" + hashlib.sha256(
            ("secret:" + run_label).encode("utf-8")
        ).hexdigest()[:5].upper()
    checksum = hashlib.sha256(
        ("checksum:" + run_label).encode("utf-8")
    ).hexdigest()[:4]
    log_text = "\n".join([
        "SIMIGO-SESSION-LOG-V1",
        "run=%s" % run_label,
        "site=lab-north",
        "secret=%s" % secret,
        "checksum=%s" % checksum,
    ])
    return {"secret": secret, "checksum": checksum, "log_text": log_text}


def _settlement_basis(
    source_payload: dict,
    result_value: dict,
    source_version: str,
    dependency_object_ids: dict,
    evaluated_at_utc: str,
    valid_until_utc: str,
    validity_policy: dict,
) -> dict:
    return {
        "source_payload_sha256": digest(source_payload),
        "result_value_sha256": digest(result_value),
        "source_version": source_version,
        "dependency_object_ids": dependency_object_ids,
        "evaluated_at_utc": evaluated_at_utc,
        "valid_until_utc": valid_until_utc,
        "validity_policy": validity_policy,
    }


def define_task(args: argparse.Namespace) -> None:
    """Create the isolated handoff task: registered source + two model items.

    The source is settled here with the ordinary settlement contract (its
    "computation" is deterministic registration). No execution state is
    recorded, so this registration never impersonates runtime work.
    """
    validity_policy = load_deployment_validity_policy()
    valid_until = deployment_default_validity(validity_policy)
    if args.valid_until and args.valid_until != valid_until:
        raise ValueError("command validity conflicts with deployment validity policy")
    parse_utc(args.evaluated_at)
    secret_override = getattr(args, "secret", None)
    secret_file = getattr(args, "secret_file", None)
    random_secret = bool(getattr(args, "random_secret", False))
    if random_secret and (secret_override is not None or secret_file):
        raise ValueError(
            "use either --random-secret, --secret or --secret-file, not a combination"
        )
    if secret_file:
        if secret_override is not None:
            raise ValueError("use either --secret or --secret-file, not both")
        secret_override = Path(secret_file).read_text(encoding="utf-8").strip()
    material = _task_material(args.run_label, secret_override, random_secret)
    log_text = material["log_text"]
    source_version = "v1:%s" % args.run_label

    loop = CarrierInformationLoop.create(args.database)
    try:
        source_payload = {
            "schema_id": "SIMIGO-HANDOFF-SESSION-LOG-V1",
            "run_label": args.run_label,
            "site": "lab-north",
            "log_text": log_text,
        }
        source = loop.put_source(
            CONTINUATION_POINT,
            TASK_SOURCE_ID,
            "session-log",
            source_version,
            source_payload,
            valid_until_utc=valid_until,
            validity_policy=validity_policy,
        )
        registration_value = {
            "log_text_sha256": digest(log_text),
            "secret_sha256": digest(material["secret"]),
            "checksum": material["checksum"],
            "site": "lab-north",
            "run_label": args.run_label,
        }
        registration_basis = _settlement_basis(
            source_payload,
            registration_value,
            source_version,
            {},
            args.evaluated_at,
            valid_until,
            validity_policy,
        )
        registration_result = {"value": registration_value, **registration_basis}
        registration = loop.settle(
            "handoff-registration",
            TASK_SOURCE_ID,
            registration_result,
            registration_basis,
            (
                loop.settlement_provenance_for(
                    TASK_SOURCE_ID, registration_result, {}, {}
                )
                if loop.provenance_policy != "off"
                else None
            ),
        )

        seed_text = "\n".join([
            "SIMIGO-REAL-MODEL-HANDOFF-V1",
            "You are executing step 1 of a two-step task.",
            "SESSION LOG:",
            log_text,
            "",
            "Read the session log and extract the value of secret.",
            "Reply with exactly one line and nothing else: SECRET=<secret>",
            "Answer:",
        ])
        u1_payload = {
            "schema_id": "SIMIGO-HANDOFF-STEP-V1",
            "step": 1,
            "model_task": "extract_secret",
            "answer_format": "SECRET=<secret>",
            "prompt_seed": seed_text,
            "next_input": " ",
            "source_item_id": TASK_SOURCE_ID,
            # Declared result semantics for the production result gate. This is
            # the item's own declaration, not a rule selected by its id: the
            # extracted SECRET must commit to the settled source digest.
            # No extraction view is derived here, so the already-shipped native
            # producer behaviour for this lineage is unchanged.
            "semantic_contract": {
                "schema_version": CONTRACT_VERSION,
                "fields": {
                    "secret": {"pattern": "SECRET=([A-Za-z0-9]+)",
                               "capture_group": 1, "type": "string",
                               "match_policy": "first"},
                },
                "bindings": [
                    {"name": "secret_commitment", "source": "dependency_field",
                     "field": "secret_sha256"},
                ],
                "constraints": [
                    {"kind": "digest_equals_binding", "field": "secret",
                     "binding": "secret_commitment"},
                ],
            },
        }
        u1 = loop.put_source(
            CONTINUATION_POINT,
            TASK_U1_ID,
            "model-task",
            "v1",
            u1_payload,
            dependencies=[TASK_SOURCE_ID],
            valid_until_utc=valid_until,
            validity_policy=validity_policy,
        )

        u2_payload = {
            "schema_id": "SIMIGO-HANDOFF-STEP-V1",
            "step": 2,
            "model_task": "compose_answer",
            "answer_format": "ANSWER=<secret>-<checksum>",
            "next_input_template": (
                "\nStep 2: the secret from step 1 is {secret}. "
                "The checksum from the session log is {checksum}.\n"
                "Reply with exactly one line and nothing else: "
                "ANSWER=<secret>-<checksum>\nAnswer:"
            ),
            "source_item_ids": [TASK_SOURCE_ID, TASK_U1_ID],
            # Explicit input contract: each template placeholder names the
            # settled dependency result field it consumes. The production
            # resolver reads THIS declaration, so input construction is part of
            # the task definition instead of caller-side interpolation.
            "input_bindings": [
                {
                    "placeholder": "secret",
                    "item_id": TASK_U1_ID,
                    "result_field": "secret",
                },
                {
                    "placeholder": "checksum",
                    "item_id": TASK_SOURCE_ID,
                    "result_field": "checksum",
                },
            ],
            "semantic_contract": {
                "schema_version": CONTRACT_VERSION,
                "fields": {
                    "answer": {
                        "pattern": "(?:ANSWER=)?([A-Za-z0-9]+-[0-9a-f]{4})",
                        "capture_group": 1, "type": "string",
                        "match_policy": "first"},
                },
                "bindings": [
                    {"name": "secret", "source": "dependency_field",
                     "field": "secret"},
                    {"name": "checksum", "source": "dependency_field",
                     "field": "checksum"},
                ],
                "constraints": [
                    {"kind": "concat", "field": "answer",
                     "parts": ["secret", "checksum"], "separator": "-"},
                ],
            },
        }
        u2 = loop.put_source(
            CONTINUATION_POINT,
            TASK_U2_ID,
            "model-task",
            "v1",
            u2_payload,
            dependencies=[TASK_SOURCE_ID, TASK_U1_ID],
            valid_until_utc=valid_until,
            validity_policy=validity_policy,
        )

        demand_u1 = loop.define_demand(
            TASK_DEMAND_U1,
            continuation_point=CONTINUATION_POINT,
            pending_obligations=["execute step 1 on the real model"],
            continuation_conditions=[
                "registered source is reusable and the model result is settled"
            ],
            required_item_ids=[TASK_U1_ID],
        )
        demand_u2 = loop.define_demand(
            TASK_DEMAND_U2,
            continuation_point=CONTINUATION_POINT,
            pending_obligations=["execute step 2 on the real model"],
            continuation_conditions=[
                "step 1 settlement is reused and step 2 is settled"
            ],
            required_item_ids=[TASK_U2_ID],
        )
        loop.commit()
        emit({
            "ok": True,
            "command": "define-task",
            "run_label": args.run_label,
            "continuation_point": CONTINUATION_POINT,
            "source": source,
            "registration_settlement_object_id": registration["object_id"],
            "u1": u1,
            "u2": u2,
            "demand_u1": demand_u1,
            "demand_u2": demand_u2,
            "log_text_sha256": digest(log_text),
            "secret_sha256": digest(material["secret"]),
            "checksum": material["checksum"],
            "random_secret": random_secret,
            "nonce_bits": 128 if random_secret else None,
        })
    finally:
        loop.close()


def _register_source(
    loop: "CarrierInformationLoop",
    item_id: str,
    run_label: str,
    secret_override: str,
    evaluated_at: str,
    valid_until: str,
    validity_policy: dict,
    advancement: str,
) -> dict:
    """Register a session-log source and settle its deterministic registration.

    This mirrors the SOURCE registration inside ``define_task`` verbatim so the
    H-round graph reuses the SAME provenance/signature machinery, only with a
    second, independent source id. It records no execution state, so a
    registration never impersonates runtime work.
    """
    material = _task_material(run_label, secret_override, False)
    log_text = material["log_text"]
    source_version = "v1:%s" % run_label
    source_payload = {
        "schema_id": "SIMIGO-HANDOFF-SESSION-LOG-V1",
        "run_label": run_label,
        "site": "lab-north",
        "log_text": log_text,
    }
    source = loop.put_source(
        CONTINUATION_POINT, item_id, "session-log", source_version,
        source_payload, valid_until_utc=valid_until, validity_policy=validity_policy,
    )
    registration_value = {
        "log_text": log_text,
        "log_text_sha256": digest(log_text),
        "secret_sha256": digest(material["secret"]),
        "checksum": material["checksum"],
        "site": "lab-north",
        "run_label": run_label,
    }
    basis = _settlement_basis(
        source_payload, registration_value, source_version, {}, evaluated_at,
        valid_until, validity_policy,
    )
    result = {"value": registration_value, **basis}
    provenance = (
        loop.settlement_provenance_for(item_id, result, {}, {})
        if loop.provenance_policy != "off" else None
    )
    registration = loop.settle(advancement, item_id, result, basis, provenance)
    return {
        "source": source,
        "registration": registration,
        "material": material,
        "source_payload": source_payload,
        "source_version": source_version,
    }


def define_h_graph(args: argparse.Namespace) -> None:
    """Build the H-round two-branch dependency graph in an isolated database.

        SOURCE-A -> U1 -> U2 -> U3
        SOURCE-B -> V1   (independent branch)

    Only the graph, sources and demands are created here; the four model items
    are settled by the ordinary ``execute-with-model-result`` path (real model) or
    a model-free fixture value that still satisfies the item's declared result
    contract. A ``handoff-graph`` demand pulls both branches so a single probe
    reports the full REUSE-vs-COMPUTE action set for the affected closure and the
    independent branch together.

    Every model item here declares its own ``semantic_contract``; the frozen
    native binary's ``result_contract`` field list is DERIVED from that
    declaration, so the extraction the producer performs and the semantics the
    production gate validates can never drift apart.
    """
    validity_policy = load_deployment_validity_policy()
    valid_until = deployment_default_validity(validity_policy)
    if args.valid_until and args.valid_until != valid_until:
        raise ValueError("command validity conflicts with deployment validity policy")
    parse_utc(args.evaluated_at)
    if not args.secret_a or not args.secret_b:
        raise ValueError("define-h-graph requires --secret-a and --secret-b")
    loop = CarrierInformationLoop.create(args.database)
    try:
        reg_a = _register_source(
            loop, TASK_SOURCE_ID, args.run_label, args.secret_a, args.evaluated_at,
            valid_until, validity_policy, "handoff-registration",
        )
        reg_b = _register_source(
            loop, TASK_SOURCE_B_ID, SOURCE_B_RUN_LABEL, args.secret_b,
            args.evaluated_at, valid_until, validity_policy,
            "handoff-registration-b",
        )
        log_text_a = reg_a["material"]["log_text"]
        log_text_b = reg_b["material"]["log_text"]

        u1_payload = {
            "schema_id": "SIMIGO-HANDOFF-STEP-V1",
            "step": 1,
            "model_task": "extract_secret",
            "answer_format": "SECRET=<secret>",
            # The model input is the SOURCE-A settled log_text, admitted through
            # the ordinary dependency-closure path. When SOURCE-A is legitimately
            # updated the new log_text is what the model reads, so this item is
            # genuinely recomputed from the changed upstream value.
            "next_input_template": (
                "\nSESSION LOG:\n{log_text}\n\n"
                "The session log contains exactly one line of the form "
                "'secret=<value>', where <value> is a 16-character lowercase "
                "hex string.\n"
                "Copy that value exactly. Do not compute, shorten or reformat it.\n"
                "Reply with exactly one line and nothing else: SECRET=<value>\n"
                "Answer:"
            ),
            "input_bindings": [
                {"placeholder": "log_text", "item_id": TASK_SOURCE_ID,
                 "result_field": "log_text"},
            ],
            "semantic_contract": {
                "schema_version": CONTRACT_VERSION,
                "fields": {
                    "secret": {"pattern": "SECRET=([A-Za-z0-9]+)",
                               "capture_group": 1, "type": "string",
                               "match_policy": "first"},
                },
                "bindings": [
                    {"name": "secret_commitment", "source": "dependency_field",
                     "field": "secret_sha256"},
                ],
                "constraints": [
                    {"kind": "digest_equals_binding", "field": "secret",
                     "binding": "secret_commitment"},
                ],
            },
            "source_item_ids": [TASK_SOURCE_ID],
        }
        u1_payload["result_contract"] = derive_extraction_view(
            u1_payload["semantic_contract"])
        u1 = loop.put_source(
            CONTINUATION_POINT, TASK_U1_ID, "model-task", "v1", u1_payload,
            dependencies=[TASK_SOURCE_ID], valid_until_utc=valid_until,
            validity_policy=validity_policy,
        )
        u2_payload = {
            "schema_id": "SIMIGO-HANDOFF-STEP-V1",
            "step": 2,
            "model_task": "compose_answer",
            "answer_format": "ANSWER=<secret>-<checksum>",
            "next_input_template": (
                "\nStep 2: the secret from step 1 is {secret}. "
                "The checksum from the session log is {checksum}.\n"
                "Reply with exactly one line and nothing else: "
                "ANSWER=<secret>-<checksum>\nAnswer:"
            ),
            "source_item_ids": [TASK_SOURCE_ID, TASK_U1_ID],
            "input_bindings": [
                {"placeholder": "secret", "item_id": TASK_U1_ID,
                 "result_field": "secret"},
                {"placeholder": "checksum", "item_id": TASK_SOURCE_ID,
                 "result_field": "checksum"},
            ],
            "semantic_contract": {
                "schema_version": CONTRACT_VERSION,
                "fields": {
                    "answer": {
                        "pattern": "(?:ANSWER=)?([A-Za-z0-9]+-[0-9a-f]{4})",
                        "capture_group": 1, "type": "string",
                        "match_policy": "first"},
                },
                "bindings": [
                    {"name": "secret", "source": "dependency_field",
                     "field": "secret"},
                    {"name": "checksum", "source": "dependency_field",
                     "field": "checksum"},
                ],
                "constraints": [
                    {"kind": "concat", "field": "answer",
                     "parts": ["secret", "checksum"], "separator": "-"},
                ],
            },
        }
        u2_payload["result_contract"] = derive_extraction_view(
            u2_payload["semantic_contract"])
        u2 = loop.put_source(
            CONTINUATION_POINT, TASK_U2_ID, "model-task", "v1", u2_payload,
            dependencies=[TASK_SOURCE_ID, TASK_U1_ID], valid_until_utc=valid_until,
            validity_policy=validity_policy,
        )
        u3_payload = {
            "schema_id": "SIMIGO-HANDOFF-STEP-V1",
            "step": 3,
            "model_task": "derive_stamp",
            "answer_format": "STAMP=<secret>",
            "next_input_template": (
                "\nStep 3: the composed answer from step 2 is {answer}.\n"
                "Reply with exactly one line and nothing else: "
                "STAMP=<the 16 hex characters before the hyphen>\nAnswer:"
            ),
            "input_bindings": [
                {"placeholder": "answer", "item_id": TASK_U2_ID,
                 "result_field": "answer"},
            ],
            "semantic_contract": {
                "schema_version": CONTRACT_VERSION,
                "fields": {
                    "stamp": {"pattern": "STAMP=([A-Za-z0-9]+)",
                              "capture_group": 1, "type": "string",
                              "match_policy": "first"},
                },
                # U3 consumes only its DIRECT dependency U2, but admitting U2
                # through the ordinary reuse decision recursively resolves U2's
                # own closure (SOURCE + U1), so the stamp must be derivable from
                # the settled U2 answer and can never be settled against an
                # unverified or missing closure.
                "bindings": [
                    {"name": "answer", "source": "dependency_field",
                     "field": "answer"},
                ],
                "constraints": [
                    {"kind": "equals_binding_segment", "field": "stamp",
                     "binding": "answer", "separator": "-", "segment": 0},
                ],
            },
            "source_item_ids": [TASK_U2_ID],
        }
        u3_payload["result_contract"] = derive_extraction_view(
            u3_payload["semantic_contract"])
        u3 = loop.put_source(
            CONTINUATION_POINT, TASK_U3_ID, "model-task", "v1", u3_payload,
            dependencies=[TASK_U2_ID], valid_until_utc=valid_until,
            validity_policy=validity_policy,
        )
        v1_payload = {
            "schema_id": "SIMIGO-HANDOFF-STEP-V1",
            "step": "B1",
            "model_task": "read_source_b_checksum",
            "answer_format": "VCHECKSUM=<checksum>",
            # Independent branch: V1 consumes ONLY SOURCE-B's settled log_text.
            # It never references SOURCE-A or any U-chain item, so it stays a
            # valid reuse target when SOURCE-A changes. It echoes SOURCE-B's own
            # checksum (a source-specific 4-hex value derived from SOURCE-B's
            # run label), which still proves V1 genuinely reads SOURCE-B without
            # depending on the U chain, while staying within the real model's
            # reliable short-copy band (verbatim 16-hex transcription is not
            # reliably completable by the model).
            "next_input_template": (
                "\nBRANCH-B SESSION LOG:\n{log_text}\n\n"
                "The session log contains exactly one line of the form "
                "'checksum=<value>', where <value> is a 4-character lowercase "
                "hex string.\n"
                "Copy that value exactly. Do not compute, shorten or reformat "
                "it, and do not use the secret line.\n"
                "Reply with exactly one line and nothing else: "
                "VCHECKSUM=<value>\nAnswer:"
            ),
            "input_bindings": [
                {"placeholder": "log_text", "item_id": TASK_SOURCE_B_ID,
                 "result_field": "log_text"},
            ],
            "semantic_contract": {
                "schema_version": CONTRACT_VERSION,
                "fields": {
                    "vcheck": {"pattern": "(?:VCHECKSUM=)?([0-9a-f]{4})",
                               "capture_group": 1, "type": "string",
                               "match_policy": "first"},
                },
                # Independent branch: V1 echoes the checksum of the single
                # admitted dependency that provides it (SOURCE-B), verified
                # against that settled commitment, so V1 can never be settled
                # against the SOURCE-A / U-chain closure.
                "bindings": [
                    {"name": "checksum", "source": "dependency_field",
                     "field": "checksum"},
                ],
                "constraints": [
                    {"kind": "equals_binding", "field": "vcheck",
                     "binding": "checksum"},
                ],
            },
            "source_item_ids": [TASK_SOURCE_B_ID],
        }
        v1_payload["result_contract"] = derive_extraction_view(
            v1_payload["semantic_contract"])
        v1 = loop.put_source(
            CONTINUATION_POINT, TASK_V1_ID, "model-task", "v1", v1_payload,
            dependencies=[TASK_SOURCE_B_ID], valid_until_utc=valid_until,
            validity_policy=validity_policy,
        )
        demand_u1 = loop.define_demand(
            TASK_DEMAND_U1, continuation_point=CONTINUATION_POINT,
            pending_obligations=["execute step 1 on the real model"],
            continuation_conditions=["SOURCE-A reusable and U1 settled"],
            required_item_ids=[TASK_U1_ID],
        )
        demand_u2 = loop.define_demand(
            TASK_DEMAND_U2, continuation_point=CONTINUATION_POINT,
            pending_obligations=["execute step 2 on the real model"],
            continuation_conditions=["U1 reused and U2 settled"],
            required_item_ids=[TASK_U2_ID],
        )
        demand_u3 = loop.define_demand(
            TASK_DEMAND_U3, continuation_point=CONTINUATION_POINT,
            pending_obligations=["execute step 3 on the real model"],
            continuation_conditions=["U2 reused (with its U1 closure) and U3 settled"],
            required_item_ids=[TASK_U3_ID],
        )
        demand_v1 = loop.define_demand(
            TASK_DEMAND_V1, continuation_point=CONTINUATION_POINT,
            pending_obligations=["execute branch V1 on the real model"],
            continuation_conditions=["SOURCE-B reusable and V1 settled"],
            required_item_ids=[TASK_V1_ID],
        )
        demand_graph = loop.define_demand(
            TASK_DEMAND_GRAPH, continuation_point=CONTINUATION_POINT,
            pending_obligations=["bring U3 and V1 up to date over both branches"],
            continuation_conditions=[
                "recompute the affected closure and reuse the independent branch"
            ],
            required_item_ids=[TASK_U3_ID, TASK_V1_ID],
        )
        loop.commit()
        emit({
            "ok": True,
            "command": "define-h-graph",
            "run_label": args.run_label,
            "continuation_point": CONTINUATION_POINT,
            "source_a": TASK_SOURCE_ID,
            "source_b": TASK_SOURCE_B_ID,
            "source_a_registration_object_id": reg_a["registration"]["object_id"],
            "source_b_registration_object_id": reg_b["registration"]["object_id"],
            "secret_a_sha256": digest(args.secret_a),
            "secret_b_sha256": digest(args.secret_b),
            "checksum_a": reg_a["material"]["checksum"],
            "checksum_b": reg_b["material"]["checksum"],
            "u1": u1, "u2": u2, "u3": u3, "v1": v1,
            "demand_u1": demand_u1, "demand_u2": demand_u2,
            "demand_u3": demand_u3, "demand_v1": demand_v1,
            "demand_graph": demand_graph,
            "graph": {
                "affected_chain": [TASK_SOURCE_ID, TASK_U1_ID, TASK_U2_ID, TASK_U3_ID],
                "unaffected_branch": [TASK_SOURCE_B_ID, TASK_V1_ID],
            },
        })
    finally:
        loop.close()


def h_source_update(args: argparse.Namespace) -> None:
    """Apply a legitimate upstream SOURCE-A change through the supported path.

    It changes SOURCE-A's session-log payload (a new secret, hence a new
    content/version identity) via ``update_source`` and then re-settles the
    registration so SOURCE-A itself remains a lawful settled dependency bound to
    the new version. The SOURCE-A settlement gets a new object id, so U1's
    cached closure binding no longer matches and U1 -> U2 -> U3 become stale in
    topological order, while V1 (whose SOURCE-B closure is untouched) stays
    reusable. It does not touch SOURCE-B and does not alter carrier recompute
    semantics.
    """
    validity_policy = load_deployment_validity_policy()
    valid_until = deployment_default_validity(validity_policy)
    parse_utc(args.evaluated_at)
    if not args.new_secret_a:
        raise ValueError("h-source-update requires --new-secret-a")
    loop = CarrierInformationLoop.open(args.database, provenance_policy="required")
    try:
        item = loop.current_item(TASK_SOURCE_ID)
        if item is None:
            raise ValueError("unknown item: %s" % TASK_SOURCE_ID)
        material = _task_material(args.run_label, args.new_secret_a, False)
        log_text = material["log_text"]
        source_version = "v2:%s" % args.run_label
        source_payload = {
            "schema_id": "SIMIGO-HANDOFF-SESSION-LOG-V1",
            "run_label": args.run_label,
            "site": "lab-north",
            "log_text": log_text,
        }
        update = loop.update_source(
            TASK_SOURCE_ID, source_version, source_payload,
            "authorized H-round selective-invalidation source revision",
            valid_until_utc=valid_until, validity_policy=validity_policy,
        )
        registration_value = {
            "log_text": log_text,
            "log_text_sha256": digest(log_text),
            "secret_sha256": digest(args.new_secret_a),
            "checksum": material["checksum"],
            "site": "lab-north",
            "run_label": args.run_label,
        }
        basis = _settlement_basis(
            source_payload, registration_value, source_version, {},
            args.evaluated_at, valid_until, validity_policy,
        )
        result = {"value": registration_value, **basis}
        provenance = (
            loop.settlement_provenance_for(TASK_SOURCE_ID, result, {}, {})
            if loop.provenance_policy != "off" else None
        )
        registration = loop.settle(
            "handoff-registration", TASK_SOURCE_ID, result, basis, provenance,
        )
        source_b = loop.current_settlement(TASK_SOURCE_B_ID)
        loop.commit()
        emit({
            "ok": True,
            "command": "h-source-update",
            "source_a_update": update,
            "source_a_registration_object_id": registration["object_id"],
            "source_a_new_secret_sha256": digest(args.new_secret_a),
            "source_a_checksum": material["checksum"],
            "source_b_settlement_unchanged_object_id": (
                source_b or {}).get("_object_id"),
        })
    finally:
        loop.close()


def _register_route_source(
    loop: "CarrierInformationLoop",
    item_id: str,
    role: str,
    sector: str,
    priority: str,
    run_label: str,
    evaluated_at: str,
    valid_until: str,
    validity_policy: dict,
    advancement: str,
) -> dict:
    """Register one independent structured route source and settle it.

    Mirrors the H-round ``_register_source`` provenance/signature machinery but
    the settled registration value carries a genuine structured SEMANTIC field
    (a sector code and a route priority) rather than an opaque nonce. Each of the
    two sources is its own item id with its own run label, so neither sector
    value appears in the other and neither is derived from the other's text.
    """
    if not re.fullmatch(r"[A-Z]{2,}", sector):
        raise ValueError("route sector must be 2+ uppercase letters")
    if not re.fullmatch(r"[1-9][0-9]?", priority):
        raise ValueError("route priority must be a 1-2 digit integer string")
    authority_text = "\n".join([
        "SIMIGO-I-ROUTE-AUTHORITY-V1",
        "run=%s" % run_label,
        "role=%s" % role,
        "sector=%s" % sector,
        "priority=%s" % priority,
    ])
    source_version = "v1:%s:%s" % (role, run_label)
    source_payload = {
        "schema_id": "SIMIGO-I-ROUTE-SOURCE-V1",
        "run_label": run_label,
        "role": role,
        "sector": sector,
        "priority": priority,
        "authority_text": authority_text,
    }
    source = loop.put_source(
        CONTINUATION_POINT, item_id, "route-authority", source_version,
        source_payload, valid_until_utc=valid_until, validity_policy=validity_policy,
    )
    registration_value = {
        "sector": sector,
        "priority": priority,
        "role": role,
        "authority_text": authority_text,
        "authority_text_sha256": digest(authority_text),
        "run_label": run_label,
    }
    # Expose the sector under its semantic role name so downstream structured
    # consumers reference origin_code / destination_code directly (SOURCE-A is
    # the origin, SOURCE-B is the destination).
    if role == "origin":
        registration_value["origin_code"] = sector
    elif role == "destination":
        registration_value["destination_code"] = sector
    basis = _settlement_basis(
        source_payload, registration_value, source_version, {}, evaluated_at,
        valid_until, validity_policy,
    )
    result = {"value": registration_value, **basis}
    provenance = (
        loop.settlement_provenance_for(item_id, result, {}, {})
        if loop.provenance_policy != "off" else None
    )
    registration = loop.settle(advancement, item_id, result, basis, provenance)
    return {
        "source": source,
        "registration": registration,
        "registration_value": registration_value,
        "source_payload": source_payload,
        "source_version": source_version,
    }


def route_synthesis_contract(origin_binding: str, destination_binding: str,
                             destination_priority_binding: str) -> dict:
    """Declarative contract for a step that synthesizes ``origin>destination``.

    The binding arguments are the step's OWN declared input-placeholder names;
    no task item id appears anywhere in the contract, so the same declaration
    validates a task created at run time under a name no source file has ever
    seen. Semantics: both sector fields must equal their admitted source
    bindings, the priority must equal the destination's admitted priority, and
    the route key must be the concatenation of the two extracted sectors -- a
    composite that appears verbatim in neither source.
    """
    return {
        "schema_version": CONTRACT_VERSION,
        "fields": {
            "origin_code": {"pattern": "ORIGIN=([A-Z]+)", "capture_group": 1,
                            "type": "string", "match_policy": "first"},
            "destination_code": {"pattern": "DEST=([A-Z]+)", "capture_group": 1,
                                 "type": "string", "match_policy": "first"},
            "route_key": {"pattern": "ROUTE=([A-Z]+>[A-Z]+)",
                          "capture_group": 1, "type": "string",
                          "match_policy": "first"},
            "priority": {"pattern": "PRIORITY=([0-9]+)", "capture_group": 1,
                         "type": "string", "match_policy": "first"},
        },
        "bindings": [
            {"name": origin_binding, "source": "input_binding",
             "placeholder": origin_binding},
            {"name": destination_binding, "source": "input_binding",
             "placeholder": destination_binding},
            {"name": destination_priority_binding, "source": "input_binding",
             "placeholder": destination_priority_binding},
        ],
        "constraints": [
            {"kind": "equals_binding", "field": "origin_code",
             "binding": origin_binding},
            {"kind": "equals_binding", "field": "destination_code",
             "binding": destination_binding},
            {"kind": "equals_binding", "field": "priority",
             "binding": destination_priority_binding},
            {"kind": "concat", "field": "route_key",
             "parts": ["origin_code", "destination_code"], "separator": ">"},
        ],
    }


def route_carry_forward_contract(route_binding: str, answer_prefix: str) -> dict:
    """Declarative contract for a step that restates one settled route field.

    The single declared field must reproduce the route bound from the item's own
    admitted upstream binding, which is the semantic-sufficiency check: the
    downstream step needs the completed computation, not the upstream context.
    """
    return {
        "schema_version": CONTRACT_VERSION,
        "fields": {
            "route_key": {"pattern": "(?:%s=)?([A-Z]+>[A-Z]+)" % answer_prefix,
                          "capture_group": 1, "type": "string",
                          "match_policy": "first"},
        },
        "bindings": [
            {"name": route_binding, "source": "input_binding",
             "placeholder": route_binding},
        ],
        "constraints": [
            {"kind": "equals_binding", "field": "route_key",
             "binding": route_binding},
        ],
    }


def define_i_graph(args: argparse.Namespace) -> None:
    """Build the I-round semantic-sufficiency graph in an isolated database.

        TASK-ORIGIN ---\\
                        >-- TASK-IU1 -> TASK-IU2 -> TASK-IU3
        TASK-DEST   ---/

    IU1 SYNTHESIZES a composite route key (origin>destination) from the two
    independent settled sources; IU2 restates IU1's settled structured field;
    IU3 restates IU2's. The model items themselves are settled by the ordinary
    ``execute-with-model-result`` path (real model) or a model-free fixture value
    that still satisfies the items' declared result contracts. A
    ``handoff-i-chain`` demand pulls the whole closure so a single model-free
    probe reports the reuse-vs-recompute action set for the full transitive
    closure.
    """
    validity_policy = load_deployment_validity_policy()
    valid_until = deployment_default_validity(validity_policy)
    if args.valid_until and args.valid_until != valid_until:
        raise ValueError("command validity conflicts with deployment validity policy")
    parse_utc(args.evaluated_at)
    for name in (args.sector_origin, args.sector_dest):
        if not name:
            raise ValueError("define-i-graph requires --sector-origin and --sector-dest")
    if args.sector_origin == args.sector_dest:
        raise ValueError("origin and destination sectors must be distinct")
    loop = CarrierInformationLoop.create(args.database)
    try:
        reg_origin = _register_route_source(
            loop, TASK_ORIGIN_ID, "origin", args.sector_origin,
            args.priority_origin, args.run_label, args.evaluated_at, valid_until,
            validity_policy, "handoff-registration-origin",
        )
        reg_dest = _register_route_source(
            loop, TASK_DEST_ID, "destination", args.sector_dest,
            args.priority_dest, args.run_label, args.evaluated_at, valid_until,
            validity_policy, "handoff-registration-dest",
        )
        expected_route = "%s>%s" % (args.sector_origin, args.sector_dest)

        iw1_payload = {
            "schema_id": "SIMIGO-I-STEP-V1",
            "step": 1,
            "model_task": "synthesize_route",
            "answer_format": "ORIGIN/DEST/ROUTE/PRIORITY",
            "next_input_template": (
                "\nThe origin sector is {origin} (route priority "
                "{origin_priority}).\nThe destination sector is {destination} "
                "(route priority {destination_priority}).\nA route key is "
                "written as the origin sector, a single '>' character, then the "
                "destination sector.\nThe route inherits the destination's "
                "priority.\nReply with exactly four lines and nothing "
                "else:\nORIGIN=<origin sector>\nDEST=<destination sector>\n"
                "ROUTE=<origin>><destination>\nPRIORITY=<destination priority>\n"
                "Answer:"
            ),
            "input_bindings": [
                {"placeholder": "origin", "item_id": TASK_ORIGIN_ID,
                 "result_field": "origin_code"},
                {"placeholder": "origin_priority", "item_id": TASK_ORIGIN_ID,
                 "result_field": "priority"},
                {"placeholder": "destination", "item_id": TASK_DEST_ID,
                 "result_field": "destination_code"},
                {"placeholder": "destination_priority", "item_id": TASK_DEST_ID,
                 "result_field": "priority"},
            ],
            "semantic_contract": route_synthesis_contract(
                origin_binding="origin",
                destination_binding="destination",
                destination_priority_binding="destination_priority"),
            "source_item_ids": [TASK_ORIGIN_ID, TASK_DEST_ID],
        }
        iw1_payload["result_contract"] = derive_extraction_view(
            iw1_payload["semantic_contract"])
        iw1 = loop.put_source(
            CONTINUATION_POINT, TASK_IW1_ID, "model-task", "v1", iw1_payload,
            dependencies=[TASK_ORIGIN_ID, TASK_DEST_ID], valid_until_utc=valid_until,
            validity_policy=validity_policy,
        )
        iw2_payload = {
            "schema_id": "SIMIGO-I-STEP-V1",
            "step": 2,
            "model_task": "carry_forward_route",
            "answer_format": "FLOW",
            "next_input_template": (
                "\nStep 1 established the route: {route_key} (priority "
                "{priority}).\nRestate that settled route exactly, unchanged, "
                "on one line in the form FLOW=<route> and add nothing else."
                "\nAnswer:"
            ),
            "input_bindings": [
                {"placeholder": "route_key", "item_id": TASK_IW1_ID,
                 "result_field": "route_key"},
                {"placeholder": "priority", "item_id": TASK_IW1_ID,
                 "result_field": "priority"},
            ],
            "semantic_contract": route_carry_forward_contract(
                route_binding="route_key", answer_prefix="FLOW"),
            "source_item_ids": [TASK_IW1_ID],
        }
        iw2_payload["result_contract"] = derive_extraction_view(
            iw2_payload["semantic_contract"])
        iw2 = loop.put_source(
            CONTINUATION_POINT, TASK_IW2_ID, "model-task", "v1", iw2_payload,
            dependencies=[TASK_IW1_ID], valid_until_utc=valid_until,
            validity_policy=validity_policy,
        )
        iw3_payload = {
            "schema_id": "SIMIGO-I-STEP-V1",
            "step": 3,
            "model_task": "confirm_carried_route",
            "answer_format": "CONFIRMED",
            "next_input_template": (
                "\nStep 2 carried the route forward as: {route_key}.\nRestate "
                "that settled route exactly, unchanged, on one line in the "
                "form CONFIRMED=<route> and add nothing else.\nAnswer:"
            ),
            "input_bindings": [
                {"placeholder": "route_key", "item_id": TASK_IW2_ID,
                 "result_field": "route_key"},
            ],
            "semantic_contract": route_carry_forward_contract(
                route_binding="route_key", answer_prefix="CONFIRMED"),
            "source_item_ids": [TASK_IW2_ID],
        }
        iw3_payload["result_contract"] = derive_extraction_view(
            iw3_payload["semantic_contract"])
        iw3 = loop.put_source(
            CONTINUATION_POINT, TASK_IW3_ID, "model-task", "v1", iw3_payload,
            dependencies=[TASK_IW2_ID], valid_until_utc=valid_until,
            validity_policy=validity_policy,
        )
        demand_iw1 = loop.define_demand(
            TASK_DEMAND_IW1, continuation_point=CONTINUATION_POINT,
            pending_obligations=["synthesize the route key from both sources"],
            continuation_conditions=["both sources reusable and IU1 settled"],
            required_item_ids=[TASK_IW1_ID],
        )
        demand_iw2 = loop.define_demand(
            TASK_DEMAND_IW2, continuation_point=CONTINUATION_POINT,
            pending_obligations=["derive the reverse route from IU1's settled route"],
            continuation_conditions=["IU1 reused and IU2 settled"],
            required_item_ids=[TASK_IW2_ID],
        )
        demand_iw3 = loop.define_demand(
            TASK_DEMAND_IW3, continuation_point=CONTINUATION_POINT,
            pending_obligations=["confirm the round trip from IU2's settled route"],
            continuation_conditions=["IU2 reused with its closure and IU3 settled"],
            required_item_ids=[TASK_IW3_ID],
        )
        demand_icontract = loop.define_demand(
            TASK_DEMAND_ICONTRACT, continuation_point=CONTINUATION_POINT,
            pending_obligations=["validate a U1 result against the field contract"],
            continuation_conditions=["IU1 settled with the full structured contract"],
            required_item_ids=[TASK_IW1_ID],
        )
        demand_ichain = loop.define_demand(
            TASK_DEMAND_ICHAIN, continuation_point=CONTINUATION_POINT,
            pending_obligations=["bring IU3 up to date over the full closure"],
            continuation_conditions=[
                "restore and reuse the settled IU1/IU2 closure, recompute only IU3"
            ],
            required_item_ids=[TASK_IW3_ID],
        )
        loop.commit()
        emit({
            "ok": True,
            "command": "define-i-graph",
            "run_label": args.run_label,
            "continuation_point": CONTINUATION_POINT,
            "origin": TASK_ORIGIN_ID,
            "dest": TASK_DEST_ID,
            "origin_sector": args.sector_origin,
            "dest_sector": args.sector_dest,
            "origin_priority": args.priority_origin,
            "dest_priority": args.priority_dest,
            "expected_route_key": expected_route,
            "expected_carried_route": expected_route,
            "origin_registration_object_id": reg_origin["registration"]["object_id"],
            "dest_registration_object_id": reg_dest["registration"]["object_id"],
            "iw1": iw1, "iw2": iw2, "iw3": iw3,
            "demand_iw1": demand_iw1, "demand_iw2": demand_iw2,
            "demand_iw3": demand_iw3, "demand_icontract": demand_icontract,
            "demand_ichain": demand_ichain,
            "graph": {
                "sources": [TASK_ORIGIN_ID, TASK_DEST_ID],
                "structured_chain": [TASK_IW1_ID, TASK_IW2_ID, TASK_IW3_ID],
                "transitive_closure_of_iw3": [
                    TASK_ORIGIN_ID, TASK_DEST_ID, TASK_IW1_ID, TASK_IW2_ID,
                    TASK_IW3_ID,
                ],
            },
        })
    finally:
        loop.close()


def define_j_graph(args: argparse.Namespace) -> None:
    """Build the J-round graph on item ids generated for this run only.

        <prefix>-ORIGIN ---\\
                           >-- <prefix>-U1 -> <prefix>-U2 -> <prefix>-U3
        <prefix>-DEST   ---/

    ``--run-token`` is supplied by the driver at run time, so every item and
    demand id in this graph is a name no source file has ever mentioned. The
    graph is otherwise identical in shape to the I round, and the three model
    items declare the same routing contracts built by
    ``route_synthesis_contract`` / ``route_carry_forward_contract``. Nothing in
    the result gate keys on these ids: the only dispatch is the declared
    ``semantic_contract``, so a brand new id validates exactly like the frozen
    H/I ids.

    ``--u1-schema-version`` exists for the J3 unknown-contract control: it lets
    the graph declare a contract version this gate does not implement, so the
    fail-closed behaviour can be observed through the ordinary production
    settlement path.

    ``--u1-constraint-kind`` exists for the K-round native counterfactual (N2):
    it replaces U1's composite (``concat``) constraint with a constraint kind the
    Python production gate implements but the NATIVE result-contract engine does
    not (for example ``equals_binding_segment``). The native pre-settlement gate
    must then refuse fail-closed with CONTRACT_UNKNOWN_CONSTRAINT, so no
    settlement object and no signature are created -- even though the Python
    validator, if it were reached, would evaluate that kind. The empty default
    leaves the native-supported ``concat`` in place, so ordinary runs are
    unchanged. (``digest_equals_binding`` is no longer a valid example: the
    native engine now implements it, so it would be accepted rather than refused.)
    """
    validity_policy = load_deployment_validity_policy()
    valid_until = deployment_default_validity(validity_policy)
    if args.valid_until and args.valid_until != valid_until:
        raise ValueError("command validity conflicts with deployment validity policy")
    parse_utc(args.evaluated_at)
    if not args.run_token:
        raise ValueError("define-j-graph requires --run-token")
    if not args.sector_origin or not args.sector_dest:
        raise ValueError("define-j-graph requires --sector-origin and --sector-dest")
    if args.sector_origin == args.sector_dest:
        raise ValueError("origin and destination sectors must be distinct")
    prefix = "J-%s" % args.run_token
    origin_id, dest_id = "%s-ORIGIN" % prefix, "%s-DEST" % prefix
    u1_id, u2_id, u3_id = ("%s-U1" % prefix, "%s-U2" % prefix,
                           "%s-U3" % prefix)
    demand_u1, demand_u2, demand_u3 = ("%s-u1" % prefix, "%s-u2" % prefix,
                                       "%s-u3" % prefix)
    demand_contract = "%s-u1-contract" % prefix
    demand_chain = "%s-chain" % prefix
    loop = CarrierInformationLoop.create(args.database)
    try:
        reg_origin = _register_route_source(
            loop, origin_id, "origin", args.sector_origin, args.priority_origin,
            args.run_label, args.evaluated_at, valid_until, validity_policy,
            "handoff-registration-origin",
        )
        reg_dest = _register_route_source(
            loop, dest_id, "destination", args.sector_dest, args.priority_dest,
            args.run_label, args.evaluated_at, valid_until, validity_policy,
            "handoff-registration-dest",
        )
        expected_route = "%s>%s" % (args.sector_origin, args.sector_dest)

        u1_contract = route_synthesis_contract(
            origin_binding="origin", destination_binding="destination",
            destination_priority_binding="destination_priority")
        u1_contract["schema_version"] = args.u1_schema_version
        u1_constraint_kind = getattr(args, "u1_constraint_kind", "") or ""
        if u1_constraint_kind:
            # Swap the native-supported concat for a Python-only constraint kind,
            # so the native gate is exercised as the authority that refuses a
            # declaration it does not implement (see the docstring on N2).
            u1_contract["constraints"] = [
                c for c in u1_contract["constraints"] if c["kind"] != "concat"
            ] + [{"kind": u1_constraint_kind, "field": "route_key",
                  "binding": "destination_priority"}]
        u1_payload = {
            "schema_id": "SIMIGO-J-STEP-V1",
            "step": 1,
            "model_task": "synthesize_route",
            "answer_format": "ORIGIN/DEST/ROUTE/PRIORITY",
            "next_input_template": (
                "\nThe origin sector is {origin} (route priority "
                "{origin_priority}).\nThe destination sector is {destination} "
                "(route priority {destination_priority}).\nA route key is "
                "written as the origin sector, a single '>' character, then the "
                "destination sector.\nThe route inherits the destination's "
                "priority.\nReply with exactly four lines and nothing "
                "else:\nORIGIN=<origin sector>\nDEST=<destination sector>\n"
                "ROUTE=<origin>><destination>\nPRIORITY=<destination priority>\n"
                "Answer:"
            ),
            "input_bindings": [
                {"placeholder": "origin", "item_id": origin_id,
                 "result_field": "origin_code"},
                {"placeholder": "origin_priority", "item_id": origin_id,
                 "result_field": "priority"},
                {"placeholder": "destination", "item_id": dest_id,
                 "result_field": "destination_code"},
                {"placeholder": "destination_priority", "item_id": dest_id,
                 "result_field": "priority"},
            ],
            "semantic_contract": u1_contract,
            "source_item_ids": [origin_id, dest_id],
        }
        u1_payload["result_contract"] = derive_extraction_view(
            u1_payload["semantic_contract"])
        item_u1 = loop.put_source(
            CONTINUATION_POINT, u1_id, "model-task", "v1", u1_payload,
            dependencies=[origin_id, dest_id], valid_until_utc=valid_until,
            validity_policy=validity_policy,
        )
        u2_payload = {
            "schema_id": "SIMIGO-J-STEP-V1",
            "step": 2,
            "model_task": "carry_forward_route",
            "answer_format": "FLOW",
            "next_input_template": (
                "\nStep 1 established the route: {route_key} (priority "
                "{priority}).\nRestate that settled route exactly, unchanged, "
                "on one line in the form FLOW=<route> and add nothing else."
                "\nAnswer:"
            ),
            "input_bindings": [
                {"placeholder": "route_key", "item_id": u1_id,
                 "result_field": "route_key"},
                {"placeholder": "priority", "item_id": u1_id,
                 "result_field": "priority"},
            ],
            "semantic_contract": route_carry_forward_contract(
                route_binding="route_key", answer_prefix="FLOW"),
            "source_item_ids": [u1_id],
        }
        u2_payload["result_contract"] = derive_extraction_view(
            u2_payload["semantic_contract"])
        item_u2 = loop.put_source(
            CONTINUATION_POINT, u2_id, "model-task", "v1", u2_payload,
            dependencies=[u1_id], valid_until_utc=valid_until,
            validity_policy=validity_policy,
        )
        u3_payload = {
            "schema_id": "SIMIGO-J-STEP-V1",
            "step": 3,
            "model_task": "confirm_carried_route",
            "answer_format": "CONFIRMED",
            "next_input_template": (
                "\nStep 2 carried the route forward as: {route_key}.\nRestate "
                "that settled route exactly, unchanged, on one line in the "
                "form CONFIRMED=<route> and add nothing else.\nAnswer:"
            ),
            "input_bindings": [
                {"placeholder": "route_key", "item_id": u2_id,
                 "result_field": "route_key"},
            ],
            "semantic_contract": route_carry_forward_contract(
                route_binding="route_key", answer_prefix="CONFIRMED"),
            "source_item_ids": [u2_id],
        }
        u3_payload["result_contract"] = derive_extraction_view(
            u3_payload["semantic_contract"])
        item_u3 = loop.put_source(
            CONTINUATION_POINT, u3_id, "model-task", "v1", u3_payload,
            dependencies=[u2_id], valid_until_utc=valid_until,
            validity_policy=validity_policy,
        )
        loop.define_demand(
            demand_u1, continuation_point=CONTINUATION_POINT,
            pending_obligations=["synthesize the route key from both sources"],
            continuation_conditions=["both sources reusable and U1 settled"],
            required_item_ids=[u1_id],
        )
        loop.define_demand(
            demand_u2, continuation_point=CONTINUATION_POINT,
            pending_obligations=["restate U1's settled route"],
            continuation_conditions=["U1 reused and U2 settled"],
            required_item_ids=[u2_id],
        )
        loop.define_demand(
            demand_u3, continuation_point=CONTINUATION_POINT,
            pending_obligations=["confirm U2's settled route"],
            continuation_conditions=["U2 reused with its closure and U3 settled"],
            required_item_ids=[u3_id],
        )
        loop.define_demand(
            demand_contract, continuation_point=CONTINUATION_POINT,
            pending_obligations=["validate a U1 result against its declared contract"],
            continuation_conditions=["U1 settled with the full structured contract"],
            required_item_ids=[u1_id],
        )
        loop.define_demand(
            demand_chain, continuation_point=CONTINUATION_POINT,
            pending_obligations=["bring U3 up to date over the full closure"],
            continuation_conditions=[
                "restore and reuse the settled U1/U2 closure, recompute only U3"
            ],
            required_item_ids=[u3_id],
        )
        loop.commit()
        emit({
            "ok": True,
            "command": "define-j-graph",
            "run_label": args.run_label,
            "run_token": args.run_token,
            "continuation_point": CONTINUATION_POINT,
            "contract_dispatch_basis": "declared_contract",
            "contract_schema_version": CONTRACT_VERSION,
            "u1_declared_schema_version": args.u1_schema_version,
            "u1_constraint_kind": u1_constraint_kind,
            "origin": origin_id,
            "dest": dest_id,
            "u1": item_u1, "u2": item_u2, "u3": item_u3,
            "item_ids": [origin_id, dest_id, u1_id, u2_id, u3_id],
            "model_item_ids": [u1_id, u2_id, u3_id],
            "demand_u1": demand_u1, "demand_u2": demand_u2,
            "demand_u3": demand_u3, "demand_contract": demand_contract,
            "demand_chain": demand_chain,
            "origin_sector": args.sector_origin,
            "dest_sector": args.sector_dest,
            "origin_priority": args.priority_origin,
            "dest_priority": args.priority_dest,
            "expected_route_key": expected_route,
            "origin_registration_object_id": reg_origin["registration"]["object_id"],
            "dest_registration_object_id": reg_dest["registration"]["object_id"],
            "graph": {
                "sources": [origin_id, dest_id],
                "structured_chain": [u1_id, u2_id, u3_id],
                "transitive_closure_of_u3": [origin_id, dest_id, u1_id, u2_id,
                                             u3_id],
            },
            "declared_contracts": {
                u1_id: u1_payload["semantic_contract"],
                u2_id: u2_payload["semantic_contract"],
                u3_id: u3_payload["semantic_contract"],
            },
        })
    finally:
        loop.close()


def read_item(args: argparse.Namespace) -> None:
    loop = CarrierInformationLoop.open(args.database)
    try:
        item = loop.current_item(args.item_id)
        if item is None:
            raise ValueError(f"unknown item: {args.item_id}")
        settlement = loop.current_settlement(args.item_id)
        emit({
            "ok": True,
            "command": "read-item",
            "item": item,
            "settlement_state": settlement.get("state") if settlement else None,
            "settlement_object_id": (
                settlement.get("_object_id") if settlement else None
            ),
        })
    finally:
        loop.close()


def read_settlement(args: argparse.Namespace) -> None:
    loop = CarrierInformationLoop.open(args.database)
    try:
        settlement = loop.current_settlement(args.item_id)
        if settlement is None:
            raise ValueError(f"item has no settlement: {args.item_id}")
        emit({
            "ok": True,
            "command": "read-settlement",
            "item_id": args.item_id,
            "settlement": settlement,
        })
    finally:
        loop.close()


class AdmissionRefusal(RuntimeError):
    """A settlement could not be admitted for model input construction.

    Raised BEFORE any model work so the caller can record a pre-generation
    refusal instead of discovering the defect after paying for a generation.
    """

    def __init__(self, stage: str, reason: str, detail: object = None) -> None:
        super().__init__("%s: %s" % (stage, reason))
        self.stage = stage
        self.reason = reason
        self.detail = detail


PLACEHOLDER_PATTERN = re.compile(r"\{([a-z][a-z0-9_]*)\}")


def _resolve_settled_dependency(
    loop: CarrierInformationLoop,
    item_id: str,
    evaluated_at,
    visiting: set,
    resolved: dict,
) -> Optional[dict]:
    """Read one settled dependency from IS, using the SAME reuse decision as
    `execute_demand` (`_settlement_reuse_decision`) instead of a second
    validator. Any mismatch is a refusal, never a silent substitution."""
    if item_id in resolved:
        return resolved[item_id]
    if item_id in visiting:
        raise AdmissionRefusal("DEPENDENCY_CYCLE", "cycle at %s" % item_id)
    visiting.add(item_id)
    item = loop.current_item(item_id)
    if item is None:
        raise AdmissionRefusal("MISSING_ITEM", "unknown item: %s" % item_id)
    dependency_object_ids: dict[str, str] = {}
    for dependency_id in item["dependencies"]:
        dependency = _resolve_settled_dependency(
            loop, dependency_id, evaluated_at, visiting, resolved
        )
        if dependency is None:
            return None
        dependency_object_ids[dependency_id] = dependency["object_id"]
    try:
        settlement = loop.current_settlement(item_id)
    except Exception as error:  # noqa: BLE001 - tampered bytes must refuse, not crash
        raise AdmissionRefusal(
            "SETTLEMENT_OBJECT_UNREADABLE",
            "%s: %s" % (type(error).__name__, error),
            {"item_id": item_id},
        ) from error
    dependency_values = {
        dependency_id: resolved[dependency_id]["value"]
        for dependency_id in dependency_object_ids
    }
    reusable, refusal_reason = loop._settlement_reuse_decision(
        settlement, item, dependency_object_ids, evaluated_at, dependency_values
    )
    if not reusable:
        signature_stages = {
            "SETTLEMENT_SIGNATURE_MISSING",
            "SETTLEMENT_SIGNATURE_INVALID",
            "SETTLEMENT_TRUST_ANCHOR_INVALID",
            "SETTLEMENT_PROVENANCE_MISMATCH",
            "SETTLEMENT_EVENT_CHAIN_INVALID",
        }
        raise AdmissionRefusal(
            refusal_reason if refusal_reason in signature_stages else "SETTLEMENT_NOT_ADMITTED",
            refusal_reason or "SETTLEMENT_BASIS_MISMATCH",
            {"item_id": item_id, "settlement_state": (settlement or {}).get("state")},
        )
    object_id = settlement["_object_id"]
    try:
        content = loop.carrier.get_object(object_id)
    except Exception as error:  # noqa: BLE001 - fail closed on any read defect
        raise AdmissionRefusal(
            "SETTLEMENT_OBJECT_UNREADABLE",
            "%s: %s" % (type(error).__name__, error),
            {"item_id": item_id, "object_id": object_id},
        ) from error
    object_sha256 = hashlib.sha256(
        content.encode("utf-8") if isinstance(content, str) else bytes(content)
    ).hexdigest()
    if object_sha256 != object_id:
        raise AdmissionRefusal(
            "SETTLEMENT_OBJECT_ID_MISMATCH",
            "object bytes hash to %s but identity declares %s"
            % (object_sha256, object_id),
            {"item_id": item_id},
        )
    result = settlement["result"]
    if digest(result["value"]) != result["result_value_sha256"]:
        raise AdmissionRefusal(
            "SETTLEMENT_RESULT_DIGEST_MISMATCH",
            "stored value does not hash to the declared result digest",
            {"item_id": item_id},
        )
    signature = loop.current_settlement_signature(item_id)
    resolved[item_id] = {
        "item_id": item_id,
        "value": result["value"],
        "object_id": object_id,
        "object_sha256": object_sha256,
        "result_value_sha256": result["result_value_sha256"],
        "source_version": result["source_version"],
        "dependency_object_ids": result["dependency_object_ids"],
        "evaluated_at_utc": result["evaluated_at_utc"],
        "valid_until_utc": result["valid_until_utc"],
        "settlement_state": settlement.get("state"),
        "settlement_signature": (
            _settlement_signature_descriptor(signature) if signature else None
        ),
    }
    return resolved[item_id]


def resolve_model_input(args: argparse.Namespace) -> None:
    """Resolve, admit and materialize the model input for one task item.

    This is the production input path: the caller names the task item, and the
    executor reads the item's declared dependencies from IS, admits each
    settlement through the ordinary reuse decision, and expands the item's own
    template. The caller never supplies the values or the text.
    """
    evaluated_at = parse_utc(args.evaluated_at)
    # ``verify`` never loads the signing key: admitting a settled result needs
    # the public trust anchor only, so the consumer cannot mint provenance.
    loop = CarrierInformationLoop.open(args.database, provenance_policy="verify")
    try:
        try:
            item = loop.current_item(args.item_id)
        except Exception as error:  # noqa: BLE001 - corrupt item refuses, not crash
            raise AdmissionRefusal(
                "TASK_ITEM_UNREADABLE",
                "%s: %s" % (type(error).__name__, error),
                {"item_id": args.item_id},
            ) from error
        if item is None:
            raise AdmissionRefusal("MISSING_ITEM", "unknown item: %s" % args.item_id)
        payload = item.get("source_payload") or {}
        # A task item declares its model input as either a dependency-bound
        # template (`next_input_template` + `input_bindings`) or, when it
        # consumes no settled value, as a literal prompt (`next_input`). Both
        # are task-definition data read from IS; the caller supplies neither.
        template = payload.get("next_input_template")
        if not isinstance(template, str) or not template:
            template = payload.get("next_input")
        bindings_spec = payload.get("input_bindings", [])
        if not isinstance(template, str) or not template:
            raise AdmissionRefusal(
                "TEMPLATE_MISSING", "item declares no model input template"
            )
        if not isinstance(bindings_spec, list):
            raise AdmissionRefusal(
                "BINDINGS_MALFORMED", "input_bindings is not a list"
            )

        resolved: dict[str, dict] = {}
        for dependency_id in item["dependencies"]:
            _resolve_settled_dependency(
                loop, dependency_id, evaluated_at, set(), resolved
            )

        by_placeholder: dict[str, tuple] = {}
        for spec in bindings_spec:
            if not isinstance(spec, dict):
                raise AdmissionRefusal("BINDINGS_MALFORMED", "binding is not an object")
            placeholder = spec.get("placeholder")
            dependency_id = spec.get("item_id")
            result_field = spec.get("result_field")
            if not all(isinstance(value, str) and value
                       for value in (placeholder, dependency_id, result_field)):
                raise AdmissionRefusal(
                    "BINDINGS_MALFORMED", "binding is missing placeholder/item_id/result_field"
                )
            if dependency_id not in item["dependencies"]:
                raise AdmissionRefusal(
                    "INPUT_BINDING_DEPENDENCY_NOT_DECLARED",
                    "placeholder {%s} requires %s, which the current task item no "
                    "longer declares" % (placeholder, dependency_id),
                    {
                        "item_id": args.item_id,
                        "declared_dependencies": list(item["dependencies"]),
                        "binding_dependency": dependency_id,
                    },
                )
            if dependency_id not in resolved:
                raise AdmissionRefusal(
                    "BINDING_DEPENDENCY_UNSETTLED",
                    "%s is not settled" % dependency_id,
                )
            dependency_value = resolved[dependency_id]["value"]
            if result_field not in dependency_value:
                raise AdmissionRefusal(
                    "BINDING_FIELD_MISSING",
                    "%s result has no field %s" % (dependency_id, result_field),
                )
            value = dependency_value[result_field]
            if not isinstance(value, str) or not value:
                raise AdmissionRefusal(
                    "BINDING_VALUE_INVALID",
                    "%s.%s is not a non-empty string" % (dependency_id, result_field),
                )
            by_placeholder[placeholder] = (spec, value, resolved[dependency_id])

        placeholders = [match.group(1) for match in PLACEHOLDER_PATTERN.finditer(template)]
        unbound = sorted({name for name in placeholders if name not in by_placeholder})
        if unbound:
            raise AdmissionRefusal(
                "UNBOUND_TEMPLATE_PLACEHOLDER",
                "no admitted settlement binding for %s" % ", ".join(unbound),
                {"unbound_placeholders": unbound},
            )

        pieces: list[str] = []
        bindings: list[dict] = []
        cursor = 0
        consumed = 0
        for match in PLACEHOLDER_PATTERN.finditer(template):
            literal = template[consumed:match.start()]
            pieces.append(literal)
            cursor += len(literal.encode("utf-8"))
            spec, value, dependency = by_placeholder[match.group(1)]
            encoded = value.encode("utf-8")
            bindings.append({
                "placeholder": spec["placeholder"],
                "item_id": spec["item_id"],
                "result_field": spec["result_field"],
                "value": value,
                "value_sha256": hashlib.sha256(encoded).hexdigest(),
                "settlement_object_id": dependency["object_id"],
                "settlement_object_sha256": dependency["object_sha256"],
                "result_value_sha256": dependency["result_value_sha256"],
                "byte_offset": cursor,
                "byte_length": len(encoded),
            })
            pieces.append(value)
            cursor += len(encoded)
            consumed = match.end()
        tail = template[consumed:]
        pieces.append(tail)
        cursor += len(tail.encode("utf-8"))
        input_text = "".join(pieces)
        input_bytes = input_text.encode("utf-8")
        if len(input_bytes) != cursor:
            raise AdmissionRefusal(
                "INPUT_LENGTH_MISMATCH", "materialized input length disagrees"
            )

        dependencies = [
            {
                "item_id": dependency["item_id"],
                "settlement_object_id": dependency["object_id"],
                "settlement_object_sha256": dependency["object_sha256"],
                "result_value_sha256": dependency["result_value_sha256"],
                "source_version": dependency["source_version"],
                "dependency_object_ids": dependency["dependency_object_ids"],
                "evaluated_at_utc": dependency["evaluated_at_utc"],
                "valid_until_utc": dependency["valid_until_utc"],
                "settlement_state": dependency["settlement_state"],
                "settlement_signature": dependency.get("settlement_signature"),
            }
            for dependency in resolved.values()
        ]
        emit({
            "ok": True,
            "command": "resolve-model-input",
            "item_id": args.item_id,
            "evaluated_at_utc": args.evaluated_at,
            "declared_dependencies": list(item["dependencies"]),
            "template": template,
            "template_sha256": hashlib.sha256(template.encode("utf-8")).hexdigest(),
            "input_text": input_text,
            "input_sha256": hashlib.sha256(input_bytes).hexdigest(),
            "input_byte_length": len(input_bytes),
            "bindings": bindings,
            "dependencies": dependencies,
            "settlement_signatures": [
                dependency["settlement_signature"]
                for dependency in resolved.values()
                if dependency.get("settlement_signature") is not None
            ],
            "checks": {
                "all_declared_dependencies_admitted": True,
                "settlement_objects_readable": True,
                "object_identity_matches_bytes": True,
                "result_digests_match_values": True,
                "source_versions_match_items": True,
                "dependency_object_sets_match": True,
                "validity_satisfied": True,
                "all_placeholders_bound": True,
                "settlement_signatures_valid": True,
            },
        })
    finally:
        loop.close()


def _validate_model_value(
    source_payload: dict,
    value: dict,
    dependency_values: dict,
) -> dict:
    """Contract-driven gate for a model-produced result. No task-id branching.

    The item's OWN declaration (``semantic_contract``) decides which fields the
    generated text must carry, how each is typed, which admitted input bindings
    a field must agree with and how fields derive from one another. The verified
    bindings are projected out of the admitted dependency closure by the
    contract's own binding selectors, so an item id that no source file has ever
    seen validates exactly like an old one, and an item that declares no
    contract is refused rather than matched to some other task's rules by name.

    This is NOT a computation. It refuses a value that the model could not have
    produced from the settled dependency results, so an externally supplied
    model output can never be settled against unrelated information.
    """
    return validate_declared_result(source_payload, value, dependency_values)


def _load_model_provenance_override(args: argparse.Namespace, value: dict) -> dict:
    """Validate the producer attestation without trusting it as a result.

    The model value is still validated by ``_validate_model_value``.  This
    helper only checks that the execution/model identity supplied by the Swift
    producer is well-formed and agrees with the value it accompanies; the
    settlement path then signs the full declaration the carrier builds.
    """
    raw = json.loads(Path(args.provenance_file).read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise ValueError("provenance override must be a JSON object")
    unexpected = set(raw) - {"producer", "model", "output"}
    if unexpected:
        raise ValueError("provenance override has unsupported fields: %s" % sorted(unexpected))
    producer = raw.get("producer")
    if not isinstance(producer, dict):
        raise ValueError("provenance producer is missing")
    if producer.get("kind") != "model_task":
        raise ValueError("provenance producer kind must be model_task")
    for field in ("run_id", "execution_id", "process_id", "build_sha256"):
        if not isinstance(producer.get(field), str) or not producer[field]:
            raise ValueError("provenance producer.%s is missing" % field)
    for field, expected in (
        ("run_id", args.run_id),
        ("execution_id", args.execution_id),
        ("build_sha256", args.build_sha256),
        ("process_id", args.producer_process_id),
    ):
        if expected is not None and producer[field] != expected:
            raise ValueError("provenance producer.%s does not match the entry" % field)
    model = raw.get("model")
    if not isinstance(model, dict):
        raise ValueError("provenance model is missing")
    for field in ("snapshot_revision", "weights_manifest_sha256"):
        if not isinstance(model.get(field), str) or not model[field]:
            raise ValueError("provenance model.%s is missing" % field)
    if model["snapshot_revision"] != value.get("model_snapshot_revision"):
        raise ValueError("provenance model identity disagrees with the model value")
    if args.model_manifest:
        manifest = json.loads(Path(args.model_manifest).read_text(encoding="utf-8"))
        if manifest.get("snapshot_revision") != model["snapshot_revision"]:
            raise ValueError("model snapshot is not the trusted deployment snapshot")
        if manifest.get("weights_manifest_sha256") != model["weights_manifest_sha256"]:
            raise ValueError("model weights are not the trusted deployment weights")
    output = raw.get("output")
    if not isinstance(output, dict):
        raise ValueError("provenance output is missing")
    expected_tokens_sha256 = digest(value.get("generated_token_ids"))
    if output.get("generated_token_ids_sha256") != expected_tokens_sha256:
        raise ValueError("provenance output digest disagrees with the model value")
    if output.get("generated_token_count") != len(value.get("generated_token_ids") or []):
        raise ValueError("provenance output token count disagrees with the model value")
    return raw


def execute_with_model_result(args: argparse.Namespace) -> None:
    """Settle a model-produced result through the ordinary demand machinery.

    The model ran in the Swift runtime BEFORE this call. The calculator is
    restricted to exactly the item the model computed: if any dependency is
    not reusable, the demand machinery asks the calculator for it and this
    command fails closed instead of settling work the model never performed.
    """
    validity_policy = load_deployment_validity_policy()
    with open(args.value_file, "r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        raise ValueError("model result value must be a JSON object")
    provenance_override = _load_model_provenance_override(args, value)
    contract_reports = {}

    loop = CarrierInformationLoop.open(args.database, provenance_policy="required")
    try:
        def calculator(item_id: str, source_payload: dict, dependency_values: dict) -> dict:
            # Not a semantic rule: the producer attests work for exactly one
            # item, so a dependency that was not reusable must never be settled
            # with this item's model output.
            if item_id != args.item_id:
                raise ValueError(
                    "model result is only valid for %s; dependency %s was not reusable"
                    % (args.item_id, item_id)
                )
            contract_reports[item_id] = _validate_model_value(
                source_payload, value, dependency_values)
            return value

        result = loop.execute_demand(
            args.demand_id,
            args.advancement,
            calculator,
            evaluated_at_utc=args.evaluated_at,
            expected_validity_policy_sha256=validity_policy["policy_sha256"],
            require_deployment_policy=True,
            provenance_overrides={args.item_id: provenance_override},
        )
        settlement = loop.current_settlement(args.item_id)
        signature = loop.current_settlement_signature(args.item_id)
        if settlement is None or signature is None:
            raise ValueError("model settlement is not signed; refusing to report success")
        loop.commit()
        emit({
            "ok": True,
            "command": "execute-with-model-result",
            "item_id": args.item_id,
            "demand_id": args.demand_id,
            "contract_dispatch_basis": "declared_contract",
            "result_contract_validation": contract_reports.get(args.item_id, {}),
            "result": result,
            "settlement_signature": _settlement_signature_descriptor(signature),
        })
    finally:
        loop.close()


def execute_probe(args: argparse.Namespace) -> None:
    """Model-free dependency-closure probe: settle whatever is not reusable.

    Used on an isolated COPY of a run database after invalidation, to prove
    which items the dependency closure actually recomputes. It never loads a
    model and never touches the authoritative run database.
    """
    validity_policy = (
        load_deployment_validity_policy()
        if os.environ.get("SIMIGO_INFO_VALIDITY_POLICY_PATH")
        else None
    )
    loop = CarrierInformationLoop.open(args.database, provenance_policy="required")
    try:
        def calculator(item_id: str, source_payload: dict, dependency_values: dict) -> dict:
            return {
                "probe_marker": digest({
                    "item_id": item_id,
                    "source_payload_sha256": digest(source_payload),
                    "dependency_item_ids": sorted(dependency_values),
                })
            }

        result = loop.execute_demand(
            args.demand_id,
            args.advancement,
            calculator,
            evaluated_at_utc=args.evaluated_at,
            expected_validity_policy_sha256=(
                validity_policy["policy_sha256"] if validity_policy else None
            ),
            require_deployment_policy=bool(validity_policy),
        )
        loop.commit()
        emit({
            "ok": True,
            "command": "execute-probe",
            "demand_id": args.demand_id,
            "result": result,
        })
    finally:
        loop.close()


def snapshot_database(args: argparse.Namespace) -> None:
    """Consistent SQLite backup, so probes never run on a live file copy."""
    import sqlite3

    destination = Path(args.destination)
    if destination.exists() or destination.is_symlink():
        raise FileExistsError(destination)
    source = sqlite3.connect(str(Path(args.database).resolve()))
    target = sqlite3.connect(str(destination))
    try:
        source.backup(target)
        target.commit()
    finally:
        target.close()
        source.close()
    emit({
        "ok": True,
        "command": "snapshot-database",
        "source": str(Path(args.database).resolve()),
        "destination": str(destination.resolve()),
    })


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

    define_task_parser = subparsers.add_parser("define-task")
    define_task_parser.add_argument("--database", required=True)
    define_task_parser.add_argument("--evaluated-at", required=True)
    define_task_parser.add_argument("--run-label", required=True)
    define_task_parser.add_argument(
        "--secret",
        default=None,
        help="controlled nonce override; does not change the task graph",
    )
    define_task_parser.add_argument(
        "--secret-file",
        default=None,
        help="read the nonce from a file so it never appears in the command line",
    )
    define_task_parser.add_argument(
        "--random-secret",
        action="store_true",
        help=(
            "generate a 128-bit nonce inside this process; the raw nonce is "
            "never emitted, passed on a command line or written to a temp file"
        ),
    )
    define_task_parser.add_argument("--valid-until")
    define_task_parser.set_defaults(handler=define_task)

    define_h_graph_parser = subparsers.add_parser("define-h-graph")
    define_h_graph_parser.add_argument("--database", required=True)
    define_h_graph_parser.add_argument("--evaluated-at", required=True)
    define_h_graph_parser.add_argument("--run-label", required=True)
    define_h_graph_parser.add_argument("--secret-a", required=True)
    define_h_graph_parser.add_argument("--secret-b", required=True)
    define_h_graph_parser.add_argument("--valid-until")
    define_h_graph_parser.set_defaults(handler=define_h_graph)

    h_source_update_parser = subparsers.add_parser("h-source-update")
    h_source_update_parser.add_argument("--database", required=True)
    h_source_update_parser.add_argument("--evaluated-at", required=True)
    h_source_update_parser.add_argument("--run-label", required=True)
    h_source_update_parser.add_argument("--new-secret-a", required=True)
    h_source_update_parser.set_defaults(handler=h_source_update)

    define_i_graph_parser = subparsers.add_parser("define-i-graph")
    define_i_graph_parser.add_argument("--database", required=True)
    define_i_graph_parser.add_argument("--evaluated-at", required=True)
    define_i_graph_parser.add_argument("--run-label", required=True)
    define_i_graph_parser.add_argument("--sector-origin", required=True)
    define_i_graph_parser.add_argument("--sector-dest", required=True)
    define_i_graph_parser.add_argument("--priority-origin", default="3")
    define_i_graph_parser.add_argument("--priority-dest", default="5")
    define_i_graph_parser.add_argument("--valid-until")
    define_i_graph_parser.set_defaults(handler=define_i_graph)

    define_j_graph_parser = subparsers.add_parser("define-j-graph")
    define_j_graph_parser.add_argument("--database", required=True)
    define_j_graph_parser.add_argument("--evaluated-at", required=True)
    define_j_graph_parser.add_argument("--run-label", required=True)
    define_j_graph_parser.add_argument(
        "--run-token", required=True,
        help="run-time token that mints every item and demand id in this graph; "
             "no source file can know it in advance",
    )
    define_j_graph_parser.add_argument("--sector-origin", required=True)
    define_j_graph_parser.add_argument("--sector-dest", required=True)
    define_j_graph_parser.add_argument("--priority-origin", default="3")
    define_j_graph_parser.add_argument("--priority-dest", default="5")
    define_j_graph_parser.add_argument(
        "--u1-schema-version", default=CONTRACT_VERSION,
        help="declared contract version for U1; the J3 control points this at a "
             "version the gate does not implement to observe the fail-closed path",
    )
    define_j_graph_parser.add_argument("--valid-until")
    define_j_graph_parser.add_argument(
        "--u1-constraint-kind", default="",
        help="K-round native counterfactual (N2): replace U1's concat with this "
             "Python-implemented, native-unimplemented constraint kind so the "
             "native pre-settlement gate refuses and settles nothing")
    define_j_graph_parser.set_defaults(handler=define_j_graph)

    read_item_parser = subparsers.add_parser("read-item")
    read_item_parser.add_argument("--database", required=True)
    read_item_parser.add_argument("--item-id", required=True)
    read_item_parser.set_defaults(handler=read_item)

    read_settlement_parser = subparsers.add_parser("read-settlement")
    read_settlement_parser.add_argument("--database", required=True)
    read_settlement_parser.add_argument("--item-id", required=True)
    read_settlement_parser.set_defaults(handler=read_settlement)

    resolve_input_parser = subparsers.add_parser("resolve-model-input")
    resolve_input_parser.add_argument("--database", required=True)
    resolve_input_parser.add_argument("--item-id", required=True)
    resolve_input_parser.add_argument("--evaluated-at", required=True)
    resolve_input_parser.set_defaults(handler=resolve_model_input)

    model_result_parser = subparsers.add_parser("execute-with-model-result")
    model_result_parser.add_argument("--database", required=True)
    model_result_parser.add_argument("--demand-id", required=True)
    model_result_parser.add_argument("--advancement", required=True)
    model_result_parser.add_argument("--evaluated-at", required=True)
    model_result_parser.add_argument("--item-id", required=True)
    model_result_parser.add_argument("--value-file", required=True)
    model_result_parser.add_argument("--provenance-file", required=True)
    model_result_parser.add_argument("--run-id")
    model_result_parser.add_argument("--execution-id")
    model_result_parser.add_argument("--build-sha256")
    model_result_parser.add_argument("--producer-process-id")
    model_result_parser.add_argument("--model-manifest")
    model_result_parser.set_defaults(handler=execute_with_model_result)

    probe_parser = subparsers.add_parser("execute-probe")
    probe_parser.add_argument("--database", required=True)
    probe_parser.add_argument("--demand-id", required=True)
    probe_parser.add_argument("--advancement", required=True)
    probe_parser.add_argument("--evaluated-at", required=True)
    probe_parser.set_defaults(handler=execute_probe)

    snapshot_parser = subparsers.add_parser("snapshot-database")
    snapshot_parser.add_argument("--database", required=True)
    snapshot_parser.add_argument("--destination", required=True)
    snapshot_parser.set_defaults(handler=snapshot_database)

    args = parser.parse_args()
    try:
        args.handler(args)
    except AdmissionRefusal as error:
        emit({
            "ok": False,
            "command": args.command,
            "error_type": type(error).__name__,
            "error": str(error),
            "refusal": {
                "stage": error.stage,
                "reason": error.reason,
                "detail": error.detail,
            },
        })
        return 1
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
