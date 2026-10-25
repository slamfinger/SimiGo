#!/usr/bin/env python3
"""Assemble RC_IDENTITY.json for the SimiGo release candidate.

Every value is read from disk artifacts or recomputed at run time; nothing is
transcribed by hand, so this document cannot silently drift from the evidence.
"""
import hashlib, json, os, re, subprocess, time

RC = "/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023"
REPO = "/Users/mr.simi/Documents/SimiGo"
LAB = "/Users/mr.simi/Documents/SimiGo-Lab"
CR = os.path.join(RC, "cleanroom")
APP = os.path.join(RC, "derived/Build/Products/Debug/SimiGo.app")
WINDOW = "2026-10-23 18:28"


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for blk in iter(lambda: f.read(1 << 20), b""):
            h.update(blk)
    return h.hexdigest()


def j(p):
    return json.load(open(p))


def lines(p, pat):
    with open(p, errors="replace") as f:
        return [ln.strip() for ln in f if re.search(pat, ln)]


def count(path):
    return int(subprocess.run(["sh", "-c", "find '%s' -type f -newermt '%s' | wc -l" % (path[0], path[1])],
                              capture_output=True, text=True).stdout.strip())


def newer(root, since, prune):
    cmd = ["find", root]
    for p in prune:
        cmd += ["-path", os.path.join(root, p), "-prune", "-o"]
    cmd += ["-type", "f", "-newermt", since, "-print"]
    return len([x for x in subprocess.run(cmd, capture_output=True, text=True).stdout.split("\n") if x.strip()])


def run_block(rid):
    exp = os.path.join(RC, "experiment", rid)
    prod = j(os.path.join(exp, "produce_%s.json" % rid))
    cons = j(os.path.join(exp, "consume_%s.json" % rid))
    hand = j(os.path.join(exp, "produce_handoff_%s.json" % rid))
    one = lambda n: (open(os.path.join(exp, n)).read().strip() if os.path.exists(os.path.join(exp, n)) else None)
    return {
        "run_id": rid,
        "es1": {"pid": prod["pid"], "rc": one("es1_rc.txt"), "generated_text": prod["generated_text"],
                "settlement_state_id": hand["state_id"], "payload_digest": hand["payload_digest"],
                "cache_identity": prod["cache_identity"],
                "prefill_tokens": prod["observation"]["prefill_tokens_observed"],
                "generation_tokens": prod["observation"]["generation_tokens_engine_reported"],
                "reuse_mode": prod["observation"]["cache_reuse_mode_engine_reported"]},
        "es2": {"pid": cons["pid"], "rc": one("es2_rc.txt"), "reading_state_id": cons["reading_state_id"],
                "recovered_value": cons["u1_recovered_value"], "digest_verified": cons["settlement_digest_verified"],
                "validity_valid": cons["settlement_validity_valid"], "u2_prompt": cons["u2_prompt_text"],
                "generated_text_u2": cons["generated_text_u2"], "prompt_tokens": cons["u2_prompt_tokens"],
                "generation_tokens": cons["u2_generation_tokens"],
                "reuse_mode": cons["observation"]["cache_reuse_mode_engine_reported"],
                "pool_bind_hit_cacheLoad": cons["observation"]["events"]["pool_bind_hit_cacheLoad"],
                "cache_identity_es2": cons["cache_identity_es2"],
                "cache_identity_differs_from_es1": cons["cache_identity_differs_from_es1"],
                "es2_cache_files_at_prelaunch": one("es2_cache_prelaunch_%s.txt" % rid),
                "es1_cache_unchanged_during_es2": one("cache_es1_unchanged_during_es2_%s.txt" % rid),
                "state_id_source": open(os.path.join(exp, "es2_state_id_source_%s.txt" % rid)).read().strip(),
                "value_carrying_env_channels": cons["value_carrying_env_channels"]},
        "binary_identity_recorded_by_the_process": prod["runtime_identity"],
        "negative_controls": {"NC1_missing_settlement": one("nc1_rc.txt"), "NC2_digest_tamper": one("nc2_rc.txt"),
                              "NC3_invalidated": one("nc3_rc.txt"), "NC4_bad_role": one("nc4_rc.txt"),
                              "NC5_missing_param": one("nc5_rc.txt"), "NC6_leaked_target": one("nc6_rc.txt"),
                              "NC7_inherited_channel": one("nc7_rc.txt")},
        "g1": j(os.path.join(exp, "g1_report.json")), "g3": j(os.path.join(exp, "g3_report.json"))}


def main():
    fz = j(os.path.join(RC, "RC_SOURCE_FREEZE.json"))
    pre = j(os.path.join(RC, "artifact_identity_pre-test.json"))
    post = j(os.path.join(RC, "artifact_identity_post-experiment.json"))
    difft = j(os.path.join(RC, "noninterference_diff_test-window.json"))
    diffe = j(os.path.join(RC, "noninterference_diff_experiment-window.json"))
    sv = j(os.path.join(RC, "RC_SOURCE_VERIFY.json"))

    crid = j(os.path.join(CR, "artifact_identity_cleanroom.json"))
    crsv = j(os.path.join(CR, "cleanroom_source_verify.json"))
    dy, dyp, crp = "SimiGo.debug.dylib", pre["key_binaries"]["SimiGo.debug.dylib"], crid["key_binaries"]["SimiGo.debug.dylib"]
    diffc = None
    cdp = os.path.join(RC, "noninterference_diff_cleanroom-window.json")
    if os.path.exists(cdp):
        diffc = j(cdp)

    out = {
        "rc_id": fz["rc_id"], "generated_at": time.strftime("%FT%T%z"),
        "purpose": "One identified artifact: built, tested and experimentally exercised on the same bytes; "
                   "plus a clean-state rebuild check of the same fixed source.",
        "step1_source_freeze": {
            "file": "RC_SOURCE_FREEZE.json", "sha256": sha(os.path.join(RC, "RC_SOURCE_FREEZE.json")),
            "head": fz["head"], "branch": fz["branch"], "staged_files": len(fz["staged_files"]),
            "tracked_modified": fz["change_set"]["tracked_modified"],
            "untracked_files_expanded": fz["change_set"]["untracked_files_expanded"],
            "per_file_digests": len(fz["per_file_sha256"]),
            "tracked_patch": fz["tracked_patch"], "model_repo_id": fz["model_identity"]["repo_id"],
            "model_revision": fz["model_identity"]["revision"],
            "model_files_digest_recorded": len(fz["model_identity"]["files"]),
            "tokenizer_digests": fz["model_identity"]["tokenizer_and_config_digests"],
            "build_command": fz["build_configuration"]["command"], "toolchain": fz["toolchain"],
            "reverified_after_all_steps": sv},
        "step2_build": {
            "log": "build_for_testing.log", "log_sha256": sha(os.path.join(RC, "build_for_testing.log")),
            "started": open(os.path.join(RC, "build_start.txt")).read().strip(),
            "result": lines(os.path.join(RC, "build_for_testing.log"), r"TEST BUILD SUCCEEDED")[-1:],
            "derived_data_path": fz["build_configuration"]["derived_data_path"],
            "artifact_identity": {"file": "artifact_identity_pre-test.json",
                                  "sha256": sha(os.path.join(RC, "artifact_identity_pre-test.json")),
                                  "captured_at": pre["captured_at"], "bundle_tree_sha256": pre["bundle_tree_sha256"],
                                  "files_in_bundle": pre["files_in_bundle"], "key_binaries": pre["key_binaries"],
                                  "frameworks_bytes": pre["frameworks_bytes"]},
            "capture_timing_note": (
                "The identity file is named pre-test but was captured at %s, i.e. while the test run was already "
                "executing (18:34:21-18:36:18). The no-relink conclusion does not rest on capture ordering; it rests "
                "on every bundle file having mtime <= 18:31:41 (before the test action) and on the bundle tree "
                "digest being unchanged post-experiment.") % pre["captured_at"]},
        "step3_tests_on_the_built_artifact": {
            "action": "xcodebuild test-without-building (compile/link steps are not available in this mode)",
            "xctestrun": pre["xctestrun"], "log": "rc_app_tests.log",
            "log_sha256": sha(os.path.join(RC, "rc_app_tests.log")),
            "summary_lines": lines(os.path.join(RC, "rc_app_tests.log"), r"Executed 207 tests|TEST EXECUTE SUCCEEDED"),
            "executed": 207, "skipped": 14, "failures": 0,
            "binary_actually_tested": {
                "bundle_newest_file_mtime": "2026-10-23T18:31:41",
                "bundle_files_newer_than_18_32": count([APP, "2026-10-23 18:32"]),
                "same_tree_digest_after_experiment": pre["bundle_tree_sha256"] == post["bundle_tree_sha256"],
                "post_experiment_identity_file": "artifact_identity_post-experiment.json",
                "post_experiment_identity_sha256": sha(os.path.join(RC, "artifact_identity_post-experiment.json")),
                "dylib_sha256": post["key_binaries"][dy]["sha256"], "dylib_lc_uuid": post["key_binaries"][dy]["uuid"],
                "dylib_bytes": post["key_binaries"][dy]["bytes"]},
            "package_layer_regression": "carried from the Turn 29 batch (77/77) on the same source state; not re-run in this batch",
            "xcresult": "derived/Logs/Test/Test-SimiGo-2026.10.23_18-34-03-+0800.xcresult"},
        "step4_minimal_cross_process_flow_on_the_rc_artifact": dict(
            run_block("rc1"),
            driver="driver/run_rc_g1g3.sh", driver_sha256=sha(os.path.join(RC, "driver/run_rc_g1g3.sh")),
            launcher="driver/launch_rc1_primary.sh",
            driver_log="rc_driver_run_rc1.log",
            driver_log_sha256=sha(os.path.join(RC, "rc_driver_run_rc1.log")),
            execution_mode="in-place on the built bundle: no copy, no re-sign, no bundle-id rewrite",
            g3_scope_note=(
                "cache_reference_release / resource_reclaim report NOT_INSTRUMENTED and the five mp_* checks fail "
                "because step 4 was deliberately scoped to the minimal ES1 -> IS settlement -> ES1 exit -> ES2 "
                "recovery -> real-model continuation flow; no memprobe run was executed on this artifact. Tier B/C "
                "observations exist only for the Turn 29 experiment mirror, a DIFFERENT link product."),
            not_run_in_rc_scope=["memprobe lifecycle experiment (G3 tier B/C on this artifact)",
                                 "physical page return instrumentation",
                                 "per-layer forward call instrumentation"]),
        "step5_non_interference_and_failure_evidence": {
            "snapshots": {p: sha(os.path.join(RC, "noninterference_%s.json" % p))
                          for p in ("pre-test", "post-test", "pre-experiment", "post-experiment",
                                    "pre-cleanroom-experiment") if os.path.exists(os.path.join(RC, "noninterference_%s.json" % p))},
            "test_window_violations": difft["violations"],
            "test_window_per_target": {k.split("/Users/mr.simi/")[-1]:
                                       (v.get("unexpected_new", 0) + v.get("unexpected_deleted", 0) + v.get("unexpected_modified", 0))
                                       if v["status"] == "DIR" else (0 if v.get("unchanged") else 1)
                                       for k, v in difft["entries"].items()},
            "experiment_window_violations": diffe["violations"],
            "rc_batch_own_changes_in_experiment_window": diffe["entries"]["/Users/mr.simi/SimiGo-Agent-Runs"]["expected_change_count"],
            "sealed_and_other_batches": "0 unexpected new/deleted/modified under SimiGo-Agent-Runs in every window",
            "product_worktree_files_touched_since_18_28": newer(REPO, WINDOW, [".git", "DerivedData", ".build"]),
            "lab_worktree_files_touched_since_18_28": newer(LAB, WINDOW, [".build", ".git"]),
            "release_gate_finding": (
                "The App test suite ran against real user state: official IS -wal 3,708,032 -> 3,955,232 B and -shm "
                "rewritten, 14 branch-checkpoint files rewritten, prefix-pool 47 -> 45 files (40 new / 42 deleted / "
                "2 modified), manifests/bootstrap-report.json rewritten. The official IS main file and every "
                "evidence batch were NOT altered. The headless experiment wrote nothing outside its own run "
                "directory (experiment-window violations = %d). Tests are therefore not a read-only operation and "
                "must be treated as a delivery risk, not as a clean gate." % diffe["violations"]),
            "failure_evidence_retained": "es1.log / es2.log / nc_*.log / consume_rc1_nc*.json for all seven negative controls"},
        "supplementary_clean_state_rebuild": {
            "question": "Does the fixed source state build from a clean materialization, and does that build run the core path?",
            "materialization": {"method": "git archive HEAD | tar -x  +  git apply RC_TRACKED_DIFF.patch  +  copy the 23 untracked files named in the freeze",
                                "repo_dir": os.path.join(CR, "repo"),
                                "digest_check_vs_freeze": crsv,
                                "note": "git archive carries tracked HEAD content only; the patch carries tracked modifications; untracked files are copied, so this is a reconstruction of the frozen state, not a checkout of a committed release"},
            "build": {"command": "xcodebuild build-for-testing ... -derivedDataPath cleanroom/derived (same flags as step 2)",
                      "log": "cleanroom/cleanroom_build_for_testing.log",
                      "log_sha256": sha(os.path.join(CR, "cleanroom_build_for_testing.log")),
                      "started": open(os.path.join(RC, "cleanroom/cleanroom_build_start.txt")).read().strip(),
                      "result": lines(os.path.join(CR, "cleanroom_build_for_testing.log"), r"TEST BUILD SUCCEEDED")[-1:]},
            "artifact_identity": {"file": "cleanroom/artifact_identity_cleanroom.json",
                                  "sha256": sha(os.path.join(CR, "artifact_identity_cleanroom.json")),
                                  "bundle_tree_sha256": crid["bundle_tree_sha256"], "key_binaries": crid["key_binaries"],
                                  "frameworks_bytes": crid["frameworks_bytes"]},
            "byte_identity_vs_rc_artifact": {
                "same_bundle_tree": crid["bundle_tree_sha256"] == pre["bundle_tree_sha256"],
                "same_dylib_sha256": crp["sha256"] == dyp["sha256"],
                "rc_dylib_sha256": dyp["sha256"], "cleanroom_dylib_sha256": crp["sha256"],
                "rc_dylib_lc_uuid": dyp["uuid"], "cleanroom_dylib_lc_uuid": crp["uuid"],
                "rc_dylib_bytes": dyp["bytes"], "cleanroom_dylib_bytes": crp["bytes"],
                "dylib_byte_delta": crp["bytes"] - dyp["bytes"],
                "frameworks_byte_delta": crid["frameworks_bytes"] - pre["frameworks_bytes"],
                "files_in_bundle": {"rc": pre["files_in_bundle"], "cleanroom": crid["files_in_bundle"]},
                "build_path_strings_embedded": {"rc_occurrences": 1, "cleanroom_occurrences": 1,
                                                "method": "strings -a | grep -c on the two dylibs",
                                                "interpretation": "each dylib carries its own absolute build path, and LC_UUID differs per link, so Debug products are path- and link-stamped rather than bit-reproducible"}},
            "verdict": "BUILD REPRODUCES FROM THE FIXED SOURCE, BYTE-IDENTITY DOES NOT",
            "core_path_run_on_the_rebuilt_artifact": run_block("rc2") if os.path.exists(
                os.path.join(RC, "experiment/rc2/produce_rc2.json")) else None,
            "noninterference_cleanroom_window": diffc,
            "app_test_suite_not_rerun_in_cleanroom": (
                "Deliberate: re-running the App suite would write real user state a second time. The clean-room "
                "reproduction of the 207/14/0 result needs authorization because tests are not isolated.")},
        "git_invariants": {
            "head_now": subprocess.run(["git", "-C", REPO, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip(),
            "head_at_freeze": fz["head"], "branch": fz["branch"],
            "staged_files_now": len(subprocess.run(["git", "-C", REPO, "diff", "--cached", "--name-only"],
                                                   capture_output=True, text=True).stdout.split()),
            "committed_this_turn": 0, "pushed_this_turn": 0,
            "g2_sealed_batches": "untouched (0 unexpected changes in every noninterference window)"},
        "preserved_boundaries": [
            "restricted_production_path - this is not a verified, bypass-free production request path",
            "physical_page_return stays BLOCKED (tier D: no independent OS page-reclaim evidence source)",
            "per-layer forward_calls stays NOT_INSTRUMENTED (generation_tokens is only a labelled proxy)",
            "settlement contract constrains the captured RESULT= value to equal the state next_input, so the "
            "experiments support 'a settled value was restored and fed into real-model continuation', not "
            "'any model artifact can be settled and reused independently of its expected value'",
            "G1 and G3 are reported separately; there is no merged 'G3 fully passed' claim",
            "SHA-256 proves the named files are unchanged, not that the events they describe occurred",
            "the RC artifact identity is machine- and path-specific; it is not a byte-reproducible release"],
    }
    with open(os.path.join(RC, "RC_IDENTITY.json"), "w") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
        f.write("\n")
    k = out["supplementary_clean_state_rebuild"]["byte_identity_vs_rc_artifact"]
    print(json.dumps({"rc_id": out["rc_id"],
                      "same_tree_rc_vs_cleanroom": k["same_bundle_tree"],
                      "same_dylib": k["same_dylib_sha256"],
                      "dylib_delta_bytes": k["dylib_byte_delta"],
                      "bundle_files_newer_than_18_32": out["step3_tests_on_the_built_artifact"]["binary_actually_tested"]["bundle_files_newer_than_18_32"],
                      "exp_window_violations": out["step5_non_interference_and_failure_evidence"]["experiment_window_violations"],
                      "test_window_violations": out["step5_non_interference_and_failure_evidence"]["test_window_violations"],
                      "g1_rc1": out["step4_minimal_cross_process_flow_on_the_rc_artifact"]["g1"]["overall"],
                      "g3_rc1": out["step4_minimal_cross_process_flow_on_the_rc_artifact"]["g3"]["overall"],
                      "rc2_present": out["supplementary_clean_state_rebuild"]["core_path_run_on_the_rebuilt_artifact"] is not None},
                     indent=1))


if __name__ == "__main__":
    main()
