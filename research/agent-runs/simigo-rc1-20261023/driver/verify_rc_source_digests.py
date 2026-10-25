#!/usr/bin/env python3
"""Re-hash every file recorded in RC_SOURCE_FREEZE.json and report drift.

This answers RC step 5's "user changes untouched" clause: the freeze is taken
before build/test/experiment, so a clean re-hash proves the RC steps did not
modify the product working tree. It does NOT prove the freeze itself is
complete -- untracked directories are expanded at freeze time only.
"""
import hashlib, json, os, subprocess

RC = "/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023"
REPO = "/Users/mr.simi/Documents/SimiGo"
FREEZE = os.path.join(RC, "RC_SOURCE_FREEZE.json")


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for blk in iter(lambda: f.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


def main():
    fz = json.load(open(FREEZE))
    rows, miss, drift = [], [], []
    for item in fz["per_file_sha256"]:
        rel, want = item["path"], item["sha256"]
        ap = os.path.join(REPO, rel)
        if not os.path.exists(ap):
            miss.append(rel)
            continue
        got = sha(ap)
        rows.append(rel)
        if got != want:
            drift.append({"path": rel, "freeze": want, "now": got})
    head = subprocess.run(["git", "-C", REPO, "rev-parse", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    staged = subprocess.run(["git", "-C", REPO, "diff", "--cached", "--name-only"],
                            capture_output=True, text=True).stdout.split()
    out = {
        "rc_id": fz["rc_id"], "freeze_sha256": sha(FREEZE), "repo": fz["repo"],
        "files_checked": len(rows), "files_missing": miss, "files_drifted": drift,
        "head_now": head, "head_at_freeze": fz["head"], "branch_at_freeze": fz["branch"],
        "head_matches_freeze": head == fz["head"],
        "staged_files_now": len(staged),
        "clean": (not drift) and (not miss) and head == fz["head"] and not staged,
        "meaning": "byte-identity of the named files at freeze time vs now; "
                   "it does not prove the freeze enumerated every change.",
    }
    with open(os.path.join(RC, "RC_SOURCE_VERIFY.json"), "w") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print(json.dumps(out, indent=1))


if __name__ == "__main__":
    main()
