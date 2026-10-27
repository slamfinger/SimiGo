#!/usr/bin/env python3
"""B-7 pre/post inventory: build identity, app identity, DB counters,
prefix-pool / branch-checkpoints listings, trace offset, process + system state.

Usage: snapshot.py <label> [--db-backup]
Writes <label>.json next to this script. Read-only against ~/.simigo except the
optional online DB backup.
"""
import hashlib, json, os, sqlite3, subprocess, sys, time

REPO = "/Users/mr.simi/Documents/SimiGo"
HOME = os.path.expanduser("~")
SIMIGO = os.path.join(HOME, ".simigo")
DB = os.path.join(SIMIGO, "simigo.sqlite3")
TRACE = os.path.join(SIMIGO, "logs/native_mlx_trace.log")
OUT = os.path.dirname(os.path.abspath(__file__))

LABEL = sys.argv[1] if len(sys.argv) > 1 else "snapshot"
DO_BACKUP = "--db-backup" in sys.argv


def run(cmd, cwd=None):
    return subprocess.run(cmd, cwd=cwd, capture_output=True, text=True).stdout


def sha(path, chunk=1 << 20):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def inventory(root):
    if not os.path.isdir(root):
        return {"present": False}
    rows = []
    total = 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(filenames):
            p = os.path.join(dirpath, name)
            st = os.lstat(p)
            rel = os.path.relpath(p, root)
            rows.append("%s|%d|%d|%d" % (rel, st.st_size, st.st_mtime_ns, st.st_ino))
            total += st.st_size
    digest = hashlib.sha256("\n".join(rows).encode()).hexdigest()
    return {
        "present": True, "file_count": len(rows), "total_bytes": total,
        "listing_sha256": digest, "files": rows,
    }


def db_summary():
    con = sqlite3.connect("file:%s?mode=ro" % DB, uri=True)
    con.row_factory = sqlite3.Row
    def q(sql):
        try:
            return [dict(r) for r in con.execute(sql).fetchall()]
        except Exception as e:
            return [{"error": repr(e)}]
    out = {
        "schema_tables": q(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"),
        "counts": q("""
            SELECT
              (SELECT COUNT(*) FROM settlements) AS settlements,
              (SELECT COUNT(*) FROM execution_states) AS states,
              (SELECT COUNT(*) FROM settlement_bindings) AS bindings,
              (SELECT COUNT(*) FROM file_contents) AS file_contents,
              (SELECT COUNT(*) FROM roots) AS roots;
        """),
        "settlements_by_status": q(
            "SELECT validation_status, validity, COUNT(*) AS n FROM settlements "
            "GROUP BY validation_status, validity;"),
        "file_contents_by_root": q(
            "SELECT root_id, COUNT(*) AS n FROM file_contents GROUP BY root_id;"),
        "roots": q("SELECT root_id, category, display_name FROM roots ORDER BY root_id;"),
        "reuse_contracts": q("SELECT COUNT(*) AS n FROM settlement_reuse_contracts;")
            if any(r.get("name") == "settlement_reuse_contracts"
                   for r in q("SELECT name FROM sqlite_master WHERE type='table';"))
            else [{"n": None, "note": "table absent"}],
        "consumptions": q("SELECT COUNT(*) AS n FROM settlement_consumptions;")
            if any(r.get("name") == "settlement_consumptions"
                   for r in q("SELECT name FROM sqlite_master WHERE type='table';"))
            else [{"n": None, "note": "table absent"}],
    }
    con.close()
    return out


def app_identity():
    exe = "/Applications/SimiGo.app/Contents/MacOS/SimiGo"
    plist = "/Applications/SimiGo.app/Contents/Info.plist"
    out = {}
    if os.path.exists(exe):
        st = os.stat(exe)
        out["exe_sha256"] = sha(exe)
        out["exe_mtime"] = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(st.st_mtime))
    if os.path.exists(plist):
        out["plist"] = json.loads(run(
            ["plutil", "-convert", "json", "-o", "-", plist]) or "{}")
        out["plist"] = {k: out["plist"].get(k) for k in (
            "CFBundleShortVersionString", "CFBundleVersion", "CFBundleIdentifier")}
    out["codesign"] = run(["codesign", "-dv", "--verbose=2",
                           "/Applications/SimiGo.app"]).strip()[-800:]
    return out


def process_state():
    ps = run(["pgrep", "-fl", "/Applications/SimiGo.app/Contents/MacOS/SimiGo"]).strip()
    listeners = run(["bash", "-lc",
                     "lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | grep -i simigo || true"]).strip()
    return {"pgrep": ps, "listeners": listeners}


def system_state():
    swap = run(["sysctl", "-n", "vm.swapusage"]).strip()
    load = run(["sysctl", "-n", "vm.loadavg"]).strip()
    return {"swapusage": swap, "loadavg": load}


status = run(["git", "-C", REPO, "status", "--porcelain"])
diff = subprocess.run(["bash", "-lc", "git -C %s diff | shasum -a 256" % REPO],
                      capture_output=True, text=True).stdout.strip()
report = {
    "label": LABEL,
    "captured_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "worktree": {
        "head": run(["git", "-C", REPO, "rev-parse", "HEAD"]).strip(),
        "porcelain_sha256": hashlib.sha256(status.encode()).hexdigest(),
        "porcelain_lines": len([l for l in status.splitlines() if l.strip()]),
        "diff_sha256": diff,
        "porcelain": status.splitlines(),
    },
    "app": app_identity(),
    "process": process_state(),
    "system": system_state(),
    "db": db_summary(),
    "prefix_pool": inventory(os.path.join(SIMIGO, "prefix-pool")),
    "branch_checkpoints": inventory(os.path.join(SIMIGO, "branch-checkpoints")),
    "trace": {
        "exists": os.path.exists(TRACE),
        "size": os.path.getsize(TRACE) if os.path.exists(TRACE) else None,
    },
}

if DO_BACKUP:
    dest = os.path.join(OUT, "db-" + LABEL + ".sqlite3")
    r = subprocess.run(["sqlite3", DB, ".backup '%s'" % dest],
                       capture_output=True, text=True)
    report["db_backup"] = {"path": dest, "rc": r.returncode,
                           "stderr": r.stderr.strip(),
                           "sha256": sha(dest) if os.path.exists(dest) else None,
                           "size": os.path.getsize(dest) if os.path.exists(dest) else None}

path = os.path.join(OUT, LABEL + ".json")
with open(path, "w") as f:
    json.dump(report, f, ensure_ascii=False, indent=1)
print(json.dumps({
    "wrote": path,
    "head": report["worktree"]["head"][:12],
    "diff": report["worktree"]["diff_sha256"],
    "exe_sha256": report["app"].get("exe_sha256", "")[:16],
    "prefix_files": report["prefix_pool"].get("file_count"),
    "checkpoint_files": report["branch_checkpoints"].get("file_count"),
    "trace_size": report["trace"]["size"],
    "backup": report.get("db_backup"),
}, ensure_ascii=False))
