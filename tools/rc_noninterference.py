#!/usr/bin/env python3
"""Snapshot protected user resources so a test run can PROVE non-interference.

Only paths under `--real-root` (defaults: the managed `~/.simigo` root and the App
Support state directory) can ever be reported as a user-state write. `--reference-root`
entries (default: the HF cache) are fingerprinted to show they did not move, but are
not counted as user state.

Small files are content-hashed; files above `--hash-limit` and everything under a
reference root degrade to (path, bytes, mtime_ns) fingerprints, which still detects
added / removed / rewritten files.

usage:
  rc_noninterference.py --phase NAME --out FILE
      [--real-root PATH]... [--reference-root PATH]... [--hash-limit BYTES]

exit: 0 ok · 3 unusable layout (no HOME, relative root, output inside a real root)
"""
import argparse, hashlib, json, os, sys, time

HASH_LIMIT_DEFAULT = 8 * 1024 * 1024


def sha(path, limit):
    try:
        size = os.path.getsize(path)
        if size > limit:
            return "TOO_LARGE:size=%d" % size
        with open(path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except Exception as e:                                    # noqa: BLE001 - recorded, not raised
        return "ERR:%s" % e


def entry(path, role, hash_limit):
    out = {"path": path, "role": role, "exists": os.path.exists(path)}
    if not out["exists"]:
        return out
    if os.path.isdir(path):
        rec, total = [], 0
        for root, dirs, files in os.walk(path):
            dirs.sort()
            for fn in sorted(files):
                fp = os.path.join(root, fn)
                try:
                    st = os.stat(fp)
                except OSError:
                    continue
                digest = None
                if role == "real_state" and st.st_size <= hash_limit:
                    digest = sha(fp, hash_limit)
                rec.append({"rel": os.path.relpath(fp, path), "bytes": st.st_size,
                            "mtime_ns": st.st_mtime_ns, "sha256": digest})
                total += st.st_size
        out.update({"files": len(rec), "bytes": total, "fingerprints": rec})
        return out
    st = os.stat(path)
    out.update({"bytes": st.st_size, "mtime_ns": st.st_mtime_ns,
                "sha256": sha(path, hash_limit) if role == "real_state" else "PATH_ONLY"})
    return out


def under(path, root):
    path, root = os.path.abspath(path), os.path.abspath(root)
    return path == root or path.startswith(root.rstrip("/") + "/")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--real-root", action="append", default=[])
    ap.add_argument("--reference-root", action="append", default=[])
    ap.add_argument("--hash-limit", type=int, default=HASH_LIMIT_DEFAULT)
    a = ap.parse_args()

    home = os.environ.get("HOME", "")
    if not home.startswith("/"):
        sys.stderr.write("rc_noninterference: HOME is not an absolute path; refusing\n")
        sys.exit(3)

    real = a.real_root or [
        os.path.join(home, ".simigo"),
        os.path.join(home, "Library", "Application Support", "SimiGo"),
        # UserDefaults.standard persists these bundle/app preference domains.
        # Include the current bundle identifier and the legacy short name.
        os.path.join(home, "Library", "Preferences", "SwiftUI.SimiGo.plist"),
        os.path.join(home, "Library", "Preferences", "SimiGo.plist"),
    ]
    ref = a.reference_root or [os.environ.get("HF_HOME", os.path.join(home, ".cache", "huggingface"))]

    roots = []
    for group, paths in (("real_state", real), ("reference", ref)):
        for p in paths:
            ap_ = os.path.abspath(os.path.expanduser(p))
            if not os.path.isabs(ap_):
                sys.stderr.write("rc_noninterference: refusing relative root %r\n" % p)
                sys.exit(3)
            roots.append((ap_, group))

    out = os.path.abspath(a.out)
    for root, group in roots:
        if group == "real_state" and under(out, root):
            sys.stderr.write("rc_noninterference: snapshot output sits inside a real root"
                             " (%s); it would count as a write\n" % root)
            sys.exit(3)
    if not os.path.isdir(os.path.dirname(out)):
        sys.stderr.write("rc_noninterference: output directory missing\n")
        sys.exit(3)

    snap = {"phase": a.phase, "taken_at": time.strftime("%FT%T%z"),
            "hash_limit": a.hash_limit,
            "real_roots": [r for r, g in roots if g == "real_state"],
            "reference_roots": [r for r, g in roots if g == "reference"],
            "entries": [entry(p, g, a.hash_limit) for p, g in roots]}
    with open(out, "w") as f:
        json.dump(snap, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print(json.dumps({"phase": a.phase, "out": out,
                      "real_roots": snap["real_roots"],
                      "entries": [{"path": e["path"], "role": e["role"],
                                   "exists": e["exists"], "files": e.get("files"),
                                   "bytes": e.get("bytes")} for e in snap["entries"]]}, indent=1))


if __name__ == "__main__":
    main()
