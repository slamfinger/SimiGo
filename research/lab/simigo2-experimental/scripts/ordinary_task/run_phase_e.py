#!/usr/bin/env python3
"""E-round runner: signed settlement provenance, mutation matrix, legacy audit.

Every world is defined through the Information Space's own public API with
`provenance_policy="required"`, so both the source registration and every model
settlement are signed inside the atomic write that materialises them. The
ordinary task entry (`SimiGoTaskRun` -> `continueTask`) consumes them under a
`verify`-only policy and an independent Ed25519 trust anchor that lives outside
every database.

Conditions:
  E0-valid-signature            unmodified signed world-a state, admission only
  E0-A / E0-B                   two independent worlds through the real model
  E1-result-value-only          semantic value changed, digests untouched
  E2-result-and-digests         value plus every digest/event rewritten, no key
  E3-producer-field             producer identity field changed, no re-sign
  E4-task-item-metadata         U1 item metadata changed outside the settlement
  E5-dependency-substitution    another world's signed source swapped in
  E6-signature-removed          self-consistent rewrite, signature index deleted
  E7-anchor-public-key-swapped  trusted key id, attacker public key
  E8-signature-object-retained  self-consistent rewrite, old signature kept

Legacy advancement (bridge `execute`, the path behind
`continueWithRealInformation`) is run on an isolated PALACE carrier so its
reuse decision is observable: a settlement whose signature does not verify is
never reused; the trusted deterministic calculator recomputes it.

The runner writes only below --run-root.
"""
from __future__ import annotations

import argparse
import base64
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
SETTLEMENT_SOURCE = "settlement:TASK-SOURCE"
SETTLEMENT_U1 = "settlement:TASK-U1"
SIGNATURE_SOURCE = "settlement-signature:TASK-SOURCE"
SIGNATURE_U1 = "settlement-signature:TASK-U1"
POLICY_ENV = "SIMIGO_SETTLEMENT_PROVENANCE"
KEY_ENV = "SIMIGO_SETTLEMENT_SIGNING_KEY"
ANCHOR_ENV = "SIMIGO_SETTLEMENT_TRUST_ANCHOR"
RUN_ENV = "SIMIGO_SETTLEMENT_RUN_ID"
EXECUTION_ENV = "SIMIGO_SETTLEMENT_EXECUTION_ID"
BUILD_ENV = "SIMIGO_SETTLEMENT_BUILD_SHA256"
SIGNATURE_SCHEMA = "EINFO-SETTLEMENT-SIGNATURE-V1"
PROVENANCE_SCHEMA = "EINFO-SETTLEMENT-PROVENANCE-V1"


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def digest(value) -> str:
    return hashlib.sha256(
        json.dumps(value, ensure_ascii=False, sort_keys=True,
                   separators=(",", ":")).encode("utf-8")
    ).hexdigest()


def canonical(value) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(",", ":")).encode("utf-8")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    handle = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            handle.update(chunk)
    return handle.hexdigest()


def write_json(path: Path, value) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=1, sort_keys=True) + "\n",
                    encoding="utf-8")


def read_json(path: Path):
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


def run_process(command: list, cwd: Path, log_path: Path, timeout: int,
                env: dict) -> dict:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    started = time.time()
    started_at = utc_now()
    with log_path.open("wb") as log:
        process = subprocess.Popen(
            [str(part) for part in command], cwd=str(cwd), stdout=log,
            stderr=subprocess.STDOUT, env=env)
        timed_out = False
        try:
            exit_code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            process.kill()
            exit_code = process.wait()
    return {
        "argv": [str(part) for part in command],
        "pid": process.pid,
        "cwd": str(cwd),
        "exit_code": exit_code,
        "timed_out": timed_out,
        "wall_seconds": round(time.time() - started, 3),
        "log": str(log_path),
        "log_sha256": sha256_file(log_path),
        "started_at_utc": started_at,
    }


def last_json_line(path: Path):
    for line in reversed(path.read_text(encoding="utf-8",
                                        errors="replace").splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue
    return None


# --------------------------------------------------------------------------
# trust root (outside every database)
# --------------------------------------------------------------------------


def provision_trust(run_root: Path) -> dict:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2] /
                           "execution-information-loop"))
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import (
        Ed25519PrivateKey,
    )

    trust_dir = run_root / "trust"
    trust_dir.mkdir(parents=True, exist_ok=True)
    private = Ed25519PrivateKey.generate()
    private_raw = private.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption(),
    )
    public_raw = private.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    key_id = "e-round-%s" % sha256_bytes(public_raw)[:16]
    key_path = trust_dir / "settlement-signing-key.json"
    anchor_path = trust_dir / "settlement-trust-anchor.json"
    key_document = {
        "schema_id": "EINFO-SETTLEMENT-SIGNING-KEY-V1",
        "algorithm": "Ed25519",
        "key_id": key_id,
        "private_key_base64": base64.b64encode(private_raw).decode("ascii"),
        "public_key_base64": base64.b64encode(public_raw).decode("ascii"),
    }
    anchor_document = {
        "schema_id": "EINFO-SETTLEMENT-TRUST-ANCHOR-V1",
        "algorithm": "Ed25519",
        "key_id": key_id,
        "public_key_base64": base64.b64encode(public_raw).decode("ascii"),
    }
    key_path.write_text(json.dumps(key_document, indent=1, sort_keys=True) + "\n",
                        encoding="utf-8")
    anchor_path.write_text(
        json.dumps(anchor_document, indent=1, sort_keys=True) + "\n",
        encoding="utf-8")
    os.chmod(key_path, 0o600)
    os.chmod(anchor_path, 0o444)

    attacker = Ed25519PrivateKey.generate()
    attacker_public = attacker.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    attacker_anchor_path = trust_dir / "attacker-anchor.json"
    attacker_anchor_path.write_text(json.dumps({
        "schema_id": "EINFO-SETTLEMENT-TRUST-ANCHOR-V1",
        "algorithm": "Ed25519",
        "key_id": key_id,
        "public_key_base64": base64.b64encode(attacker_public).decode("ascii"),
    }, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(attacker_anchor_path, 0o444)
    return {
        "schema_id": "SIMIGO-E-ROUND-TRUST-ROOT-V1",
        "key_id": key_id,
        "key_path": str(key_path),
        "key_sha256": sha256_file(key_path),
        "key_mode": oct(key_path.stat().st_mode & 0o777),
        "anchor_path": str(anchor_path),
        "anchor_sha256": sha256_file(anchor_path),
        "anchor_mode": oct(anchor_path.stat().st_mode & 0o777),
        "public_key_base64": anchor_document["public_key_base64"],
        "public_key_sha256": sha256_bytes(public_raw),
        "attacker_anchor_path": str(attacker_anchor_path),
        "attacker_anchor_sha256": sha256_file(attacker_anchor_path),
        "attacker_public_key_sha256": sha256_bytes(attacker_public),
        "private_key_location": "filesystem only; never a database row",
    }


def child_environment(lab_root: Path, trust: dict, run_label: str,
                      execution_label: str, with_key: bool,
                      anchor_path: str = None, policy: str = "required") -> dict:
    environment = os.environ.copy()
    for name in (KEY_ENV, POLICY_ENV, ANCHOR_ENV, RUN_ENV, EXECUTION_ENV,
                 BUILD_ENV):
        environment.pop(name, None)
    environment[POLICY_ENV] = policy
    environment[ANCHOR_ENV] = anchor_path or trust["anchor_path"]
    if with_key:
        environment[KEY_ENV] = trust["key_path"]
    environment[RUN_ENV] = run_label
    environment[EXECUTION_ENV] = execution_label
    environment[BUILD_ENV] = trust["build_sha256"]
    environment["SIMIGO_INFO_VALIDITY_POLICY_PATH"] = str(
        lab_root / "integrated-es-palace/mlx-smoke-v1/ISOLATED_VALIDITY_POLICY.json")
    environment["SIMIGO_INFO_SNAPSHOT_PATH"] = str(
        lab_root / "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite")
    return environment


# --------------------------------------------------------------------------
# signed task definition
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


def define_ordinary_task(database: Path, lab_root: Path, run_label: str,
                         environment: dict) -> dict:
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
    os.environ.update({key: environment[key] for key in (
        POLICY_ENV, KEY_ENV, ANCHOR_ENV, RUN_ENV, EXECUTION_ENV, BUILD_ENV)})
    loop = CarrierInformationLoop.create(str(database))
    try:
        if loop.provenance_policy != "required":
            raise RuntimeError("definition did not load the required policy")
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
        "source_payload": source_payload,
        "source_version": source_version,
        "valid_until_utc": valid_until,
        "validity_policy": policy,
        "source_settlement_object_id": registration["object_id"],
        "source_signature_object_id": registration["signature_object_id"],
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


def current_signature(connection: sqlite3.Connection, item_id: str):
    row = connection.execute(
        "SELECT record_object FROM is_index_entries WHERE srs_identity=? "
        "ORDER BY append_order DESC LIMIT 1",
        ("settlement-signature:" + item_id,)).fetchone()
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


def history_length(connection: sqlite3.Connection, dependency_id: str) -> int:
    row = connection.execute(
        "SELECT COUNT(*) FROM dependency_entries WHERE dependency_id=?",
        (dependency_id,)).fetchone()
    return int(row[0])


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
# independent signature verification (outside the loop implementation)
# --------------------------------------------------------------------------


def verify_envelope(envelope: dict, anchor: dict, expected_object_id: str,
                    expected_item_id: str) -> dict:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import (
        Ed25519PublicKey,
    )

    public_key = Ed25519PublicKey.from_public_bytes(
        base64.b64decode(anchor["public_key_base64"]))
    payload_bytes = base64.b64decode(envelope["payload_canonical_base64"])
    signature = base64.b64decode(envelope["signature_base64"])
    checks = {
        "schema_id": envelope.get("schema_id") == SIGNATURE_SCHEMA,
        "algorithm": envelope.get("algorithm") == "Ed25519",
        "key_id_matches_anchor": envelope.get("key_id") == anchor["key_id"],
        "object_id_matches": envelope.get("settlement_object_id") == expected_object_id,
        "item_id_matches": envelope.get("item_id") == expected_item_id,
        "payload_is_canonical": canonical(envelope.get("payload")) == payload_bytes,
        "payload_object_id": envelope.get("payload", {}).get(
            "settlement_object_id") == expected_object_id,
        "payload_schema_id": envelope.get("payload", {}).get(
            "schema_id") == PROVENANCE_SCHEMA,
        "ed25519": public_key.verify(signature, payload_bytes) is None,
    }
    return checks


def signature_binding(settlement: dict, envelope: dict,
                      dependency_values: dict) -> dict:
    payload = envelope.get("payload") or {}
    provenance = payload.get("provenance") or {}
    result = settlement.get("result") or {}
    basis = settlement.get("basis") or {}
    return {
        "advancement_bound": payload.get("advancement_id") == settlement.get(
            "advancement_id"),
        "contract_bound": payload.get("settlement_contract") == settlement.get(
            "settlement_contract"),
        "schema_bound": payload.get("settlement_schema_id") == settlement.get(
            "schema_id"),
        "provenance_identical": provenance == settlement.get("provenance"),
        "result_digest_bound": provenance.get("result_value_sha256")
        == result.get("result_value_sha256") == digest(result.get("value")),
        "source_bound": (provenance.get("source") or {}).get("payload_sha256")
        == basis.get("source_payload_sha256"),
        "source_version_bound": (provenance.get("source") or {}).get("version")
        == result.get("source_version"),
        "dependencies_bound": {
            key: value.get("object_id")
            for key, value in (provenance.get("dependencies") or {}).items()
        } == result.get("dependency_object_ids"),
        # An item with no dependencies has nothing to bind: vacuous truth is
        # correct there. ``None`` means the caller could not supply the
        # dependency values, which must stay a failure.
        "dependency_values_bound": all(
            value.get("result_value_sha256")
            == digest((dependency_values or {}).get(key))
            for key, value in (provenance.get("dependencies") or {}).items()
        ) if dependency_values is not None else False,
        "validity_bound": (
            (provenance.get("validity") or {}).get("evaluated_at_utc")
            == result.get("evaluated_at_utc")
            and (provenance.get("validity") or {}).get("valid_until_utc")
            == result.get("valid_until_utc")),
    }


def signature_checks(database: Path, item_id: str, evidence: dict,
                     anchor: dict) -> dict:
    connection = connect_readonly(database)
    try:
        settlement = current_object(connection, "settlement:" + item_id)
        envelope = current_signature(connection, item_id)
        history = history_length(connection, "settlement:" + item_id)
        dependency_values = {}
        for dependency_id in (settlement.get("basis") or {}).get(
                "dependency_object_ids", {}):
            dependency = current_object(connection, "settlement:" + dependency_id)
            dependency_values[dependency_id] = (dependency or {}).get(
                "result", {}).get("value")
    finally:
        connection.close()
    checks = {
        "settlement_present": settlement is not None,
        "signature_present": envelope is not None,
    }
    if settlement is None or envelope is None:
        return checks
    checks.update({
        "signature_object_matches_current_settlement":
            envelope.get("settlement_object_id") == settlement.get("_object_id"),
        "provenance_present": isinstance(settlement.get("provenance"), dict),
        "event_chain": (settlement.get("provenance", {}).get("event", {}).get(
            "sequence") == history),
    })
    checks.update(verify_envelope(
        envelope, anchor, settlement["_object_id"], item_id))
    checks.update(signature_binding(settlement, envelope, dependency_values))
    admission = evidence.get("input_admission") or {}
    reported = {
        entry.get("item_id"): entry.get("settlement_object_id")
        for entry in admission.get("settlement_signatures") or []
    }
    if item_id in reported:
        # The admission descriptor names the settlement object the signature
        # covers; the signature object id is a separate identity.
        checks["admission_signature_object_matches_db"] = (
            reported[item_id] == settlement.get("_object_id")
            and envelope.get("settlement_object_id")
            == settlement.get("_object_id"))
    settlement_evidence = evidence.get("settlement") or {}
    if evidence.get("task_item_id") == item_id:
        # The executed item's report must name the detached signature object it
        # produced and the settlement that signature covers -- two distinct
        # identities. Both are re-derived from the database here.
        checks["reported_signature_object_matches_db"] = (
            settlement_evidence.get("settlement_signature_object_id")
            == envelope.get("_object_id"))
        checks["reported_signed_settlement_matches_db"] = (
            settlement_evidence.get("signed_settlement_object_id")
            == settlement.get("_object_id"))
        checks["reported_signature_action_matches"] = any(
            action.get("item_id") == item_id
            and action.get("settlement_signature_object_id")
            == settlement_evidence.get("settlement_signature_object_id")
            for action in settlement_evidence.get("actions") or [])
    return checks


# --------------------------------------------------------------------------
# isolated mutations
# --------------------------------------------------------------------------


def open_carrier(path: Path):
    sys.path.insert(0, str(Path(__file__).resolve().parents[3] /
                           "database-carrier-replication/implementation"))
    from db_is import DatabaseBackedIS  # noqa: PLC0415

    carrier = DatabaseBackedIS(str(path))
    carrier.validate_schema()
    return carrier


def latest_revision(connection: sqlite3.Connection, dependency_id: str) -> int:
    row = connection.execute(
        "SELECT revision FROM dependency_entries WHERE dependency_id=? "
        "ORDER BY append_order DESC LIMIT 1", (dependency_id,)).fetchone()
    if row is None:
        raise RuntimeError("no dependency history for %s" % dependency_id)
    return int(row[0])


def materialize_revision(database: Path, dependency_id: str, document: dict,
                         reason: str) -> dict:
    carrier = open_carrier(database)
    try:
        revision = latest_revision(carrier.connection, dependency_id) + 1
        content = canonical(document)
        with carrier.atomic_write_group():
            object_id, order = carrier.atomic_dependency_materialization(
                content,
                {"dependency_id": dependency_id, "content_address": "",
                 "revision": revision, "reason": reason})
            carrier.append_index_entry({
                "srs_identity": dependency_id, "record_object": object_id})
        return {"object_id": object_id, "revision": revision,
                "append_order": order, "content_sha256": sha256_bytes(content)}
    finally:
        carrier.close()


def settlement_document(database: Path, dependency_id: str) -> dict:
    connection = connect_readonly(database)
    try:
        value = current_object(connection, dependency_id)
    finally:
        connection.close()
    if value is None:
        raise RuntimeError("missing %s" % dependency_id)
    value.pop("_object_id", None)
    return value


def rewrite_event(document: dict, database: Path) -> None:
    connection = connect_readonly(database)
    try:
        history = connection.execute(
            "SELECT content_address FROM dependency_entries WHERE dependency_id=? "
            "ORDER BY append_order ASC",
            ("settlement:" + document["item_id"],)).fetchall()
    finally:
        connection.close()
    sequence = len(history) + 1
    previous = history[-1]["content_address"] if history else None
    document["provenance"]["event"] = {
        "settlement_event_id": digest({
            "item_id": document["item_id"],
            "sequence": sequence,
            "previous_settlement_object_id": previous,
            "result_value_sha256": document["result"]["result_value_sha256"],
            "evaluated_at_utc": document["result"]["evaluated_at_utc"],
        }),
        "sequence": sequence,
        "previous_settlement_object_id": previous,
    }


def rewrite_result_self_consistent(database: Path, item_id: str,
                                   new_value: dict) -> dict:
    document = settlement_document(database, "settlement:" + item_id)
    old = document["result"]["value"]
    document["result"]["value"] = new_value
    new_digest = digest(new_value)
    document["result"]["result_value_sha256"] = new_digest
    document["basis"]["result_value_sha256"] = new_digest
    document["provenance"]["result_value_sha256"] = new_digest
    rewrite_event(document, database)
    applied = materialize_revision(
        database, "settlement:" + item_id, document,
        "self-consistent rewrite without signing key")
    applied["old_value_sha256"] = digest(old)
    applied["new_value_sha256"] = new_digest
    return applied


def mutate_value_only(database: Path, new_value: dict) -> dict:
    document = settlement_document(database, SETTLEMENT_U1)
    old = document["result"]["value"]
    document["result"]["value"] = new_value
    applied = materialize_revision(
        database, SETTLEMENT_U1, document, "result value replaced only")
    applied["old_value_sha256"] = digest(old)
    applied["declared_result_value_sha256"] = document["result"][
        "result_value_sha256"]
    return applied


def mutate_producer_field(database: Path) -> dict:
    document = settlement_document(database, SETTLEMENT_U1)
    previous = document["provenance"]["producer"]["run_id"]
    document["provenance"]["producer"]["run_id"] = previous + "-tampered"
    applied = materialize_revision(
        database, SETTLEMENT_U1, document, "producer identity field modified")
    applied["previous_run_id"] = previous
    return applied


def mutate_task_item_metadata(database: Path) -> dict:
    sys.path.insert(0, str(Path(__file__).resolve().parents[3] /
                           "execution-information-loop"))
    from carrier_loop import CarrierInformationLoop  # noqa: PLC0415

    loop = CarrierInformationLoop.open(str(database))
    try:
        item = loop.current_item(ITEM_U1)
        if item is None:
            raise RuntimeError("TASK-U1 missing")
        previous_kind = item["source_kind"]
        result = loop.put_source(
            item["demand_id"], ITEM_U1, "model-task-metadata-tampered",
            item["source_version"], item["source_payload"],
            dependencies=list(item["dependencies"]),
            valid_until_utc=item["valid_until_utc"],
            validity_policy=item["validity_policy"])
        loop.commit()
        return {"previous_source_kind": previous_kind,
                "new_source_kind": "model-task-metadata-tampered",
                "new_item_object_id": result["object_id"]}
    finally:
        loop.close()


def copy_settlement(source_db: Path, target_db: Path, item_id: str,
                    replace: bool = True) -> dict:
    """Swap one validly signed settlement (and its item) into another carrier.

    `replace` removes the target item's existing settlement/signature history so
    the imported declaration keeps its original event sequence (revision 1).
    Without it, the imported declaration's event chain would be broken by the
    target's prior history, which would mask the dependency binding under test.
    """
    source = connect_readonly(source_db)
    try:
        item_row = source.execute(
            "SELECT record_object FROM is_index_entries WHERE srs_identity=? "
            "ORDER BY append_order DESC LIMIT 1",
            ("item:" + item_id,)).fetchone()
        settlement_row = source.execute(
            "SELECT content_address FROM dependency_entries WHERE dependency_id=? "
            "ORDER BY append_order DESC LIMIT 1",
            ("settlement:" + item_id,)).fetchone()
        signature_row = source.execute(
            "SELECT record_object FROM is_index_entries WHERE srs_identity=? "
            "ORDER BY append_order DESC LIMIT 1",
            ("settlement-signature:" + item_id,)).fetchone()
        if not (item_row and settlement_row and signature_row):
            raise RuntimeError("source world has no signed %s" % item_id)
        item_content = bytes(source.execute(
            "SELECT content FROM is_objects WHERE object_id=?",
            (item_row["record_object"],)).fetchone()[0])
        settlement_content = bytes(source.execute(
            "SELECT content FROM is_objects WHERE object_id=?",
            (settlement_row["content_address"],)).fetchone()[0])
        signature_content = bytes(source.execute(
            "SELECT content FROM is_objects WHERE object_id=?",
            (signature_row["record_object"],)).fetchone()[0])
    finally:
        source.close()
    if replace:
        connection = sqlite3.connect(str(target_db))
        try:
            connection.execute(
                "DELETE FROM dependency_entries WHERE dependency_id=?",
                ("settlement:" + item_id,))
            connection.execute(
                "DELETE FROM is_index_entries WHERE srs_identity IN (?,?)",
                ("settlement:" + item_id,
                 "settlement-signature:" + item_id))
            connection.commit()
        finally:
            connection.close()
    carrier = open_carrier(target_db)
    try:
        target = carrier.connection
        revision = 1 if replace else latest_revision(
            target, "settlement:" + item_id) + 1
        with carrier.atomic_write_group():
            item_object_id = carrier.write_object(item_content)
            carrier.append_index_entry({
                "srs_identity": "item:" + item_id,
                "record_object": item_object_id})
            settlement_object_id, _ = carrier.atomic_dependency_materialization(
                settlement_content,
                {"dependency_id": "settlement:" + item_id, "content_address": "",
                 "revision": revision,
                 "reason": "validly signed dependency substituted"})
            carrier.append_index_entry({
                "srs_identity": "settlement:" + item_id,
                "record_object": settlement_object_id})
            signature_object_id = carrier.write_object(signature_content)
            carrier.append_index_entry({
                "srs_identity": "settlement-signature:" + item_id,
                "record_object": signature_object_id})
        return {"item_object_id": item_object_id,
                "settlement_object_id": settlement_object_id,
                "signature_object_id": signature_object_id,
                "revision": revision}
    finally:
        carrier.close()


def remove_signature(database: Path, item_id: str) -> dict:
    connection = sqlite3.connect(str(database))
    try:
        deleted = connection.execute(
            "DELETE FROM is_index_entries WHERE srs_identity=?",
            ("settlement-signature:" + item_id,)).rowcount
        connection.commit()
        return {"deleted_signature_entries": deleted}
    finally:
        connection.close()


def mutate_legacy_settlement(database: Path, item_id: str,
                             new_value_patch: dict) -> dict:
    document = settlement_document(database, "settlement:" + item_id)
    old_value = document["result"]["value"]
    value = dict(old_value)
    value.update(new_value_patch)
    new_digest = digest(value)
    document["result"]["value"] = value
    document["result"]["result_value_sha256"] = new_digest
    document["basis"]["result_value_sha256"] = new_digest
    document["provenance"]["result_value_sha256"] = new_digest
    rewrite_event(document, database)
    applied = materialize_revision(
        database, "settlement:" + item_id, document,
        "legacy settlement self-consistent rewrite without signing key")
    applied["old_value_sha256"] = digest(old_value)
    return applied


# --------------------------------------------------------------------------
# entry execution
# --------------------------------------------------------------------------


def run_entry(binary: Path, case_dir: Path, lab_root: Path, model_dir: Path,
              item: str, demand: str, advancement: str, state_name: str,
              max_tokens: int, environment: dict, probe: bool = False) -> dict:
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
        "--run-id", "e-%s" % advancement,
    ]
    if probe:
        command.append("--admission-probe")
    metadata = run_process(command, lab_root, case_dir / "logs" / (
        "%s.log" % state_name), 1800, environment)
    evidence = read_json(evidence_path) if evidence_path.exists() else None
    metadata.update({
        "state_directory": str(state_dir),
        "evidence_path": str(evidence_path),
        "evidence_sha256": sha256_file(evidence_path)
        if evidence_path.exists() else None,
        "terminal_state": (evidence or {}).get("terminal_state", "NO_EVIDENCE"),
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


def positive_checks(definition: dict, u1: dict, u2: dict, database: Path,
                    anchor: dict) -> dict:
    ev1 = u1.get("evidence") or {}
    ev2 = u2.get("evidence") or {}
    state = task_state(database)
    u1_settlement = state["u1_settlement"] or {}
    source_settlement = state["source_settlement"] or {}
    u1_value = (u1_settlement.get("result") or {}).get("value", {})
    u2_value = settlement_value(database, ITEM_U2)
    secret = u1_value.get("secret", "")
    checksum = (source_settlement.get("result") or {}).get(
        "value", {}).get("checksum", "")
    expected = "%s-%s" % (secret, checksum)
    answer = answer_of(ev2)
    counters1 = ev1.get("counters") or {}
    counters2 = ev2.get("counters") or {}
    admission1 = ev1.get("input_admission") or {}
    admission2 = ev2.get("input_admission") or {}
    checks1 = admission1.get("checks") or {}
    checks2 = admission2.get("checks") or {}
    sig1 = signature_checks(database, ITEM_U1, ev1, anchor)
    sig_source = signature_checks(database, ITEM_SOURCE, ev1, anchor)
    sig2 = signature_checks(database, ITEM_U2, ev2, anchor)
    generated = ev2.get("generated_token_ids") or []
    # The admission evidence carries only descriptor fields, not the signed
    # payload. Read the signature object itself so the provenance comparison
    # is against the bytes that were actually signed.
    connection = connect_readonly(database)
    try:
        u2_envelope = current_signature(connection, ITEM_U2) or {}
    finally:
        connection.close()
    payload = u2_envelope.get("payload") or {}
    provenance = payload.get("provenance") or {}
    checks = {
        "u1_settled": ev1.get("terminal_state") == "TASK_SETTLED",
        "u1_generation_exactly_once": counters1.get("model_continuation_calls") == 1
        and counters1.get("tokenize_text_calls") == 1
        and counters1.get("tokenize_seed_calls") == 1,
        "u1_admission_admitted": ev1.get("input_admission_status") == "ADMITTED",
        "u1_admission_checks_all_true": bool(checks1) and all(checks1.values()),
        "u1_admitted_sha_matches_evidence": bool(ev1.get("admitted_input_sha256"))
        and ev1.get("admitted_input_sha256") == admission1.get("input_sha256"),
        "u1_settled_input_matches_admitted": bool(ev1.get("admitted_input_sha256"))
        and u1_value.get("admitted_input_sha256") == ev1.get("admitted_input_sha256"),
        "u1_settlement_signed": bool(
            (ev1.get("settlement") or {}).get("settlement_signature_object_id")),
        "u1_signature_checks_all_true": bool(sig1) and all(sig1.values()),
        "source_signature_checks_all_true": bool(sig_source)
        and all(sig_source.values()),
        "u2_settled": ev2.get("terminal_state") == "TASK_SETTLED",
        "u2_generation_exactly_once": counters2.get("model_continuation_calls") == 1
        and counters2.get("tokenize_text_calls") == 1
        and counters2.get("tokenize_seed_calls") == 1,
        "u2_admission_admitted": ev2.get("input_admission_status") == "ADMITTED",
        "u2_admission_checks_all_true": bool(checks2) and all(checks2.values()),
        "u2_admitted_sha_matches_evidence": bool(ev2.get("admitted_input_sha256"))
        and ev2.get("admitted_input_sha256") == admission2.get("input_sha256"),
        "u2_settled_input_matches_admitted": bool(ev2.get("admitted_input_sha256"))
        and u2_value.get("admitted_input_sha256") == ev2.get("admitted_input_sha256"),
        "u2_settlement_signed": bool(
            (ev2.get("settlement") or {}).get("settlement_signature_object_id")),
        "u2_signature_checks_all_true": bool(sig2) and all(sig2.values()),
        "u2_declared_dependencies": sorted(
            ev2.get("declared_dependencies") or []) == [ITEM_SOURCE, ITEM_U1],
        "u2_secret_bound_to_u1_settlement":
            (ev2.get("dependency_settlement_object_ids") or {}).get(ITEM_U1)
            == u1_settlement.get("_object_id"),
        "u2_checksum_bound_to_source_settlement":
            (ev2.get("dependency_settlement_object_ids") or {}).get(ITEM_SOURCE)
            == source_settlement.get("_object_id"),
        "u2_input_contains_admitted_secret": bool(secret)
        and any(binding.get("placeholder") == "secret"
                and binding.get("value") == secret
                for binding in (ev2.get("bindings") or [])),
        "u2_input_contains_admitted_checksum": bool(checksum)
        and any(binding.get("placeholder") == "checksum"
                and binding.get("value") == checksum
                for binding in (ev2.get("bindings") or [])),
        "u2_answer_matches_settled_value": bool(answer) and answer == expected,
        "u2_settled_answer_equals_generated": bool(answer)
        and answer == u2_value.get("answer", ""),
        "u2_producer_is_model_task": provenance.get("producer", {}).get("kind")
        == "model_task",
        "u2_model_identity_bound": provenance.get("model", {}).get(
            "snapshot_revision") == ev2.get("model", {}).get("snapshot_revision"),
        "u2_output_tokens_bound": provenance.get("output", {}).get(
            "generated_token_ids_sha256")
        == sha256_bytes(("[" + ",".join(str(x) for x in generated) + "]").encode())
        and provenance.get("output", {}).get("generated_token_count") == len(generated),
        "u2_template_unchanged": definition["u2_template_sha256"]
        == hashlib.sha256(
            ((state["u2_item"] or {}).get("source_payload") or {})
            .get("next_input_template", "").encode()).hexdigest(),
    }
    return checks


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


def nonce_audit(world: Path, other_world: Path, planned_argv: list) -> dict:
    connection = connect_readonly(world / "carrier.sqlite")
    try:
        settlement = current_object(connection, SETTLEMENT_U1)
    finally:
        connection.close()
    if settlement is None:
        raise RuntimeError("U1 settlement missing for nonce audit")
    nonce = settlement["result"]["value"]["secret"]
    argv_text = "\0".join(planned_argv)
    environment = os.environ.copy()
    environment.pop("SIMIGO_SETTLEMENT_SIGNING_KEY", None)
    env_text = "\0".join("%s=%s" % (key, value)
                         for key, value in environment.items())
    violations = {
        "argv": nonce in argv_text,
        "environment": nonce in env_text,
        "other_world_database": nonce_in_path(other_world / "carrier.sqlite", nonce),
        "other_world_state": nonce_in_directory(other_world / "state", nonce),
        "other_world_evidence": nonce_in_directory(other_world / "evidence", nonce),
        "other_world_logs": nonce_in_directory(other_world / "logs", nonce),
    }
    return {
        "schema_id": "SIMIGO-E-ROUND-NONCE-AUDIT-V1",
        "world": world.name,
        "nonce_sha256": sha256_bytes(nonce.encode()),
        "nonce_length": len(nonce),
        "surface_contains_nonce": violations,
        "cross_contaminated": any(violations.values()),
        "verdict": "CLEAN" if not any(violations.values()) else "CONTAMINATED",
    }


def nonce_in_path(path: Path, nonce: str) -> bool:
    if not path.exists():
        return False
    return nonce in path.read_bytes().decode("utf-8", errors="ignore")


def nonce_in_directory(directory: Path, nonce: str) -> bool:
    if not directory.exists():
        return False
    for path in sorted(directory.rglob("*")):
        if path.is_file() and nonce_in_path(path, nonce):
            return True
    return False


def negative_checks(entry: dict, expected_stage: str) -> dict:
    evidence = entry.get("evidence") or {}
    counters = evidence.get("counters") or {}
    refusal = evidence.get("input_admission_refusal") or {}
    return {
        "refused_before_generation": evidence.get("terminal_state")
        == "INPUT_ADMISSION_REFUSED",
        "admission_status_refused": evidence.get("input_admission_status")
        == "ADMISSION_REFUSED",
        "stage_matches": refusal.get("stage") == expected_stage,
        "tokenize_text_zero": counters.get("tokenize_text_calls") == 0,
        "tokenize_seed_zero": counters.get("tokenize_seed_calls") == 0,
        "generation_zero": counters.get("model_continuation_calls") == 0,
        "generation_not_entered": evidence.get("generation_entered") is False,
        # Loading the model container is NOT the guarantee; tokenize/generate are.
        # Model load is recorded as an observation in ``case`` instead.
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
        "u1_signatures_differ":
            (ev_a.get("dependency_settlement_object_ids") or {}).get(
                ITEM_U1) != (ev_b.get("dependency_settlement_object_ids") or {}).get(
                ITEM_U1),
        "u2_inputs_differ": ev_a.get("admitted_input_sha256")
        != ev_b.get("admitted_input_sha256")
        and bool(ev_a.get("admitted_input_sha256"))
        and bool(ev_b.get("admitted_input_sha256")),
        "outputs_differ": bool(answer_a) and bool(answer_b) and answer_a != answer_b,
        "each_output_matches_its_own_world":
            answer_a == world_a["expected_answer"]
            and answer_b == world_b["expected_answer"],
    }
    checks["world_pair_distinguished"] = all([
        checks["u2_templates_identical"], checks["cold_seeds_identical"],
        checks["u1_settlements_differ"], checks["u2_inputs_differ"],
        checks["outputs_differ"], checks["each_output_matches_its_own_world"]])
    return checks


def grep_lines(path: Path, needle: str) -> list:
    lines = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if needle in line:
            lines.append(number)
    return lines


def coverage_audit(lab_root: Path) -> dict:
    package = lab_root / "simigo2-experimental"
    integration = package / "Sources/SimiGo2Experimental/ProductionRuntimeInformationIntegration.swift"
    task_run = package / "Sources/SimiGoTaskRun/main.swift"
    handoff_main = package / "Sources/RealModelHandoff/main.swift"
    handoff_causality = package / "Sources/RealModelHandoff/Causality.swift"
    smoke_child = package / "Sources/ActualMLXSmokeChild/main.swift"
    app = package / "Sources/SimiGo2App/SimiGo2App.swift"
    bridge = lab_root / "execution-information-loop/production_runtime_bridge.py"
    text = integration.read_text(encoding="utf-8")
    continue_task_index = text.find("public func continueTask(")
    next_function = text.find("\n  public func ", continue_task_index + 1)
    continue_body = text[
        continue_task_index:
        next_function if next_function > continue_task_index else len(text)]
    # Order matters INSIDE the production entry: the admission call must
    # precede the first tokenization in this function's own body.
    resolve_call_index = continue_body.find("resolveTaskInput(")
    tokenize_index = continue_body.find("try await modelExecutor.tokenizeText(")
    seed_index = continue_body.find("try await modelExecutor.tokenizeSeedText(")
    resolve_index = text.find("func resolveTaskInput(")
    bridge_resolve = grep_lines(bridge, "provenance_policy=\"verify\"")
    bridge_producer = grep_lines(bridge, "provenance_policy=\"required\"")
    legacy_open = grep_lines(bridge, "require_provenance=True")
    exclusions = [
        {
            "entry": "SimiGo2App.send / sendSmallScale / self-test",
            "path": str(app.relative_to(lab_root)),
            "call_lines": sorted(set(
                grep_lines(app, "engine.generate("))),
            "reason": (
                "interactive chat/benchmark surface: calls the engine directly "
                "with user text, names no task item, never constructs "
                "ProductionRuntimeInformationIntegration and reads no IS settlement"),
            "excluded": True,
        },
        {
            "entry": "MLXGroupResidencyBenchmark / MLXGroupInferenceGate",
            "path": "simigo2-experimental/Sources/SimiGo2Experimental",
            "call_lines": sorted(set(
                grep_lines(package / "Sources/SimiGo2Experimental/MLXGroupResidencyBenchmark.swift",
                           "ChatTemplateGeneration.generate(")
                + grep_lines(package / "Sources/SimiGo2Experimental/MLXGroupInferenceGate.swift",
                             "ChatTemplateGeneration.generate("))),
            "reason": (
                "measurement/instrumentation harness: direct generation for "
                "timing and residency probes, no task item and no settlement"),
            "excluded": True,
        },
        {
            "entry": "GroupExecutionTraceProbe / MeasuredExecutionTracePilot",
            "path": "simigo2-experimental/Sources/SimiGo2Experimental/Instrumentation",
            "call_lines": sorted(set(
                grep_lines(package / "Sources/SimiGo2Experimental/Instrumentation/GroupExecutionTraceProbe.swift",
                           "ChatTemplateGeneration.generate(")
                + grep_lines(package / "Sources/SimiGo2Experimental/Instrumentation/MeasuredExecutionTracePilot.swift",
                             "ChatTemplateGeneration.generate("))),
            "reason": (
                "instrumentation-only trace generation; no task identity, no IS "
                "admission and no settlement consumption"),
            "excluded": True,
        },
        {
            "entry": "G3SwiftIsolationEntry",
            "path": "simigo2-experimental/Sources/G3SwiftIsolationEntry/main.swift",
            "call_lines": grep_lines(
                package / "Sources/G3SwiftIsolationEntry/main.swift",
                "generate:"),
            "reason": (
                "isolation-gate harness with an injected generate closure; it "
                "tests cancellation/isolation, not task advancement"),
            "excluded": True,
        },
    ]
    checks = {
        "continueTask_calls_resolveTaskInput": resolve_call_index >= 0,
        "resolveTaskInput_before_tokenize":
            0 <= resolve_call_index < tokenize_index,
        "resolveTaskInput_before_seed_tokenize":
            0 <= resolve_call_index < seed_index,
        "consumer_bridge_uses_verify_only": bool(bridge_resolve),
        "producer_bridge_uses_required": bool(bridge_producer),
        "legacy_execute_uses_required_provenance": bool(legacy_open),
        "all_continueTask_call_sites_pass_provenance": all(
            "provenance:" in "\n".join(path.read_text(encoding="utf-8").splitlines()[
                line - 1:line + 12])
            for path in (task_run, handoff_main, handoff_causality)
            for line in grep_lines(path, ".continueTask(")),
    }
    return {
        "schema_id": "SIMIGO-E-ROUND-COVERAGE-AUDIT-V1",
        "production_task_entries": [
            {
                "entry": "SimiGoTaskRun",
                "path": str(task_run.relative_to(lab_root)),
                "continueTask_call_lines": grep_lines(task_run, ".continueTask("),
                "admission": "continueTask -> resolveTaskInput -> bridge "
                             "resolve-model-input (verify) -> Swift Ed25519 verify",
                "covered": True,
            },
            {
                "entry": "RealModelHandoff",
                "path": str(handoff_main.relative_to(lab_root)),
                "continueTask_call_lines": (
                    grep_lines(handoff_main, ".continueTask(")
                    + grep_lines(handoff_causality, ".continueTask(")),
                "admission": "same continueTask admission; handoff orchestration "
                             "only chooses the item",
                "covered": True,
            },
            {
                "entry": "ActualMLXSmokeChild (legacy advancement)",
                "path": str(smoke_child.relative_to(lab_root)),
                "continueWithRealInformation_call_lines": grep_lines(
                    smoke_child, ".continueWithRealInformation("),
                "admission": "bridge execute -> open_loop(require_provenance=True) "
                             "-> execute_demand -> _settlement_reuse_decision",
                "covered": True,
            },
        ],
        "source_evidence": {
            "integration_resolveTaskInput_line": continue_body[:resolve_call_index]
            .count("\n") + text[:continue_task_index].count("\n") + 1
            if resolve_call_index >= 0 else None,
            "integration_first_tokenize_line": continue_body[:tokenize_index]
            .count("\n") + text[:continue_task_index].count("\n") + 1
            if tokenize_index >= 0 else None,
            "integration_continueTask_body_lines": continue_body.count("\n") + 1,
            "bridge_verify_policy_lines": bridge_resolve,
            "bridge_required_policy_lines": bridge_producer,
            "bridge_legacy_execute_lines": legacy_open,
            "continueTask_definition_line": text[:continue_task_index].count("\n") + 1
            if continue_task_index >= 0 else None,
        },
        "non_task_direct_inference": exclusions,
        "checks": checks,
        "verdict": "PASS" if all(checks.values()) else "FAIL",
        "not_claimed": [
            "every inference call in the repository",
            "semantic correctness of a signed model answer",
            "protection when the attacker controls database, signing key and anchor",
            "database-instance lineage: a complete, validly signed history from "
            "another instance is still a valid signed history",
        ],
    }


# --------------------------------------------------------------------------
# orchestration
# --------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-root", required=True)
    parser.add_argument("--lab-root", required=True)
    parser.add_argument("--model-dir", required=True)
    parser.add_argument("--max-tokens", type=int, default=64)
    arguments = parser.parse_args()

    run_root = Path(arguments.run_root).expanduser().resolve()
    lab_root = Path(arguments.lab_root).expanduser().resolve()
    model_dir = Path(arguments.model_dir).expanduser().resolve()
    binary = lab_root / "simigo2-experimental/.build/debug/SimiGoTaskRun"
    bridge = lab_root / "execution-information-loop/production_runtime_bridge.py"
    if not binary.is_file():
        raise SystemExit("ordinary entry binary missing: %s" % binary)

    worlds_root = run_root / "worlds"
    negative_root = run_root / "phase2"
    legacy_root = run_root / "phase3-legacy"
    for directory in (worlds_root, negative_root, legacy_root):
        if directory.exists() and any(directory.iterdir()):
            raise SystemExit("refusing to overwrite %s" % directory)
        directory.mkdir(parents=True, exist_ok=True)

    trust = provision_trust(run_root)
    trust["build_sha256"] = sha256_bytes(("\n".join([
        sha256_file(binary), sha256_file(bridge),
        sha256_file(lab_root / "execution-information-loop/settlement_provenance.py"),
    ])).encode())
    write_json(run_root / "trust" / "trust-root.json", trust)
    anchor_document = read_json(Path(trust["anchor_path"]))

    results = {}
    worlds = {}
    attempts_root = worlds_root / "attempts"
    attempts_root.mkdir(exist_ok=True)
    for name, label in (("world-a", "e-world-a"), ("world-b", "e-world-b")):
        attempts = []
        settled = None
        for attempt in range(1, 4):
            world = worlds_root / name
            if world.exists():
                archive = attempts_root / ("%s-u1-attempt-%d" % (name, attempt - 1))
                if archive.exists():
                    raise SystemExit("refusing to overwrite %s" % archive)
                world.rename(archive)
            world.mkdir()
            definition_env = child_environment(
                lab_root, trust, "e-definition-%s" % name,
                "e-definition-%s" % name, with_key=True)
            definition = define_ordinary_task(
                world / "carrier.sqlite", lab_root, label, definition_env)
            u1_env = child_environment(
                lab_root, trust, "e-%s-u1" % name, "e-%s-u1" % name,
                with_key=True)
            u1 = run_entry(binary, world, lab_root, model_dir, ITEM_U1,
                           DEMAND_U1, "e-%s-u1-a%d" % (name, attempt), "u1",
                           arguments.max_tokens, u1_env)
            attempts.append({
                "attempt": attempt,
                "world_path": str(world),
                "terminal_state": u1["terminal_state"],
                "evidence_path": u1["evidence_path"],
                "evidence_sha256": u1["evidence_sha256"],
                "log": u1["log"],
                "log_sha256": u1["log_sha256"],
                "failure": (u1.get("evidence") or {}).get("failure"),
            })
            if u1["terminal_state"] == "TASK_SETTLED":
                settled = {"definition": definition, "u1": u1, "world": world}
                break
            if u1["terminal_state"] == "INPUT_ADMISSION_REFUSED":
                break
        if settled is None:
            write_json(run_root / "summary.json", {
                "schema_id": "SIMIGO-E-ROUND-SUMMARY-V1",
                "terminal_state": "BLOCKED_NOT_RUN",
                "world": name,
                "attempts": attempts,
            })
            return 1
        settled["attempts"] = attempts
        worlds[name] = settled

    for name in worlds:
        sqlite_backup(worlds[name]["world"] / "carrier.sqlite",
                      run_root / "phase2" / ("base-%s.sqlite" % name))

    planned_argv = [
        str(binary), "--database", "<case>", "--item", ITEM_U2,
        "--demand", DEMAND_U2, "--advancement", "<id>",
        "--evaluated-at", "<utc>", "--model-dir", str(model_dir),
        "--lab-root", str(lab_root), "--state-dir", "<case>/state/u2",
        "--out", "<case>/evidence/u2.json",
    ]
    nonce = {
        "W_A": nonce_audit(worlds_root / "world-a", worlds_root / "world-b",
                           planned_argv),
        "W_B": nonce_audit(worlds_root / "world-b", worlds_root / "world-a",
                           planned_argv),
    }
    write_json(run_root / "logs" / "nonce-surface-audit.json", nonce)
    if nonce["W_A"]["cross_contaminated"] or nonce["W_B"]["cross_contaminated"]:
        write_json(run_root / "summary.json", {
            "schema_id": "SIMIGO-E-ROUND-SUMMARY-V1",
            "terminal_state": "INVALID_CONDITION", "nonce": nonce})
        return 1

    for name in worlds:
        u2_attempts = []
        settled_u2 = None
        for attempt in range(1, 4):
            case = worlds_root / ("%s-u2" % name)
            if case.exists():
                archive = attempts_root / ("%s-u2-attempt-%d" % (name, attempt - 1))
                if archive.exists():
                    raise SystemExit("refusing to overwrite %s" % archive)
                case.rename(archive)
            case.mkdir()
            shutil.copyfile(run_root / "phase2" / ("base-%s.sqlite" % name),
                            case / "carrier.sqlite")
            u2_env = child_environment(
                lab_root, trust, "e-%s-u2" % name, "e-%s-u2" % name,
                with_key=True)
            u2 = run_entry(binary, case, lab_root, model_dir, ITEM_U2,
                           DEMAND_U2, "e-%s-u2-a%d" % (name, attempt), "u2",
                           arguments.max_tokens, u2_env)
            u2_attempts.append({
                "attempt": attempt,
                "world_path": str(case),
                "terminal_state": u2["terminal_state"],
                "evidence_path": u2["evidence_path"],
                "evidence_sha256": u2["evidence_sha256"],
                "log": u2["log"],
                "log_sha256": u2["log_sha256"],
                "failure": (u2.get("evidence") or {}).get("failure"),
            })
            if u2["terminal_state"] == "TASK_SETTLED":
                # The task contract requires the model to emit ANSWER=<v>. A
                # settled but off-contract generation is a model failure, not
                # an admission result; retry it like the D round did.
                state = task_state(case / "carrier.sqlite")
                expected = "%s-%s" % (
                    (((state["u1_settlement"] or {}).get("result") or {})
                     .get("value") or {}).get("secret", ""),
                    (((state["source_settlement"] or {}).get("result") or {})
                     .get("value") or {}).get("checksum", ""))
                if answer_of(u2.get("evidence") or {}) == expected:
                    settled_u2 = {"u2": u2, "world": case}
                    break
                u2_attempts[-1]["failure"] = (
                    "output contract: no ANSWER=<secret>-<checksum> matching "
                    "the settled dependencies")
                continue
            if u2["terminal_state"] == "INPUT_ADMISSION_REFUSED":
                break
        if settled_u2 is None:
            write_json(run_root / "summary.json", {
                "schema_id": "SIMIGO-E-ROUND-SUMMARY-V1",
                "terminal_state": "BLOCKED_NOT_RUN",
                "world": name,
                "u1": {key: value for key, value in worlds[name]["u1"].items()
                       if key != "evidence"},
                "u2_attempts": u2_attempts,
            })
            return 1
        worlds[name].update(settled_u2)
        worlds[name]["u2_attempts"] = u2_attempts
        u2 = settled_u2["u2"]
        state = task_state(worlds[name]["world"] / "carrier.sqlite")
        u1_value = ((state["u1_settlement"] or {}).get("result") or {}).get(
            "value", {})
        source_value = ((state["source_settlement"] or {}).get("result") or {}).get(
            "value", {})
        worlds[name]["expected_answer"] = "%s-%s" % (
            u1_value.get("secret", ""), source_value.get("checksum", ""))
        worlds[name]["positive_checks"] = positive_checks(
            worlds[name]["definition"], u1=worlds[name]["u1"], u2=u2,
            database=worlds[name]["world"] / "carrier.sqlite",
            anchor=anchor_document)

    for name in worlds:
        results["E0-%s" % name[-1].upper()] = {
            "terminal_state": worlds[name]["u2"]["terminal_state"],
            "u1": {key: value for key, value in worlds[name]["u1"].items()
                   if key != "evidence"},
            "u2": {key: value for key, value in worlds[name]["u2"].items()
                   if key != "evidence"},
            "positive_checks": worlds[name]["positive_checks"],
        }
    world_pair = compare_worlds(worlds["world-a"], worlds["world-b"])
    write_json(run_root / "phase2" / "world-comparison.json", world_pair)

    # E0: the unmodified signed state is admitted by the model-free probe.
    probe_dir = negative_root / "E0-valid-signature"
    probe_dir.mkdir()
    shutil.copyfile(run_root / "phase2" / "base-world-a.sqlite",
                    probe_dir / "carrier.sqlite")
    probe_env = child_environment(
        lab_root, trust, "e-probe-valid", "e-probe-valid", with_key=False,
        policy="verify")
    probe = run_entry(binary, probe_dir, lab_root, model_dir, ITEM_U2,
                      DEMAND_U2, "e-probe-valid", "u2", arguments.max_tokens,
                      probe_env, probe=True)
    probe_evidence = probe.get("evidence") or {}
    probe_admission = probe_evidence.get("input_admission") or {}
    probe_signatures = probe_evidence.get("settlement_signatures") or []
    probe_checks = {
        "admitted": probe_evidence.get("terminal_state") == "INPUT_ADMITTED",
        "status_admitted": probe_evidence.get("input_admission_status")
        == "ADMITTED",
        "checks_all_true": bool(probe_admission.get("checks"))
        and all(probe_admission.get("checks").values()),
        "declared_dependencies": sorted(
            probe_evidence.get("declared_dependencies") or [])
        == [ITEM_SOURCE, ITEM_U1],
        "one_signature_per_dependency": len(probe_signatures)
        == len(probe_evidence.get("declared_dependencies") or []),
        "signatures_match_applied": sorted(
            entry.get("item_id") for entry in probe_signatures)
        == [ITEM_SOURCE, ITEM_U1],
        "counters_zero": probe_evidence.get("counters") == {
            "tokenize_text_calls": 0, "tokenize_seed_calls": 0,
            "model_continuation_calls": 0},
        "no_model_loaded": probe_evidence.get("model_loaded") is False,
        "database_unchanged": probe_evidence.get("database_unchanged") is True,
        "state_unchanged": probe_evidence.get("state_unchanged") is True,
    }
    results["E0-valid-signature"] = {
        "terminal_state": probe["terminal_state"],
        "entry": {key: value for key, value in probe.items() if key != "evidence"},
        "admission": probe_admission,
        "settlement_signatures": probe_signatures,
        "checks": probe_checks,
        "verdict": "PASS" if all(probe_checks.values()) else "FAIL",
    }

    def case(name, stage, mutation, expected_item=ITEM_U1, anchor_path=None,
             probe_mode=False):
        case_dir = negative_root / name
        case_dir.mkdir()
        shutil.copyfile(run_root / "phase2" / "base-world-a.sqlite",
                        case_dir / "carrier.sqlite")
        applied = mutation(case_dir / "carrier.sqlite")
        # Consumer profile: the verifier holds only the public anchor. A
        # missing key must never be what stops the run; admission must.
        environment = child_environment(
            lab_root, trust, "e-%s" % name, "e-%s" % name, with_key=False,
            anchor_path=anchor_path, policy="verify")
        entry = run_entry(binary, case_dir, lab_root, model_dir, ITEM_U2,
                          DEMAND_U2, "e-%s" % name, "u2",
                          arguments.max_tokens, environment, probe=probe_mode)
        checks = negative_checks(entry, stage)
        evidence = entry.get("evidence") or {}
        refusal = evidence.get("input_admission_refusal") or {}
        checks["refusal_item_matches"] = refusal.get("item_id") == expected_item
        return {
            "terminal_state": entry["terminal_state"],
            "expected_stage": stage,
            "expected_item": expected_item,
            "mutation": applied,
            "entry": {key: value for key, value in entry.items()
                      if key != "evidence"},
            "refusal": refusal,
            "counters": evidence.get("counters"),
            "observations": {
                "model_loaded_before_refusal": bool(evidence.get("model")),
                "model_load_seconds": evidence.get("model_load_seconds"),
                "database_sha256_before": (evidence.get("database_before") or {})
                .get("sha256"),
                "database_sha256_after": (evidence.get("database_after") or {})
                .get("sha256"),
            },
            "checks": checks,
            "verdict": "PASS" if all(checks.values()) else "FAIL",
        }

    matrix = [
        ("E1-result-value-only", "SETTLEMENT_NOT_ADMITTED",
         lambda path: mutate_value_only(
             path, {"secret": "0123456789abcdef", "answer": "forged"}),
         ITEM_U1),
        ("E2-result-and-digests", "SETTLEMENT_SIGNATURE_INVALID",
         lambda path: rewrite_result_self_consistent(
             path, ITEM_U1,
             {"secret": "fedcba9876543210", "answer": "fedcba9876543210-forged"}),
         ITEM_U1),
        ("E3-producer-field", "SETTLEMENT_SIGNATURE_INVALID",
         mutate_producer_field, ITEM_U1),
        ("E4-task-item-metadata", "SETTLEMENT_PROVENANCE_MISMATCH",
         mutate_task_item_metadata, ITEM_U1),
        ("E5-dependency-substitution", "SETTLEMENT_NOT_ADMITTED",
         lambda path: copy_settlement(
             worlds_root / "world-b" / "carrier.sqlite", path, ITEM_SOURCE),
         ITEM_U1),
        ("E6-signature-removed", "SETTLEMENT_SIGNATURE_MISSING",
         lambda path: dict(
             rewrite_result_self_consistent(
                 path, ITEM_U1,
                 {"secret": "aaaabbbbccccdddd", "answer": "aaaabbbbccccdddd-forged"}),
             **remove_signature(path, ITEM_U1)),
         ITEM_U1),
        ("E8-foreign-signed-u1-replay", "SETTLEMENT_NOT_ADMITTED",
         lambda path: copy_settlement(
             worlds_root / "world-b" / "carrier.sqlite", path, ITEM_U1),
         ITEM_U1),
        ("E7-anchor-public-key-swapped", "SETTLEMENT_SIGNATURE_INVALID",
         lambda path: {"anchor": "attacker"},
         ITEM_SOURCE),
    ]
    for name, stage, mutation, item in matrix:
        anchor_path = trust["attacker_anchor_path"] \
            if name == "E7-anchor-public-key-swapped" else None
        result = safe_condition(name, lambda name=name, stage=stage,
                                mutation=mutation, item=item,
                                anchor_path=anchor_path: case(
            name, stage, mutation, item, anchor_path))
        results[name] = result

    # Legacy advancement: bridge `execute`, the path behind
    # continueWithRealInformation. Run on an isolated PALACE carrier.
    legacy = safe_condition("legacy", lambda: legacy_phase(
        bridge, lab_root, legacy_root, trust, arguments))
    results["legacy"] = legacy

    coverage = coverage_audit(lab_root)
    write_json(run_root / "logs" / "coverage-audit.json", coverage)

    positive_all = all(
        all(worlds[name]["positive_checks"].values()) for name in worlds)
    world_pair_ok = world_pair["world_pair_distinguished"]
    matrix_all = all(
        results[name].get("verdict") == "PASS"
        for name, _, _, _ in matrix)
    probe_ok = results["E0-valid-signature"]["verdict"] == "PASS"
    legacy_ok = legacy.get("verdict") == "PASS"
    coverage_ok = coverage["verdict"] == "PASS"

    summary = {
        "schema_id": "SIMIGO-E-ROUND-SUMMARY-V1",
        "run_id": run_root.name,
        "created_at_utc": utc_now(),
        "terminal_state": ("OBSERVED" if all([
            positive_all, world_pair_ok, probe_ok, matrix_all,
            legacy_ok, coverage_ok]) else "INCOMPLETE"),
        "run_root": str(run_root),
        "entry": {
            "binary": str(binary),
            "binary_sha256": sha256_file(binary),
            "target": "SimiGoTaskRun",
        },
        "trust_root": trust,
        "worlds": {
            name: {
                "definition": worlds[name]["definition"],
                "u1": {key: value for key, value in worlds[name]["u1"].items()
                       if key != "evidence"},
                "u2": {key: value for key, value in worlds[name]["u2"].items()
                       if key != "evidence"},
                "expected_answer": worlds[name]["expected_answer"],
                "u1_attempts": worlds[name].get("attempts", []),
                "u2_attempts": worlds[name].get("u2_attempts", []),
                "positive_checks": worlds[name]["positive_checks"],
            }
            for name in worlds
        },
        "world_pair": world_pair,
        "nonce": nonce,
        "coverage_audit": coverage,
        "conditions": results,
        "claims": {
            "E1_trusted_path_signs_settlements":
                "OBSERVED_FOR_REGISTRATION_U1_AND_U2" if positive_all
                else "NOT_ESTABLISHED",
            "E2_signed_results_survive_dual_world":
                "OBSERVED_WITH_SIGNATURES_AND_DISTINCT_INPUTS"
                if world_pair_ok else "NOT_ESTABLISHED",
            "E3_signature_failure_refused_before_generation":
                "OBSERVED_WITH_ZERO_COUNTERS_AND_ZERO_DB_STATE_CHANGE"
                if matrix_all else "NOT_ESTABLISHED",
            "E4_self_consistent_unsigned_rewrite_distinguished":
                "OBSERVED_SIGNATURE_MISSING_OR_INVALID"
                if matrix_all else "NOT_ESTABLISHED",
            "E5_legacy_advancement_applies_reuse_admission":
                "OBSERVED_TAMPERED_SETTLEMENT_RECOMPUTED_NOT_REUSED"
                if legacy_ok else "NOT_ESTABLISHED",
            "E6_signature_does_not_prove_semantic_correctness":
                "BOUNDARY_STATED_AND_NOT_CLAIMED",
        },
    }
    write_json(run_root / "summary.json", summary)
    write_json(run_root / "phase2" / "conditions.json", {
        "schema_id": "SIMIGO-E-ROUND-CONDITIONS-V1",
        "created_at_utc": utc_now(), "results": results})
    return 0 if summary["terminal_state"] == "OBSERVED" else 1


def legacy_phase(bridge: Path, lab_root: Path, legacy_root: Path, trust: dict,
                 arguments) -> dict:
    """Prove the legacy advancement path never reuses a bad settlement."""
    environment = child_environment(
        lab_root, trust, "e-legacy", "e-legacy", with_key=True)
    database = legacy_root / "base.sqlite"
    initialize = run_process([
        "/usr/bin/python3", str(bridge), "initialize",
        "--database", str(database)], lab_root,
        legacy_root / "logs" / "initialize.log", 300, environment)
    if initialize["exit_code"] != 0:
        raise RuntimeError("legacy initialize failed: %s" % initialize["log"])
    def execute_and_confirm(database_path: Path, advancement: str,
                            prefix: str) -> dict:
        """Run the legacy advancement and record its runtime confirmation.

        ``execute`` leaves the new execution state PENDING_SWIFT on purpose:
        the Swift runtime owns the physical application. The next advancement
        refuses to start while that confirmation is missing, so the harness
        must apply the same completion step a real runtime performs.
        """
        executed = run_process([
            "/usr/bin/python3", str(bridge), "execute",
            "--database", str(database_path), "--advancement", advancement,
            "--evaluated-at", utc_now()], lab_root,
            legacy_root / "logs" / (prefix + ".log"), 300, environment)
        output = last_json_line(Path(executed["log"]))
        if executed["exit_code"] != 0 or not output or not output.get("ok"):
            raise RuntimeError("legacy execute %s failed: %s"
                               % (advancement, executed["log"]))
        state_id = ((output.get("result") or {}).get("execution_state")
                    or {}).get("state_id")
        if not state_id:
            raise RuntimeError("legacy %s returned no pending state"
                               % advancement)
        confirmed = run_process([
            "/usr/bin/python3", str(bridge), "confirm-runtime-application",
            "--database", str(database_path), "--state-id", state_id],
            lab_root, legacy_root / "logs" / (prefix + "-confirm.log"), 300,
            environment)
        confirmation = last_json_line(Path(confirmed["log"]))
        if (confirmed["exit_code"] != 0 or not confirmation
                or not confirmation.get("ok")):
            raise RuntimeError("legacy confirm %s failed: %s"
                               % (state_id, confirmed["log"]))
        output["execution_process"] = executed
        output["confirmation"] = confirmation
        output["confirmation_process"] = confirmed
        return output

    first = execute_and_confirm(database, "legacy-1", "execute-1")
    first_output = first
    second = execute_and_confirm(database, "legacy-2", "execute-2")
    second_output = second

    tampered = legacy_root / "tampered.sqlite"
    shutil.copyfile(database, tampered)
    real_1_before = settlement_value(tampered, "REAL-1")
    tamper_1 = mutate_legacy_settlement(
        tampered, "REAL-1", {"payload_digest": "0" * 64})
    removed = remove_signature(tampered, "REAL-2")
    third = execute_and_confirm(tampered, "legacy-3", "execute-3")
    third_output = third
    fourth = execute_and_confirm(tampered, "legacy-4", "execute-4")
    fourth_output = fourth

    def actions(output):
        result = output.get("result") or {}
        return {action["item_id"]: action for action in result.get("actions") or []}

    def signature_valid_in(database_path: Path, item_id: str) -> bool:
        connection = connect_readonly(database_path)
        try:
            settlement = current_object(connection, "settlement:" + item_id)
            envelope = current_signature(connection, item_id)
        finally:
            connection.close()
        if not settlement or not envelope:
            return False
        doc = read_json(Path(trust["anchor_path"]))
        return all(verify_envelope(
            envelope, doc, settlement["_object_id"], item_id).values())

    def signature_valid(item_id: str) -> bool:
        return signature_valid_in(tampered, item_id)

    first_actions = actions(first_output)
    second_actions = actions(second_output)
    third_actions = actions(third_output)
    fourth_actions = actions(fourth_output)
    real_1_after = settlement_value(tampered, "REAL-1")
    recomputed = [item for item, action in third_actions.items()
                  if action.get("action") == "COMPUTE"]
    reused_third = [item for item, action in third_actions.items()
                    if action.get("action") == "REUSE"]
    checks = {
        "first_execution_computed_all": sorted(
            first_output["result"].get("computed_item_ids") or [])
        == sorted(first_actions),
        "all_first_settlements_signed": all(
            action.get("settlement_signature_object_id")
            for action in first_actions.values()),
        "second_execution_reused_all": sorted(
            second_output["result"].get("reused_item_ids") or [])
        == sorted(second_actions),
        # Every reuse must name the signature object that admitted it, and
        # that signature must verify independently against the public anchor.
        "second_execution_reuse_has_signatures": all(
            action.get("settlement_signature_object_id")
            for action in second_actions.values()) and all(
            signature_valid_in(database, item) for item in second_actions),
        "tampered_recomputed_not_reused": "REAL-1" in recomputed,
        "missing_signature_recomputed_not_reused": "REAL-2" in recomputed,
        "tampered_reason_is_signature_invalid":
            third_actions["REAL-1"].get("reason") == "SETTLEMENT_SIGNATURE_INVALID",
        "missing_reason_is_signature_missing":
            third_actions["REAL-2"].get("reason") == "SETTLEMENT_SIGNATURE_MISSING",
        "untouched_items_reused": sorted(reused_third) == sorted(
            set(third_actions) - {"REAL-1", "REAL-2"}),
        "tampered_value_not_consumed":
            real_1_after.get("payload_digest")
            == real_1_before.get("payload_digest")
            and real_1_after.get("payload_digest") != "0" * 64,
        "recomputed_settlements_resigned": all(
            third_actions[item].get("settlement_signature_object_id")
            for item in ("REAL-1", "REAL-2")),
        "fourth_execution_reuses_all": sorted(
            fourth_output["result"].get("reused_item_ids") or [])
        == sorted(fourth_actions),
        "all_fourth_signatures_verify": all(
            signature_valid(item) for item in fourth_actions),
    }
    return {
        "schema_id": "SIMIGO-E-ROUND-LEGACY-V1",
        "database": str(database),
        "tampered_database": str(tampered),
        "initialize": initialize,
        "execute_1": first,
        "execute_2": second,
        "execute_3": third,
        "execute_4": fourth,
        "first_actions": first_actions,
        "second_actions": second_actions,
        "third_actions": third_actions,
        "fourth_actions": fourth_actions,
        "mutation": {"real_1": tamper_1, "real_2": removed},
        "recomputed": recomputed,
        "reused_after_tamper": reused_third,
        "checks": checks,
        "verdict": "PASS" if all(checks.values()) else "FAIL",
    }


if __name__ == "__main__":
    sys.exit(main())
