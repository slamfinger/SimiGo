#!/usr/bin/env python3
"""Verify the authorized bounded SimiGo runtime / PALACE integration."""
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAB_ROOT = ROOT
PACKAGE_ROOT = ROOT / "simigo2-experimental"
MANIFEST = ROOT / (
    "docs/02-evidence/production-runtime-integration-20261009/"
    "PRODUCTION_RUNTIME_INTEGRATION_MANIFEST_V2.json"
)
ACCEPTED_TAG = "simigo-es-is-final-acceptance-20261009-v1"
ACCEPTED_COMMIT = "bb09a55ef980ac4af3f1605ccf8de928abf6cc23"
SEALED_SNAPSHOT = ROOT / "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"
SEALED_SHA256 = "8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444"
REQUIRED_FILES = [
    "execution-information-loop/carrier_loop.py",
    "execution-information-loop/real_palace_loop.py",
    "execution-information-loop/production_runtime_bridge.py",
    "simigo2-experimental/Sources/SimiGo2Experimental/ProductionRuntimeInformationIntegration.swift",
    "simigo2-experimental/Tests/SimiGo2ExperimentalTests/ProductionRuntimeInformationIntegrationTests.swift",
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

    swift_test = subprocess.run(
        [
            "swift", "test",
            "--filter", "ProductionRuntimeInformationIntegrationTests",
        ],
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

    checks = {
        "manifest_schema_current": manifest.get("schema_id") == "PRODUCTION-RUNTIME-INTEGRATION-MANIFEST-V2",
        "manifest_status_verified": manifest.get("status") == "VERIFIED",
        "manifest_file_set_complete": (
            set(recorded_hashes) == set(REQUIRED_FILES)
        ),
        "manifest_hashes_valid": bool(recorded_hashes) and all(
            isinstance(value, str) and len(value) == 64
            for value in recorded_hashes.values()
        ),
        "implementation_hashes_match": implementation_hashes == recorded_hashes,
        "accepted_review_tag_present": bool(
            git("rev-parse", "--verify", "--quiet", f"refs/tags/{ACCEPTED_TAG}^{{commit}}")
        ),
        "accepted_review_commit_bound": (
            git("rev-parse", "--verify", "--quiet", f"refs/tags/{ACCEPTED_TAG}^{{commit}}")
            == ACCEPTED_COMMIT
        ),
        "sealed_palace_snapshot_digest": (
            SEALED_SNAPSHOT.is_file() and sha256(SEALED_SNAPSHOT) == SEALED_SHA256
        ),
        "swift_integration_tests_pass": (
            swift_test.returncode == 0
            and "Test Suite 'ProductionRuntimeInformationIntegrationTests' passed" in swift_output
            and "Executed 2 tests, with 0 failures" in swift_output
        ),
    }
    report = {
        "schema_id": "PRODUCTION-RUNTIME-INTEGRATION-VERIFIER-V1",
        "verifier_binding": "CURRENT_REVIEW_COMMIT",
        "result": "PASS" if all(checks.values()) else "FAIL",
        "manifest": str(MANIFEST.relative_to(ROOT)),
        "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "accepted_review_commit": ACCEPTED_COMMIT,
        "accepted_review_tag": ACCEPTED_TAG,
        "implementation_sha256": implementation_hashes,
        "sealed_palace_snapshot_sha256": sha256(SEALED_SNAPSHOT),
        "swift_test_exit_code": swift_test.returncode,
        "checks": checks,
    }
    print(json.dumps(report, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
