#!/usr/bin/env python3
"""Snapshot/verify repository boundaries for the SimiGo autonomous experiment.

This helper never edits the repository. It hashes tracked and non-ignored
untracked files, fingerprints staged changes, and refuses changes to frozen
paths even if they accidentally match an allowed-change glob.
"""
from __future__ import annotations
import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone


def run_git(root: Path, *args: str, binary: bool = False):
    cp = subprocess.run(["git", *args], cwd=root, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, check=False)
    if cp.returncode:
        raise RuntimeError(f"git {' '.join(args)} failed: {cp.stderr.decode(errors='replace')}")
    return cp.stdout if binary else cp.stdout.decode("utf-8", errors="surrogateescape").strip()


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def staged_fingerprint(root: Path) -> str:
    return sha_bytes(run_git(root, "diff", "--cached", "--binary", binary=True))


def file_record(path: Path, root: Path) -> dict:
    rel = path.relative_to(root).as_posix()
    try:
        st = path.lstat()
    except FileNotFoundError:
        return {"path": rel, "exists": False}
    rec = {"path": rel, "exists": True, "mode": st.st_mode & 0o7777, "size": st.st_size}
    if path.is_symlink():
        rec["kind"] = "symlink"
        rec["sha256"] = sha_bytes(os.readlink(path).encode())
    elif path.is_file():
        rec["kind"] = "file"
        h = hashlib.sha256()
        with path.open("rb") as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b""):
                h.update(chunk)
        rec["sha256"] = h.hexdigest()
    elif path.is_dir():
        rec["kind"] = "dir"
        rec["sha256"] = None
    else:
        rec["kind"] = "other"
        rec["sha256"] = None
    return rec


def enumerate_paths(root: Path) -> list[str]:
    tracked = run_git(root, "ls-files", "-z", binary=True).decode("utf-8", errors="surrogateescape").split("\0")
    untracked = run_git(root, "ls-files", "--others", "--exclude-standard", "-z", binary=True).decode("utf-8", errors="surrogateescape").split("\0")
    names = {x for x in tracked + untracked if x}
    # Include tracked files missing from disk in the manifest too.
    return sorted(names)


def frozen_reason(rel: str, existed_before: bool = True) -> str | None:
    p = rel.strip("/")
    parts = p.split("/")
    if "run-20261022a" in parts or any("run-20261022a" in x for x in parts):
        return "protected run-20261022a"
    if p.startswith("docs/02-evidence/") or p == "docs/02-evidence":
        # Existing evidence is frozen. A path absent from the pre-round
        # snapshot is new evidence: it may be added only through an explicit
        # --allow-change entry, never by matching this rule.
        return "protected existing evidence tree" if existed_before else None
    if p.startswith("docs/00-governance/") or p == "docs/00-governance":
        return "protected governance/frozen-set tree"
    if "g2" in parts or "G2" in parts:
        return "protected G2 path"
    if p.startswith("docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_SRS_VAL_01_DESIGN_V0.") and "_DELIVERY_20261007.md" in p:
        return "protected restored SRS-VAL-01 DELIVERY file"
    if p.startswith("docs/09-archive/"):
        return "protected archive tree"
    return None


def snapshot(root: Path, out: Path):
    root = root.resolve()
    toplevel = Path(run_git(root, "rev-parse", "--show-toplevel")).resolve()
    if toplevel != root:
        raise RuntimeError(f"--repo must be the Git root (found {toplevel})")
    paths = enumerate_paths(root)
    recs = [file_record(root / rel, root) for rel in paths]
    status = run_git(root, "status", "--porcelain=v1", "--branch", "--untracked-files=all")
    data = {
        "schema_version": 1,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "repo_root": str(root),
        "head": run_git(root, "rev-parse", "HEAD"),
        "branch": run_git(root, "branch", "--show-current"),
        "staged_diff_sha256": staged_fingerprint(root),
        "status_porcelain": status,
        "files": recs,
        "protected_path_count": sum(1 for x in recs if frozen_reason(x["path"])),
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"snapshot": str(out), "head": data["head"], "branch": data["branch"],
                      "files_hashed": len(recs), "protected_paths": data["protected_path_count"],
                      "staged_diff_sha256": data["staged_diff_sha256"]}, ensure_ascii=False, indent=2))


def allowed(rel: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatchcase(rel, p) for p in patterns)


def verify(root: Path, before: Path, out: Path, allow_patterns: list[str]):
    root = root.resolve()
    old = json.loads(before.read_text())
    if Path(old["repo_root"]).resolve() != root:
        raise RuntimeError("snapshot repo_root does not match --repo")
    new_paths = enumerate_paths(root)
    new = {rel: file_record(root / rel, root) for rel in new_paths}
    old_files = {r["path"]: r for r in old["files"]}
    issues = []
    new_head = run_git(root, "rev-parse", "HEAD")
    new_branch = run_git(root, "branch", "--show-current")
    new_staged = staged_fingerprint(root)
    if new_head != old["head"]:
        issues.append({"kind": "HEAD_CHANGED", "before": old["head"], "after": new_head})
    if new_branch != old["branch"]:
        issues.append({"kind": "BRANCH_CHANGED", "before": old["branch"], "after": new_branch})
    if new_staged != old["staged_diff_sha256"]:
        issues.append({"kind": "STAGED_DIFF_CHANGED", "before": old["staged_diff_sha256"], "after": new_staged})
    all_paths = sorted(set(old_files) | set(new))
    changed = []
    for rel in all_paths:
        a = old_files.get(rel, {"path": rel, "exists": False})
        b = new.get(rel, {"path": rel, "exists": False})
        if a.get("exists") == b.get("exists") and a.get("sha256") == b.get("sha256") and a.get("mode") == b.get("mode"):
            continue
        row = {"path": rel, "before": a, "after": b}
        changed.append(row)
        reason = frozen_reason(rel, existed_before=bool(a.get("exists")))
        if reason:
            issues.append({"kind": "PROTECTED_PATH_CHANGED", "path": rel, "reason": reason})
        elif not allowed(rel, allow_patterns):
            issues.append({"kind": "CHANGE_OUTSIDE_ALLOWLIST", "path": rel})
    report = {
        "schema_version": 1,
        "verified_utc": datetime.now(timezone.utc).isoformat(),
        "repo_root": str(root),
        "head_unchanged": new_head == old["head"],
        "branch_unchanged": new_branch == old["branch"],
        "staged_diff_unchanged": new_staged == old["staged_diff_sha256"],
        "changed_file_count": len(changed),
        "changed_files": changed,
        "issues": issues,
        "result": "PASS" if not issues else "FAIL",
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"result": report["result"], "changed_file_count": len(changed),
                      "issues": issues, "report": str(out)}, ensure_ascii=False, indent=2))
    return 0 if not issues else 2


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("snapshot")
    s.add_argument("--repo", required=True, type=Path)
    s.add_argument("--out", required=True, type=Path)
    v = sub.add_parser("verify")
    v.add_argument("--repo", required=True, type=Path)
    v.add_argument("--before", required=True, type=Path)
    v.add_argument("--out", required=True, type=Path)
    v.add_argument("--allow-change", action="append", default=[], help="repeatable fnmatch glob of allowed source/test paths")
    args = p.parse_args()
    try:
        if args.cmd == "snapshot":
            snapshot(args.repo, args.out)
            return 0
        return verify(args.repo, args.before, args.out, args.allow_change)
    except Exception as e:
        print(f"workspace_guard: ERROR: {e}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
