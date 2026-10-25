"""Write MANIFEST_SHA256.txt for this batch (sha256 of every file except itself).

usage: make_manifest.py <batch-dir>
Lines are "sha256  <path relative to the batch dir>", sorted, so the file can be
checked with `shasum -a 256 -c MANIFEST_SHA256.txt` from inside the batch dir.
"""
import hashlib, os, sys

B = os.path.abspath(sys.argv[1])
OUT = os.path.join(B, "MANIFEST_SHA256.txt")
rows = []
for root, dirs, files in os.walk(B):
    dirs.sort()
    for fn in sorted(files):
        p = os.path.join(root, fn)
        rel = os.path.relpath(p, B)
        # Self-referential logs cannot be listed: writing the manifest appends to
        # logs/manifest.log, and verifying it rewrites logs/verify_manifest.log, so
        # both would always mismatch their own entry. Everything else is hashed.
        if rel in ("MANIFEST_SHA256.txt", "logs/manifest.log",
                   "logs/verify_manifest.log") or rel.endswith(".DS_Store"):
            continue
        h = hashlib.sha256()
        with open(p, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 22), b""):
                h.update(chunk)
        rows.append("%s  %s" % (h.hexdigest(), rel))
with open(OUT, "w") as f:
    f.write("\n".join(rows) + "\n")
print("wrote %s with %d entries" % (OUT, len(rows)))
