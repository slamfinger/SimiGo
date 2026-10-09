#!/usr/bin/env python3
"""Verify the Controlled Production Pilot v1 evidence package."""
from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE_ROOT = ROOT / "simigo2-experimental"
MANIFEST = ROOT / (
    "docs/02-evidence/controlled-production-pilot-20261009/"
    "CONTROLLED_PRODUCTION_PILOT_V1_MANIFEST.json"
)
PRIMARY_EVIDENCE = ROOT / (
    "docs/02-evidence/controlled-production-pilot-20261009/"
    "CONTROLLED_PRODUCTION_PILOT_V1_E2E_RECORD.json"
)
SEALED_SNAPSHOT = ROOT / "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"
SEALED_SNAPSHOT_SHA256 = "8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444"
BASE_COMMIT = "6259ffd9de7a4356d1da2e90dfc4b7db473644e0"
PREREQUISITE_TAG = "production-readiness-v1-pass"
ACCEPTED_PROOF_COMMIT = "6a36c928c50021ec4c754eb4c8006306125bc35b"
ACCEPTED_PROOF_TAG = "integrated-simigo-proof-v1-validated"
REQUIRED_FILES = [
    "execution-information-loop/carrier_loop.py",
    "execution-information-loop/real_palace_loop.py",
    "execution-information-loop/production_runtime_bridge.py",
    "simigo2-experimental/Sources/SimiGo2Experimental/ProductionRuntimeInformationIntegration.swift",
    "simigo2-experimental/Tests/SimiGo2ExperimentalTests/ControlledProductionPilotV1E2ETests.swift",
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*arguments: str) -> str:
    return subprocess.run(
        ["git", *arguments],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    ).stdout.strip()


def main() -> int:
    manifest_bytes = MANIFEST.read_bytes() if MANIFEST.is_file() else b"{}"
    try:
        manifest = json.loads(manifest_bytes)
    except json.JSONDecodeError:
        manifest = {}
    try:
        evidence = json.loads(PRIMARY_EVIDENCE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        evidence = {}

    swift_test = subprocess.run(
        ["swift", "test", "--filter", "ControlledProductionPilotV1E2ETests"],
        cwd=PACKAGE_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    swift_output = swift_test.stdout + swift_test.stderr

    implementation_hashes = {
        path: sha256(ROOT / path) if (ROOT / path).is_file() else None
        for path in REQUIRED_FILES
    }
    recorded_hashes = manifest.get("implementation_sha256", {})
    readiness_target = git(
        "rev-parse", "--verify", "--quiet",
        f"refs/tags/{PREREQUISITE_TAG}^{{commit}}",
    )
    proof_target = git(
        "rev-parse", "--verify", "--quiet",
        f"refs/tags/{ACCEPTED_PROOF_TAG}^{{commit}}",
    )

    checks = {
        "manifest_schema_current": manifest.get("schema_id") == "CONTROLLED-PRODUCTION-PILOT-V1-MANIFEST",
        "manifest_status_verified": manifest.get("status") == "VERIFIED",
        "manifest_file_set_complete": set(recorded_hashes) == set(REQUIRED_FILES),
        "manifest_hashes_valid": bool(recorded_hashes) and all(
            isinstance(value, str) and len(value) == 64
            for value in recorded_hashes.values()
        ),
        "implementation_hashes_match": implementation_hashes == recorded_hashes,
        "primary_evidence_schema_current": evidence.get("schema_id") == "CONTROLLED-PRODUCTION-PILOT-V1-E2E-RECORD",
        "primary_evidence_result": evidence.get("result") == "PASS",
        "primary_evidence_status": evidence.get("status") == "PASS",
        "primary_evidence_isolated_bundle": evidence.get("environment", {}).get("isolated_palace_snapshot_copy") is True,
        "primary_evidence_no_development_layout": evidence.get("environment", {}).get("development_build_layout_required") is False,
        "primary_evidence_validity_policy_explicit": evidence.get("validity_policy", {}).get("policy_source") == "CONTROLLED_PRODUCTION_PILOT_V1",
        "startup_and_initial_compute_pass": evidence.get("phases", {}).get("startup_and_initial_compute", {}).get("result") == "PASS",
        "restart_and_recovery_pass": evidence.get("phases", {}).get("restart_and_recovery", {}).get("result") == "PASS",
        "dependency_invalidation_propagation_pass": evidence.get("phases", {}).get("dependency_invalidation_propagation", {}).get("result") == "PASS",
        "source_version_selective_recompute_pass": evidence.get("phases", {}).get("source_version_selective_recompute", {}).get("result") == "PASS",
        "fault_observability_and_rollback_pass": evidence.get("phases", {}).get("fault_observability_and_rollback", {}).get("result") == "PASS",
        "stale_validity_fail_closed_pass": evidence.get("phases", {}).get("stale_validity_fail_closed", {}).get("result") == "PASS",
        "missing_information_fail_closed_pass": evidence.get("phases", {}).get("missing_information_fail_closed", {}).get("result") == "PASS",
        "malformed_observation_time_fail_closed_pass": evidence.get("phases", {}).get("malformed_observation_time_fail_closed", {}).get("result") == "PASS",
        "corrupt_persisted_lifecycle_fail_closed_pass": evidence.get("phases", {}).get("corrupt_persisted_lifecycle_fail_closed", {}).get("result") == "PASS",
        "base_commit_bound": BASE_COMMIT in (git("rev-parse", "HEAD"), readiness_target, proof_target),
        "prerequisite_readiness_tag_bound": readiness_target == BASE_COMMIT,
        "accepted_isolated_proof_bound": proof_target == ACCEPTED_PROOF_COMMIT,
        "sealed_palace_snapshot_digest": (
            SEALED_SNAPSHOT.is_file()
            and sha256(SEALED_SNAPSHOT) == SEALED_SNAPSHOT_SHA256
        ),
        "swift_pilot_tests_pass": (
            swift_test.returncode == 0
            and "Test Suite 'ControlledProductionPilotV1E2ETests' passed" in swift_output
            and "Executed 1 test, with 0 failures" in swift_output
        ),
    }
    report = {
        "schema_id": "CONTROLLED-PRODUCTION-PILOT-V1-VERIFIER",
        "result": "PASS" if all(checks.values()) else "FAIL",
        "manifest": str(MANIFEST.relative_to(ROOT)),
        "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "primary_evidence": str(PRIMARY_EVIDENCE.relative_to(ROOT)),
        "primary_evidence_sha256": sha256(PRIMARY_EVIDENCE) if PRIMARY_EVIDENCE.is_file() else None,
        "base_commit": BASE_COMMIT,
        "prerequisite_tag": PREREQUISITE_TAG,
        "accepted_isolated_proof_commit": ACCEPTED_PROOF_COMMIT,
        "implementation_sha256": implementation_hashes,
        "sealed_palace_snapshot_sha256": sha256(SEALED_SNAPSHOT),
        "swift_test_exit_code": swift_test.returncode,
        "checks": checks,
    }
    print(json.dumps(report, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
