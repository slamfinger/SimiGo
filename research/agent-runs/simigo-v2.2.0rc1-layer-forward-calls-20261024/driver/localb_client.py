#!/usr/bin/env python3
"""External LOCALB client for the SimiGo Service/HTTP acceptance lane.

This process is deliberately outside the product: it speaks the product's own
wire protocol over TLS and never calls the model or any product API directly.

    TLS (pinned SPKI) -> POST /localb/auth/challenge
                      -> LOCALB proof V2 over the exact request bytes
                      -> POST /v1/chat/completions (protected)

The canonical encodings below are re-implemented from the package sources
(`LOCALBPairingFieldCodec`, `LOCALBPairingProofV1`,
`LOCALBClientRequestProofV2`); any divergence shows up as a server-side
rejection instead of a silent pass.
"""
import argparse
import base64
import hashlib
import http.client
import json
import os
import ssl
import sys

from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

PAIR_DOMAIN = "SIMIGO_PERSISTENT_SRS_LOCALB_CLIENT_POP_V1"
REQUEST_DOMAIN = "SIMIGO_PERSISTENT_SRS_LOCALB_CLIENT_REQUEST_CONTENT_V2"
CANON_VERSION = "LOCALB_HTTP_REQUEST_CANONICAL_V1"


def be(value, width):
    return int(value).to_bytes(width, "big")


def field(label, ftype, value):
    lb = label.encode("utf-8")
    return be(len(lb), 2) + lb + bytes([ftype]) + be(len(value), 8) + value


def s(label, value):
    return field(label, 0x02, value.encode("utf-8"))


def b(label, value):
    return field(label, 0x04, value)


def encode(domain, fields):
    return domain.encode("utf-8") + b"\x00" + be(len(fields), 4) + b"".join(fields)


def pairing_input(credential_id, session_nonce, host_instance_id,
                  tls_spki, srs_key_id, protocol_version, client_pub):
    return encode(PAIR_DOMAIN, [
        s("credential_id", credential_id),
        b("session_nonce", session_nonce),
        s("host_instance_id", host_instance_id),
        s("tls_spki_sha256", tls_spki),
        s("srs_key_id", srs_key_id),
        s("protocol_version", protocol_version),
        b("client_public_key_raw", client_pub),
    ])


def request_input(client_key_id, permission, method, authority, target,
                  content_type, content_encoding, body_sha256, body_length,
                  challenge):
    return encode(REQUEST_DOMAIN, [
        s("canonicalization_version", CANON_VERSION),
        s("client_key_id", client_key_id),
        s("required_permission", permission),
        b("server_challenge", challenge),
        s("http_method", method),
        s("authority", authority),
        s("request_target", target),
        s("content_type", content_type),
        s("content_encoding", content_encoding),
        s("body_sha256", body_sha256),
        b("body_length", be(body_length, 8)),
    ])


def load_key(path):
    with open(path, "r", encoding="utf-8") as handle:
        material = json.load(handle)
    return (Ed25519PrivateKey.from_private_bytes(bytes.fromhex(material["private_key_hex"])),
            bytes.fromhex(material["public_key_hex"]))


def tls_connection(host, port, timeout=20.0):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    conn = http.client.HTTPSConnection(host, port, timeout=timeout, context=context)
    conn.connect()
    der = conn.sock.getpeercert(binary_form=True)
    if not der:
        raise SystemExit("tls: no peer certificate")
    spki = hashlib.sha256(
        x509.load_der_x509_certificate(der).public_key().public_bytes(
            serialization.Encoding.DER,
            serialization.PublicFormat.SubjectPublicKeyInfo,
        )
    ).hexdigest()
    return conn, spki, der.hex()


def emit(payload, out=None):
    text = json.dumps(payload, sort_keys=True)
    if out:
        with open(out, "w", encoding="utf-8") as handle:
            handle.write(text + "\n")
    print(text)


def cmd_keygen(args):
    key = Ed25519PrivateKey.generate()
    pub = key.public_key().public_bytes(
        serialization.Encoding.Raw, serialization.PublicFormat.Raw
    )
    seed = key.private_bytes(
        serialization.Encoding.Raw,
        serialization.PrivateFormat.Raw,
        serialization.NoEncryption(),
    )
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    fd = os.open(args.out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump({"private_key_hex": seed.hex(), "public_key_hex": pub.hex()}, handle)
    emit({"public_key_hex": pub.hex(), "key_file": args.out})


def cmd_spki(args):
    conn, spki, der = tls_connection(args.host, args.port)
    conn.close()
    verdict = "match" if (not args.expect or spki == args.expect) else "MISMATCH"
    emit({"observed_spki_sha256": spki, "expected": args.expect,
          "verdict": verdict, "certificate_der_hex": der})
    if verdict != "match":
        return 5
    return 0


def cmd_pair_sign(args):
    key, pub = load_key(args.key)
    payload = pairing_input(
        args.credential_id,
        bytes.fromhex(args.session_nonce_hex),
        args.host_instance,
        args.spki,
        args.srs_key_id,
        args.protocol,
        pub,
    )
    signature = key.sign(payload)
    emit({"pairing_proof_hex": signature.hex(),
          "signing_input_sha256": hashlib.sha256(payload).hexdigest()})
    return 0


def cmd_challenge(args):
    conn, spki, _ = tls_connection(args.host, args.port)
    try:
        conn.request("POST", "/localb/auth/challenge",
                     body=json.dumps({"method": "POST",
                                      "requestTarget": "/v1/chat/completions"}),
                     headers={"content-type": "application/json",
                              "x-simigo-localb-client-key-id": args.client_key_id})
        response = conn.getresponse()
        body = response.read().decode("utf-8", "replace")
        emit({"status": response.status, "body": body,
              "observed_spki_sha256": spki})
        return 0 if response.status == 200 else 6
    finally:
        conn.close()


def cmd_request(args):
    with open(args.body, "rb") as handle:
        body = handle.read()
    key, _pub = load_key(args.key)
    conn, spki, _ = tls_connection(args.host, args.port)
    try:
        if args.expect_spki and spki != args.expect_spki:
            emit({"error": "tls-spki-mismatch", "observed": spki})
            return 5
        target = args.target
        authority = "%s:%d" % (args.host, args.port)
        content_type = "application/json"
        # 1. challenge (open route)
        conn.request("POST", "/localb/auth/challenge",
                     body=json.dumps({"method": "POST", "requestTarget": target}),
                     headers={"content-type": "application/json",
                              "x-simigo-localb-client-key-id": args.client_key_id})
        challenge_response = conn.getresponse()
        challenge_body = challenge_response.read().decode("utf-8", "replace")
        if challenge_response.status != 200:
            emit({"stage": "challenge", "status": challenge_response.status,
                  "body": challenge_body})
            return 6
        challenge = bytes.fromhex(json.loads(challenge_body)["challenge"])
        # 2. proof V2 over the exact tuple we are about to send
        payload = request_input(
            args.client_key_id, args.permission, "POST", authority, target,
            content_type, "identity", hashlib.sha256(body).hexdigest(),
            len(body), challenge,
        )
        proof = base64.b64encode(key.sign(payload)).decode("ascii")
        # 3. the protected request itself
        conn.request("POST", target, body=body, headers={
            "content-type": content_type,
            "x-simigo-localb-client-key-id": args.client_key_id,
            "x-simigo-localb-challenge": challenge.hex(),
            "x-simigo-localb-proof-v2": proof,
        })
        response = conn.getresponse()
        response_body = response.read().decode("utf-8", "replace")
        if args.out_body:
            with open(args.out_body, "w", encoding="utf-8") as handle:
                handle.write(response_body)
        emit({"stage": "request", "status": response.status,
              "body": response_body[:2000],
              "observed_spki_sha256": spki,
              "signing_input_sha256": hashlib.sha256(payload).hexdigest(),
              "body_bytes": len(body)})
        return 0 if response.status == 200 else 6
    finally:
        conn.close()


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("keygen")
    p.add_argument("--out", required=True)
    p.set_defaults(func=cmd_keygen)

    p = sub.add_parser("spki")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--expect", default="")
    p.set_defaults(func=cmd_spki)

    p = sub.add_parser("pair-sign")
    p.add_argument("--key", required=True)
    p.add_argument("--credential-id", required=True)
    p.add_argument("--session-nonce-hex", required=True)
    p.add_argument("--host-instance", required=True)
    p.add_argument("--spki", required=True)
    p.add_argument("--srs-key-id", required=True)
    p.add_argument("--protocol", required=True)
    p.set_defaults(func=cmd_pair_sign)

    p = sub.add_parser("challenge")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--client-key-id", required=True)
    p.set_defaults(func=cmd_challenge)

    p = sub.add_parser("request")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, required=True)
    p.add_argument("--key", required=True)
    p.add_argument("--client-key-id", required=True)
    p.add_argument("--body", required=True)
    p.add_argument("--target", default="/v1/chat/completions")
    p.add_argument("--permission", default="P-INFERENCE")
    p.add_argument("--expect-spki", default="")
    p.add_argument("--out-body", default="")
    p.set_defaults(func=cmd_request)

    args = parser.parse_args()
    sys.exit(args.func(args))


if __name__ == "__main__":
    main()
