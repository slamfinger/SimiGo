"""One-run D-002 replay/experiment/observer campaign with write-once closure."""
from __future__ import annotations

import argparse
import hashlib
import json
import ast
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
import sys
sys.path.insert(0, str(ROOT / "integrated-es-palace/d001/implementation"))
CASES = ["P-LAWFUL", "P-SETTLED", "P-BLOCKED", "N-MISSING", "N-STALE", "N-AMBIGUOUS", "N-ILLEGAL"]
PROTECTED = ("database-carrier-replication", "boundary-study", "docs/02-evidence/es-is-20261005", "palace-v0", "integrated-es-palace/d001/fixtures")


def git(*args: str) -> str:
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()


def digest_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def atomic(path: Path, value) -> None:
    if path.exists() or path.is_symlink():
        raise FileExistsError(path)
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    with tempfile.NamedTemporaryFile(delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(payload)
    temporary.replace(path)


def manifest_adapter_closure(manifest: dict) -> tuple[bool, dict]:
    reasons = []
    for path in manifest["completeness_binding"]["required_paths"]:
        value = manifest
        for key in path:
            if not isinstance(value, dict) or key not in value:
                reasons.append(".".join(path))
                break
            value = value[key]
    if manifest.get("package_binding", {}).get("package_id") != manifest.get("package_id"):
        reasons.append("package_id_mismatch")
    frozen_evidence_objects = [
        "RUN_MANIFEST_INSTANCE.json", "DECISION_REPLAY_RECORD.json", "EXPERIMENT_RECORD.json",
        "CARRIER_LIFECYCLE_RECORD.json", "OBSERVER_RECORD.json", "RECONCILIATION_RECORD.json",
        "CLAIM_RECORD.json", "EVIDENCE_SHA256SUMS",
    ]
    if manifest["evidence_binding"]["exact_objects"] != frozen_evidence_objects:
        reasons.append("evidence_objects_mismatch")
    if manifest["campaign_binding"]["cases"] != CASES:
        reasons.append("campaign_cases_mismatch")
    if manifest["fixture_binding"]["cases"] != CASES or manifest["fixture_binding"]["fixtures_parent"] != "integrated-es-palace/d002/fixtures":
        reasons.append("fixture_binding_mismatch")
    replay_source = (ROOT / "integrated-es-palace/d002/implementation/decision_replay.py").read_text(encoding="utf-8")
    tree = ast.parse(replay_source)
    literals = {node.value for node in ast.walk(tree) if isinstance(node, ast.Constant) and isinstance(node.value, str)}
    required_literals = {"package_binding", "package_id", "manifest_instance_id", "schema_version", "evidence_binding", "exact_objects", "campaign_binding", "cases", "fixture_binding", "fixtures_parent", "snapshot_binding"}
    missing_literals = sorted(required_literals - literals)
    if missing_literals:
        reasons.append("adapter_literal_access_missing:" + ",".join(missing_literals))
    return not reasons, {"schema_id": "D002-MANIFEST-ADAPTER-CLOSURE-V1", "gate_id": manifest["completeness_binding"]["gate_id"], "reasons": reasons, "result": "PASS" if not reasons else "FAIL"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    args = parser.parse_args()
    path = Path(args.manifest)
    manifest = load(path if path.is_absolute() else ROOT / path)
    evidence = ROOT / manifest["evidence_binding"]["parent"]
    checks = {
        "mode_bounded": manifest["mode"] == "D002_BOUNDED_CONSUMPTION_ONLY",
        "worktree_clean": git("status", "--porcelain") == "",
        "branch_main": git("branch", "--show-current") == "main",
        "head_origin_equal": git("rev-parse", "HEAD") == git("rev-parse", "origin/main"),
        "canonical_base_ancestor": subprocess.run(["git", "-C", str(ROOT), "merge-base", "--is-ancestor", manifest["repository_binding"]["canonical_base"], "HEAD"]).returncode == 0,
        "source_unchanged": digest_bytes((ROOT / manifest["snapshot_binding"]["source"]["path"]).read_bytes()) == manifest["snapshot_binding"]["source"]["sha256"],
        "snapshot_unchanged": digest_bytes((ROOT / manifest["snapshot_binding"]["prepared_snapshot"]["path"]).read_bytes()) == manifest["snapshot_binding"]["prepared_snapshot"]["sha256"],
        "preparation_validation_bound": digest_bytes((ROOT / manifest["preparation_binding"]["validation_record"]["path"]).read_bytes()) == manifest["preparation_binding"]["validation_record"]["sha256"],
        "seven_retained_fixtures": sorted(item.name for item in (ROOT / manifest["fixture_binding"]["fixtures_parent"]).iterdir()) == sorted(CASES),
        "write_once_targets_absent": sorted(item.name for item in evidence.iterdir() if item.name != "RUN_MANIFEST_INSTANCE.json") == [],
        "no_mutation_paths_touched": git("status", "--porcelain", "--", *PROTECTED) == "",
        "correction_scope_clean": (ROOT / manifest["authorization_binding"]["path"]).is_file() and git("status", "--porcelain") == "" and git("status", "--porcelain", "--", "integrated-es-palace/d001", "palace-v0", "integrated-es-palace/d002/fixtures") == "",
        "D001_CORE_DIGESTS_UNCHANGED": all(digest_bytes((ROOT / "integrated-es-palace/d001/implementation" / name).read_bytes()) == digest for name, digest in manifest["baseline_binding"]["d001_core_sha256"].items()),
        "FIXTURE_EXPECTED_UNCHANGED": all(digest_bytes((ROOT / "integrated-es-palace/d002/fixtures" / case / filename).read_bytes()) == digest for case, bindings in manifest["baseline_binding"]["expected_and_manifest_sha256"].items() for filename, digest in bindings.items()),
        "SNAPSHOT_SOURCE_BINDINGS": digest_bytes((ROOT / manifest["snapshot_binding"]["source"]["path"]).read_bytes()) == manifest["baseline_binding"]["source_sha256"] and digest_bytes((ROOT / manifest["snapshot_binding"]["prepared_snapshot"]["path"]).read_bytes()) == manifest["baseline_binding"]["snapshot_sha256"],
        "D002_MANIFEST_ADAPTER_CLOSURE": manifest_closure[0],
    }
    manifest_closure = manifest_adapter_closure(manifest)
    manifest_closure_record = manifest_closure[1]
    if not all(checks.values()):
        raise RuntimeError(f"D002 campaign preflight failed: {checks}")

    replay_output = subprocess.check_output([
        "python3", str(ROOT / "integrated-es-palace/d002/implementation/decision_replay.py"), "--manifest", str(ROOT / path)
    ], text=True)
    replay = json.loads(replay_output)
    replay_by_case = {item["case_id"]: item for item in replay["records"]}
    vector_pass = True
    for case in CASES:
        expected = load(ROOT / manifest["fixture_binding"]["fixtures_parent"] / case / "EXPECTED.json")
        observed = replay_by_case[case]["observed"]
        replay_by_case[case]["vector_pass"] = [observed["decision"], observed["continuation_class"], observed["precedence_reason"]] == [expected["decision"], expected["continuation_class"], expected["precedence_reason"]]
        vector_pass &= replay_by_case[case]["vector_pass"]
    replay["vector_result"] = "PASS" if vector_pass else "FAIL"

    from carrier import persist_records
    records = [{"record_key": replay_by_case[case]["identity_digest"], "case_id": case, "identity_digest": replay_by_case[case]["identity_digest"]} for case in CASES]
    with tempfile.TemporaryDirectory() as temporary:
        carrier = persist_records(Path(temporary) / "carrier.sqlite", records)
    experiment = {
        "schema_id": "D002-EXPERIMENT-RECORD-V1", "manifest_instance_id": manifest["manifest_instance_id"],
        "execution_head": git("rev-parse", "HEAD"), "checks": checks,
        "manifest_adapter_closure": manifest_closure_record, "replay_result": replay["vector_result"],
        "carrier_state": carrier, "result": "PASS" if replay["result"] == "PASS" and replay["vector_result"] == "PASS" and carrier["state"] == "PERSISTED" else "FAIL",
    }
    observer_output = subprocess.check_output([
        "python3", str(ROOT / "integrated-es-palace/d002/implementation/observer.py"), "--fixtures", str(ROOT / manifest["fixture_binding"]["fixtures_parent"])
    ], text=True)
    observer = json.loads(observer_output)
    observer_by_case = {item["case_id"]: item for item in observer["observations"]}
    reconciled = all(observer_by_case[case]["observer_decision"] == replay_by_case[case]["observed"]["decision"] and observer_by_case[case]["inventory_complete"] and observer_by_case[case]["side_channels_denied"] for case in CASES)
    reconciliation = {
        "schema_id": "D002-RECONCILIATION-RECORD-V1", "experiment_result": experiment["result"],
        "observer_result": observer["result"], "reconciled_cases": reconciled,
        "forbidden_channels_observed": any(not item["side_channels_denied"] for item in observer["observations"]),
        "canonical_is_mutated": False,
        "result": "PASS" if experiment["result"] == "PASS" and observer["result"] == "PASS" and reconciled else "FAIL",
    }
    claim = {
        "schema_id": "D002-BOUNDED-CLAIM-V1", "result": reconciliation["result"],
        "claim": "For the pre-registered real PALACE D-002 configuration, allowed Information-Space metadata was mapped into D-001 typed reconstruction inputs; the unchanged D-001 Decision Core produced the frozen three-component vector, persisted seven Carrier records, and an independent observer reconciled the result without forbidden-channel influence or canonical/PALACE mutation.",
        "scope_exclusions": ["PALACE equivalence", "integrated SimiGo proof", "general Execution State theorem", "production SimiGo validity", "LLM autonomy", "arbitrary IS/ES states"],
    }
    atomic(evidence / "DECISION_REPLAY_RECORD.json", replay)
    atomic(evidence / "EXPERIMENT_RECORD.json", experiment)
    atomic(evidence / "CARRIER_LIFECYCLE_RECORD.json", {"schema_id": "D002-CARRIER-LIFECYCLE-V1", "state": carrier, "result": "PASS" if carrier["state"] == "PERSISTED" else "FAIL"})
    atomic(evidence / "OBSERVER_RECORD.json", observer)
    atomic(evidence / "RECONCILIATION_RECORD.json", reconciliation)
    atomic(evidence / "CLAIM_RECORD.json", claim)
    final = evidence / "EVIDENCE_SHA256SUMS"
    lines = [f"{digest_bytes(item.read_bytes())}  {item.name}" for item in sorted(evidence.iterdir()) if item != final and item.is_file()]
    with tempfile.NamedTemporaryFile(delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(("\n".join(lines) + "\n").encode())
    temporary.replace(final)
    print(reconciliation["result"])
    return 0 if reconciliation["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
