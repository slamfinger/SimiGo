#!/usr/bin/env python3
"""Create the immutable Run Manifest for the authorized single run."""
from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RUN_ROOT = ROOT / "integrated-es-palace/non-d002-validation-v1"
FIXTURE_MANIFEST = ROOT / "integrated-es-palace/integration-fixture-v1/FIXTURE_PACKAGE_MANIFEST.json"
FIXTURE_CHECKSUMS = ROOT / "integrated-es-palace/integration-fixture-v1/preparation/EVIDENCE_SHA256SUMS"
ISOLATION_PROOF = ROOT / "integrated-es-palace/integration-fixture-v1/preparation/ISOLATION_PROOF.json"
MISSING_ITEMS = ROOT / "integrated-es-palace/integration-fixture-v1/preparation/MISSING_ITEMS.json"
SELF_CHECK = ROOT / "integrated-es-palace/integration-fixture-v1/preparation/PREPARATION_SELF_CHECK.json"
SNAPSHOT = ROOT / "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"
SEALED_SNAPSHOT_SHA256 = (
    "8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444"
)
CASES = [
    "P-LAWFUL", "P-SETTLED", "P-BLOCKED",
    "N-MISSING", "N-STALE", "N-AMBIGUOUS", "N-ILLEGAL",
]
EXPECTED = {
    "P-LAWFUL": ("CONTINUE", "SETTLED_CONTINUATION", "LAWFUL_CURRENT_CONTINUATION"),
    "P-SETTLED": ("REUSE", "SETTLED_CONTINUATION", "REUSE_PREDICATE_COMPLETE"),
    "P-BLOCKED": ("BLOCK", "BLOCKED_LAWFUL_CONTINUATION", "REGISTERED_BLOCKING_CONDITION"),
    "N-MISSING": ("BLOCK", "BLOCKED_DEFECT", "MANDATORY_OBJECT_UNRESOLVABLE"),
    "N-STALE": ("BLOCK", "BLOCKED_DEFECT", "MANDATORY_EVIDENCE_SUPERSEDED"),
    "N-AMBIGUOUS": ("BLOCK", "BLOCKED_DEFECT", "CONFLICTING_VALID_POINTERS"),
    "N-ILLEGAL": ("BLOCK", "BLOCKED_DEFECT", "REGISTERED_BOUNDARY_VIOLATION_PROVEN"),
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def git(*arguments: str) -> str:
    return subprocess.check_output(["git", "-C", str(ROOT), *arguments], text=True).strip()


def main() -> int:
    destination = RUN_ROOT / "RUN_MANIFEST_INSTANCE.json"
    if destination.exists() or destination.is_symlink():
        raise FileExistsError(destination)
    fixture = json.loads(FIXTURE_MANIFEST.read_text())
    require = lambda condition, message: (_ for _ in ()).throw(RuntimeError(message)) if not condition else None
    require(fixture["result"] == "PASS", "fixture package did not pass")
    require(fixture["experiment_executed"] is False, "fixture already executed")
    require(sha256(SNAPSHOT) == SEALED_SNAPSHOT_SHA256, "sealed snapshot drift")
    cases = []
    seen = set()
    for record in fixture["cases"]:
        case = record["case_id"]
        require(case in CASES and case not in seen, "fixture case set drift")
        seen.add(case)
        decision, continuation_class, precedence_reason = EXPECTED[case]
        cases.append({
            "case_id": case,
            "opaque_locator": f"d002://snapshot/embedding/{record['source_internal_id']}",
            "fixture_manifest": f"integrated-es-palace/integration-fixture-v1/fixtures/{case}/fixture-manifest.json",
            "fixture_manifest_sha256": record["manifest_sha256"],
            "expected": {
                "decision": decision,
                "continuation_class": continuation_class,
                "precedence_reason": precedence_reason,
                "no_fallback_guess": True,
                "no_partial_continuation": True,
                "no_silent_recompute": True,
                "no_stale_success": True,
            },
        })
    require(sorted(seen) == sorted(CASES), "fixture case coverage drift")
    manifest = {
        "schema_id": "NON-D002-INTEGRATED-VALIDATION-RUN-MANIFEST-V1",
        "manifest_instance_id": str(uuid.uuid5(
            uuid.NAMESPACE_URL,
            "INTEGRATED-ES-PALACE-NON-D002-VALIDATION-V1:" + sha256(FIXTURE_MANIFEST),
        )).upper(),
        "authorization": {
            "status": "ACCEPT",
            "request": "INTEGRATED-ES-PALACE-NON-D002-VALIDATION-AUTHORIZATION-REQUEST-V1.0",
            "request_sha256": "82a2f5cf030bfd5acb61a3f37866e28e70ca9eb8c206bffb599e3f2d692fd5f9",
            "authorized_runs": 1,
            "automatic_rerun_or_repair": False,
        },
        "bindings": {
            "canonical_base": git("rev-parse", "HEAD"),
            "branch": git("branch", "--show-current"),
            "head_origin_equal": git("rev-parse", "HEAD") == git("rev-parse", "origin/main"),
            "frozen_design": "INTEGRATED-ES-PALACE-VALIDATION-DESIGN-PACKAGE-001-V1.1",
            "fixture_package": fixture["fixture_package_id"],
            "fixture_manifest": "integrated-es-palace/integration-fixture-v1/FIXTURE_PACKAGE_MANIFEST.json",
            "fixture_manifest_sha256": sha256(FIXTURE_MANIFEST),
            "fixture_checksum_list": "integrated-es-palace/integration-fixture-v1/preparation/EVIDENCE_SHA256SUMS",
            "fixture_checksum_list_sha256": sha256(FIXTURE_CHECKSUMS),
            "isolation_proof_sha256": sha256(ISOLATION_PROOF),
            "missing_items_sha256": sha256(MISSING_ITEMS),
            "preparation_self_check_sha256": sha256(SELF_CHECK),
            "sealed_palace_snapshot": "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite",
            "sealed_palace_snapshot_sha256": SEALED_SNAPSHOT_SHA256,
            "pilot_v5_sqlite_busy_revision": "ACCEPT / CLOSED",
        },
        "runner": {
            "path": "integrated-es-palace/non-d002-validation-v1/runner.py",
            "sha256": sha256(RUN_ROOT / "runner.py"),
            "language": "Python 3",
            "third_party_dependencies": [],
            "network_access": False,
            "model_participation": False,
        },
        "cases": cases,
        "execution": {
            "mode": "ONE_FRESH_ENTRY_PASS",
            "executed": False,
            "rerun_authorized": False,
            "repair_authorized": False,
            "terminal_states": ["VALIDATION_PASS", "VALIDATION_FAIL"],
        },
        "evidence_root": "integrated-es-palace/non-d002-validation-v1/evidence",
        "approved_evidence_objects": [
            "FRESH_ENTRY_PREFLIGHT.json",
            "SOURCE_SNAPSHOT_BINDING.json",
            "PRIMITIVE_INVENTORY.json",
            "TYPED_MAPPING_RECORD.json",
            "CASE_COMPARISON_RECORD.json",
            "CARRIER_LIFECYCLE_RECORD.json",
            "FORBIDDEN_CHANNEL_DENIAL_RECORD.json",
            "VALIDATION_RECORD.json",
            "EVIDENCE_SHA256SUMS",
        ],
        "boundaries": {
            "canonical_palace_mutation": False,
            "canonical_information_space_mutation": False,
            "d002_rerun_or_repair": False,
            "production_deployment": False,
            "network_access": False,
            "model_authority": False,
        },
        "stop_rule": "STOP_AFTER_ONE_RUN_WITH_VALIDATION_PASS_OR_VALIDATION_FAIL",
    }
    RUN_ROOT.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(canonical(manifest) + b"\n")
    temporary.replace(destination)
    print(destination)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
