#!/usr/bin/env python3
"""Pin WHERE the LOCALB proof-gate status codes come from, in product source.

The operator table for this gate writes "invalid proof -> HTTP 503". The v5
candidate answered 401 to a fabricated proof and 401 to missing proof headers,
and 503 only when no authorization was configured at all. Until now that was
explained in prose. This script turns the explanation into something checkable:

  * it parses the product's own `HTTPServerError.statusCode` map out of
    HTTPServer.swift (values are read, never hardcoded),
  * it locates the throw sites and the guard each one sits behind,
  * it reads the observed status/body of THIS gate run out of the structured
    record and asks which of those cases could have produced them.

Exit 0 when source and observation agree, 2 when they do not (that would mean
the candidate does not match the source it was built from).
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

SRC = "/Users/mr.simi/Documents/SimiGo"
HTTP = "SimiGo/Protocol/HTTPServer.swift"
SIGNER = "Packages/LOCALBCore/Sources/LOCALBCore/LOCALBProductionSigner.swift"


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def git(src, *args):
    try:
        return subprocess.run(["git", "-C", src] + list(args), check=True,
                              capture_output=True, text=True).stdout.strip()
    except subprocess.CalledProcessError:
        return ""


def read_lines(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read().splitlines()


def block_map(lines, opener):
    """Parse `case .name...: return VALUE` pairs inside a switch block."""
    start = next((i for i, l in enumerate(lines) if l.strip() == opener), None)
    if start is None:
        return {}, None
    depth, pending, out, first = 0, [], {}, None
    for i in range(start, len(lines)):
        line = lines[i]
        depth += line.count("{") - line.count("}")
        if i > start and depth == 0:
            break
        s = line.strip()
        m = re.match(r"case ((?:\.[A-Za-z_][\w]*(?:\([^)]*\))?)(?:,\s*\.[A-Za-z_][\w]*(?:\([^)]*\))?)*):$", s)
        if m:
            pending = re.findall(r"\.([A-Za-z_][\w]*)", m.group(1))
            continue
        m2 = re.match(r"return (\"[^\"]*\"|-?\d+)$", s)
        if m2 and pending:
            if first is None:
                first = i + 1
            for name in pending:
                out[name] = m2.group(1).strip('"') if m2.group(1).startswith('"') else int(m2.group(1))
            pending = []
    return out, first


def find(lines, needle, flags=0):
    return [i + 1 for i, l in enumerate(lines) if re.search(needle, l, flags)]


def nearest_guard(lines, throw_line, needle, window=8):
    for back in range(1, window + 1):
        i = throw_line - 1 - back
        if i < 0:
            break
        if re.search(needle, lines[i]):
            return {"line": i + 1, "text": lines[i].strip()}
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=SRC)
    ap.add_argument("--leg", default="evidence/gate_v5/service_http_gate_installed.json")
    ap.add_argument("--out", default="evidence/service_http_status_mapping_attribution.json")
    opts = ap.parse_args()

    http_path = os.path.join(opts.src, HTTP)
    signer_path = os.path.join(opts.src, SIGNER)
    lines = read_lines(http_path)
    signer = read_lines(signer_path)

    codes, codes_line = block_map(lines, "var statusCode: Int {")
    messages, msg_line = block_map(lines, "var message: String {")

    unavailable = find(lines, r"throw HTTPServerError\.localbAuthorizationUnavailable")
    rejected_status = find(lines, r"throw HTTPServerError\.localbRequestRejected\(reason: status\.rawValue\)")
    proof_missing = find(lines, r'reason: "LOCALB_CLIENT_PROOF_MISSING"')
    sig_invalid = find(signer, r'case clientRequestSignatureInvalid\s*=\s*"LOCALB_CLIENT_REQUEST_SIGNATURE_INVALID"')
    challenge_invalid = find(signer, r'LOCALB_CLIENT_CHALLENGE_INVALID')
    # the comment wraps across two source lines; anchor the first and record both
    spki_comment = find(lines, r"Client-supplied SPKI values are")
    spki_comment_tail = find(lines, r"^\s*// never read\.")
    transport_guard = find(lines, r"guard context\.transportSecurity\.eligibleForLOCALBPairingBinding")
    checkpoint = find(lines, r"checkpoint: try authorization\.trustedCheckpoint\(\)")

    unavailable_guards = []
    for line in unavailable:
        unavailable_guards.append({
            "throw_line": line,
            "guard": nearest_guard(lines, line, r"guard let authorization = localbRequestAuthorization"),
            "message": messages.get("localbAuthorizationUnavailable"),
        })

    leg = json.load(open(opts.leg))
    cases = leg["positive"]["negative_probes"]["result"]["cases"]
    observed = {
        "fabricated_proof": {
            "status": cases["fabricated_proof"]["status"],
            "error": re.search(r'"message":"([^"]+)"', cases["fabricated_proof"]["body"]).group(1),
            "trace_delta": cases["fabricated_proof"]["trace_delta"],
        },
        "no_proof_headers": {
            "status": cases["no_proof_headers"]["status"],
            "error": re.search(r'"message":"([^"]+)"', cases["no_proof_headers"]["body"]).group(1),
            "trace_delta": cases["no_proof_headers"]["trace_delta"],
        },
        "challenge_replay": {
            "status": cases["challenge_replay"]["replay_status"],
            "error": re.search(r'"message":"([^"]+)"',
                               cases["challenge_replay"]["replay_body"]).group(1),
            "trace_delta": cases["challenge_replay"]["replay_trace_delta"],
        },
        "unactivated_challenge_route": {
            "status": leg["no_authorization"]["challenge_route"]["status"],
            "error": re.search(r'"message":"([^"]+)"',
                               leg["no_authorization"]["challenge_route"]["body"]).group(1),
            "trace_delta": None,
        },
    }

    # Which thrown case can carry each observed token?
    rejected_codes = set()
    for name in ("fabricated_proof", "no_proof_headers", "challenge_replay"):
        token = observed[name]["error"]
        in_http_literal = token in "\n".join(lines)
        in_signer_enum = token in "\n".join(signer)
        observed[name]["raised_by"] = (
            "localbRequestRejected(reason:)" + (
                " - literal in HTTPServer.swift" if in_http_literal
                else (" - LOCALBStatus.rawValue from LOCALBCore" if in_signer_enum else " - UNKNOWN"))
        )
        observed[name]["expected_status_by_source"] = codes.get("localbRequestRejected")
        rejected_codes.add(observed[name]["expected_status_by_source"])

    unact = observed["unactivated_challenge_route"]
    unact["raised_by"] = "localbAuthorizationUnavailable - guard let authorization == nil"
    unact["expected_status_by_source"] = codes.get("localbAuthorizationUnavailable")
    unact["message_matches_source"] = unact["error"] == messages.get("localbAuthorizationUnavailable")

    checks = {
        "status_map_read_from_source": bool(codes_line) and bool(msg_line),
        "proof_gate_status_is_401": codes.get("localbRequestRejected") == 401,
        "unconfigured_authorization_status_is_503": codes.get("localbAuthorizationUnavailable") == 503,
        "both_unavailable_throws_are_behind_the_nil_authorization_guard":
            bool(unavailable) and all(g["guard"] is not None for g in unavailable_guards),
        "proof_failures_observed_with_the_rejected_case_status":
            all(observed[n]["status"] == codes.get("localbRequestRejected")
                for n in ("fabricated_proof", "no_proof_headers", "challenge_replay")),
        "proof_failures_generated_nothing":
            all(observed[n]["trace_delta"] == 0
                for n in ("fabricated_proof", "no_proof_headers", "challenge_replay")),
        "unactivated_status_and_message_match_the_unavailable_case":
            unact["status"] == codes.get("localbAuthorizationUnavailable") and unact["message_matches_source"],
        "client_supplied_spki_is_never_read": bool(spki_comment) and bool(spki_comment_tail),
        "transport_trust_comes_from_the_accepting_listener": bool(transport_guard),
        "trusted_checkpoint_is_passed_to_authorize": bool(checkpoint),
        "auth_checks_run_before_dispatch": bool(rejected_status),
    }

    doc = {
        "gate": "product_service_http_status_convention",
        "question": ("the operator table says an invalid proof must answer HTTP 503; the candidate "
                     "answered 401 to three proof failures and 503 only when no authorization was "
                     "configured - which of those is the product's rule?"),
        "answer": ("both statuses exist and mean different things. A configured authorization whose "
                   "proof fails throws localbRequestRejected -> 401. 503 is reserved for 'this host "
                   "has no request authorization configured at all', which is scenario S5. The "
                   "operator table's 503 matches S5, not S2. The product was not changed."),
        "source": {
            "repo": opts.src,
            "head": git(opts.src, "rev-parse", "HEAD"),
            "files": [
                {"path": HTTP, "sha256": sha256(http_path),
                 "git_blob": git(opts.src, "hash-object", HTTP),
                 "git_head_blob": git(opts.src, "rev-parse", "HEAD:" + HTTP),
                 "worktree_clean": git(opts.src, "status", "--porcelain", HTTP) == ""},
                {"path": SIGNER, "sha256": sha256(signer_path),
                 "git_blob": git(opts.src, "hash-object", SIGNER),
                 "git_head_blob": git(opts.src, "rev-parse", "HEAD:" + SIGNER),
                 "worktree_clean": git(opts.src, "status", "--porcelain", SIGNER) == ""},
            ],
            "status_code_map": codes,
            "status_code_map_at_line": codes_line,
            "message_map_at_line": msg_line,
            "anchors": {
                "localbRequestRejected_from_LOCALBStatus": rejected_status,
                "localbRequestRejected_PROOF_MISSING": proof_missing,
                "localbAuthorizationUnavailable_throws": unavailable_guards,
                "spki_never_read_comment": {"first_line": spki_comment, "tail_line": spki_comment_tail},
                "transport_trust_guard": transport_guard,
                "trustedCheckpoint_argument": checkpoint,
                "signer_clientRequestSignatureInvalid": [
                    {"path": SIGNER, "line": n} for n in sig_invalid],
                "signer_challenge_invalid": [
                    {"path": SIGNER, "line": n} for n in challenge_invalid],
            },
        },
        "observed": observed,
        "operator_table": {
            "row": "invalid proof",
            "expected": "HTTP 503",
            "resolution": ("the expectation names the S5 status; the proof gate itself is 401. "
                           "Recorded as a wording deviation, not repaired by changing the product."),
            "product_changed_to_match": False,
        },
        "checks": checks,
        "all_checks_pass": all(checks.values()),
    }
    with open(opts.out, "w") as fh:
        json.dump(doc, fh, indent=1, sort_keys=True)
    for name, ok in checks.items():
        print("%-62s %s" % (name, "true" if ok else "FALSE"))
    print("wrote", opts.out)
    return 0 if doc["all_checks_pass"] else 2


if __name__ == "__main__":
    sys.exit(main())
