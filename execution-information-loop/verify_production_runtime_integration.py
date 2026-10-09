#!/usr/bin/env python3
"""Verify the V3 REV1 bounded SimiGo runtime / PALACE integration."""
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE_ROOT = ROOT / "simigo2-experimental"
BRIDGE = ROOT / "execution-information-loop/production_runtime_bridge.py"
MANIFEST = ROOT / (
    "docs/02-evidence/production-runtime-integration-20261009/"
    "PRODUCTION_RUNTIME_INTEGRATION_MANIFEST_V3_REV1.json"
)
PRIMARY_EVIDENCE = ROOT / (
    "docs/02-evidence/production-runtime-integration-20261009/"
    "PRODUCTION_RUNTIME_INTEGRATION_E2E_RECORD_V3_REV1.json"
)
SEALED_SNAPSHOT = ROOT / "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"

ACCEPTED_TAG = "simigo-es-is-final-acceptance-20261009-v1"
ACCEPTED_COMMIT = "bb09a55ef980ac4af3f1605ccf8de928abf6cc23"
REVISION_TAG = "simigo-production-integration-v3-rev1-review"
PRIMARY_EVIDENCE_SHA256 = "d87a3b021fa68037daac493df2749f337c74ec662698026e1d89a96e09918bb8"
SEALED_SNAPSHOT_SHA256 = "8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444"
EXPECTED_STALE_ITEMS = [
    "REAL-COLLECTION",
    "REAL-SEGMENT",
    "REAL-1",
    "REAL-2",
    "REAL-3",
    "REAL-4",
    "REAL-5",
    "REAL-6",
    "REAL-7",
]
REQUIRED_FILES = [
    "execution-information-loop/carrier_loop.py",
    "execution-information-loop/real_palace_loop.py",
    "execution-information-loop/production_runtime_bridge.py",
    "execution-information-loop/verify_production_runtime_integration.py",
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


def run_bridge(arguments: list[str]) -> dict:
    result = subprocess.run(
        [sys.executable, str(BRIDGE), *arguments],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError:
        value = {"ok": False, "error": result.stderr}
    value["_exit_code"] = result.returncode
    return value


def stale_preflight_probe() -> tuple[bool, dict]:
    with tempfile.TemporaryDirectory(prefix="simigo-v3rev1-verifier-") as temporary:
        database = str(Path(temporary) / "bridge.sqlite")
        initialized = run_bridge([
            "initialize",
            "--database", database,
            "--valid-until", "2020-01-01T00:00:00Z",
        ])
        response = run_bridge([
            "execute",
            "--database", database,
            "--advancement", "verifier-stale-probe",
            "--evaluated-at", "2026-10-09T00:00:00Z",
        ])
    result = response.get("result", {})
    actual_items = result.get("validity_failure_item_ids")
    passed = (
        initialized.get("ok") is True
        and response.get("ok") is True
        and response.get("_exit_code") == 0
        and result.get("state") == "BLOCKED_STALE_VALIDITY"
        and result.get("advanced") is False
        and actual_items == EXPECTED_STALE_ITEMS
        and len(actual_items or []) == len(set(actual_items or []))
    )
    return passed, {
        "state": result.get("state"),
        "validity_failure_item_ids": actual_items,
        "advanced": result.get("advanced"),
    }


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
        ["swift", "test", "--filter", "ProductionRuntimeInformationIntegrationTests"],
        cwd=PACKAGE_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    swift_output = swift_test.stdout + swift_test.stderr

    stale_passed, stale_probe = stale_preflight_probe()
    implementation_hashes = {
        path: sha256(ROOT / path) if (ROOT / path).is_file() else None
        for path in REQUIRED_FILES
    }
    recorded_hashes = manifest.get("implementation_sha256", {})
    head = git("rev-parse", "HEAD")
    accepted_target = git(
        "rev-parse", "--verify", "--quiet", f"refs/tags/{ACCEPTED_TAG}^{{commit}}"
    )
    revision_target = git(
        "rev-parse", "--verify", "--quiet", f"refs/tags/{REVISION_TAG}^{{commit}}"
    )
    revision_type = git("cat-file", "-t", f"refs/tags/{REVISION_TAG}")
    worktree_clean = git("status", "--porcelain", "--untracked-files=all") == ""

    checks = {
        "manifest_schema_current": manifest.get("schema_id") == "PRODUCTION-RUNTIME-INTEGRATION-MANIFEST-V3-REV1",
        "manifest_status_verified": manifest.get("status") == "VERIFIED",
        "manifest_implementation_file_set_complete": set(recorded_hashes) == set(REQUIRED_FILES),
        "manifest_hashes_valid": bool(recorded_hashes) and all(
            isinstance(value, str) and len(value) == 64
            for value in recorded_hashes.values()
        ),
        "implementation_hashes_match": implementation_hashes == recorded_hashes,
        "primary_evidence_sha256": (
            PRIMARY_EVIDENCE.is_file()
            and sha256(PRIMARY_EVIDENCE) == PRIMARY_EVIDENCE_SHA256
        ),
        "primary_evidence_result": evidence.get("result") == "PASS",
        "primary_evidence_stale_items_exact": evidence.get(
            "stale_validity_gate", {}
        ).get("validity_failure_item_ids") == EXPECTED_STALE_ITEMS,
        "stale_preflight_exact_items": stale_passed,
        "accepted_review_tag_bound": accepted_target == ACCEPTED_COMMIT,
        "revision_tag_exists": bool(revision_target),
        "revision_tag_is_annotated": revision_type == "tag",
        "revision_tag_targets_head": revision_target == head,
        "review_commit_worktree_clean": worktree_clean,
        "sealed_palace_snapshot_digest": (
            SEALED_SNAPSHOT.is_file() and sha256(SEALED_SNAPSHOT) == SEALED_SNAPSHOT_SHA256
        ),
        "swift_integration_tests_pass": (
            swift_test.returncode == 0
            and "Test Suite 'ProductionRuntimeInformationIntegrationTests' passed" in swift_output
            and "Executed 3 tests, with 0 failures" in swift_output
        ),
    }
    report = {
        "schema_id": "PRODUCTION-RUNTIME-INTEGRATION-VERIFIER-V2",
        "result": "PASS" if all(checks.values()) else "FAIL",
        "manifest": str(MANIFEST.relative_to(ROOT)),
        "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "primary_evidence": str(PRIMARY_EVIDENCE.relative_to(ROOT)),
        "primary_evidence_sha256": (
            sha256(PRIMARY_EVIDENCE) if PRIMARY_EVIDENCE.is_file() else None
        ),
        "expected_primary_evidence_sha256": PRIMARY_EVIDENCE_SHA256,
        "review_commit": head,
        "review_tag": REVISION_TAG,
        "review_tag_target": revision_target,
        "accepted_review_commit": ACCEPTED_COMMIT,
        "accepted_review_tag": ACCEPTED_TAG,
        "implementation_sha256": implementation_hashes,
        "sealed_palace_snapshot_sha256": sha256(SEALED_SNAPSHOT),
        "stale_preflight": stale_probe,
        "swift_test_exit_code": swift_test.returncode,
        "checks": checks,
    }
    print(json.dumps(report, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
