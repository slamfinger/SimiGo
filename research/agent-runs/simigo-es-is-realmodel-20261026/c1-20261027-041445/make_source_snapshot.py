#!/usr/bin/env python3
"""Rebuildable source snapshot + full change list for the C-1 (post-fix) build.

Captured BEFORE the Release build so the installed artifact can be tied back to
an exact, reproducible source state. Records HEAD, staged/unstaged patches, every
modified tracked file and every untracked build input with its SHA-256, and a
tarball of the untracked build inputs (the research/ evidence tree is listed but
excluded: it is evidence, not a build input).

usage: make_source_snapshot.py <out-dir>
"""
import hashlib, json, os, subprocess, sys, tarfile, time

REPO = "/Users/mr.simi/Documents/SimiGo"
OUT = os.path.abspath(sys.argv[1])
EXCLUDE_FROM_TARBALL = ("research/", "build/", "dist/")


def run(args):
    return subprocess.run(args, cwd=REPO, capture_output=True, text=True)


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for blk in iter(lambda: f.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


def write(name, text):
    path = os.path.join(OUT, name)
    with open(path, "w") as f:
        f.write(text)
    return {"file": name, "sha256": sha(path), "bytes": os.path.getsize(path)}


def file_meta(rel):
    path = os.path.join(REPO, rel)
    if not os.path.isfile(path):
        return {"path": rel, "missing": True}
    return {"path": rel, "bytes": os.path.getsize(path), "sha256": sha(path)}


os.makedirs(OUT, exist_ok=True)
head = run(["git", "rev-parse", "HEAD"]).stdout.strip()
head_date = run(["git", "log", "-1", "--format=%ci"]).stdout.strip()
status = [l for l in run(["git", "status", "--porcelain"]).stdout.splitlines() if l.strip()]

staged = run(["git", "diff", "--cached"]).stdout
unstaged = run(["git", "diff"]).stdout
staged_meta = write("staged.patch", staged)
unstaged_meta = write("unstaged.patch", unstaged)

check = subprocess.run(["git", "apply", "--check", "--reverse", "unstaged.patch"],
                       cwd=OUT, capture_output=True, text=True)
unstaged_meta["reverse_apply_check"] = "ok" if check.returncode == 0 else check.stderr.strip()

tracked = [m for m in status if not m.startswith("??")]
untracked = [m[3:] for m in status if m.startswith("??")]

tracked_files = []
for line in tracked:
    rel = line[3:].split(" -> ")[-1]
    tracked_files.append(file_meta(rel))

untracked_files = []
tarball_members = []
for rel in untracked:
    path = os.path.join(REPO, rel)
    if os.path.isdir(path):
        for base, dirs, names in os.walk(path):
            dirs.sort()
            for name in sorted(names):
                full = os.path.join(base, name)
                relf = os.path.relpath(full, REPO)
                untracked_files.append(file_meta(relf))
    else:
        untracked_files.append(file_meta(rel))

with open(os.path.join(OUT, "tracked-modified.tsv"), "w") as f:
    for item in tracked_files:
        f.write("%s\t%s\n" % (item["path"], item.get("sha256", "MISSING")))
with open(os.path.join(OUT, "untracked.tsv"), "w") as f:
    for item in untracked_files:
        f.write("%s\t%d\t%s\n" % (item["path"], item.get("bytes", -1),
                                  item.get("sha256", "MISSING")))

tarball = os.path.join(OUT, "untracked-build-inputs.tar.gz")
with tarfile.open(tarball, "w:gz") as tar:
    for item in untracked_files:
        rel = item["path"]
        if rel.startswith(EXCLUDE_FROM_TARBALL):
            continue
        tar.add(os.path.join(REPO, rel), arcname=rel)
        tarball_members.append(rel)

with open(os.path.join(OUT, "HEAD.txt"), "w") as f:
    f.write(head + "\n")

manifest = {
    "captured_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "repo": REPO,
    "head": head,
    "head_commit_date": head_date,
    "staged_patch": staged_meta,
    "unstaged_patch": unstaged_meta,
    "tracked_modified": {"count": len(tracked_files), "files": tracked_files},
    "untracked": {"count": len(untracked_files), "files": untracked_files},
    "tarball": {"file": os.path.basename(tarball), "members": tarball_members,
                "sha256": sha(tarball), "bytes": os.path.getsize(tarball)},
    "toolchain": {
        "xcodebuild": run(["xcodebuild", "-version"]).stdout.strip(),
        "swift": subprocess.run(["swift", "--version"], capture_output=True,
                                text=True).stdout.strip(),
    },
    "rebuild": {
        "steps": [
            "git checkout %s" % head,
            "git apply staged.patch",
            "git apply unstaged.patch",
            "tar xzf untracked-build-inputs.tar.gz",
            "xcodebuild build -project SimiGo.xcodeproj -scheme SimiGo "
            "-configuration Release -derivedDataPath /tmp/simigo_rel",
            "tools/make_release_dmg.sh /tmp/simigo_rel/Build/Products/Release/SimiGo.app",
        ],
        "release_build_log": None,
        "installed_exe_sha256": None,
    },
    "notes": [
        "captured BEFORE the post-fix Release build; the exe the build produces "
        "cannot byte-match a later rebuild of the same source, so identity is "
        "the pair (source snapshot, build log)",
        "the research/ evidence tree is listed in untracked.tsv but excluded "
        "from the tarball",
    ],
}
with open(os.path.join(OUT, "MANIFEST.json"), "w") as f:
    json.dump(manifest, f, ensure_ascii=False, indent=1)
    f.write("\n")

print(json.dumps({
    "out": OUT,
    "head": head[:12],
    "tracked_modified": len(tracked_files),
    "untracked": len(untracked_files),
    "unstaged_sha256": unstaged_meta["sha256"],
    "reverse_apply": unstaged_meta["reverse_apply_check"],
    "tarball_sha256": manifest["tarball"]["sha256"],
}, ensure_ascii=False))
