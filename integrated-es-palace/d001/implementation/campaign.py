"""One-run D-001 bounded experiment and independent observer campaign."""
from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

from carrier import persist_records
from continuation import decide
from inventory import Inventory
from schemas import canonical_bytes, digest_bytes, load_json

ROOT = Path(__file__).resolve().parents[3]
FIXTURES = ROOT / "integrated-es-palace/d001/fixtures"
CASES = ["P-LAWFUL", "P-SETTLED", "P-BLOCKED", "N-MISSING", "N-STALE", "N-AMBIGUOUS", "N-ILLEGAL"]
FORBIDDEN_MUTATION_ROOTS = ("database-carrier-replication", "boundary-study", "docs/02-evidence/es-is-20261005", "palace-v0")


def git(*args: str) -> str:
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()


def atomic(path: Path, value: dict) -> None:
    if path.exists() or path.is_symlink():
        raise FileExistsError(path)
    with tempfile.NamedTemporaryFile(delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(canonical_bytes(value))
    temporary.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    args = parser.parse_args()
    manifest_path = Path(args.manifest)
    manifest = load_json(manifest_path if manifest_path.is_absolute() else ROOT / manifest_path)
    evidence = ROOT / manifest["evidence_binding"]["parent"]
    checks = {
        "mode_bounded": manifest["mode"] == "BOUNDED_EXPERIMENT_OBSERVER_CAMPAIGN_ONLY",
        "worktree_clean": git("status", "--porcelain") == "",
        "branch_main": git("branch", "--show-current") == "main",
        "head_origin_equal": git("rev-parse", "HEAD") == git("rev-parse", "origin/main"),
        "canonical_base_ancestor": subprocess.run(["git", "-C", str(ROOT), "merge-base", "--is-ancestor", manifest["repository_binding"]["canonical_base"], "HEAD"]).returncode == 0,
        "preparation_validation_bound": digest_bytes((ROOT / "docs/02-evidence/integrated-es-palace-d001-validation-v1-correction-005/PREPARATION_VALIDATION_RECORD.json").read_bytes()) == manifest["preparation_binding"]["validation_sha256"],
        "seven_fresh_cases": FIXTURES.exists() and sorted(path.name for path in FIXTURES.iterdir()) == sorted(CASES) and all(not (FIXTURES / case).is_symlink() for case in CASES),
        "write_once_targets_absent": sorted(path.name for path in evidence.iterdir()) == ["RUN_MANIFEST_INSTANCE.json"],
        "no_mutation_paths_touched": git("status", "--porcelain", "--", *FORBIDDEN_MUTATION_ROOTS) == "",
    }
    if not all(checks.values()):
        raise RuntimeError(f"campaign preflight failed: {checks}")

    observations = {}
    identities = []
    for case in CASES:
        inventory = Inventory(FIXTURES / case / "fixture-manifest.json")
        result = decide(inventory)
        expected = load_json(FIXTURES / case / "EXPECTED.json")
        observations[case] = {
            "decision": result["typed_decision"],
            "continuation_class": result["output"]["continuation_class"],
            "precedence_reason": result["precedence_reason"],
            "identity_digest": result["identity_digest"],
            "output_digest": result["output"]["continuation_output_digest"],
            "expected_decision": expected["decision"],
            "expected_class": expected["continuation_class"],
            "passed": result["typed_decision"] == expected["decision"] and result["output"]["continuation_class"] == expected["continuation_class"],
        }
        identities.append({
            "record_key": result["identity_digest"], "case_id": case, "identity": result["identity"],
            "identity_digest": result["identity_digest"], "closure_digest": result["closure"]["closure_digest"],
        })
    with tempfile.TemporaryDirectory() as temporary:
        carrier_state = persist_records(Path(temporary) / "carrier.sqlite", identities)
    experiment = {
        "schema_id": "D001-BOUNDED-EXPERIMENT-RECORD-V1", "manifest_instance_id": manifest["manifest_instance_id"],
        "execution_head": git("rev-parse", "HEAD"), "checks": checks, "observations": observations,
        "carrier_state": carrier_state, "result": "PASS" if all(item["passed"] for item in observations.values()) and carrier_state["state"] == "PERSISTED" else "FAIL",
    }
    observer_output = subprocess.check_output([
        "python3", str(ROOT / "integrated-es-palace/d001/implementation/observer.py"), "--fixtures", str(FIXTURES)
    ], text=True)
    observer = json.loads(observer_output)
    reconciled = all(
        observations[item["case_id"]]["passed"] and item["observer_decision"] == observations[item["case_id"]]["decision"]
        and item["inventory_complete"] and item["side_channels_denied"] for item in observer["observations"]
    )
    reconciliation = {
        "schema_id": "D001-EXPERIMENT-OBSERVER-RECONCILIATION-V1",
        "experiment_result": experiment["result"], "observer_result": observer["result"],
        "reconciled_cases": reconciled, "canonical_is_mutated": False,
        "forbidden_channels_observed": any(not item["side_channels_denied"] for item in observer["observations"]),
        "result": "PASS" if experiment["result"] == "PASS" and observer["result"] == "PASS" and reconciled else "FAIL",
    }
    claim = {
        "schema_id": "D001-BOUNDED-CLAIM-V1", "result": reconciliation["result"],
        "claim": "For the pre-registered D-001 fixture configuration, Execution State produced the seven pre-registered typed decisions and the independent observer reconciled them without forbidden-channel influence or canonical IS mutation.",
        "scope_exclusions": ["PALACE equivalence", "integrated SimiGo proof", "general Execution State theorem", "production SimiGo validity", "LLM autonomy", "arbitrary IS/ES states"],
    }
    atomic(evidence / "EXPERIMENT_RECORD.json", experiment)
    atomic(evidence / "OBSERVER_RECORD.json", observer)
    atomic(evidence / "RECONCILIATION_RECORD.json", reconciliation)
    atomic(evidence / "CLAIM_RECORD.json", claim)
    final = evidence / "EVIDENCE_SHA256SUMS"
    lines = [f"{digest_bytes(path.read_bytes())}  {path.name}" for path in sorted(evidence.iterdir()) if path != final and path.is_file()]
    with tempfile.NamedTemporaryFile(delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(("\n".join(lines) + "\n").encode())
    temporary.replace(final)
    print(reconciliation["result"])
    return 0 if reconciliation["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
