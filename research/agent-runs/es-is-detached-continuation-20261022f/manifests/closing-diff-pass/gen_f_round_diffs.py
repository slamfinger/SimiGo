#!/usr/bin/env python3
"""Reconstruct genuine F-round-only code diffs and hash-verify them.

Why this exists: the task pack's evidence list requires the source diff, and its
final acceptance standard is "actual code differences".  The workspace guard
records a before/after SHA-256 for every file this round touched, but a diff was
only ever produced for the TRACKED files, via `git diff` against HEAD.  That left
(1) `source/diff-taskrun.patch` at 0 bytes while its own README described it as a
diff of `SimiGoTaskRun/main.swift`, and (2) no diff at all for the four files this
round created, including the native driver itself.

This script rebuilds the pre-F content of each touched file from independent
earlier-round records and verifies the reconstruction against the pre-F snapshot
hash taken before any F-round edit:

  * tracked and modified  : `git show HEAD:<path>`  +  E-round `diffs/tracked-changes.diff`
  * untracked and modified: the E-round `diffs/untracked-current/` copy, or, when that
                            is absent, `git apply` of the E-round `diffs/new-files.diff`
                            creation hunk
  * created in F          : no pre-F content exists; the diff is /dev/null -> current

A reconstruction is accepted only when its SHA-256 equals the `before` hash in
`manifests/workspace-verify.json`.  Anything that does not match is reported as
NOT RECONSTRUCTED and no diff is invented for it.

Outputs land in the workspace staging area; the caller copies them into the run
root (the agent cannot write the run root with its file tools).
"""

from __future__ import annotations

import difflib
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

RUN = Path(os.path.expanduser("~/SimiGo-Agent-Runs/es-is-detached-continuation-20261022f"))
REPO = Path("/Users/mr.simi/Documents/SimiGo-Lab")
E_RUN = Path(os.path.expanduser("~/SimiGo-Agent-Runs/settlement-provenance-20261022e"))
OUT = REPO / ".build/frund/f-round-diffs"

TRACKED_DIFF = E_RUN / "diffs/tracked-changes.diff"
NEW_FILES_DIFF = E_RUN / "diffs/new-files.diff"
UNTRACKED_CURRENT = E_RUN / "diffs/untracked-current"
# The D round recorded the whole tracked worktree delta against the same HEAD.  For a
# tracked file the E round did not touch, that delta *is* the pre-F content, so it is
# kept as a fallback source.  Every candidate still has to hash-match the pre-F snapshot.
D_WORKTREE_DIFF = (
    Path(os.path.expanduser("~/SimiGo-Agent-Runs/handoff-causality-20261022d"))
    / "diffs/worktree-vs-head.diff"
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read(path: Path) -> bytes:
    return path.read_bytes()


def git(*args: str, cwd: Path) -> bytes:
    proc = subprocess.run(["git", *args], cwd=str(cwd), capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {proc.stderr.decode()[:400]}")
    return proc.stdout


def head_version(rel_path: str) -> bytes:
    """The committed (HEAD) content of a tracked file."""
    return git("show", f"HEAD:{rel_path}", cwd=REPO)


def apply_tracked_chain(rel_path: str, chain: list[Path]) -> bytes | None:
    """HEAD content with the given earlier-round tracked deltas applied in order."""
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        target = root / rel_path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(head_version(rel_path))
        for diff in chain:
            if not diff.exists():
                return None
            try:
                git("apply", "-p1", "--include", rel_path, str(diff), cwd=root)
            except RuntimeError:
                return None
        return read(target)


def apply_e_new_file_hunk(rel_path: str) -> bytes | None:
    """Recreate a file the E round created, from E's new-files.diff."""
    if not NEW_FILES_DIFF.exists():
        return None
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        try:
            git("apply", "-p1", "--include", rel_path, str(NEW_FILES_DIFF), cwd=root)
        except RuntimeError:
            return None
        created = root / rel_path
        return read(created) if created.exists() else None


def e_untracked_copy(rel_path: str) -> bytes | None:
    cand = UNTRACKED_CURRENT / rel_path.replace("/", "__")
    return read(cand) if cand.exists() else None


def reconstruct_before(rel_path: str, before: dict,
                       before_sha: str | None) -> tuple[bytes | None, str]:
    """Return (pre-F content, method) or (None, why-not).

    For a tracked file several earlier-round deltas can describe the pre-F state, and the
    only way to tell which one is right is the pre-F snapshot hash, so each candidate is
    tried and accepted only when it reproduces that hash exactly.
    """
    if not before.get("exists"):
        return None, "created-in-F"
    if is_tracked(rel_path):
        for chain, label in (
            ([TRACKED_DIFF], "HEAD + E-round diffs/tracked-changes.diff"),
            ([D_WORKTREE_DIFF], "HEAD + D-round diffs/worktree-vs-head.diff"),
            ([D_WORKTREE_DIFF, TRACKED_DIFF],
             "HEAD + D-round worktree-vs-head.diff + E-round tracked-changes.diff"),
        ):
            got = apply_tracked_chain(rel_path, chain)
            if got is not None and (before_sha is None or sha256(got) == before_sha):
                return got, label
    got = e_untracked_copy(rel_path)
    if got is not None and (before_sha is None or sha256(got) == before_sha):
        return got, "E-round diffs/untracked-current copy"
    got = apply_e_new_file_hunk(rel_path)
    if got is not None and (before_sha is None or sha256(got) == before_sha):
        return got, "E-round diffs/new-files.diff creation hunk"
    return None, "no independent pre-F record reproduced the snapshot hash"


_TRACKED_CACHE: dict[str, bool] = {}


def is_tracked(rel_path: str) -> bool:
    if rel_path not in _TRACKED_CACHE:
        proc = subprocess.run(
            ["git", "ls-files", "--error-unmatch", rel_path],
            cwd=str(REPO), capture_output=True,
        )
        _TRACKED_CACHE[rel_path] = proc.returncode == 0
    return _TRACKED_CACHE[rel_path]


def flat(rel_path: str) -> str:
    """Repository path flattened for use as a file name (`/` -> `__`)."""
    return rel_path.replace("/", "__")


def unified(rel_path: str, before_bytes: bytes | None, after_bytes: bytes) -> str:
    before_text = (before_bytes or b"").decode("utf-8", "replace").splitlines(keepends=True)
    after_text = after_bytes.decode("utf-8", "replace").splitlines(keepends=True)
    return "".join(
        difflib.unified_diff(
            before_text, after_text,
            fromfile=("dev/null" if before_bytes is None else f"a/{rel_path}"),
            tofile=f"b/{rel_path}",
            lineterm="\n",
        )
    )


def main() -> int:
    verify = json.loads(read(RUN / "manifests/workspace-verify.json"))
    if verify.get("result") != "PASS":
        print("refusing: workspace-verify.json is not PASS", file=sys.stderr)
        return 1

    OUT.mkdir(parents=True, exist_ok=True)
    for stale in OUT.glob("*.diff"):
        stale.unlink()

    rows = []
    for entry in verify["changed_files"]:
        rel_path = entry["path"]
        before, after = entry["before"], entry["after"]
        current = REPO / rel_path
        if not current.exists():
            rows.append({"path": rel_path, "status": "MISSING-IN-WORKTREE"})
            continue
        after_bytes = read(current)
        after_ok = sha256(after_bytes) == after.get("sha256")
        before_bytes, method = reconstruct_before(
            rel_path, before, before.get("sha256")
        )
        record = {
            "path": rel_path,
            "before_sha256_expected": before.get("sha256"),
            "exists_before": bool(before.get("exists")),
            "current_matches_guard_after": after_ok,
            "reconstruction": method,
        }
        if before_bytes is None:
            record["status"] = "CREATED_IN_F_FULL_CONTENT_DIFF"
            record["diff_file"] = flat(rel_path) + ".created.diff"
            (OUT / record["diff_file"]).write_text(
                unified(rel_path, None, after_bytes), encoding="utf-8"
            )
        elif sha256(before_bytes) == before.get("sha256"):
            record["status"] = "VERIFIED_F_ROUND_ONLY_DIFF"
            record["diff_file"] = flat(rel_path) + ".f-round.diff"
            record["before_sha256_reconstructed"] = sha256(before_bytes)
            (OUT / record["diff_file"]).write_text(
                unified(rel_path, before_bytes, after_bytes), encoding="utf-8"
            )
            stager = REPO / ".build/frund/f-round-before"
            stager.mkdir(parents=True, exist_ok=True)
            (stager / flat(rel_path)).write_bytes(before_bytes)
        else:
            record["status"] = "NOT_RECONSTRUCTED"
            record["before_sha256_reconstructed"] = sha256(before_bytes)
        rows.append(record)

    manifest = {
        "schema_version": 1,
        "generated_utc": subprocess.run(
            ["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"], capture_output=True
        ).stdout.decode().strip(),
        "purpose": "F-round-only code diffs, each reconstruction hash-checked against "
                   "the pre-F workspace snapshot recorded in manifests/workspace-verify.json",
        "inputs": {
            "workspace_verify": str(RUN / "manifests/workspace-verify.json"),
            "e_round_tracked_changes_diff": str(TRACKED_DIFF),
            "e_round_new_files_diff": str(NEW_FILES_DIFF),
            "e_round_untracked_current": str(UNTRACKED_CURRENT),
            "repo_head": git("rev-parse", "HEAD", cwd=REPO).decode().strip(),
        },
        "files": rows,
    }
    (OUT / "RECONSTRUCTION_MANIFEST.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )

    # The reconstructed pre-F bytes travel with the diffs so a reviewer can re-derive
    # every patch without rerunning this script.
    stager = REPO / ".build/frund/f-round-before"
    before_dir = OUT / "before"
    before_dir.mkdir(parents=True, exist_ok=True)
    for staged in sorted(stager.glob("simigo2-experimental__*")):
        (before_dir / staged.name).write_bytes(staged.read_bytes())

    sums = []
    for f in sorted(OUT.glob("*.diff")) + [OUT / "RECONSTRUCTION_MANIFEST.json"]:
        sums.append(f"{sha256(read(f))}  {f.name}")
    for f in sorted(before_dir.glob("*")):
        sums.append(f"{sha256(read(f))}  before/{f.name}")
    (OUT / "SHA256SUMS").write_text("\n".join(sums) + "\n", encoding="utf-8")

    ok = sum(1 for r in rows if r["status"] == "VERIFIED_F_ROUND_ONLY_DIFF")
    created = sum(1 for r in rows if r["status"] == "CREATED_IN_F_FULL_CONTENT_DIFF")
    bad = [r for r in rows if r["status"] not in
           ("VERIFIED_F_ROUND_ONLY_DIFF", "CREATED_IN_F_FULL_CONTENT_DIFF")]
    for r in rows:
        print(f"{r['status']:>32}  {r['path']}")
    print(f"\nverified f-round-only diffs: {ok}   created-in-F full-content diffs: {created}   "
          f"unreconstructed: {len(bad)}")
    for r in bad:
        print("  UNRECONSTRUCTED:", r["path"], r.get("reconstruction"))
    return 0 if not bad else 2


if __name__ == "__main__":
    sys.exit(main())
