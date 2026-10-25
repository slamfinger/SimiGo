#!/usr/bin/env python3
"""Targeted regression guard for the MINIMAL-PIR-EXP-001 EV-P08 recorder."""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
RUNNER = Path(__file__).with_name("minimal_pir_experiment.py")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check(report: list, name: str, passed: bool, details: dict) -> None:
    report.append({"name": name, "pass": passed, "details": details})
    if not passed:
        print(f"FAIL {name}: {details}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    report: list[dict] = []
    source = RUNNER.read_text(encoding="utf-8")
    tree = ast.parse(source)

    write_text_calls = []
    write_bytes_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            target = ast.unparse(node.func.value)
            if target == "observations_path":
                if node.func.attr == "write_text":
                    write_text_calls.append(ast.unparse(node))
                if node.func.attr == "write_bytes":
                    write_bytes_calls.append(ast.unparse(node))
    check(report, "negative_bytes_to_text_guard", not write_text_calls, {
        "observations_path_write_text_calls": write_text_calls,
    })
    check(report, "positive_bytes_to_bytes_guard", len(write_bytes_calls) == 1, {
        "observations_path_write_bytes_calls": write_bytes_calls,
    })

    with tempfile.TemporaryDirectory(prefix="pir-evp08-regression-") as directory:
        path = Path(directory) / "EV-P08.jsonl"
        payload = (
            b'{"stable_object_id":"a","verdict":"FRESH_WITHIN_WINDOW"}\n'
            b'{"stable_object_id":"b","verdict":"PHYSICALLY_DELETED"}\n'
        )
        negative_rejected = False
        try:
            path.write_text(payload)
        except TypeError:
            negative_rejected = True
        if path.exists():
            raise RuntimeError("bytes-to-text negative guard created an artifact")
        path.write_bytes(payload)
        persisted = path.read_bytes()
        parsed = [json.loads(line) for line in persisted.splitlines()]
        positive_pass = persisted == payload and parsed == [
            {"stable_object_id": "a", "verdict": "FRESH_WITHIN_WINDOW"},
            {"stable_object_id": "b", "verdict": "PHYSICALLY_DELETED"},
        ]
        check(report, "synthetic_bytes_persistence_reread_parse", positive_pass, {
            "byte_length": len(persisted),
            "physical_lines": len(persisted.splitlines()),
            "parsed_records": len(parsed),
        })

    entry_pass = (
        "def execute_fixture" in source
        and "EV-P08_physical_reconciliation_observations.jsonl" in source
        and "MINIMAL-PIR-EXP-001" in source
    )
    check(report, "fresh_experiment_entry_validation", entry_pass, {
        "runner": str(RUNNER),
        "entry_function_present": "def execute_fixture" in source,
        "ev_p08_destination_present": "EV-P08_physical_reconciliation_observations.jsonl" in source,
    })

    result = {
        "request": "PIR Experiment Recorder Correction + Validation Request v2.6",
        "runner": str(RUNNER),
        "runner_sha256": sha256(RUNNER),
        "checks": report,
        "all_pass": all(item["pass"] for item in report),
        "decision": "RECORDER_CORRECTION_VALIDATION_PASS",
        "experiment_execution_authorized": False,
        "exp_002_authorized": False,
        "is_mutations": 0,
        "fixture_mutations": 0,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True,
                                     ensure_ascii=False, allow_nan=False) + "\n",
                           encoding="utf-8")
    print(f"RECORDER_CORRECTION={result['decision']}")
    print(f"CHECKS={sum(x['pass'] for x in report)}/{len(report)}")
    print(f"OUTPUT={args.output}")
    return 0 if result["all_pass"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
