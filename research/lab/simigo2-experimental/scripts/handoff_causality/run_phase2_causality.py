#!/usr/bin/env python3
"""Phase 2 handoff-causality runner (isolated, no silent retries).

Runs two lineage-complete worlds through the real-model handoff path, then
derives B0/B1/B3/B4 observations from isolated database copies.  The runner
never edits the repository; it writes only below --run-root.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

LABEL = "handoff-causality-20261022b"
COLD_U2_SEED = (
    "SIMIGO-HANDOFF-COLD-U2-V1\n"
    "You are executing step 2 in a fresh execution instance.\n"
)
U1_SETTLEMENT_ID = "settlement:TASK-U1"


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=1, sort_keys=True) + "\n", encoding="utf-8")


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sqlite_backup(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        raise FileExistsError(destination)
    src = sqlite3.connect(str(source))
    dst = sqlite3.connect(str(destination))
    try:
        src.backup(dst)
        dst.commit()
    finally:
        dst.close()
        src.close()


def process_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def run_process(command: list[str], log_path: Path, timeout: int) -> dict:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.time()
    with log_path.open("wb") as log:
        process = subprocess.Popen(
            command,
            cwd=str(Path(command[0]).parent),
            stdout=log,
            stderr=subprocess.STDOUT,
            env=os.environ.copy(),
        )
        timed_out = False
        try:
            exit_code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            process.kill()
            exit_code = process.wait()
    return {
        "argv": command,
        "pid": process.pid,
        "exit_code": exit_code,
        "timed_out": timed_out,
        "wall_seconds": round(time.time() - started, 3),
        "log": str(log_path),
        "log_sha256": sha256_file(log_path),
        "started_at_utc": utc_now(),
    }


# --------------------------------------------------------------------------
# database readers / isolated mutations
# --------------------------------------------------------------------------


def connect_readonly(path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect("file:%s?mode=ro" % path, uri=True)
    connection.row_factory = sqlite3.Row
    return connection


def current_object(connection: sqlite3.Connection, dependency_id: str) -> dict | None:
    row = connection.execute(
        "SELECT content_address FROM dependency_entries WHERE dependency_id=? "
        "ORDER BY append_order DESC LIMIT 1",
        (dependency_id,),
    ).fetchone()
    if row is None:
        return None
    content = connection.execute(
        "SELECT content FROM is_objects WHERE object_id=?", (row["content_address"],)
    ).fetchone()
    if content is None:
        return None
    value = json.loads(bytes(content["content"]))
    value["_object_id"] = row["content_address"]
    return value


def current_index_object(connection: sqlite3.Connection, identity: str) -> dict | None:
    row = connection.execute(
        "SELECT record_object FROM is_index_entries WHERE srs_identity=? "
        "ORDER BY append_order DESC LIMIT 1",
        (identity,),
    ).fetchone()
    if row is None:
        return None
    content = connection.execute(
        "SELECT content FROM is_objects WHERE object_id=?", (row["record_object"],)
    ).fetchone()
    if content is None:
        return None
    value = json.loads(bytes(content["content"]))
    value["_object_id"] = row["record_object"]
    return value


def read_task_definitions(database: Path) -> dict:
    connection = connect_readonly(database)
    try:
        return {
            "source": current_index_object(connection, "item:TASK-SOURCE"),
            "u1": current_index_object(connection, "item:TASK-U1"),
            "u2": current_index_object(connection, "item:TASK-U2"),
            "u1_settlement": current_object(connection, U1_SETTLEMENT_ID),
            "source_settlement": current_object(connection, "settlement:TASK-SOURCE"),
        }
    finally:
        connection.close()


def read_u1_secret(database: Path) -> str:
    definitions = read_task_definitions(database)
    settlement = definitions["u1_settlement"]
    if not settlement:
        raise RuntimeError("U1 settlement missing in %s" % database)
    return settlement["result"]["value"]["secret"]


def write_append_object(
    connection: sqlite3.Connection,
    content: bytes,
    dependency_id: str,
    reason: str,
    index_identity: str | None,
) -> dict:
    object_id = sha256_bytes(content)
    created_order = connection.execute(
        "SELECT COALESCE(MAX(created_order),0)+1 FROM is_objects"
    ).fetchone()[0]
    connection.execute(
        "INSERT INTO is_objects (object_id, byte_size, content, created_order) "
        "VALUES (?,?,?,?)",
        (object_id, len(content), content, created_order),
    )
    revision = connection.execute(
        "SELECT COALESCE(MAX(revision),0)+1 FROM dependency_entries "
        "WHERE dependency_id=?",
        (dependency_id,),
    ).fetchone()[0]
    append_order = connection.execute(
        "SELECT COALESCE(MAX(append_order),0)+1 FROM dependency_entries"
    ).fetchone()[0]
    connection.execute(
        "INSERT INTO dependency_entries "
        "(append_order, dependency_id, content_address, revision, reason) "
        "VALUES (?,?,?,?,?)",
        (append_order, dependency_id, object_id, revision, reason),
    )
    if index_identity:
        index_order = connection.execute(
            "SELECT COALESCE(MAX(append_order),0)+1 FROM is_index_entries"
        ).fetchone()[0]
        connection.execute(
            "INSERT INTO is_index_entries "
            "(append_order, srs_identity, record_object) VALUES (?,?,?)",
            (index_order, index_identity, object_id),
        )
    return {"object_id": object_id, "revision": revision, "append_order": append_order}


def mutate_remove_u1_settlement(database: Path) -> dict:
    connection = sqlite3.connect(str(database))
    connection.row_factory = sqlite3.Row
    try:
        dependency_rows = connection.execute(
            "SELECT append_order FROM dependency_entries WHERE dependency_id=?",
            (U1_SETTLEMENT_ID,),
        ).fetchall()
        index_rows = connection.execute(
            "SELECT append_order FROM is_index_entries WHERE srs_identity=?",
            (U1_SETTLEMENT_ID,),
        ).fetchall()
        connection.execute(
            "DELETE FROM dependency_entries WHERE dependency_id=?", (U1_SETTLEMENT_ID,)
        )
        connection.execute(
            "DELETE FROM is_index_entries WHERE srs_identity=?", (U1_SETTLEMENT_ID,)
        )
        connection.commit()
        retained = current_index_object(connection, "item:TASK-U1") is not None
        return {
            "deleted_dependency_rows": len(dependency_rows),
            "deleted_index_rows": len(index_rows),
            "u1_item_retained": retained,
            "u1_source_retained": current_index_object(connection, "item:TASK-SOURCE")
            is not None,
        }
    finally:
        connection.close()


def mutate_tamper_u1_object(database: Path) -> dict:
    connection = sqlite3.connect(str(database))
    try:
        row = connection.execute(
            "SELECT content_address FROM dependency_entries WHERE dependency_id=? "
            "ORDER BY append_order DESC LIMIT 1",
            (U1_SETTLEMENT_ID,),
        ).fetchone()
        if row is None:
            raise RuntimeError("U1 settlement missing for B3a")
        object_id = row[0]
        original = bytes(
            connection.execute(
                "SELECT content FROM is_objects WHERE object_id=?", (object_id,)
            ).fetchone()[0]
        )
        tampered = bytearray(original)
        tampered[len(tampered) // 2] ^= 0x01
        connection.execute(
            "UPDATE is_objects SET content=? WHERE object_id=?",
            (bytes(tampered), object_id),
        )
        connection.commit()
        return {
            "object_id": object_id,
            "original_sha256": sha256_bytes(original),
            "tampered_sha256": sha256_bytes(bytes(tampered)),
            "object_id_still_declared": object_id,
        }
    finally:
        connection.close()


def mutate_substitute_u1_value(database: Path, lab_root: Path) -> dict:
    sys.path.insert(0, str(lab_root / "execution-information-loop"))
    from carrier_loop import canonical, digest  # noqa: PLC0415

    connection = sqlite3.connect(str(database))
    try:
        row = connection.execute(
            "SELECT content_address FROM dependency_entries WHERE dependency_id=? "
            "ORDER BY append_order DESC LIMIT 1",
            (U1_SETTLEMENT_ID,),
        ).fetchone()
        if row is None:
            raise RuntimeError("U1 settlement missing for B3b")
        original_id = row[0]
        original = json.loads(
            bytes(
                connection.execute(
                    "SELECT content FROM is_objects WHERE object_id=?", (original_id,)
                ).fetchone()[0]
            )
        )
        substitute = os.urandom(16).hex()
        original_value = dict(original["result"]["value"])
        original_digest = original["result"]["result_value_sha256"]
        original_value["secret"] = substitute
        new_digest = digest(original_value)
        original["result"]["value"] = original_value
        original["result"]["result_value_sha256"] = new_digest
        original["basis"]["result_value_sha256"] = new_digest
        content = canonical(original)
        appended = write_append_object(
            connection,
            content,
            U1_SETTLEMENT_ID,
            "B3b digest-valid semantic substitution",
            U1_SETTLEMENT_ID,
        )
        connection.commit()
        return {
            "original_object_id": original_id,
            "original_result_value_sha256": original_digest,
            "substituted_secret_sha256": digest(substitute),
            "substituted_result_value_sha256": new_digest,
            "new_object_id": appended["object_id"],
            "retained_source_metadata": {
                "source_payload_sha256": original["result"]["source_payload_sha256"],
                "source_version": original["result"]["source_version"],
                "dependency_object_ids": original["result"]["dependency_object_ids"],
                "valid_until_utc": original["result"]["valid_until_utc"],
                "validity_policy": original["result"]["validity_policy"],
            },
        }
    finally:
        connection.close()


def mutate_dependency_pointer(database: Path, lab_root: Path) -> dict:
    sys.path.insert(0, str(lab_root / "execution-information-loop"))
    from carrier_loop import CarrierInformationLoop  # noqa: PLC0415

    loop = CarrierInformationLoop.open(str(database))
    try:
        item = loop.current_item("TASK-U2")
        if item is None:
            raise RuntimeError("TASK-U2 missing for B3c")
        previous = list(item["dependencies"])
        result = loop.put_source(
            item["demand_id"],
            "TASK-U2",
            item["source_kind"],
            item["source_version"],
            item["source_payload"],
            dependencies=["TASK-SOURCE"],
            valid_until_utc=item["valid_until_utc"],
            validity_policy=item["validity_policy"],
        )
        loop.commit()
        return {
            "previous_dependencies": previous,
            "new_dependencies": ["TASK-SOURCE"],
            "new_item_object_id": result["object_id"],
            "new_revision": result["revision"],
        }
    finally:
        loop.close()


# --------------------------------------------------------------------------
# B4 nonce-leak audit (before U2 starts)
# --------------------------------------------------------------------------


def files_contain(directory: Path, needle: str, pattern: str = "*") -> list[str]:
    hits: list[str] = []
    if not directory.exists():
        return hits
    for path in sorted(directory.rglob(pattern)):
        if not path.is_file():
            continue
        try:
            if needle in path.read_bytes().decode("utf-8", errors="ignore"):
                hits.append(str(path))
        except OSError:
            continue
    return hits


def audit_world(world: Path, other_world: Path, planned_argv: list[str]) -> dict:
    definitions = read_task_definitions(world / "pristine.sqlite")
    secret = definitions["u1_settlement"]["result"]["value"]["secret"]
    template = definitions["u2"]["source_payload"]["next_input_template"]
    argv_text = "\0".join(planned_argv)
    env_text = "\0".join("%s=%s" % (key, value) for key, value in os.environ.items())
    temp_hits = files_contain(Path(tempfile.gettempdir()), secret, "simigo-*")
    state_hits = files_contain(world / "run" / "state", secret)
    log_hits = files_contain(world / "logs", secret)
    evidence_hits = files_contain(world / "run" / "evidence", secret)
    other_db_hits = []
    for candidate in sorted(other_world.rglob("*.sqlite")):
        try:
            if secret in candidate.read_bytes().decode("utf-8", errors="ignore"):
                other_db_hits.append(str(candidate))
        except OSError:
            continue
    other_state_hits = files_contain(other_world / "run" / "state", secret)
    other_log_hits = files_contain(other_world / "logs", secret)
    violations = {
        "argv": secret in argv_text,
        "environment": secret in env_text,
        "cold_seed": secret in COLD_U2_SEED,
        "u2_base_template": secret in template,
        "u2_state_directory": bool(state_hits),
        "pre_u2_logs": bool(log_hits),
        "pre_u2_evidence": bool(evidence_hits),
        "temporary_files": bool(temp_hits),
        "other_world_database": bool(other_db_hits),
        "other_world_state": bool(other_state_hits),
        "other_world_logs": bool(other_log_hits),
    }
    return {
        "schema_id": "SIMIGO-CAUSALITY-PHASE2-B4-V1",
        "world": world.name,
        "audited_at_utc": utc_now(),
        "nonce_sha256": sha256_bytes(secret.encode("utf-8")),
        "nonce_length": len(secret),
        "allowlisted_occurrences": {
            "primary_database": str(world / "pristine.sqlite"),
            "u1_source_payload": True,
            "u1_item_prompt_seed": True,
            "u1_settlement_result": True,
        },
        "surface_contains_nonce": violations,
        "unexpected_hit_paths": {
            "u2_state_directory": state_hits,
            "pre_u2_logs": log_hits,
            "pre_u2_evidence": evidence_hits,
            "temporary_files": temp_hits,
            "other_world_database": other_db_hits,
            "other_world_state": other_state_hits,
            "other_world_logs": other_log_hits,
        },
        "cross_contaminated": any(violations.values()),
        "verdict": "CLEAN" if not any(violations.values()) else "CONTAMINATED",
    }


# --------------------------------------------------------------------------
# orchestration
# --------------------------------------------------------------------------


def stage_a(binary: Path, world: Path, model_dir: Path, lab_root: Path,
            max_tokens: int) -> dict:
    command = [
        str(binary), "stage-a",
        "--run-dir", str(world / "run"),
        "--model-dir", str(model_dir),
        "--lab-root", str(lab_root),
        "--run-label", LABEL,
        "--nonce-source", "random",
        "--max-tokens", str(max_tokens),
    ]
    metadata = run_process(command, world / "logs" / "stage-a.log", 1800)
    evidence_path = world / "run" / "evidence" / "stage-a.json"
    evidence = read_json(evidence_path) if evidence_path.exists() else None
    metadata["terminal_state"] = (
        evidence.get("terminal_state") if isinstance(evidence, dict) else "NO_EVIDENCE"
    )
    metadata["evidence_path"] = str(evidence_path)
    metadata["evidence_sha256"] = sha256_file(evidence_path) if evidence_path.exists() else None
    metadata["alive_after_exit"] = process_alive(metadata["pid"])
    metadata["model"] = evidence.get("model") if isinstance(evidence, dict) else None
    metadata["stage_a_pid"] = evidence.get("pid") if isinstance(evidence, dict) else None
    metadata["stage_a_continuation"] = (
        evidence.get("continuation") if isinstance(evidence, dict) else None
    )
    return metadata


def prepare_case(world: Path, case_name: str, mutation=None) -> Path:
    case_dir = world / case_name
    if case_dir.exists():
        raise FileExistsError(case_dir)
    case_dir.mkdir(parents=True)
    sqlite_backup(world / "pristine.sqlite", case_dir / "carrier.sqlite")
    if mutation is not None:
        mutation(case_dir / "carrier.sqlite")
    (case_dir / "state").mkdir()
    return case_dir


def u2_case(binary: Path, case_dir: Path, case_name: str, model_dir: Path,
            lab_root: Path, max_tokens: int, stage_a_pid: int) -> dict:
    state_dir = case_dir / "state"
    state_dir.mkdir(exist_ok=True)
    command = [
        str(binary), "phase2-u2",
        "--run-dir", str(case_dir),
        "--model-dir", str(model_dir),
        "--lab-root", str(lab_root),
        "--run-label", LABEL,
        "--case", case_name,
        "--state-dir", str(state_dir),
        "--u1-pid", str(stage_a_pid),
        "--max-tokens", str(max_tokens),
    ]
    metadata = run_process(command, case_dir / "logs" / "u2.log", 1800)
    evidence_path = case_dir / "evidence" / "phase2.json"
    evidence = read_json(evidence_path) if evidence_path.exists() else None
    metadata["terminal_state"] = (
        evidence.get("terminal_state") if isinstance(evidence, dict) else "NO_EVIDENCE"
    )
    metadata["evidence_path"] = str(evidence_path)
    metadata["evidence_sha256"] = sha256_file(evidence_path) if evidence_path.exists() else None
    metadata["command_contains_nonce"] = False
    metadata["evidence"] = evidence
    return metadata


def safe_condition(name: str, function) -> dict:
    try:
        return function()
    except Exception as error:  # noqa: BLE001 - preserve, never retry
        import traceback
        return {
            "terminal_state": "HARNESS_FAIL",
            "failure": "%s: %s" % (type(error).__name__, error),
            "failure_traceback": traceback.format_exc(),
        }


def compare_worlds(a: dict, b: dict) -> dict:
    ea = a.get("evidence") or {}
    eb = b.get("evidence") or {}
    out_a = ea.get("output") or {}
    out_b = eb.get("output") or {}
    template_a = (ea.get("is_reads") or {}).get("u2_item_source_payload_template_sha256")
    template_b = (eb.get("is_reads") or {}).get("u2_item_source_payload_template_sha256")
    seed_a = (ea.get("prompt") or {}).get("seed_sha256")
    seed_b = (eb.get("prompt") or {}).get("seed_sha256")
    next_a = (ea.get("prompt") or {}).get("next_input_sha256")
    next_b = (eb.get("prompt") or {}).get("next_input_sha256")
    answer_a = out_a.get("answer", "")
    answer_b = out_b.get("answer", "")
    match_a = bool(out_a.get("matches_settled_expected"))
    match_b = bool(out_b.get("matches_settled_expected"))
    follows_a = bool(ea.get("output_follows_is_settlement"))
    follows_b = bool(eb.get("output_follows_is_settlement"))
    checks = {
        "u2_template_identical": template_a is not None and template_a == template_b,
        "cold_seed_identical": seed_a is not None and seed_a == seed_b,
        "settlements_differ": ea.get("u1_settlement_object_id") != eb.get("u1_settlement_object_id")
        and bool(ea.get("u1_settlement_object_id")) and bool(eb.get("u1_settlement_object_id")),
        "u2_inputs_differ": next_a is not None and next_b is not None and next_a != next_b,
        "outputs_differ": bool(answer_a) and bool(answer_b) and answer_a != answer_b,
        "world_a_output_follows_its_settlement": follows_a and match_a,
        "world_b_output_follows_its_settlement": follows_b and match_b,
        "world_a_reused_u1_and_generated_u2": bool(ea.get("u1_reused"))
        and not bool(ea.get("u1_recomputed"))
        and (ea.get("u2_action") or {}).get("action") == "COMPUTE"
        and (ea.get("counters") or {}).get("model_continuation_calls") == 1,
        "world_b_reused_u1_and_generated_u2": bool(eb.get("u1_reused"))
        and not bool(eb.get("u1_recomputed"))
        and (eb.get("u2_action") or {}).get("action") == "COMPUTE"
        and (eb.get("counters") or {}).get("model_continuation_calls") == 1,
    }
    established = all(checks.values())
    return {
        "schema_id": "SIMIGO-CAUSALITY-PHASE2-B2-V1",
        "compared_at_utc": utc_now(),
        "checks": checks,
        "world_a": {
            "settlement_object_id": ea.get("u1_settlement_object_id"),
            "next_input_sha256": next_a,
            "answer_sha256": (out_a or {}).get("answer_sha256"),
            "matches_settled_expected": match_a,
            "u1_reused": ea.get("u1_reused"),
            "u1_recomputed": ea.get("u1_recomputed"),
            "u2_action": (ea.get("u2_action") or {}).get("action"),
            "generation_calls": (ea.get("counters") or {}).get("model_continuation_calls"),
        },
        "world_b": {
            "settlement_object_id": eb.get("u1_settlement_object_id"),
            "next_input_sha256": next_b,
            "answer_sha256": (out_b or {}).get("answer_sha256"),
            "matches_settled_expected": match_b,
            "u1_reused": eb.get("u1_reused"),
            "u1_recomputed": eb.get("u1_recomputed"),
            "u2_action": (eb.get("u2_action") or {}).get("action"),
            "generation_calls": (eb.get("counters") or {}).get("model_continuation_calls"),
        },
        "terminal_state": "C2_DIFFERENTIAL_ESTABLISHED" if established else "C2_DIFFERENTIAL_NOT_ESTABLISHED",
    }


def summarize_claims(results: dict, b2: dict, b4: dict) -> dict:
    b0a = results.get("B0-A", {})
    b0b = results.get("B0-B", {})
    b1 = results.get("B1-harness", {})
    b1_loop = results.get("B1-loop", {})
    b3b = results.get("B3b", {})
    c2 = "NOT_ESTABLISHED"
    if b2.get("terminal_state") == "C2_DIFFERENTIAL_ESTABLISHED" and not b4["W_A"]["cross_contaminated"] and not b4["W_B"]["cross_contaminated"]:
        c2 = "SUPPORTED_IN_THE_TESTED_HANDOFF_PATH_ONLY"
    b1_evidence = b1.get("evidence") or {}
    b1_refused = (
        b1.get("terminal_state") in {
            "PHASE2_READ_REFUSAL",
            "PHASE2_INPUT_ADMISSION_REFUSAL",
        }
        and (b1_evidence.get("counters") or {}).get("model_continuation_calls") == 0
        and not b1_evidence.get("continue_task_entered")
        and not b1_evidence.get("u1_recomputed")
    )
    loop_actions = ((b1_loop.get("probe") or {}).get("result") or {}).get("actions") or []
    loop_computed = [action.get("item_id") for action in loop_actions if action.get("action") == "COMPUTE"]
    loop_recomputed_u1 = "TASK-U1" in loop_computed
    if b1_refused and loop_recomputed_u1:
        c3 = "OBSERVED_DIFFERENT_BEHAVIOR_BY_PATH"
    elif b1_refused or loop_recomputed_u1:
        c3 = "PARTIAL"
    else:
        c3 = "NOT_ESTABLISHED"
    b3b_evidence = b3b.get("evidence") or {}
    b3b_accepted = (
        b3b.get("terminal_state") == "PHASE2_OBSERVED_SUBSTITUTION"
        and bool((b3b_evidence.get("output") or {}).get("matches_settled_expected"))
        and bool(b3b_evidence.get("output_follows_is_settlement"))
    )
    c4 = (
        "DIGEST_VALIDITY_DOES_NOT_ESTABLISH_U1_PROVENANCE"
        if b3b_accepted
        else "NOT_DEMONSTRATED"
    )
    return {
        "C1": "OBSERVED_IN_PHASE1 (see phase1 evidence)",
        "C2": c2,
        "C3": c3,
        "C3_evidence": {
            "handoff_refused": b1_refused,
            "handoff_generation_calls": (b1_evidence.get("counters") or {}).get("model_continuation_calls"),
            "generic_loop_computed_items": loop_computed,
            "generic_loop_recomputed_u1": loop_recomputed_u1,
        },
        "C4": c4,
        "C4_evidence": {
            "b3b_accepted_substitution": b3b_accepted,
            "b3b_output_matches_substituted_value": bool(
                (b3b_evidence.get("output") or {}).get("matches_settled_expected")),
            "b3b_authenticity_label": b3b_evidence.get("c4_authenticity"),
        },
        "B0-A": b0a.get("terminal_state"),
        "B0-B": b0b.get("terminal_state"),
    }


def admission_conditions(results: dict) -> dict:
    """Per-condition proof that admission happened before any generation.

    A refused condition must show a structured refusal stage, zero
    tokenize/generation calls, and no continuation entry. An admitted
    condition must show the admission identity that the model consumed.
    """

    def condition(
        name: str, stage: str | None, terminal: str, generation: int
    ) -> dict:
        result = results.get(name) or {}
        evidence = result.get("evidence") or {}
        refusal = evidence.get("input_admission_refusal") or {}
        counters = evidence.get("counters") or {}
        admission = evidence.get("input_admission") or {}
        refused = stage is not None
        # A refused condition never tokenizes; an admitted fresh-ES continuation
        # tokenizes its seed and its admitted next input exactly once.
        expected_tokenize_text = 0 if refused else 1
        expected_tokenize_seed = 0 if refused else 1
        passed = (
            result.get("terminal_state") == terminal
            and evidence.get("input_admission_status") == (
                "REFUSED" if refused else "ADMITTED")
            and (refusal.get("stage") == stage if refused else True)
            and counters.get("model_continuation_calls") == generation
            and (
                not evidence.get("continue_task_entered")
                if refused else evidence.get("continue_task_entered") is True
            )
            and counters.get("tokenize_text_calls") == expected_tokenize_text
            and counters.get("tokenize_seed_calls") == expected_tokenize_seed
        )
        return {
            "terminal_state": result.get("terminal_state"),
            "expected_terminal_state": terminal,
            "input_admission_status": evidence.get("input_admission_status"),
            "expected_refusal_stage": stage,
            "refusal_stage": refusal.get("stage"),
            "refusal_reason": refusal.get("reason"),
            "production_continuation_invoked": evidence.get(
                "production_continuation_invoked"),
            "continue_task_entered": evidence.get("continue_task_entered"),
            "generation_entered": evidence.get("generation_entered"),
            "tokenize_text_calls": counters.get("tokenize_text_calls"),
            "tokenize_seed_calls": counters.get("tokenize_seed_calls"),
            "expected_tokenize_text_calls": expected_tokenize_text,
            "expected_tokenize_seed_calls": expected_tokenize_seed,
            "model_continuation_calls": counters.get("model_continuation_calls"),
            "expected_generation_calls": generation,
            "input_sha256": admission.get("input_sha256"),
            "dependency_settlement_object_ids": admission.get(
                "dependency_settlement_object_ids"),
            "pass": passed,
        }

    return {
        "B0-A": condition("B0-A", None, "PHASE2_OBSERVED_SUCCESS", 1),
        "B0-B": condition("B0-B", None, "PHASE2_OBSERVED_SUCCESS", 1),
        "B1": condition(
            "B1-harness", "SETTLEMENT_NOT_ADMITTED",
            "PHASE2_INPUT_ADMISSION_REFUSAL", 0),
        "B3a": condition(
            "B3a", "SETTLEMENT_OBJECT_UNREADABLE",
            "PHASE2_INPUT_ADMISSION_REFUSAL", 0),
        "B3b": condition(
            "B3b", None, "PHASE2_OBSERVED_SUBSTITUTION", 1),
        "B3c": condition(
            "B3c", "INPUT_BINDING_DEPENDENCY_NOT_DECLARED",
            "PHASE2_INPUT_ADMISSION_REFUSAL", 0),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", required=True)
    parser.add_argument("--lab-root", required=True)
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--max-tokens", type=int, default=64)
    parser.add_argument("--world-suffix", default="")
    args = parser.parse_args()

    run_root = Path(args.run_root).expanduser().resolve()
    global LABEL
    # The run tag follows the run root so a new label (e.g. 20261022c) never
    # overwrites the earlier round's evidence.
    LABEL = run_root.name
    lab_root = Path(args.lab_root).expanduser().resolve()
    model_dir = Path(args.model_dir).expanduser().resolve()
    binary = lab_root / "simigo2-experimental" / ".build" / "debug" / "RealModelHandoff"
    phase2a = run_root / "phase2a" / ("world-a" + args.world_suffix)
    phase2b = run_root / "phase2b" / ("world-b" + args.world_suffix)

    for world in (phase2a, phase2b):
        if (world / "run").exists():
            raise SystemExit("refusing to overwrite existing world: %s" % world)
        world.mkdir(parents=True)

    world_a_stage = stage_a(binary, phase2a, model_dir, lab_root, args.max_tokens)
    world_b_stage = stage_a(binary, phase2b, model_dir, lab_root, args.max_tokens)
    write_json(run_root / "logs" / "stage-a-launch.json", {
        "schema_id": "SIMIGO-CAUSALITY-PHASE2-STAGE-A-V1",
        "created_at_utc": utc_now(),
        "W_A": world_a_stage,
        "W_B": world_b_stage,
    })
    if world_a_stage["terminal_state"] != "STAGE_A_PASS" or world_b_stage["terminal_state"] != "STAGE_A_PASS":
        write_json(run_root / "summary.json", {
            "schema_id": "SIMIGO-CAUSALITY-PHASE2-SUMMARY-V1",
            "run_id": LABEL,
            "created_at_utc": utc_now(),
            "terminal_state": "BLOCKED_NOT_RUN",
            "W_A": world_a_stage,
            "W_B": world_b_stage,
        })
        return 1

    sqlite_backup(phase2a / "run" / "carrier.sqlite", phase2a / "pristine.sqlite")
    sqlite_backup(phase2b / "run" / "carrier.sqlite", phase2b / "pristine.sqlite")

    planned_u2 = [
        str(binary), "phase2-u2", "--run-dir", "<case>", "--model-dir", str(model_dir),
        "--lab-root", str(lab_root), "--run-label", LABEL, "--case", "<condition>",
        "--state-dir", "<case>/state", "--u1-pid", str(world_a_stage["pid"]),
        "--max-tokens", str(args.max_tokens),
    ]
    b4_a = audit_world(phase2a, phase2b, planned_u2)
    b4_b = audit_world(phase2b, phase2a, planned_u2)
    write_json(phase2a / "B4.json", b4_a)
    write_json(phase2b / "B4.json", b4_b)
    if b4_a["cross_contaminated"] or b4_b["cross_contaminated"]:
        write_json(run_root / "summary.json", {
            "schema_id": "SIMIGO-CAUSALITY-PHASE2-SUMMARY-V1",
            "run_id": LABEL,
            "created_at_utc": utc_now(),
            "terminal_state": "INVALID_CONDITION",
            "B4": {"W_A": b4_a, "W_B": b4_b},
        })
        return 1

    results: dict[str, dict] = {}

    def run_b0(name: str, world: Path, stage: dict) -> dict:
        case_dir = prepare_case(world, name)
        return u2_case(binary, case_dir, name, model_dir, lab_root,
                       args.max_tokens, stage["pid"])

    results["B0-A"] = safe_condition("B0-A", lambda: run_b0("B0-A", phase2a, world_a_stage))
    results["B0-B"] = safe_condition("B0-B", lambda: run_b0("B0-B", phase2b, world_b_stage))

    # B1-harness must record the removal itself, so it is built explicitly.
    try:
        b1_dir = phase2a / "B1-harness"
        if b1_dir.exists():
            raise FileExistsError(b1_dir)
        b1_dir.mkdir(parents=True)
        sqlite_backup(phase2a / "pristine.sqlite", b1_dir / "carrier.sqlite")
        b1_mutation = mutate_remove_u1_settlement(b1_dir / "carrier.sqlite")
        (b1_dir / "state").mkdir()
        results["B1-harness"] = u2_case(
            binary, b1_dir, "B1-harness", model_dir, lab_root,
            args.max_tokens, world_a_stage["pid"])
        results["B1-harness"]["mutation"] = b1_mutation
    except Exception as error:  # noqa: BLE001
        results["B1-harness"] = {
            "terminal_state": "HARNESS_FAIL",
            "failure": "%s: %s" % (type(error).__name__, error),
        }

    def run_b1_loop() -> dict:
        loop_dir = phase2a / "B1-loop"
        if loop_dir.exists():
            raise FileExistsError(loop_dir)
        loop_dir.mkdir(parents=True)
        sqlite_backup(phase2a / "pristine.sqlite", loop_dir / "carrier.sqlite")
        loop_mutation = mutate_remove_u1_settlement(loop_dir / "carrier.sqlite")
        probe_command = [
            "/usr/bin/python3",
            str(lab_root / "execution-information-loop" / "production_runtime_bridge.py"),
            "execute-probe",
            "--database", str(loop_dir / "carrier.sqlite"),
            "--demand-id", "handoff-u2",
            "--advancement", f"b1-loop-probe-{LABEL}",
            "--evaluated-at", utc_now(),
        ]
        probe_env = os.environ.copy()
        probe_env["SIMIGO_RUNTIME_ROOT"] = str(lab_root)
        probe_env["SIMIGO_INFO_SNAPSHOT_PATH"] = str(
            lab_root / "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite")
        probe_env["SIMIGO_INFO_VALIDITY_POLICY_PATH"] = str(
            lab_root / "integrated-es-palace/mlx-smoke-v1/ISOLATED_VALIDITY_POLICY.json")
        probe_log = loop_dir / "logs" / "execute-probe.log"
        probe_log.parent.mkdir(parents=True)
        started = time.time()
        with probe_log.open("wb") as log:
            probe = subprocess.run(probe_command, cwd=str(lab_root), stdout=log,
                                   stderr=subprocess.STDOUT, env=probe_env, timeout=300)
        lines = probe_log.read_text(errors="replace").strip().splitlines()
        probe_result = json.loads(lines[-1]) if lines else {}
        return {
            "terminal_state": "OBSERVED" if probe.returncode == 0 else "HARNESS_FAIL",
            "exit_code": probe.returncode,
            "wall_seconds": round(time.time() - started, 3),
            "mutation": loop_mutation,
            "probe": probe_result,
            "log": str(probe_log),
            "log_sha256": sha256_file(probe_log),
        }

    results["B1-loop"] = safe_condition("B1-loop", run_b1_loop)

    b2 = compare_worlds(results.get("B0-A", {}), results.get("B0-B", {}))
    write_json(run_root / "phase2a" / "B2.json", b2)

    def run_b3a() -> dict:
        case_dir = prepare_case(phase2a, "B3a", lambda path: None)
        # prepare_case already copied; mutate now, before U2.
        mutation = mutate_tamper_u1_object(case_dir / "carrier.sqlite")
        result = u2_case(binary, case_dir, "B3a", model_dir, lab_root,
                         args.max_tokens, world_a_stage["pid"])
        result["mutation"] = mutation
        return result

    def run_b3b() -> dict:
        case_dir = prepare_case(phase2a, "B3b", lambda path: None)
        mutation = mutate_substitute_u1_value(case_dir / "carrier.sqlite", lab_root)
        result = u2_case(binary, case_dir, "B3b", model_dir, lab_root,
                         args.max_tokens, world_a_stage["pid"])
        result["mutation"] = mutation
        return result

    def run_b3c() -> dict:
        case_dir = prepare_case(phase2a, "B3c", lambda path: None)
        mutation = mutate_dependency_pointer(case_dir / "carrier.sqlite", lab_root)
        result = u2_case(binary, case_dir, "B3c", model_dir, lab_root,
                         args.max_tokens, world_a_stage["pid"])
        result["mutation"] = mutation
        return result

    results["B3a"] = safe_condition("B3a", run_b3a)
    results["B3b"] = safe_condition("B3b", run_b3b)
    results["B3c"] = safe_condition("B3c", run_b3c)

    claims = summarize_claims(results, b2, {"W_A": b4_a, "W_B": b4_b})
    sanitized = {
        name: {key: value for key, value in result.items() if key != "evidence"}
        for name, result in results.items()
    }
    summary = {
        "schema_id": "SIMIGO-CAUSALITY-PHASE2-SUMMARY-V1",
        "run_id": LABEL,
        "created_at_utc": utc_now(),
        "terminal_state": "OBSERVED",
        "run_root": str(run_root),
        "worlds": {
            "W_A": {"stage_a": world_a_stage, "b4": b4_a},
            "W_B": {"stage_a": world_b_stage, "b4": b4_b},
        },
        "conditions": sanitized,
        "b2": b2,
        "admission_conditions": admission_conditions(results),
        "claims": claims,
    }
    write_json(run_root / "summary.json", summary)
    write_json(run_root / "phase2a" / "conditions.json", {
        "schema_id": "SIMIGO-CAUSALITY-PHASE2-CONDITIONS-V1",
        "created_at_utc": utc_now(),
        "results": sanitized,
    })
    return 0


if __name__ == "__main__":
    sys.exit(main())
