#!/usr/bin/env python3
"""Self-check for the RC1 batch: manifest, identity chain, non-interference, git.

Run after everything else in the batch. Prints a one-page verdict; exits 1 on any
failed invariant so it can gate a release decision.
"""
import hashlib, json, os, subprocess, sys

RC = "/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023"
REPO = "/Users/mr.simi/Documents/SimiGo"
I = json.load(open(os.path.join(RC, "RC_IDENTITY.json")))
s3, s5, CR = (I["step3_tests_on_the_built_artifact"],
              I["step5_non_interference_and_failure_evidence"],
              I["supplementary_clean_state_rebuild"])
b = CR["byte_identity_vs_rc_artifact"]
res = []


def check(name, ok, detail):
    res.append({"item": name, "ok": bool(ok), "detail": detail})


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for blk in iter(lambda: f.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


# manifest
rows, bad = [], []
for ln in open(os.path.join(RC, "MANIFEST_SHA256_rc1.txt")):
    if ln.startswith("#"):
        continue
    h, rel = ln.rstrip("\n").split("  ", 1)
    rows.append(rel)
    p = os.path.join(RC, rel)
    if not os.path.exists(p):
        bad.append("MISSING " + rel)
    elif not h.startswith("SKIPPED") and sha(p) != h:
        bad.append("MISMATCH " + rel)
check("manifest_rehash", not bad, "%d rows / %d bad" % (len(rows), len(bad)))

# step 1: freeze reverified
sv = I["step1_source_freeze"]["reverified_after_all_steps"]
check("source_freeze_reverified", sv["clean"], "%d files, drift %d, head_matches %s, staged %d"
      % (sv["files_checked"], len(sv["files_drifted"]), sv["head_matches_freeze"], sv["staged_files_now"]))

# steps 2/3/4 same bytes
bt = s3["binary_actually_tested"]
check("build_equals_test_equals_experiment",
      bt["same_tree_digest_after_experiment"] and bt["bundle_files_newer_than_18_32"] == 0,
      "newer-than-18:32 files=%d, tree same=%s, dylib=%s UUID=%s"
      % (bt["bundle_files_newer_than_18_32"], bt["same_tree_digest_after_experiment"],
         bt["dylib_sha256"][:8], bt["dylib_lc_uuid"][:8]))

# step 4 outcome
s4 = I["step4_minimal_cross_process_flow_on_the_rc_artifact"]
check("g1_pass_on_rc_artifact", s4["g1"]["overall"] == "PASS",
      "ES1 %s -> %s; ES2 %s recovered '%s' -> %s" % (s4["es1"]["pid"], s4["es1"]["generated_text"],
                                                    s4["es2"]["pid"], s4["es2"]["recovered_value"],
                                                    s4["es2"]["generated_text_u2"]))
check("negative_controls_expected", all(v.endswith(("rc=6", "rc=2", "rc=7")) for v in s4["negative_controls"].values()),
      json.dumps(s4["negative_controls"]))

# step 5
check("experiment_window_non_interference", s5["experiment_window_violations"] == 0,
      "violations=%d (test window violations=%d are the App suite's own writes)"
      % (s5["experiment_window_violations"], s5["test_window_violations"]))
check("worktrees_untouched",
      s5["product_worktree_files_touched_since_18_28"] == 0 and s5["lab_worktree_files_touched_since_18_28"] == 0,
      "product %d, lab %d" % (s5["product_worktree_files_touched_since_18_28"],
                              s5["lab_worktree_files_touched_since_18_28"]))

# clean-room
check("cleanroom_build_succeeds", bool(CR["build"]["result"]), str(CR["build"]["result"]))
check("cleanroom_source_matches_freeze", not CR["materialization"]["digest_check_vs_freeze"]["bad"],
      "%d/%d" % (CR["materialization"]["digest_check_vs_freeze"]["checked"],
                 CR["materialization"]["digest_check_vs_freeze"]["checked"]))
rc2 = CR["core_path_run_on_the_rebuilt_artifact"]
check("cleanroom_core_path_g1", rc2 and rc2["g1"]["overall"] == "PASS",
      "G1 %s, ES2 -> %s" % (rc2 and rc2["g1"]["overall"], rc2 and rc2["es2"]["generated_text_u2"]))
check("cleanroom_window_non_interference", CR["noninterference_cleanroom_window"]["violations"] == 0,
      "violations=%d" % CR["noninterference_cleanroom_window"]["violations"])
check("byte_identity_NOT_established_across_rebuild",
      b["same_bundle_tree"] is False and b["same_dylib_sha256"] is False,
      "dylib delta %+d B, LC_UUID differs, tree differs" % b["dylib_byte_delta"])

# git
head = subprocess.run(["git", "-C", REPO, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
staged = subprocess.run(["git", "-C", REPO, "diff", "--cached", "--name-only"], capture_output=True, text=True).stdout.split()
check("git_invariants", head == I["git_invariants"]["head_at_freeze"] and not staged,
      "HEAD %s, staged %d, committed 0, pushed 0" % (head[:12], len(staged)))

out = {"rc_id": I["rc_id"], "checked_at": subprocess.run(["date", "+%FT%T%z"], capture_output=True, text=True).stdout.strip(),
       "items": res, "failed": [r["item"] for r in res if not r["ok"]]}
with open(os.path.join(RC, "RC_BATCH_SELF_CHECK.json"), "w") as f:
    json.dump(out, f, indent=1, ensure_ascii=False)
    f.write("\n")
for r in res:
    print(("PASS " if r["ok"] else "FAIL ") + r["item"].ljust(38) + str(r["detail"])[:130])
print("\nfailed items:", out["failed"] or "none")
sys.exit(1 if out["failed"] else 0)
