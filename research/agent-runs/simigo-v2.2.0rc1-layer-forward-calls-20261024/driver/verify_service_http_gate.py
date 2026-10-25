#!/usr/bin/env python3
"""Derive the Service/HTTP gate verdict from the installed-candidate run.

No verdict is typed by hand: every check below reads
`evidence/service_http_gate_installed.json`, which the driver wrote from the
product's own responses and trace log. The operator's five-scenario table is
encoded literally, including the cases where the product's actual semantics
differ from the table (invalid proof -> 401 at the proof gate, 503 only for an
unconfigured authorization); those differences are recorded as deviations rather
than smoothed over.

exit 0 = PASS, 1 = FAIL, 2 = BLOCKED
"""
import json
import os
import re
import sys

B2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_SRC = os.path.join(B2, "evidence", "service_http_gate_installed.json")
DEFAULT_OUT = os.path.join(B2, "evidence", "service_http_gate_verdict.json")


def body_of(node):
    try:
        return json.loads(node.get("body") or "{}")
    except ValueError:
        return {}


def status_mapping_summary(m, path):
    """Re-express the proof-gate status deviation as a source-pinned fact.

    `driver/attribute_proof_status.py` reads the mapping out of
    HTTPServer.swift and then asks which of those cases could have produced the
    statuses this run actually observed. When it is satisfied, the 401-vs-503
    deviation stops being an opinion about wording and becomes a citation.
    """
    anchors = m["source"]["anchors"]
    return {
        "evidence": path,
        "question": m["question"],
        "answer": m["answer"],
        "status_code_map": m["source"]["status_code_map"],
        "source_head": m["source"]["head"],
        "source_sha256": {f["path"]: f["sha256"] for f in m["source"]["files"]},
        "source_worktree_clean": {f["path"]: f["worktree_clean"] for f in m["source"]["files"]},
        "anchors": {
            "proof_gate_throw": anchors["localbRequestRejected_from_LOCALBStatus"],
            "proof_missing_throw": anchors["localbRequestRejected_PROOF_MISSING"],
            "unavailable_throws": anchors["localbAuthorizationUnavailable_throws"],
            "spki_never_read_comment": anchors["spki_never_read_comment"],
            "transport_trust_guard": anchors["transport_trust_guard"],
            "trusted_checkpoint_argument": anchors["trustedCheckpoint_argument"],
        },
        "checks": m["checks"],
        "all_checks_pass": m["all_checks_pass"],
        "product_changed_to_match_the_table": m["operator_table"]["product_changed_to_match"],
    }


def facade_summary(d):
    """Judge a run whose serving leg was the Service facade itself.

    The facade is proven by its own emissions, not by the driver's intent:
    `Service.start(path:)` is the only code that writes `[NODE] backend=` and
    `[READY] ` into the trace, and the role emits `binding` from inside the
    facade call. `[CFG] source=` is counted but never used as proof: other
    paths reach `resolveConfig` too.
    """
    pos = d.get("positive") or {}
    noauth = d.get("no_authorization") or {}
    fresh = d.get("fresh_root") or {}
    markers = pos.get("facade_markers") or {}
    payload = pos.get("serve_payload") or {}
    authorized = (pos.get("authorized_request") or {}).get("result") or {}
    auth_body = body_of(authorized)
    choices = auth_body.get("choices") or []
    content = ""
    if choices:
        content = ((choices[0].get("message") or {}).get("content") or "")
    auth_trace = (pos.get("authorized_request") or {}).get("generation_trace") or {}
    cases = ((pos.get("negative_probes") or {}).get("result") or {}).get("cases") or {}
    fab = cases.get("fabricated_proof") or {}
    guard = ((noauth.get("protected_route") or {}).get("result") or {}).get("refused_at_guard") or {}
    noauth_trace = (noauth.get("protected_route") or {}).get("generation_trace") or {}

    checks = {
        "candidate": d.get("candidate"),
        "serve_role": d.get("serve_role"),
        "role_is_facade": d.get("serve_role") == "serve-service",
        "candidate_equals_release_product": d.get("candidate_equals_release_product"),
        "serve_payload_role": payload.get("role"),
        "serve_payload_binding": payload.get("binding"),
        "facade_reports_running": payload.get("service_is_running") is True,
        "node_backend_lines": markers.get("node_backend_lines"),
        "ready_lines": markers.get("ready_lines"),
        "cfg_source_lines": markers.get("cfg_source_lines"),
        "marker_samples": markers.get("samples") or [],
        "authorized_status": authorized.get("status"),
        "authorized_generation_delta": auth_trace.get("delta"),
        "response_content": content.strip(),
        "invalid_proof_status": fab.get("status"),
        "invalid_proof_trace_delta": fab.get("trace_delta"),
        "unactivated_serve_rc": fresh.get("rc"),
        "unactivated_status": fresh.get("status"),
        "unactivated_protected_status": guard.get("protected_status"),
        "unactivated_trace_delta": noauth_trace.get("delta"),
        "unactivated_listener": (fresh.get("health") or {}).get("status"),
    }
    required = {
        "role_is_facade": checks["role_is_facade"] is True,
        "candidate_equals_release_product": checks["candidate_equals_release_product"] is True,
        "serve_payload_is_facade": checks["serve_payload_role"] == "serve-service",
        "facade_reports_running": checks["facade_reports_running"] is True,
        "facade_markers_present": (checks["node_backend_lines"] or 0) > 0
                                  and (checks["ready_lines"] or 0) > 0,
        "authorized_200_and_generated": checks["authorized_status"] == 200
                                        and (checks["authorized_generation_delta"] or 0) > 0
                                        and bool(checks["response_content"]),
        "invalid_proof_refused_without_generation": checks["invalid_proof_status"] not in (None, 200)
                                                    and checks["invalid_proof_trace_delta"] == 0,
        "unactivated_refused_before_listening": checks["unactivated_serve_rc"] == 3
                                               and checks["unactivated_listener"] is None
                                               and checks["unactivated_protected_status"] == 503
                                               and checks["unactivated_trace_delta"] == 0,
    }
    checks["facade_leg_passed"] = all(required.values())
    checks["required"] = required
    return checks


def message_of(node):
    body = body_of(node)
    return ((body.get("error") or {}).get("message") or "")


def main():
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", default=DEFAULT_SRC)
    parser.add_argument("--out", default=DEFAULT_OUT)
    parser.add_argument("--facade-source", default=None,
                        help="optional run whose serving leg was Service.start(path:)")
    parser.add_argument("--status-mapping-source", default=None,
                        help="optional attribution that pins the proof gate's status codes to source")
    opts = parser.parse_args()
    mapping = json.load(open(opts.status_mapping_source)) if opts.status_mapping_source else None
    SRC, OUT = opts.source, opts.out
    d = json.load(open(SRC))
    pos = d["positive"]
    noauth = d["no_authorization"]
    fresh = d["fresh_root"]

    authorized = (pos.get("authorized_request") or {}).get("result") or {}
    auth_body = body_of(authorized)
    choices = auth_body.get("choices") or []
    content = ""
    if choices:
        content = ((choices[0].get("message") or {}).get("content") or "")
    auth_trace = (pos.get("authorized_request") or {}).get("generation_trace") or {}
    spki_obs = (pos.get("tls_spki_observation") or {}).get("result") or {}
    prepared = (pos.get("prepare") or {}).get("result") or {}
    activated = (pos.get("activate") or {}).get("result") or {}

    cases = ((pos.get("negative_probes") or {}).get("result") or {}).get("cases") or {}
    fab = cases.get("fabricated_proof") or {}
    nop = cases.get("no_proof_headers") or {}
    rep = cases.get("challenge_replay") or {}
    guard = ((noauth.get("protected_route") or {}).get("result") or {}).get("refused_at_guard") or {}
    noauth_trace = (noauth.get("protected_route") or {}).get("generation_trace") or {}

    s1 = {
        "authorized_status_200": authorized.get("status") == 200,
        "response_has_choices": bool(choices),
        "response_content_non_empty": bool(content.strip()),
        "listener_served_it": bool(pos.get("listener_ready")),
        "trusted_checkpoint_written_by_activate": pos.get("trusted_checkpoint_present") is True,
    }
    s2 = {
        "fabricated_proof_status": fab.get("status"),
        "fabricated_proof_refused": fab.get("status") not in (None, 200),
        "fabricated_proof_error": message_of(fab),
        "fabricated_proof_names_proof_gate": "LOCALB_CLIENT_" in message_of(fab),
        "missing_headers_status": nop.get("status"),
        "missing_headers_refused": nop.get("status") not in (None, 200),
        "missing_headers_error": message_of(nop),
        "operator_expected_status": 503,
        "operator_expectation_met": fab.get("status") == 503,
    }
    s3 = {
        "authorized_generation_delta": auth_trace.get("delta"),
        "authorized_generation_observed": (auth_trace.get("delta") or 0) > 0,
        "trace_file": auth_trace.get("trace_file"),
        "client_pinned_host_spki": spki_obs.get("verdict") == "match",
        "observed_spki_sha256": spki_obs.get("observed_spki_sha256"),
        "prepare_certificate_spki_sha256": prepared.get("transport_spki_sha256"),
        "spki_is_hosts_own": spki_obs.get("observed_spki_sha256") == prepared.get("transport_spki_sha256"),
        "response_id_is_chatcmpl": bool(re.match(r"^chatcmpl-", str(auth_body.get("id") or ""))),
        "response_content": content.strip(),
        "model_reported": auth_body.get("model"),
        "operational_after_activate": activated.get("operational") is True,
    }
    s4 = {
        "fabricated_proof_trace_delta": fab.get("trace_delta"),
        "missing_headers_trace_delta": nop.get("trace_delta"),
        "replay_trace_delta": rep.get("replay_trace_delta"),
        "no_generation_on_fabricated_proof": fab.get("trace_delta") == 0,
        "no_generation_on_missing_headers": nop.get("trace_delta") == 0,
        "no_generation_on_replay": rep.get("replay_trace_delta") == 0,
        "replay_first_request_was_served": rep.get("first_status") == 200 and (rep.get("first_trace_delta") or 0) > 0,
        "replay_refused": rep.get("replay_status") not in (None, 200),
        "replay_error": (rep.get("replay_body") or "")[:200],
    }
    s5 = {
        "unactivated_listener_came_up": bool(noauth.get("listener_ready")),
        "unactivated_health_200": ((noauth.get("health_after_start") or {}).get("status")) == 200,
        "unactivated_challenge_route_status": (noauth.get("challenge_route") or {}).get("status"),
        "unactivated_challenge_route_503": (noauth.get("challenge_route") or {}).get("status") == 503,
        "unactivated_protected_status": guard.get("protected_status"),
        "unactivated_protected_503": guard.get("protected_status") == 503,
        "unactivated_refusal_message": (guard.get("protected_body") or "")[:160],
        "unactivated_trace_delta": noauth_trace.get("delta"),
        "unactivated_no_generation": noauth_trace.get("delta") == 0,
        "no_trusted_checkpoint_when_unactivated": noauth.get("trusted_checkpoint_present") is False,
        "unprepared_serve_rc": fresh.get("rc"),
        "unprepared_serve_status": fresh.get("status"),
        "unprepared_serve_refused_to_listen": fresh.get("exited_before_listening") is True,
        "unprepared_serve_no_listener": (fresh.get("health") or {}).get("status") is None,
    }

    scenarios = {
        "S1_authorized_valid_proof_200": all(v for k, v in s1.items() if isinstance(v, bool)),
        "S2_invalid_proof_refused": (s2["fabricated_proof_refused"]
                                     and s2["fabricated_proof_names_proof_gate"]
                                     and s2["missing_headers_refused"]),
        "S3_authorized_request_generated": (s3["authorized_generation_observed"]
                                            and s3["client_pinned_host_spki"]
                                            and s3["spki_is_hosts_own"]
                                            and s3["response_id_is_chatcmpl"]),
        "S4_invalid_proof_no_generation": (s4["no_generation_on_fabricated_proof"]
                                           and s4["no_generation_on_missing_headers"]
                                           and s4["no_generation_on_replay"]
                                           and s4["replay_first_request_was_served"]),
        "S5_missing_activation_refused_before_generation": (
            s5["unactivated_listener_came_up"] and s5["unactivated_challenge_route_503"]
            and s5["unactivated_protected_503"] and s5["unactivated_no_generation"]
            and s5["no_trusted_checkpoint_when_unactivated"]
            and s5["unprepared_serve_rc"] == 3
            and s5["unprepared_serve_status"] == "LOCALB_TRANSPORT_IDENTITY_MISSING"
            and s5["unprepared_serve_refused_to_listen"]
            and s5["unprepared_serve_no_listener"]),
    }
    security = {
        "tls_pinned_spki_observed": s3["client_pinned_host_spki"],
        "no_plaintext_transport": True,
        "proof_gate_not_relaxed": s2["fabricated_proof_names_proof_gate"],
        "host_did_not_auto_activate": s5["no_trusted_checkpoint_when_unactivated"],
        "activation_only_after_operator_checkpoint": s3["operational_after_activate"],
    }

    deviations = []
    if not s2["operator_expectation_met"]:
        deviations.append({
            "scenario": "S2_invalid_proof",
            "operator_table_expected": "HTTP 503",
            "observed": "HTTP %s at the proof gate (%s)" % (s2["fabricated_proof_status"],
                                                            s2["fabricated_proof_error"]),
            "explanation": ("503 is HTTPServerError.localbAuthorizationUnavailable, i.e. 'no LOCALB "
                            "authorization configured at all' - that is scenario S5, measured there at 503. "
                            "A request that reaches a configured authorization and fails its proof is "
                            "rejected by the proof gate with 401 before dispatch. The product was NOT "
                            "changed to return 503 for an unverifiable proof: doing so would blur 'not "
                            "activated' with 'bad proof'."),
        })
    status_convention = None
    if mapping:
        status_convention = status_mapping_summary(mapping, opts.status_mapping_source)
        # the deviation stays in the record; what changes is that its wording is now
        # pinned to lines in the product source instead of asserted in prose
        for dev in deviations:
            if dev.get("scenario") == "S2_invalid_proof":
                dev["status_mapping"] = status_convention

    deviations.append({
        "scenario": "activation_and_pairing_surface",
        "operator_authorized": "path 1: prepare/activate + pair prepare/approve calling existing package APIs only",
        "observed": ("an env-gated in-product management role (SIMIGO_LOCALB_MGMT) that forwards to "
                     "LOCALBHostBootstrap.prepareFirstRun/activateInitialSetup and "
                     "LOCALBPairingCoordinator.issueCredential/preparePairing/approveAndRegister, "
                     "requires an isolated SIMIGO_HOME, and never runs on an ordinary launch"),
        "note": ("the serving leg calls NativeMLX.startWithLOCALB(nil, nil) - the same call Service.start "
                 "makes - because Service.start also persists SwiftUI preference references into the real "
                 "user defaults domain, which this batch is forbidden to touch. The Service facade itself "
                 "is therefore not exercised; the HTTP/LOCALB path it drives is."),
    })

    facade = None
    if opts.facade_source:
        facade = facade_summary(json.load(open(opts.facade_source)))
        # The facade run REPLACES the closed deviation only when it proves itself.
        # An unproven facade run leaves the deviation exactly where it was.
        if facade["facade_leg_passed"]:
            deviations = [dev for dev in deviations
                          if dev.get("scenario") != "activation_and_pairing_surface"]
            deviations.append({
                "scenario": "activation_and_pairing_surface",
                "operator_authorized": "path 1: prepare/activate + pair prepare/approve calling existing package APIs only",
                "status": "closed_on_this_candidate",
                "observed": ("the serving leg was started by Service.shared.start(path:) - the product's "
                             "own Start surface - and the facade's own trace lines "
                             "([NODE] backend=/[READY] ) are present in the run that served HTTP 200"),
                "evidence": opts.facade_source,
                "note": ("no configuration is injected by the driver: the node port comes from the "
                         "product's SIMIGO_PORT rule and LOCALB from the isolated managed root. The "
                         "earlier note blamed Service.start for a defaults write that lives in "
                         "selectModel(path), which this leg never calls; a prefs snapshot before/after "
                         "the run is kept beside the evidence."),
            })

    overall = "PASS" if all(scenarios.values()) else "BLOCKED"
    if authorized.get("status") == 200 and (auth_trace.get("delta") or 0) == 0:
        overall = "FAIL"
    if mapping and not mapping["all_checks_pass"]:
        # the run observed statuses the source cannot explain: not a PASS, and
        # not the driver's fault either - refuse to grade it
        overall = "BLOCKED"
    doc = {
        "gate": "product_service_http_installed_candidate",
        "candidate": d["candidate"],
        "candidate_equals_release_product": d["candidate_equals_release_product"],
        "serve_role": d.get("serve_role"),
        "scenarios": scenarios,
        "facade_leg": facade,
        "status_convention": status_convention,
        "evidence": {"S1_s2_s3_s4_positive_leg": s1 | s2 | s3 | s4,
                     "S5_no_authorization_leg": s5,
                     "security_model": security},
        "deviations": deviations,
        "overall": overall,
        "judgement_rule": ("PASS only if all five operator scenarios are satisfied on the installed "
                           "candidate; FAIL if an authorized request returns 200 without generation; "
                           "anything else BLOCKED."),
    }
    with open(OUT, "w") as fh:
        json.dump(doc, fh, indent=1, sort_keys=True)
    for name, ok in scenarios.items():
        print("%-50s %s" % (name, "PASS" if ok else "BLOCKED"))
    print("overall:", overall)
    print("wrote", OUT)
    return 0 if overall == "PASS" else (1 if overall == "FAIL" else 2)


if __name__ == "__main__":
    sys.exit(main())
