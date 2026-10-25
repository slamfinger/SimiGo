#!/usr/bin/env python3
"""G1.1 gate — the frozen reference-calculator vectors must pass in Swift.

Runs the frozen contract's 9 success vectors, 6 error vectors and 1
canonicalization vector through the compiled Swift executable, and requires:

  * the result object to match the frozen expectation;
  * the frozen input / dependency / result SHA-256 values to appear verbatim in
    the Swift-authored event log;
  * exactly one `started` and one terminal event per invocation, each carrying
    the pinned executable hash;
  * a build identity record (command, source revision, executable SHA-256).

This gate does not touch the Carrier and says nothing about model or KV behaviour.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
PACKAGE_DIR = HERE / "g1-swift-reference-calculator"
DEFAULT_BINARY = PACKAGE_DIR / ".build" / "release" / "SwiftReferenceCalculator"


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def run(command: list[str], cwd: Path) -> str:
    completed = subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    if completed.returncode != 0:
        raise SystemExit(
            f"command failed ({completed.returncode}): {' '.join(command)}\n"
            f"{completed.stderr.decode('utf-8', errors='replace')}"
        )
    return completed.stdout.decode("utf-8").strip()


def build_identity(repo_root: Path, binary: Path, sha: str) -> dict:
    swift_version = run(["swift", "--version"], repo_root).splitlines()[0]
    revision = run(["git", "rev-parse", "HEAD"], repo_root)
    dirty = run(["git", "status", "--porcelain"], repo_root)
    return {
        "build_command": f"swift build -c release --package-path {PACKAGE_DIR.relative_to(repo_root)}",
        "build_id": "swift-reference-calculator/1.0.0+g1",
        "swift_version": swift_version,
        "source_revision": revision,
        "source_tree_clean_at_build": dirty == "",
        "executable_path": str(binary.relative_to(repo_root)),
        "executable_sha256": sha,
        "executable_bytes": binary.stat().st_size,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--contract", type=Path, default=HERE / "calculator-contract-freeze.jsonl")
    parser.add_argument("--binary", type=Path, default=DEFAULT_BINARY)
    parser.add_argument("--build", action="store_true", help="build the package before running")
    parser.add_argument("--report", type=Path, help="write the JSON report to this path")
    parser.add_argument("--events-out", type=Path, help="preserve the Swift event log at this path")
    args = parser.parse_args()

    repo_root = HERE
    while repo_root != repo_root.parent and not (
        repo_root / "execution-information-loop" / "carrier_loop.py"
    ).is_file():
        repo_root = repo_root.parent
    if not (repo_root / "execution-information-loop" / "carrier_loop.py").is_file():
        raise SystemExit("cannot locate the SimiGo-Lab repository root")
    if args.build:
        run(["swift", "build", "-c", "release", "--package-path", str(PACKAGE_DIR)], repo_root)
    binary = args.binary.resolve()
    if not binary.is_file():
        raise SystemExit(f"missing executable {binary}; build it with --build")

    refcalc = load_module(HERE / "calc_refcalculator_entry_test.py", "simigo_refcalc")
    adapter_module = load_module(HERE / "swift_reference_calculator_adapter.py", "simigo_swift_adapter")

    header, records = refcalc.load_jsonl_contract(args.contract.resolve())
    refcalc.validate_implementation_matches_contract(records)

    success_vectors = [r for r in records if r.get("record_type") == "test_vector" and r.get("expected_status") == "SUCCESS"]
    error_vectors = [r for r in records if r.get("record_type") == "test_vector" and r.get("expected_status") == "ERROR"]
    canon_vectors = [r for r in records if r.get("record_type") == "canonicalization_test_vector"]
    if (len(success_vectors), len(error_vectors), len(canon_vectors)) != (9, 6, 1):
        raise SystemExit(
            f"vector inventory drifted: {len(success_vectors)} success / "
            f"{len(error_vectors)} error / {len(canon_vectors)} canonicalization"
        )

    with tempfile.TemporaryDirectory(prefix="simigo-g1-vectors-") as temporary:
        events_path = Path(temporary) / "swift-events.jsonl"
        adapter = adapter_module.SwiftReferenceCalculatorAdapter(binary, events_path)
        results: list[dict] = []

        for vector in success_vectors:
            payload = vector["input"]
            result = adapter(item_id=payload["item_id"],
                             source_payload=payload["source_payload"],
                             dependency_values=payload["dependency_values"])
            if result != vector["expected_result"]:
                raise SystemExit(f"{vector['vector_id']}: result mismatch {result!r}")
            started, terminal = adapter.last_events
            for label, observed, frozen in (
                ("input_sha256", started.get("input_sha256"), vector["input_sha256"]),
                ("dependencies_sha256", started.get("dependencies_sha256"), vector["dependencies_sha256"]),
                ("result_sha256", terminal.get("result_sha256"), vector["expected_result_sha256"]),
            ):
                if observed != frozen:
                    raise SystemExit(f"{vector['vector_id']}: {label} {observed!r} != frozen {frozen!r}")
            results.append({
                "vector_id": vector["vector_id"],
                "status": "PASS",
                "result": result,
                "input_sha256": started["input_sha256"],
                "dependencies_sha256": started["dependencies_sha256"],
                "result_sha256": terminal["result_sha256"],
            })

        for vector in error_vectors:
            expected = vector["expected_error_code"]
            try:
                adapter(item_id=vector["item_id"],
                        source_payload=vector["source_payload"],
                        dependency_values=vector["dependency_values"])
            except adapter_module.SwiftCalculatorFailure as error:
                if error.code != expected:
                    raise SystemExit(f"{vector['vector_id']}: expected {expected}, got {error.code}")
            else:
                raise SystemExit(f"{vector['vector_id']}: expected {expected} but the Swift call succeeded")
            started, terminal = adapter.last_events
            if terminal.get("error_code") != expected:
                raise SystemExit(f"{vector['vector_id']}: event code {terminal.get('error_code')!r} != {expected}")
            results.append({
                "vector_id": vector["vector_id"],
                "status": "PASS",
                "error_code": expected,
                "input_sha256": started.get("input_sha256"),
            })

        canon = canon_vectors[0]
        text, digest = adapter.canonicalize(canon["input_value"])
        if text != canon["expected_canonical_utf8_text"]:
            raise SystemExit(f"canonical text mismatch: {text!r}")
        if digest != canon["expected_sha256"]:
            raise SystemExit(f"canonical sha256 mismatch: {digest}")
        started, terminal = adapter.last_events
        if terminal.get("canonical_sha256") != canon["expected_sha256"]:
            raise SystemExit("canonicalization event digest mismatch")
        results.append({
            "vector_id": canon["vector_id"],
            "status": "PASS",
            "canonical_utf8_text": text,
            "canonical_sha256": digest,
        })

        line_count = sum(1 for _ in events_path.open("r", encoding="utf-8"))
        expected_events = 2 * (len(success_vectors) + len(error_vectors) + len(canon_vectors))
        if line_count != expected_events:
            raise SystemExit(f"event log has {line_count} lines, expected {expected_events}")
        if args.events_out:
            args.events_out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(events_path, args.events_out)

        report: dict[str, Any] = {
            "schema_id": "SIMIGO-G1-SWIFT-VECTOR-GATE-REPORT-V1",
            "gate": "G1.1",
            "contract_id": header["contract_id"],
            "contract_version": header["version"],
            "contract_path": str(args.contract.resolve()),
            "binary": str(binary),
            "vector_inventory": {
                "success": len(success_vectors),
                "error": len(error_vectors),
                "canonicalization": len(canon_vectors),
                "invocations": len(success_vectors) + len(error_vectors) + len(canon_vectors),
                "expected_events": expected_events,
                "observed_events": line_count,
            },
            "results": results,
            "build_identity": build_identity(repo_root, binary, adapter.pinned_sha256),
            "non_claims": [
                "Not evidence that any existing project Calculator was executed.",
                "Not evidence of model inference, KV-cache release, or Information-Space restoration (G2).",
            ],
            "result": "PASS",
        }

    rendered = json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2)
    if args.report:
        args.report.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
