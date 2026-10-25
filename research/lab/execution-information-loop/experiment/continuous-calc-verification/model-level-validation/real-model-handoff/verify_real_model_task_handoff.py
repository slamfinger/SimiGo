#!/usr/bin/env python3
"""Verify the real-model ES -> IS -> fresh-ES handoff from authoritative records.

Every criterion is decided from: the two stage evidence files written by the
real-model process, the physical SQLite Information Space file, and a
model-free dependency-closure probe run on a consistent COPY of that file.

Physical KV reuse is NOT claimed here. The production continuation path
replays the token prefix (`cache: nil`), so `prefix_replay_tokens` is recorded
as UNPROVEN for physical reuse and PASS only for logical settled-work reuse.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

CONTINUATION_POINT = "bounded-production-runtime-integration"
SOURCE_ID = "TASK-SOURCE"
U1_ID = "TASK-U1"
U2_ID = "TASK-U2"
U2_DEMAND = "handoff-u2"


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical(value) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def digest(value) -> str:
    return sha256_hex(canonical(value))


def is_sha256_name(value: str) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def process_alive(pid: int) -> bool:
    """True unless the kernel reports that no such process exists."""
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def physical_identity(path: Path) -> dict:
    info = path.stat()
    return {
        "device": str(info.st_dev),
        "inode": str(info.st_ino),
        "size_bytes": info.st_size,
        "sha256": sha256_hex(path.read_bytes()),
    }


def resolve_snapshot(model: dict) -> dict:
    """Re-derive the model identity independently of the stage evidence.

    Weight identity comes from the symlink's blob file name (a git-lfs content
    sha256) and from the blob's real size. `attributesOfItem` in the stage CLI
    recorded the symlink length, so the verifier reads sizes through `stat`.
    """
    snapshot = Path(model["snapshot_path"])
    weights = []
    content_lines = []
    total = 0
    for url in sorted(snapshot.glob("*.safetensors")):
        blob = Path(os.readlink(url)).name
        if not is_sha256_name(blob):
            raise ValueError("%s is not linked to a sha256 blob name" % url.name)
        resolved = url.resolve(strict=True)
        size = resolved.stat().st_size
        weights.append({
            "name": url.name,
            "content_sha256": blob,
            "blob_size_bytes": size,
            "blob_path": str(resolved),
        })
        content_lines.append("%s:%s" % (url.name, blob))
        total += size
    identity_files = {}
    for name in [
        "config.json",
        "tokenizer.json",
        "tokenizer_config.json",
        "model.safetensors.index.json",
    ]:
        path = snapshot / name
        identity_files[name] = sha256_hex(path.read_bytes()) if path.exists() else None
    return {
        "snapshot_path": str(snapshot),
        "snapshot_revision": snapshot.name,
        "weight_files": weights,
        "total_weight_bytes": total,
        "content_manifest_sha256": sha256_hex(
            "\n".join(content_lines).encode("utf-8")
        ),
        "identity_file_sha256": identity_files,
    }


def decoded_prefix(entry: dict) -> list[int]:
    payload = entry.get("payload", {})
    return json.loads(base64.b64decode(payload["data"]))["tokenPrefix"]


class Checks:
    def __init__(self) -> None:
        self.items: list[dict] = []

    def add(self, criterion: str, name: str, passed: bool, detail=None) -> None:
        self.items.append({
            "criterion": criterion,
            "name": name,
            "passed": bool(passed),
            "detail": detail,
        })

    def equal(self, criterion: str, name: str, actual, expected) -> None:
        self.add(criterion, name, actual == expected, {"actual": actual, "expected": expected})

    def truth(self, criterion: str, name: str, value, detail=None) -> None:
        self.add(criterion, name, bool(value), detail)

    def criteria(self) -> dict[str, str]:
        result: dict[str, str] = {}
        for item in self.items:
            key = item["criterion"]
            if key not in result:
                result[key] = "PASS"
            if not item["passed"]:
                result[key] = "FAIL"
        return result


def open_readonly(database: Path) -> sqlite3.Connection:
    connection = sqlite3.connect(
        database.resolve().as_uri() + "?mode=ro", uri=True
    )
    connection.row_factory = sqlite3.Row
    return connection


def read_object(connection: sqlite3.Connection, object_id: str) -> dict:
    row = connection.execute(
        "SELECT content FROM is_objects WHERE object_id=?", (object_id,)
    ).fetchone()
    if row is None:
        raise KeyError("missing carrier object: %s" % object_id)
    content = bytes(row["content"])
    if sha256_hex(content) != object_id:
        raise ValueError("carrier object bytes do not match its address: %s" % object_id)
    return json.loads(content)


def current_object(connection: sqlite3.Connection, identity: str) -> tuple[str, dict] | None:
    row = connection.execute(
        "SELECT record_object FROM is_index_entries WHERE srs_identity=? "
        "ORDER BY append_order DESC LIMIT 1",
        (identity,),
    ).fetchone()
    if row is None:
        return None
    return row["record_object"], read_object(connection, row["record_object"])


def settlement(connection: sqlite3.Connection, item_id: str) -> dict | None:
    found = current_object(connection, "settlement:%s" % item_id)
    if found is None:
        return None
    object_id, value = found
    value["_object_id"] = object_id
    return value


def execution_states(connection: sqlite3.Connection) -> list[dict]:
    rows = connection.execute(
        "SELECT append_order,srs_identity,record_object FROM is_index_entries "
        "WHERE srs_identity LIKE ? ORDER BY append_order ASC",
        ("execution_state:%s:%%" % CONTINUATION_POINT,),
    ).fetchall()
    values = []
    for row in rows:
        value = read_object(connection, row["record_object"])
        value["_identity"] = row["srs_identity"]
        values.append(value)
    return values


def run_bridge(
    python: str, bridge: Path, command: str, arguments: list[str], environment: dict
) -> dict:
    completed = subprocess.run(
        [python, str(bridge), command] + arguments,
        capture_output=True,
        text=True,
        env=environment,
    )
    try:
        payload = json.loads(completed.stdout)
    except json.JSONDecodeError:
        raise RuntimeError(
            "bridge %s produced no JSON: %s" % (command, completed.stderr[-2000:])
        )
    if completed.returncode != 0 or not payload.get("ok"):
        raise RuntimeError(
            "bridge %s failed: %s" % (command, payload.get("error") or payload)
        )
    return payload


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--lab-root", default="/Users/mr.simi/Documents/SimiGo-Lab")
    parser.add_argument("--python", default="/usr/bin/python3")
    args = parser.parse_args()

    run_dir = Path(args.run_dir).resolve()
    lab_root = Path(args.lab_root).resolve()
    bridge = lab_root / "execution-information-loop" / "production_runtime_bridge.py"
    database = run_dir / "carrier.sqlite"
    evidence_dir = run_dir / "evidence"
    stage_a = json.loads((evidence_dir / "stage-a.json").read_text(encoding="utf-8"))
    stage_c = json.loads((evidence_dir / "stage-c.json").read_text(encoding="utf-8"))
    checks = Checks()

    # ---------------- model identity ----------------
    for stage_name, stage in (("stage_a", stage_a), ("stage_c", stage_c)):
        model = stage.get("model", {})
        weights = model.get("weight_files", [])
        checks.truth(
            "model_identity", "%s_snapshot_revision_present" % stage_name,
            isinstance(model.get("snapshot_revision"), str) and len(model["snapshot_revision"]) == 40,
            model.get("snapshot_revision"),
        )
        checks.truth(
            "model_identity", "%s_weights_listed" % stage_name,
            isinstance(weights, list) and len(weights) == 4,
            len(weights) if isinstance(weights, list) else None,
        )
        checks.truth(
            "model_identity", "%s_weight_digests_are_sha256" % stage_name,
            all(
                isinstance(weight.get("content_sha256"), str)
                and len(weight["content_sha256"]) == 64
                and "/" not in weight["content_sha256"]
                for weight in weights
            ),
            [weight.get("content_sha256") for weight in weights],
        )
        for field in [
            "weights_manifest_sha256",
            "tokenizer_json_sha256",
            "config_json_sha256",
            "model_index_json_sha256",
        ]:
            checks.truth(
                "model_identity", "%s_%s_present" % (stage_name, field),
                isinstance(model.get(field), str) and len(model[field]) == 64,
                model.get(field),
            )
    checks.equal(
        "model_identity", "same_model_snapshot_both_stages",
        stage_a.get("model", {}).get("snapshot_path"),
        stage_c.get("model", {}).get("snapshot_path"),
    )
    checks.equal(
        "model_identity", "same_weights_manifest_both_stages",
        stage_a.get("model", {}).get("weights_manifest_sha256"),
        stage_c.get("model", {}).get("weights_manifest_sha256"),
    )
    checks.equal(
        "model_identity", "same_tokenizer_both_stages",
        stage_a.get("model", {}).get("tokenizer_json_sha256"),
        stage_c.get("model", {}).get("tokenizer_json_sha256"),
    )

    # Independent re-reading of the snapshot on disk: the verifier does not
    # trust the stage evidence for weight or tokenizer identity.
    resolved_snapshot: dict = {}
    try:
        resolved_snapshot = resolve_snapshot(stage_a["model"])
        checks.equal(
            "model_identity", "independent_snapshot_revision",
            resolved_snapshot["snapshot_revision"],
            stage_a["model"]["snapshot_revision"],
        )
        checks.equal(
            "model_identity", "independent_weight_blob_set",
            {weight["name"]: weight["content_sha256"]
             for weight in resolved_snapshot["weight_files"]},
            {weight["name"]: weight["content_sha256"]
             for weight in stage_a["model"]["weight_files"]},
        )
        checks.truth(
            "model_identity", "independent_weight_bytes_are_real_blobs",
            resolved_snapshot["total_weight_bytes"] > 1_000_000_000,
            {
                "total_weight_bytes": resolved_snapshot["total_weight_bytes"],
                "per_file": {
                    weight["name"]: weight["blob_size_bytes"]
                    for weight in resolved_snapshot["weight_files"]
                },
            },
        )
        for field, name in [
            ("config_json_sha256", "config.json"),
            ("tokenizer_json_sha256", "tokenizer.json"),
            ("tokenizer_config_json_sha256", "tokenizer_config.json"),
            ("model_index_json_sha256", "model.safetensors.index.json"),
        ]:
            checks.equal(
                "model_identity", "independent_%s" % field,
                resolved_snapshot["identity_file_sha256"].get(name),
                stage_a["model"].get(field),
            )
        checks.equal(
            "model_identity", "both_stages_list_identical_weights",
            stage_a["model"]["weight_files"], stage_c["model"]["weight_files"],
        )
    except Exception as error:  # noqa: BLE001 - recorded as a failed criterion
        checks.add(
            "model_identity", "independent_snapshot_resolution", False, str(error))

    # ---------------- IS persistence (same physical file + settled record) -----
    checks.equal(
        "is_persistence", "stage_c_opened_stage_a_database_bytes",
        stage_c.get("database_at_start", {}).get("sha256"),
        stage_a.get("database", {}).get("sha256"),
    )
    checks.equal(
        "is_persistence", "same_physical_file",
        stage_c.get("database_at_start", {}).get("inode"),
        stage_a.get("database", {}).get("inode"),
    )
    connection = open_readonly(database)
    try:
        u1 = settlement(connection, U1_ID)
        source = settlement(connection, SOURCE_ID)
        u2 = settlement(connection, U2_ID)
        states = execution_states(connection)
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        object_rows = connection.execute("SELECT object_id FROM is_objects").fetchall()
        all_objects_verify = all(
            sha256_hex(bytes(connection.execute(
                "SELECT content FROM is_objects WHERE object_id=?", (row["object_id"],)
            ).fetchone()["content"])) == row["object_id"]
            for row in object_rows
        )
    finally:
        connection.close()

    checks.equal("is_persistence", "database_integrity_check", integrity, "ok")
    checks.truth("is_persistence", "all_carrier_objects_verify", all_objects_verify,
                 len(object_rows))
    checks.truth("is_persistence", "u1_settled_after_stage_c",
                 u1 is not None and u1.get("state") == "SETTLED",
                 u1.get("state") if u1 else None)
    checks.truth("is_persistence", "u2_settled_after_stage_c",
                 u2 is not None and u2.get("state") == "SETTLED",
                 u2.get("state") if u2 else None)

    stage_a_actions = {
        action["item_id"]: action
        for action in stage_a.get("continuation", {}).get("settlement_actions", [])
    }
    stage_c_actions = {
        action["item_id"]: action
        for action in stage_c.get("continuation", {}).get("settlement_actions", [])
    }
    checks.equal(
        "is_persistence", "u1_settlement_object_matches_stage_a",
        stage_c_actions.get(U1_ID, {}).get("settlement_object_id"),
        stage_a_actions.get(U1_ID, {}).get("settlement_object_id"),
    )
    checks.equal(
        "is_persistence", "u1_physical_object_is_the_settled_one",
        u1.get("_object_id") if u1 else None,
        stage_a_actions.get(U1_ID, {}).get("settlement_object_id"),
    )
    checks.equal(
        "is_persistence", "u1_settlement_advancement_is_stage_a",
        u1.get("advancement_id") if u1 else None,
        "handoff-a-u1-%s" % stage_a.get("run_label"),
    )
    checks.truth(
        "is_persistence", "u1_result_digest_stable",
        u1 is not None
        and digest(u1["result"]["value"]) == u1["result"]["result_value_sha256"]
        and u1["result"]["result_value_sha256"] == u1["basis"]["result_value_sha256"],
        u1["result"]["result_value_sha256"] if u1 else None,
    )

    # The run must still be preserved exactly as stage C left it: nothing may
    # have been rewritten after the last stage of the experiment.
    current_database = physical_identity(database)
    checks.equal(
        "is_persistence", "database_bytes_unchanged_since_stage_c",
        current_database["sha256"],
        stage_c.get("database_after", {}).get("sha256"),
    )
    checks.equal(
        "is_persistence", "database_inode_unchanged_since_stage_c",
        current_database["inode"],
        stage_c.get("database_after", {}).get("inode"),
    )

    # ---------------- ES independence ----------------
    checks.truth(
        "es_independence", "stage_c_is_a_new_process",
        isinstance(stage_c.get("pid"), int)
        and stage_c.get("pid") != stage_a.get("pid"),
        {"stage_a_pid": stage_a.get("pid"), "stage_c_pid": stage_c.get("pid")},
    )
    checks.equal(
        "es_independence", "stage_c_did_not_create_a_fresh_execution",
        stage_c.get("continuation", {}).get("created_fresh_execution"), False,
    )
    checks.equal(
        "es_independence", "stage_c_recovered_position",
        stage_c.get("recovery", {}).get("recovered_position"), 1,
    )
    checks.truth(
        "es_independence", "stage_c_recovered_lifecycle_is_live",
        stage_c.get("recovery", {}).get("recovered_lifecycle") in ("active", "restored"),
        stage_c.get("recovery", {}).get("recovered_lifecycle"),
    )
    checks.truth(
        "es_independence", "same_durable_state_directory",
        stage_c.get("semantic_state_directory") == stage_a.get("semantic_state_directory"),
        stage_c.get("semantic_state_directory"),
    )
    checks.equal(
        "es_independence", "is_authorized_recovery_with_applied_state",
        stage_c.get("recovery", {}).get("authorized_by_is_runtime_application_status"),
        "APPLIED_SWIFT",
    )
    # Execution-state lineage: stage C advancement -> stage A confirmation ->
    # stage A advancement. Each step must exist in the physical IS ledger.
    by_id = {state.get("state_id"): state for state in states}
    stage_c_confirmation = stage_c.get("continuation", {}).get(
        "is_confirmation_state_id")
    stage_a_confirmation_id = stage_a.get("continuation", {}).get("is_confirmation_state_id")
    checks.truth(
        "es_independence", "stage_a_confirmation_present_in_is",
        stage_a_confirmation_id in by_id
        and by_id[stage_a_confirmation_id].get("runtime_application_status") == "APPLIED_SWIFT",
        stage_a_confirmation_id,
    )
    checks.truth(
        "es_independence", "stage_c_confirmation_present_in_is",
        stage_c_confirmation in by_id
        and by_id[stage_c_confirmation].get("runtime_application_status") == "APPLIED_SWIFT",
        stage_c_confirmation,
    )
    checks.equal(
        "es_independence", "stage_c_advancement_prior_is_stage_a_confirmation",
        by_id.get(stage_c.get("continuation", {}).get("is_pending_state_id"), {}).get(
            "prior_state_id"),
        stage_a_confirmation_id,
    )

    # Stage B: the old execution stage must be gone, not merely paused.
    stage_a_pid = stage_a.get("pid")
    checks.truth(
        "es_independence", "stage_a_process_terminated",
        isinstance(stage_a_pid, int) and not process_alive(stage_a_pid),
        {"stage_a_pid": stage_a_pid, "alive": process_alive(stage_a_pid)
         if isinstance(stage_a_pid, int) else None},
    )
    checks.truth(
        "es_independence", "stage_a_released_carrier_before_exit",
        stage_a.get("carrier_release", {}).get("released") is True
        and stage_a.get("carrier_release", {}).get("old_binding_unusable") is True,
        stage_a.get("carrier_release"),
    )
    checks.truth(
        "es_independence", "stage_c_reloaded_the_weights",
        isinstance(stage_c.get("model_load_seconds"), (int, float))
        and stage_c["model_load_seconds"] > 0,
        stage_c.get("model_load_seconds"),
    )

    # Durable execution state: the new process must reattach to the persisted
    # representation instead of creating another execution.
    es_state_summary: dict = {}
    try:
        state_file = Path(stage_c["semantic_state_directory"]) / "execution-state.json"
        es_state = json.loads(state_file.read_text(encoding="utf-8"))
        lifecycle = es_state.get("lifecycle", [])
        representations = {
            entry.get("position"): entry
            for entry in es_state.get("representations", [])
        }
        checkpoints = es_state.get("settlementCheckpoints", [])
        lineage = [(event.get("operation"), event.get("resultPosition"))
                   for event in lifecycle]
        es_state_summary = {
            "path": str(state_file),
            "sha256": sha256_hex(state_file.read_bytes()),
            "lineage": lineage,
            "representation_token_counts": {
                str(position): len(decoded_prefix(entry))
                for position, entry in sorted(representations.items())
            },
            "settlement_checkpoints": checkpoints,
        }
        checks.equal(
            "es_independence", "durable_state_created_exactly_once",
            [operation for operation, _ in lineage].count("created"), 1,
        )
        checks.equal(
            "es_independence", "durable_state_lineage",
            lineage,
            [("created", 0), ("continued", 1), ("reattached", 1), ("continued", 2)],
        )
        persisted_step_1 = (
            decoded_prefix(representations[1]) if 1 in representations else [])
        persisted_step_2 = (
            decoded_prefix(representations[2]) if 2 in representations else [])
        stage_a_generated = (
            stage_a.get("continuation", {}).get("generated_token_ids") or [])
        checks.equal(
            "settled_work_reuse", "durable_representation_step_1_length",
            len(persisted_step_1),
            stage_a.get("continuation", {}).get("updated_prefix_token_count"),
        )
        checks.equal(
            "settled_work_reuse", "durable_representation_step_1_tail_is_stage_a",
            persisted_step_1[-len(stage_a_generated):] if stage_a_generated else None,
            stage_a_generated,
        )
        checks.equal(
            "incremental_continuation", "durable_representation_step_2_length",
            len(persisted_step_2),
            stage_c.get("continuation", {}).get("updated_prefix_token_count"),
        )
        checks.truth(
            "settled_work_reuse", "durable_checkpoint_is_stage_c_advancement",
            any(
                checkpoint.get("lastSettledAdvancementID")
                == "handoff-c-u2-%s" % stage_c.get("run_label")
                and checkpoint.get("isConfirmationStateID")
                == stage_c.get("continuation", {}).get("is_confirmation_state_id")
                and checkpoint.get("resultDigest")
                == stage_c.get("continuation", {}).get("bridge_result_digest")
                for checkpoint in checkpoints
            ),
            checkpoints,
        )
    except Exception as error:  # noqa: BLE001 - recorded as a failed criterion
        checks.add(
            "es_independence", "durable_execution_state_readable", False, str(error))

    # ---------------- completed-work reuse ----------------
    checks.equal(
        "settled_work_reuse", "stage_a_computed_step_1_only",
        stage_a.get("continuation", {}).get("computed_item_ids"), [U1_ID],
    )
    checks.equal(
        "settled_work_reuse", "stage_a_reused_registered_source",
        stage_a.get("continuation", {}).get("reused_item_ids"), [SOURCE_ID],
    )
    checks.equal(
        "settled_work_reuse", "stage_c_computed_step_2_only",
        stage_c.get("continuation", {}).get("computed_item_ids"), [U2_ID],
    )
    checks.equal(
        "settled_work_reuse", "stage_c_reused_source_and_step_1",
        sorted(stage_c.get("continuation", {}).get("reused_item_ids") or []),
        sorted([SOURCE_ID, U1_ID]),
    )
    checks.equal(
        "settled_work_reuse", "stage_c_u1_settlement_object_identity",
        stage_c_actions.get(U1_ID, {}).get("settlement_object_id"),
        u1.get("_object_id") if u1 else None,
    )
    checks.equal(
        "settled_work_reuse", "stage_c_source_settlement_object_identity",
        stage_c_actions.get(SOURCE_ID, {}).get("settlement_object_id"),
        source.get("_object_id") if source else None,
    )
    checks.equal(
        "settled_work_reuse", "stage_c_model_continuation_calls",
        stage_c.get("counters", {}).get("model_continuation_calls"), 1,
    )
    checks.equal(
        "settled_work_reuse", "stage_c_seed_retokenizations",
        stage_c.get("counters", {}).get("tokenize_seed_calls"), 0,
    )
    checks.equal(
        "settled_work_reuse", "stage_c_recovered_prefix_is_stage_a_prefix",
        stage_c.get("recovery", {}).get("bound_prefix_token_count"),
        stage_a.get("continuation", {}).get("updated_prefix_token_count"),
    )
    checks.truth(
        "settled_work_reuse", "recovered_prefix_tail_is_stage_a_generation",
        stage_c.get("recovery", {}).get("prefix_tail_matches_stage_a_generated_tokens") is True,
        stage_c.get("recovery", {}),
    )

    # ---------------- incremental continuation ----------------
    stage_a_tokens = stage_a.get("continuation", {}).get("generated_token_ids") or []
    stage_c_tokens = stage_c.get("continuation", {}).get("generated_token_ids") or []
    checks.truth(
        "incremental_continuation", "stage_a_real_model_generated",
        len(stage_a_tokens) > 0 and stage_a.get("counters", {}).get("model_continuation_calls") == 1,
        stage_a_tokens,
    )
    checks.truth(
        "incremental_continuation", "stage_c_real_model_generated_new_work",
        len(stage_c_tokens) > 0 and stage_c_tokens != stage_a_tokens,
        {"stage_c_tokens": stage_c_tokens, "stage_a_tokens": stage_a_tokens},
    )
    checks.equal(
        "incremental_continuation", "stage_c_model_call_count",
        stage_c.get("counters", {}).get("model_continuation_calls"), 1,
    )
    checks.equal(
        "incremental_continuation", "stage_c_advanced_to_position_2",
        stage_c.get("continuation", {}).get("advanced_position"), 2,
    )
    checks.equal(
        "incremental_continuation", "stage_c_consumed_the_settled_prefix",
        stage_c.get("continuation", {}).get("consumed_prefix_length"),
        stage_a.get("continuation", {}).get("updated_prefix_token_count"),
    )
    checks.truth(
        "incremental_continuation", "stage_c_input_used_settled_u1_secret",
        stage_c.get("prompt", {}).get("next_input_uses_settled_u1_secret") is True,
        stage_c.get("prompt", {}),
    )
    expected_answer = None
    if u1 and source:
        expected_answer = "%s-%s" % (
            u1["result"]["value"].get("secret"),
            source["result"]["value"].get("checksum"),
        )
    checks.truth(
        "incremental_continuation", "stage_c_answer_matches_dependency_values",
        u2 is not None and expected_answer is not None
        and u2["result"]["value"].get("answer") == expected_answer,
        {
            "settled_answer": u2["result"]["value"].get("answer") if u2 else None,
            "expected_from_settled_dependencies": expected_answer,
        },
    )
    checks.equal(
        "incremental_continuation", "u2_settlement_advancement_is_stage_c",
        u2.get("advancement_id") if u2 else None,
        "handoff-c-u2-%s" % stage_c.get("run_label"),
    )
    checks.truth(
        "incremental_continuation", "u2_result_digest_matches_contract",
        u2 is not None
        and digest(u2["result"]["value"]) == u2["result"]["result_value_sha256"],
        u2["result"]["result_value_sha256"] if u2 else None,
    )
    checks.equal(
        "incremental_continuation", "u2_dependency_declares_step_1_and_source",
        u2.get("basis", {}).get("dependency_object_ids") if u2 else None,
        {
            SOURCE_ID: source.get("_object_id") if source else None,
            U1_ID: u1.get("_object_id") if u1 else None,
        },
    )

    # ---------------- dependency correctness (model-free probe on a copy) ------
    environment = dict(os.environ)
    environment["SIMIGO_INFO_VALIDITY_POLICY_PATH"] = str(
        lab_root / "integrated-es-palace/mlx-smoke-v1/ISOLATED_VALIDITY_POLICY.json"
    )
    probe_dir = run_dir / "probe"
    probe_database = probe_dir / "carrier.sqlite"
    probe_summary: dict = {}
    try:
        if probe_dir.exists():
            raise RuntimeError("probe directory already exists; refusing to overwrite")
        probe_dir.mkdir(parents=True)
        run_bridge(args.python, bridge, "snapshot-database", [
            "--database", str(database), "--destination", str(probe_database),
        ], environment)
        invalidation = run_bridge(args.python, bridge, "invalidate", [
            "--database", str(probe_database),
            "--item-id", U1_ID,
            "--reason", "dependency-closure probe: step 1 settlement is invalid",
        ], environment)
        probe = run_bridge(args.python, bridge, "execute-probe", [
            "--database", str(probe_database),
            "--demand-id", U2_DEMAND,
            "--advancement", "handoff-probe-u2",
            "--evaluated-at", utc_now(),
        ], environment)
        result = probe["result"]
        probe_summary = {
            "invalidated_item_ids": invalidation["invalidation"]["invalidated_item_ids"],
            "computed_item_ids": result.get("computed_item_ids"),
            "reused_item_ids": result.get("reused_item_ids"),
            "state": result.get("state"),
        }
        checks.equal(
            "dependency_correctness", "invalidation_propagated_to_step_2",
            sorted(invalidation["invalidation"]["invalidated_item_ids"]),
            sorted([U1_ID, U2_ID]),
        )
        checks.equal(
            "dependency_correctness", "probe_recomputed_invalidated_closure",
            result.get("computed_item_ids"), [U1_ID, U2_ID],
        )
        checks.equal(
            "dependency_correctness", "probe_reused_valid_source",
            result.get("reused_item_ids"), [SOURCE_ID],
        )
        checks.equal(
            "dependency_correctness", "probe_advanced", result.get("state"), "ADVANCED",
        )
        # The authoritative run database must be untouched by the probe.
        connection = open_readonly(database)
        try:
            u1_after = settlement(connection, U1_ID)
            u2_after = settlement(connection, U2_ID)
        finally:
            connection.close()
        checks.equal(
            "dependency_correctness", "authoritative_u1_untouched",
            u1_after.get("_object_id") if u1_after else None,
            u1.get("_object_id") if u1 else None,
        )
        checks.equal(
            "dependency_correctness", "authoritative_u2_untouched",
            u2_after.get("_object_id") if u2_after else None,
            u2.get("_object_id") if u2 else None,
        )
    except Exception as error:  # noqa: BLE001 - recorded as a failed criterion
        checks.add("dependency_correctness", "probe_executed", False, str(error))

    criteria = checks.criteria()
    record = {
        "schema_id": "SIMIGO-REAL-MODEL-HANDOFF-VERIFICATION-V1",
        "run_dir": str(run_dir),
        "database": str(database),
        "verified_at_utc": utc_now(),
        "checks": checks.items,
        "criteria": criteria,
        "probe": probe_summary,
        "resolved_snapshot": resolved_snapshot,
        "es_state_file": es_state_summary,
        "metadata_notes": [
            "The stage evidence was written before the modelIdentity fix: "
            "weight_files[].size_bytes recorded the SYMLINK length (76) instead "
            "of the blob size. Weight identity is unaffected because it is the "
            "blob file name (a git-lfs content sha256); the verifier re-resolved "
            "the snapshot and recorded real blob sizes under resolved_snapshot.",
            "The experiment was NOT re-executed to correct evidence metadata; "
            "the fix applies to future runs only.",
        ],
        "propositions": {
            "arc_reference_release": "UNPROVEN_NOT_INSTRUMENTED",
            "old_carrier_not_reusable": stage_a.get("propositions", {}).get(
                "old_carrier_not_reusable"),
            "gpu_memory_returned_to_os": "UNPROVEN_NOT_A_SUCCESS_CONDITION",
            "physical_kv_reuse": "UNPROVEN_PREFIX_REPLAY",
        },
        "prefix_replay_tokens": stage_c.get("continuation", {}).get(
            "consumed_prefix_length"),
        "overall": "PASS" if criteria and all(
            value == "PASS" for value in criteria.values()) else "FAIL",
    }
    output = evidence_dir / "verification.json"
    output.write_text(
        json.dumps(record, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps({
        "ok": record["overall"] == "PASS",
        "criteria": criteria,
        "failed_checks": [item for item in checks.items if not item["passed"]],
        "probe": probe_summary,
        "verification_path": str(output),
    }, ensure_ascii=False, sort_keys=True))
    return 0 if record["overall"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
