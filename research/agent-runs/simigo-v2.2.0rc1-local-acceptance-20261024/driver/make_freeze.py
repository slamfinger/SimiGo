#!/usr/bin/env python3
"""Freeze the exact source + dependency state this RC round builds from.

Records, without mutating anything: repo branch/HEAD/upstream/ahead-behind,
staged / tracked-modified / untracked sets, SHA-256 of every changed or
untracked file the build reads, the tracked diff against HEAD (local commits are
never rewritten), the model snapshot revision with per-file digests recomputed
for this round, and the toolchain identity.
"""
import hashlib, json, os, subprocess, sys, time

MODEL_REPO = "mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit"
HF_ROOT = os.path.expanduser(
    "~/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit")

def run(cmd, cwd=None):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return p.returncode, p.stdout.strip(), p.stderr.strip()

def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

def git(repo, *args):
    rc, out, err = run(["git"] + list(args), cwd=repo)
    if rc != 0:
        raise SystemExit("git %s failed: %s" % (" ".join(args), err))
    return out

def repo_state(repo):
    head = git(repo, "rev-parse", "HEAD")
    branch = git(repo, "rev-parse", "--abbrev-ref", "HEAD")
    upstream, ahead, behind = "", None, None
    rc, out, _ = run(["git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], cwd=repo)
    if rc == 0 and out:
        upstream = out
        rc2, out2, _ = run(["git", "rev-list", "--left-right", "--count", "HEAD...@{u}"], cwd=repo)
        if rc2 == 0 and out2:
            a, b = out2.split()
            ahead, behind = int(a), int(b)
    # Both helpers strip stdout, which swallows the first column of a
    # worktree-only change (" M path" -> "M path") and shifts the path by one
    # character. Porcelain must be read verbatim.
    porcelain = subprocess.run(["git", "status", "--porcelain"], cwd=repo,
                               capture_output=True, text=True).stdout
    staged, modified, untracked = [], [], []
    for line in porcelain.splitlines():
        code, path = line[:2], line[3:]
        if path.endswith("/"):
            path = path[:-1]
        if code[0] not in (" ", "?"):
            staged.append(path)
        if code[1] == "M":
            modified.append(path)
        if code == "??":
            untracked.append(path)
    untracked_files = []
    for p in untracked:
        full = os.path.join(repo, p)
        if os.path.isdir(full):
            for root, _, files in os.walk(full):
                for f in files:
                    untracked_files.append(os.path.relpath(os.path.join(root, f), repo))
        else:
            untracked_files.append(p)
    changed = sorted(set(modified) | set(untracked_files))
    digests = {p: sha256_file(os.path.join(repo, p)) for p in changed
               if os.path.isfile(os.path.join(repo, p))}
    rc, diff, _ = run(["git", "diff", "HEAD", "--binary"], cwd=repo)
    diff_bytes = diff.encode()
    return {
        "repo": repo, "branch": branch, "head": head, "upstream": upstream,
        "ahead": ahead, "behind": behind,
        "staged_files": staged, "tracked_modified": modified,
        "untracked_expanded": untracked_files,
        "changed_file_digests": digests, "changed_file_count": len(changed),
        "tracked_diff": {"sha256": hashlib.sha256(diff_bytes).hexdigest(), "bytes": len(diff_bytes)},
    }

def model_state():
    snapshots = os.path.join(HF_ROOT, "snapshots")
    revs = sorted(os.listdir(snapshots)) if os.path.isdir(snapshots) else []
    if len(revs) != 1:
        raise SystemExit("expected exactly one snapshot revision, found %r" % revs)
    rev = revs[0]
    snap = os.path.join(snapshots, rev)
    files = {}
    for name in sorted(os.listdir(snap)):
        full = os.path.join(snap, name)
        entry = {"kind": "symlink" if os.path.islink(full) else "file",
                 "bytes": os.path.getsize(full)}
        if os.path.islink(full):
            entry["target"] = os.path.realpath(full)
        entry["sha256"] = sha256_file(full) if os.path.isfile(full) else None
        files[name] = entry
    tokenizer = {k: v["sha256"] for k, v in files.items()
                 if any(t in k for t in ("tokenizer", "vocab", "merges", "special_tokens", "added_tokens"))}
    return {"repo_id": MODEL_REPO, "revision": rev, "snapshot_path": snap,
            "files": files, "tokenizer_digests": tokenizer, "file_count": len(files)}

def toolchain():
    out = {}
    for key, cmd in (("xcodebuild", ["xcodebuild", "-version"]),
                     ("swift", ["swift", "--version"]),
                     ("sdk", ["xcrun", "--sdk", "macosx", "--show-sdk-version"]),
                     ("uname", ["uname", "-a"])):
        rc, so, se = run(cmd)
        out[key] = (so or se).replace("\n", " ").strip()
    out["macos_product_version"] = run(["sw_vers", "-productVersion"])[1]
    out["macos_build_version"] = run(["sw_vers", "-buildVersion"])[1]
    return out

def main():
    repo = os.path.abspath(sys.argv[1])
    out_path = sys.argv[2]
    lab = None
    if "--lab" in sys.argv:
        lab = os.path.abspath(sys.argv[sys.argv.index("--lab") + 1])
    doc = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "product": repo_state(repo), "model": model_state(), "toolchain": toolchain(),
        "note": ("Records the working tree the build reads. Local commits are not amended; "
                 "the diff against HEAD is preserved so this binary's source is reconstructable."),
    }
    if lab:
        doc["lab"] = repo_state(lab)
    # A digest alone would not let anyone rebuild this binary: the tree that was
    # actually compiled is not a commit. Persist the patch against HEAD and a copy
    # of every untracked source file the build reads, so the candidate's source is
    # reconstructable without committing or rewriting anything.
    batch = os.path.dirname(os.path.abspath(out_path))
    patch_path = os.path.join(batch, "RC_SOURCE_DIFF.patch")
    rc, diff, _ = run(["git", "diff", "HEAD"], cwd=repo)
    with open(patch_path, "w") as f:
        f.write(diff + ("\n" if diff and not diff.endswith("\n") else ""))
    doc["product"]["tracked_diff_patch"] = {
        "path": os.path.basename(patch_path),
        "bytes": os.path.getsize(patch_path),
        "sha256": sha256_file(patch_path),
    }
    snap_dir = os.path.join(batch, "source_snapshot")
    snap = {}
    for rel in doc["product"].get("untracked_expanded", []):
        src = os.path.join(repo, rel)
        if not os.path.isfile(src):
            continue
        dst = os.path.join(snap_dir, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(src, "rb") as fi, open(dst, "wb") as fo:
            fo.write(fi.read())
        snap[rel] = sha256_file(dst)
    doc["product"]["untracked_snapshot"] = snap
    with open(out_path, "w") as f:
        json.dump(doc, f, indent=1, sort_keys=True)
        f.write("\n")
    print("wrote", out_path)
    print("head", doc["product"]["head"][:12], "changed", doc["product"]["changed_file_count"],
          "model_rev", doc["model"]["revision"][:12])

if __name__ == "__main__":
    main()
