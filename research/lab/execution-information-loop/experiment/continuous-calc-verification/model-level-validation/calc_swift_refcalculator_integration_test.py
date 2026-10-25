#!/usr/bin/env python3
"""G1.2 gate — rerun the accepted Carrier sequence with the Swift adapter.

The already-passing acceptance sequence in `calc_refcalculator_entry_test.py` is
reused verbatim; the only change is that the module-level `reference_calculator`
it calls is replaced by `SwiftReferenceCalculatorAdapter`. No Carrier code is
modified and no Python fallback exists: a Swift failure raises through the
Carrier transaction.

Required observations (frozen `p3_arm4_acceptance_contract`):
  * cold start settles A=6, B=11, C=24, D=42, E=26 with five Swift calls;
  * after A: 3 -> 4, recompute {A,B,C,D} and reuse {E};
  * E keeps its settlement object_id; the four recomputed nodes get new ones;
  * a forced Swift error rolls the demand transaction back with no settlement.

Plus the cross-language event audit: one `started` and one terminal event per
Swift call, every event carrying the pinned executable hash.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
DEFAULT_BINARY = HERE / "g1-swift-reference-calculator" / ".build" / "release" / "SwiftReferenceCalculator"


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


def audit_events(lines: list[dict], expected_calls: list[str]) -> dict:
    by_invocation: dict[str, list[dict]] = {}
    for line in lines:
        by_invocation.setdefault(line["invocation_id"], []).append(line)
    if len(by_invocation) != len(expected_calls):
        raise SystemExit(
            f"event audit: {len(by_invocation)} invocations for {len(expected_calls)} calculator calls"
        )
    failed = 0
    compute_units: list[str] = []
    for invocation_id, events in by_invocation.items():
        if len(events) != 2:
            raise SystemExit(f"event audit: invocation {invocation_id} has {len(events)} events")
        started, terminal = events
        if started["event"] != "started" or started["seq"] != 1:
            raise SystemExit(f"event audit: bad started event {started}")
        if terminal["seq"] != 2 or terminal["event"] not in {"completed", "failed"}:
            raise SystemExit(f"event audit: bad terminal event {terminal}")
        if started.get("item_id") is not None:
            compute_units.append(started["item_id"])
        if terminal["event"] == "failed":
            failed += 1
            if terminal.get("error_code") != "ARITHMETIC_OVERFLOW":
                raise SystemExit(f"event audit: unexpected failure code {terminal.get('error_code')}")
    return {
        "invocations": len(by_invocation),
        "events": len(lines),
        "failed_invocations": failed,
        "compute_unit_sequence": compute_units,
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

    package_dir = HERE / "g1-swift-reference-calculator"
    if args.build:
        run(["swift", "build", "-c", "release", "--package-path", str(package_dir)], repo_root)
    binary = args.binary.resolve()
    if not binary.is_file():
        raise SystemExit(f"missing executable {binary}; build it with --build")

    refcalc = load_module(HERE / "calc_refcalculator_entry_test.py", "simigo_refcalc")
    adapter_module = load_module(HERE / "swift_reference_calculator_adapter.py", "simigo_swift_adapter")

    header, records = refcalc.load_jsonl_contract(args.contract.resolve())
    acceptance = refcalc.validate_implementation_matches_contract(records)

    with tempfile.TemporaryDirectory(prefix="simigo-g1-carrier-") as temporary:
        events_path = Path(temporary) / "carrier-events.jsonl"
        adapter = adapter_module.SwiftReferenceCalculatorAdapter(
            binary, events_path, error_class=refcalc.CalculatorContractError
        )

        # Explicit substitution: the acceptance sequence calls the module-level
        # `reference_calculator`; that name now resolves to the Swift adapter.
        refcalc.reference_calculator = adapter

        carrier = refcalc.run_carrier_acceptance(records, acceptance, repo_root)
        rollback = refcalc.run_rollback_acceptance(repo_root)

        events = [json.loads(line) for line in events_path.read_text(encoding="utf-8").splitlines() if line.strip()]
        audit = audit_events(events, adapter.calls)

        expected_sequence = ["A", "B", "C", "D", "E", "A", "B", "C", "D", "A", "B"]
        if adapter.calls != expected_sequence:
            raise SystemExit(f"Swift call sequence drifted: {adapter.calls}")
        if audit["failed_invocations"] != 1:
            raise SystemExit(f"expected exactly one failed Swift invocation, saw {audit['failed_invocations']}")

        if args.events_out:
            args.events_out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(events_path, args.events_out)

    report: dict[str, Any] = {
        "schema_id": "SIMIGO-G1-CARRIER-INTEGRATION-REPORT-V1",
        "gate": "G1.2",
        "contract_id": header["contract_id"],
        "contract_version": header["version"],
        "acceptance_contract": acceptance["scenario_id"],
        "substitution": "calc_refcalculator_entry_test.reference_calculator -> SwiftReferenceCalculatorAdapter",
        "carrier_acceptance": carrier,
        "rollback_acceptance": rollback,
        "swift_call_sequence": adapter.calls,
        "event_audit": audit,
        "build_identity": {
            "build_command": f"swift build -c release --package-path {package_dir.relative_to(repo_root)}",
            "source_revision": run(["git", "rev-parse", "HEAD"], repo_root),
            "source_tree_clean_at_build": run(["git", "status", "--porcelain"], repo_root) == "",
            "executable_sha256": adapter.pinned_sha256,
        },
        "non_claims": [
            "G1.2 proves cross-language consistency and Carrier transaction behaviour only.",
            "It does not prove that any pre-existing project Calculator was executed.",
            "It does not prove KV-cache release, Information-Space restoration, or model continuation (G2).",
        ],
        "result": "PASS",
    }

    rendered = json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
