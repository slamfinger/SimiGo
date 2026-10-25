#!/usr/bin/env python3
"""Verify the E round artifact manifest against the current disk state.

Checks every listed digest and size, checks the guarded repository paths, and
detects unlisted run-root files (drift after the manifest was written). The
manifest and this verification record are excluded by construction.
"""
from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

RUN_ROOT = Path(__file__).resolve().parents[1]
MANIFEST = RUN_ROOT / "manifests" / "MANIFEST_SHA256.txt"
OUTPUT = RUN_ROOT / "logs" / "manifest-verify.json"
SKIP_DIRS = {"previous-attempts"}
SKIP_FILES = {
    "manifests/MANIFEST_SHA256.txt",
    "logs/manifest-verify.json",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    entries = []
    for line in MANIFEST.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        digest, size, path = line.split("  ", 2)
        entries.append({"sha256": digest, "size": int(size), "path": path})
    failures = []
    listed = set()
    for entry in entries:
        path = Path(entry["path"])
        absolute = path if path.is_absolute() else RUN_ROOT / path
        if not absolute.is_file():
            failures.append({"path": entry["path"], "issue": "missing"})
            continue
        actual_size = absolute.stat().st_size
        actual_digest = sha256(absolute)
        if actual_size != entry["size"]:
            failures.append({"path": entry["path"], "issue": "size",
                             "expected": entry["size"], "actual": actual_size})
        if actual_digest != entry["sha256"]:
            failures.append({"path": entry["path"], "issue": "sha256",
                             "expected": entry["sha256"],
                             "actual": actual_digest})
        if not path.is_absolute():
            listed.add(path.as_posix())
    current = set()
    for path in RUN_ROOT.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(RUN_ROOT).as_posix()
        if any(part in SKIP_DIRS for part in path.relative_to(RUN_ROOT).parts):
            continue
        if relative in SKIP_FILES:
            continue
        current.add(relative)
    unlisted = sorted(current - listed)
    missing_from_disk = sorted(listed - current)
    report = {
        "schema_id": "SIMIGO-E-ROUND-MANIFEST-VERIFY-V1",
        "verified_utc": datetime.now(timezone.utc).isoformat(),
        "manifest": str(MANIFEST),
        "manifest_sha256": sha256(MANIFEST),
        "entry_count": len(entries),
        "artifact_count": len([entry for entry in entries
                               if not Path(entry["path"]).is_absolute()]),
        "guarded_path_count": len([entry for entry in entries
                                   if Path(entry["path"]).is_absolute()]),
        "failures": failures,
        "unlisted_run_root_files": unlisted,
        "listed_but_absent": missing_from_disk,
        "result": "PASS" if not failures and not unlisted
                  and not missing_from_disk else "FAIL",
    }
    OUTPUT.write_text(json.dumps(report, indent=1, sort_keys=True) + "\n",
                      encoding="utf-8")
    print(json.dumps({key: report[key] for key in (
        "result", "entry_count", "artifact_count", "guarded_path_count",
        "manifest_sha256", "failures", "unlisted_run_root_files")},
        ensure_ascii=False, indent=1))
    return 0 if report["result"] == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())
