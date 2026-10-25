#!/usr/bin/env python3
"""D-round runner: ordinary task entry end-to-end (no handoff orchestration).

Each world is defined by the Information Space's own public API, then executed
ONLY through `SimiGoTaskRun`, the ordinary production task entry. The runner
never supplies an input text, a settled value, a template or a nonce to the
entry; it only names the task item and the model snapshot.

Conditions:
  B0-A / B0-B   two worlds, new independent nonces, U1 then U2 through the
                ordinary entry.
  B1-missing    U1 settlement removed before U2.
  B2-tampered   U1 settlement object bytes flipped before U2.
  B3-dependency U2's declared dependency set rewritten before U2.

The runner writes only below --run-root.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

CONTINUATION_POINT = "bounded-production-runtime-integration"
ITEM_SOURCE = "TASK-SOURCE"
ITEM_U1 = "TASK-U1"
ITEM_U2 = "TASK-U2"
DEMAND_U1 = "task-u1"
DEMAND_U2 = "task-u2"
SETTLEMENT_U1 = "settlement:TASK-U1"
SETTLEMENT_SOURCE = "settlement:TASK-SOURCE"


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def digest(value) -> str:
    return hashlib.sha256(
        json.dumps(value, ensure_ascii=False, sort_keys=True,
                   separators=(",", ":")).encode("utf-8")
    ).hexdigest()


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


def connect_readonly(path: Path) -> sqlite3.Connection:
    connection = sqlite3.connect("file:%s?mode=ro" % path, uri=True)
    connection.row_factory = sqlite3.Row
    return connection


def run_process(command: list[str], log_path: Path, timeout: int) -> dict:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.time()
    with log_path.open("wb") as log:
        process = subprocess.Popen(
            command, cwd=str(Path(command[0]).parent), stdout=log,
            stderr=subprocess.STDOUT, env=os.environ.copy())
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
# task definition (fixture) — built with the IS's own public API
# --------------------------------------------------------------------------


def load_validity_policy(lab_root: Path) -> dict:
    path = lab_root / "integrated-es-palace/mlx-smoke-v1/ISOLATED_VALIDITY_POLICY.json"
    policy = json.loads(path.read_text(encoding="utf-8"))
    policy["policy_sha256"] = digest(
        {key: value for key, value in policy.items() if key != "policy_sha256"})
    return policy


def settlement_basis(source_payload, result_value, source_version,
                     dependency_object_ids, evaluated_at, valid_until, policy):
    return {
        "source_payload_sha256": digest(source_payload),
        "result_value_sha256": digest(result_value),
        "source_version": source_version,
        "dependency_object_ids": dependency_object_ids,
        "evaluated_at_utc": evaluated_at,
        "valid_until_utc": valid_until,
        "validity_policy": policy,
    }


def define_ordinary_task(database: Path, lab_root: Path, run_label: str) -> dict:
    sys.path.insert(0, str(lab_root / "execution-information-loop"))
    from carrier_loop import CarrierInformationLoop  # noqa: PLC0415

    policy = load_validity_policy(lab_root)
    valid_until = policy["default_valid_until_utc"]
    evaluated_at = utc_now()
    secret = secrets.token_hex(8)
    checksum = hashlib.sha256(("checksum:" + secret).encode()).hexdigest()[:4]
    log_text = "\n".join([
        "SIMIGO-ORDINARY-TASK-LOG-V1",
        "run=%s" % run_label,
        "site=lab-north",
        "secret=%s" % secret,
        "checksum=%s" % checksum,
    ])
    loop = CarrierInformationLoop.create(str(database))
    try:
        source_payload = {
            "schema_id": "SIMIGO-ORDINARY-SOURCE-V1",
            "run_label": run_label,
            "site": "lab-north",
            "log_text": log_text,
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
        source_basis = settlement_basis(
            source_payload, source_value, source_version, {}, evaluated_at,
            valid_until, policy)
        registration = loop.settle(
            "task-registration", ITEM_SOURCE,
            {"value": source_value, **source_basis}, source_basis)

        u1_payload = {
            "schema_id": "SIMIGO-ORDINARY-STEP-V1",
            "step": 1,
            "model_task": "extract_secret",
            "answer_format": "SECRET=<secret>",
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
            "next_input_template": (
                "\nStep 2: the secret from step 1 is {secret}. "
                "The checksum from the session log is {checksum}.\n"
                "Reply with exactly one line and nothing else: "
                "ANSWER=<secret>-<checksum>\nAnswer:"
            ),
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
        "secret_sha256": digest(secret),
        "checksum": checksum,
        "log_text_sha256": digest(log_text),
        "source_settlement_object_id": registration["object_id"],
        "u1_item_object_id": u1["object_id"],
        "u2_item_object_id": u2["object_id"],
        "u1_template_sha256": hashlib.sha256(
            u1_payload["next_input_template"].encode()).hexdigest(),
        "u2_template_sha256": hashlib.sha256(
            u2_payload["next_input_template"].encode()).hexdigest(),
    }


# --------------------------------------------------------------------------
# evidence readers
# --------------------------------------------------------------------------


def current_object(connection: sqlite3.Connection, dependency_id: str):
    row = connection.execute(
        "SELECT content_address FROM dependency_entries WHERE dependency_id=? "
        "ORDER BY append_order DESC LIMIT 1", (dependency_id,)).fetchone()
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


def current_item(connection: sqlite3.Connection, item_id: str):
    row = connection.execute(
        "SELECT record_object FROM is_index_entries WHERE srs_identity=? "
        "ORDER BY append_order DESC LIMIT 1", ("item:" + item_id,)).fetchone()
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


def task_state(database: Path) -> dict:
    connection = connect_readonly(database)
    try:
        return {
            "u1_settlement": current_object(connection, SETTLEMENT_U1),
            "source_settlement": current_object(connection, SETTLEMENT_SOURCE),
            "u2_item": current_item(connection, ITEM_U2),
        }
    finally:
        connection.close()


def settlement_value(database: Path, item_id: str) -> dict:
    connection = connect_readonly(database)
    try:
        settlement = current_object(connection, "settlement:" + item_id)
    finally:
        connection.close()
    return (settlement or {}).get("result", {}).get("value", {})


# --------------------------------------------------------------------------
# isolated mutations
# --------------------------------------------------------------------------


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
    sys.path.insert(0, str(lab_root / "execution-information-loop"))
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


# --------------------------------------------------------------------------
# nonce surface audit (before U2 starts)
# --------------------------------------------------------------------------


def files_contain(directory: Path, needle: str) -> list[str]:
    hits: list[str] = []
    if directory.is_file():
        candidates = [directory]
    elif directory.exists():
        candidates = sorted(path for path in directory.rglob("*") if path.is_file())
    else:
        return hits
    for path in candidates:
        try:
            if needle in path.read_bytes().decode("utf-8", errors="ignore"):
                hits.append(str(path))
        except OSError:
            continue
    return hits


def audit_nonce(world: Path, other_world: Path, planned_argv: list[str]) -> dict:
    """Audit every U2 *input* surface before U2 starts.

    The U1 evidence file is the U1 entry's own output record, not a channel
    the U2 entry receives: U2's argv names only its own --out and a fresh
    --state-dir, and the entry source has no evidence-read path. It is
    therefore reported explicitly as an allowlisted occurrence rather than
    silently ignored. Everything the U2 process can actually receive or the
    other world contains must be free of this world's nonce.
    """
    connection = connect_readonly(world / "carrier.sqlite")
    try:
        settlement = current_object(connection, SETTLEMENT_U1)
    finally:
        connection.close()
    if settlement is None:
        raise RuntimeError("U1 settlement missing for nonce audit")
    nonce = settlement["result"]["value"]["secret"]
    argv_text = "\0".join(planned_argv)
    env_text = "\0".join("%s=%s" % (key, value) for key, value in os.environ.items())
    u2_output = world / "evidence" / "u2.json"
    u2_log = world / "logs" / "u2.log"
    violations = {
        "argv": nonce in argv_text,
        "environment": nonce in env_text,
        "u2_state_directory": bool(files_contain(world / "state" / "u2", nonce)),
        "u2_output_path": (u2_output.exists()
                           and bool(files_contain(u2_output, nonce))),
        "u2_process_log": (u2_log.exists()
                           and bool(files_contain(u2_log, nonce))),
        "other_world_database": bool(
            nonce in (other_world / "carrier.sqlite").read_bytes()
            .decode("utf-8", errors="ignore")),
        "other_world_state": bool(files_contain(other_world / "state", nonce)),
        "other_world_evidence": bool(files_contain(other_world / "evidence", nonce)),
        "other_world_logs": bool(files_contain(other_world / "logs", nonce)),
        "attempt_directories": bool(
            files_contain(world.parent / "attempts", nonce)),
    }
    u1_evidence = world / "evidence" / "u1.json"
    return {
        "schema_id": "SIMIGO-ORDINARY-TASK-B4-V1",
        "world": world.name,
        "audited_at_utc": utc_now(),
        "nonce_sha256": hashlib.sha256(nonce.encode()).hexdigest(),
        "nonce_length": len(nonce),
        "allowlisted_occurrences": {
            "primary_database": str(world / "carrier.sqlite"),
            "source_payload_log_text": True,
            "source_registration_value": True,
            "u1_settlement_result": True,
            "u1_model_input_and_state": True,
            "same_world_u1_evidence": str(u1_evidence),
            "same_world_u1_evidence_contains_nonce": bool(
                u1_evidence.exists() and files_contain(u1_evidence, nonce)),
        },
        "u2_input_surfaces": [
            "argv", "environment", "state/u2", "evidence/u2.json",
            "logs/u2.log", "world-b carrier.sqlite", "world-b state",
            "world-b evidence", "world-b logs", "worlds/attempts",
        ],
        "surface_contains_nonce": violations,
        "cross_contaminated": any(violations.values()),
        "verdict": "CLEAN" if not any(violations.values()) else "CONTAMINATED",
    }


# --------------------------------------------------------------------------
# orchestration
# --------------------------------------------------------------------------


def run_entry(binary: Path, case_dir: Path, lab_root: Path, model_dir: Path,
              item: str, demand: str, advancement: str, state_name: str,
              max_tokens: int) -> dict:
    state_dir = case_dir / "state" / state_name
    state_dir.mkdir(parents=True, exist_ok=True)
    evidence_path = case_dir / "evidence" / ("%s.json" % state_name)
    command = [
        str(binary),
        "--database", str(case_dir / "carrier.sqlite"),
        "--item", item,
        "--demand", demand,
        "--advancement", advancement,
        "--evaluated-at", utc_now(),
        "--model-dir", str(model_dir),
        "--lab-root", str(lab_root),
        "--state-dir", str(state_dir),
        "--out", str(evidence_path),
        "--max-tokens", str(max_tokens),
    ]
    metadata = run_process(command, case_dir / "logs" / ("%s.log" % state_name), 1800)
    evidence = read_json(evidence_path) if evidence_path.exists() else None
    metadata.update({
        "state_directory": str(state_dir),
        "evidence_path": str(evidence_path),
        "evidence_sha256": sha256_file(evidence_path) if evidence_path.exists() else None,
        "terminal_state": evidence.get("terminal_state") if evidence else "NO_EVIDENCE",
        "evidence": evidence,
    })
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


def answer_of(evidence: dict) -> str:
    text = evidence.get("generated_text") or ""
    match = re.search(r"ANSWER=([A-Za-z0-9]+-[A-Za-z0-9]+)", text)
    return match.group(1) if match else ""


def positive_checks(definition: dict, u1: dict, u2: dict, database: Path) -> dict:
    ev1 = u1.get("evidence") or {}
    ev2 = u2.get("evidence") or {}
    state = task_state(database)
    u1_settlement = state["u1_settlement"] or {}
    source_settlement = state["source_settlement"] or {}
    u1_value = (u1_settlement.get("result") or {}).get("value", {})
    u2_value = settlement_value(database, ITEM_U2)
    secret = u1_value.get("secret", "")
    checksum = (source_settlement.get("result") or {}).get("value", {}).get("checksum", "")
    expected = "%s-%s" % (secret, checksum)
    answer = answer_of(ev2)
    counters1 = ev1.get("counters") or {}
    counters2 = ev2.get("counters") or {}
    u1_actions = (ev1.get("settlement") or {}).get("actions") or []
    admission1 = ev1.get("input_admission") or {}
    admission2 = ev2.get("input_admission") or {}
    checks1 = admission1.get("checks") or {}
    checks2 = admission2.get("checks") or {}
    return {
        "u1_settled": ev1.get("terminal_state") == "TASK_SETTLED",
        "u1_generation_exactly_once": counters1.get("model_continuation_calls") == 1
        and counters1.get("tokenize_text_calls") == 1
        and counters1.get("tokenize_seed_calls") == 1,
        "u1_admission_admitted": ev1.get("input_admission_status") == "ADMITTED",
        "u1_admission_checks_all_true": bool(checks1) and all(checks1.values()),
        "u1_admitted_sha_matches_evidence": bool(ev1.get("admitted_input_sha256"))
        and ev1.get("admitted_input_sha256") == (admission1.get("input_sha256")),
        "u1_settled_input_matches_admitted": bool(ev1.get("admitted_input_sha256"))
        and u1_value.get("admitted_input_sha256") == ev1.get("admitted_input_sha256"),
        "u1_settled_dependency_matches_source":
            (u1_value.get("admitted_dependency_settlement_object_ids") or {})
            .get(ITEM_SOURCE) == source_settlement.get("_object_id"),
        "u1_bound_source_log_text": [
            binding.get("item_id") for binding in (ev1.get("bindings") or [])
        ] == [ITEM_SOURCE],
        "u1_settlement_object_matches_state": any(
            action.get("item_id") == ITEM_U1
            and action.get("settlement_object_id") == u1_settlement.get("_object_id")
            for action in u1_actions),
        "u2_settled": ev2.get("terminal_state") == "TASK_SETTLED",
        "u2_generation_exactly_once": counters2.get("model_continuation_calls") == 1
        and counters2.get("tokenize_text_calls") == 1
        and counters2.get("tokenize_seed_calls") == 1,
        "u2_admission_admitted": ev2.get("input_admission_status") == "ADMITTED",
        "u2_admission_checks_all_true": bool(checks2) and all(checks2.values()),
        "u2_admitted_sha_matches_evidence": bool(ev2.get("admitted_input_sha256"))
        and ev2.get("admitted_input_sha256") == (admission2.get("input_sha256")),
        "u2_settled_input_matches_admitted": bool(ev2.get("admitted_input_sha256"))
        and u2_value.get("admitted_input_sha256") == ev2.get("admitted_input_sha256"),
        "u2_settled_dependencies_match_admitted":
            bool(ev2.get("dependency_settlement_object_ids"))
            and u2_value.get("admitted_dependency_settlement_object_ids")
            == ev2.get("dependency_settlement_object_ids"),
        "u2_declared_dependencies": sorted(
            ev2.get("declared_dependencies") or []) == [ITEM_SOURCE, ITEM_U1],
        "u2_secret_bound_to_u1_settlement":
            (ev2.get("dependency_settlement_object_ids") or {}).get(ITEM_U1)
            == u1_settlement.get("_object_id"),
        "u2_checksum_bound_to_source_settlement":
            (ev2.get("dependency_settlement_object_ids") or {}).get(ITEM_SOURCE)
            == source_settlement.get("_object_id"),
        "u2_input_contains_admitted_secret": bool(secret)
        and any(binding.get("placeholder") == "secret" and binding.get("value") == secret
                for binding in (ev2.get("bindings") or [])),
        "u2_input_contains_admitted_checksum": bool(checksum)
        and any(binding.get("placeholder") == "checksum" and binding.get("value") == checksum
                for binding in (ev2.get("bindings") or [])),
        "u2_answer_matches_settled_value": bool(answer) and answer == expected,
        "u2_settled_answer_equals_generated": bool(answer)
        and answer == u2_value.get("answer", ""),
        "u2_template_unchanged": definition["u2_template_sha256"]
        == hashlib.sha256(
            ((state["u2_item"] or {}).get("source_payload") or {})
            .get("next_input_template", "").encode()).hexdigest(),
    }


def extract_target_block(package_text: str, name: str) -> str:
    marker = 'name: "%s"' % name

    def balanced(start: int) -> str:
        depth = 0
        for offset in range(start, len(package_text)):
            character = package_text[offset]
            if character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
                if depth == 0:
                    return package_text[start:offset + 1]
        return ""

    for opener in (".executableTarget(", ".target("):
        index = package_text.find(opener)
        while index >= 0:
            block = balanced(index)
            if marker in block:
                return block
            index = package_text.find(opener, index + 1)
    return ""


def path_independence(lab_root: Path, binary: Path, results: dict) -> dict:
    """Prove the D entry is a separate target with no handoff orchestration."""
    package_root = lab_root / "simigo2-experimental"
    sources = [
        package_root / "Sources/SimiGoTaskRun/main.swift",
        package_root / "Sources/SimiGoTaskRun/TaskResultContract.swift",
    ]
    forbidden_tokens = {
        "readSettlement(": False,
        "next_input_template": False,
        "input_bindings": False,
        "replacingOccurrences": False,
        "ProcessInfo.processInfo.environment": False,
        "RealModelHandoff": False,
    }
    source_identity: dict[str, str] = {}
    for path in sources:
        text = path.read_text(encoding="utf-8")
        source_identity[str(path.relative_to(lab_root))] = hashlib.sha256(
            text.encode("utf-8")).hexdigest()
        for token in forbidden_tokens:
            if token in text:
                forbidden_tokens[token] = True
    target_block = extract_target_block(
        (package_root / "Package.swift").read_text(encoding="utf-8"),
        "SimiGoTaskRun")
    invoked = []
    for value in results.values():
        candidates = []
        if isinstance(value.get("entry"), dict):
            candidates.append(value["entry"])
        for key in ("u1", "u2"):
            if isinstance(value.get(key), dict):
                candidates.append(value[key])
        for entry in candidates:
            if entry.get("argv"):
                invoked.append(entry["argv"][0])
    handoff_used = any("RealModelHandoff" in command for command in invoked)
    checks = {
        "entry_source_has_no_settlement_read":
            not forbidden_tokens["readSettlement("]
            and not forbidden_tokens["next_input_template"]
            and not forbidden_tokens["input_bindings"],
        "entry_source_has_no_template_interpolation":
            not forbidden_tokens["replacingOccurrences"],
        "entry_source_reads_no_environment":
            not forbidden_tokens["ProcessInfo.processInfo.environment"],
        "entry_target_does_not_link_handoff":
            bool(target_block) and "RealModelHandoff" not in target_block
            and not forbidden_tokens["RealModelHandoff"],
        "only_the_ordinary_entry_was_invoked": bool(invoked)
        and not handoff_used,
    }
    return {
        "schema_id": "SIMIGO-ORDINARY-TASK-PATH-INDEPENDENCE-V1",
        "entry_binary": str(binary),
        "entry_target": "SimiGoTaskRun",
        "entry_sources": source_identity,
        "forbidden_source_tokens": forbidden_tokens,
        "target_block": target_block,
        "invoked_entry_commands": sorted(set(invoked)),
        "handoff_binary_invoked": handoff_used,
        "checks": checks,
        "verdict": "PASS" if all(checks.values()) else "FAIL",
    }


def negative_checks(entry: dict, expected_stage: str) -> dict:
    evidence = entry.get("evidence") or {}
    counters = evidence.get("counters") or {}
    refusal = evidence.get("input_admission_refusal") or {}
    return {
        "refused_before_generation": evidence.get("terminal_state") == "INPUT_ADMISSION_REFUSED",
        "admission_status_refused": evidence.get("input_admission_status") == "ADMISSION_REFUSED",
        "stage_matches": refusal.get("stage") == expected_stage,
        "tokenize_text_zero": counters.get("tokenize_text_calls") == 0,
        "tokenize_seed_zero": counters.get("tokenize_seed_calls") == 0,
        "generation_zero": counters.get("model_continuation_calls") == 0,
        "generation_not_entered": evidence.get("generation_entered") is False,
        "database_unchanged": evidence.get("database_unchanged") is True,
        "state_unchanged": evidence.get("state_unchanged") is True,
    }


def compare_worlds(world_a: dict, world_b: dict) -> dict:
    ev_a = world_a["u2"].get("evidence") or {}
    ev_b = world_b["u2"].get("evidence") or {}
    answer_a = answer_of(ev_a)
    answer_b = answer_of(ev_b)
    checks = {
        "u2_templates_identical":
            world_a["definition"]["u2_template_sha256"]
            == world_b["definition"]["u2_template_sha256"],
        "cold_seeds_identical": ev_a.get("seed_sha256") == ev_b.get("seed_sha256")
        and ev_a.get("seed_source") == "builtin_cold_seed"
        and ev_b.get("seed_source") == "builtin_cold_seed",
        "u1_settlements_differ":
            (ev_a.get("dependency_settlement_object_ids") or {}).get(ITEM_U1)
            != (ev_b.get("dependency_settlement_object_ids") or {}).get(ITEM_U1)
            and bool((ev_a.get("dependency_settlement_object_ids") or {}).get(ITEM_U1))
            and bool((ev_b.get("dependency_settlement_object_ids") or {}).get(ITEM_U1)),
        "u2_inputs_differ": ev_a.get("admitted_input_sha256")
        != ev_b.get("admitted_input_sha256")
        and bool(ev_a.get("admitted_input_sha256"))
        and bool(ev_b.get("admitted_input_sha256")),
        "outputs_differ": bool(answer_a) and bool(answer_b) and answer_a != answer_b,
        "each_output_matches_its_own_world":
            answer_a == world_a["expected_answer"] and answer_b == world_b["expected_answer"],
    }
    checks["world_pair_distinguished"] = all([
        checks["u2_templates_identical"], checks["cold_seeds_identical"],
        checks["u1_settlements_differ"], checks["u2_inputs_differ"],
        checks["outputs_differ"], checks["each_output_matches_its_own_world"]])
    return checks


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", required=True)
    parser.add_argument("--lab-root", required=True)
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--max-tokens", type=int, default=32)
    arguments = parser.parse_args()

    run_root = Path(arguments.run_root).expanduser().resolve()
    lab_root = Path(arguments.lab_root).expanduser().resolve()
    model_dir = Path(arguments.model_dir).expanduser().resolve()
    binary = lab_root / "simigo2-experimental/.build/debug/SimiGoTaskRun"
    if not binary.is_file():
        raise SystemExit("ordinary entry binary missing: %s" % binary)

    worlds_root = run_root / "worlds"
    negative_root = run_root / "phase2"
    for directory in (worlds_root, negative_root):
        if directory.exists() and any(directory.iterdir()):
            raise SystemExit("refusing to overwrite %s" % directory)
        directory.mkdir(parents=True, exist_ok=True)

    results: dict[str, dict] = {}
    worlds: dict[str, dict] = {}

    for name, label in (("world-a", "d-world-a"), ("world-b", "d-world-b")):
        attempts = []
        settled = None
        for attempt in range(1, 4):
            world = worlds_root / name
            if world.exists():
                archive = worlds_root / "attempts" / (
                    "%s-attempt-%d" % (name, attempt - 1))
                archive.parent.mkdir(parents=True, exist_ok=True)
                if archive.exists():
                    raise SystemExit("refusing to overwrite %s" % archive)
                world.rename(archive)
            world.mkdir()
            definition = define_ordinary_task(
                world / "carrier.sqlite", lab_root, label)
            u1 = run_entry(binary, world, lab_root, model_dir, ITEM_U1, DEMAND_U1,
                           "d-%s-u1-a%d" % (name, attempt), "u1",
                           arguments.max_tokens)
            attempts.append({
                "attempt": attempt,
                "world_path": str(world),
                "terminal_state": u1["terminal_state"],
                "exit_code": u1["exit_code"],
                "evidence_path": u1["evidence_path"],
                "evidence_sha256": u1["evidence_sha256"],
                "log": u1["log"],
                "log_sha256": u1["log_sha256"],
                "failure": (u1.get("evidence") or {}).get("failure"),
            })
            if u1["terminal_state"] == "TASK_SETTLED":
                settled = {"world": world, "definition": definition, "u1": u1}
                break
            if u1["terminal_state"] == "INPUT_ADMISSION_REFUSED":
                # A refusal is a mechanism result, not model variance: never retry.
                break
        if settled is None:
            write_json(run_root / "summary.json", {
                "schema_id": "SIMIGO-ORDINARY-TASK-SUMMARY-V1",
                "terminal_state": "BLOCKED_NOT_RUN",
                "world": name,
                "attempts": attempts,
            })
            return 1
        worlds[name] = {
            "definition": settled["definition"],
            "u1": settled["u1"],
            "world": settled["world"],
            "path": str(settled["world"]),
            "attempts": attempts,
        }

    # Snapshot each world's IS state AFTER U1 and BEFORE U2, so the negative
    # conditions share exactly the state the positive U2 would have consumed.
    for name in worlds:
        world = worlds_root / name
        sqlite_backup(world / "carrier.sqlite",
                      run_root / "phase2" / ("base-%s.sqlite" % name))

    planned_argv = [
        str(binary), "--database", "<case>", "--item", ITEM_U2,
        "--demand", DEMAND_U2, "--advancement", "<id>", "--evaluated-at", "<utc>",
        "--model-dir", str(model_dir), "--lab-root", str(lab_root),
        "--state-dir", "<case>/state/u2", "--out", "<case>/evidence/u2.json",
    ]
    b4 = {
        "W_A": audit_nonce(worlds_root / "world-a", worlds_root / "world-b", planned_argv),
        "W_B": audit_nonce(worlds_root / "world-b", worlds_root / "world-a", planned_argv),
    }
    write_json(run_root / "logs" / "nonce-surface-audit.json", b4)
    if b4["W_A"]["cross_contaminated"] or b4["W_B"]["cross_contaminated"]:
        write_json(run_root / "summary.json", {
            "schema_id": "SIMIGO-ORDINARY-TASK-SUMMARY-V1",
            "terminal_state": "INVALID_CONDITION",
            "B4": b4,
        })
        return 1

    for name in worlds:
        world = worlds_root / name
        u2 = run_entry(binary, world, lab_root, model_dir, ITEM_U2, DEMAND_U2,
                       "d-%s-u2" % name, "u2", arguments.max_tokens)
        worlds[name]["u2"] = u2
        state = task_state(world / "carrier.sqlite")
        u1_value = ((state["u1_settlement"] or {}).get("result") or {}).get(
            "value", {})
        source_value = ((state["source_settlement"] or {}).get("result") or {}).get(
            "value", {})
        worlds[name]["expected_answer"] = "%s-%s" % (
            u1_value.get("secret", ""), source_value.get("checksum", ""))
        worlds[name]["positive_checks"] = positive_checks(
            worlds[name]["definition"], u1=worlds[name]["u1"], u2=u2,
            database=world / "carrier.sqlite")

    for name in worlds:
        results["B0-%s" % name[-1].upper()] = {
            "terminal_state": worlds[name]["u2"]["terminal_state"],
            "u1": {key: value for key, value in worlds[name]["u1"].items()
                   if key != "evidence"},
            "u2": {key: value for key, value in worlds[name]["u2"].items()
                   if key != "evidence"},
            "positive_checks": worlds[name]["positive_checks"],
        }

    b2 = compare_worlds(worlds["world-a"], worlds["world-b"])
    write_json(run_root / "phase2" / "B2-world-comparison.json", b2)

    negative = [
        ("B1-missing", "SETTLEMENT_NOT_ADMITTED", mutate_remove_u1),
        ("B2-tampered", "SETTLEMENT_OBJECT_UNREADABLE", mutate_tamper_u1),
        ("B3-dependency", "INPUT_BINDING_DEPENDENCY_NOT_DECLARED",
         lambda path: mutate_dependency_set(path, lab_root)),
    ]
    for case, stage, mutation in negative:
        def execute(case=case, stage=stage, mutation=mutation):
            case_dir = negative_root / case
            case_dir.mkdir()
            shutil.copyfile(run_root / "phase2" / "base-world-a.sqlite",
                            case_dir / "carrier.sqlite")
            applied = mutation(case_dir / "carrier.sqlite")
            entry = run_entry(binary, case_dir, lab_root, model_dir, ITEM_U2,
                              DEMAND_U2, "d-%s-u2" % case, "u2",
                              arguments.max_tokens)
            checks = negative_checks(entry, stage)
            return {
                "terminal_state": entry["terminal_state"],
                "mutation": applied,
                "entry": {key: value for key, value in entry.items()
                          if key != "evidence"},
                "refusal": (entry.get("evidence") or {}).get("input_admission_refusal"),
                "counters": (entry.get("evidence") or {}).get("counters"),
                "checks": checks,
                "verdict": "PASS" if all(checks.values()) else "FAIL",
            }
        results[case] = safe_condition(case, execute)

    positive_all = all(
        all(worlds[name]["positive_checks"].values()) for name in worlds)
    negative_all = all(
        results[case].get("verdict") == "PASS"
        for case in ("B1-missing", "B2-tampered", "B3-dependency"))
    independence = path_independence(lab_root, binary, results)
    independence_ok = independence["verdict"] == "PASS"
    summary = {
        "schema_id": "SIMIGO-ORDINARY-TASK-SUMMARY-V1",
        "run_id": run_root.name,
        "created_at_utc": utc_now(),
        "terminal_state": ("OBSERVED"
                           if positive_all and negative_all and independence_ok
                           else "INCOMPLETE"),
        "run_root": str(run_root),
        "entry": {
            "binary": str(binary),
            "binary_sha256": sha256_file(binary),
            "binary_size_bytes": binary.stat().st_size,
            "target": "SimiGoTaskRun",
        },
        "worlds": {
            name: {
                "definition": worlds[name]["definition"],
                "attempts": worlds[name]["attempts"],
                "u1": {key: value for key, value in worlds[name]["u1"].items()
                       if key != "evidence"},
                "u2": {key: value for key, value in worlds[name]["u2"].items()
                       if key != "evidence"},
                "expected_answer": worlds[name]["expected_answer"],
                "positive_checks": worlds[name]["positive_checks"],
            }
            for name in worlds
        },
        "b2": b2,
        "b4": b4,
        "path_independence": independence,
        "conditions": results,
        "claims": {
            "D1_ordinary_entry_performs_input_admission":
                "OBSERVED_IN_THE_ORDINARY_TASK_ENTRY"
                if positive_all else "NOT_ESTABLISHED",
            "D2_dual_world_causality":
                "OBSERVED_FOR_TWO_INDEPENDENT_SETTLEMENTS"
                if b2["world_pair_distinguished"] else "NOT_ESTABLISHED",
            "D3_pre_generation_refusal":
                "OBSERVED_BEFORE_TOKENIZE_AND_GENERATION"
                if negative_all else "NOT_ESTABLISHED",
            "D4_path_independence":
                "ENTRY_IS_A_SEPARATE_TARGET_WITHOUT_HANDOFF_ORCHESTRATION"
                if independence_ok else "NOT_ESTABLISHED",
        },
    }
    write_json(run_root / "summary.json", summary)
    write_json(run_root / "phase2" / "conditions.json", {
        "schema_id": "SIMIGO-ORDINARY-TASK-CONDITIONS-V1",
        "created_at_utc": utc_now(),
        "results": results,
    })
    return 0 if summary["terminal_state"] == "OBSERVED" else 1


if __name__ == "__main__":
    sys.exit(main())
