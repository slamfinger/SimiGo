#!/usr/bin/env python3
"""Snapshot protected user resources so RC steps can PROVE non-interference.

phases: pre-test / post-test / pre-experiment / post-experiment
Small files are content-hashed; large caches are hashed by (path,size,mtime) only.
"""
import hashlib, json, os, subprocess, sys, time

RC = os.environ.get("GATE_CLOSURE_DIR",
     "/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-gate-closure-20261023")
HASH_LIMIT = 8 * 1024 * 1024  # content-hash files up to 8 MB
PROTECTED = [
    ("/Users/mr.simi/.simigo/simigo.sqlite3", "official IS database"),
    ("/Users/mr.simi/.simigo/simigo.sqlite3-wal", "official IS WAL"),
    ("/Users/mr.simi/.simigo/simigo.sqlite3-shm", "official IS shm"),
    ("/Users/mr.simi/.simigo/branch-checkpoints", "official KV branch checkpoints"),
    ("/Users/mr.simi/.simigo/prefix-pool", "official prefix pool"),
    ("/Users/mr.simi/.simigo/manifests", "official bootstrap manifests"),
    ("/Users/mr.simi/Library/Application Support/SimiGo", "app support state"),
    ("/Users/mr.simi/SimiGo-Agent-Runs", "agent-run evidence batches"),
    # GATE-CLOSURE SCOPE EXPANSION (2026-10-23): the RC1 audit only covered
    # six ~/.simigo sub-trees and therefore MISSED writes to the append-only
    # trace log. From here on the ENTIRE managed root is swept, so no sink can
    # hide outside the enumerated list.
    ("/Users/mr.simi/.simigo", "ENTIRE managed root (full-tree sweep)"),
    ("/Users/mr.simi/.simigo/logs", "native MLX trace log"),
    ("/Users/mr.simi/.simigo/harness", "harness state"),
    ("/Users/mr.simi/.simigo/locks", "locks"),
    ("/Users/mr.simi/.simigo/staging", "staging"),
    ("/Users/mr.simi/.simigo/bin", "bin"),
    ("/Users/mr.simi/.simigo/sources", "sources"),
    ("/Users/mr.simi/.simigo/build", "build"),
    ("/Users/mr.simi/.simigo/codex-bridge", "codex-bridge"),
    ("/Users/mr.simi/.cache/huggingface", "HF model cache (reference only)"),
]
BIG_SUBTREES = {"/Users/mr.simi/SimiGo-Agent-Runs", "/Users/mr.simi/.cache/huggingface"}
# ^ the two trees above are far too large to content-hash; they get
# (path, bytes, mtime_ns) fingerprints only, which still detects any added,
# removed or rewritten entry. ~/.simigo itself is NOT here: small files under
# it are content-hashed even in the full-tree sweep.


def sha(p, limit=HASH_LIMIT):
    try:
        if os.path.getsize(p) > limit:
            return "TOO_LARGE:size=%d" % os.path.getsize(p)
        with open(p, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except Exception as e:
        return "ERR:%s" % e


def entry(path, label):
    out = {"path": path, "label": label, "exists": os.path.exists(path)}
    if not out["exists"]:
        return out
    if os.path.isdir(path):
        rec, tot = [], 0
        for root, dirs, files in os.walk(path):
            dirs.sort(); 
            for fn in sorted(files):
                fp = os.path.join(root, fn)
                st = None
                try:
                    st = os.stat(fp)
                except OSError:
                    continue
                h = None
                if path not in BIG_SUBTREES and st.st_size <= HASH_LIMIT:
                    h = sha(fp)
                rec.append({"rel": os.path.relpath(fp, path), "bytes": st.st_size,
                            "mtime_ns": st.st_mtime_ns, "sha256": h})
                tot += st.st_size
        out["files"] = len(rec)
        out["bytes"] = tot
        out["fingerprints"] = rec
        return out
    st = os.stat(path)
    out["bytes"] = st.st_size
    out["mtime_ns"] = st.st_mtime_ns
    out["sha256"] = sha(path) if path not in BIG_SUBTREES else "PATH_ONLY"
    return out


def main():
    phase = sys.argv[1] if len(sys.argv) > 1 else "pre-test"
    snap = {"phase": phase, "taken_at": time.strftime("%FT%T%z"),
            "entries": [entry(p, l) for p, l in PROTECTED]}
    with open(os.path.join(RC, "noninterference_%s.json" % phase), "w") as f:
        json.dump(snap, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print(json.dumps({"phase": phase,
                      "official_db_sha": snap["entries"][0].get("sha256"),
                      "official_wal_sha": snap["entries"][1].get("sha256"),
                      "official_wal_bytes": snap["entries"][1].get("bytes"),
                      "checkpoints_files": snap["entries"][3].get("files"),
                      "checkpoints_bytes": snap["entries"][3].get("bytes"),
                      "prefix_pool_files": snap["entries"][4].get("files"),
                      "agent_runs_files": snap["entries"][7].get("files")}, indent=1))


if __name__ == "__main__":
    main()
