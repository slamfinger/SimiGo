#!/usr/bin/env python3
"""Build the frozen G3 snapshot and bind the produced artifacts to it.

G7b is not satisfied by a source manifest alone: a manifest says what was
reviewed, not what ran. This script closes that gap for the artifacts that
exist today:

  1. compute the manifest (with archives) and record `source_sha256` BEFORE the
     build;
  2. run `swift build` and `swift build --build-tests`;
  3. recompute the manifest and refuse if `source_sha256` moved during the build
     (a concurrent edit would otherwise let the stamp name the wrong sources);
  4. attach `artifact_stamp = {source_sha256, artifacts_sha256, commands, ...}`
     so the final manifest's binary hashes are bound to that digest.

mtime ordering is deliberately NOT the binding. A file save updates mtime
without changing a byte, and an incremental build may not relink; the stamp is
content-based and survives both.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import g3_runner_manifest as M

PACKAGE = M.ROOT / "simigo2-experimental"
STAMP_SCHEMA = "G3-D1-BUILD-STAMP-V1"


def run_build(command: list[str]) -> dict:
    proc = subprocess.run(
        command,
        cwd=PACKAGE,
        capture_output=True,
        text=True,
        check=False,
    )
    return {
        "command": " ".join(command),
        "exit": proc.returncode,
        "stdout_tail": proc.stdout.strip().splitlines()[-5:],
        "stderr_tail": proc.stderr.strip().splitlines()[-5:],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True, help="manifest to write")
    parser.add_argument("--bundle-dir", type=Path, help="archive directory")
    parser.add_argument("--require-artifacts", action="store_true")
    parser.add_argument("--require-boundary", action="store_true")
    parser.add_argument("--require-execution-binding", action="store_true")
    args = parser.parse_args()

    out: Path = args.out
    bundle_dir = args.bundle_dir or out.parent / "archives"
    bundle_dir = (
        (M.ROOT / bundle_dir).resolve()
        if not bundle_dir.is_absolute()
        else bundle_dir.resolve()
    )

    pre = M.build_manifest(bundle_dir, write_archives=True)
    source_digest = pre["source_sha256"]
    print(f"pre-build source_sha256 {source_digest}")

    # The stamped artifacts live under `.build/out` (ARTIFACTS in the manifest).
    # A plain `swift build` writes to `.build/debug` and would leave the stamped
    # paths untouched, so the stamp would bind binaries this build never made.
    # Pinning the scratch path makes "the artifact that exists" and "the artifact
    # this command just produced" the same file by construction.
    builds = [
        run_build(["swift", "build", "--scratch-path", ".build/out"]),
        run_build(["swift", "build", "--build-tests", "--scratch-path", ".build/out"]),
    ]
    for build in builds:
        print(f"{build['command']} -> exit {build['exit']}")
    if any(build["exit"] != 0 for build in builds):
        for build in builds:
            for line in build["stderr_tail"]:
                print(f"  {line}")
        print("BUILD FAILED: no stamp written, manifest not advanced")
        return 2

    post = M.build_manifest(bundle_dir, write_archives=False)
    if post["source_sha256"] != source_digest:
        print(
            "SOURCE DRIFT DURING BUILD: "
            f"{source_digest} -> {post['source_sha256']}; refusing to stamp"
        )
        return 3

    artifacts = {
        art["path"]: art.get("sha256")
        for art in post["artifacts"]
        if art.get("expected", True)
    }
    absent = [
        art["path"]
        for art in post["artifacts"]
        if art.get("expected", True) and not art.get("present")
    ]
    if absent:
        print("EXPECTED ARTIFACTS ABSENT")
        for path in absent:
            print(f"  - {path}")
        return 2

    stamp = {
        "schema_id": STAMP_SCHEMA,
        "source_sha256": source_digest,
        "source_sha256_matches": True,
        "artifacts_sha256": artifacts,
        "commands": builds,
        "toolchain": M.toolchain(),
        "built_at_utc": M.utc(datetime.now(tz=timezone.utc).timestamp()),
        "builder": "tools/g3_build_stamped.py",
    }

    final = M.build_manifest(bundle_dir, write_archives=False, artifact_stamp=stamp)
    if final["source_sha256"] != source_digest:
        print("SOURCE DRIFT AFTER STAMP: refusing to write")
        return 3

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(
        json.dumps(final, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    sidecar = out.with_suffix(out.suffix + ".sha256")
    sidecar.write_text(f"{final['runner_sha256']}  {out.name}\n", encoding="utf-8")
    print(f"wrote {out}")
    print(f"wrote {sidecar}")
    print(f"source_revision {final['source_revision']}")
    print(f"source_sha256   {final['source_sha256']}")
    print(f"runner_sha256   {final['runner_sha256']}")
    for condition in final["open_conditions"]:
        print(f"open            {condition}")
    return M.requirement_checks(
        final,
        args.require_artifacts,
        args.require_boundary,
        args.require_execution_binding,
    )


if __name__ == "__main__":
    raise SystemExit(main())
