#!/usr/bin/env python3
"""Run the five acceptance selftests and verify primary evidence integrity."""
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
TESTS = [
    "selftest.py",
    "carrier_selftest.py",
    "real_palace_selftest.py",
    "real_palace_source_change_selftest.py",
    "real_palace_integrated_selftest.py",
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--skip-tests", action="store_true")
    args = parser.parse_args()

    evidence_hash = sha256(PRIMARY_EVIDENCE)
    evidence = json.loads(PRIMARY_EVIDENCE.read_text(encoding="utf-8"))
    results = {}
    if not args.skip_tests:
        for name in TESTS:
            completed = subprocess.run(
                [sys.executable, str(Path(__file__).with_name(name))],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=False,
            )
            try:
                report = json.loads(completed.stdout)
                results[name] = report.get("result")
            except json.JSONDecodeError:
                results[name] = f"INVALID_JSON/{completed.returncode}"

    checks = {
        "primary_evidence_sha256": evidence_hash == PRIMARY_SHA256,
        "primary_evidence_result": evidence.get("result") == "PASS",
        "primary_evidence_all_checks": all(evidence.get("checks", {}).values()),
        **{name: result == "PASS" for name, result in results.items()},
    }
    report = {
        "schema_id": "EINFO-FINAL-ACCEPTANCE-VERIFIER-V1",
        "primary_evidence_sha256": evidence_hash,
        "tests": results,
        "checks": checks,
        "result": "PASS" if all(checks.values()) else "FAIL",
    }
    print(json.dumps(report, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
    return 0 if report["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
