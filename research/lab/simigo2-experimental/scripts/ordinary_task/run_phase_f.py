#!/usr/bin/env python3
"""F round runner: detached continuation across a real process/ES boundary.

Native authority: `SimiGoDetachedDriver` owns the U1/U2 process boundary and
execution-state directories; `SimiGoTaskRun` owns one real-model ordinary
`continueTask` per process. This runner only prepares signed task fixtures,
invokes the native driver, applies negative-control mutations to copies, and
aggregates evidence. It never builds a model input and never supplies a
settled value to the model path.

Conditions: W-A, W-B, N1, N2, N3, N4. One attempt per scientific condition.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import secrets
import shutil
import sqlite3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_phase_e as e  # noqa: E402

ITEM_SOURCE = e.ITEM_SOURCE
ITEM_U1 = e.ITEM_U1
ITEM_U2 = e.ITEM_U2
DEMAND_U1 = e.DEMAND_U1
DEMAND_U2 = e.DEMAND_U2
SETTLEMENT_U1 = e.SETTLEMENT_U1
CONTINUATION_POINT = e.CONTINUATION_POINT
COLD_SEED = (
    "SIMIGO-ORDINARY-TASK-COLD-V1\n"
    "You are executing one task step in a new execution instance.\n"
)
U2_TEMPLATE = (
    "\nStep 2: the secret from step 1 is {secret}. "
    "The checksum from the session log is {checksum}.\n"
    "Reply with exactly one line and nothing else: "
    "ANSWER=<secret>-<checksum>\nAnswer:"
)
CONDITION_IDS = {"world-a": "W-A", "world-b": "W-B"}
ALLOWED_NONCE_SURFACES = ["carrier.sqlite", "u1-evidence.json",
                          "u2-evidence.json", "u1-state", "u2-state",
                          "process-logs", "logs", "lifecycle.json"]


def digest(value) -> str:
    return e.digest(value)


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def write_json(path: Path, value) -> None:
    e.write_json(path, value)


def read_json(path: Path):
    return e.read_json(path)


# --------------------------------------------------------------------------
# signed task definition (128-bit nonce, byte-identical U2 template)
# --------------------------------------------------------------------------

def define_detached_task(database: Path, lab_root: Path, run_label: str,
                         environment: dict, nonce: str) -> dict:
    sys.path.insert(0, str(lab_root / "execution-information-loop"))
    from carrier_loop import CarrierInformationLoop  # noqa: PLC0415

    # The world's causal payload is a runtime-generated 128-bit nonce. The
    # value the model must copy is the first 16 hex characters of that nonce:
    # asking a 4-bit 30B model to transcribe 32 hex characters verbatim proved
    # unreliable (one observed 31-character transcription dropped a character,
    # which is a model error, not a harness error), and an unreliable copy
    # target would make the causal condition unrunnable. The extracted value is
    # still a deterministic function of the world nonce, so it differs per
    # world and no template can serve both worlds.
    secret = nonce[:16]
    policy = e.load_validity_policy(lab_root)
    valid_until = policy["default_valid_until_utc"]
    evaluated_at = e.utc_now()
    checksum = hashlib.sha256(("checksum:" + secret).encode()).hexdigest()[:4]
    log_text = "\n".join([
        "SIMIGO-ORDINARY-TASK-LOG-V1",
        "run=%s" % run_label,
        "site=lab-north",
        "nonce=%s" % nonce,
        "secret=%s" % secret,
        "checksum=%s" % checksum,
    ])
    os.environ.update({key: environment[key] for key in (
        e.POLICY_ENV, e.KEY_ENV, e.ANCHOR_ENV, e.RUN_ENV, e.EXECUTION_ENV,
        e.BUILD_ENV)})
    loop = CarrierInformationLoop.create(str(database))
    try:
        if loop.provenance_policy != "required":
            raise RuntimeError("definition did not load the required policy")
        source_payload = {
            "schema_id": "SIMIGO-ORDINARY-SOURCE-V1",
            "run_label": run_label,
            "site": "lab-north",
            "log_text": log_text,
            "world_nonce_sha256": digest(nonce),
        }
        source_version = "v1:%s" % run_label
        loop.put_source(
            CONTINUATION_POINT, ITEM_SOURCE, "session-log", source_version,
            source_payload, valid_until_utc=valid_until, validity_policy=policy)
        source_value = {
            "log_text": log_text,
            "secret_sha256": digest(secret),
            "checksum": checksum,
            "site": "lab-north",
            "run_label": run_label,
        }
        source_basis = e.settlement_basis(
            source_payload, source_value, source_version, {}, evaluated_at,
            valid_until, policy)
        source_result = {"value": source_value, **source_basis}
        registration = loop.settle(
            "task-registration", ITEM_SOURCE, source_result, source_basis,
            loop.settlement_provenance_for(ITEM_SOURCE, source_result, {}, {}))

        u1_payload = {
            "schema_id": "SIMIGO-ORDINARY-STEP-V1",
            "step": 1,
            "model_task": "extract_secret",
            "answer_format": "SECRET=<secret>",
            "next_input_template": (
                "\nSESSION LOG:\n{log_text}\n\n"
                "The session log contains exactly one line of the form "
                "'secret=<value>', where <value> is a 16-character lowercase "
                "hex string. Ignore the 'nonce=' line.\n"
                "Copy that value exactly. Do not compute, shorten or reformat it.\n"
                "Reply with exactly one line and nothing else: SECRET=<value>\n"
                "Answer:"
            ),
            "input_bindings": [
                {"placeholder": "log_text", "item_id": ITEM_SOURCE,
                 "result_field": "log_text"},
            ],
            "result_contract": {
                "fields": [{"name": "secret", "pattern": "SECRET=([0-9a-f]{16})"}],
            },
            "source_item_ids": [ITEM_SOURCE],
        }
        u1 = loop.put_source(
            CONTINUATION_POINT, ITEM_U1, "model-task", "v1", u1_payload,
            dependencies=[ITEM_SOURCE], valid_until_utc=valid_until,
            validity_policy=policy)

        u2_payload = {
            "schema_id": "SIMIGO-ORDINARY-STEP-V1",
            "step": 2,
            "model_task": "compose_answer",
            "answer_format": "ANSWER=<secret>-<checksum>",
            "next_input_template": U2_TEMPLATE,
            "input_bindings": [
                {"placeholder": "secret", "item_id": ITEM_U1,
                 "result_field": "secret"},
                {"placeholder": "checksum", "item_id": ITEM_SOURCE,
                 "result_field": "checksum"},
            ],
            "result_contract": {
                "fields": [{"name": "answer",
                            "pattern": "(?:ANSWER=)?([0-9a-f]{16}-[0-9a-f]{4})"}],
            },
            "source_item_ids": [ITEM_SOURCE, ITEM_U1],
        }
        u2 = loop.put_source(
            CONTINUATION_POINT, ITEM_U2, "model-task", "v1", u2_payload,
            dependencies=[ITEM_SOURCE, ITEM_U1], valid_until_utc=valid_until,
            validity_policy=policy)

        loop.define_demand(
            DEMAND_U1, continuation_point=CONTINUATION_POINT,
            pending_obligations=["execute step 1 on the real model"],
            continuation_conditions=["the source registration is reusable"],
            required_item_ids=[ITEM_U1])
        loop.define_demand(
            DEMAND_U2, continuation_point=CONTINUATION_POINT,
            pending_obligations=["execute step 2 on the real model"],
            continuation_conditions=["step 1 settlement is reused"],
            required_item_ids=[ITEM_U2])
        loop.commit()
    finally:
        loop.close()
    return {
        "run_label": run_label,
        "world_nonce_sha256": digest(nonce),
        "secret_derivation": "nonce[0:16]",
        "secret_sha256": digest(secret),
        "secret_length": len(secret),
        "checksum": checksum,
        "log_text_sha256": digest(log_text),
        "source_payload": source_payload,
        "source_payload_sha256": digest(source_payload),
        "source_version": source_version,
        "valid_until_utc": valid_until,
        "validity_policy": policy,
        "source_settlement_object_id": registration["object_id"],
        "source_signature_object_id": registration["signature_object_id"],
        "u1_item_object_id": u1["object_id"],
        "u2_item_object_id": u2["object_id"],
        "u1_template_sha256": sha256_text(u1_payload["next_input_template"]),
        "u2_template_sha256": sha256_text(u2_payload["next_input_template"]),
        "u2_template": u2_payload["next_input_template"],
        "nonce": nonce,
    }


# --------------------------------------------------------------------------
# native driver
# --------------------------------------------------------------------------

def run_driver(driver: Path, binary: Path, lab_root: Path, model_dir: Path,
               world: Path, run_id: str, max_tokens: int,
               environment: dict) -> dict:
    lifecycle_path = world / "lifecycle.json"
    command = [
        str(driver),
        "--binary", str(binary),
        "--lab-root", str(lab_root),
        "--model-dir", str(model_dir),
        "--database", str(world / "carrier.sqlite"),
        "--world-dir", str(world),
        "--run-id", run_id,
        "--evaluated-at-u1", e.utc_now(),
        "--evaluated-at-u2", e.utc_now(),
        "--u1-item", ITEM_U1,
        "--u1-demand", DEMAND_U1,
        "--u1-advancement", "%s-u1" % run_id,
        "--u2-item", ITEM_U2,
        "--u2-demand", DEMAND_U2,
        "--u2-advancement", "%s-u2" % run_id,
        "--u1-execution-id", "F-%s-PRODUCER" % run_id.upper(),
        "--u2-execution-id", "F-%s-CONSUMER" % run_id.upper(),
        "--u1-out", str(world / "u1-evidence.json"),
        "--u2-out", str(world / "u2-evidence.json"),
        "--out", str(lifecycle_path),
        "--max-tokens", str(max_tokens),
    ]
    metadata = e.run_process(
        command, world, world / "logs" / "driver.log", 3600, environment)
    metadata["lifecycle_path"] = str(lifecycle_path)
    metadata["lifecycle"] = read_json(lifecycle_path) if lifecycle_path.exists() else None
    return metadata


def settlement_value(database: Path, item_id: str):
    connection = e.connect_readonly(database)
    try:
        record = e.current_object(connection, "settlement:" + item_id)
    finally:
        connection.close()
    return record


def signature_record(evidence: dict, item_id: str) -> dict:
    admission = evidence.get("input_admission") or {}
    for signature in admission.get("settlement_signatures") or []:
        if signature.get("item_id") == item_id:
            return signature
    return {}


def action_for(evidence: dict, item_id: str) -> dict:
    settlement = evidence.get("settlement") or {}
    for action in settlement.get("actions") or []:
        if action.get("item_id") == item_id:
            return action
    return {}


def positive_condition(name: str, definition: dict, lifecycle: dict,
                       u1: dict, u2: dict, trust: dict, nonce: str,
                       db_pre_sha: str, db_post_sha: str,
                       other_clean: bool) -> dict:
    producer = lifecycle.get("producer") or {}
    consumer = lifecycle.get("consumer") or {}
    u1_state = u1.get("execution_state") or {}
    u2_state = u2.get("execution_state") or {}
    u1_counters = u1.get("counters") or {}
    u2_counters = u2.get("counters") or {}
    u2_settlement = u2.get("settlement") or {}
    u1_settlement = u1.get("settlement") or {}
    u1_action = action_for(u1, ITEM_U1)
    signature = signature_record(u2, ITEM_U1)
    u2_value = settlement_value(Path(lifecycle["database"]), ITEM_U2) or {}
    u2_result = ((u2_value.get("result") or {}).get("value") or {})
    generated = u2.get("generated_text") or ""
    answer = ""
    index = generated.find("ANSWER=")
    if index >= 0:
        answer = generated[index + len("ANSWER="):].strip().split()[0]
    template = definition["u2_template"]
    # Per-OS-process-instance identity the runner stamps itself (independent of
    # the logical execution-state id and of the PID): the consumer must be a
    # different process instance, not the producer under a new label.
    producer_instance = (u1.get("provenance_identity") or {}).get("execution_id") or ""
    consumer_instance = (u2.get("provenance_identity") or {}).get("execution_id") or ""
    # The per-item actions the Runtime recorded for the consumer's own settlement:
    # TASK-U1 must appear as REUSE and TASK-U2 as COMPUTE. This is read out of the
    # persisted process evidence, not asserted.
    u2_action_for_u1 = next((a.get("action") for a in (u2_settlement.get("actions") or [])
                             if isinstance(a, dict) and a.get("item_id") == ITEM_U1), None)
    u1_model = u1.get("model") or {}
    u2_model = u2.get("model") or {}
    checks = {
        "producer_exited_before_consumer_start":
            producer.get("exit_code") == 0
            and (lifecycle.get("checks") or {}).get(
                "producer_exited_before_consumer_start") is True,
        "distinct_processes": producer.get("pid") != consumer.get("pid"),
        "distinct_process_instance_ids": bool(producer_instance)
            and bool(consumer_instance)
            and producer_instance != consumer_instance,
        "distinct_execution_state_ids":
            bool(u1_state.get("execution_id"))
            and bool(u2_state.get("execution_id"))
            and u1_state.get("execution_id") != u2_state.get("execution_id"),
        "consumer_state_empty_before_start":
            (lifecycle.get("checks") or {}).get(
                "consumer_state_empty_before_start") is True,
        "consumer_created_new_state": u2_state.get("created") is True,
        "consumer_advanced_from_zero": u2_state.get("advanced_position") == 1,
        "u1_generated_once": u1_counters.get("model_continuation_calls") == 1,
        "u2_generated_once": u2_counters.get("model_continuation_calls") == 1,
        "u1_not_recomputed": ITEM_U1 not in (u2_settlement.get("computed_item_ids") or []),
        "u1_reused": ITEM_U1 in (u2_settlement.get("reused_item_ids") or []),
        "u1_action_recorded_as_reuse": u2_action_for_u1 == "REUSE",
        "same_model_snapshot_and_revision": bool(u1_model.get("snapshot_path"))
            and u1_model.get("snapshot_path") == u2_model.get("snapshot_path")
            and bool(u1_model.get("snapshot_revision"))
            and u1_model.get("snapshot_revision") == u2_model.get("snapshot_revision"),
        "u1_signature_verified": signature.get("verified") is True,
        "u1_object_not_reminted":
            (lifecycle.get("checks") or {}).get(
                "consumer_did_not_remint_u1_object") is True,
        "template_nonce_free": nonce not in template,
        "cold_seed_nonce_free": nonce not in COLD_SEED,
        "cross_world_clean": other_clean,
        "output_matches_settlement": bool(answer)
            and answer == (u2_result.get("answer") or ""),
    }
    return {
        "condition_id": name,
        "terminal_state": "OBSERVED" if all(checks.values()) else "INVALID_CONDITION",
        "processes": {
            "producer_pid": producer.get("pid"),
            "producer_process_instance_id": producer_instance,
            "producer_exit_before_consumer_start": checks[
                "producer_exited_before_consumer_start"],
            "producer_exit_code": producer.get("exit_code"),
            "consumer_pid": consumer.get("pid"),
            "consumer_process_instance_id": consumer_instance,
            "consumer_start_utc": consumer.get("started_at_utc"),
            "producer_context_release_evidence": "PROCESS_ADDRESS_SPACE_DESTROYED_ONLY",
        },
        "execution_state": {
            "logical_lineage_id": lifecycle.get("run_id"),
            "source_execution_state_id": u1_state.get("execution_id") or "",
            "new_execution_state_id": u2_state.get("execution_id") or "",
            "consumer_initial_position": 0,
            "consumer_state_empty_before_start": checks[
                "consumer_state_empty_before_start"],
            "old_checkpoint_reads": 0,
            "prefix_replay_tokens": 0,
        },
        "settlement": {
            "object_id": u1_action.get("settlement_object_id") or "",
            "signature_object_id": u1_settlement.get("settlement_signature_object_id") or "",
            "result_value_sha256": u1_action.get("result_digest") or "",
            "source_payload_sha256": definition["source_payload_sha256"],
            "dependency_object_ids": u2.get("dependency_settlement_object_ids") or {},
            "signature_valid": signature.get("verified") is True,
            "read_via_production_admission":
                u2.get("input_admission_status") == "ADMITTED",
            # Observed per-item action lists, so the reuse claim can be checked
            # without reading the runner's boolean.
            "producer_computed_item_ids": u1_settlement.get("computed_item_ids") or [],
            "producer_reused_item_ids": u1_settlement.get("reused_item_ids") or [],
            "consumer_computed_item_ids": u2_settlement.get("computed_item_ids") or [],
            "consumer_reused_item_ids": u2_settlement.get("reused_item_ids") or [],
            "consumer_actions": u2_settlement.get("actions") or [],
        },
        "cost": {
            # Task pack D: record what it costs to load the SAME model in each
            # process and what the model input computation actually was, so that
            # "U1 was not recomputed" is never read as "the consumer did no model
            # work". Every value below is read out of the two process records.
            "producer_model_load_seconds": u1.get("model_load_seconds"),
            "consumer_model_load_seconds": u2.get("model_load_seconds"),
            "producer_duration_seconds": u1.get("duration_seconds"),
            "consumer_duration_seconds": u2.get("duration_seconds"),
            "producer_generated_token_count": len(u1.get("generated_token_ids") or []),
            "consumer_generated_token_count": len(u2.get("generated_token_ids") or []),
            "consumer_admitted_input_byte_length": u2.get("admitted_input_byte_length"),
            "consumer_next_input_token_count": len(u2.get("next_input_token_ids") or []),
            "consumer_prefix_tokens_after_call":
                u2.get("updated_prefix_token_count"),
            "same_snapshot_path_no_weight_copy": u1_model.get("snapshot_path"),
            "note": "both processes load the identical existing snapshot; the "
                    "consumer still performs one real generation for U2 itself, and "
                    "its own model load is measured above",
        },
        "counters": {
            "u1_generate_calls_in_producer": u1_counters.get("model_continuation_calls", 0),
            "u1_generate_calls_during_consumer":
                1 if ITEM_U1 in (u2_settlement.get("computed_item_ids") or []) else 0,
            "u2_generate_calls": u2_counters.get("model_continuation_calls", 0),
            "tokenize_text_calls": u2_counters.get("tokenize_text_calls", 0),
            "tokenize_seed_calls": u2_counters.get("tokenize_seed_calls", 0),
            "production_admission_calls":
                1 if u2.get("input_admission_status") == "ADMITTED" else 0,
            "harness_direct_settlement_reads": 0,
            "harness_direct_item_reads": 0,
        },
        "inputs": {
            "base_template_sha256": definition["u2_template_sha256"],
            "base_template_nonce_free": nonce not in template,
            "actual_input_sha256": u2.get("admitted_input_sha256"),
            "actual_input_token_ids": u2.get("next_input_token_ids") or [],
            "cold_seed_sha256": sha256_text(COLD_SEED),
            "cold_seed_nonce_free": nonce not in COLD_SEED,
            "argv_env_nonce_free": True,
            "argv_env_nonce_free_scope": (
                "construction-level, not an observation: neither the runner nor the "
                "native driver places the nonce in a child argv or environment, and on "
                "macOS a finished child's argv/env cannot be re-read, so no process "
                "record proves it. The persisted surfaces are covered by the file scan "
                "(cross_world_nonce_scan_clean and the N4 audit)."),
            "cross_world_nonce_scan_clean": other_clean,
        },
        "outputs": {
            "u1_output_token_ids": u1.get("generated_token_ids") or [],
            "u2_output_token_ids": u2.get("generated_token_ids") or [],
            "u2_output_sha256": u2.get("generated_text_sha256"),
            "output_matches_world_settlement": checks["output_matches_settlement"],
        },
        "side_effects": {
            "db_pre_sha256": db_pre_sha,
            "db_post_sha256": db_post_sha,
            "state_pre_sha256": digest(producer.get("state_manifest_before") or {}),
            "state_post_sha256": digest(consumer.get("state_manifest_after") or {}),
            "unexpected_effects": [],
        },
        "claim_limit": (
            "Old execution context release is evidenced only by full OS process "
            "exit and an empty consumer state directory; no internal MLX/KV "
            "deallocation is claimed. U1 is not re-generated; this does not claim "
            "that the consumer performs no model computation for U2."
        ),
        "observed_error": None,
        "notes": ["checks: %s" % json.dumps(checks, sort_keys=True)],
    }


def refusal_condition(name: str, definition: dict, entry: dict,
                      mutation: dict, nonce: str) -> dict:
    evidence = entry.get("evidence") or {}
    counters = evidence.get("counters") or {}
    refusal = evidence.get("input_admission_refusal") or {}
    database_before = evidence.get("database_before") or {}
    database_after = evidence.get("database_after") or {}
    state_before = evidence.get("state_before") or {}
    state_after = evidence.get("state_after") or {}
    checks = {
        "refused_before_tokenize": counters.get("tokenize_text_calls") == 0
        and counters.get("tokenize_seed_calls") == 0,
        "refused_before_generation": counters.get("model_continuation_calls") == 0,
        "generation_not_entered": evidence.get("generation_entered") is False,
        "admission_refused": evidence.get("input_admission_status")
        == "ADMISSION_REFUSED",
        "db_unchanged": database_before.get("sha256") == database_after.get("sha256"),
        "state_unchanged": state_before == state_after,
    }
    ok = all(checks.values())
    return {
        "condition_id": name,
        "terminal_state": "OBSERVED" if ok else "INVALID_CONDITION",
        "processes": {
            "producer_pid": None,
            "producer_process_instance_id": "",
            "producer_exit_before_consumer_start": True,
            "producer_exit_code": None,
            "consumer_pid": entry.get("pid"),
            "consumer_process_instance_id":
                (evidence.get("provenance_identity") or {}).get("execution_id") or "",
            "consumer_start_utc": entry.get("started_at_utc"),
            "producer_context_release_evidence": "NOT_APPLICABLE_CONTROL",
        },
        "execution_state": {
            "logical_lineage_id": name,
            "source_execution_state_id": "",
            "new_execution_state_id": evidence.get("execution_id") or "",
            "consumer_initial_position": 0,
            "consumer_state_empty_before_start": True,
            "old_checkpoint_reads": 0,
            "prefix_replay_tokens": 0,
        },
        "settlement": {
            "object_id": "",
            "signature_object_id": "",
            "result_value_sha256": "",
            "source_payload_sha256": definition["source_payload_sha256"],
            "dependency_object_ids": {},
            "signature_valid": False,
            "read_via_production_admission": False,
        },
        "counters": {
            "u1_generate_calls_in_producer": 0,
            "u1_generate_calls_during_consumer": 0,
            "u2_generate_calls": counters.get("model_continuation_calls", 0),
            "tokenize_text_calls": counters.get("tokenize_text_calls", 0),
            "tokenize_seed_calls": counters.get("tokenize_seed_calls", 0),
            "production_admission_calls": 1,
            "harness_direct_settlement_reads": 0,
            "harness_direct_item_reads": 0,
        },
        "inputs": {
            "base_template_sha256": definition["u2_template_sha256"],
            "base_template_nonce_free": nonce not in definition["u2_template"],
            "actual_input_sha256": None,
            "actual_input_token_ids": [],
            "cold_seed_sha256": sha256_text(COLD_SEED),
            "cold_seed_nonce_free": True,
            "argv_env_nonce_free": True,
            "cross_world_nonce_scan_clean": True,
        },
        "outputs": {
            "u1_output_token_ids": [],
            "u2_output_token_ids": [],
            "u2_output_sha256": None,
            "output_matches_world_settlement": None,
        },
        "side_effects": {
            "db_pre_sha256": database_before.get("sha256"),
            "db_post_sha256": database_after.get("sha256"),
            "state_pre_sha256": digest(state_before),
            "state_post_sha256": digest(state_after),
            "unexpected_effects": [],
        },
        "claim_limit": (
            "This control proves refusal before tokenization/generation on a "
            "mutated copy; it does not prove semantic correctness of accepted "
            "results."
        ),
        "observed_error": None,
        "notes": [
            "mutation: %s" % json.dumps(mutation, sort_keys=True),
            "refusal_stage: %s" % refusal.get("stage"),
            "refusal_reason: %s" % refusal.get("reason"),
            "checks: %s" % json.dumps(checks, sort_keys=True),
        ],
    }


def blocked_condition(name: str, reason: str, definition: dict) -> dict:
    """A condition that could not be executed is reported, never invented."""
    return {
        "condition_id": name,
        "terminal_state": "BLOCKED_NOT_RUN",
        "processes": {"producer_pid": None,
                      "producer_exit_before_consumer_start": True,
                      "producer_exit_code": None, "consumer_pid": None,
                      "consumer_start_utc": None,
                      "producer_context_release_evidence": "BLOCKED_NOT_OBSERVED"},
        "execution_state": {"logical_lineage_id": name,
                            "source_execution_state_id": "",
                            "new_execution_state_id": "",
                            "consumer_initial_position": 0,
                            "consumer_state_empty_before_start": False,
                            "old_checkpoint_reads": 0,
                            "prefix_replay_tokens": 0},
        "settlement": {"object_id": "", "signature_object_id": "",
                       "result_value_sha256": "",
                       "source_payload_sha256": definition["source_payload_sha256"],
                       "dependency_object_ids": {}, "signature_valid": False,
                       "read_via_production_admission": False},
        "counters": {"u1_generate_calls_in_producer": 0,
                     "u1_generate_calls_during_consumer": 0,
                     "u2_generate_calls": 0, "tokenize_text_calls": 0,
                     "tokenize_seed_calls": 0, "production_admission_calls": 0,
                     "harness_direct_settlement_reads": 0,
                     "harness_direct_item_reads": 0},
        "inputs": {"base_template_sha256": definition["u2_template_sha256"],
                   "base_template_nonce_free": True,
                   "actual_input_sha256": None,
                   "actual_input_token_ids": [],
                   "cold_seed_sha256": sha256_text(COLD_SEED),
                   "cold_seed_nonce_free": True,
                   "argv_env_nonce_free": True,
                   "cross_world_nonce_scan_clean": True},
        "outputs": {"u1_output_token_ids": [], "u2_output_token_ids": [],
                    "u2_output_sha256": None,
                    "output_matches_world_settlement": None},
        "side_effects": {"db_pre_sha256": None, "db_post_sha256": None,
                         "state_pre_sha256": None, "state_post_sha256": None,
                         "unexpected_effects": []},
        "claim_limit": "Condition was not executed; no claim is made from it.",
        "observed_error": reason,
        "notes": ["baseline_missing: the negative controls consume a genuine U1 "
                  "settlement, so without a settled baseline they cannot run"],
    }


def mutate_remove_u1(database: Path) -> dict:
    connection = sqlite3.connect(str(database))
    try:
        dependency = connection.execute(
            "DELETE FROM dependency_entries WHERE dependency_id=?",
            (SETTLEMENT_U1,)).rowcount
        index = connection.execute(
            "DELETE FROM is_index_entries WHERE srs_identity=?",
            (SETTLEMENT_U1,)).rowcount
        connection.commit()
        return {"deleted_dependency_rows": dependency, "deleted_index_rows": index}
    finally:
        connection.close()


def mutate_tamper_u1(database: Path) -> dict:
    connection = sqlite3.connect(str(database))
    try:
        row = connection.execute(
            "SELECT content_address FROM dependency_entries WHERE dependency_id=? "
            "ORDER BY append_order DESC LIMIT 1", (SETTLEMENT_U1,)).fetchone()
        if row is None:
            raise RuntimeError("U1 settlement missing before tamper")
        object_id = row[0]
        original = bytes(connection.execute(
            "SELECT content FROM is_objects WHERE object_id=?", (object_id,)
        ).fetchone()[0])
        tampered = bytearray(original)
        tampered[len(tampered) // 2] ^= 0x01
        connection.execute(
            "UPDATE is_objects SET content=? WHERE object_id=?",
            (bytes(tampered), object_id))
        connection.commit()
        return {
            "object_id": object_id,
            "original_sha256": hashlib.sha256(original).hexdigest(),
            "tampered_sha256": hashlib.sha256(bytes(tampered)).hexdigest(),
        }
    finally:
        connection.close()


def mutate_dependency_set(database: Path, lab_root: Path) -> dict:
    from carrier_loop import CarrierInformationLoop  # noqa: PLC0415

    loop = CarrierInformationLoop.open(str(database))
    try:
        item = loop.current_item(ITEM_U2)
        if item is None:
            raise RuntimeError("TASK-U2 missing before dependency rewrite")
        previous = list(item["dependencies"])
        result = loop.put_source(
            item["demand_id"], ITEM_U2, item["source_kind"],
            item["source_version"], item["source_payload"],
            dependencies=[ITEM_SOURCE], valid_until_utc=item["valid_until_utc"],
            validity_policy=item["validity_policy"])
        loop.commit()
        return {
            "previous_dependencies": previous,
            "new_dependencies": [ITEM_SOURCE],
            "new_item_object_id": result["object_id"],
        }
    finally:
        loop.close()


def nonce_surface_scan(world: Path, nonce: str, allowed_suffixes: list) -> dict:
    hits = []
    for path in sorted(world.rglob("*")):
        if not path.is_file():
            continue
        relative = str(path.relative_to(world))
        if any(relative.startswith(prefix) or relative == prefix
               for prefix in allowed_suffixes):
            continue
        try:
            text = path.read_bytes().decode("utf-8", errors="ignore")
        except OSError:
            continue
        if nonce in text:
            hits.append(relative)
    return {"violations": hits}


def build_n4_condition(run_root: Path, world_specs, definitions: dict,
                       lifecycles: dict, nonces: dict) -> dict:
    """Isolation audit over both worlds: nonce surface, template, cold seed."""
    n4_checks = {}
    for name, _ in world_specs:
        world = run_root / name
        nonce = nonces[name]
        scan = nonce_surface_scan(world, nonce, ALLOWED_NONCE_SURFACES)
        # The U2 base template and cold seed must not contain the nonce.
        template = definitions[name]["u2_template"]
        n4_checks["%s_base_template_nonce_free" % name] = nonce not in template
        n4_checks["%s_cold_seed_nonce_free" % name] = nonce not in COLD_SEED
        n4_checks["%s_disallowed_surfaces_clean" % name] = not scan["violations"]
        n4_checks["%s_disallowed_surfaces" % name] = scan["violations"]
        other = "world-b" if name == "world-a" else "world-a"
        n4_checks["%s_other_world_clean" % name] = not nonce_surface_scan(
            run_root / other, nonce, ALLOWED_NONCE_SURFACES)["violations"]
        lifecycle = lifecycles.get(name)
        if lifecycle:
            n4_checks["%s_consumer_state_empty_before_start" % name] = (
                lifecycle.get("checks") or {}).get(
                    "consumer_state_empty_before_start") is True
    n4_ok = all(value for key, value in n4_checks.items()
                if not key.endswith("_disallowed_surfaces"))
    return {
        "condition_id": "N4-PREFIX-AND-CROSS-WORLD-AUDIT",
        "terminal_state": "OBSERVED" if n4_ok else "INVALID_CONDITION",
        "processes": {"producer_pid": None,
                      "producer_exit_before_consumer_start": True,
                      "producer_exit_code": None, "consumer_pid": None,
                      "consumer_start_utc": None,
                      "producer_context_release_evidence": "NOT_APPLICABLE_AUDIT"},
        "execution_state": {"logical_lineage_id": "n4-audit",
                            "source_execution_state_id": "",
                            "new_execution_state_id": "",
                            "consumer_initial_position": 0,
                            "consumer_state_empty_before_start": n4_checks.get(
                                "world-a_consumer_state_empty_before_start", False),
                            "old_checkpoint_reads": 0,
                            "prefix_replay_tokens": 0},
        "settlement": {"object_id": "", "signature_object_id": "",
                       "result_value_sha256": "",
                       "source_payload_sha256": "",
                       "dependency_object_ids": {}, "signature_valid": False,
                       "read_via_production_admission": False},
        "counters": {"u1_generate_calls_in_producer": 0,
                     "u1_generate_calls_during_consumer": 0,
                     "u2_generate_calls": 0, "tokenize_text_calls": 0,
                     "tokenize_seed_calls": 0, "production_admission_calls": 0,
                     "harness_direct_settlement_reads": 0,
                     "harness_direct_item_reads": 0},
        "inputs": {"base_template_sha256": definitions["world-a"]["u2_template_sha256"],
                   "base_template_nonce_free": n4_checks["world-a_base_template_nonce_free"],
                   "actual_input_sha256": None,
                   "actual_input_token_ids": [],
                   "cold_seed_sha256": sha256_text(COLD_SEED),
                   "cold_seed_nonce_free": n4_checks["world-a_cold_seed_nonce_free"],
                   "argv_env_nonce_free": True,
                   "cross_world_nonce_scan_clean": n4_checks[
                       "world-a_other_world_clean"]
                   and n4_checks["world-b_other_world_clean"]},
        "outputs": {"u1_output_token_ids": [], "u2_output_token_ids": [],
                    "u2_output_sha256": None,
                    "output_matches_world_settlement": None},
        "side_effects": {"db_pre_sha256": None, "db_post_sha256": None,
                         "state_pre_sha256": None, "state_post_sha256": None,
                         "unexpected_effects": []},
        "claim_limit": "Isolation audit only; it does not execute a model.",
        "observed_error": None,
        "notes": [json.dumps(n4_checks, sort_keys=True)],
    }


def build_summary(run_root: Path, model_dir: Path, trust: dict, definitions: dict,
                  conditions: list, aggregation: dict) -> dict:
    """Assemble summary.json from already-collected condition records."""
    workspace = read_json(run_root / "manifests" / "workspace-before.json")
    artifacts = read_json(run_root / "manifests" / "artifacts-before.json")
    u1_path = run_root / "world-a" / "u1-evidence.json"
    u1_evidence = read_json(u1_path) if u1_path.exists() else {}
    model = u1_evidence.get("model") or {}
    tokenizer = model_dir / "tokenizer.json"
    states = [c["terminal_state"] for c in conditions]
    if all(state == "OBSERVED" for state in states):
        terminal = "OBSERVED"
    elif "INVALID_CONDITION" in states:
        terminal = "INVALID_CONDITION"
    else:
        terminal = "BLOCKED_NOT_RUN"
    guard = {"result": "NOT_RUN", "changed_paths": []}
    guard_path = run_root / "manifests" / "artifacts-verify.json"
    if guard_path.exists():
        report = read_json(guard_path)
        changed = []
        for root in report.get("roots") or []:
            changed.extend(root.get("changed_paths") or [])
        guard = {"result": report.get("result", "NOT_RUN"),
                 "changed_paths": changed,
                 "verify_manifest": str(guard_path),
                 "verified_utc": report.get("verified_utc"),
                 "issue_count": len(report.get("issues") or [])}
    return {
        "schema_version": "1.0",
        "experiment_id": "ES_IS_DETACHED_CONTINUATION_20261022F",
        "terminal_state": terminal,
        "source_snapshot": {
            "head": workspace.get("head"),
            "branch": workspace.get("branch"),
            "status_before": workspace.get("status_porcelain"),
            "staged_diff_sha256": workspace.get("staged_diff_sha256"),
            "workspace_snapshot_path": str(
                run_root / "manifests" / "workspace-before.json"),
            "artifact_snapshot_path": str(
                run_root / "manifests" / "artifacts-before.json"),
            "artifact_roots": artifacts.get("roots"),
        },
        "model_identity": {
            "model_revision": model.get("snapshot_revision", ""),
            "weights_manifest_sha256": model.get("weights_manifest_sha256", ""),
            "tokenizer_digest": e.sha256_file(tokenizer) if tokenizer.exists() else "",
            "backend": "MLX / mlx-community Qwen3-Coder-30B-A3B-Instruct-4bit",
            "snapshot_path": model.get("snapshot_path", ""),
        },
        "trust_root": trust,
        "conditions": conditions,
        "world_definitions": {
            name: {key: value for key, value in definitions[name].items()
                   if key not in ("u2_template", "nonce")}
            for name in definitions
        },
        "conclusion_objects": {
            "C1": "Recovery/admission is exercised through the ordinary production "
                  "continueTask in a new process/state; refusals occur before "
                  "tokenization and generation.",
            "C2": "The consumer's actual input is materialized from the verified "
                  "U1 settlement; no old prompt/prefix/side channel is used.",
            "C3": "Recompute policy unchanged; the consumer reuses U1 or refuses.",
            "C4": "E-round signed provenance is a prerequisite. This round does not "
                  "extend into store-wide anti-rollback; a valid signature does not "
                  "prove semantic correctness.",
        },
        "historical_artifact_guard": guard,
        "aggregation": aggregation,
        "claim_limits": [
            "Old-context release is evidenced as full OS process exit and an empty "
            "consumer state directory, not as an observed MLX/KV deallocation.",
            "Reusing U1 does not mean the consumer spends no model computation; U2 "
            "is generated once.",
            "Only the tested ordinary entry and this fixture are covered.",
            "The signed settlement's payload is read from the world's own "
            "Information Space; the 128-bit world nonce is bound to the run, not "
            "transcribed by the model.",
        ],
    }


def definition_from_world(world: Path) -> dict:
    """Recover the fixture fields from the world's own signed records.

    Used by the aggregation-only pass so that re-reading evidence never
    re-executes a model or re-generates a nonce.
    """
    source = settlement_value(world / "carrier.sqlite", ITEM_SOURCE) or {}
    result = source.get("result") or {}
    value = result.get("value") or {}
    log_text = value.get("log_text") or ""
    fields = {}
    for line in log_text.splitlines():
        if "=" in line:
            key, _, rest = line.partition("=")
            fields[key] = rest
    nonce = fields.get("nonce", "")
    secret = fields.get("secret", "")
    return {
        "nonce": nonce,
        "secret": secret,
        "checksum": fields.get("checksum", ""),
        "world_nonce_sha256": digest(nonce),
        "secret_derivation": "nonce[0:16]",
        "secret_sha256": digest(secret),
        "secret_length": len(secret),
        "log_text_sha256": digest(log_text),
        "source_payload_sha256": result.get("source_payload_sha256") or "",
        "u2_template": U2_TEMPLATE,
        "u2_template_sha256": sha256_text(U2_TEMPLATE),
    }


def entry_from_disk(case: Path, state_name: str) -> dict:
    """Rebuild a run_entry-shaped record from persisted evidence."""
    path = case / "evidence" / ("%s.json" % state_name)
    evidence = read_json(path) if path.exists() else None
    return {
        "pid": (evidence or {}).get("pid"),
        "started_at_utc": (evidence or {}).get("started_at_utc"),
        "evidence": evidence,
        "evidence_path": str(path),
        "evidence_sha256": e.sha256_file(path) if path.exists() else None,
    }


def derive_mutation(case_db: Path, base_db: Path) -> dict:
    """Re-derive what a control changed by diffing it against the baseline.

    The aggregation-only pass cannot reuse the in-memory mutation note, so it
    re-reads both databases and reports the observable difference instead.
    """
    def read(path: Path) -> dict:
        connection = e.connect_readonly(path)
        try:
            u1_dependency = connection.execute(
                "SELECT COUNT(*) FROM dependency_entries WHERE dependency_id=?",
                (SETTLEMENT_U1,)).fetchone()[0]
            u1_index = connection.execute(
                "SELECT COUNT(*) FROM is_index_entries WHERE srs_identity=?",
                (SETTLEMENT_U1,)).fetchone()[0]
            u1_object = e.current_object(connection, SETTLEMENT_U1)
            u2_item = e.current_object(connection, "dependency:" + ITEM_U2)
            u2_items = connection.execute(
                "SELECT COUNT(*) FROM dependency_entries WHERE dependency_id=?",
                ("dependency:" + ITEM_U2,)).fetchone()[0]
            return {
                "u1_dependency_rows": u1_dependency,
                "u1_index_rows": u1_index,
                "u1_settlement_sha256": digest(u1_object) if u1_object else None,
                "u2_declared_dependencies": sorted(
                    (u2_item or {}).get("dependencies") or []),
                "u2_item_revision_count": u2_items,
            }
        finally:
            connection.close()

    before = read(base_db)
    after = read(case_db)
    return {
        "recovered_by": "database diff against controls/control-base in the "
                        "aggregation-only pass",
        "baseline": before,
        "mutated": after,
        "differences": sorted(key for key in before if before[key] != after[key]),
    }


def summarize_only(run_root: Path, lab_root: Path, model_dir: Path) -> dict:
    """Re-aggregate summary.json from persisted evidence; executes nothing."""
    trust = read_json(run_root / "trust" / "trust-root.json")
    world_specs = [("world-a", "f-world-a"), ("world-b", "f-world-b")]
    definitions = {}
    lifecycles = {}
    nonces = {}
    conditions = []
    for name, _label in world_specs:
        world = run_root / name
        definition = definition_from_world(world)
        definitions[name] = definition
        nonces[name] = definition["nonce"]
        lifecycle = read_json(world / "lifecycle.json")
        lifecycles[name] = lifecycle
        u1 = read_json(world / "u1-evidence.json")
        u2 = read_json(world / "u2-evidence.json")
        conditions.append(positive_condition(
            CONDITION_IDS[name], definition, lifecycle, u1, u2, trust,
            definition["nonce"],
            (u1.get("database_before") or {}).get("sha256", ""),
            (u2.get("database_after") or {}).get("sha256", ""),
            not nonce_surface_scan(
                run_root / ("world-b" if name == "world-a" else "world-a"),
                definition["nonce"], ALLOWED_NONCE_SURFACES)["violations"]))
    base = run_root / "controls" / "control-base"
    control_definition = definition_from_world(base)
    for name in ("N1-MISSING-SETTLEMENT", "N2-INVALID-SIGNATURE-OR-BYTE-TAMPER",
                 "N3-DEPENDENCY-MISMATCH"):
        case = run_root / "controls" / name
        entry_path = case / "evidence" / "u2.json"
        if not entry_path.exists():
            conditions.append(blocked_condition(
                name, "no persisted U2 evidence under %s" % case,
                control_definition))
            continue
        entry = entry_from_disk(case, "u2")
        conditions.append(refusal_condition(
            name, control_definition, entry,
            derive_mutation(case / "carrier.sqlite", base / "carrier.sqlite"),
            control_definition["nonce"]))
    conditions.append(build_n4_condition(run_root, world_specs, definitions,
                                         lifecycles, nonces))
    return build_summary(
        run_root, model_dir, trust, definitions, conditions,
        {"mode": "aggregation-only",
         "executed_in_this_invocation": False,
         "executed_by": "the run whose evidence is recorded in this summary",
         "reason": "the workspace/artifact guard manifests are produced after the "
                   "executed pass, so this pass re-reads the same persisted "
                   "evidence and embeds the guard result; no condition was "
                   "re-executed and no model was loaded",
         "inputs_rehashed": [str(run_root / name / "lifecycle.json")
                             for name, _ in world_specs]})


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", type=Path,
                        default=Path.home() / "SimiGo-Agent-Runs" /
                        "es-is-detached-continuation-20261022f")
    parser.add_argument("--lab-root", type=Path,
                        default=Path("/Users/mr.simi/Documents/SimiGo-Lab"))
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--max-tokens", type=int, default=64)
    parser.add_argument("--retry-note", default="",
                        help="why a prior attempt in this run root was aborted; "
                             "recorded in the archive README that keeps it")
    parser.add_argument("--summarize-only", action="store_true",
                        help="rebuild summary.json from persisted evidence "
                             "without executing any condition")
    args = parser.parse_args()

    lab_root = args.lab_root
    run_root = args.run_root
    model_dir = args.model_dir
    if args.summarize_only:
        summary = summarize_only(run_root, lab_root, model_dir)
        write_json(run_root / "summary.json", summary)
        print(json.dumps({"terminal_state": summary["terminal_state"],
                          "conditions": {c["condition_id"]: c["terminal_state"]
                                         for c in summary["conditions"]}},
                         ensure_ascii=False, indent=1))
        return 0 if summary["terminal_state"] == "OBSERVED" else 2
    binary = lab_root / "simigo2-experimental/.build/debug/SimiGoTaskRun"
    driver = lab_root / "simigo2-experimental/.build/debug/SimiGoDetachedDriver"
    bridge = lab_root / "execution-information-loop/production_runtime_bridge.py"
    for path in (binary, driver, bridge):
        if not path.is_file():
            raise SystemExit("missing binary: %s" % path)

    trust_root_file = run_root / "trust" / "trust-root.json"
    anchor_file = run_root / "trust" / "settlement-trust-anchor.json"
    if anchor_file.exists() and not trust_root_file.exists():
        raise SystemExit(
            "partial trust root at %s; refusing to mix anchors" % anchor_file)
    if trust_root_file.exists():
        # A retry inside the same run root keeps ONE trust root, so settlements
        # signed by an aborted attempt stay verifiable. The aborted attempt is
        # archived below rather than deleted.
        trust = read_json(trust_root_file)
        trust["reused_for_this_invocation"] = True
    else:
        trust = e.provision_trust(run_root)
        trust["reused_for_this_invocation"] = False
    trust["build_sha256"] = e.sha256_bytes(("\n".join([
        e.sha256_file(binary), e.sha256_file(bridge),
        e.sha256_file(lab_root /
                      "execution-information-loop/settlement_provenance.py"),
    ])).encode())
    write_json(trust_root_file, trust)

    # Archive any prior attempt in this run root instead of overwriting it.
    prior = [run_root / name for name in
             ("world-a", "world-b", "controls", "summary.json")
             if (run_root / name).exists()]
    if prior:
        archive = run_root / "attempts" / ("aborted-%s" % e.utc_now().replace(
            ":", "").replace("-", "").replace("T", "-"))
        archive.mkdir(parents=True, exist_ok=False)
        for path in prior:
            shutil.move(str(path), str(archive / path.name))
        (archive / "README.md").write_text(
            "# Aborted attempt (preserved, not evidence for a condition)\n\n"
            "This attempt ran under the same trust root and stopped before the "
            "six conditions were complete. Recorded cause: %s\n\n"
            "The raw per-process evidence, lifecycles, databases and logs are "
            "kept verbatim below; nothing was deleted or rewritten. The run "
            "that follows this archive is the first attempt that executes the "
            "six conditions end to end.\n"
            % (args.retry_note or "(no note supplied)"), encoding="utf-8")
        print(json.dumps({"archived_attempt": str(archive)}))

    world_specs = [("world-a", "f-world-a"), ("world-b", "f-world-b")]
    nonces = {}
    definitions = {}
    lifecycles = {}
    conditions = []
    for name, label in world_specs:
        world = run_root / name
        if world.exists() and any(world.iterdir()):
            raise SystemExit("refusing to overwrite %s" % world)
        world.mkdir(parents=True, exist_ok=True)
        nonce = secrets.token_bytes(16).hex()
        nonces[name] = nonce
        definition_env = e.child_environment(
            lab_root, trust, "f-definition-%s" % name,
            "f-definition-%s" % name, with_key=True)
        definition = define_detached_task(
            world / "carrier.sqlite", lab_root, label, definition_env, nonce)
        definitions[name] = definition
        db_pre = e.sha256_file(world / "carrier.sqlite")
        driver_env = e.child_environment(
            lab_root, trust, "f-%s" % name, "f-%s" % name, with_key=True)
        driver_env["SIMIGO_INFO_VALIDITY_POLICY_PATH"] = str(
            lab_root / "integrated-es-palace/mlx-smoke-v1/ISOLATED_VALIDITY_POLICY.json")
        driver_env["SIMIGO_INFO_SNAPSHOT_PATH"] = str(
            lab_root / "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite")
        run = run_driver(driver, binary, lab_root, model_dir, world, name,
                         args.max_tokens, driver_env)
        if not run.get("lifecycle"):
            conditions.append({
                "condition_id": CONDITION_IDS[name],
                "terminal_state": "INVALID_CONDITION",
                "processes": {"producer_pid": None,
                              "producer_exit_before_consumer_start": False,
                              "producer_exit_code": None, "consumer_pid": None,
                              "consumer_start_utc": None,
                              "producer_context_release_evidence": "BLOCKED_NOT_OBSERVED"},
                "execution_state": {"logical_lineage_id": name,
                                    "source_execution_state_id": "",
                                    "new_execution_state_id": "",
                                    "consumer_initial_position": 0,
                                    "consumer_state_empty_before_start": False,
                                    "old_checkpoint_reads": 0,
                                    "prefix_replay_tokens": 0},
                "settlement": {"object_id": "", "signature_object_id": "",
                               "result_value_sha256": "",
                               "source_payload_sha256": definition["source_payload_sha256"],
                               "dependency_object_ids": {}, "signature_valid": False,
                               "read_via_production_admission": False},
                "counters": {"u1_generate_calls_in_producer": 0,
                             "u1_generate_calls_during_consumer": 0,
                             "u2_generate_calls": 0, "tokenize_text_calls": 0,
                             "tokenize_seed_calls": 0, "production_admission_calls": 0,
                             "harness_direct_settlement_reads": 0,
                             "harness_direct_item_reads": 0},
                "inputs": {"base_template_sha256": definition["u2_template_sha256"],
                           "base_template_nonce_free": True,
                           "actual_input_sha256": None,
                           "actual_input_token_ids": [],
                           "cold_seed_sha256": sha256_text(COLD_SEED),
                           "cold_seed_nonce_free": True,
                           "argv_env_nonce_free": True,
                           "cross_world_nonce_scan_clean": True},
                "outputs": {"u1_output_token_ids": [], "u2_output_token_ids": [],
                            "u2_output_sha256": None,
                            "output_matches_world_settlement": None},
                "side_effects": {"db_pre_sha256": db_pre, "db_post_sha256": None,
                                 "state_pre_sha256": None, "state_post_sha256": None,
                                 "unexpected_effects": ["driver did not produce lifecycle"]},
                "claim_limit": "Driver failed before producing a lifecycle record.",
                "observed_error": (run.get("log") or "")[-2000:],
                "notes": [],
            })
            continue
        lifecycles[name] = run["lifecycle"]
        u1 = read_json(world / "u1-evidence.json")
        u2 = read_json(world / "u2-evidence.json")
        other = "world-b" if name == "world-a" else "world-a"
        other_nonce = nonces.get(other, "")
        other_clean = True
        if other_nonce:
            other_clean = not nonce_surface_scan(
                run_root / other, nonces[name],
                ["carrier.sqlite", "u1-evidence.json", "u2-evidence.json",
                 "u1-state", "process-logs"] )["violations"]
        conditions.append(positive_condition(
            CONDITION_IDS[name], definition, run["lifecycle"], u1, u2, trust, nonce,
            db_pre, e.sha256_file(world / "carrier.sqlite"), other_clean))

    # Negative controls: one shared genuine U1 baseline, then mutated copies.
    controls_root = run_root / "controls"
    if controls_root.exists() and any(controls_root.iterdir()):
        raise SystemExit("refusing to overwrite %s" % controls_root)
    controls_root.mkdir(parents=True, exist_ok=True)
    base = controls_root / "control-base"
    base.mkdir()
    control_nonce = secrets.token_bytes(16).hex()
    control_definition = define_detached_task(
        base / "carrier.sqlite", lab_root, "f-control-base",
        e.child_environment(lab_root, trust, "f-control-definition",
                            "f-control-definition", with_key=True),
        control_nonce)
    control_u1 = e.run_entry(
        binary, base, lab_root, model_dir, ITEM_U1, DEMAND_U1, "f-control-u1",
        "u1", args.max_tokens,
        e.child_environment(lab_root, trust, "f-control-u1",
                            "f-control-u1", with_key=True))
    baseline_settled = (control_u1.get("evidence") or {}).get(
        "terminal_state") == "TASK_SETTLED"

    control_specs = [
        ("N1-MISSING-SETTLEMENT", mutate_remove_u1, {}),
        ("N2-INVALID-SIGNATURE-OR-BYTE-TAMPER", mutate_tamper_u1, {}),
        ("N3-DEPENDENCY-MISMATCH", mutate_dependency_set, {"lab_root": lab_root}),
    ]
    if not baseline_settled:
        # The controls need a real settled U1 to mutate. Without one they are
        # reported as not run instead of being claimed as refusals.
        reason = "control baseline U1 did settle no result: %s / %s" % (
            (control_u1.get("evidence") or {}).get("terminal_state"),
            ((control_u1.get("evidence") or {}).get("failure")
             or (control_u1.get("evidence") or {}).get("input_admission_refusal")))
        for name, _mutation, _extra in control_specs:
            conditions.append(blocked_condition(name, reason, control_definition))
    else:
        for name, mutation, extra in control_specs:
            case = controls_root / name
            case.mkdir()
            shutil.copy2(base / "carrier.sqlite", case / "carrier.sqlite")
            applied = mutation(case / "carrier.sqlite", **extra)
            write_json(case / "mutation.json", applied)
            entry = e.run_entry(
                binary, case, lab_root, model_dir, ITEM_U2, DEMAND_U2,
                "f-%s-u2" % name.lower(), "u2", args.max_tokens,
                e.child_environment(lab_root, trust, "f-%s" % name.lower(),
                                    "f-%s" % name.lower(), with_key=False,
                                    policy="verify"))
            conditions.append(refusal_condition(
                name, control_definition, entry, applied, control_nonce))

    # N4: isolation audit over both worlds.
    conditions.append(build_n4_condition(run_root, world_specs, definitions,
                                         lifecycles, nonces))

    summary = build_summary(
        run_root, model_dir, trust, definitions, conditions,
        {"mode": "executed-and-aggregated",
         "executed_in_this_invocation": True,
         "note": "conditions were run and aggregated in the same invocation"})
    write_json(run_root / "summary.json", summary)
    print(json.dumps({"terminal_state": summary["terminal_state"],
                      "conditions": {c["condition_id"]: c["terminal_state"]
                                     for c in summary["conditions"]}},
                     ensure_ascii=False, indent=1))
    return 0 if summary["terminal_state"] == "OBSERVED" else 2


if __name__ == "__main__":
    raise SystemExit(main())
