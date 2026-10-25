#!/usr/bin/env python3
"""Batch manifest for the RC1 evidence set.

Scope: every file in the batch EXCEPT the two derived-data trees (which are the
build products themselves, ~2.1 GB each and identified by their bundle tree
digest instead of being re-hashed here). The manifest does not hash itself.
"""
import hashlib, json, os

RC = "/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023"
SKIP_PARTS = (os.sep + "derived" + os.sep,)
BIG = 64 * 1024 * 1024  # skip content hash for files above this (logs/xcresult blobs)


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for blk in iter(lambda: f.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


rows = []
for root, dirs, files in os.walk(RC):
    dirs[:] = [d for d in sorted(dirs) if os.path.join(root, d, "") .find(SKIP_PARTS[0]) < 0]
    if SKIP_PARTS[0] in root + os.sep:
        continue
    for fn in sorted(files):
        fp = os.path.join(root, fn)
        if (fp.endswith("MANIFEST_SHA256_rc1.txt") or fp.endswith("RC_BATCH_SELF_CHECK.json")
                or "/xcresult" in fp):
            continue
        st = os.stat(fp)
        rel = os.path.relpath(fp, RC)
        rows.append((rel, st.st_size, sha(fp) if st.st_size <= BIG else "SKIPPED_OVER_64MB"))
with open(os.path.join(RC, "MANIFEST_SHA256_rc1.txt"), "w") as f:
    f.write("# RC1 batch manifest - rc_id simigo-rc1-de362ef4-20261023\n")
    f.write("# scope: batch evidence files, excluding derived-data trees and .xcresult bundles\n")
    for rel, n, h in rows:
        f.write("%s  %s\n" % (h, rel))
    f.write("# files: %d\n" % len(rows))
    f.write("# total_bytes: %d\n" % sum(r[1] for r in rows))
    f.write("# excluded: derived/ and cleanroom/derived/ (build products; identified by "
            "bundle_tree_sha256 in artifact_identity_*.json); this manifest; "
            "RC_BATCH_SELF_CHECK.json (written after the manifest by driver/verify_rc_batch.py, "
            "which re-hashes every row above).\n")
print("manifest files", len(rows), "bytes", sum(r[1] for r in rows))
