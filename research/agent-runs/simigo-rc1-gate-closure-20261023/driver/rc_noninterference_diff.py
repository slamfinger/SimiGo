#!/usr/bin/env python3
"""Diff two noninterference snapshots taken by rc_noninterference.py.

Usage: rc_noninterference_diff.py <a.json> <b.json> <out.json> [abs-prefix[,...]]

CHANGELOG vs the RC1 copy of this tool (gate-closure batch, 2026-10-23):
 1. Allowlisting is now keyed on ABSOLUTE paths and applies to every sweep entry.
    The RC1 copy only applied the allowlist to the SimiGo-Agent-Runs entry and
    matched it on a relative prefix, so the batch's own snapshot file at its root
    (`noninterference_pre-memprobe.json`) was counted as a violation. Real user
    state is now the only thing that can be a violation, and self-writes are
    classified as expected with the matched prefix recorded.
 2. Sweep scopes overlap ON PURPOSE (the whole ~/.simigo root plus its individually
    listed sub-trees), so the same physical file can appear in two entries. Counts
    are therefore published twice: `violation_events` (records) and
    `distinct_violating_abs_paths` / `real_user_state_write_count` (PHYSICAL files).
    The headline release-gate number is the PHYSICAL file count.
 3. A file is "modified" when (bytes, mtime_ns, sha256) differ; for entries the
    snapshot could not content-hash (too large / fingerprint-only scope) the
    comparison degrades to (bytes, mtime_ns) and says so.
"""
import json, os, sys

REAL_STATE_ROOTS = ("/Users/mr.simi/.simigo", "/Users/mr.simi/Library/Application Support")


def classify(abs_path, allow):
    """-> 'expected' if the path lives under an allowlisted absolute prefix."""
    for p in allow:
        if abs_path == p or abs_path.startswith(p.rstrip("/") + "/"):
            return "expected", p
    return "unexpected", None


def dir_records(e):
    if "fingerprints" not in e:
        return None
    return {f["rel"]: f for f in e["fingerprints"]}


def main():
    a = json.load(open(sys.argv[1]))
    b = json.load(open(sys.argv[2]))
    out_path = sys.argv[3]
    allow = [x for x in (sys.argv[4].split(",") if len(sys.argv) > 4 else []) if x]

    ea = {e["path"]: e for e in a["entries"]}
    eb = {e["path"]: e for e in b["entries"]}

    events = 0
    vio, exp = {}, {}
    out = {"a_phase": a["phase"], "b_phase": b["phase"],
           "a_taken_at": a["taken_at"], "b_taken_at": b["taken_at"],
           "allowlisted_abs_prefixes": allow, "real_state_roots": REAL_STATE_ROOTS,
           "entries": {}, "violation_events": 0}

    for p in sorted(set(ea) | set(eb)):
        x, y = ea.get(p), eb.get(p)
        if x is None or y is None:
            out["entries"][p] = {"status": "ENTRY_APPEARED_OR_DISAPPEARED"}
            events += 1
            vio[p] = p
            continue
        if "fingerprints" in x:
            ia, ib = dir_records(x), dir_records(y)
            rec = {"new": [], "deleted": [], "modified": [], "expected": []}
            for rel in sorted(set(ia) | set(ib)):
                xi, yi = ia.get(rel), ib.get(rel)
                ap = os.path.normpath(os.path.join(x["path"], rel))
                if xi is None:
                    kind, detail = "new", rel
                elif yi is None:
                    kind, detail = "deleted", rel
                elif (xi["bytes"], xi["mtime_ns"], xi.get("sha256")) != (yi["bytes"], yi["mtime_ns"], yi.get("sha256")):
                    kind = "modified"
                    detail = {"rel": rel,
                              "a": {"bytes": xi["bytes"], "sha256": xi.get("sha256")},
                              "b": {"bytes": yi["bytes"], "sha256": yi.get("sha256")},
                              "content_compared": xi.get("sha256") is not None and yi.get("sha256") is not None}
                else:
                    continue
                state, hit = classify(ap, allow)
                if state == "expected":
                    rec["expected"].append({"abs": ap, "matched_prefix": hit})
                    exp[ap] = hit
                else:
                    rec[kind].append(detail)
                    events += 1
                    vio[ap] = p
            n_un = len(rec["new"]) + len(rec["deleted"]) + len(rec["modified"])
            out["entries"][p] = {"status": "DIR", "a_files": x.get("files"), "b_files": y.get("files"),
                                 "a_bytes": x.get("bytes"), "b_bytes": y.get("bytes"),
                                 "unexpected_new": len(rec["new"]), "unexpected_deleted": len(rec["deleted"]),
                                 "unexpected_modified": len(rec["modified"]), "expected_change_count": len(rec["expected"]),
                                 "unexpected_details": rec, "clean": n_un == 0}
            out["violation_events"] += n_un
        else:
            same = (x.get("sha256") == y.get("sha256") and x.get("bytes") == y.get("bytes")
                    and x.get("mtime_ns") == y.get("mtime_ns"))
            out["entries"][p] = {"status": "FILE", "a_sha256": x.get("sha256"), "b_sha256": y.get("sha256"),
                                 "a_bytes": x.get("bytes"), "b_bytes": y.get("bytes"), "unchanged": same}
            if not same:
                events += 1
                out["violation_events"] += 1
                if not classify(p, allow)[0] == "expected":
                    vio[p] = p
                else:
                    exp[p] = None

    real = sorted(k for k in vio if any(k.startswith(r.rstrip("/")) for r in REAL_STATE_ROOTS))
    out.update({"distinct_changed_abs_paths": sorted(set(vio) | set(exp)),
                "distinct_violating_abs_paths": sorted(vio),
                "distinct_expected_abs_paths": sorted(exp),
                "distinct_violation_count": len(vio),
                "real_user_state_write_paths": real,
                "real_user_state_write_count": len(real)})
    with open(out_path, "w") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print(json.dumps({"a": a["phase"], "b": b["phase"],
                      "violation_events": out["violation_events"],
                      "distinct_violation_count": out["distinct_violation_count"],
                      "real_user_state_write_count": out["real_user_state_write_count"],
                      "real_user_state_write_paths": real,
                      "expected_self_writes": len(exp)}, indent=1))


if __name__ == "__main__":
    main()
