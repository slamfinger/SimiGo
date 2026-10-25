#!/usr/bin/env python3
"""Prove that the retained patches are exactly this batch's delta.

Why this exists
  The product worktree already carried 15 uncommitted entries before this batch
  began (evidence/worktree_before_build.txt). `git diff` therefore reports the
  union of someone else's changes and ours, and would overstate the delta. The
  only honest unit of attribution is "the pre-edit bytes -> the bytes now on
  disk", so this script replays each patch onto a retained copy of the pre-edit
  file and demands byte equality with the file that was actually compiled.

  The pre-edit copies are themselves checked: the app one was rebuilt by
  reversing this batch's own edits and compared against the sha256 recorded
  before the first edit; the test one is `git show HEAD:<path>`, i.e. the
  committed bytes, because that file was untouched in the worktree beforehand.

Entries
  A  app_instrumentation_driver   SimiGo/Headless/SimiGoG1G3Entry.swift
  B  trace_role_test_coverage     SimiGoTests/SimiGoG1G3HeadlessEntryTests.swift

Rules (per entry)
  P1  the pre-edit copy hashes to the recorded pre-edit sha
  P2  the patch applies to that copy with zero fuzz and no rejects
  P3  the patched result is byte-identical to the file now in the worktree
  P4  the patch touches exactly one path
  P5  the worktree file still hashes to the post-edit sha the build consumed

Rules (batch)
  P6  the test-only entry did not move the installed candidate: the install
      identity document recomputed after the test edit equals the one recorded
      before it, key by key

usage: verify_patch_attribution.py
Exit codes: 0 PASS, 1 contradiction.
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "/Users/mr.simi/Documents/SimiGo"
OUT = os.path.join(B, "evidence/patch_attribution.json")

ENTRIES = [
    {
        "name": "app_instrumentation_driver",
        "patch": "LAYER_FORWARD_INSTRUMENTATION.patch",
        "path": "SimiGo/Headless/SimiGoG1G3Entry.swift",
        "pre": "source/pre_edit_SimiGoG1G3Entry.swift",
        "pre_sha": "9a1e2b1670995b4b4f941ece79eb6f196769aeea22ae501668b5ceacbe55bfa4",
        "post_sha": "25c4e967bcfaa88b61259b116951558360e1c8ad8cadfbcec4d792a1eb3f7122",
        "target": "app",
        "affects_installed_binary": True,
        "pre_origin": "rebuilt by reversing this batch's edits, sha checked against the value recorded before the first edit",
    },
    {
        "name": "trace_role_test_coverage",
        "patch": "TESTS_TRACE_ROLE_COVERAGE.patch",
        "path": "SimiGoTests/SimiGoG1G3HeadlessEntryTests.swift",
        "pre": "source/pre_edit_SimiGoG1G3HeadlessEntryTests.swift",
        "pre_sha": "ee3ddc9cc21562fffd1c6d85db5b300a41ce6ed924fb8940b2e98b4ba33865f9",
        "post_sha": "69f5f2d2b063b9b351a34e66e668f99366c2c942d3795c74883137d6cc7de320",
        "target": "test_bundle",
        "affects_installed_binary": False,
        "pre_origin": "git show HEAD:<path> (the file was clean in the worktree before this batch)",
    },
]


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def check_entry(entry):
    patch_path = os.path.join(B, entry["patch"])
    pre_path = os.path.join(B, entry["pre"])
    cur_path = os.path.join(REPO, entry["path"])
    patch_text = open(patch_path).read()

    paths = sorted({line.split()[1][2:] for line in patch_text.splitlines()
                    if line.startswith("--- ") or line.startswith("+++ ")})

    work = tempfile.mkdtemp(prefix="attrib-")
    dest = os.path.join(work, entry["path"])
    os.makedirs(os.path.dirname(dest))
    shutil.copyfile(pre_path, dest)
    proc = subprocess.run(["patch", "-p1", "-t", "-F0", "-i", patch_path],
                          cwd=work, capture_output=True, text=True)
    rejects = [os.path.join(root, f) for root, _, files in os.walk(work) for f in files
               if f.endswith((".rej", ".orig"))]

    pre_sha, patched_sha, cur_sha = sha(pre_path), sha(dest), sha(cur_path)
    added = sum(1 for l in patch_text.splitlines()
                if l.startswith("+") and not l.startswith("+++"))
    removed = sum(1 for l in patch_text.splitlines()
                  if l.startswith("-") and not l.startswith("---"))
    checks = {
        "P1_pre_edit_copy_matches_recorded_sha": pre_sha == entry["pre_sha"],
        "P2_patch_applies_clean": proc.returncode == 0 and not rejects,
        "P3_patched_bytes_equal_worktree_file": patched_sha == cur_sha,
        "P4_patch_touches_one_path": paths == [entry["path"]],
        "P5_worktree_matches_post_edit_sha": cur_sha == entry["post_sha"],
    }
    return {
        "name": entry["name"],
        "target": entry["target"],
        "affects_installed_binary": entry["affects_installed_binary"],
        "checks": checks,
        "passed": all(checks.values()),
        "patch": {"path": entry["patch"], "sha256": sha(patch_path),
                  "lines": len(patch_text.splitlines()),
                  "added": added, "removed": removed, "paths": paths},
        "path": entry["path"],
        "pre_edit_sha256": pre_sha,
        "post_edit_sha256": cur_sha,
        "patched_copy_sha256": patched_sha,
        "pre_edit_origin": entry["pre_origin"],
        "patch_stdout": proc.stdout.strip(),
        "rejects": rejects,
    }


def install_identity_unchanged():
    before = os.path.join(B, "evidence/install_identity_before_test_change.json")
    after = os.path.join(B, "evidence/install_identity_new_candidate.json")
    if not (os.path.exists(before) and os.path.exists(after)):
        return False, {"reason": "one of the two install identity documents is missing"}
    a, b = json.load(open(before)), json.load(open(after))
    keys = sorted(set(a) | set(b))
    changed = [k for k in keys if a.get(k) != b.get(k)]
    return not changed, {"compared_keys": len(keys), "changed_keys": changed,
                         "comparison": "before_test_change vs recomputed_after_test_change"}


def main():
    entries = [check_entry(e) for e in ENTRIES]
    unchanged, detail = install_identity_unchanged()
    checks = {"P6_installed_candidate_unmoved_by_test_edit": unchanged}
    passed = all(e["passed"] for e in entries) and unchanged

    payload = {
        "gate": "layer_forward_instrumentation_attribution",
        "verdict": "PASS" if passed else "BLOCKED",
        "checks": checks,
        "entries": entries,
        "install_identity": detail,
        "source": {
            "repo": REPO,
            "head": subprocess.run(["git", "-C", REPO, "rev-parse", "HEAD"],
                                   capture_output=True, text=True).stdout.strip(),
            "branch": subprocess.run(["git", "-C", REPO, "rev-parse", "--abbrev-ref", "HEAD"],
                                     capture_output=True, text=True).stdout.strip(),
        },
        "why_not_git_diff": (
            "The worktree already carried 15 uncommitted entries before this batch. "
            "`git diff` over the same app file reports the union of those pre-existing "
            "changes and this batch's edit (+237/-12); only the replayed patch "
            "(+112/-1) is attributable to this batch. See "
            "evidence/worktree_before_build.txt and evidence/worktree_after_test_change.txt."),
        "note": ("A passing attribution check does not make the forward-call gate pass. "
                 "It only fixes what this batch changed; the gate verdict comes from "
                 "layer_forward_calls_verdict.json."),
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as handle:
        json.dump(payload, handle, indent=1)
        handle.write("\n")
    print(json.dumps({"verdict": payload["verdict"],
                      "entries": {e["name"]: e["passed"] for e in entries},
                      "batch_checks": checks}, indent=1))
    return 0 if payload["verdict"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
