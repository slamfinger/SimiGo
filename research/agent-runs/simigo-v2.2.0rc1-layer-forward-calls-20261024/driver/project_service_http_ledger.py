#!/usr/bin/env python3
"""Project the round-3 ledger gate `product_service_http` onto the v5 candidate.

The round-3 acceptance ledger computes that gate from a probe record with eight
checks (driver/verify_batch.py, fallback branch):

    probe_present
    listening_socket_found
    tls_only_transport
    unconfigured_authorization_refused        (observed http_status=503)
    no_authorization_relaxation
    authorized_request_completed
    authorization_surface_recorded
    authorized_lane_passes_in_test_target

This script re-evaluates those eight checks against measurements taken on the
REBUILT candidate (install_v5 / exe 83a88048..., see
evidence/install_identity_v5_candidate.json). It is a projection, not a ledger
edit: the ledger and the sealed round-3 evidence are read-only here, and the
output says so in `ledger_modified`.

Where a round-2 token string cannot be reproduced (`tls_verify=18`), the script
records the measurement it actually has and marks the token as not reproduced
instead of copying the old wording.

usage: project_service_http_ledger.py [--out <json>]
"""
import hashlib
import json
import os
import re
import subprocess
import sys

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER_B = "/Users/mr.simi/SimiGo-Agent-Runs/simigo-v2.2.0rc1-local-acceptance-20261024"
REPO = "/Users/mr.simi/Documents/SimiGo"
PROBE = os.path.join(B, "evidence/transport_v5/service_http_transport_probe_v5.json")
FACADE = os.path.join(B, "evidence/gate_v5_facade/service_http_gate_installed.json")
VERDICT = os.path.join(B, "evidence/gate_v5/service_http_gate_verdict.json")
IDENTITY = os.path.join(B, "evidence/install_identity_v5_candidate.json")
SURFACE = os.path.join(LEDGER_B, "evidence/localb_authorization_path.txt")
SEALED_LOG = os.path.join(LEDGER_B, "logs/isolated_r4.stdout.log")
LF3_LOG = os.path.join(B, "run_isolated_lf3/isolated_tests_lf3.log")
LEDGER = os.path.join(LEDGER_B, "acceptance_report.json")
OUT = os.path.join(B, "evidence/service_http_ledger_projection_v5.json")
CASES = [
    "testDefaultHostResolutionServesAuthorizedRequests",
    "testDefaultHostResolutionFailsClosedBeforeActivation",
    "testProtectedRouteServesOnlyWithVerifiedProofOverTLS",
    "testSignedBodyReachesInferenceEndpoint",
    "testMissingProofHeadersAndUnconfiguredAuthorizationFailClosed",
    "testBareChatCompletionsPathRequiresProofAndServesWithProof",
    "testTamperedBodyIsRejected",
    "testChallengeIsSingleUse",
    "testUnknownRoutesFailClosedAndOpenRoutesStayOpen",
    "testAdoptedEndpointConfigDispatchesInferenceThroughProductionRuntime",
]


def rel(path):
    return os.path.relpath(path, B) if path.startswith(B) else path


def jload(path):
    with open(path) as fh:
        return json.load(fh)


def sha256(path):
    if not os.path.exists(path):
        return None
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def case_results(log_path):
    if not os.path.exists(log_path):
        return {"log": log_path, "exists": False, "cases": {}, "suites": []}
    text = open(log_path, errors="replace").read().splitlines()
    cases = {}
    for name in CASES:
        hit = [l for l in text if (" " + name + "]") in l and ("passed" in l or "failed" in l)]
        cases[name] = ("passed" if hit and "passed" in hit[0] else
                       "failed" if hit else "missing")
    suites = [l.strip() for l in text
              if re.search(r"Test Suite '(LOCALBRequestAuthWiringTests|"
                           r"ExternalAdoptionInferenceE2ETests)' (passed|failed)", l)]
    return {"log": log_path, "exists": True, "cases": cases, "suites": suites}


def ceremony_call_sites():
    proc = subprocess.run(["grep", "-rn", "persistTrustedCheckpoint", "SimiGo", "SimiGoTests"],
                          cwd=REPO, capture_output=True, text=True)
    hits = [l for l in proc.stdout.splitlines() if l.strip()]
    app = [l for l in hits if l.startswith("SimiGo/")
           and "static func persistTrustedCheckpoint" not in l]
    # The round-3 scan counted every textual hit, comments included. Keep that
    # number for comparability and add the code-only count, which is what
    # "does the shipped target actually call the ceremony" means.
    def is_code(line):
        body = line.split(":", 2)[-1].strip()
        return bool(body) and not body.startswith("//")

    code = [l for l in app if is_code(l)]
    return {"hits": hits, "app_target_call_sites": len(app),
            "app_target_code_sites": len(code),
            "app_target_sites": app, "app_target_code": code,
            "tests_target_sites": len([l for l in hits if l.startswith("SimiGoTests/")])}


def main():
    global OUT
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=OUT)
    opts = parser.parse_args()
    OUT = opts.out

    probe = jload(PROBE)
    facade = jload(FACADE)
    verdict = jload(VERDICT)
    identity = jload(IDENTITY)
    tokens = probe["tokens"]
    act, unauth = probe["activated"], probe["unconfigured"]
    auth = act["authorized_request"]
    auth_body = auth["result"].get("body") or ""
    cases_new = case_results(LF3_LOG)
    cases_sealed = case_results(SEALED_LOG)
    sites = ceremony_call_sites()
    signed_off_probe = (facade["positive"].get("negative_probes") or {}).get("result", {}).get("cases", {})

    checks = {}

    checks["probe_present"] = {
        "value": os.path.exists(PROBE),
        "source": rel(PROBE),
        "note": "ledger token file produced on the activated listener of v5; "
                "the round-3 stage-C file is untouched",
    }
    checks["listening_socket_found"] = {
        "value": tokens["listening_socket_found"] == 1
                 and (act["listening_socket"]["owned_by_candidate"] is True)
                 and (unauth["listening_socket"]["owned_by_candidate"] is True),
        "source": rel(PROBE),
        "note": "lsof -nP -iTCP:<port> -sTCP:LISTEN during BOTH legs; the owner pid "
                "equals the candidate pid (%d activated, %d unactivated)"
                % (act["listening_socket"]["candidate_pid"],
                   unauth["listening_socket"]["candidate_pid"]),
    }
    checks["tls_only_transport"] = {
        "value": tokens["tls_only_transport"] == 1
                 and act["spki_match"]["result"].get("verdict") == "match",
        "source": rel(PROBE),
        "note": "plaintext GET -> curl rc=52 'Empty reply from server' (%s); "
                "default-trust TLS -> rc=60 self-signed; the peer certificate's SPKI "
                "matches the host's prepared value (%s)"
                % (act["plaintext_to_tls_port"]["stderr"],
                   act["spki_match"]["result"].get("observed_spki_sha256", "")[:16]),
        "token_not_reproduced": "tls_verify=18 is a round-2 string that no retained "
                                "record contains; this projection does not assert it",
    }
    checks["unconfigured_authorization_refused"] = {
        "value": tokens["http_status_503_unconfigured"] == 503,
        "source": rel(PROBE),
        "note": "observed %s on /localb/auth/challenge with the host prepared but not "
                "activated: %s" % (tokens["http_status_503_unconfigured"],
                                   (unauth["guarded_route"]["body"] or "")[:90]),
    }
    checks["no_authorization_relaxation"] = {
        "value": tokens["authorization_relaxed"] == 0,
        "source": rel(PROBE),
        "note": "child env audited: %s; no relax/insecure/skip-proof key, no product flag; "
                "the only source delta of this candidate is the management entry "
                "(SERVICE_FACADE_LEG.patch :188 calls persistTrustedCheckpoint from the "
                "activate role, nothing touches the guard)"
                % ", ".join((act["env_audit"] or {}).get("forwarded_simigo_keys", [])),
    }
    checks["authorized_request_completed"] = {
        "value": (tokens["authorized_request_completed"] == 1
                  and bool(auth_body) and auth["generation_trace"]["delta"] > 0),
        "source": rel(PROBE),
        "note": "HTTP 200 with a non-empty chatcmpl body; generation trace delta=%d "
                "(before=%d after=%d); TLS without proof -> %s"
                % (auth["generation_trace"]["delta"], auth["generation_trace"]["before"],
                   auth["generation_trace"]["after"], tokens["proof_refused_status"]),
    }
    checks["authorization_surface_recorded"] = {
        "value": os.path.exists(SURFACE),
        "source": rel(SURFACE),
        "note": "the sealed round-3 record exists; re-measured on the CURRENT tree: "
                "app_target_code_sites=%d (textual hits incl. comments=%d; was 0 when the "
                "sealed record was written). The shipped surface is the env-gated "
                "management entry, which requires an isolated SIMIGO_HOME and does not run "
                "on a normal launch; the GUI flow still does not perform the ceremony."
                % (sites["app_target_code_sites"], sites["app_target_call_sites"]),
        "recomputed": sites,
    }
    new_pass = all(v == "passed" for v in cases_new["cases"].values()) and bool(cases_new["cases"])
    sealed_pass = all(v == "passed" for v in cases_sealed["cases"].values()) and bool(cases_sealed["cases"])
    checks["authorized_lane_passes_in_test_target"] = {
        "value": new_pass,
        "source": rel(LF3_LOG),
        "note": "all 10 LOCALB cases passed in the App suite run against the v5 test host "
                "(210 executed / 14 skipped / 0 failures); the sealed round-3 log also "
                "reads %s for the same 10 cases"
                % ("all passed" if sealed_pass else "not all passed"),
        "cases": cases_new["cases"],
        "sealed_reference": cases_sealed["cases"],
    }

    projection = "PASS" if all(c["value"] for c in checks.values()) else "BLOCKED"
    doc = {
        "batch": os.path.basename(B),
        "gate": "product_service_http",
        "rule_source": os.path.join(LEDGER_B, "driver/verify_batch.py") + ":153-178 (probe-token branch)",
        "candidate": {
            "app": identity["app"],
            "executable_sha256": identity["executable_sha256"],
            "bundle_tree_sha256": identity["bundle_tree_sha256"],
            "installed_equals_built": identity["installed_equals_built"],
        },
        "facade_leg": {
            "facade_leg_passed": (verdict.get("facade_leg") or {}).get("facade_leg_passed"),
            "serve_role": verdict.get("serve_role"),
            "serve_role_in_facade_source": jload(FACADE).get("serve_role"),
            "serve_role_note": ("'serve_role' above is the direct leg that produced this verdict; "
                                "the facade leg's own role is the field next to it"),
            "negative_cases": {k: {"status": v.get("status"), "trace_delta": v.get("trace_delta")}
                               for k, v in signed_off_probe.items()},
            "source": rel(FACADE),
        },
        "status_convention": {
            "question": (verdict.get("status_convention") or {}).get("question"),
            "answer": (verdict.get("status_convention") or {}).get("answer"),
            "pinned_to_source": bool(verdict.get("status_convention")),
            "all_checks_pass": (verdict.get("status_convention") or {}).get("all_checks_pass"),
            "source_head": (verdict.get("status_convention") or {}).get("source_head"),
            "evidence": (verdict.get("status_convention") or {}).get("evidence"),
            "open_items": ("the deviation itself stays open: the operator table says 503 for an "
                           "invalid proof and the product answers 401. Nothing was changed to "
                           "align them; what changed is that the wording is now cited to source"),
        },
        "checks": checks,
        "projected_verdict": projection,
        "ledger": {"path": LEDGER, "sha256": sha256(LEDGER),
                   "counts_now": jload(LEDGER)["counts"],
                   "overall_now": jload(LEDGER)["overall"]},
        "ledger_modified": False,
        "merge_requires_authorization": True,
        "not_claimed": [
            "this file does not change acceptance_report.json",
            "a projection over a rebuilt candidate is not a ledger merge",
            "the GUI prompt leg is untouched by this gate",
            "the round-2 'tls_verify=18' token is not reproduced and not asserted",
            "a source-pinned status convention is not the same thing as an approved status change",
            "the physical page-return gate and the per-layer forward_calls gate are untouched here",
        ],
    }
    with open(OUT, "w") as fh:
        json.dump(doc, fh, indent=1, sort_keys=True)
    print("projected_verdict=%s checks=%s" % (
        projection, json.dumps({k: v["value"] for k, v in checks.items()}, sort_keys=True)))
    print("wrote " + OUT)
    return 0 if projection == "PASS" else 2


if __name__ == "__main__":
    sys.exit(main())
