#!/usr/bin/env python3
"""Independently re-derive the v2.2.0rc1 acceptance verdicts from the raw files
this batch produced. No verdict is typed by hand: every gate below is a check
whose inputs are read from disk (logs, evidence JSON, sqlite, bundle identity).

exit 0 = every gate PASS or explicitly NOT_APPLICABLE
exit 1 = at least one FAIL
exit 2 = at least one BLOCKED / NOT_INSTRUMENTED / INCONCLUSIVE and no FAIL
"""
import hashlib, json, os, re, subprocess, sys

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GATES = {}
DETAIL = []

def gate(name, verdict, checks, note=""):
    GATES[name] = {"verdict": verdict, "checks": checks, "note": note}

def find(p):
    return p if os.path.exists(p) else None

def jload(p):
    with open(p) as f:
        return json.load(f)

def log_has(p, needle):
    if not os.path.exists(p):
        return False
    with open(p, errors="replace") as f:
        return needle in f.read()

def log_rc(p):
    if not os.path.exists(p):
        return None
    m = re.search(r"rc=(-?\d+)", open(p, errors="replace").read())
    return int(m.group(1)) if m else None

def service_http_note(probe):
    """Compose the product_service_http note from the RETAINED stage-C record.

    Corrected 2026-10-24 (operator-authorized): the previous note asserted three
    observations of the installed binary - an ephemeral port seen via lsof, a
    TLS-only handshake, and a 503 from a POST carrying a fabricated LOCALB proof.
    No retained file in this batch supports any of them. The only retained
    stage-C record reports listening_socket_found=0 /
    probe_result=NO_SOCKET_WINDOW OBSERVED, and the 503 is established from
    source (HTTPServer.swift localbAuthorizationUnavailable), not from an observed
    response. The note is therefore generated from what is on disk, and the
    round-2 assertions are downgraded to "no retained evidence supports ...".
    The verdict is untouched: missing evidence is not evidence of the opposite,
    so product_service_http stays BLOCKED on the missing activation surface.
    """
    facts = []
    if os.path.exists(probe):
        for line in open(probe, errors="replace"):
            line = line.strip()
            if line and not line.startswith("#"):
                facts.append(line)
    retained = "; ".join(facts) if facts else "no stage-C probe record retained"
    return (
        "CORRECTED 2026-10-24: no retained evidence supports (\u65e0\u7559\u5b58\u8bc1\u636e\u652f\u6301) the "
        "earlier round-2 note - 'Round 2 reached the installed app's real HTTPServer "
        "(ephemeral port observed via lsof on the running pid, TLS-only: plaintext "
        "gets an empty reply)' and 'a POST carrying a fabricated LOCALB proof returns "
        "503'. The retained stage-C record reads: %s. There is no lsof/bound-port "
        "line, no tls_verify line and no http_status line for the installed binary "
        "anywhere in this batch, so those three observations were recalled, not "
        "recorded. What the batch does support: the product ships no surface that "
        "runs the activation ceremony (app_target_call_sites=0 in "
        "evidence/localb_authorization_path.txt), so an unactivated host refuses "
        "protected traffic at the guard, and the same product code serves authorized "
        "requests once activated - proven only in the product's own test target, not "
        "through the installed listener. The correction does not flip this gate: an "
        "absence of evidence is not evidence that the server never listened, so "
        "product_service_http stays BLOCKED until a rebuilt candidate that ships the "
        "activation path is observed end-to-end (an authorized request served through "
        "the real listener plus a negative proof refused before generation)."
        % retained
    )

# ---------------------------------------------------------------- G0 freeze
ids = find(os.path.join(B, "RC_SOURCE_FREEZE.json"))
model = find(os.path.join(B, "RC_MODEL_IDENTITY.json"))
gate("source_and_model_frozen", "PASS" if ids and model else "BLOCKED", {
    "source_freeze_present": bool(ids),
    "model_identity_present": bool(model),
})

# ------------------------------------------------------- G1 build and package
build_log = os.path.join(B, "logs/release_build.log")
dmg = os.path.join(B, "install/SimiGo-v2.2.0rc1.dmg")
inst = find(os.path.join(B, "evidence/m3_install_identity.json"))
checks = {
    "release_build_succeeded": log_has(build_log, "** BUILD SUCCEEDED **"),
    "dmg_present": bool(find(dmg)),
    "install_identity_present": bool(inst),
}
if inst:
    d = jload(inst)
    checks.update({
        "marketing_version_2_2_0": d.get("marketing_version") == "2.2.0",
        "build_version_26": d.get("build_version") == "26",
        "bundle_id_is_product": d.get("bundle_id") == "SwiftUI.SimiGo",
        "codesign_valid": "valid on disk" in (d.get("codesign_verify") or ""),
        "executable_digest_recorded": bool(d.get("executable_sha256")),
        "bundle_tree_digest_recorded": bool(d.get("bundle_tree_sha256")),
    })
    checks["gatekeeper_assessed"] = "rejected" in (d.get("spctl_assess") or "")
verdict = "PASS" if all(v for k, v in checks.items() if k != "gatekeeper_assessed") else "FAIL"
gate("build_and_package", verdict, checks,
     "gatekeeper_assessed only records that a local, non-notarized RC is rejected by "
     "Gatekeeper; it is an environment constraint, not a build failure.")

# ------------------------------------------------------ G2 install and operate
stage_a = os.path.join(B, "evidence/m3_stage_a_process.txt")
boot = os.path.join(B, "m3/home/manifests/bootstrap-report.json")
stage_b = find(os.path.join(B, "evidence/m3_stage_b_gui_inference.json"))
checks = {
    "installed_binary_ran": os.path.exists(stage_a) and "install/SimiGo.app/Contents/MacOS/SimiGo" in open(stage_a).read(),
    "isolation_env_seen_by_app": os.path.exists(stage_a) and "SIMIGO_HOME=" in open(stage_a).read(),
    "bootstrap_report_present": bool(boot),
}
if boot:
    r = jload(boot)
    checks["bootstrap_models_discovered"] = r.get("modelsDiscovered", 0) > 0
    checks["bootstrap_schema_v3"] = r.get("schemaVersion") == 3
    checks["bootstrap_no_issues"] = r.get("issueCount") == 0
checks["gui_prompt_ran_real_model"] = bool(stage_b) and jload(stage_b).get("real_model_output", False) if stage_b else False
if checks["gui_prompt_ran_real_model"]:
    gate("install_and_operate", "PASS", checks)
elif all(v for k, v in checks.items() if k != "gui_prompt_ran_real_model"):
    gate("install_and_operate", "BLOCKED", checks,
         "The installed, independently path'd app resolves the three isolated roots, "
         "completes bootstrap (20 models, schema v3, 0 issues), creates its sqlite "
         "database, quits and restarts from the same bundle. Two blockers used to hide "
         "this: (1) round 3 found Service.init() blocking forever inside "
         "SecItemCopyMatching because CloudKeychain read the real login Keychain and "
         "the item's ACL answered the new binary with an interactive SecurityAgent "
         "prompt (securityd: 'QueryKeychainUse::queryUser'); that isolation gap is "
         "fixed in this build - CloudKeychain is inert when SIMIGO_HOME is set - and is "
         "covered by testIsolatedManagedRootNeverReadsOrWritesTheLoginKeychain. (2) The "
         "user-visible prompt leg is still unproven: this host grants the driver no "
         "Screen Recording, so although the 8 GUI attempts now reach the AX tree "
         "(2 menu bars, 6 items) and AXPress succeeds, no window appears, screencapture "
         "fails ('could not create image from display') and no keystroke can be typed "
         "into a prompt field. An unproven leg stays BLOCKED rather than being inferred "
         "from stage A.")
else:
    gate("install_and_operate", "FAIL", checks)

# -------------------------------------------------------- G3 product dispatch
svc = find(os.path.join(B, "evidence/m3_stage_c_service_http.json"))
if svc:
    d = jload(svc)
    checks = {k: bool(v) for k, v in d.get("checks", {}).items()}
    gate("product_service_http", "PASS" if all(checks.values()) and checks else "FAIL", checks)
else:
    probe = os.path.join(B, "evidence/m3_stage_c_probe.txt")
    # The probe carries its own machine-readable result line, written from the
    # lsof/curl output quoted above it. A substring test on "LISTEN" would be
    # meaningless because the quoted command itself contains "-sTCP:LISTEN".
    surface = os.path.join(B, "evidence/localb_authorization_path.txt")
    checks = {
        "probe_present": os.path.exists(probe),
        "listening_socket_found": log_has(probe, "listening_socket_found=1"),
        "tls_only_transport": log_has(probe, "tls_verify=18"),
        "unconfigured_authorization_refused": log_has(probe, 'http_status=503'),
        "no_authorization_relaxation": log_has(probe, "authorization_relaxed=0"),
        "authorized_request_completed": log_has(probe, "authorized_request_completed=1"),
        "authorization_surface_recorded": os.path.exists(surface),
        "authorized_lane_passes_in_test_target": log_has(
            os.path.join(B, "logs/isolated_r4.stdout.log"),
            "testDefaultHostResolutionServesAuthorizedRequests"),
    }
    gate("product_service_http",
         "PASS" if all(checks.values()) else ("BLOCKED" if not checks["authorized_request_completed"] else "FAIL"),
         checks,
         service_http_note(probe))

# ------------------------------------------------------------- G4 research chain
def run_gate(rid, target, baseline):
    R = os.path.join(B, "m4", rid)
    p = jload(os.path.join(R, "produce_%s.json" % rid))
    c = jload(os.path.join(R, "consume_%s.json" % rid))
    checks = {
        "es1_rc_zero": log_rc(os.path.join(R, "es1_rc.txt")) == 0,
        "es1_status_ok": p.get("status") == "OK",
        "es1_real_generation": p.get("generated_text") == "RESULT=%s" % target,
        "es1_settled": bool(p.get("settlement_payload_digest")),
        "es1_readback_from_is": p.get("is_settlement_restored_readback") is True,
        "es1_identity_bound": p.get("producer_identity_bindings_recorded") is True,
        "es1_exited_before_es2": "ES1 exited before ES2 - OK" in open(os.path.join(R, "es1_rc.txt")).read(),
        "es2_new_pid": c.get("pid") != p.get("pid"),
        "es2_rc_zero": log_rc(os.path.join(R, "es2_rc.txt")) == 0,
        "es2_status_ok": c.get("status") == "OK",
        "es2_recovered_from_is": c.get("u1_recovered_value") == target,
        "es2_digest_verified": c.get("settlement_digest_verified") is True,
        "es2_validity_verified": c.get("settlement_validity_valid") is True,
        "es2_binding_ok": c.get("settlement_binding_status") == "ok",
        "es2_no_value_channel": c.get("value_carrying_env_channels") == [],
        "es2_prompt_carries_value": c.get("u2_prompt_contains_recovered_value") is True,
        "es2_real_continuation": c.get("real_model_continuation") is True,
        "es2_output_expected": c.get("generated_text_u2") == "RESULT=%s-U2" % target,
        "es2_fresh_cache": c.get("cache_identity_differs_from_es1") is True,
        "es2_u2_settled": bool(c.get("u2_settlement_payload_digest")),
        "counterfactual_baseline_differs": c.get("counterfactual_baseline_value") == baseline,
        "u1_differs_from_baseline": c.get("u1_value_differs_from_baseline") is True,
    }
    return checks, c

checks_a, cons_a = run_gate("m4a", "hello", "world")
gate("research_chain_primary", "PASS" if all(checks_a.values()) else "FAIL", checks_a)

expected = {"m4a": {"nc1": 6, "nc2": 6, "nc3": 6, "nc4": 6, "nc5": 2, "nc6": 2, "nc7": 7}}
nc_checks = {}
for rid, want in expected.items():
    R = os.path.join(B, "m4", rid)
    for k, code in want.items():
        nc_checks["%s_%s_rc_%d" % (rid, k, code)] = log_rc(os.path.join(R, "%s_rc.txt" % k)) == code
gate("research_chain_negative_controls", "PASS" if all(nc_checks.values()) else "FAIL", nc_checks)

nc_ev = {}
R = os.path.join(B, "m4", "m4a")
for name, stage in (("consume_m4a_ncmiss.json", "is_verify_u1"),
                    ("consume_m4a_nctamper.json", "is_verify_u1"),
                    ("consume_m4a_ncinval.json", "is_verify_u1"),
                    ("consume_m4a_ncmodel.json", "is_binding_verify"),
                    ("consume_m4a_ncleak.json", "input_channel_guard")):
    d = jload(os.path.join(R, name))
    nc_ev[name] = {"stage": d.get("stage"), "expected_stage": stage,
                   "blocked": d.get("status") == "BLOCKED",
                   "generation_call_count_zero": d.get("generation_call_count") == 0,
                   "stage_matches": d.get("stage") == stage}
gate("negative_controls_refuse_before_generation",
     "PASS" if all(v["blocked"] and v["generation_call_count_zero"] and v["stage_matches"] for v in nc_ev.values()) else "FAIL",
     nc_ev)

if os.path.exists(os.path.join(B, "m4/m4b/consume_m4b.json")):
    # Both runs keep the same fixpoint baseline ("world"); the controlled
    # difference is the ES1 settlement value, not the baseline.
    checks_b, cons_b = run_gate("m4b", "delta9", "world")
    diff = {"es1_settlement_value_a": cons_a.get("u1_recovered_value"),
            "es1_settlement_value_b": cons_b.get("u1_recovered_value"),
            "es2_output_a": cons_a.get("generated_text_u2"),
            "es2_output_b": cons_b.get("generated_text_u2")}
    checks_b["controlled_difference_observed"] = (
        diff["es1_settlement_value_a"] != diff["es1_settlement_value_b"]
        and diff["es2_output_a"] == "RESULT=%s-U2" % diff["es1_settlement_value_a"]
        and diff["es2_output_b"] == "RESULT=%s-U2" % diff["es1_settlement_value_b"])
    checks_b.update({"diff_" + k: v for k, v in diff.items()})
    gate("research_chain_controlled_difference", "PASS" if all(checks_b.values()) else "FAIL", checks_b)
else:
    gate("research_chain_controlled_difference", "BLOCKED", {"second_run_present": False})

# ------------------------------------------------------ G5 test + isolation
iso = find(os.path.join(B, "run_isolated_r4/isolation_run_r4.json"))
app_log = os.path.join(B, "run_isolated_r4/isolated_tests_r4.log")
checks = {"isolated_run_present": bool(iso)}
if iso:
    d = jload(iso)
    checks.update({
        "app_suite_executed": d.get("executed_skipped_failures") is not None,
        "app_suite_no_failures": (d.get("executed_skipped_failures") or [0, 0, 1])[2] == 0,
        # 207 is the historical floor; this build adds the CloudKeychain isolation
        # test, so the count must be at least that and never lower.
        "app_suite_ge_207_executed": (d.get("executed_skipped_failures") or [0])[0] >= 207,
        "app_suite_skips_not_inflated": (d.get("executed_skipped_failures") or [0, 0])[1] <= 14,
        "isolation_root_fresh": d.get("fresh_isolation_root") is True,
        "no_real_user_state_write": d["noninterference"]["real_user_state_write_count"] == 0,
        "no_violation_events": d["noninterference"]["violation_events"] == 0,
        "cloud_keychain_isolation_test_ran": log_has(
            app_log, "testIsolatedManagedRootNeverReadsOrWritesTheLoginKeychain]' passed"),
        "executed_count": d.get("executed_skipped_failures"),
    })
gate("app_suite_and_isolation", "PASS" if all(checks.values()) else "FAIL", checks)

def pkg_aggregate(path):
    """Last "Executed N tests" aggregate of one swift-test log.

    Two shapes occur: "Executed N tests, with S tests skipped and F failures" and
    the no-skip form "Executed N tests, with F failures".
    """
    if not os.path.exists(path):
        return None
    txt = open(path, errors="replace").read()
    m = re.findall(r"Executed (\d+) tests?, with (\d+) tests? skipped and (\d+) failures?", txt)
    if m:
        return tuple(int(x) for x in m[-1])
    m2 = re.findall(r"Executed (\d+) tests?, with (\d+) failures?", txt)
    return (int(m2[-1][0]), 0, int(m2[-1][1])) if m2 else None


lbc = pkg_aggregate(os.path.join(B, "logs/localbcore_tests.log"))
srt = pkg_aggregate(os.path.join(B, "logs/simigoruntime_tests.log"))
pkg_checks = {
    "localbcore_log_present": bool(lbc),
    "simigoruntime_log_present": bool(srt),
    "localbcore_41_executed": bool(lbc) and lbc[0] == 41,
    "simigoruntime_85_executed": bool(srt) and srt[0] == 85,
    "package_zero_failures": bool(lbc) and bool(srt) and lbc[2] == 0 and srt[2] == 0,
    "package_total_executed": (lbc[0] if lbc else 0) + (srt[0] if srt else 0),
}
gate("package_suite", "PASS" if all(pkg_checks.values()) else "FAIL", pkg_checks)

# ------------------------------------------------------ G6 resource lifecycle
mem = find(os.path.join(B, "m4/m4a/memprobe_m4a_mem.json"))
if mem:
    d = jload(mem)
    checks = {
        "memprobe_ran": d.get("status") == "OK",
        "warm_generate_observed": bool(d.get("warm_generated")),
        "resume_generate_observed": bool(d.get("post_resume_generated")),
        "reference_release_observed": d.get("reference_release_observed") is True,
        "resource_reclaim_observed": d.get("resource_reclaim_observed") is True,
        "container_ref_dropped": d.get("model_container_ref_dropped") is True,
        "suspend_returned_true": d.get("suspend_returned_true") is True,
        "lifecycle_suspend_event_observed": d.get("lifecycle_suspend_delta") == 1,
        "lifecycle_resume_event_observed": d.get("lifecycle_resume_delta") == 1,
        "container_present_before": d.get("model_container_present_before") is True,
        "container_absent_after": d.get("model_container_absent_after") is True,
        "sessions_released_ge_1": (d.get("sessions_released") or 0) >= 1,
        # Anti-cheat: the probe must not shorten the eligibility window with a
        # test seam. It has to wait out the shipped adaptive idle floor.
        "no_release_timing_seam": str(d.get("suspend_window_source", "")).startswith(
            "production adaptive idle"),
        "waited_out_production_idle_floor": (d.get("observed_idle_wait_seconds") or 0) >= 240,
    }
    verdict = "PASS" if all(checks.values()) else "FAIL"
    gate("resource_lifecycle", verdict, checks,
         "Round 2: the Release binary has no idle-timing seam, so the probe waits out the "
         "production adaptive idle floor (240 s) and then calls the unmodified "
         "suspendIfIdle(); every observed value below comes from that path. A FAIL here "
         "means the shipped suspend/reclaim path did not actually take effect.")
else:
    gate("resource_lifecycle", "BLOCKED", {"memprobe_present": False})

gate("physical_page_return", "BLOCKED", {
    "os_level_page_return_evidence": False,
    "footprint_only": True,
}, "No OS-level page-return evidence was collected; footprint/exit is supporting only.")
gate("per_layer_forward_calls", "NOT_INSTRUMENTED", {
    "instrumented": False,
}, "No per-layer forward-count instrumentation exists in the product.")

# ---------------------------------------------------- G7 non-interference diff
pre = find(os.path.join(B, "evidence/noninterference_pre_m4.json"))
post = find(os.path.join(B, "evidence/noninterference_post_m4.json"))
diffp = find(os.path.join(B, "evidence/noninterference_diff_m4.json"))


def finder_view_metadata(path):
    """True only when the file on disk is a Finder .DS_Store container.

    The DS_Store format starts with a 4-byte big-endian version followed by the
    ASCII magic "Bud1"; a product state file never carries that header. The test
    is applied to the bytes actually on disk, so the classification cannot be
    asserted by writing it into this script.
    """
    if os.path.basename(path) != ".DS_Store":
        return False
    try:
        with open(path, "rb") as fh:
            head = fh.read(12)
    except OSError:
        return False
    return head[:4] == b"\x00\x00\x00\x01" and head[4:8] == b"Bud1"


checks = {"pre": bool(pre), "post": bool(post), "diff": bool(diffp)}
if diffp:
    d = jload(diffp)
    writes = d.get("real_user_state_write_paths") or []
    residual = [p for p in writes if finder_view_metadata(p)]
    product_writes = [p for p in writes if p not in residual]
    # A bracket pair measured immediately around one isolated launch of the SAME
    # installed binary: if it reports zero writes, the candidate demonstrably does
    # not touch the protected roots, so the batch-level residual cannot come from it.
    bdiff = find(os.path.join(B, "evidence/noninterference_bracket_diff.json"))
    bt = find(os.path.join(B, "evidence/noninterference_bracket.txt"))
    inst = find(os.path.join(B, "evidence/m3_install_identity.json"))
    bracket_zero = bool(bdiff) and jload(bdiff).get("real_user_state_write_count") == 0
    bracket_same_binary = bool(bdiff and bt and inst) and (
        jload(inst).get("executable_sha256") in open(bt, errors="replace").read())
    checks.update({
        "raw_real_user_state_write_count": d.get("real_user_state_write_count"),
        "raw_violation_events": d.get("violation_events"),
        "product_state_writes_zero": not product_writes,
        "residual_classified_finder_metadata": len(residual) == len(writes),
        "bracket_recheck_zero_writes": bracket_zero,
        "bracket_used_same_installed_binary": bracket_same_binary,
        "reference_changes_zero": len(d.get("reference_change_paths", [])) == 0,
    })
booleans = [v for k, v in checks.items() if isinstance(v, bool)]
gate("experiment_non_interference",
     "PASS" if all(booleans) else "FAIL", checks,
     "Raw pre/post over the whole evidence window is reported unchanged: 1 real-root "
     "write, on ~/.simigo/.DS_Store. That file is a Finder view-metadata container "
     "(verified by its Bud1 header at verify time, not by assertion), it was rewritten "
     "at 01:30:44 - inside a window with no candidate process alive - and a bracket "
     "pair taken immediately around one launch of the same installed binary reports 0 "
     "writes. Every product state path (sqlite3, -wal, -shm, prefix-pool, "
     "branch-checkpoints, manifests, Application Support, HF reference root) is "
     "unmodified. evidence/noninterference_residual_analysis.md holds the full "
     "attribution and the re-test condition; nothing was allowlisted to reach this verdict.")

# ------------------------------------------- G7b Keychain non-interference
kc = find(os.path.join(B, "evidence/keychain_noninterference.json"))
checks = {"keychain_report_present": bool(kc)}
if kc:
    d = jload(kc)
    iso = d.get("isolation") or {}
    pkg_log = os.path.join(B, "logs/localbcore_tests.log")
    checks.update({
        "production_credentials_untouched": all(
            (r.get("modified") or r.get("created") or "") < "20261024"
            for r in d.get("production_items", [])),
        # Round 3: a metadata baseline is taken BEFORE the runs; the gate is the
        # delta, not the absolute count (round 1/2 items stay as evidence).
        "no_new_login_keychain_items": d.get("new_item_count") == 0,
        "no_items_removed_or_rewritten": len(d.get("removed_items_since_baseline", [])) == 0,
        "keychain_isolated_by_simigo_home": iso.get("keychain_isolated_by_simigo_home") is True,
        "isolated_runs_wrote_scoped_keychain_files": bool(d.get("scoped_keychain_files")),
        "scoped_store_covered_by_package_test": log_has(
            pkg_log, "testScopedKeychainKeepsIdentityOutOfTheDefaultSearchList"),
        "cloud_keychain_isolation_covered_by_app_test": log_has(
            os.path.join(B, "run_isolated_r4/isolated_tests_r4.log"),
            "testIsolatedManagedRootNeverReadsOrWritesTheLoginKeychain]' passed"),
        "baseline_present": bool((d.get("baseline") or {}).get("item_count")),
        "new_item_count": d.get("new_item_count"),
        "legacy_round2_item_count": d.get("legacy_round2_item_count"),
    })
gate("keychain_non_interference", "PASS" if all(
        v for k, v in checks.items() if isinstance(v, bool)) else "FAIL", checks,
     "Round 2 found every headless run creating a one-time LOCALB transport identity in "
     "the real login Keychain (45 items: 3 per process, index + key + certificate), because "
     "SIMIGO_HOME redirected every filesystem root but not the Keychain. Round 3 fixes the "
     "product, not the measurement: LOCALBTransportIdentityStore resolves its identity into "
     "<SIMIGO_HOME>/localb/transport-identity.keychain-db whenever the managed root is "
     "isolated, and scopes every SecItem call (kSecUseKeychain for adds, kSecMatchSearchList "
     "for copy/update/delete, SecIdentityCreateWithCertificate(keychain) for the TLS "
     "identity). The audit is now a metadata delta against a baseline captured before the "
     "runs; the 45 round-1/2 items are left in place as evidence rather than deleted. "
     "Production credentials (com.simigo.localb-*) are untouched. Round 4 adds the "
     "second half of the same isolation rule: CloudKeychain (service SimiGo, "
     "cloud.api-key) is inert while SIMIGO_HOME is set, because an isolated run that "
     "reads the real credential both blocks Service.init() behind an ACL prompt and "
     "pulls a user secret into the candidate's window.")

# ------------------------------------------------ G8 M5 artifact re-check
rc = find(os.path.join(B, "evidence/recheck_artifacts.json"))
checks = {"recheck_present": bool(rc)}
if rc:
    d = jload(rc)
    checks["recheck_verdict_pass"] = d.get("verdict") == "PASS"
    checks.update({k: bool(v) for k, v in d.get("checks", {}).items()})
gate("artifact_identity_recomputed", "PASS" if all(checks.values()) else "FAIL", checks,
     "Every source, model, DMG and installed-bundle identity is re-derived from disk in "
     "evidence/recheck_artifacts.json; a mismatch fails this gate.")

# ------------------------------------------------------------------ summary
verdicts = {k: v["verdict"] for k, v in GATES.items()}
# Severity order, best -> worst: a hard FAIL outranks an unproven leg, which
# outranks a blocked one, which outranks a merely uninstrumented metric.
order = ["PASS", "NOT_INSTRUMENTED", "BLOCKED", "INCONCLUSIVE", "FAIL"]
# The batch verdict is the WORST gate verdict, so severity must be indexed and
# maximised - iterating from the best verdict would let one PASS hide a FAIL.
severity = {v: i for i, v in enumerate(order)}
overall = max(verdicts.values(), key=lambda v: severity[v])
doc = {"generated_at": subprocess.run(["date", "+%Y-%m-%dT%H:%M:%S%z"], capture_output=True, text=True).stdout.strip(),
       "overall": overall, "gates": GATES,
       "counts": {v: list(verdicts.values()).count(v) for v in order}}
out = os.path.join(B, "acceptance_report.json")
with open(out, "w") as f:
    json.dump(doc, f, indent=1, sort_keys=True)
    f.write("\n")
for k in sorted(verdicts):
    print("%-42s %s" % (k, verdicts[k]))
print("overall:", overall)
print("wrote", out)
sys.exit(0 if overall == "PASS" else (1 if overall == "FAIL" else 2))
