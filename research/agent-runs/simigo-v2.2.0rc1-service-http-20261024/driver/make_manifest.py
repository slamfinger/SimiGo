"""Write MANIFEST_SHA256.txt for this batch (sha256 of every retained file).

usage: make_manifest.py <batch-dir>
Lines are "sha256  <path relative to the batch dir>", sorted, so the file can be
checked with `shasum -a 256 -c MANIFEST_SHA256.txt` from inside the batch dir.

Excluded on purpose (and stated in REPORT.md):
  * MANIFEST_SHA256.txt itself;
  * logs/manifest.log and logs/verify_manifest.log - writing/verifying the
    manifest appends to them, so they can never match their own entry;
  * build/ - DerivedData, reproducible from the recorded xcodebuild commands;
  * the throwaway isolation roots (m3*, */isolation) - state the drivers create
    and delete, not evidence;
  * .DS_Store.
"""
import hashlib
import os
import sys

B = os.path.abspath(sys.argv[1])
OUT = os.path.join(B, "MANIFEST_SHA256.txt")
SKIP = {"MANIFEST_SHA256.txt", "logs/manifest.log", "logs/verify_manifest.log"}
SKIP_TOP_DIRS = {"build"}
SKIP_TOP_PREFIXES = ("m3",)


def skipped(rel):
    parts = rel.split(os.sep)
    if parts and parts[0] in SKIP_TOP_DIRS:
        return True
    if parts and parts[0].startswith(SKIP_TOP_PREFIXES):
        return True
    return "/isolation/" in rel or rel.endswith("/isolation")


def main():
    rows = []
    for root, dirs, files in os.walk(B):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(root, name)
            rel = os.path.relpath(path, B)
            if rel in SKIP or rel.endswith(".DS_Store") or skipped(rel):
                continue
            digest = hashlib.sha256()
            with open(path, "rb") as handle:
                for chunk in iter(lambda: handle.read(1 << 22), b""):
                    digest.update(chunk)
            rows.append("%s  %s" % (digest.hexdigest(), rel))
    with open(OUT, "w") as handle:
        handle.write("\n".join(rows) + "\n")
    print("wrote %s with %d entries" % (OUT, len(rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
