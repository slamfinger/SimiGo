#!/usr/bin/env python3
"""Pre-generation admission self-test for the production input resolver.

Every condition runs against an isolated copy of ONE defined task database.
The resolver must refuse BEFORE it returns any model input, and the database
bytes must be unchanged by the refused attempt. No model is loaded here; the
Swift ``ProductionInputAdmissionTests`` prove the executor's tokenize and
generation counters stay at zero for the same conditions.

Usage:
  python3 admission_selftest.py --out <path/to/admission-selftest.json>
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
LAB_ROOT = HERE.parent
BRIDGE = HERE / "production_runtime_bridge.py"
PYTHON = "/usr/bin/python3"
ENV = {
    **os.environ,
    "SIMIGO_RUNTIME_ROOT": str(LAB_ROOT),
    "SIMIGO_INFO_VALIDITY_POLICY_PATH": str(
        LAB_ROOT / "integrated-es-palace/mlx-smoke-v1/ISOLATED_VALIDITY_POLICY.json"
    ),
}
SETTLEMENT_ID = "settlement:TASK-U1"
TRUST_KEY_ID = "admission-selftest-key"


def provision_trust(directory: Path) -> dict:
    """Create the deployment signing key and trust anchor for this fixture.

    The anchor is written OUTSIDE the database (the consumer reads it from
    there), and the signing key is written 0600. The signing key is only used
    to produce the fixture settlements; the consumer path never loads it.
    """
    import base64

    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

    directory.mkdir(parents=True, exist_ok=True)
    private = Ed25519PrivateKey.generate()
    private_bytes = private.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption(),
    )
    public_bytes = private.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    key_path = directory / "signing-key.json"
    anchor_path = directory / "trust-anchor.json"
    key_path.write_text(json.dumps({
        "schema_id": "EINFO-SETTLEMENT-SIGNING-KEY-V1",
        "algorithm": "Ed25519",
        "key_id": TRUST_KEY_ID,
        "private_key_base64": base64.b64encode(private_bytes).decode("ascii"),
    }), encoding="utf-8")
    anchor_path.write_text(json.dumps({
        "schema_id": "EINFO-SETTLEMENT-TRUST-ANCHOR-V1",
        "algorithm": "Ed25519",
        "key_id": TRUST_KEY_ID,
        "public_key_base64": base64.b64encode(public_bytes).decode("ascii"),
    }), encoding="utf-8")
    os.chmod(key_path, 0o600)
    os.chmod(anchor_path, 0o444)
    ENV["SIMIGO_SETTLEMENT_SIGNING_KEY"] = str(key_path)
    ENV["SIMIGO_SETTLEMENT_TRUST_ANCHOR"] = str(anchor_path)
    ENV["SIMIGO_SETTLEMENT_PROVENANCE"] = "required"
    ENV["SIMIGO_SETTLEMENT_RUN_ID"] = "admission-selftest"
    ENV["SIMIGO_SETTLEMENT_EXECUTION_ID"] = "admission-selftest-execution"
    ENV["SIMIGO_SETTLEMENT_BUILD_SHA256"] = sha256_file(BRIDGE)
    return {"key_path": str(key_path), "anchor_path": str(anchor_path)}


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_file(path: Path) -> str:
    import hashlib

    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def directory_entries(path: Path) -> list[str]:
    return sorted(entry.name for entry in path.iterdir())


def run_bridge(*arguments: str) -> tuple[int, dict]:
    process = subprocess.run(
        [PYTHON, str(BRIDGE), *arguments],
        capture_output=True,
        text=True,
        env=ENV,
        cwd=str(HERE),
        timeout=120,
    )
    try:
        payload = json.loads(process.stdout or "{}")
    except json.JSONDecodeError:
        payload = {
            "ok": False,
            "error_type": "NonJSONOutput",
            "error": (process.stdout or "") + (process.stderr or ""),
        }
    return process.returncode, payload


def prepare_database(directory: Path) -> dict:
    """Define the two-step task and settle TASK-U1 with a synthetic model value."""
    import secrets

    database = directory / "base.sqlite"
    secret = secrets.token_hex(16)
    code, defined = run_bridge(
        "define-task",
        "--database", str(database),
        "--evaluated-at", utc_now(),
        "--run-label", "admission-selftest",
        "--secret", secret,
    )
    if code != 0 or not defined.get("ok"):
        raise RuntimeError("define-task failed: %s" % defined)
    value = {
        "secret": secret,
        "generated_token_ids": [11, 22, 33, 44],
        "model_snapshot_revision": "admission-selftest-revision",
        "model_weights_manifest_sha256": "admission-selftest-weights",
        "raw_generated_text": "SECRET=" + secret,
        "model_call_index": 1,
    }
    value_path = directory / "u1-value.json"
    value_path.write_text(json.dumps(value), encoding="utf-8")
    token_ids = json.dumps(value["generated_token_ids"], separators=(",", ":"))
    provenance = {
        "producer": {
            "kind": "model_task",
            "run_id": ENV["SIMIGO_SETTLEMENT_RUN_ID"],
            "execution_id": ENV["SIMIGO_SETTLEMENT_EXECUTION_ID"],
            "process_id": str(os.getpid()),
            "build_sha256": ENV["SIMIGO_SETTLEMENT_BUILD_SHA256"],
        },
        "model": {
            "snapshot_revision": value["model_snapshot_revision"],
            "weights_manifest_sha256": value["model_weights_manifest_sha256"],
        },
        "output": {
            "generated_token_ids_sha256": sha256_bytes(token_ids.encode("utf-8")),
            "generated_token_count": len(value["generated_token_ids"]),
        },
    }
    provenance_path = directory / "u1-provenance.json"
    provenance_path.write_text(json.dumps(provenance), encoding="utf-8")
    code, settled = run_bridge(
        "execute-with-model-result",
        "--database", str(database),
        "--demand-id", "handoff-u1",
        "--advancement", "admission-selftest-u1",
        "--evaluated-at", utc_now(),
        "--item-id", "TASK-U1",
        "--value-file", str(value_path),
        "--provenance-file", str(provenance_path),
        "--run-id", ENV["SIMIGO_SETTLEMENT_RUN_ID"],
        "--execution-id", ENV["SIMIGO_SETTLEMENT_EXECUTION_ID"],
        "--build-sha256", ENV["SIMIGO_SETTLEMENT_BUILD_SHA256"],
        "--producer-process-id", str(os.getpid()),
    )
    if code != 0 or not settled.get("ok"):
        raise RuntimeError("settle TASK-U1 failed: %s" % settled)
    return {
        "database": database,
        "secret": secret,
        "secret_sha256": defined["secret_sha256"],
        "u1_advancement_state_id": settled["result"]["execution_state"]["state_id"],
        "u1_settlement_signature_object_id": settled.get(
            "settlement_signature", {}
        ).get("signature_object_id"),
        "u1_signed_settlement_object_id": settled.get(
            "settlement_signature", {}
        ).get("settlement_object_id"),
    }


def copy_database(source: Path, destination: Path) -> None:
    source_connection = sqlite3.connect(str(source))
    destination_connection = sqlite3.connect(str(destination))
    try:
        source_connection.backup(destination_connection)
        destination_connection.commit()
    finally:
        destination_connection.close()
        source_connection.close()


def remove_u1_settlement(database: Path) -> dict:
    connection = sqlite3.connect(str(database))
    try:
        deleted_dependency = connection.execute(
            "DELETE FROM dependency_entries WHERE dependency_id=?", (SETTLEMENT_ID,)
        ).rowcount
        deleted_index = connection.execute(
            "DELETE FROM is_index_entries WHERE srs_identity=?", (SETTLEMENT_ID,)
        ).rowcount
        connection.commit()
        return {
            "deleted_dependency_rows": deleted_dependency,
            "deleted_index_rows": deleted_index,
        }
    finally:
        connection.close()


def tamper_u1_object(database: Path) -> dict:
    connection = sqlite3.connect(str(database))
    try:
        row = connection.execute(
            "SELECT content_address FROM dependency_entries WHERE dependency_id=? "
            "ORDER BY append_order DESC LIMIT 1",
            (SETTLEMENT_ID,),
        ).fetchone()
        if row is None:
            raise RuntimeError("U1 settlement missing before tamper")
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
        }
    finally:
        connection.close()


def sha256_bytes(data: bytes) -> str:
    import hashlib

    return hashlib.sha256(data).hexdigest()


def rewrite_u2_dependencies(database: Path) -> dict:
    sys.path.insert(0, str(HERE))
    from carrier_loop import CarrierInformationLoop  # noqa: PLC0415

    loop = CarrierInformationLoop.open(str(database))
    try:
        item = loop.current_item("TASK-U2")
        if item is None:
            raise RuntimeError("TASK-U2 missing before dependency rewrite")
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


def forge_u1_settlement(database: Path) -> dict:
    """Rewrite U1's value and every matching digest WITHOUT the signing key.

    This is the C4 negative: a locally self-consistent settlement (result,
    result digest and basis digest all agree) that was never signed by the
    trusted production path. A digest-only contract accepts it; the provenance
    contract must refuse it before any model input leaves the resolver.
    """
    sys.path.insert(0, str(HERE))
    from carrier_loop import CarrierInformationLoop, canonical, digest  # noqa: PLC0415

    loop = CarrierInformationLoop.open(str(database))
    try:
        settlement = loop.current_settlement("TASK-U1")
        if settlement is None:
            raise RuntimeError("U1 settlement missing before forge")
        previous_object_id = settlement["_object_id"]
        declaration = {
            key: value for key, value in settlement.items() if not key.startswith("_")
        }
        forged_secret = "forged-" + str(digest(declaration))[:24]
        forged_value = dict(declaration["result"]["value"])
        forged_value["secret"] = forged_secret
        forged_sha = digest(forged_value)
        declaration["result"]["value"] = forged_value
        declaration["result"]["result_value_sha256"] = forged_sha
        declaration["basis"]["result_value_sha256"] = forged_sha
        history = loop.carrier.get_dependency_history(SETTLEMENT_ID)
        new_object_id, _ = loop.carrier.atomic_dependency_materialization(
            canonical(declaration),
            {
                "dependency_id": SETTLEMENT_ID,
                "content_address": "",
                "revision": len(history) + 1,
                "reason": "forged settlement without signing key",
            },
        )
        loop.commit()
        return {
            "previous_object_id": previous_object_id,
            "forged_object_id": new_object_id,
            "forged_secret": forged_secret,
            "forged_result_value_sha256": forged_sha,
            "signature_reused": True,
        }
    finally:
        loop.close()


# --------------------------------------------------------------------------
# model-free MULTIHOP fixture: settled U1 + settled U2 + a U3 item that
# declares ONLY U2, so admitting U3 must recursively validate U2's own
# (SOURCE + U1) closure. Used by the Swift transitive-closure tests.
# --------------------------------------------------------------------------

def _checksum_of(run_label: str) -> str:
    import hashlib

    return hashlib.sha256(("checksum:" + run_label).encode("utf-8")).hexdigest()[:4]


def _settle_model_item(directory: Path, database: Path, item_id: str,
                       demand_id: str, advancement: str, secret: str,
                       extra_value: dict) -> dict:
    """Settle one model item with a synthetic (model-free) value.

    The value still passes the production result gate because it agrees with the
    settled dependency commitments declared by each item's own result contract;
    the point of the fixture is the admission graph, not the model output.
    """
    value = {
        "secret": secret,
        "generated_token_ids": [7, 8, 9],
        "model_snapshot_revision": "multihop-fixture-revision",
        "model_weights_manifest_sha256": "multihop-fixture-weights",
        "raw_generated_text": "SECRET=" + secret,
        "model_call_index": 1,
        **extra_value,
    }
    value_path = directory / ("%s-value.json" % item_id)
    value_path.write_text(json.dumps(value), encoding="utf-8")
    token_ids = json.dumps(value["generated_token_ids"], separators=(",", ":"))
    provenance = {
        "producer": {
            "kind": "model_task",
            "run_id": ENV["SIMIGO_SETTLEMENT_RUN_ID"],
            "execution_id": ENV["SIMIGO_SETTLEMENT_EXECUTION_ID"],
            "process_id": str(os.getpid()),
            "build_sha256": ENV["SIMIGO_SETTLEMENT_BUILD_SHA256"],
        },
        "model": {
            "snapshot_revision": value["model_snapshot_revision"],
            "weights_manifest_sha256": value["model_weights_manifest_sha256"],
        },
        "output": {
            "generated_token_ids_sha256": sha256_bytes(token_ids.encode("utf-8")),
            "generated_token_count": len(value["generated_token_ids"]),
        },
    }
    provenance_path = directory / ("%s-provenance.json" % item_id)
    provenance_path.write_text(json.dumps(provenance), encoding="utf-8")
    code, settled = run_bridge(
        "execute-with-model-result",
        "--database", str(database),
        "--demand-id", demand_id,
        "--advancement", advancement,
        "--evaluated-at", utc_now(),
        "--item-id", item_id,
        "--value-file", str(value_path),
        "--provenance-file", str(provenance_path),
        "--run-id", ENV["SIMIGO_SETTLEMENT_RUN_ID"],
        "--execution-id", ENV["SIMIGO_SETTLEMENT_EXECUTION_ID"],
        "--build-sha256", ENV["SIMIGO_SETTLEMENT_BUILD_SHA256"],
        "--producer-process-id", str(os.getpid()),
    )
    if code != 0 or not settled.get("ok"):
        raise RuntimeError("settle %s failed: %s" % (item_id, settled))
    # Mirror the Swift continueTask completion: a settled model item leaves a
    # PENDING_SWIFT runtime application on its advancement state, which the
    # next demand's restore_continuation refuses until confirmed. Confirm it so
    # the model-free fixture reaches a lawful settled U1 -> settled U2 lineage.
    state_id = ((settled.get("result") or {}).get(
        "execution_state") or {}).get("state_id")
    if state_id:
        confirm_code, confirm = run_bridge(
            "confirm-runtime-application",
            "--database", str(database),
            "--state-id", state_id,
        )
        if confirm_code != 0 or not confirm.get("ok"):
            raise RuntimeError(
                "confirm %s failed: %s" % (item_id, confirm))
    return settled


def prepare_multihop_database(directory: Path) -> dict:
    """Build a three-hop world with a real (synthetic) settled U1 and U2."""
    import secrets

    database = directory / "base.sqlite"
    run_label = "multihop-selftest"
    secret = secrets.token_hex(8)
    checksum = _checksum_of(run_label)
    code, defined = run_bridge(
        "define-task",
        "--database", str(database),
        "--evaluated-at", utc_now(),
        "--run-label", run_label,
        "--secret", secret,
    )
    if code != 0 or not defined.get("ok"):
        raise RuntimeError("define-task failed: %s" % defined)
    # Settle U1 (extract secret) then U2 (compose answer) with model-free values
    # that still satisfy the semantic validators, so U2 carries a signed
    # settlement binding the SOURCE + U1 closure.
    u1_settled = _settle_model_item(directory, database, "TASK-U1", "handoff-u1",
                                    "multihop-u1", secret, {})
    answer = "%s-%s" % (secret, checksum)
    _settle_model_item(directory, database, "TASK-U2", "handoff-u2",
                       "multihop-u2", secret, {
                           "answer": answer,
                           "raw_generated_text": "ANSWER=" + answer,
                       })
    # Add the U3 item that declares ONLY TASK-U2 as its dependency.
    sys.path.insert(0, str(HERE))
    os.environ.setdefault("SIMIGO_INFO_VALIDITY_POLICY_PATH",
                          ENV["SIMIGO_INFO_VALIDITY_POLICY_PATH"])
    os.environ.setdefault("SIMIGO_RUNTIME_ROOT", ENV["SIMIGO_RUNTIME_ROOT"])
    from carrier_loop import CarrierInformationLoop  # noqa: PLC0415
    from declarative_result_contract import (  # noqa: PLC0415
        derive_extraction_view as production_derive_extraction_view,
    )
    from production_runtime_bridge import (  # noqa: PLC0415
        CONTINUATION_POINT, load_deployment_validity_policy,
        deployment_default_validity,
    )

    policy = load_deployment_validity_policy()
    valid_until = deployment_default_validity(policy)
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
            {"placeholder": "answer", "item_id": "TASK-U2",
             "result_field": "answer"},
        ],
        "semantic_contract": {
            "schema_version": "simigo.result-contract/v1",
            "fields": {
                "stamp": {"pattern": "STAMP=([A-Za-z0-9]+)", "capture_group": 1,
                          "type": "string", "match_policy": "first"},
            },
            "bindings": [{"name": "answer", "source": "dependency_field",
                          "field": "answer"}],
            "constraints": [
                {"kind": "equals_binding_segment", "field": "stamp",
                 "binding": "answer", "separator": "-", "segment": 0},
            ],
        },
        "source_item_ids": ["TASK-U2"],
    }
    u3_payload["result_contract"] = production_derive_extraction_view(
        u3_payload["semantic_contract"])
    loop = CarrierInformationLoop.open(str(database))
    try:
        loop.put_source(
            CONTINUATION_POINT, "TASK-U3", "model-task", "v1", u3_payload,
            dependencies=["TASK-U2"], valid_until_utc=valid_until,
            validity_policy=policy)
        loop.commit()
    finally:
        loop.close()
    return {
        "database": database,
        "secret": secret,
        "secret_sha256": sha256_bytes(secret.encode("utf-8")),
        "checksum": checksum,
        "answer": answer,
        "u1_settlement_signature_object_id": (u1_settled.get(
            "settlement_signature", {}) or {}).get("signature_object_id"),
        "u1_signed_settlement_object_id": (u1_settled.get(
            "settlement_signature", {}) or {}).get("settlement_object_id"),
    }


def multihop_attempt(case: str, prepared: dict, work_directory: Path,
                     mutate) -> dict:
    """Resolve TASK-U3 against a (possibly mutated) multihop world."""
    case_directory = work_directory / case
    case_directory.mkdir()
    database = case_directory / "carrier.sqlite"
    copy_database(prepared["database"], database)
    mutation = mutate(database) if mutate else {}
    before_sha = sha256_file(database)
    entries_before = directory_entries(case_directory)
    code, payload = run_bridge(
        "resolve-model-input",
        "--database", str(database),
        "--item-id", "TASK-U3",
        "--evaluated-at", utc_now(),
    )
    after_sha = sha256_file(database)
    entries_after = directory_entries(case_directory)
    resolved_ids = sorted(
        dependency["item_id"] for dependency in (payload.get("dependencies") or []))
    if mutate is None:
        checks = {
            "exit_code_is_0": code == 0,
            "ok_is_true": payload.get("ok") is True,
            "declares_only_u2": payload.get("declared_dependencies") == ["TASK-U2"],
            "closure_includes_u1_and_u2": (
                "TASK-U1" in resolved_ids and "TASK-U2" in resolved_ids),
            "answer_bound_from_u2": any(
                binding["item_id"] == "TASK-U2" and binding["value"] == prepared["answer"]
                for binding in (payload.get("bindings") or [])),
            "database_bytes_unchanged": before_sha == after_sha,
        }
    else:
        refusal = payload.get("refusal") or {}
        checks = {
            "exit_code_is_1": code == 1,
            "ok_is_false": payload.get("ok") is False,
            "structured_refusal": isinstance(refusal, dict) and bool(refusal),
            "refusal_names_u1_closure": "TASK-U1" in json.dumps(refusal),
            "database_bytes_unchanged": before_sha == after_sha,
            "no_new_files": entries_before == entries_after,
        }
    return {
        "case": case,
        "mutation": mutation,
        "resolved_dependency_ids": resolved_ids,
        "exit_code": code,
        "payload": payload,
        "checks": checks,
        "verdict": "PASS" if all(checks.values()) else "FAIL",
    }


def attempt(
    case: str,
    prepared: dict,
    work_directory: Path,
    mutate,
    expected_stage: str,
    expected_reason: str | None,
) -> dict:
    case_directory = work_directory / case
    case_directory.mkdir()
    database = case_directory / "carrier.sqlite"
    copy_database(prepared["database"], database)
    mutation = mutate(database) if mutate else {}
    before_sha = sha256_file(database)
    entries_before = directory_entries(case_directory)
    code, payload = run_bridge(
        "resolve-model-input",
        "--database", str(database),
        "--item-id", "TASK-U2",
        "--evaluated-at", utc_now(),
    )
    after_sha = sha256_file(database)
    entries_after = directory_entries(case_directory)
    refusal = payload.get("refusal") or {}
    checks = {
        "exit_code_is_1": code == 1,
        "ok_is_false": payload.get("ok") is False,
        "structured_refusal": isinstance(refusal, dict) and bool(refusal),
        "stage_matches": refusal.get("stage") == expected_stage,
        "reason_matches": (
            expected_reason is None
            or str(refusal.get("reason", "")).startswith(expected_reason)
        ),
        "database_bytes_unchanged": before_sha == after_sha,
        "no_new_files": entries_before == entries_after,
    }
    return {
        "case": case,
        "mutation": mutation,
        "expected_stage": expected_stage,
        "expected_reason_prefix": expected_reason,
        "exit_code": code,
        "payload": payload,
        "database_sha256_before": before_sha,
        "database_sha256_after": after_sha,
        "entries_before": entries_before,
        "entries_after": entries_after,
        "checks": checks,
        "verdict": "PASS" if all(checks.values()) else "FAIL",
    }


def happy_path(prepared: dict, work_directory: Path) -> dict:
    case_directory = work_directory / "happy"
    case_directory.mkdir()
    database = case_directory / "carrier.sqlite"
    copy_database(prepared["database"], database)
    before_sha = sha256_file(database)
    code, payload = run_bridge(
        "resolve-model-input",
        "--database", str(database),
        "--item-id", "TASK-U2",
        "--evaluated-at", utc_now(),
    )
    bindings = payload.get("bindings") or []
    input_text = payload.get("input_text") or ""
    raw = input_text.encode("utf-8")
    offsets_match = True
    for binding in bindings:
        start = binding["byte_offset"]
        end = start + binding["byte_length"]
        if raw[start:end].decode("utf-8", errors="replace") != binding["value"]:
            offsets_match = False
    by_placeholder = {binding["placeholder"]: binding for binding in bindings}
    checks = {
        "exit_code_is_0": code == 0,
        "ok_is_true": payload.get("ok") is True,
        "two_bindings": len(bindings) == 2,
        "offsets_match_admitted_values": offsets_match,
        "secret_bound_from_u1": (
            by_placeholder.get("secret", {}).get("item_id") == "TASK-U1"
            and by_placeholder.get("secret", {}).get("value") == prepared["secret"]
        ),
        "checksum_bound_from_source": (
            by_placeholder.get("checksum", {}).get("item_id") == "TASK-SOURCE"
        ),
        "dependency_closure_complete": sorted(
            payload.get("declared_dependencies") or []
        ) == ["TASK-SOURCE", "TASK-U1"],
        "object_identity_is_content_digest": all(
            binding["settlement_object_id"] == binding["settlement_object_sha256"]
            for binding in bindings
        ),
        "all_reported_checks_true": all(
            (payload.get("checks") or {}).values()
        ),
        "database_bytes_unchanged": before_sha == sha256_file(database),
    }
    return {
        "case": "happy",
        "exit_code": code,
        "input_sha256": payload.get("input_sha256"),
        "bindings": [
            {
                "placeholder": binding["placeholder"],
                "item_id": binding["item_id"],
                "byte_offset": binding["byte_offset"],
                "byte_length": binding["byte_length"],
                "settlement_object_id": binding["settlement_object_id"],
                "result_value_sha256": binding["result_value_sha256"],
            }
            for binding in bindings
        ],
        "checks": checks,
        "verdict": "PASS" if all(checks.values()) else "FAIL",
    }


MUTATIONS = {
    "happy": None,
    "missing-settlement": None,
    "tampered-object-bytes": None,
    "dependency-mismatch": None,
    "forged-u1-settlement": None,
    "multihop-happy": None,
    "multihop-missing-u1": None,
}


def emit_fixture(case: str, out_database: Path) -> int:
    """Materialize one isolated case database for another test harness.

    The Swift admission test uses this so its fixtures are produced by the
    same mutation code the Python selftest verifies, instead of a second
    hand-written copy of the mutations.
    """
    mutations = {
        "happy": None,
        "missing-settlement": remove_u1_settlement,
        "tampered-object-bytes": tamper_u1_object,
        "dependency-mismatch": rewrite_u2_dependencies,
        "forged-u1-settlement": forge_u1_settlement,
        "multihop-happy": None,
        "multihop-missing-u1": remove_u1_settlement,
    }
    if case not in mutations:
        print(json.dumps({"ok": False, "error": "unknown case: %s" % case}))
        return 2
    work_directory = Path(tempfile.mkdtemp(prefix="simigo-admission-fixture-"))
    trust_directory = out_database.parent / ("trust-" + case)
    trust = provision_trust(trust_directory)
    try:
        if case.startswith("multihop"):
            prepared = prepare_multihop_database(work_directory)
        else:
            prepared = prepare_database(work_directory)
        out_database.parent.mkdir(parents=True, exist_ok=True)
        copy_database(prepared["database"], out_database)
        mutate = mutations[case]
        mutation = mutate(out_database) if mutate else {}
        print(json.dumps({
            "ok": True,
            "case": case,
            "database": str(out_database),
            "database_sha256": sha256_file(out_database),
            "secret_sha256": prepared["secret_sha256"],
            "settlement_signature_object_id": prepared[
                "u1_settlement_signature_object_id"
            ],
            "signed_settlement_object_id": prepared[
                "u1_signed_settlement_object_id"
            ],
            "trust_anchor_path": trust["anchor_path"],
            "mutation": mutation,
        }, sort_keys=True))
        return 0
    finally:
        shutil.rmtree(work_directory, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out")
    parser.add_argument("--emit-fixture", choices=sorted(MUTATIONS))
    parser.add_argument("--out-database")
    arguments = parser.parse_args()
    if arguments.emit_fixture:
        if not arguments.out_database:
            parser.error("--emit-fixture requires --out-database")
        return emit_fixture(arguments.emit_fixture, Path(arguments.out_database))
    if not arguments.out:
        parser.error("--out is required")

    work_directory = Path(tempfile.mkdtemp(prefix="simigo-admission-selftest-"))
    try:
        provision_trust(work_directory / "trust")
        prepared = prepare_database(work_directory)
        multihop_directory = work_directory / "multihop"
        multihop_directory.mkdir()
        mprepared = prepare_multihop_database(multihop_directory)
        results = {
            "schema_id": "SIMIGO-ADMISSION-SELFTEST-V1",
            "created_at_utc": utc_now(),
            "work_directory": str(work_directory),
            "conditions": [
                happy_path(prepared, work_directory),
                attempt(
                    "missing-settlement",
                    prepared,
                    work_directory,
                    remove_u1_settlement,
                    "SETTLEMENT_NOT_ADMITTED",
                    "MISSING_OR_SUPERSEDED_SETTLEMENT",
                ),
                attempt(
                    "tampered-object-bytes",
                    prepared,
                    work_directory,
                    tamper_u1_object,
                    "SETTLEMENT_OBJECT_UNREADABLE",
                    None,
                ),
                attempt(
                    "dependency-mismatch",
                    prepared,
                    work_directory,
                    rewrite_u2_dependencies,
                    "INPUT_BINDING_DEPENDENCY_NOT_DECLARED",
                    None,
                ),
                attempt(
                    "forged-u1-settlement",
                    prepared,
                    work_directory,
                    forge_u1_settlement,
                    "SETTLEMENT_SIGNATURE_INVALID",
                    None,
                ),
                multihop_attempt(
                    "multihop-happy", mprepared, work_directory, None),
                multihop_attempt(
                    "multihop-missing-u1", mprepared, work_directory,
                    remove_u1_settlement),
            ],
        }
        results["verdict"] = (
            "PASS"
            if all(item["verdict"] == "PASS" for item in results["conditions"])
            else "FAIL"
        )
        Path(arguments.out).parent.mkdir(parents=True, exist_ok=True)
        Path(arguments.out).write_text(
            json.dumps(results, indent=1, sort_keys=True) + "\n", encoding="utf-8"
        )
        print(json.dumps({
            "verdict": results["verdict"],
            "conditions": [
                {"case": item["case"], "verdict": item["verdict"], "checks": item["checks"]}
                for item in results["conditions"]
            ],
        }, indent=1, sort_keys=True))
        return 0 if results["verdict"] == "PASS" else 1
    finally:
        shutil.rmtree(work_directory, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
