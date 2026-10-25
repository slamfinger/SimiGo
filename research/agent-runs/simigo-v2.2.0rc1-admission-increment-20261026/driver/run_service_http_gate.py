#!/usr/bin/env python3
"""Service/HTTP gate, run against the REBUILT and INSTALLED candidate.

The candidate is `install/SimiGo.app` - byte-identical to the Release build
product of this batch. Every leg uses the product's own app binary:

  * control legs run the shipped first-run ceremony / pairing primitives through
    the product's env-gated management role (SIMIGO_LOCALB_MGMT=...), which only
    forwards to existing public APIs and refuses to run without an isolated
    SIMIGO_HOME;
  * the serving leg is the product's own listener, TLS-only, LOCALB proof gate intact;
    with --serve-role serve-service the same leg is started through the product's
    own orchestration surface (Service.shared.start(path:)) instead of the runtime
    call that surface forwards to, so the gate can be judged on the Service path
    itself as well;
  * the client legs are the external Python client, never the product API, and
    every request goes over TLS to the listening socket.

Trace deltas are line counts of the product's own generation trace
(<SIMIGO_HOME>/logs/native_mlx_trace.log), so "refused before generation" is a
measured 0 rather than an assumption.

usage: run_service_http_gate.py [--positive-only]
"""
import json
import os
import shutil
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request

B2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(B2, "install", "SimiGo.app")
BIN = os.path.join(APP, "Contents", "MacOS", "SimiGo")
EV = os.path.join(B2, "evidence", "gate_installed")
CLIENT = os.path.join(B2, "driver", "localb_client.py")
PROBE = os.path.join(B2, "driver", "localb_negative_probe.py")
MODEL = ("/Users/mr.simi/.cache/huggingface/hub/models--mlx-community--"
         "Qwen3-Coder-30B-A3B-Instruct-4bit/snapshots/6e302ea604ad9ab206367e2c501d1571023e7b6d")
PORT_POSITIVE = 8100
PORT_NO_AUTH = 8101
PORT_FRESH = 8102
ROOT_PREFIX = "m3i"
SERVING_ROLE = "serve"
CHAT_BODY = {"model": "mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit",
             "messages": [{"role": "user", "content": "Reply with exactly: SERVICE-HTTP-OK"}],
             "max_tokens": 16, "temperature": 0}


def log(msg):
    print("[gate] " + msg, flush=True)


def fresh_roots(suffix):
    root = os.path.join(B2, ROOT_PREFIX + suffix)
    if os.path.exists(root):
        shutil.rmtree(root)
    for sub in ("home", "cache", "state-graph", "client"):
        os.makedirs(os.path.join(root, sub), exist_ok=True)
    return {"SIMIGO_HOME": os.path.join(root, "home"),
            "SIMIGO_CACHE_ROOT": os.path.join(root, "cache"),
            "SIMIGO_STATE_GRAPH_STORE": os.path.join(root, "state-graph", "reference-graph-v1.json")}


def child_env(env, role):
    e = {k: v for k, v in os.environ.items()
         if not k.startswith("SIMIGO_")}
    e.update(env)
    e["SIMIGO_LOCALB_MGMT"] = role
    return e


def last_json(stdout):
    payload = None
    for line in stdout.splitlines():
        line = line.strip()
        if line.startswith("{"):
            try:
                payload = json.loads(line)
            except ValueError:
                pass
    return payload


def role(role_name, env, tag, timeout=300):
    proc = subprocess.run([BIN], env=child_env(env, role_name),
                          capture_output=True, text=True, timeout=timeout)
    with open(os.path.join(EV, tag + ".stdout"), "w") as fh:
        fh.write(proc.stdout)
    with open(os.path.join(EV, tag + ".stderr"), "w") as fh:
        fh.write(proc.stderr)
    payload = last_json(proc.stdout)
    log("%s rc=%d payload=%s" % (tag, proc.returncode,
                                 "yes" if payload else "none"))
    return {"role": role_name, "rc": proc.returncode, "result": payload,
            "stderr_tail": proc.stderr[-800:]}


def client(args, timeout=600):
    proc = subprocess.run([sys.executable, CLIENT] + args, capture_output=True,
                          text=True, timeout=timeout)
    payload = last_json(proc.stdout)
    log("client %s rc=%d" % (args[0], proc.returncode))
    return {"rc": proc.returncode, "result": payload, "stderr_tail": proc.stderr[-800:]}


def probe(args, timeout=600):
    proc = subprocess.run([sys.executable, PROBE] + args, capture_output=True,
                          text=True, timeout=timeout)
    payload = last_json(proc.stdout)
    log("probe rc=%d" % proc.returncode)
    return {"rc": proc.returncode, "result": payload, "stderr_tail": proc.stderr[-800:]}


def trace_count(home):
    path = os.path.join(home, "logs", "native_mlx_trace.log")
    if not os.path.exists(path):
        return 0
    with open(path, errors="replace") as fh:
        return sum(1 for _ in fh)


def https_get(port, target, timeout=5):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    try:
        with urllib.request.urlopen("https://127.0.0.1:%d%s" % (port, target),
                                    context=ctx, timeout=timeout) as rsp:
            return rsp.status, rsp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")
    except Exception as exc:  # noqa: BLE001 - a dead listener is a result too
        return None, repr(exc)


def https_post(port, target, payload, timeout=15):
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    body = json.dumps(payload).encode()
    request = urllib.request.Request("https://127.0.0.1:%d%s" % (port, target),
                                     data=body, method="POST",
                                     headers={"content-type": "application/json"})
    try:
        with urllib.request.urlopen(request, context=ctx, timeout=timeout) as rsp:
            return rsp.status, rsp.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode("utf-8", "replace")
    except Exception as exc:  # noqa: BLE001
        return None, repr(exc)


def start_serve(env, port, tag):
    out = open(os.path.join(EV, tag + ".stdout"), "w")
    err = open(os.path.join(EV, tag + ".stderr"), "w")
    e = child_env(env, SERVING_ROLE)
    e["SIMIGO_LOCALB_SERVE_MODEL"] = MODEL
    e["SIMIGO_LOCALB_SERVE_PORT"] = str(port)
    if SERVING_ROLE == "serve-service":
        # Service resolves its node address from the product's own env rule;
        # the value is then read back from the facade's [NODE] trace line.
        e["SIMIGO_PORT"] = str(port)
    proc = subprocess.Popen([BIN], env=e, stdout=out, stderr=err)
    log("%s pid=%d port=%d role=%s" % (tag, proc.pid, port, SERVING_ROLE))
    return proc


def facade_markers(trace):
    """Count the lines ONLY the Service facade emits.

    `[CFG] source=` is deliberately not a marker on its own: resolveConfig also
    runs on other paths, so it is counted but not treated as proof.
    """
    out = {"trace_file": trace, "exists": os.path.exists(trace),
           "node_backend_lines": 0, "ready_lines": 0, "cfg_source_lines": 0,
           "samples": []}
    if not out["exists"]:
        return out
    with open(trace, errors="replace") as fh:
        for line in fh:
            if "[NODE] backend=" in line:
                out["node_backend_lines"] += 1
            if "[READY] " in line:
                out["ready_lines"] += 1
            if "[CFG] source=" in line:
                out["cfg_source_lines"] += 1
            if len(out["samples"]) < 4 and ("[NODE] backend=" in line
                                            or "[READY] " in line):
                out["samples"].append(line.strip()[-200:])
    return out


def payload_of(tag):
    path = os.path.join(EV, tag + ".stdout")
    if not os.path.exists(path):
        return None
    with open(path, errors="replace") as fh:
        return last_json(fh.read())


def wait_health(port, seconds):
    deadline = time.time() + seconds
    last = None
    while time.time() < deadline:
        status, body = https_get(port, "/health")
        last = {"status": status, "body": body[:200]}
        if status == 200:
            return True, last
        time.sleep(2)
    return False, last


def stop(proc, tag):
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=30)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=30)
    log("%s exited rc=%s" % (tag, proc.returncode))
    return proc.returncode


def positive_leg(result):
    env = fresh_roots("A")
    home = env["SIMIGO_HOME"]
    trace = os.path.join(home, "logs", "native_mlx_trace.log")
    key_file = os.path.join(ROOT_PREFIX and os.path.join(B2, ROOT_PREFIX + "A"), "client", "client-key.json")
    body_file = os.path.join(ROOT_PREFIX and os.path.join(B2, ROOT_PREFIX + "A"), "client", "chat_body.json")
    with open(body_file, "w") as fh:
        json.dump(CHAT_BODY, fh)

    prep = role("prepare", env, "A1_prepare")
    prepared = prep["result"] or {}
    result["prepare"] = prep
    if prep["rc"] != 0 or not prepared.get("checkpoint"):
        result["blocked_reason"] = "prepare failed"
        return

    checkpoint = prepared["checkpoint"]
    spki = prepared["transport_spki_sha256"]
    srs_key = prepared["signer_key_id"]
    host_instance = prepared["lineage_id"]
    result["activate"] = role("activate",
                              dict(env, SIMIGO_LOCALB_CHECKPOINT=checkpoint),
                              "A2_activate")
    result["keygen"] = client(["keygen", "--out", key_file])
    client_pub = (result["keygen"]["result"] or {}).get("public_key_hex", "")

    serve = start_serve(env, PORT_POSITIVE, "A3_serve")
    ok, health = wait_health(PORT_POSITIVE, 420)
    result["listener_ready"] = ok
    result["health_after_start"] = health
    result["serve_role"] = SERVING_ROLE
    result["serve_payload"] = payload_of("A3_serve")
    result["facade_markers"] = facade_markers(trace)
    if not ok:
        result["blocked_reason"] = "listener never answered /health"
        stop(serve, "A3_serve")
        return

    result["tls_spki_observation"] = client(
        ["spki", "--port", str(PORT_POSITIVE), "--expect", spki])

    issued = role("pair-issue",
                  dict(env, SIMIGO_LOCALB_CLIENT_PUBKEY_HEX=client_pub,
                       SIMIGO_LOCALB_SCOPE="localb-service-http"),
                  "A4_pair_issue")
    result["pair_issue"] = issued
    cred = issued["result"] or {}
    if issued["rc"] != 0 or not cred.get("credential_id"):
        result["blocked_reason"] = "pair-issue failed"
        stop(serve, "A3_serve")
        return

    sign = client(["pair-sign", "--key", key_file,
                   "--credential-id", cred["credential_id"],
                   "--session-nonce-hex", cred["session_nonce_hex"],
                   "--host-instance", cred["host_instance_id"],
                   "--spki", cred["tls_spki_sha256"],
                   "--srs-key-id", cred["srs_key_id"],
                   "--protocol", cred["protocol_version"]])
    result["pair_sign"] = sign
    proof = (sign["result"] or {}).get("pairing_proof_hex", "")

    approved = role("pair-approve",
                    dict(env,
                         SIMIGO_LOCALB_CREDENTIAL_ID=cred["credential_id"],
                         SIMIGO_LOCALB_SECRET_B64URL=cred["secret_b64url"],
                         SIMIGO_LOCALB_CLIENT_PUBKEY_HEX=client_pub,
                         SIMIGO_LOCALB_PAIRING_PROOF_HEX=proof,
                         SIMIGO_LOCALB_TLS_SPKI_HEX=cred["tls_spki_sha256"],
                         SIMIGO_LOCALB_SRS_KEY_ID=cred["srs_key_id"],
                         SIMIGO_LOCALB_PROTOCOL_VERSION=cred["protocol_version"],
                         SIMIGO_LOCALB_CHECKPOINT=checkpoint),
                    "A5_pair_approve")
    result["pair_approve"] = approved
    client_key_id = (approved["result"] or {}).get("client_key_id", "")

    before = trace_count(home)
    authorized = client(["request", "--port", str(PORT_POSITIVE),
                         "--key", key_file, "--client-key-id", client_key_id,
                         "--body", body_file, "--expect-spki", spki,
                         "--out-body", os.path.join(EV, "A6_authorized_body.json")])
    after = trace_count(home)
    authorized["generation_trace"] = {"before": before, "after": after,
                                      "delta": after - before,
                                      "trace_file": trace}
    result["authorized_request"] = authorized

    result["negative_probes"] = probe(
        ["--port", str(PORT_POSITIVE), "--key", key_file,
         "--client-key-id", client_key_id, "--body", body_file,
         "--expect-spki", spki, "--trace-file", trace,
         "--out", os.path.join(EV, "A7_negative_probes.json")])
    result["open_route_health"] = dict(zip(("status", "body"),
                                           https_get(PORT_POSITIVE, "/health")))
    result["trusted_checkpoint_present"] = os.path.exists(
        os.path.join(home, "localb", "trusted-checkpoint.json"))
    stop(serve, "A3_serve")


def no_authorization_leg(result):
    env = fresh_roots("B")
    trace = os.path.join(env["SIMIGO_HOME"], "logs", "native_mlx_trace.log")
    key_file = os.path.join(ROOT_PREFIX and os.path.join(B2, ROOT_PREFIX + "B"), "client", "client-key.json")
    body_file = os.path.join(ROOT_PREFIX and os.path.join(B2, ROOT_PREFIX + "B"), "client", "chat_body.json")
    with open(body_file, "w") as fh:
        json.dump(CHAT_BODY, fh)
    prep = role("prepare", env, "B1_prepare_noactivate")
    result["prepare"] = prep
    result["activate"] = None
    result["trusted_checkpoint_present"] = os.path.exists(
        os.path.join(env["SIMIGO_HOME"], "localb", "trusted-checkpoint.json"))
    client(["keygen", "--out", key_file])

    serve = start_serve(env, PORT_NO_AUTH, "B2_serve_noauth")
    ok, health = wait_health(PORT_NO_AUTH, 420)
    result["listener_ready"] = ok
    result["health_after_start"] = health
    if not ok:
        result["blocked_reason"] = "listener never answered /health"
        stop(serve, "B2_serve_noauth")
        return

    before = trace_count(env["SIMIGO_HOME"])
    result["challenge_route"] = dict(zip(("status", "body"), https_post(
        PORT_NO_AUTH, "/localb/auth/challenge",
        {"method": "POST", "requestTarget": "/v1/chat/completions"})))
    guarded = probe(["--port", str(PORT_NO_AUTH), "--key", key_file,
                     "--client-key-id", "unpaired-client", "--body", body_file,
                     "--trace-file", trace,
                     "--out", os.path.join(EV, "B3_noauth_probe.json")])
    after = trace_count(env["SIMIGO_HOME"])
    guarded["generation_trace"] = {"before": before, "after": after,
                                   "delta": after - before}
    result["protected_route"] = guarded
    stop(serve, "B2_serve_noauth")


def fresh_root_leg(result):
    env = fresh_roots("C")
    proc = start_serve(env, PORT_FRESH, "C1_serve_unprepared")
    deadline = time.time() + 180
    while proc.poll() is None and time.time() < deadline:
        time.sleep(2)
    if proc.poll() is None:
        stop(proc, "C1_serve_unprepared")
        result["rc"] = None
        result["exited_before_listening"] = False
    else:
        result["rc"] = proc.returncode
        result["exited_before_listening"] = True
    result["status"] = None
    result["error"] = None
    path = os.path.join(EV, "C1_serve_unprepared.stdout")
    if os.path.exists(path):
        payload = last_json(open(path).read())
        if payload:
            result["status"] = payload.get("localb_status")
            result["error"] = payload.get("error")
            result["payload"] = payload
    result["health"] = dict(zip(("status", "body"), https_get(PORT_FRESH, "/health")))
    result["generation_trace"] = {"trace_file": os.path.join(env["SIMIGO_HOME"], "logs", "native_mlx_trace.log"),
                                  "exists": os.path.exists(os.path.join(env["SIMIGO_HOME"], "logs", "native_mlx_trace.log"))}


def main():
    global EV, PORT_POSITIVE, PORT_NO_AUTH, PORT_FRESH, ROOT_PREFIX, APP, BIN, SERVING_ROLE
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-dir", default=EV)
    parser.add_argument("--roots-prefix", default=ROOT_PREFIX)
    parser.add_argument("--port-base", type=int, default=PORT_POSITIVE)
    parser.add_argument("--positive-only", action="store_true")
    parser.add_argument("--app", default=APP,
                        help="installed candidate to exercise (default: install/SimiGo.app)")
    parser.add_argument("--build-product", default=None,
                        help="release product to diff the candidate against "
                             "(default: build/Build/Products/Release/SimiGo.app)")
    parser.add_argument("--serve-role", default="serve",
                        choices=["serve", "serve-service"],
                        help="serve = runtime call Service forwards to; "
                             "serve-service = the Service facade itself")
    opts = parser.parse_args()
    EV = opts.evidence_dir
    ROOT_PREFIX = opts.roots_prefix
    PORT_POSITIVE = opts.port_base
    PORT_NO_AUTH = opts.port_base + 1
    PORT_FRESH = opts.port_base + 2
    SERVING_ROLE = opts.serve_role
    APP = opts.app
    BIN = os.path.join(APP, "Contents", "MacOS", "SimiGo")
    build_product = opts.build_product or os.path.join(
        B2, "build", "Build", "Products", "Release", "SimiGo.app")
    os.makedirs(EV, exist_ok=True)
    same = subprocess.run(["diff", "-r", APP, build_product],
                          capture_output=True, text=True)
    result = {"batch": os.path.basename(B2),
              "evidence_dir": EV,
              "roots_prefix": ROOT_PREFIX,
              "ports": [PORT_POSITIVE, PORT_NO_AUTH, PORT_FRESH],
              "candidate": APP,
              "release_product": build_product,
              "serve_role": SERVING_ROLE,
              "candidate_equals_release_product": same.returncode == 0,
              "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
              "positive": {}, "no_authorization": {}, "fresh_root": {}}
    positive_leg(result["positive"])
    if not opts.positive_only:
        no_authorization_leg(result["no_authorization"])
        fresh_root_leg(result["fresh_root"])
    result["finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    out = os.path.join(EV, "service_http_gate_installed.json")
    with open(out, "w") as fh:
        json.dump(result, fh, indent=1, sort_keys=True)
    canonical = os.path.join(B2, "evidence", "service_http_gate_installed.json")
    if os.path.abspath(out) != os.path.abspath(canonical):
        shutil.copyfile(out, canonical) if os.path.abspath(EV) == os.path.abspath(
            os.path.join(B2, "evidence", "gate_installed")) else None
    log("wrote " + out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
