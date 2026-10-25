#!/usr/bin/env python3
"""Negative LOCALB probes against the installed candidate's real listener.

Every case goes through the product's own TLS listener; nothing here calls the
model or any product API. Each case brackets its request with a line count of the
product's own generation trace (`<SIMIGO_HOME>/logs/native_mlx_trace.log`), so a
refusal that still generated is visible as a non-zero delta.

Cases
  1. fabricated_proof  challenge obtained, proof replaced with 64 random bytes
  2. no_proof_headers  protected route without the three LOCALB headers
  3. challenge_replay  one valid request (expected 200), then the same
                       challenge + proof + body replayed (expected refusal)
"""
import argparse
import base64
import hashlib
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import localb_client as lc


def trace_lines(path):
    if not path or not os.path.exists(path):
        return 0
    with open(path, errors="replace") as handle:
        return sum(1 for _ in handle)


def ask_challenge(conn, client_key_id, target):
    conn.request("POST", "/localb/auth/challenge",
                 body=json.dumps({"method": "POST", "requestTarget": target}),
                 headers={"content-type": "application/json",
                          "x-simigo-localb-client-key-id": client_key_id})
    response = conn.getresponse()
    body = response.read().decode("utf-8", "replace")
    return response.status, body


def proof_for(key, client_key_id, authority, target, body, challenge, permission):
    payload = lc.request_input(
        client_key_id, permission, "POST", authority, target, "application/json",
        "identity", hashlib.sha256(body).hexdigest(), len(body), challenge)
    return base64.b64encode(key.sign(payload)).decode("ascii")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--client-key-id", required=True)
    parser.add_argument("--body", required=True)
    parser.add_argument("--target", default="/v1/chat/completions")
    parser.add_argument("--permission", default="P-INFERENCE")
    parser.add_argument("--expect-spki", default="")
    parser.add_argument("--trace-file", default="")
    parser.add_argument("--out", default="")
    args = parser.parse_args()

    with open(args.body, "rb") as handle:
        body = handle.read()
    key, _pub = lc.load_key(args.key)
    authority = "%s:%d" % (args.host, args.port)
    result = {"cases": {}, "observed_spki_sha256": None}

    conn, spki, _der = lc.tls_connection(args.host, args.port)
    try:
        result["observed_spki_sha256"] = spki
        if args.expect_spki and spki != args.expect_spki:
            result["error"] = "tls-spki-mismatch"
            lc.emit(result, args.out)
            return 5

        # 0. if the host is not authorized yet, the guard answers the open
        # challenge route too; record that instead of fabricating a proof
        status, challenge_body = ask_challenge(conn, args.client_key_id, args.target)
        if status != 200:
            before = trace_lines(args.trace_file)
            conn.request("POST", args.target, body=body,
                         headers={"content-type": "application/json"})
            response = conn.getresponse()
            guard_body = response.read().decode("utf-8", "replace")
            result["refused_at_guard"] = {
                "challenge_status": status, "challenge_body": challenge_body[:400],
                "protected_status": response.status, "protected_body": guard_body[:400],
                "trace_delta": trace_lines(args.trace_file) - before}
            lc.emit(result, args.out)
            return 0 if response.status != 200 else 6

        # 1. fabricated proof: a correct challenge with a proof over other bytes
        challenge = bytes.fromhex(json.loads(challenge_body)["challenge"])
        real = proof_for(key, args.client_key_id, authority, args.target, body,
                         challenge, args.permission)
        fabricated = base64.b64encode(hashlib.sha256(real.encode()).digest() * 2).decode("ascii")
        before = trace_lines(args.trace_file)
        conn.request("POST", args.target, body=body, headers={
            "content-type": "application/json",
            "x-simigo-localb-client-key-id": args.client_key_id,
            "x-simigo-localb-challenge": challenge.hex(),
            "x-simigo-localb-proof-v2": fabricated,
        })
        response = conn.getresponse()
        text = response.read().decode("utf-8", "replace")
        result["cases"]["fabricated_proof"] = {
            "status": response.status, "body": text[:400],
            "trace_delta": trace_lines(args.trace_file) - before}

        # 2. no proof headers at all
        before = trace_lines(args.trace_file)
        conn.request("POST", args.target, body=body,
                     headers={"content-type": "application/json"})
        response = conn.getresponse()
        text = response.read().decode("utf-8", "replace")
        result["cases"]["no_proof_headers"] = {
            "status": response.status, "body": text[:400],
            "trace_delta": trace_lines(args.trace_file) - before}

        # 3. challenge replay: a valid request, then the identical tuple again
        status, challenge_body = ask_challenge(conn, args.client_key_id, args.target)
        challenge = bytes.fromhex(json.loads(challenge_body)["challenge"])
        proof = proof_for(key, args.client_key_id, authority, args.target, body,
                          challenge, args.permission)
        headers = {
            "content-type": "application/json",
            "x-simigo-localb-client-key-id": args.client_key_id,
            "x-simigo-localb-challenge": challenge.hex(),
            "x-simigo-localb-proof-v2": proof,
        }
        before = trace_lines(args.trace_file)
        conn.request("POST", args.target, body=body, headers=headers)
        response = conn.getresponse()
        first_status = response.status
        first_text = response.read().decode("utf-8", "replace")
        first_delta = trace_lines(args.trace_file) - before
        before = trace_lines(args.trace_file)
        conn.request("POST", args.target, body=body, headers=headers)
        response = conn.getresponse()
        replay_text = response.read().decode("utf-8", "replace")
        result["cases"]["challenge_replay"] = {
            "first_status": first_status,
            "first_body": first_text[:200], "first_trace_delta": first_delta,
            "replay_status": response.status, "replay_body": replay_text[:400],
            "replay_trace_delta": trace_lines(args.trace_file) - before}
    finally:
        conn.close()

    lc.emit(result, args.out)
    refused = all(
        result["cases"][name].get("status", result["cases"][name].get("replay_status")) != 200
        for name in ("fabricated_proof", "no_proof_headers", "challenge_replay"))
    return 0 if refused else 6


if __name__ == "__main__":
    sys.exit(main())
