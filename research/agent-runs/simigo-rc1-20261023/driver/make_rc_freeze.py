#!/usr/bin/env python3
"""Freeze the exact source/toolchain/model/build-config state for the SimiGo RC.

Read-only over the product tree; writes only into the RC batch directory.
"""
import hashlib, json, os, re, subprocess, sys

REPO = "/Users/mr.simi/Documents/SimiGo"
RC = "/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023"
MODEL = ("/Users/mr.simi/.cache/huggingface/hub/"
         "models--mlx-community--Qwen3-Coder-30A3B-Instruct-4bit")  # placeholder, fixed below
MODEL = ("/Users/mr.simi/.cache/huggingface/hub/"
         "models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/"
         "snapshots/6e302ea604ad9ab206367e2c501d1571023e7b6d")
BUILD_CMD = ("xcodebuild build-for-testing -project SimiGo.xcodeproj -scheme SimiGo "
             "-configuration Debug -destination platform=macOS,arch=arm64 "
             "CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= -enableCodeCoverage NO "
             "-derivedDataPath " + RC + "/derived")


def run(cmd, cwd=REPO):
    return subprocess.run(cmd, shell=True, cwd=cwd, capture_output=True, text=True).stdout


def sha(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def main():
    head = run("git rev-parse HEAD").strip()
    branch = run("git rev-parse --abbrev-ref HEAD").strip()
    staged = [l for l in run("git diff --cached --name-only").splitlines() if l.strip()]
    porcelain = [l for l in run("git status --short").splitlines() if l.strip()]
    tracked, untracked = [], []
    for l in porcelain:
        code, path = l[:2].strip(), l[3:].strip()
        (untracked if code == "??" else tracked).append((code, path))

    # expand untracked entries that are directories into their files
    untracked_files = []
    for _, p in untracked:
        full = os.path.join(REPO, p)
        if os.path.isdir(full):
            for root, _, files in os.walk(full):
                for fn in sorted(files):
                    rel = os.path.relpath(os.path.join(root, fn), REPO)
                    untracked_files.append(rel)
        elif os.path.exists(full):
            untracked_files.append(p)

    per_file = []
    for _, p in tracked:
        full = os.path.join(REPO, p)
        if os.path.exists(full):
            b = open(full, "rb").read()
            per_file.append({"path": p, "kind": "tracked", "sha256": hashlib.sha256(b).hexdigest(),
                             "bytes": len(b)})
    for p in untracked_files:
        full = os.path.join(REPO, p)
        b = open(full, "rb").read()
        per_file.append({"path": p, "kind": "untracked", "sha256": hashlib.sha256(b).hexdigest(),
                         "bytes": len(b)})

    patch_name = "RC_TRACKED_DIFF.patch"
    with open(os.path.join(RC, patch_name), "w") as f:
        f.write(run("git diff"))
    patch_sha = sha(os.path.join(RC, patch_name))

    cfg_files = ["Package.swift", "Package.resolved",
                 "Packages/SimiGoRuntime/Package.swift", "Packages/SimiGoRuntime/Package.resolved"]
    configs = []
    for p in cfg_files:
        full = os.path.join(REPO, p)
        if os.path.exists(full):
            configs.append({"path": p, "sha256": sha(full), "bytes": os.path.getsize(full)})

    model_files = []
    for fn in sorted(os.listdir(MODEL)):
        full = os.path.join(MODEL, fn)
        if os.path.islink(full):
            model_files.append({"file": fn, "kind": "symlink",
                                "target": os.path.realpath(full),
                                "target_sha256": sha(os.path.realpath(full)),
                                "target_bytes": os.path.getsize(os.path.realpath(full))})
        elif os.path.isfile(full):
            model_files.append({"file": fn, "kind": "file", "sha256": sha(full),
                                "bytes": os.path.getsize(full)})

    tok = [m for m in model_files if m["file"].startswith("tokenizer") or m["file"] in
           ("vocab.json", "merges.txt", "config.json", "generation_config.json")]

    toolchain = {
        "xcodebuild": run("xcodebuild -version").strip().replace("\n", " | "),
        "swift": run("swift --version 2>&1").strip().replace("\n", " | "),
        "macos": run("sw_vers -productVersion").strip(),
        "arch": run("uname -m").strip(),
    }

    rc_id = "simigo-rc1-%s-20261023" % head[:8]
    out = {
        "rc_id": rc_id,
        "frozen_at": subprocess.run("date +%FT%T%z", shell=True, capture_output=True, text=True).stdout.strip(),
        "repo": REPO,
        "head": head,
        "branch": branch,
        "staged_files": staged,
        "committed_this_turn": 0,
        "pushed_this_turn": 0,
        "change_set": {"tracked_modified": len(tracked), "untracked_entries": len(untracked),
                       "untracked_files_expanded": len(untracked_files)},
        "per_file_sha256": per_file,
        "tracked_patch": {"file": patch_name, "sha256": patch_sha,
                          "bytes": os.path.getsize(os.path.join(RC, patch_name))},
        "build_configuration": {
            "command": BUILD_CMD,
            "configuration": "Debug",
            "destination": "platform=macOS,arch=arm64",
            "code_signing_allowed": "NO",
            "derived_data_path": RC + "/derived",
            "packages": configs,
        },
        "model_identity": {
            "repo_id": "mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit",
            "revision": "6e302ea604ad9ab206367e2c501d1571023e7b6d",
            "snapshot_path": MODEL,
            "files": model_files,
            "tokenizer_and_config_digests": tok,
        },
        "toolchain": toolchain,
        "limits": [
            "this freeze records state; it does not by itself prove the build succeeds",
            "untracked files cannot be carried by a git patch; their identity is the per-file digest",
            "model weights are referenced from the HF cache and are NOT copied into this batch",
        ],
    }
    with open(os.path.join(RC, "RC_SOURCE_FREEZE.json"), "w") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
        f.write("\n")

    lines = ["# SimiGo release-candidate source freeze",
             "# rc_id: " + rc_id,
             "# head: " + head, "# branch: " + branch,
             "# staged: %d ; committed: 0 ; pushed: 0" % len(staged),
             "# tracked modified: %d ; untracked entries: %d (%d files)" % (
                 len(tracked), len(untracked), len(untracked_files)), "",
             "[per-file sha256]"]
    for e in per_file:
        lines.append("%s  %9d  %s  (%s)" % (e["sha256"], e["bytes"], e["path"], e["kind"]))
    lines += ["", "[build configuration]", BUILD_CMD, ""]
    lines += ["[toolchain]"] + ["%s = %s" % (k, v) for k, v in toolchain.items()] + [""]
    lines += ["[model snapshot: %s]" % MODEL]
    for m in tok:
        lines.append(json.dumps(m, ensure_ascii=False))
    with open(os.path.join(RC, "RC_SOURCE_FREEZE.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print(json.dumps({"rc_id": rc_id, "tracked_modified": len(tracked),
                      "untracked_entries": len(untracked), "untracked_files": len(untracked_files),
                      "per_file_rows": len(per_file), "patch_bytes": out["tracked_patch"]["bytes"],
                      "model_files": len(model_files)}, indent=1))


if __name__ == "__main__":
    sys.exit(main())
