"""S0 fresh-entry preflight."""
from __future__ import annotations

import argparse
import ast
import subprocess
import tempfile
from pathlib import Path

from schemas import canonical_bytes, digest_bytes, exact_fields, load_json

ROOT = Path(__file__).resolve().parents[3]
IMPLEMENTATION = ROOT / "integrated-es-palace/d001/implementation"
FIXTURES = ROOT / "integrated-es-palace/d001/fixtures"
CASES = ["P-LAWFUL", "P-SETTLED", "P-BLOCKED", "N-MISSING", "N-STALE", "N-AMBIGUOUS", "N-ILLEGAL"]
ALLOWED_IMPORTS = {"argparse", "ast", "contextlib", "datetime", "hashlib", "json", "pathlib", "sqlite3", "subprocess", "tempfile", "typing", "__future__", "inventory", "reconstruction", "schemas", "continuation", "carrier"}


def git(*args: str) -> str:
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()


def git_ok(*args: str) -> bool:
    return subprocess.run(["git", "-C", str(ROOT), *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def atomic_write(path: Path, value: dict) -> None:
    if path.exists() or path.is_symlink():
        raise FileExistsError(path)
    with tempfile.NamedTemporaryFile(delete=False) as handle:
        temp = Path(handle.name)
        handle.write(canonical_bytes(value))
    temp.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True)
    args = parser.parse_args()
    manifest_path = (ROOT / args.manifest).resolve() if not Path(args.manifest).is_absolute() else Path(args.manifest)
    manifest = load_json(manifest_path)
    exact_fields(manifest, {"manifest_instance_id", "manifest_contract_id", "package_id", "mode", "schema_version", "repository_binding", "governance_bindings", "implementation_binding", "fixture_binding", "evidence_binding", "stage_plan", "stop_rule"}, "manifest-instance")
    checks = {}
    checks["PF-1"] = git("status", "--porcelain") == ""
    checks["PF-2"] = git("branch", "--show-current") == "main" and git("rev-parse", "HEAD") == git("rev-parse", "origin/main") and git_ok("merge-base", "--is-ancestor", manifest["repository_binding"]["canonical_commit"], "HEAD")
    governance_ok = True
    for record in manifest["governance_bindings"].values():
        if not isinstance(record, dict) or "path" not in record:
            continue
        path = ROOT / record["path"]
        governance_ok &= path.is_file() and not path.is_symlink() and digest_bytes(path.read_bytes()) == record["sha256"]
    checks["PF-3"] = bool(governance_ok)
    actual_files = sorted(path.name for path in IMPLEMENTATION.iterdir() if path.is_file() and not path.is_symlink())
    checks["PF-4"] = actual_files == sorted(manifest["implementation_binding"]["artifacts"]) and (not FIXTURES.exists() or sorted(path.name for path in FIXTURES.iterdir()) == sorted(CASES))
    evidence = ROOT / manifest["evidence_binding"]["parent"]
    existing = sorted(path.name for path in evidence.iterdir() if path.name != "RUN_MANIFEST_INSTANCE.json")
    checks["PF-5"] = existing == []
    checks["PF-6"] = not FIXTURES.exists() or all(not (FIXTURES / case).is_symlink() for case in CASES)
    checks["PF-7"] = (IMPLEMENTATION / "IMPLEMENTATION_MANIFEST.json").is_file()
    checks["PF-8"] = manifest["mode"] == "IMPLEMENTATION_FIXTURE_PREPARATION_ONLY"
    checks["PF-9"] = manifest["stage_plan"]["integrated_experiment"] is False and manifest["stage_plan"]["observer_campaign"] is False
    checks["PF-10"] = "canonical_is_mutation" not in canonical_bytes(manifest).decode().lower()

    source_ok = True
    for path in IMPLEMENTATION.glob("*.py"):
        tree = ast.parse(path.read_text(encoding="utf-8"))
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                source_ok &= all(alias.name.split(".")[0] in ALLOWED_IMPORTS for alias in node.names)
            elif isinstance(node, ast.ImportFrom) and node.module:
                source_ok &= node.module.split(".")[0] in ALLOWED_IMPORTS
            elif isinstance(node, ast.Attribute):
                source_ok &= not (isinstance(node.value, ast.Name) and node.value.id == "os" and node.attr == "environ")
            elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
                source_ok &= node.func.attr != "getenv"
    checks["STATIC_SOURCE"] = source_ok
    result = {"schema_id": "D001-S0-PREFLIGHT-V1", "manifest_instance_id": manifest["manifest_instance_id"], "stage": "S0-PREFLIGHT", "checks": checks, "result": "PASS" if all(checks.values()) else "FAIL"}
    atomic_write(evidence / "PREFLIGHT.json", result)
    print(result["result"])
    return 0 if result["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
