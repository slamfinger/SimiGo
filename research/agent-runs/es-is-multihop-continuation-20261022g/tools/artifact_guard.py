#!/usr/bin/env python3
"""Hash prior experiment roots so a new run cannot silently rewrite old evidence.

This is read-only. It records file bytes, symlinks, modes and sizes beneath explicit
historical roots, does not follow symlink directories, and writes snapshots only to
an external output path supplied by the caller.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
from datetime import datetime, timezone


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_record(path: Path, root: Path) -> dict:
    rel = path.relative_to(root).as_posix()
    try:
        st = path.lstat()
    except FileNotFoundError:
        return {"path": rel, "exists": False}
    rec = {"path": rel, "exists": True, "mode": st.st_mode & 0o7777, "size": st.st_size}
    if path.is_symlink():
        rec.update(kind="symlink", sha256=sha(os.readlink(path).encode("utf-8", errors="surrogateescape")))
    elif path.is_file():
        h = hashlib.sha256()
        with path.open("rb") as f:
            for chunk in iter(lambda: f.read(1024 * 1024), b""):
                h.update(chunk)
        rec.update(kind="file", sha256=h.hexdigest())
    elif path.is_dir():
        rec.update(kind="dir", sha256=None)
    else:
        rec.update(kind="other", sha256=None)
    return rec


def enumerate_root(root: Path) -> list[Path]:
    found = []
    for current, dirs, files in os.walk(root, followlinks=False):
        cp = Path(current)
        # Treat symlink dirs as entries, not traversable subtrees.
        keep_dirs = []
        for d in dirs:
            p = cp / d
            found.append(p)
            if not p.is_symlink():
                keep_dirs.append(d)
        dirs[:] = keep_dirs
        found.extend(cp / f for f in files)
    return sorted(set(found), key=lambda p: p.as_posix())


def snapshot(roots: list[Path], out: Path):
    rows = []
    for raw in roots:
        root = raw.expanduser().resolve()
        if not root.exists() or not root.is_dir():
            rows.append({"root": str(root), "exists": False, "files": []})
            continue
        rows.append({"root": str(root), "exists": True,
                     "files": [file_record(p, root) for p in enumerate_root(root)]})
    data = {"schema_version": 1, "created_utc": datetime.now(timezone.utc).isoformat(), "roots": rows}
    out = out.expanduser().resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"snapshot": str(out), "root_count": len(rows),
                      "existing_roots": sum(bool(r["exists"]) for r in rows),
                      "file_entries": sum(len(r["files"]) for r in rows)}, indent=2))


def verify(before: Path, out: Path):
    prior = json.loads(before.expanduser().read_text())
    issues = []
    results = []
    for row in prior["roots"]:
        root = Path(row["root"])
        existed_then = row["exists"]
        exists_now = root.exists() and root.is_dir()
        if existed_then != exists_now:
            issues.append({"root": str(root), "kind": "ROOT_EXISTENCE_CHANGED", "before": existed_then, "after": exists_now})
            results.append({"root": str(root), "changed": True, "changed_count": 1})
            continue
        if not existed_then:
            results.append({"root": str(root), "changed": False, "changed_count": 0})
            continue
        old = {f["path"]: f for f in row["files"]}
        now = {p.relative_to(root).as_posix(): file_record(p, root) for p in enumerate_root(root)}
        changed = []
        for rel in sorted(set(old) | set(now)):
            a, b = old.get(rel, {"path": rel, "exists": False}), now.get(rel, {"path": rel, "exists": False})
            if (a.get("exists"), a.get("sha256"), a.get("mode"), a.get("size"), a.get("kind")) == (b.get("exists"), b.get("sha256"), b.get("mode"), b.get("size"), b.get("kind")):
                continue
            changed.append(rel)
            issues.append({"root": str(root), "path": rel, "kind": "HISTORICAL_ARTIFACT_CHANGED", "before": a, "after": b})
        results.append({"root": str(root), "changed": bool(changed), "changed_count": len(changed), "changed_paths": changed})
    report = {"schema_version": 1, "verified_utc": datetime.now(timezone.utc).isoformat(),
              "snapshot": str(before.expanduser().resolve()), "result": "PASS" if not issues else "FAIL",
              "roots": results, "issues": issues}
    out = out.expanduser().resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"result": report["result"], "issues": len(issues), "report": str(out)}, indent=2))
    return 0 if not issues else 2


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("snapshot")
    s.add_argument("--out", required=True, type=Path)
    s.add_argument("roots", nargs="+", type=Path)
    v = sub.add_parser("verify")
    v.add_argument("--before", required=True, type=Path)
    v.add_argument("--out", required=True, type=Path)
    a = p.parse_args()
    try:
        if a.cmd == "snapshot":
            snapshot(a.roots, a.out)
            return 0
        return verify(a.before, a.out)
    except Exception as e:
        print(f"artifact_guard: ERROR: {e}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
