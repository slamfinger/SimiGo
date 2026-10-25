#!/usr/bin/env python3
"""Measure what this batch did to the login Keychain.

The protected-state snapshot only covers the filesystem. LOCALB transport
identities live in the Keychain instead, and `SIMIGO_HOME` does not redirect it,
so a run that calls LOCALBTransportIdentityStore.loadOrCreate() adds items to the
user's real login Keychain. This script reads item metadata (no secrets) and
separates three things:

  production items   -> the long-lived `com.simigo.localb-*` services
  batch items        -> services namespaced by OUR run ids (headless.g1g3.<run>)
  test items         -> `com.simigo.tests.*` services created by the test suites

Nothing is deleted: orphaned items are evidence, not garbage.
"""
import json, os, re, subprocess, time

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(B, "evidence/keychain_noninterference.json")
OUR_RUNS = ("m4a", "m4b", "m4a_mem", "m4b_mem")

dump = subprocess.run(["security", "dump-keychain"], capture_output=True, text=True).stdout
rows = []
for block in dump.split("keychain:"):
    svce = re.search(r'0x00000007 <blob>="([^"]*)"', block)
    if not svce or "simigo" not in svce.group(1).lower():
        continue
    def ts(name):
        m = re.search(r'"%s"<timedate>=(?:0x[0-9A-F]+00\s+"(\d{14})|"(\d{14})Z")' % name, block)
        return (m.group(1) or m.group(2)) if m else None
    rows.append({"service": svce.group(1), "created": ts("cdat"), "modified": ts("mdat")})

production = [r for r in rows if r["service"].startswith("com.simigo.localb")]
batch = [r for r in rows if r["service"].startswith("com.simigo.headless.g1g3.")
         and any((".%s." % run) in r["service"] for run in OUR_RUNS)]
tests = [r for r in rows if r["service"].startswith("com.simigo.tests.")]

doc = {
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "scope": "login Keychain item METADATA only; no secret values are read or stored",
    "total_simigo_items": len(rows),
    "production_items": production,
    "production_credentials_modified": any(
        (r["modified"] or r["created"] or "").startswith("2026102") for r in production),
    "batch_namespaced_items": sorted(batch, key=lambda r: (r["created"] or "")),
    "batch_namespaced_item_count": len(batch),
    "test_scoped_item_count": len(tests),
    "isolation": {
        "filesystem_roots_isolated": True,
        "keychain_isolated_by_simigo_home": False,
        "mechanism": ("SimiGoG1G3Entry.startIsolated builds LOCALBTransportIdentityStore("
                      "service: \"com.simigo.headless.g1g3.<SIMIGO_RUN_ID>.<uuid8>\") and calls "
                      "loadOrCreate(); the Keychain has no path scoping, so each run adds one "
                      "index item plus a key and a certificate to the login Keychain."),
        "effect": "additive only: unique per-run service, no existing credential read, rewritten or deleted",
    },
    "verdict": "FAIL",
    "verdict_reason": ("Task book: a protected location that cannot be isolated, or an out-of-bounds "
                       "write, fails the affected acceptance closed. The candidate adds Keychain items "
                       "to the real login Keychain on every headless run; production credentials "
                       "themselves are untouched."),
    "not_affected": ("Research-chain values, settlements and digests do not depend on which Keychain "
                     "service holds the transport identity; the m4/m4b results stand."),
    "minimum_unblock": ("Run headless/experiment identities in a dedicated throwaway Keychain "
                        "(security create-keychain + SecItemAdd scoping) and delete it at teardown; "
                        "have the isolated test runner do the same instead of writing "
                        "com.simigo.tests.* items into the login Keychain."),
}
json.dump(doc, open(OUT, "w"), indent=1, sort_keys=True)
print("items=%d production=%d batch=%d tests=%d" % (len(rows), len(production), len(batch), len(tests)))
for r in doc["batch_namespaced_items"]:
    print("  %s %s" % (r["created"], r["service"]))
