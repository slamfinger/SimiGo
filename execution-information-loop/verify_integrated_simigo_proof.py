#!/usr/bin/env python3
"""Verify Integrated SimiGo proof plus production readiness preparation."""
from __future__ import annotations

import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE_ROOT = ROOT / "simigo2-experimental"
MANIFEST = ROOT / (
    "docs/02-evidence/integrated-simigo-proof-20261009/"
    "INTEGRATED_SIMIGO_PROOF_PRODUCTION_READINESS_MANIFEST_V2.json"
)
PRIMARY_EVIDENCE = ROOT / (
    "docs/02-evidence/integrated-simigo-proof-20261009/"
    "INTEGRATED_SIMIGO_PROOF_PRODUCTION_READINESS_E2E_RECORD_V2.json"
)
SEALED_SNAPSHOT = ROOT / "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"
SEALED_SNAPSHOT_SHA256 = "8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444"
ACCEPTED_COMMIT = "2a3f1372946b53e47114ebaba6efb6264812d44f"
ACCEPTED_TAG = "simigo-production-integration-v3-rev2-accepted"
ACCEPTANCE_COMMIT = "a6dc75eaa94e80d9c66fccf7baadabf8a018a9ba"
REQUIRED_FILES = [
    "execution-information-loop/carrier_loop.py",
    "execution-information-loop/real_palace_loop.py",
    "execution-information-loop/production_runtime_bridge.py",
    "simigo2-experimental/Sources/SimiGo2Experimental/ProductionRuntimeInformationIntegration.swift",
    "simigo2-experimental/Tests/SimiGo2ExperimentalTests/IntegratedSimigoProofE2ETests.swift",
    "simigo2-experimental/Tests/SimiGo2ExperimentalTests/ProductionReadinessDeploymentPreparationTests.swift",
    "execution-information-loop/verify_integrated_simigo_proof.py",
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
        ["swift", "test", "--filter", "IntegratedSimigoProofE2ETests|ProductionRuntimeInformationIntegrationTests|ProductionReadinessDeploymentPreparationTests"],
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
    accepted_target = git(
        "rev-parse", "--verify", "--quiet", f"refs/tags/{ACCEPTED_TAG}^{{commit}}"
    )
    review_ancestor = subprocess.run(
        ["git", "merge-base", "--is-ancestor", ACCEPTED_COMMIT, ACCEPTANCE_COMMIT],
        cwd=ROOT,
        check=False,
    ).returncode == 0

    checks = {
        "manifest_schema_current": manifest.get("schema_id") == "INTEGRATED-SIMIGO-PROOF-PRODUCTION-READINESS-MANIFEST-V2",
        "manifest_status_verified": manifest.get("status") == "VERIFIED",
        "manifest_file_set_complete": set(recorded_hashes) == set(REQUIRED_FILES),
        "manifest_hashes_valid": bool(recorded_hashes) and all(
            isinstance(value, str) and len(value) == 64
            for value in recorded_hashes.values()
        ),
        "implementation_hashes_match": implementation_hashes == recorded_hashes,
        "primary_evidence_sha256": (
            PRIMARY_EVIDENCE.is_file()
            and sha256(PRIMARY_EVIDENCE) == manifest.get("primary_evidence", {}).get("sha256")
        ),
        "primary_evidence_result": evidence.get("result") == "PASS",
        "primary_evidence_runtime_authority": evidence.get("runtime_authority", {}).get("coordinator") == "ExecutionContinuityCoordinator",
        "primary_evidence_no_vector_fulltext": evidence.get("information_path", {}).get("vector_or_fulltext_access") is False,
        "primary_evidence_no_model_cloud": evidence.get("information_path", {}).get("model_or_cloud_access") is False,
        "primary_evidence_all_objects_verify": evidence.get("verification", {}).get("carrier_all_objects_verify") is True,
        "failure_safety_complete": all(evidence.get("failure_safety", {}).values()),
        "production_launch_policy_bound": evidence.get("production_readiness", {}).get("validity_policy_explicit") is True,
        "production_launch_no_development_layout": evidence.get("production_readiness", {}).get("development_build_layout_required") is False,
        "production_startup_failure_fail_closed": evidence.get("production_readiness", {}).get("missing_bridge_startup_fail_closed") is True,
        "production_diagnostics_operable": evidence.get("production_readiness", {}).get("diagnostics_operable") is True,
        "production_append_only_rollback_operable": evidence.get("production_readiness", {}).get("append_only_rollback_operable") is True,
        "accepted_integration_commit_bound": accepted_target == ACCEPTANCE_COMMIT and review_ancestor,
        "sealed_palace_snapshot_digest": (
            SEALED_SNAPSHOT.is_file() and sha256(SEALED_SNAPSHOT) == SEALED_SNAPSHOT_SHA256
        ),
        "swift_integration_and_readiness_tests_pass": (
            swift_test.returncode == 0
            and "Test Suite 'IntegratedSimigoProofE2ETests' passed" in swift_output
            and "Test Suite 'ProductionRuntimeInformationIntegrationTests' passed" in swift_output
            and "Test Suite 'ProductionReadinessDeploymentPreparationTests' passed" in swift_output
            and "Executed 8 tests, with 0 failures" in swift_output
        ),
    }
    report = {
        "schema_id": "INTEGRATED-SIMIGO-PROOF-PRODUCTION-READINESS-VERIFIER-V2",
        "result": "PASS" if all(checks.values()) else "FAIL",
        "manifest": str(MANIFEST.relative_to(ROOT)),
        "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "primary_evidence": str(PRIMARY_EVIDENCE.relative_to(ROOT)),
        "primary_evidence_sha256": sha256(PRIMARY_EVIDENCE) if PRIMARY_EVIDENCE.is_file() else None,
        "accepted_review_commit": ACCEPTED_COMMIT,
        "accepted_review_tag": ACCEPTED_TAG,
        "acceptance_commit": ACCEPTANCE_COMMIT,
        "implementation_sha256": implementation_hashes,
        "sealed_palace_snapshot_sha256": sha256(SEALED_SNAPSHOT),
        "swift_test_exit_code": swift_test.returncode,
        "checks": checks,
    }
    print(json.dumps(report, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
