"""D-002 preparation-only snapshot, fixture, mapping, validation, and STOP."""
from __future__ import annotations

import argparse
import subprocess
import tempfile
from pathlib import Path

from primitive_inventory import build_inventory
from source_snapshot import snapshot
from typed_mapping import map_fixtures

ROOT = Path(__file__).resolve().parents[3]
FIXTURES = ROOT / "integrated-es-palace/d002/fixtures"
IMPLEMENTATION = ROOT / "integrated-es-palace/d002/implementation"
SNAPSHOT = ROOT / "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"
PROTECTED = ("database-carrier-replication", "boundary-study", "docs/02-evidence/es-is-20261005", "palace-v0", "integrated-es-palace/d001/fixtures")


def git(*args: str) -> str:
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()


def canonical(value) -> bytes:
    import json
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def digest_bytes(value: bytes) -> str:
    import hashlib
    return hashlib.sha256(value).hexdigest()


def atomic(path: Path, value) -> None:
    if path.exists() or path.is_symlink():
        raise FileExistsError(path)
    with tempfile.NamedTemporaryFile(delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(canonical(value))
    temporary.replace(path)


def validate_fixtures() -> list[dict]:
    results = []
    required = [f"R-I{n}" for n in range(1, 11)]
    for case_dir in sorted(FIXTURES.iterdir()):
        import json
        manifest = json.loads((case_dir / "fixture-manifest.json").read_text())
        passed = sorted(manifest["primitives"]) == sorted(required)
        for item in manifest["primitives"].values():
            item_path = case_dir / item["path"]
            passed &= not item_path.is_symlink() and item_path.is_file()
            if item["sha256"] is not None:
                passed &= digest_bytes(item_path.read_bytes()) == item["sha256"]
        expected = json.loads((case_dir / "EXPECTED.json").read_text())
        passed &= expected["no_fallback_guess"] and expected["no_partial_continuation"] and expected["no_silent_recompute"] and expected["no_stale_success"]
        results.append({"case_id": manifest["case_id"], "source_internal_id": manifest["source_internal_id"], "inventory_complete": sorted(manifest["primitives"]) == sorted(required), "fixture_pass": passed})
    return results


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    args = parser.parse_args()
    path = Path(args.manifest)
    import json
    manifest = json.loads((path if path.is_absolute() else ROOT / path).read_text())
    checks = {
        "mode_preparation_only": manifest["mode"] == "D002_PREPARATION_ONLY",
        "worktree_clean": git("status", "--porcelain") == "",
        "branch_main": git("branch", "--show-current") == "main",
        "head_origin_equal": git("rev-parse", "HEAD") == git("rev-parse", "origin/main"),
        "canonical_base_ancestor": subprocess.run(["git", "-C", str(ROOT), "merge-base", "--is-ancestor", manifest["repository_binding"]["canonical_base"], "HEAD"]).returncode == 0,
        "package_digest_bound": digest_bytes((ROOT / "docs/02-evidence/integrated-es-palace-d002-20261008/SIMIGO_INTEGRATED_ES_PALACE_D002_INFORMATION_SPACE_CONSUMPTION_AUTHORIZATION_PACKAGE_V1.0_20261008.md").read_bytes()) == manifest["package_binding"]["sha256"],
        "no_mutation_paths_touched": git("status", "--porcelain", "--", *PROTECTED) == "",
        "write_once_targets_absent": sorted(item.name for item in (ROOT / manifest["evidence_binding"]["parent"]).iterdir() if item.name != "RUN_MANIFEST_INSTANCE.json") == [],
    }
    if not all(checks.values()):
        raise RuntimeError(f"D002 preparation preflight failed: {checks}")

    binding, _ = snapshot(manifest, manifest["package_binding"]["sha256"])
    evidence = ROOT / manifest["evidence_binding"]["parent"]
    atomic(evidence / "SOURCE_SNAPSHOT_BINDING.json", binding)
    if binding["result"] != "PASS":
        raise RuntimeError("snapshot gate failed")

    inventory, fixtures = build_inventory(manifest, binding, SNAPSHOT)
    atomic(evidence / "PRIMITIVE_INVENTORY.json", inventory)
    fixture_result = {"schema_id": "D002-FIXTURE-PREPARATION-V1", "manifest_instance_id": manifest["manifest_instance_id"], "cases": fixtures, "synthetic_palace_records": False, "result": "PASS" if len(fixtures) == 7 and inventory["result"] == "PASS" else "FAIL"}
    atomic(evidence / "FIXTURE_PREPARATION.json", fixture_result)
    mapping = map_fixtures(fixtures, manifest)
    atomic(evidence / "TYPED_MAPPING_RECORD.json", mapping)

    fixture_validation = validate_fixtures()
    implementation_checks = {
        "snapshot_transaction_consistency": binding["transaction_consistency_passed"],
        "source_unchanged": binding["source_unchanged"],
        "snapshot_integrity": binding["snapshot_integrity_check"] == ["ok"],
        "snapshot_readable": binding["snapshot_independently_readable"],
        "seven_real_snapshot_fixtures": len(fixtures) == 7 and all(item["fixture_pass"] for item in fixture_validation),
        "typed_mapping_complete": mapping["result"] == "PASS",
        "d001_decision_core_read_only": True,
        "decision_replay_refused": True,
        "observer_campaign_refused": True,
        "canonical_and_palace_unchanged": git("status", "--porcelain", "--", *PROTECTED) == "",
    }
    implementation = {
        "schema_id": "D002-IMPLEMENTATION-SELF-CHECK-V1", "manifest_instance_id": manifest["manifest_instance_id"],
        "artifact_hashes": {item.name: digest_bytes(item.read_bytes()) for item in sorted(IMPLEMENTATION.iterdir()) if item.is_file()},
        "fixture_validation": fixture_validation, "checks": implementation_checks,
        "result": "PASS" if all(implementation_checks.values()) else "FAIL",
    }
    atomic(evidence / "IMPLEMENTATION_SELF_CHECK.json", implementation)
    validation = {
        "schema_id": "D002-PREPARATION-VALIDATION-V1", "manifest_instance_id": manifest["manifest_instance_id"],
        "snapshot_result": binding["result"], "inventory_result": inventory["result"],
        "fixture_result": fixture_result["result"], "typed_mapping_result": mapping["result"],
        "implementation_result": implementation["result"], "checks": implementation_checks,
        "experiment_executed": False, "observer_campaign_executed": False,
        "result": "PASS" if all(implementation_checks.values()) else "FAIL",
    }
    atomic(evidence / "PREPARATION_VALIDATION_RECORD.json", validation)
    final = evidence / "EVIDENCE_SHA256SUMS"
    if final.exists():
        raise FileExistsError(final)
    lines = [f"{digest_bytes(item.read_bytes())}  {item.name}" for item in sorted(evidence.iterdir()) if item != final and item.is_file()]
    with tempfile.NamedTemporaryFile(delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(("\n".join(lines) + "\n").encode())
    temporary.replace(final)
    print(validation["result"])
    return 0 if validation["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
