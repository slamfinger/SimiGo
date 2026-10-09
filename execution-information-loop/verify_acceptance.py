#!/usr/bin/env python3
"""Run and bind the final Execution-Information acceptance verification."""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "docs/02-evidence/execution-information-loop-vertical-slice-20261009"
PRIMARY_EVIDENCE = EVIDENCE / "REAL_PALACE_CONTRACT_BOUND_ATOMIC_E2E_RECORD.json"
PRIMARY_SHA256 = "6121384bd54ab0462cd1eae0525b23e23a2a8efba08f4b2fe01a40822eba2e66"
MANIFEST = EVIDENCE / "FINAL_ACCEPTANCE_REVIEW_MANIFEST_V4.json"
SEALED_SNAPSHOT = ROOT / "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"
SEALED_SNAPSHOT_SHA256 = "8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444"
REVIEW_TAG = "simigo-es-is-final-acceptance-20261009-v1"

TESTS = [
    "selftest.py",
    "carrier_selftest.py",
    "real_palace_selftest.py",
    "real_palace_source_change_selftest.py",
    "real_palace_integrated_selftest.py",
]

IMPLEMENTATION_PATHS = [
    "execution-information-loop/carrier_loop.py",
    "execution-information-loop/crash_worker.py",
    "execution-information-loop/loop.py",
    "execution-information-loop/real_palace_integrated_selftest.py",
    "execution-information-loop/real_palace_loop.py",
    "execution-information-loop/real_palace_selftest.py",
    "execution-information-loop/real_palace_source_change_selftest.py",
    "execution-information-loop/selftest.py",
    "execution-information-loop/carrier_selftest.py",
    "execution-information-loop/verify_acceptance.py",
]

REQUIRED_MANIFEST_FIELDS = [
    "schema_id",
    "status",
    "scope",
    "review_anchor",
    "review_commands",
    "acceptance_tests",
    "implementation_sha256",
    "primary_evidence",
    "acceptance_matrix",
    "non_claims",
]

REQUIRED_CHECKS = [
    "manifest_schema_current",
    "manifest_required_fields_present",
    "manifest_ready_for_human_review",
    "manifest_review_anchor_present",
    "manifest_test_set_complete",
    "manifest_implementation_file_set_complete",
    "manifest_hashes_valid_format",
    "implementation_hashes_match_manifest",
    "primary_evidence_sha256",
    "primary_evidence_result",
    "primary_evidence_all_checks",
    "primary_evidence_count_matches_manifest",
    "sealed_palace_snapshot_digest",
    "immutable_review_tag_exists",
    "immutable_review_tag_is_annotated",
    "immutable_review_tag_targets_head",
    "review_commit_worktree_clean",
    "all_five_selftests_executed",
    "all_five_selftests_explicit_pass",
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def is_sha256(value: object) -> bool:
    return (
        isinstance(value, str)
        and len(value) == 64
        and all(character in "0123456789abcdef" for character in value)
    )


def git_text(*arguments: str) -> str:
    completed = subprocess.run(
        ["git", *arguments],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        return ""
    return completed.stdout.strip()


def build_report(
    *,
    skip_tests: bool,
    manifest: dict | None,
    manifest_bytes: bytes,
    test_results: dict[str, str],
    git_results: dict[str, object],
) -> dict:
    manifest_checks: dict[str, bool] = {
        name: False for name in REQUIRED_CHECKS if name.startswith("manifest_")
    }
    implementation_hash_checks: dict[str, bool] = {
        path: False for path in IMPLEMENTATION_PATHS
    }

    if isinstance(manifest, dict):
        manifest_checks["manifest_schema_current"] = (
            manifest.get("schema_id") == "EINFO-FINAL-ACCEPTANCE-REVIEW-MANIFEST-V4"
        )
        manifest_checks["manifest_required_fields_present"] = all(
            field in manifest for field in REQUIRED_MANIFEST_FIELDS
        )
        manifest_checks["manifest_ready_for_human_review"] = (
            manifest.get("status") == "READY_FOR_HUMAN_REVIEW"
        )
        anchor = manifest.get("review_anchor")
        manifest_checks["manifest_review_anchor_present"] = (
            isinstance(anchor, dict)
            and anchor.get("kind") == "GIT_ANNOTATED_TAG"
            and anchor.get("name") == REVIEW_TAG
            and anchor.get("must_target_head") is True
        )
        manifest_checks["manifest_test_set_complete"] = (
            manifest.get("acceptance_tests") == TESTS
        )

        recorded_hashes = manifest.get("implementation_sha256")
        manifest_checks["manifest_implementation_file_set_complete"] = (
            isinstance(recorded_hashes, dict)
            and set(recorded_hashes) == set(IMPLEMENTATION_PATHS)
        )
        manifest_checks["manifest_hashes_valid_format"] = (
            isinstance(recorded_hashes, dict)
            and bool(recorded_hashes)
            and all(is_sha256(value) for value in recorded_hashes.values())
        )
        if isinstance(recorded_hashes, dict):
            implementation_hash_checks = {
                path: (
                    path in recorded_hashes
                    and is_sha256(recorded_hashes[path])
                    and (ROOT / path).is_file()
                    and sha256(ROOT / path) == recorded_hashes[path]
                )
                for path in IMPLEMENTATION_PATHS
            }

    try:
        evidence = json.loads(PRIMARY_EVIDENCE.read_text(encoding="utf-8"))
        primary_evidence_checks = evidence.get("checks", {})
    except (OSError, json.JSONDecodeError):
        evidence = {}
        primary_evidence_checks = {}

    expected_test_results = {
        name: ("NOT_EXECUTED" if skip_tests else "INVALID") for name in TESTS
    }
    all_tests_executed = (
        not skip_tests
        and set(test_results) == set(TESTS)
        and all(test_results[name] == "PASS" for name in TESTS)
    )

    checks = {
        **manifest_checks,
        "implementation_hashes_match_manifest": all(
            implementation_hash_checks.values()
        ),
        "primary_evidence_sha256": (
            PRIMARY_EVIDENCE.is_file()
            and sha256(PRIMARY_EVIDENCE) == PRIMARY_SHA256
        ),
        "primary_evidence_result": evidence.get("result") == "PASS",
        "primary_evidence_all_checks": bool(primary_evidence_checks)
        and all(primary_evidence_checks.values()),
        "primary_evidence_count_matches_manifest": (
            isinstance(manifest, dict)
            and isinstance(manifest.get("primary_evidence"), dict)
            and manifest["primary_evidence"].get("checks_total")
            == len(primary_evidence_checks)
        ),
        "sealed_palace_snapshot_digest": (
            SEALED_SNAPSHOT.is_file()
            and sha256(SEALED_SNAPSHOT) == SEALED_SNAPSHOT_SHA256
        ),
        "immutable_review_tag_exists": bool(git_results.get("tag_exists")),
        "immutable_review_tag_is_annotated": (
            git_results.get("tag_object_type") == "tag"
        ),
        "immutable_review_tag_targets_head": (
            git_results.get("tag_target") == git_results.get("head")
            and bool(git_results.get("head"))
        ),
        "review_commit_worktree_clean": (
            git_results.get("worktree_clean") is True
        ),
        "all_five_selftests_executed": all_tests_executed,
        "all_five_selftests_explicit_pass": all_tests_executed,
    }
    missing_checks = [name for name in REQUIRED_CHECKS if name not in checks]
    checks["verification_report_complete"] = not missing_checks

    if skip_tests:
        verdict = "NOT_ACCEPTED_VERIFICATION_INCOMPLETE"
    elif missing_checks or not all(checks.values()):
        verdict = "FAIL"
    else:
        verdict = "PASS"

    return {
        "schema_id": "EINFO-FINAL-ACCEPTANCE-VERIFIER-V2",
        "verdict": verdict,
        "result": verdict,
        "acceptance_pass": verdict == "PASS",
        "tests_executed": not skip_tests,
        "manifest_path": str(MANIFEST.relative_to(ROOT)),
        "manifest_sha256": hashlib.sha256(manifest_bytes).hexdigest(),
        "review_tag": REVIEW_TAG,
        "review_commit": git_results.get("head"),
        "review_tag_target": git_results.get("tag_target"),
        "primary_evidence_path": str(PRIMARY_EVIDENCE.relative_to(ROOT)),
        "primary_evidence_sha256": (
            sha256(PRIMARY_EVIDENCE) if PRIMARY_EVIDENCE.is_file() else None
        ),
        "sealed_palace_snapshot_sha256": (
            sha256(SEALED_SNAPSHOT) if SEALED_SNAPSHOT.is_file() else None
        ),
        "implementation_hash_checks": implementation_hash_checks,
        "git_checks": {
            "head": git_results.get("head"),
            "tag_target": git_results.get("tag_target"),
            "tag_object_type": git_results.get("tag_object_type"),
            "worktree_clean": git_results.get("worktree_clean"),
        },
        "tests": {
            name: test_results.get(name, expected_test_results[name])
            for name in TESTS
        },
        "required_checks": {
            name: checks.get(name, False) for name in REQUIRED_CHECKS
        },
        "missing_checks": missing_checks,
        "checks": checks,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--skip-tests",
        action="store_true",
        help="audit static bindings only; can never yield acceptance PASS",
    )
    args = parser.parse_args()

    manifest_bytes = MANIFEST.read_bytes() if MANIFEST.is_file() else b""
    try:
        manifest = json.loads(manifest_bytes)
    except json.JSONDecodeError:
        manifest = None

    test_results: dict[str, str] = {}
    if not args.skip_tests:
        for name in TESTS:
            completed = subprocess.run(
                [sys.executable, str(ROOT / "execution-information-loop" / name)],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            try:
                report = json.loads(completed.stdout)
                test_results[name] = report.get("result", "NO_RESULT")
            except json.JSONDecodeError:
                test_results[name] = f"INVALID_JSON/exit_{completed.returncode}"

    tag_target = git_text(
        "rev-parse", "--verify", "--quiet", f"refs/tags/{REVIEW_TAG}^{{commit}}"
    )
    head = git_text("rev-parse", "HEAD")
    tag_object_type = git_text("cat-file", "-t", f"refs/tags/{REVIEW_TAG}")
    status_output = git_text("status", "--porcelain", "--untracked-files=all")
    git_results = {
        "head": head,
        "tag_target": tag_target,
        "tag_object_type": tag_object_type,
        "tag_exists": bool(tag_target),
        "worktree_clean": status_output == "",
    }

    report = build_report(
        skip_tests=args.skip_tests,
        manifest=manifest,
        manifest_bytes=manifest_bytes,
        test_results=test_results,
        git_results=git_results,
    )
    print(json.dumps(report, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
