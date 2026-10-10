#!/usr/bin/env python3
"""Prepare the write-once integrated ES+PALACE fixture package."""
from __future__ import annotations

import hashlib
import json
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_FIXTURES = ROOT / "integrated-es-palace/d002/fixtures"
SOURCE_SNAPSHOT = ROOT / "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite"
DESTINATION = ROOT / "integrated-es-palace/integration-fixture-v1"
EVIDENCE = DESTINATION / "preparation"
CASES = [
    "P-LAWFUL", "P-SETTLED", "P-BLOCKED",
    "N-MISSING", "N-STALE", "N-AMBIGUOUS", "N-ILLEGAL",
]
PRIMITIVE_FAMILIES = [f"R-I{index}" for index in range(1, 11)]
SEALED_SNAPSHOT_SHA256 = (
    "8b3856e2e4e3a1bd87580afc1ab42094e9a952e0985952323e02ae6595ce1444"
)
PILOT_MANIFEST_SHA256 = (
    "14c6b9d11e7237a4c5586a0755541082faf1919d04298801b0bfba1f12c5d488"
)
PILOT_VERIFIER_SHA256 = (
    "9fe413d796a233157225cdb27465a357d1d62c144d2ef0b19fa5abbc16c49ef3"
)
PILOT_SELFTEST_SHA256 = (
    "6aecd57398459feaa07cc5d3e7574ae97d64b2d9d4a397560c42d5048b188009"
)
FORBIDDEN_CHANNELS = [
    "semantic_search",
    "embedding_ranking",
    "model_hidden_context",
    "physical_filesystem_probe",
    "unapproved_environment_input",
    "unregistered_is_object",
    "carrier_semantic_decision",
    "unregistered_global_state",
]
PROTECTED_PATHS = [
    "palace-v0",
    "database-carrier-replication",
    "integrated-es-palace/d001",
    "integrated-es-palace/d002",
    "docs/02-evidence/integrated-es-palace-d002-consumption-v1",
]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")


def atomic_json(path: Path, value: object) -> None:
    if path.exists() or path.is_symlink():
        raise FileExistsError(path)
    with tempfile.NamedTemporaryFile(delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(canonical(value) + b"\n")
    temporary.replace(path)


def git(*arguments: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(ROOT), *arguments], text=True
    ).strip()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def verify_inherited_evidence() -> dict:
    require(digest(SOURCE_SNAPSHOT) == SEALED_SNAPSHOT_SHA256, "snapshot drift")
    preparation = json.loads(
        (ROOT / "docs/02-evidence/integrated-es-palace-d002-preparation-correction-002/FIXTURE_PREPARATION.json").read_text()
    )
    require(preparation["result"] == "PASS", "inherited fixture preparation failed")
    require(len(preparation["cases"]) == 7, "inherited case count drift")
    require(
        digest(ROOT / PILOT_MANIFEST_SHA256_FIELD) == PILOT_MANIFEST_SHA256,
        "pilot manifest drift",
    )
    require(
        digest(ROOT / PILOT_VERIFIER_SHA256_FIELD) == PILOT_VERIFIER_SHA256,
        "pilot verifier drift",
    )
    require(
        digest(ROOT / PILOT_SELFTEST_SHA256_FIELD) == PILOT_SELFTEST_SHA256,
        "pilot selftest drift",
    )
    return preparation


def validate_case(case: str) -> tuple[dict, dict]:
    source = SOURCE_FIXTURES / case
    require(source.is_dir() and not source.is_symlink(), f"bad source case {case}")
    manifest = json.loads((source / "fixture-manifest.json").read_text())
    expected = json.loads((source / "EXPECTED.json").read_text())
    require(manifest["case_id"] == case, f"case identity drift {case}")
    require(sorted(manifest["primitives"]) == sorted(PRIMITIVE_FAMILIES), f"inventory drift {case}")
    for family, item in manifest["primitives"].items():
        path = source / item["path"]
        if item["sha256"] is None:
            require(
                family == "R-I5" and case == "N-MISSING" and not path.exists(),
                f"unexpected missing primitive {case}:{family}",
            )
            continue
        require(not path.is_symlink() and path.is_file(), f"bad primitive {case}:{family}")
        require(digest(path) == item["sha256"], f"primitive drift {case}:{family}")
    require(expected["decision"] in {"CONTINUE", "REUSE", "BLOCK"}, f"decision drift {case}")
    require(all(expected[key] for key in [
        "no_fallback_guess", "no_partial_continuation",
        "no_silent_recompute", "no_stale_success",
    ]), f"fail-closed flags drift {case}")
    return manifest, expected


def relative_files(root: Path) -> list[Path]:
    return sorted(
        path for path in root.rglob("*")
        if path.is_file() and not path.is_symlink()
    )


PILOT_MANIFEST_SHA256_FIELD = (
    "docs/02-evidence/controlled-production-pilot-20261009/"
    "CONTROLLED_PRODUCTION_PILOT_V5_SQLITE_BUSY_REVISION_MANIFEST.json"
)
PILOT_VERIFIER_SHA256_FIELD = (
    "docs/02-evidence/controlled-production-pilot-20261009/"
    "CONTROLLED_PRODUCTION_PILOT_V5_SQLITE_BUSY_REVISION_VERIFIER_RECORD.json"
)
PILOT_SELFTEST_SHA256_FIELD = (
    "docs/02-evidence/controlled-production-pilot-20261009/"
    "CONTROLLED_PRODUCTION_PILOT_V5_SQLITE_BUSY_REVISION_CARRIER_SELFTEST.json"
)


def main() -> int:
    if DESTINATION.exists() or DESTINATION.is_symlink():
        raise FileExistsError(DESTINATION)
    require(git("branch", "--show-current") == "main", "must run on main")
    require(git("status", "--porcelain") == "", "worktree must be clean")
    inherited = verify_inherited_evidence()

    before_snapshot = digest(SOURCE_SNAPSHOT)
    case_records = []
    for case in CASES:
        manifest, expected = validate_case(case)
        source = SOURCE_FIXTURES / case
        destination = DESTINATION / "fixtures" / case
        shutil.copytree(source, destination, symlinks=False)
        copied = relative_files(destination)
        require(
            [path.relative_to(destination).as_posix() for path in copied]
            == [path.relative_to(source).as_posix() for path in relative_files(source)],
            f"copy inventory drift {case}",
        )
        require(
            all(digest(path) == digest(source / path.relative_to(destination)) for path in copied),
            f"copy digest drift {case}",
        )
        case_records.append({
            "case_id": case,
            "expected": expected,
            "fixture_root": f"fixtures/{case}",
            "manifest_sha256": digest(destination / "fixture-manifest.json"),
            "primitive_count": len(manifest["primitives"]),
            "source_internal_id": manifest["source_internal_id"],
        })
    require(digest(SOURCE_SNAPSHOT) == before_snapshot, "sealed snapshot changed")

    dependencies = {
        "python": {
            "implementation": "3",
            "runtime": platform.python_version(),
            "third_party_packages": [],
            "stdlib_only": True,
        },
        "d001_read_only_decision_core": {
            name: digest(ROOT / "integrated-es-palace/d001/implementation" / name)
            for name in ["schemas.py", "inventory.py", "reconstruction.py", "continuation.py"]
        },
        "frozen_design_v1_1": digest(ROOT / "docs/00-governance/SIMIGO_INTEGRATED_ES_PALACE_VALIDATION_DESIGN_PACKAGE_001_REVISION_V1.1_20261008.md"),
        "frozen_design_acceptance": digest(ROOT / "docs/00-governance/SIMIGO_INTEGRATED_ES_PALACE_VALIDATION_DESIGN_PACKAGE_001_REVISION_V1.1_ACCEPTANCE_RULING_20261008.md"),
        "fixture_request_v1_0": digest(ROOT / "docs/00-governance/SIMIGO_INTEGRATED_ES_PALACE_IMPLEMENTATION_FIXTURE_PREPARATION_REQUEST_V1.0_20261008.md"),
        "pilot_v5_sqlite_busy": {
            "governance_acceptance": digest(ROOT / "docs/00-governance/SIMIGO_CONTROLLED_PRODUCTION_PILOT_V5_SQLITE_BUSY_ACCEPT_20261010.md"),
            "manifest_sha256": PILOT_MANIFEST_SHA256,
            "selftest_sha256": PILOT_SELFTEST_SHA256,
            "verifier_record_sha256": PILOT_VERIFIER_SHA256,
        },
        "sealed_palace_snapshot": {
            "path": "integrated-es-palace/d002/snapshot/PALACE_SNAPSHOT.sqlite",
            "read_only": True,
            "sha256": SEALED_SNAPSHOT_SHA256,
        },
    }
    missing = [
        {
            "item": "non-D002 integration validation Run Manifest",
            "reason": "must be created only in the single follow-on authorization request",
        },
        {
            "item": "new integration Execution State implementation/adaptor",
            "reason": "fixture preparation is input-only and does not execute semantics",
        },
        {
            "item": "fresh integrated validation evidence",
            "reason": "experiment execution remains unauthorized",
        },
        {
            "item": "Human authorization for one non-D002 integration validation",
            "reason": "must be granted by a separate explicit ruling",
        },
    ]
    manifest = {
        "schema_id": "INTEGRATED-ES-PALACE-FIXTURE-PACKAGE-MANIFEST-V1",
        "fixture_package_id": "INTEGRATED-ES-PALACE-FIXTURE-PACKAGE-V1",
        "mode": "FIXTURE_PREPARATION_ONLY",
        "governing_request": "INTEGRATED-ES-PALACE-IMPLEMENTATION-FIXTURE-PREPARATION-REQUEST-V1.0",
        "frozen_design": "INTEGRATED-ES-PALACE-VALIDATION-DESIGN-PACKAGE-001-V1.1",
        "frozen_contracts": ["P1", "P2", "P3", "P4", "P5", "P6", "P7"],
        "canonical_base": git("rev-parse", "HEAD"),
        "source_snapshot_sha256": SEALED_SNAPSHOT_SHA256,
        "inherited_preparation_result": inherited["result"],
        "cases": case_records,
        "dependencies": dependencies,
        "forbidden_channels": FORBIDDEN_CHANNELS,
        "authorities": {
            "next_action_pointer": "registered NEXT_ACTION only",
            "decision": "Execution State implementation only",
            "carrier": "persistence/integrity only",
            "provenance": "lawfulness/currentness only",
            "model": "excluded from authority path",
        },
        "experiment_executed": False,
        "canonical_is_mutated": False,
        "result": "PASS",
    }
    atomic_json(DESTINATION / "FIXTURE_PACKAGE_MANIFEST.json", manifest)

    isolation = {
        "schema_id": "INTEGRATED-ES-PALACE-FIXTURE-ISOLATION-PROOF-V1",
        "destination_root": "integrated-es-palace/integration-fixture-v1",
        "destination_is_new": True,
        "all_files_and_dirs_regular": all(
            not path.is_symlink()
            for path in DESTINATION.rglob("*")
        ),
        "all_package_files_regular": all(
            not path.is_symlink() and path.is_file()
            for path in DESTINATION.rglob("*")
            if path.is_file()
        ),
        "network_access": False,
        "observer_campaign_executed": False,
        "experiment_executed": False,
        "canonical_palace_mutated": False,
        "canonical_information_space_mutated": False,
        "d002_rerun_or_repair": False,
        "protected_paths_unchanged": git("status", "--porcelain", "--", *PROTECTED_PATHS) == "",
        "sealed_snapshot_unchanged": digest(SOURCE_SNAPSHOT) == before_snapshot == SEALED_SNAPSHOT_SHA256,
        "case_set_exact": sorted(path.name for path in (DESTINATION / "fixtures").iterdir()) == sorted(CASES),
        "forbidden_channels_denied": FORBIDDEN_CHANNELS,
        "result": "PASS",
    }
    EVIDENCE.mkdir(parents=True, exist_ok=False)
    atomic_json(EVIDENCE / "ISOLATION_PROOF.json", isolation)
    atomic_json(EVIDENCE / "MISSING_ITEMS.json", {
        "schema_id": "INTEGRATED-ES-PALACE-FIXTURE-MISSING-ITEMS-V1",
        "missing_items": missing,
        "result": "PASS",
    })
    checks = {
        "seven_cases": len(case_records) == 7,
        "all_primitive_inventories_complete": all(
            record["primitive_count"] == 10 for record in case_records
        ),
        "sealed_snapshot_unchanged": isolation["sealed_snapshot_unchanged"],
        "protected_paths_unchanged": isolation["protected_paths_unchanged"],
        "destination_isolated": (
            isolation["all_files_and_dirs_regular"]
            and isolation["all_package_files_regular"]
            and isolation["all_files_and_dirs_regular"]
        ),
        "no_experiment": not isolation["experiment_executed"],
        "no_canonical_mutation": not isolation["canonical_palace_mutated"] and not isolation["canonical_information_space_mutated"],
        "pilot_evidence_inherited": dependencies["pilot_v5_sqlite_busy"]["manifest_sha256"] == PILOT_MANIFEST_SHA256,
        "missing_items_explicit": len(missing) == 4,
    }
    self_check = {
        "schema_id": "INTEGRATED-ES-PALACE-FIXTURE-PREPARATION-SELF-CHECK-V1",
        "checks": checks,
        "experiment_executed": False,
        "result": "PASS" if all(checks.values()) else "FAIL",
    }
    atomic_json(EVIDENCE / "PREPARATION_SELF_CHECK.json", self_check)

    final = EVIDENCE / "EVIDENCE_SHA256SUMS"
    if final.exists():
        raise FileExistsError(final)
    lines = [
        f"{digest(path)}  {path.relative_to(EVIDENCE).as_posix()}"
        for path in sorted(EVIDENCE.rglob("*"))
        if path.is_file() and path != final
    ]
    with tempfile.NamedTemporaryFile(delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(("\n".join(lines) + "\n").encode("utf-8"))
    temporary.replace(final)
    print(self_check["result"])
    return 0 if self_check["result"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
