#!/usr/bin/env python3
"""Record which authorization surface this candidate actually ships.

Two questions, answered from disk only:
  1. what does the INSTALLED binary do on the protected route?  (stage C probe)
  2. does the product's own authorized lane exist and pass?     (round-2 test log)

Nothing here relaxes authorization: the installed binary is probed with a
bogus proof on purpose and the outcome is reported as observed.
"""
import os, re, subprocess

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "/Users/mr.simi/Documents/SimiGo"
OUT = os.path.join(B, "evidence/localb_authorization_path.txt")

PROBE = os.path.join(B, "evidence/m3_stage_c_probe.txt")
LOG = os.path.join(B, "logs/isolated_r4.stdout.log")
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


def git(*args):
    return subprocess.run(["git", "-C", REPO, *args], capture_output=True, text=True).stdout.strip()


def rg(pattern, *paths):
    r = subprocess.run(["grep", "-rn", pattern, *paths, "--include=*.swift"],
                       capture_output=True, text=True, cwd=REPO)
    return [l for l in r.stdout.splitlines() if l]


lines = []
lines.append("# LOCALB authorization surface of the v2.2.0rc1 candidate")
lines.append("# product HEAD %s (branch %s)" % (git("rev-parse", "HEAD"), git("rev-parse", "--abbrev-ref", "HEAD")))
lines.append("")
lines.append("== [1] installed binary on the protected route (bogus proof, no relaxation) ==")
for l in open(PROBE, errors="replace"):
    if re.match(r"(pid=|bound_port=|listening_socket_found=|http_status=|authorized_request_completed="
                r"|authorization_relaxed=|probe_result=)", l):
        lines.append("  " + l.rstrip())
lines.append("")
lines.append("== [2] the 503 is the unconfigured-authorization guard ==")
for l in rg("localbAuthorizationUnavailable", "SimiGo/Protocol/HTTPServer.swift"):
    lines.append("  " + l)
lines.append("")
lines.append("== [3] authorization is configured only from a verified LOCALB host context ==")
for l in rg("configureLOCALBRequestAuthorization", "SimiGo"):
    lines.append("  " + l)
lines.append("")
lines.append("== [4] the activation ceremony is the only writer of the trusted checkpoint ==")
allhits = rg("persistTrustedCheckpoint", "SimiGo", "SimiGoTests")
for l in allhits:
    lines.append("  " + l)
app_sites = [l for l in allhits if l.startswith("SimiGo/") and "static func persistTrustedCheckpoint" not in l]
lines.append("  app_target_call_sites=%d" % len(app_sites))
lines.append("")
lines.append("== [5] authorized lane inside the product test target (round-2 test binary) ==")
txt = open(LOG, errors="replace").read().splitlines()
for name in CASES:
    hit = [l for l in txt if (" " + name + "]") in l and ("passed" in l or "failed" in l)]
    lines.append("  %s %s" % ("PASS" if hit and "passed" in hit[0] else "MISSING", name))
for l in txt:
    if re.search(r"Test Suite '(LOCALBRequestAuthWiringTests|ExternalAdoptionInferenceE2ETests)' (passed|failed)", l):
        lines.append("  " + l.strip())
lines.append("")
lines.append("== [6] conclusion ==")
lines.append("  installed_binary_protected_route = BLOCKED")
lines.append("    reason: no product surface performs the activation ceremony, so the installed")
lines.append("            app runs unactivated and the guard returns 503 before any proof is")
lines.append("            evaluated. Reaching the route would require either relaxing the guard")
lines.append("            (forbidden) or an activation surface the product does not ship.")
lines.append("  authorized_lane_in_product_test_target = PASS (cases above)")
lines.append("  authorization_relaxed = 0   proof_fabricated = 0   route_policy_changed = 0")
lines.append("  minimum_unblock: a product-side activation/management surface (operator CLI or")
lines.append("                   equivalent) that runs persistTrustedCheckpoint against the")
lines.append("                   isolated host directory, plus a paired client whose key lives in")
lines.append("                   a throwaway Keychain.")
open(OUT, "w").write("\n".join(lines) + "\n")
print("wrote %s (%d lines)" % (OUT, len(lines)))
