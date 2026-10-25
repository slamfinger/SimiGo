#!/usr/bin/env python3
"""Transport-discipline probe on the REBUILT v5 candidate.

Why this exists
---------------
The round-3 acceptance gate `product_service_http` is computed from a probe
record that carries five machine-readable facts:

    listening_socket_found / authorized_request_completed / an observed
    http_status=503 for an unconfigured authorization / TLS-only transport /
    authorization_relaxed=0

Round 3 never produced such a record on a live listener: its stage-C record
reads `listening_socket_found=0`, so the gate stayed BLOCKED. This script
produces that record on `install_v5/SimiGo.app` by MEASURING each fact, not by
transcribing the round-2 wording that the operator authorized correcting.

What it measures (all against the shipped app binary, isolated roots only)
  1. the listening socket belongs to the candidate pid      (lsof -sTCP:LISTEN)
  2. plaintext HTTP to that port does not get an HTTP reply (TLS-only)
  3. default trust store refuses the listener's certificate (real TLS, self-signed)
  4. the peer certificate matches the host's prepared SPKI    (product client `spki`)
  5. TLS without a LOCALB proof is refused with 401           (proof gate)
  6. a paired, authorized request is served: 200 + generation trace delta > 0
  7. unconfigured authorization answers 503 and generates nothing (delta == 0)
  8. authorization_relaxed == 0: the child env is audited, no product flag and
     no env var that relaxes authorization/TLS is passed

Nothing here calls the inference API directly; every request goes over the
listening socket. Nothing is written outside the isolated roots.

usage: probe_transport_discipline.py [--app <app>] [--port-base 8500]
"""
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_service_http_gate as gate  # noqa: E402  (reuse the audited client drivers)

B = gate.B2
OUT = os.path.join(B, "evidence", "transport_v5")
PORT_TLS = 8500
PORT_UNAUTH = 8501
ROOT_PREFIX = "t5"
RELAX_MARKERS = ("RELAX", "INSECURE", "NO_VERIFY", "SKIP_PROOF", "ALLOW_")


def log(msg):
    print("[transport] " + msg, flush=True)


def curl(args, timeout=10):
    argv = ["curl", "-sS", "-m", str(timeout)] + args
    proc = subprocess.run(argv, capture_output=True, text=True)
    return {"argv": argv[1:], "rc": proc.returncode,
            "stdout": proc.stdout[:300], "stderr": proc.stderr.strip()[:300]}


def listener_owner(port):
    proc = subprocess.run(["lsof", "-nP", "-iTCP:%d" % port, "-sTCP:LISTEN"],
                          capture_output=True, text=True)
    rows = [l for l in proc.stdout.splitlines() if l.strip()]
    pids = []
    for row in rows[1:]:
        parts = row.split()
        if len(parts) > 1 and parts[1].isdigit():
            pids.append(int(parts[1]))
    return {"rc": proc.returncode, "rows": rows, "pids": sorted(set(pids))}


def start_serve(env, port, tag):
    """Same launch as the gate's serving leg, but the env is kept for auditing."""
    e = gate.child_env(env, "serve-service")
    e["SIMIGO_LOCALB_SERVE_MODEL"] = gate.MODEL
    e["SIMIGO_LOCALB_SERVE_PORT"] = str(port)
    e["SIMIGO_PORT"] = str(port)
    forwarded = sorted(k for k, v in e.items()
                       if k.startswith("SIMIGO_") and isinstance(v, str) and v)
    relaxed = [k for k in forwarded if any(m in k.upper() for m in RELAX_MARKERS)]
    out = open(os.path.join(OUT, tag + ".stdout"), "w")
    err = open(os.path.join(OUT, tag + ".stderr"), "w")
    proc = subprocess.Popen([gate.BIN], env=e, stdout=out, stderr=err)
    log("%s pid=%d port=%d" % (tag, proc.pid, port))
    return proc, {"forwarded_simigo_keys": forwarded,
                  "relaxing_keys": relaxed,
                  "authorization_relaxed": 0 if not relaxed else 1}


def leg_activated(result):
    env = gate.fresh_roots("U1")
    home = env["SIMIGO_HOME"]
    trace = os.path.join(home, "logs", "native_mlx_trace.log")
    client_dir = os.path.join(B, ROOT_PREFIX + "U1", "client")
    key_file = os.path.join(client_dir, "client-key.json")
    body_file = os.path.join(client_dir, "chat_body.json")
    with open(body_file, "w") as fh:
        json.dump(gate.CHAT_BODY, fh)

    prep = gate.role("prepare", env, "U1_prepare")
    result["prepare"] = prep
    prepared = prep["result"] or {}
    if prep["rc"] != 0 or not prepared.get("checkpoint"):
        result["blocked_reason"] = "prepare failed"
        return
    checkpoint = prepared["checkpoint"]
    spki = prepared["transport_spki_sha256"]
    result["activate"] = gate.role("activate", dict(env, SIMIGO_LOCALB_CHECKPOINT=checkpoint),
                                  "U1_activate")
    result["keygen"] = gate.client(["keygen", "--out", key_file])
    client_pub = (result["keygen"]["result"] or {}).get("public_key_hex", "")

    serve, env_audit = start_serve(env, PORT_TLS, "U1_serve")
    result["env_audit"] = env_audit
    ok, health = gate.wait_health(PORT_TLS, 420)
    result["listener_ready"] = ok
    result["health_after_start"] = health
    if not ok:
        result["blocked_reason"] = "listener never answered /health"
        gate.stop(serve, "U1_serve")
        return

    owner = listener_owner(PORT_TLS)
    result["listening_socket"] = {"lsof": owner, "candidate_pid": serve.pid,
                                  "owned_by_candidate": serve.pid in owner["pids"]}

    result["plaintext_to_tls_port"] = curl(["http://127.0.0.1:%d/v1/models" % PORT_TLS])
    result["default_trust_tls"] = curl(["https://127.0.0.1:%d/v1/models" % PORT_TLS])
    result["tls_no_proof"] = curl(["-k", "-o", "/dev/null", "-w", "%{http_code}",
                                   "https://127.0.0.1:%d/v1/models" % PORT_TLS])
    result["spki_match"] = gate.client(["spki", "--port", str(PORT_TLS), "--expect", spki])

    issued = gate.role("pair-issue",
                       dict(env, SIMIGO_LOCALB_CLIENT_PUBKEY_HEX=client_pub,
                            SIMIGO_LOCALB_SCOPE="localb-service-http"),
                       "U1_pair_issue")
    result["pair_issue"] = issued
    cred = issued["result"] or {}
    if issued["rc"] != 0 or not cred.get("credential_id"):
        result["blocked_reason"] = "pair-issue failed"
        gate.stop(serve, "U1_serve")
        return
    sign = gate.client(["pair-sign", "--key", key_file,
                        "--credential-id", cred["credential_id"],
                        "--session-nonce-hex", cred["session_nonce_hex"],
                        "--host-instance", cred["host_instance_id"],
                        "--spki", cred["tls_spki_sha256"],
                        "--srs-key-id", cred["srs_key_id"],
                        "--protocol", cred["protocol_version"]])
    result["pair_sign"] = sign
    proof = (sign["result"] or {}).get("pairing_proof_hex", "")
    approved = gate.role("pair-approve",
                         dict(env,
                              SIMIGO_LOCALB_CREDENTIAL_ID=cred["credential_id"],
                              SIMIGO_LOCALB_SECRET_B64URL=cred["secret_b64url"],
                              SIMIGO_LOCALB_CLIENT_PUBKEY_HEX=client_pub,
                              SIMIGO_LOCALB_PAIRING_PROOF_HEX=proof,
                              SIMIGO_LOCALB_TLS_SPKI_HEX=cred["tls_spki_sha256"],
                              SIMIGO_LOCALB_SRS_KEY_ID=cred["srs_key_id"],
                              SIMIGO_LOCALB_PROTOCOL_VERSION=cred["protocol_version"],
                              SIMIGO_LOCALB_CHECKPOINT=checkpoint),
                         "U1_pair_approve")
    result["pair_approve"] = approved
    client_key_id = (approved["result"] or {}).get("client_key_id", "")

    before = gate.trace_count(home)
    authorized = gate.client(["request", "--port", str(PORT_TLS),
                              "--key", key_file, "--client-key-id", client_key_id,
                              "--body", body_file, "--expect-spki", spki,
                              "--out-body", os.path.join(OUT, "U1_authorized_body.json")])
    after = gate.trace_count(home)
    authorized["generation_trace"] = {"before": before, "after": after,
                                      "delta": after - before, "trace_file": trace}
    result["authorized_request"] = authorized
    result["facade_markers"] = gate.facade_markers(trace)
    gate.stop(serve, "U1_serve")


def leg_unconfigured(result):
    env = gate.fresh_roots("U2")
    home = env["SIMIGO_HOME"]
    trace = os.path.join(home, "logs", "native_mlx_trace.log")
    prep = gate.role("prepare", env, "U2_prepare_noactivate")
    result["prepare"] = prep
    result["trusted_checkpoint_present"] = os.path.exists(
        os.path.join(home, "localb", "trusted-checkpoint.json"))
    serve, env_audit = start_serve(env, PORT_UNAUTH, "U2_serve_unactivated")
    result["env_audit"] = env_audit
    ok, health = gate.wait_health(PORT_UNAUTH, 420)
    result["listener_ready"] = ok
    result["health_after_start"] = health
    if not ok:
        result["blocked_reason"] = "listener never answered /health"
        gate.stop(serve, "U2_serve_unactivated")
        return
    result["listening_socket"] = {"lsof": listener_owner(PORT_UNAUTH),
                                  "candidate_pid": serve.pid,
                                  "owned_by_candidate": serve.pid in listener_owner(PORT_UNAUTH)["pids"]}
    before = gate.trace_count(home)
    status, body = gate.https_post(PORT_UNAUTH, "/localb/auth/challenge",
                                   {"method": "POST",
                                    "requestTarget": "/v1/chat/completions"})
    after = gate.trace_count(home)
    result["guarded_route"] = {"status": status, "body": body[:300],
                               "generation_trace": {"before": before, "after": after,
                                                    "delta": after - before,
                                                    "trace_file": trace}}
    gate.stop(serve, "U2_serve_unactivated")


def main():
    global OUT, PORT_TLS, PORT_UNAUTH
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=os.path.join(B, "install_v5", "SimiGo.app"))
    parser.add_argument("--port-base", type=int, default=8500)
    parser.add_argument("--evidence-dir", default=OUT)
    opts = parser.parse_args()
    OUT = opts.evidence_dir
    os.makedirs(OUT, exist_ok=True)
    PORT_TLS = opts.port_base
    PORT_UNAUTH = opts.port_base + 1
    gate.EV = OUT
    gate.SERVING_ROLE = "serve-service"
    gate.ROOT_PREFIX = ROOT_PREFIX
    gate.APP = opts.app
    gate.BIN = os.path.join(opts.app, "Contents", "MacOS", "SimiGo")

    result = {"batch": os.path.basename(B),
              "candidate": opts.app,
              "serve_role": gate.SERVING_ROLE,
              "ports": [PORT_TLS, PORT_UNAUTH],
              "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
              "activated": {}, "unconfigured": {}}
    leg_activated(result["activated"])
    leg_unconfigured(result["unconfigured"])

    act, unauth = result["activated"], result["unconfigured"]
    plain = act.get("plaintext_to_tls_port") or {}
    trust = act.get("default_trust_tls") or {}
    no_proof = act.get("tls_no_proof") or {}
    auth = act.get("authorized_request") or {}
    guarded = unauth.get("guarded_route") or {}
    tokens = {
        "listening_socket_found": 1 if (act.get("listening_socket") or {}).get("owned_by_candidate") else 0,
        "authorized_request_completed": 1 if (auth.get("result") or {}).get("status") == 200 else 0,
        "http_status_503_unconfigured": guarded.get("status"),
        "tls_only_transport": 1 if (plain.get("rc") not in (0, None)
                                   and "http" not in (plain.get("stdout") or "").lower()
                                   and trust.get("rc") == 60) else 0,
        "authorization_relaxed": max((act.get("env_audit") or {}).get("authorization_relaxed", 0),
                                    (unauth.get("env_audit") or {}).get("authorization_relaxed", 0)),
        "generation_call_count_authorized": (auth.get("generation_trace") or {}).get("delta"),
        "generation_call_count_unconfigured": (guarded.get("generation_trace") or {}).get("delta"),
        "proof_refused_status": (no_proof.get("stdout") or "").strip() or None,
    }
    result["tokens"] = tokens
    result["finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    path = os.path.join(OUT, "service_http_transport_probe_v5.json")
    with open(path, "w") as fh:
        json.dump(result, fh, indent=1, sort_keys=True)
    log("tokens: " + json.dumps(tokens, ensure_ascii=False))
    log("wrote " + path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
