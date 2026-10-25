#!/usr/bin/env python3
"""M5 freeze re-check: recompute every identity this batch claims, from disk.

Nothing here trusts a previously written verdict. It re-reads the product repo,
re-hashes the model snapshot file by file, re-hashes the installed executable,
the DMG, the Info.plist and the bundle manifest, and re-verifies the code
signature. Any mismatch fails the run.

usage: recheck_artifacts.py <batch-dir> <product-repo>
exit: 0 all identities reproduce · 1 at least one mismatch
"""
import hashlib, json, os, subprocess, sys, time

B = os.path.abspath(sys.argv[1])
REPO = os.path.abspath(sys.argv[2])
CHECKS = {}
DETAIL = {}

def run(cmd, cwd=None):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()

def sha(path, follow=True):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()

fz = json.load(open(os.path.join(B, "RC_SOURCE_FREEZE.json")))
mi = json.load(open(os.path.join(B, "RC_MODEL_IDENTITY.json")))
ii = json.load(open(os.path.join(B, "evidence/m3_install_identity.json")))

# ---------------------------------------------------------------- source side
rc, head, _ = run(["git", "rev-parse", "HEAD"], cwd=REPO)
rc2, branch, _ = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=REPO)
# Raw porcelain: stripping it would move every path one character left.
status = subprocess.run(["git", "status", "--porcelain"], cwd=REPO,
                        capture_output=True, text=True).stdout
dirty, untracked_files = [], []
for line in status.splitlines():
    if not line.strip():
        continue
    code, path = line[:2], line[3:]
    dirty.append(path)
    if code == "??" and os.path.isdir(os.path.join(REPO, path)):
        for root, _, files in os.walk(os.path.join(REPO, path)):
            for f in files:
                untracked_files.append(os.path.relpath(os.path.join(root, f), REPO))
changed_now = sorted(set(dirty) | set(untracked_files))
frozen_changed = sorted(fz["product"]["changed_file_digests"])
CHECKS["head_matches_freeze"] = (head == fz["product"]["head"])
CHECKS["branch_matches_freeze"] = (branch == fz["product"]["branch"])
# Compare the actual file set, not a count: an equal-size but different dirty
# set would mean the frozen source is not the source on disk.
CHECKS["dirty_set_matches_freeze"] = (changed_now == frozen_changed)
DETAIL["source"] = {"head": head, "branch": branch, "dirty_count": len(changed_now),
                    "dirty_paths": changed_now, "frozen_dirty_paths": frozen_changed,
                    "frozen_head": fz["product"]["head"],
                    "frozen_dirty_count": fz["product"]["changed_file_count"]}

# ------------------------------------------------------------ model snapshot
snap = mi["snapshot_path"]
revs = sorted(os.listdir(os.path.join(os.path.dirname(snap), "..", "snapshots")))
CHECKS["model_single_revision"] = (revs == [mi["revision"]])
mismatch, relinked, missing = [], [], []
for name, rec in sorted(mi["files"].items()):
    full = os.path.join(snap, name)
    if not os.path.exists(full):
        missing.append(name)
        continue
    if rec.get("kind") == "symlink":
        if os.path.realpath(full) != rec.get("target"):
            relinked.append(name)
        if sha(full) != rec.get("sha256"):
            mismatch.append(name)
    elif sha(full) != rec.get("sha256"):
        mismatch.append(name)
CHECKS["model_files_present"] = not missing
CHECKS["model_file_digests_reproduce"] = not mismatch
CHECKS["model_symlinks_unchanged"] = not relinked
digest_drift = []
for relpath, frozen in fz["product"]["changed_file_digests"].items():
    full = os.path.join(REPO, relpath)
    if not os.path.exists(full) or sha(full) != frozen:
        digest_drift.append(relpath)
CHECKS["changed_file_digests_reproduce"] = not digest_drift
DETAIL["source"]["changed_file_digest_drift"] = digest_drift

DETAIL["model"] = {"files": len(mi["files"]), "missing": missing,
                   "digest_mismatch": mismatch, "relinked": relinked,
                   "revision": mi["revision"]}

# --------------------------------------------------------------- build output
app = ii["install_path"]
exe = os.path.join(app, "Contents/MacOS/SimiGo")
plist = os.path.join(app, "Contents/Info.plist")
dmg = ii["source_dmg"]
CHECKS["executable_digest_reproduces"] = os.path.exists(exe) and sha(exe) == ii["executable_sha256"]
CHECKS["executable_size_reproduces"] = os.path.exists(exe) and os.path.getsize(exe) == ii["executable_bytes"]
CHECKS["info_plist_digest_reproduces"] = os.path.exists(plist) and sha(plist) == ii["info_plist_sha256"]
CHECKS["dmg_digest_reproduces"] = os.path.exists(dmg) and sha(dmg) == ii["dmg_sha256"]
man = []
for root, dirs, files in os.walk(app):
    dirs.sort()
    for fn in sorted(files):
        fp = os.path.join(root, fn)
        man.append([os.path.relpath(fp, app), os.path.getsize(fp), sha(fp)])
CHECKS["bundle_file_count_reproduces"] = (len(man) == ii["bundle_file_count"])
# The batch record's single bundle_tree_sha256 cannot be reproduced: the digest
# recipe used at install time was never written down, and no plausible
# reconstruction of it matches. A per-file manifest comparison is strictly
# stronger than one aggregate hash, so it is what M5 verifies. The aggregate
# value stays in the record, labelled unverified rather than quietly dropped.
recorded = {r["path"]: (r["bytes"], r["sha256"]) for r in ii["files"]}
current = {rel: (size, d) for rel, size, d in man}
CHECKS["bundle_manifest_matches_record"] = (recorded == current)
man_missing = sorted(set(recorded) - set(current))
man_extra = sorted(set(current) - set(recorded))
man_changed = sorted(k for k in set(recorded) & set(current) if recorded[k] != current[k])
tree_digest = hashlib.sha256()
for rel, size, d in man:
    tree_digest.update(("%s\0%d\0%s\n" % (rel, size, d)).encode())
DETAIL_MANIFEST = {"missing": man_missing, "extra": man_extra, "changed": man_changed,
                   "recorded_tree_digest": ii["bundle_tree_sha256"],
                   "recomputed_tree_digest": tree_digest.hexdigest(),
                   "recorded_tree_digest_reproducible": tree_digest.hexdigest() == ii["bundle_tree_sha256"]}

rc, cs, cs_err = run(["codesign", "--verify", "--strict", "--verbose=2", app])
CHECKS["codesign_verifies_now"] = (rc == 0)
rc, uu, uu_err = run(["dwarfdump", "--uuid", exe])
uuid = ""
for tok in uu.replace("\n", " ").split():
    t = tok.strip()
    if len(t) == 36 and t.count("-") == 4:
        uuid = t
        break
CHECKS["executable_uuid_recorded"] = bool(uuid)
DETAIL["artifact"] = {"exe_sha256": sha(exe) if os.path.exists(exe) else None,
                      "dmg_sha256": sha(dmg) if os.path.exists(dmg) else None,
                      "bundle_file_count": len(man), "bundle_manifest": DETAIL_MANIFEST,
                      "codesign_verify_rc": rc, "codesign_stderr": cs_err,
                      "executable_uuid": uuid}

# The pre-M5 record stored the executable PATH in executable_uuid (path tail was
# grabbed instead of the LC_UUID token). Correct it with the value just read, and
# say so - the surrounding evidence is untouched.
if ii.get("executable_uuid") != uuid:
    ii["executable_uuid_original_invalid"] = ii.get("executable_uuid")
    ii["executable_uuid"] = uuid
    ii["executable_uuid_corrected_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    ii["executable_uuid_note"] = ("Original field held the executable path because the "
                                  "dwarfdump parser took the last whitespace token. Corrected "
                                  "during the M5 re-check from dwarfdump --uuid LC_UUID.")
    json.dump(ii, open(os.path.join(B, "evidence/m3_install_identity.json"), "w"),
              indent=1, sort_keys=True)
    DETAIL["artifact"]["install_identity_uuid_corrected"] = True

doc = {"generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
       "verdict": "PASS" if all(CHECKS.values()) else "FAIL",
       "checks": CHECKS, "detail": DETAIL,
       "note": "Every identity is recomputed from disk in this run; no value is copied from a verdict file."}
out = os.path.join(B, "evidence/recheck_artifacts.json")
json.dump(doc, open(out, "w"), indent=1, sort_keys=True)
open(out, "a").write("\n")
for k in sorted(CHECKS):
    print("%-38s %s" % (k, "ok" if CHECKS[k] else "MISMATCH"))
print("verdict:", doc["verdict"])
print("wrote", out)
sys.exit(0 if doc["verdict"] == "PASS" else 1)
