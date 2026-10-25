#!/usr/bin/env python3
"""Diff two noninterference snapshots taken by rc_noninterference.py.

Usage: rc_noninterference_diff.py <a.json> <b.json> <out.json> [rel prefix to allowlist]

For directory entries the comparison is per-file on (rel -> bytes, mtime_ns, sha256).
A file is "modified" when any of the three differ. Files under an allowlisted rel
prefix are counted separately as EXPECTED (e.g. the RC batch writing into its own
evidence directory) and are excluded from the violation count.
"""
import json, sys, os


def index(e):
    if "fingerprints" not in e:
        return None
    return {f["rel"]: f for f in e["fingerprints"]}


def diff_dir(a, b, allow):
    ia, ib = index(a) or {}, index(b) or {}
    res = {"new": [], "deleted": [], "modified": [], "expected_change": []}
    for rel in sorted(set(ib) - set(ia)):
        (res["expected_change"] if any(rel.startswith(x) for x in allow) else res["new"]).append(rel)
    for rel in sorted(set(ia) - set(ib)):
        (res["expected_change"] if any(rel.startswith(x) for x in allow) else res["deleted"]).append(rel)
    for rel in sorted(set(ia) & set(ib)):
        x, y = ia[rel], ib[rel]
        if (x["bytes"], x["mtime_ns"], x.get("sha256")) != (y["bytes"], y["mtime_ns"], y.get("sha256")):
            row = {"rel": rel, "a": {"bytes": x["bytes"], "sha256": x.get("sha256")},
                   "b": {"bytes": y["bytes"], "sha256": y.get("sha256")}}
            (res["expected_change"] if any(rel.startswith(p) for p in allow) else res["modified"]).append(row)
    return res


def main():
    a = json.load(open(sys.argv[1]))
    b = json.load(open(sys.argv[2]))
    out_path = sys.argv[3]
    allow = sys.argv[4].split(",") if len(sys.argv) > 4 and sys.argv[4] else []
    ea = {e["path"]: e for e in a["entries"]}
    eb = {e["path"]: e for e in b["entries"]}
    out = {"a_phase": a["phase"], "b_phase": b["phase"],
           "a_taken_at": a["taken_at"], "b_taken_at": b["taken_at"],
           "allowlisted_prefixes": allow, "entries": {}, "violations": 0}
    for p in sorted(set(ea) | set(eb)):
        x, y = ea.get(p), eb.get(p)
        if x is None or y is None:
            out["entries"][p] = {"status": "ENTRY_APPEARED_OR_DISAPPEARED"}
            out["violations"] += 1
            continue
        if "fingerprints" in x:
            d = diff_dir(x, y, allow if p == "/Users/mr.simi/SimiGo-Agent-Runs" else [])
            n_unexp = len(d["new"]) + len(d["deleted"]) + len(d["modified"])
            out["entries"][p] = {
                "status": "DIR", "a_files": x.get("files"), "b_files": y.get("files"),
                "a_bytes": x.get("bytes"), "b_bytes": y.get("bytes"),
                "unexpected_new": len(d["new"]), "unexpected_deleted": len(d["deleted"]),
                "unexpected_modified": len(d["modified"]),
                "expected_change_count": len(d["expected_change"]),
                "unexpected_details": d,
                "clean": n_unexp == 0}
            out["violations"] += n_unexp
        else:
            same = (x.get("sha256") == y.get("sha256") and x.get("bytes") == y.get("bytes")
                    and x.get("mtime_ns") == y.get("mtime_ns"))
            out["entries"][p] = {"status": "FILE", "a_sha256": x.get("sha256"),
                                 "b_sha256": y.get("sha256"), "a_bytes": x.get("bytes"),
                                 "b_bytes": y.get("bytes"), "unchanged": same}
            if not same:
                out["violations"] += 1
    with open(out_path, "w") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print(json.dumps({"a": a["phase"], "b": b["phase"], "violations": out["violations"],
                      "per_entry": {k: (v.get("clean") if v["status"] == "DIR"
                                        else v.get("unchanged", v["status"]))
                                    for k, v in out["entries"].items()}}, indent=1))


if __name__ == "__main__":
    main()
