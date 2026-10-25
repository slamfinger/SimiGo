#!/usr/bin/env python3
"""A2 materialization check — offline, read-only, loads no model.

Verifies that a dereferenced copy of the frozen artifact is the same artifact:
same relative path set (no additions, omissions or renames), every entry a
regular file rather than a symlink, same byte count and same SHA-256 per file,
and the same aggregate under the frozen `path / bytes / sha256` rule.

It also predicts the engine weights digest the future P0 would compute. That
prediction is a rule replica, NOT an EngineModelIdentity reading: this script
does not prove the engine will agree, and it cannot stand in for a P0 run.

SCRIPT_VERSION 2 — 2026-10-20. Version 1 ran first without path sanitization; its
output was discarded before publication and never committed. Version 2 only
sanitizes the home prefix in the displayed paths; the checks and the digests are
unchanged.
"""

import argparse
import hashlib
import json
import os
import sys
import datetime

SCRIPT_VERSION = 2
BOUNDARY = (
    "Offline artifact-materialization verification. No model was loaded, no P0 "
    "authorization was consumed, and nothing here is a P0 run fact. Passing "
    "shows the copy is byte-identical to the frozen content; it does not show "
    "that EngineModelIdentity returns a non-empty or matching digest for the "
    "copy, and it does not show that loading or the cache hook will pass a new "
    "P0."
)


def display(path):
    """Sanitize the local home prefix before writing paths into a record."""
    home = os.path.expanduser("~")
    return path.replace(home, "~") if path.startswith(home) else path


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def walk_rows(root):
    rows = []
    symlinks = []
    for dirpath, dirnames, filenames in os.walk(root, followlinks=False):
        for name in list(dirnames):
            path = os.path.join(dirpath, name)
            if os.path.islink(path):
                symlinks.append(os.path.relpath(path, root))
        for name in filenames:
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, root)
            is_link = os.path.islink(path)
            if is_link:
                symlinks.append(rel)
            rows.append({
                "path": rel,
                "is_symlink": is_link,
                "is_regular_file": os.path.isfile(path) and not is_link,
                "bytes": os.path.getsize(path),
                "sha256": sha256_file(path),
            })
    rows.sort(key=lambda row: row["path"])
    return rows, sorted(symlinks)


def aggregate(rows):
    canonical = json.dumps(
        [{"path": r["path"], "bytes": r["bytes"], "sha256": r["sha256"]} for r in rows],
        sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def engine_weights_prediction(rows):
    lines = sorted(
        "%s:%d:%s" % (r["path"], r["bytes"], r["sha256"])
        for r in rows if r["path"].endswith(".safetensors"))
    return hashlib.sha256("\n".join(lines).encode("utf-8")).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binding", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--dest", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    binding = json.loads(open(args.binding, encoding="utf-8").read())
    expected = {row["path"]: row for row in binding["files"]}
    expected_aggregate = binding["model"]["aggregate_sha256"]

    dest_rows, dest_symlinks = walk_rows(args.dest)
    source_rows, source_symlinks = walk_rows(args.source)
    dest_by_path = {row["path"]: row for row in dest_rows}

    missing = sorted(set(expected) - set(dest_by_path))
    extra = sorted(set(dest_by_path) - set(expected))
    per_file = []
    for path in sorted(expected):
        want = expected[path]
        got = dest_by_path.get(path)
        per_file.append({
            "path": path,
            "present": got is not None,
            "is_symlink": got["is_symlink"] if got else None,
            "is_regular_file": got["is_regular_file"] if got else None,
            "bytes": got["bytes"] if got else None,
            "expected_bytes": want["bytes"],
            "sha256": got["sha256"] if got else None,
            "expected_sha256": want["sha256"],
            "match": bool(got
                          and not got["is_symlink"]
                          and got["is_regular_file"]
                          and got["bytes"] == want["bytes"]
                          and got["sha256"] == want["sha256"]),
        })

    copied_aggregate = aggregate(dest_rows)
    checks = {
        "binding_file_count_equals_copy": len(expected) == len(dest_rows),
        "no_missing_paths": not missing,
        "no_extra_paths": not extra,
        "all_entries_regular_files": not dest_symlinks,
        "all_bytes_and_digests_match": all(row["match"] for row in per_file),
        "aggregate_matches_binding": copied_aggregate == expected_aggregate,
        "source_is_the_symlinked_snapshot": bool(source_symlinks),
    }
    record = {
        "schema_id": "SIMIGO-G2-A2-MATERIALIZATION-CHECK-V1",
        "kind": "offline_materialization_verification",
        "script_version": SCRIPT_VERSION,
        "created_at_utc": utc_now(),
        "command": display(" ".join([sys.executable] + sys.argv)),
        "binding": {
            "path": display(args.binding),
            "sha256": sha256_file(args.binding),
            "expected_aggregate_sha256": expected_aggregate,
            "expected_file_count": len(expected),
        },
        "source": {
            "path": display(os.path.realpath(args.source)),
            "entries": len(source_rows),
            "symlinks": len(source_symlinks),
            "note": "read-only; the source was never written to",
        },
        "dest": {
            "path": display(os.path.realpath(args.dest)),
            "entries": len(dest_rows),
            "symlinks": dest_symlinks,
            "regular_files": sum(1 for row in dest_rows if row["is_regular_file"]),
        },
        "missing_paths": missing,
        "extra_paths": extra,
        "aggregate_sha256": copied_aggregate,
        "aggregate_rule": "sha256(UTF-8(JSON.dumps([{path,bytes,sha256}], sort_keys=true, "
                          "separators=(',',':'), ensure_ascii=false)))",
        "predicted_engine_weights_digest": engine_weights_prediction(dest_rows),
        "prediction_status": "rule replica for the future P0; NOT an EngineModelIdentity "
                             "reading and not evidence that the engine agrees",
        "checks": checks,
        "all_pass": all(checks.values()),
        "files": per_file,
        "boundary": BOUNDARY,
    }

    with open(args.out, "x", encoding="utf-8") as fh:
        json.dump(record, fh, indent=2, sort_keys=True)
        fh.write("\n")

    print(json.dumps({
        "all_pass": record["all_pass"],
        "checks": checks,
        "entries": record["dest"]["entries"],
        "symlinks_in_copy": record["dest"]["symlinks"],
        "aggregate_sha256": copied_aggregate,
        "expected_aggregate": expected_aggregate,
        "predicted_engine_weights_digest": record["predicted_engine_weights_digest"],
        "out": args.out,
    }, indent=2, sort_keys=True))
    return 0 if record["all_pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
