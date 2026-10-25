#!/usr/bin/env python3
"""Write the E round artifact manifest.

Every file under the run root is hashed except:
  * `previous-attempts/` - diagnostic attempts, not final evidence;
  * `manifests/MANIFEST_SHA256.txt` - the manifest cannot contain itself;
  * `logs/manifest-verify.json` - the record produced by verify_manifest.py
    cannot be covered by the manifest it verifies (write/verify ordering).

The guarded repository paths are appended with the `after` digest recorded by
`workspace_guard.py verify`, so the manifest binds both the run artifacts and
the exact repository files the run is based on.
"""
from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

RUN_ROOT = Path(__file__).resolve().parents[1]
MANIFEST = RUN_ROOT / "manifests" / "MANIFEST_SHA256.txt"
GUARD = RUN_ROOT / "logs" / "workspace-guard-verify.json"
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
    artifacts = []
    for path in sorted(RUN_ROOT.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(RUN_ROOT).as_posix()
        if any(part in SKIP_DIRS for part in path.relative_to(RUN_ROOT).parts):
            continue
        if relative in SKIP_FILES:
            continue
        artifacts.append((sha256(path), path.stat().st_size, relative))
    guard = json.loads(GUARD.read_text(encoding="utf-8"))
    repo_root = Path(guard["repo_root"])
    guarded = []
    for change in guard["changed_files"]:
        after = change["after"]
        if not after.get("exists"):
            raise SystemExit("guarded path missing after verification: %s"
                             % after["path"])
        path = Path(after["path"])
        if not path.is_absolute():
            path = repo_root / path
        guarded.append((after["sha256"], after["size"], str(path)))
    lines = [
        "# SIMIGO E ROUND ARTIFACT MANIFEST V1",
        "# generated_utc: %s" % datetime.now(timezone.utc).isoformat(),
        "# run_root: %s" % RUN_ROOT,
        "# fields: sha256  size  relative_path",
        "# excluded: previous-attempts/ (diagnostic attempts, not final "
        "evidence); this manifest; logs/manifest-verify.json (the record that "
        "verifies this manifest)",
        "# guarded paths: after sha256 from logs/workspace-guard-verify.json",
    ]
    lines += ["%s  %d  %s" % row for row in artifacts]
    lines += [
        "",
        "# GUARDED REPO PATHS (after sha256 from logs/workspace-guard-verify.json)",
        "# fields: sha256  size  absolute_path",
    ]
    lines += ["%s  %d  %s" % row for row in guarded]
    lines += [
        "",
        "# COUNTS",
        "# artifacts: %d" % len(artifacts),
        "# guarded_repo_paths: %d" % len(guarded),
    ]
    MANIFEST.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"artifacts": len(artifacts), "guarded": len(guarded),
                      "manifest": str(MANIFEST)}, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
