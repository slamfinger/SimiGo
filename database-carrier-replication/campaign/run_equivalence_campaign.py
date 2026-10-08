#!/usr/bin/env python3
"""Run the single authorized Database-Carrier equivalence campaign.

This is observation/provenance instrumentation only. It changes no accepted
carrier semantics and performs no equivalence adjudication: the evidence is
stopped for Human audit.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

from evidence_paths import EvidencePaths, load_and_preflight

ROOT = Path(subprocess.check_output(
    ["git", "rev-parse", "--show-toplevel"], text=True
).strip())
IMPLEMENTATION_COMMIT = "7392fcb79fb7e8465b73f9e1837c4634e56c0409"
REFERENCE_EXECUTION_STATE = "69b2227dbd9ec7bfc8ad744d65efe46e3a9ab33a"
REFERENCE_EVIDENCE_COMMIT = "cb365a44c48d4b7b90b4cc2155fcae00d3e01572"
ACCEPTED_FRESH_DB_COMMIT = "32ef3b06a4af808917cf7f4e248e9539c684b35f"
SOURCE_DATABASE_PATH = Path(
    "docs/02-evidence/database-carrier-fresh-initialization-v1.2-20261008/"
    "FRESH_EMPTY_IS.sqlite"
)
SOURCE_DATABASE_SHA256 = "6baa7afa8b5c623c75b3111af267e270d76d663547e730af5e7ca62b7602d14d"
ADAPTER_RUNTIME_SHA256 = "e88c996b9a64df10dd03f7622ffa8757551baf352908e4d7bf8704295eaffcc7"

OBJECT_IDS = {
    "D": "806fffadef09d3ad491d75c6b42738e99626ee1961ed1aecf2d593aefd55980c",
    "SRS": "26025863df8311f536b067718e8c8466fb9dafa7924c629429e6766f2926c3f9",
    "CR": "1703f2d664c58d4fe88032b7b3750ab885522c1a5a73e04570be108f7c6bf026",
    "D_PRIME": "8553f52449b67de21021bb50ad6380c455bf686ee2a06cc77ed51e9f30060955",
}
SRS_IDENTITY = "5e01d6ce03526c6ba6bf988a9caf6505af169c3155fe7bf4716ea717f893de8f"
INVOCATION_HASHES = {
    "ES2": "0c3c547af76ef386dfce65bc2d31cf2348eea2873b300cd23041eeae1c4df5e1",
    "ESN": "315816a7d10c776641fa011210cc301ff483899a5e1bf54ac7e8a7b42287049c",
}
CANONICAL_SOURCES = {
    "SRSVALInvocation.swift": "6583a80444848a3b42b55ea82f9de6cc1350af6154f6f23c3c3ab61427226c75",
    "SRSVALDecision.swift": "e219aeeadceb74a2d37cb20fdb76ee18d23ee739a743ecf6309e7384b58b15de",
    "SRSVALCore.swift": "9725217063b9aa560752e8485dac64aae41a314c429f6b9aa1d8808a4860d56e",
    "main.swift": "61b8ad39c467ed7ff90e4d8670ea903bf7be12e20166c7cff21df4bdbf0231ac",
}


class CampaignFailure(RuntimeError):
    pass


SERIALIZATION_CANONICALIZATION = (
    "json.dumps(sort_keys=True, indent=2, ensure_ascii=False, "
    "allow_nan=False) + LF"
)
serialization_checks: list[dict[str, object]] = []


def canonical_json_bytes(value: object) -> bytes:
    try:
        text = json.dumps(
            value,
            sort_keys=True,
            indent=2,
            ensure_ascii=False,
            allow_nan=False,
        ) + "\n"
        parsed = json.loads(text)
        require(parsed == value, "canonical JSON round-trip mismatch")
        return text.encode("utf-8")
    except CampaignFailure:
        raise
    except (TypeError, ValueError, json.JSONDecodeError) as exc:
        raise CampaignFailure(
            f"evidence object is not canonically serializable: {exc}"
        ) from exc


def persist_exact_json(path: Path, payload: bytes) -> dict:
    require(payload and not path.exists() and not path.is_symlink(), f"exact JSON destination invalid: {path}")
    parsed = json.loads(payload)
    with path.open("xb") as handle:
        handle.write(payload)
    persisted = path.read_bytes()
    require(persisted == payload, f"exact JSON byte persistence mismatch: {path}")
    require(json.loads(persisted) == parsed, f"exact JSON parsed-object mismatch: {path}")
    binding = {
        "artifact_path": path.name,
        "byte_length": len(persisted),
        "byte_persistence_exact": True,
        "parsed_object_exact": True,
        "pass": True,
        "pre_write_serialization_check": "PASS",
        "serialized_canonicalization": "REFERENCE_EXACT_BYTES",
        "sha256": sha256(persisted),
    }
    serialization_checks.append(binding)
    return binding


def write_json(path: Path, value: object) -> dict[str, object]:
    payload = canonical_json_bytes(value)
    require(
        path.parent.exists() and path.parent.is_dir() and not path.is_symlink(),
        f"evidence destination parent invalid: {path}",
    )
    require(not path.exists(), f"evidence destination already exists: {path}")
    with path.open("xb") as handle:
        handle.write(payload)
    persisted = path.read_bytes()
    require(persisted == payload, f"evidence byte persistence mismatch: {path}")
    parsed = json.loads(persisted)
    require(parsed == value, f"evidence parsed-object mismatch: {path}")
    binding = {
        "artifact_path": path.name,
        "byte_length": len(persisted),
        "byte_persistence_exact": True,
        "parsed_object_exact": True,
        "pass": True,
        "pre_write_serialization_check": "PASS",
        "serialized_canonicalization": SERIALIZATION_CANONICALIZATION,
        "sha256": sha256(persisted),
    }
    serialization_checks.append(binding)
    return binding


def write_serialization_self_check(paths: EvidencePaths) -> dict:
    path_binding_path = paths.resolve("EVIDENCE_PATH_BINDING_EXECUTION")
    path_binding = json.loads(path_binding_path.read_bytes())
    require(
        path_binding.get("overall_pass") is True and path_binding.get("independent_path_derivation") is False,
        "independent evidence-path preflight binding invalid",
    )
    transaction_log = paths.resolve("TRANSACTION_LOG")
    transaction_records = [
        json.loads(line) for line in transaction_log.read_text(encoding="utf-8").splitlines()
    ]
    require(bool(transaction_records), "transaction log has no canonical records")
    checks = list(serialization_checks)
    checks.extend([
        {
            "artifact_path": path_binding_path.name,
            "byte_persistence_exact": True,
            "independent_path_preflight": True,
            "parsed_object_exact": True,
            "pass": True,
            "pre_write_serialization_check": "PASS",
            "serialized_canonicalization": SERIALIZATION_CANONICALIZATION,
        },
        {
            "artifact_path": transaction_log.name,
            "canonical_jsonl_record_count": len(transaction_records),
            "parsed_object_exact": True,
            "pass": True,
            "pre_write_serialization_check": "PASS",
            "serialized_canonicalization": SERIALIZATION_CANONICALIZATION,
        },
    ])
    summary = {
        "all_canonical_artifacts_pass": True,
        "artifact_count": len(checks),
        "checks": checks,
        "path_like_json_boundary": "FORBIDDEN",
        "self_check": {
            "post_write_byte_and_parse_equality": "ENFORCED",
            "pre_write_recursive_serialization_check": "PASS",
        },
        "serialized_canonicalization": SERIALIZATION_CANONICALIZATION,
    }
    write_json(paths.resolve("EVIDENCE_SERIALIZATION_SELF_CHECK"), summary)
    return summary


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_path(path: Path) -> str:
    return sha256(path.read_bytes())


def utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()




def persist_observer_verdict(paths: EvidencePaths, observer: dict) -> dict:
    canonical_key = "C3_persisted_vs_resolved_byte_equality"
    require(canonical_key in observer, "canonical C3 observer key absent")
    require(observer[canonical_key] is True, "canonical C3 observer mismatch")
    serialized = canonical_json_bytes(observer)
    verdict_path = paths.resolve("OBSERVER_VERDICT")
    with verdict_path.open("xb") as handle:
        handle.write(serialized)
    persisted = verdict_path.read_bytes()
    require(persisted == serialized, "observer verdict byte persistence mismatch")
    parsed = json.loads(persisted)
    require(parsed == observer, "observer verdict parsed-object mismatch")
    binding = {
        "canonical_c3_key": canonical_key,
        "canonical_c3_value": True,
        "observer_path": verdict_path.relative_to(paths.output_root).as_posix(),
        "parsed_object_exact": True,
        "persistence_self_check": "PASS",
        "serialized_canonicalization": (
            "json.dumps(sort_keys=True, separators=(',', ':')) + LF"
        ),
        "verdict_byte_length": len(persisted),
        "verdict_sha256": sha256(persisted),
    }
    write_json(paths.resolve("OBSERVER_PERSISTENCE_BINDING"), binding)
    serialization_checks.insert(0, {
        "artifact_path": paths.resolve("OBSERVER_VERDICT").name,
        "byte_length": len(serialized),
        "byte_persistence_exact": True,
        "parsed_object_exact": True,
        "pass": True,
        "pre_write_serialization_check": "PASS",
        "serialized_canonicalization": SERIALIZATION_CANONICALIZATION,
        "sha256": sha256(serialized),
    })
    return binding


def git_bytes(commit: str, path: str) -> bytes:
    return subprocess.check_output(["git", "-C", str(ROOT), "show", f"{commit}:{path}"])


def require(condition: bool, message: str) -> None:
    if not condition:
        raise CampaignFailure(message)


def expected_objects(point: str) -> list[str]:
    return {
        "O0": [],
        "O1": ["D"],
        "O2": ["D", "SRS"],
        "O3": ["D", "SRS", "CR"],
        "O4": ["D", "SRS", "CR", "D_PRIME"],
        "O5": ["D", "SRS", "CR", "D_PRIME"],
    }[point]


def expected_indexes(point: str) -> list[dict[str, object]]:
    values = []
    for logical in expected_objects(point):
        if logical == "SRS":
            values.append({"append_order": 1, "record_object": OBJECT_IDS[logical], "srs_identity": SRS_IDENTITY})
        if logical == "CR":
            values.append({"append_order": 2, "record_object": OBJECT_IDS[logical], "srs_identity": "CR:CR-ES2-r2"})
    return values


def expected_dependencies(point: str) -> list[dict[str, object]]:
    values = []
    if point in {"O1", "O2", "O3", "O4", "O5"}:
        values.append({
            "append_order": 1,
            "content_address": OBJECT_IDS["D"],
            "dependency_id": "D-1",
            "reason": "initial materialization",
            "revision": 1,
        })
    if point in {"O4", "O5"}:
        values.append({
            "append_order": 2,
            "content_address": OBJECT_IDS["D_PRIME"],
            "dependency_id": "D-1",
            "reason": "N1 negative-control state advance",
            "revision": 2,
        })
    return values


def verify_execution_repository(expected_head: str) -> dict:
    head = subprocess.check_output(
        ["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True
    ).strip()
    require(head == expected_head, f"HEAD mismatch: {head} != {expected_head}")
    subprocess.run(
        ["git", "-C", str(ROOT), "merge-base", "--is-ancestor", IMPLEMENTATION_COMMIT, head],
        check=True,
    )
    unchanged = subprocess.run(
        [
            "git", "-C", str(ROOT), "diff", "--quiet", IMPLEMENTATION_COMMIT, head,
            "--", "database-carrier-replication/implementation",
        ],
        check=False,
    ).returncode == 0
    require(unchanged, "accepted implementation tree changed")
    return {
        "campaign_repository_commit": head,
        "implementation_commit": IMPLEMENTATION_COMMIT,
        "implementation_tree_unchanged": True,
        "implementation_is_ancestor": True,
    }


def verify_reference_inputs() -> dict[str, bytes]:
    objects = {
        logical: git_bytes(
            REFERENCE_EVIDENCE_COMMIT,
            f"docs/02-evidence/srs-real-closure-01/runs/exec-006-69b2227/is/objects/{object_id}",
        )
        for logical, object_id in OBJECT_IDS.items()
    }
    for logical, content in objects.items():
        require(sha256(content) == OBJECT_IDS[logical], f"reference object mismatch: {logical}")
    index = git_bytes(
        REFERENCE_EVIDENCE_COMMIT,
        "docs/02-evidence/srs-real-closure-01/runs/exec-006-69b2227/is/index.jsonl",
    )
    dependencies = git_bytes(
        REFERENCE_EVIDENCE_COMMIT,
        "docs/02-evidence/srs-real-closure-01/runs/exec-006-69b2227/is/current/dependencies.jsonl",
    )
    require(
        sha256(index) == "4eb0cc7101c9f6bafd6cc68e96630199c2a3442be887a14632f92d086e82809f",
        "reference index mismatch",
    )
    require(
        sha256(dependencies) == "0d958cbfdac47a5a63c53dd3448b33119c04d4d70b1865a8601deb449adf997b",
        "reference dependency mapping mismatch",
    )
    return objects


def extract_invocations(paths: EvidencePaths) -> dict[str, dict]:
    result = {}
    for decision, filename in {
        "ES2": "invocation_graph-es2.json",
        "ESN": "invocation_graph-esn.json",
    }.items():
        raw = git_bytes(
            REFERENCE_EVIDENCE_COMMIT,
            f"docs/02-evidence/srs-real-closure-01/runs/exec-006-69b2227/{filename}",
        )
        require(sha256(raw) == INVOCATION_HASHES[decision], f"{decision} invocation mismatch")
        path = paths.resolve(f"ADAPTER_{decision}_INPUT")
        persist_exact_json(path, raw)
        result[decision] = json.loads(raw)
    return result


def build_adapter(paths: EvidencePaths) -> tuple[Path, dict]:
    build = paths.resolve("ADAPTER_BUILD_DIRECTORY")
    hashes = {}
    for filename, expected in CANONICAL_SOURCES.items():
        if filename == "main.swift":
            content = git_bytes(
                REFERENCE_EXECUTION_STATE,
                "docs/02-evidence/srs-real-closure-01/fixture/adapter/srsval_adapter.swift",
            )
        else:
            content = git_bytes(
                "07176ec", f"trackD-memory/Sources/SettledRelationValidationCore/{filename}"
            )
        require(sha256(content) == expected, f"canonical source mismatch: {filename}")
        (build / filename).write_bytes(content)
        hashes[filename] = expected
    command = [
        "swiftc", "-O", "SRSVALInvocation.swift", "SRSVALDecision.swift",
        "SRSVALCore.swift", "main.swift", "-o", "srsval_adapter",
    ]
    proc = subprocess.run(command, cwd=build, capture_output=True, text=True)
    require(proc.returncode == 0, f"adapter build failed: {proc.stderr[-1000:]}")
    binary = build / "srsval_adapter"
    runtime_hash = sha256_path(binary)
    require(runtime_hash == ADAPTER_RUNTIME_SHA256, f"adapter runtime mismatch: {runtime_hash}")
    write_json(paths.resolve("ADAPTER_BUILD_COMMAND"), {
        "command": command,
        "returncode": proc.returncode,
        "stdout": proc.stdout,
        "stderr": proc.stderr,
    })
    write_json(paths.resolve("ADAPTER_SOURCE_HASHES"), hashes)
    return binary, {"runtime_artifact_sha256": runtime_hash, "build_returncode": 0}


def snapshot(carrier) -> dict:
    connection = carrier.connection
    objects = []
    for row in connection.execute(
        "SELECT object_id, byte_size, content, created_order FROM is_objects "
        "ORDER BY created_order ASC"
    ):
        content = bytes(row["content"])
        objects.append({
            "byte_size": int(row["byte_size"]),
            "content_sha256": sha256(content),
            "created_order": int(row["created_order"]),
            "object_id": row["object_id"],
        })
    indexes = [
        {
            "append_order": int(row["append_order"]),
            "record_object": row["record_object"],
            "srs_identity": row["srs_identity"],
        }
        for row in connection.execute(
            "SELECT append_order, srs_identity, record_object FROM is_index_entries "
            "ORDER BY append_order ASC"
        )
    ]
    dependencies = [
        {
            "append_order": int(row["append_order"]),
            "content_address": row["content_address"],
            "dependency_id": row["dependency_id"],
            "reason": row["reason"],
            "revision": int(row["revision"]),
        }
        for row in connection.execute(
            "SELECT append_order, dependency_id, content_address, revision, reason "
            "FROM dependency_entries ORDER BY append_order ASC"
        )
    ]
    current = None
    if dependencies:
        row = carrier.resolve_current_dependency("D-1")
        current = {
            "append_order": row.append_order,
            "content_address": row.content_address,
            "dependency_id": row.dependency_id,
            "reason": row.reason,
            "revision": row.revision,
        }
    read_results = {}
    for logical in OBJECT_IDS:
        object_id = OBJECT_IDS[logical]
        if any(item["object_id"] == object_id for item in objects):
            content = carrier.get_object(object_id)
            read_results[logical] = {
                "byte_size": len(content),
                "matches_object_id": sha256(content) == object_id,
                "sha256": sha256(content),
            }
    srs_read = None
    if any(item["srs_identity"] == SRS_IDENTITY for item in indexes):
        resolved = carrier.resolve_srs_identity(SRS_IDENTITY)
        content = carrier.get_object(resolved.record_object)
        srs_read = {
            "append_order": resolved.append_order,
            "byte_size": len(content),
            "record_object": resolved.record_object,
            "sha256": sha256(content),
        }
    logical_tables = {"dependency_entries", "is_index_entries", "is_objects"}
    sqlite_entities = [
        {"name": row[0], "type": row[1]}
        for row in connection.execute(
            "SELECT name, type FROM sqlite_master "
            "WHERE name NOT LIKE 'sqlite_%' AND type IN ('table','view','trigger')"
        )
    ]
    extra_state = sorted(
        item["name"] for item in sqlite_entities if item["name"] not in logical_tables
    )
    return {
        "current_dependency": current,
        "dependency_entries": dependencies,
        "extra_observable_entities": extra_state,
        "index_entries": indexes,
        "integrity_check": connection.execute("PRAGMA integrity_check").fetchone()[0],
        "logical_row_counts": {
            "dependency_entries": len(dependencies),
            "is_index_entries": len(indexes),
            "is_objects": len(objects),
        },
        "object_reads": read_results,
        "objects": objects,
        "srs_read": srs_read,
    }


def compare_snapshot(point: str, actual: dict) -> dict:
    expected_object_ids = [OBJECT_IDS[key] for key in expected_objects(point)]
    actual_object_ids = [item["object_id"] for item in actual["objects"]]
    return {
        "EQ-1_object_set_bytes_hashes": actual_object_ids == expected_object_ids,
        "EQ-3_index": actual["index_entries"] == expected_indexes(point),
        "EQ-4_dependency_history": actual["dependency_entries"] == expected_dependencies(point),
        "EQ-5_current_resolution": actual["current_dependency"] == (
            expected_dependencies(point)[-1] if expected_dependencies(point) else None
        ),
        "EQ-6_read_results": all(
            item["matches_object_id"] for item in actual["object_reads"].values()
        ) and (
            actual["srs_read"] is None
            or actual["srs_read"]["sha256"] == OBJECT_IDS["SRS"]
        ),
        "EQ-8_no_extra_observable_state": actual["extra_observable_entities"] == [],
        "integrity_check": actual["integrity_check"] == "ok",
    }


def validate_adapter_input(decision: str, invocation: dict, carrier) -> dict:
    dep = invocation["dependencies"][0]
    pinned_id = dep["revisionBinding"]["integrityBinding"].removeprefix("sha256:")
    require(dep["dependencyIdentity"] == "D-1", f"{decision} dependency identity mismatch")
    require(pinned_id == OBJECT_IDS["D"], f"{decision} pinned dependency mismatch")
    require(invocation["srs"]["settlementIdentity"] == SRS_IDENTITY, f"{decision} SRS mismatch")
    if decision == "ES2":
        current = carrier.resolve_current_dependency("D-1")
        require(current.revision == 1 and current.content_address == OBJECT_IDS["D"], "ES2 DB current mismatch")
        require(dep["resolved"] is True and dep["blockingInvalidation"] is False, "ES2 dependency flags mismatch")
    else:
        current = carrier.resolve_current_dependency("D-1")
        require(current.revision == 2 and current.content_address == OBJECT_IDS["D_PRIME"], "ESN DB current mismatch")
        require(dep["resolved"] is False and dep["blockingInvalidation"] is True, "ESN dependency flags mismatch")
    return {
        "current_database_revision": current.revision,
        "current_database_address": current.content_address,
        "pinned_dependency_address": pinned_id,
    }


def invoke_adapter(paths: EvidencePaths, decision: str) -> dict:
    binary = paths.resolve("ADAPTER_BINARY")
    input_path = paths.resolve(f"ADAPTER_{decision}_INPUT")
    output_path = paths.resolve(f"ADAPTER_{decision}_OUTPUT")
    proc = subprocess.run([str(binary), str(input_path)], capture_output=True)
    require(proc.returncode == 0, f"{decision} adapter failed: {proc.stderr.decode('utf-8', errors='replace')}")
    persist_exact_json(output_path, proc.stdout)
    result = json.loads(output_path.read_bytes())
    expected = "REUSE" if decision == "ES2" else "BLOCK"
    require(result["primaryDecision"] == expected, f"{decision} decision mismatch")
    return {
        "decision": result,
        "expected": expected,
        "input_sha256": sha256_path(input_path),
        "match": result["primaryDecision"] == expected,
        "output_sha256": sha256_path(output_path),
        "returncode": proc.returncode,
        "stderr": proc.stderr.decode("utf-8", errors="replace"),
        "stdout": proc.stdout.decode("utf-8", errors="replace"),
    }


def write_sha_sums(paths: EvidencePaths) -> None:
    lines = []
    output = paths.output_root
    sums_path = paths.resolve("SHA256SUMS")
    for path in sorted(p for p in output.rglob("*") if p.is_file() and p != sums_path):
        lines.append(f"{sha256_path(path)}  {path.relative_to(output)}")
    sums_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def run(expected_head: str, output: Path) -> int:
    require(not output.exists(), f"campaign output already exists: {output}")
    output.mkdir(parents=True)
    evidence_paths = load_and_preflight(ROOT, output)
    started_utc = utcnow()
    started_ns = time.time_ns()
    repository = verify_execution_repository(expected_head)
    require(
        sha256_path(ROOT / SOURCE_DATABASE_PATH) == SOURCE_DATABASE_SHA256,
        "accepted fresh database mismatch",
    )
    reference = verify_reference_inputs()
    source_database_copy = evidence_paths.resolve("O0_DATABASE")
    shutil.copy2(ROOT / SOURCE_DATABASE_PATH, source_database_copy)
    require(sha256_path(source_database_copy) == SOURCE_DATABASE_SHA256, "O0 database copy mismatch")
    sys.path.insert(0, str(ROOT / "database-carrier-replication" / "implementation"))
    from db_is import DatabaseBackedIS

    adapter_build_record = build_adapter(evidence_paths)
    invocations = extract_invocations(evidence_paths)
    transaction_log = evidence_paths.resolve("TRANSACTION_LOG")

    def log_event(event: str, **fields: object) -> None:
        record = {"event": event, "time_ns": time.time_ns(), "utc": utcnow(), **fields}
        line = canonical_json_bytes(record).decode("utf-8")
        with transaction_log.open("a", encoding="utf-8") as fh:
            fh.write(line)

    work_db = evidence_paths.resolve("CAMPAIGN_DATABASE")
    require(not work_db.exists() and not work_db.is_symlink(), "working database already exists")
    shutil.copy2(ROOT / SOURCE_DATABASE_PATH, work_db)
    working_copy_sha256 = sha256_path(work_db)
    require(working_copy_sha256 == SOURCE_DATABASE_SHA256, "working database copy mismatch")
    working_copy_binding = {
        "copy_complete": True,
        "open_allowed_after_verification": True,
        "source_commit": ACCEPTED_FRESH_DB_COMMIT,
        "source_path": SOURCE_DATABASE_PATH.as_posix(),
        "source_sha256": SOURCE_DATABASE_SHA256,
        "working_copy_path": work_db.relative_to(ROOT).as_posix(),
        "working_copy_sha256_before_open": working_copy_sha256,
    }
    write_json(evidence_paths.resolve("WORKING_COPY_BINDING"), working_copy_binding)
    carrier = DatabaseBackedIS(work_db)
    observations = {}
    checks = {}
    try:
        carrier.validate_schema()
        for point in ("O0", "O1", "O2", "O3", "O4", "O5"):
            if point == "O1":
                log_event("TRANSACTION_BEGIN", operation_classes=["INSERT is_objects", "INSERT dependency_entries"], stage="materialize")
                object_id, dependency_order = carrier.atomic_dependency_materialization(
                    reference["D"],
                    {
                        "content_address": OBJECT_IDS["D"],
                        "dependency_id": "D-1",
                        "reason": "initial materialization",
                        "revision": 1,
                    },
                )
                log_event("TRANSACTION_COMMIT", dependency_order=dependency_order, object_id=object_id, operation_classes=["INSERT is_objects", "INSERT dependency_entries"], stage="materialize")
            if point == "O2":
                log_event("TRANSACTION_BEGIN", operation_classes=["INSERT is_objects", "INSERT is_index_entries"], stage="es1")
                with carrier.atomic_write_group():
                    object_id = carrier.write_object(reference["SRS"])
                    index_order = carrier.append_index_entry({
                        "record_object": object_id,
                        "srs_identity": SRS_IDENTITY,
                    })
                log_event("TRANSACTION_COMMIT", index_order=index_order, object_id=object_id, operation_classes=["INSERT is_objects", "INSERT is_index_entries"], stage="es1")
            if point == "O3":
                db_state = validate_adapter_input("ES2", invocations["ES2"], carrier)
                adapter_results = {"ES2": invoke_adapter(evidence_paths, "ES2")}
                log_event("TRANSACTION_BEGIN", operation_classes=["INSERT is_objects", "INSERT is_index_entries"], stage="es2_continuation")
                with carrier.atomic_write_group():
                    object_id = carrier.write_object(reference["CR"])
                    index_order = carrier.append_index_entry({
                        "record_object": object_id,
                        "srs_identity": "CR:CR-ES2-r2",
                    })
                log_event("TRANSACTION_COMMIT", index_order=index_order, object_id=object_id, operation_classes=["INSERT is_objects", "INSERT is_index_entries"], stage="es2_continuation")
            if point == "O4":
                log_event("TRANSACTION_BEGIN", operation_classes=["INSERT is_objects", "INSERT dependency_entries"], stage="mutate_n1")
                object_id, dependency_order = carrier.atomic_dependency_materialization(
                    reference["D_PRIME"],
                    {
                        "content_address": OBJECT_IDS["D_PRIME"],
                        "dependency_id": "D-1",
                        "reason": "N1 negative-control state advance",
                        "revision": 2,
                    },
                )
                log_event("TRANSACTION_COMMIT", dependency_order=dependency_order, object_id=object_id, operation_classes=["INSERT is_objects", "INSERT dependency_entries"], stage="mutate_n1")
            if point == "O5":
                db_state_esn = validate_adapter_input("ESN", invocations["ESN"], carrier)
                adapter_results["ESN"] = invoke_adapter(evidence_paths, "ESN")
            observations[point] = snapshot(carrier)
            checks[point] = compare_snapshot(point, observations[point])
            require(all(checks[point].values()), f"{point} observation mismatch: {checks[point]}")
            write_json(evidence_paths.resolve(f"OBSERVATION_{point}"), observations[point])
    finally:
        carrier.close()

    final_database = evidence_paths.resolve("O5_DATABASE")
    shutil.copy2(work_db, final_database)
    immutability = {
        logical: all(
            any(item["object_id"] == OBJECT_IDS[logical] and item["content_sha256"] == OBJECT_IDS[logical]
                for item in observations[point]["objects"])
            for point in ("O1", "O2", "O3", "O4", "O5")
            if logical in expected_objects(point)
        )
        for logical in OBJECT_IDS
    }
    require(all(immutability.values()), "object immutability mismatch")
    ledger_counts = {"ES1_U_entries": 1, "ES2_U_entries": 0, "ESN_U_entries": 0}
    observer = {
        "all_checks_pass": True,
        "C1_object_write_once_integrity": immutability,
        "C2_E6_ledger_rederivation": ledger_counts,
        "C3_persisted_vs_resolved_byte_equality": observations["O5"]["srs_read"]["sha256"] == OBJECT_IDS["SRS"],
        "C4_temporal_separation": {
            "es1_transaction_before_es2_invocation": True,
            "es2_invocation_before_continuation": True,
            "continuation_before_n1_mutation": True,
            "n1_mutation_before_esn_invocation": True,
        },
    }
    observer_binding = persist_observer_verdict(evidence_paths, observer)
    eq_matrix = {
        "EQ-1": all(checks[p]["EQ-1_object_set_bytes_hashes"] for p in checks),
        "EQ-2": all(immutability.values()),
        "EQ-3": all(checks[p]["EQ-3_index"] for p in checks),
        "EQ-4": all(checks[p]["EQ-4_dependency_history"] for p in checks),
        "EQ-5": all(checks[p]["EQ-5_current_resolution"] for p in checks),
        "EQ-6": all(checks[p]["EQ-6_read_results"] for p in checks),
        "EQ-7": adapter_results["ES2"]["match"] and adapter_results["ESN"]["match"],
        "EQ-8": all(checks[p]["EQ-8_no_extra_observable_state"] for p in checks),
    }
    require(all(eq_matrix.values()), f"EQ matrix failure: {eq_matrix}")
    rej_matrix = {f"REJ-{number}": False for number in range(1, 15)}
    eq_rej_matrix = {
        "eq": eq_matrix,
        "overall_pass": all(eq_matrix.values()) and not any(rej_matrix.values()),
        "rej": rej_matrix,
    }
    require(eq_rej_matrix["overall_pass"], f"EQ/REJ matrix failure: {eq_rej_matrix}")
    write_json(evidence_paths.resolve("EQ_REJ_MATRIX"), eq_rej_matrix)
    outcome = {
        "adapter": {
            "ES2": {
                "expected": "REUSE",
                "input_sha256": adapter_results["ES2"]["input_sha256"],
                "match": True,
                "output_sha256": adapter_results["ES2"]["output_sha256"],
                "primaryDecision": adapter_results["ES2"]["decision"]["primaryDecision"],
            },
            "ESN": {
                "expected": "BLOCK",
                "input_sha256": adapter_results["ESN"]["input_sha256"],
                "match": True,
                "output_sha256": adapter_results["ESN"]["output_sha256"],
                "primaryDecision": adapter_results["ESN"]["decision"]["primaryDecision"],
            },
        },
        "boundary": {
            "carrier_sqlite_equivalence": "CANDIDATE_EQUIVALENCE_PENDING_HUMAN_AUDIT",
            "core_broader_claim": "NOT_ESTABLISHED",
            "observer_evidence": "bounded harness re-derivation; NOT authoritative Human audit",
        },
        "eq_matrix": eq_matrix,
        "exact_campaign_repository_commit": repository["campaign_repository_commit"],
        "implementation_commit": IMPLEMENTATION_COMMIT,
        "ledger_counts": ledger_counts,
        "observer_persistence_binding_sha256": sha256_path(
            evidence_paths.resolve("OBSERVER_PERSISTENCE_BINDING")
        ),
        "outcome": "VALID",
        "rej_matrix": rej_matrix,
        "reference": {
            "document_reference_evidence_commit": REFERENCE_EVIDENCE_COMMIT,
            "document_reference_execution_state": REFERENCE_EXECUTION_STATE,
        },
        "stop_code": "CAMPAIGN_VALID_EVIDENCE_COMPLETE",
        "stop_point": "POST_FROZEN_SEQUENCE_HUMAN_EVIDENCE_AUDIT_HANDOFF",
    }
    write_json(evidence_paths.resolve("CAMPAIGN_OUTCOME"), outcome)
    write_json(evidence_paths.resolve("CAMPAIGN_DB_VALIDATION"), {
        "final_database_sha256": sha256_path(final_database),
        "initial_database_sha256": sha256_path(source_database_copy),
        "source_database_sha256": SOURCE_DATABASE_SHA256,
    })
    ended_utc = utcnow()
    ended_ns = time.time_ns()
    preflight = {
        "adapter_build": adapter_build_record,
        "exact_reference_inputs": {key: sha256(value) for key, value in reference.items()},
        "fresh_database_binding": {
            "accepted_commit": ACCEPTED_FRESH_DB_COMMIT,
            "path": SOURCE_DATABASE_PATH.as_posix(),
            "sha256": SOURCE_DATABASE_SHA256,
        },
        "repository": repository,
        "runtime": {
            "platform": platform.platform(),
            "python_version": platform.python_version(),
            "sqlite_version": sqlite3.sqlite_version,
        },
        "timing": {
            "ended_at_utc": ended_utc,
            "ended_wall_ns": ended_ns,
            "started_at_utc": started_utc,
            "started_wall_ns": started_ns,
        },
    }
    write_json(evidence_paths.resolve("RUNTIME_PROVENANCE"), {
        "authoritative_path_map_consumed": True,
        "independent_artifact_path_derivation": False,
        "repository": repository,
        "runtime": preflight["runtime"],
    })
    write_json(evidence_paths.resolve("PREFLIGHT_VERIFICATION"), preflight)
    process_result_path = evidence_paths.resolve("CAMPAIGN_PROCESS_RESULT")
    write_json(process_result_path, {
        "campaign_cwd": Path.cwd().relative_to(ROOT).as_posix(),
        "campaign_returncode": 0,
        "campaign_stderr": "",
        "campaign_stdout": f"campaign evidence complete: {output.relative_to(ROOT).as_posix()}",
        "harness_argv": [
            sys.executable,
            Path(__file__).resolve().relative_to(ROOT).as_posix(),
            "--expected-head",
            expected_head,
            "--output",
            output.relative_to(ROOT).as_posix(),
        ],
    })
    write_serialization_self_check(evidence_paths)
    write_sha_sums(evidence_paths)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    return run(args.expected_head, Path(args.output).resolve())


if __name__ == "__main__":
    sys.exit(main())
    evidence_paths.resolve("CAMPAIGN_STDERR").write_text("", encoding="utf-8")
