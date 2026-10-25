"""Write MANIFEST_SHA256.txt for this batch (sha256 of every retained file).

usage: make_manifest.py <batch-dir>
Lines are "sha256  <path relative to the batch dir>", sorted, so the file can be
checked with `shasum -a 256 -c MANIFEST_SHA256.txt` from inside the batch dir.

Excluded on purpose (and stated in REPORT.md):
  * MANIFEST_SHA256.txt itself;
  * logs/manifest.log and logs/verify_manifest.log - writing/verifying the
    manifest appends to them, so they can never match their own entry;
  * build/ - DerivedData, reproducible from the recorded xcodebuild commands;
  * build_v5/ - the same, for the v5 rebuild that added the `serve-service`
    role (its identity is fixed in evidence/install_identity_v5_candidate.json);
  * run_isolated_*/isolation - the throwaway roots the runner creates, fills
    with a 19 GiB model cache and deletes on the next run; they are working
    state, not evidence. The runner's own JSON/log/xcresult stay in;
  * default.profraw - LLVM profile droppings rewritten by any later app run;
  * .DS_Store.
"""
import hashlib
import os
import sys

B = os.path.abspath(sys.argv[1])
OUT = os.path.join(B, "MANIFEST_SHA256.txt")
SKIP_FILES = {"MANIFEST_SHA256.txt", "logs/manifest.log", "logs/verify_manifest.log",
              "default.profraw"}
SKIP_TOP_DIRS = {"build", "build_v5"}


def skipped_file(rel):
    parts = rel.split(os.sep)
    if rel in SKIP_FILES or rel.endswith(".DS_Store"):
        return True
    if parts[0] in SKIP_TOP_DIRS:
        return True
    return any(p == "isolation" for p in parts)


def sha(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 22), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    rows = []
    for root, dirs, files in os.walk(B):
        rel_root = os.path.relpath(root, B)
        if rel_root == ".":
            dirs[:] = [d for d in dirs if d not in SKIP_TOP_DIRS]
        dirs[:] = sorted(d for d in dirs if d != "isolation")
        for name in sorted(files):
            path = os.path.join(root, name)
            rel = os.path.relpath(path, B)
            if skipped_file(rel):
                continue
            rows.append("%s  %s" % (sha(path), rel))
    rows.sort(key=lambda row: row.split("  ", 1)[1])
    with open(OUT, "w") as handle:
        handle.write("\n".join(rows) + "\n")
    total = sum(os.path.getsize(os.path.join(B, r.split("  ", 1)[1])) for r in rows)
    print("wrote %s with %d entries, %.1f MiB" % (OUT, len(rows), total / (1 << 20)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
