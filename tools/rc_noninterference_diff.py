#!/usr/bin/env python3
"""Diff two rc_noninterference.py snapshots; classify every change.

Counts are published twice on purpose: `violation_events` counts RECORDS (sweep
scopes overlap, so one physical file can appear twice) while
`real_user_state_write_count` counts PHYSICAL files under a real-state root. The
release-gate number is the physical one.

`--allow-prefix` exists only for self-writes (evidence directory, result bundle).
A prefix that would cover a real-state root is rejected, so an allowlist can never
hide a user-state write.

usage:
  rc_noninterference_diff.py <a.json> <b.json> <out.json> [--allow-prefix PATH]...

exit: 0 ok · 3 unusable input (unreadable snapshot, overlapping allowlist)
"""
import argparse, json, os, sys


def under(path, root):
    path, root = os.path.abspath(path), os.path.abspath(root)
    return path == root or path.startswith(root.rstrip("/") + "/")


def classify(abs_path, allow):
    for p in allow:
        if abs_path == p or abs_path.startswith(p.rstrip("/") + "/"):
            return "expected", p
    return "unexpected", None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a")
    ap.add_argument("b")
    ap.add_argument("out")
    ap.add_argument("--allow-prefix", action="append", default=[])
    args = ap.parse_args()

    try:
        a = json.load(open(args.a))
        b = json.load(open(args.b))
    except Exception as e:                                    # noqa: BLE001
        sys.stderr.write("rc_noninterference_diff: unreadable snapshot: %s\n" % e)
        sys.exit(3)

    ea = {e["path"]: e for e in a["entries"]}
    eb = {e["path"]: e for e in b["entries"]}
    if set(ea) != set(eb):
        sys.stderr.write("rc_noninterference_diff: snapshots cover different roots; refusing\n")
        sys.exit(3)

    real_roots = sorted({e["path"] for e in a["entries"] if e.get("role") == "real_state"})
    allow = [os.path.abspath(p) for p in args.allow_prefix]
    for p in allow:
        for r in real_roots:
            if under(r, p) or under(p, r):
                sys.stderr.write("rc_noninterference_diff: allow-prefix %s overlaps real root %s\n"
                                 % (p, r))
                sys.exit(3)

    out = {"a_phase": a["phase"], "b_phase": b["phase"],
           "a_taken_at": a["taken_at"], "b_taken_at": b["taken_at"],
           "real_roots": real_roots, "allowlisted_abs_prefixes": allow,
           "entries": {}, "violation_events": 0}
    vio, exp, ref_changed = {}, {}, []

    for path in sorted(ea):
        x, y = ea[path], eb[path]
        if x.get("role") != y.get("role"):
            sys.stderr.write("rc_noninterference_diff: role changed for %s; refusing\n" % path)
            sys.exit(3)
        if "fingerprints" in x:
            ia = {f["rel"]: f for f in x["fingerprints"]}
            ib = {f["rel"]: f for f in y["fingerprints"]}
            rec = {"new": [], "deleted": [], "modified": [], "expected": [], "reference": []}
            for rel in sorted(set(ia) | set(ib)):
                xi, yi = ia.get(rel), ib.get(rel)
                abs_path = os.path.normpath(os.path.join(path, rel))
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
                if x.get("role") == "reference":
                    rec["reference"].append(detail)
                    ref_changed.append(abs_path)
                    continue
                state, hit = classify(abs_path, allow)
                if state == "expected":
                    rec["expected"].append({"abs": abs_path, "matched_prefix": hit})
                    exp[abs_path] = hit
                else:
                    rec[kind].append(detail)
                    vio[abs_path] = path
            unexpected = len(rec["new"]) + len(rec["deleted"]) + len(rec["modified"])
            out["entries"][path] = {"status": "DIR", "role": x.get("role"),
                                    "a_files": x.get("files"), "b_files": y.get("files"),
                                    "a_bytes": x.get("bytes"), "b_bytes": y.get("bytes"),
                                    "unexpected_new": len(rec["new"]),
                                    "unexpected_deleted": len(rec["deleted"]),
                                    "unexpected_modified": len(rec["modified"]),
                                    "expected_change_count": len(rec["expected"]),
                                    "reference_change_count": len(rec["reference"]),
                                    "unexpected_details": rec, "clean": unexpected == 0}
            out["violation_events"] += unexpected
            continue

        same = (x.get("sha256") == y.get("sha256") and x.get("bytes") == y.get("bytes")
                and x.get("mtime_ns") == y.get("mtime_ns"))
        out["entries"][path] = {"status": "FILE", "role": x.get("role"),
                                "a_sha256": x.get("sha256"), "b_sha256": y.get("sha256"),
                                "a_bytes": x.get("bytes"), "b_bytes": y.get("bytes"),
                                "unchanged": same}
        if same:
            continue
        if x.get("role") == "reference":
            ref_changed.append(path)
            continue
        out["violation_events"] += 1
        state, hit = classify(path, allow)
        if state == "expected":
            exp[path] = hit
        else:
            vio[path] = path

    real = sorted(p for p in vio if any(under(p, r) for r in real_roots))
    out.update({"distinct_changed_abs_paths": sorted(set(vio) | set(exp)),
                "distinct_violating_abs_paths": sorted(vio),
                "distinct_expected_abs_paths": sorted(exp),
                "distinct_violation_count": len(vio),
                "reference_change_paths": sorted(ref_changed),
                "real_user_state_write_paths": real,
                "real_user_state_write_count": len(real)})
    with open(args.out, "w") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print(json.dumps({"a": a["phase"], "b": b["phase"],
                      "violation_events": out["violation_events"],
                      "distinct_violation_count": out["distinct_violation_count"],
                      "real_user_state_write_count": out["real_user_state_write_count"],
                      "real_user_state_write_paths": real,
                      "expected_self_writes": len(exp),
                      "reference_changes": len(set(ref_changed))}, indent=1))


if __name__ == "__main__":
    main()
