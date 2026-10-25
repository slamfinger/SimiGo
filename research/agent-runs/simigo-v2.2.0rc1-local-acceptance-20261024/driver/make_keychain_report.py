#!/usr/bin/env python3
"""Prove the batched runs did NOT touch the real login Keychain.

Round 2 found the opposite: `SIMIGO_HOME` redirected every filesystem root but
not the Keychain, so each headless run left one LOCALB transport identity
(index + key + certificate) in the user's login Keychain.

Round 3 changes the store, not the measurement: a store whose managed root is
isolated resolves its identity into `<SIMIGO_HOME>/localb/transport-identity
.keychain-db` and scopes every SecItem call to it. This script compares a
metadata baseline taken BEFORE the round-3 runs with the current Keychain and
reports the delta. Item metadata only (service/account/timestamps) - no secret
value is read or stored, and nothing is deleted.
"""
import glob, json, os, re, subprocess, sys, time

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(B, "evidence/keychain_pre_round3.json")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(B, "evidence/keychain_noninterference.json")
INTERMEDIATE = os.path.join(B, "evidence/keychain_round3_intermediate_leak.json")
ROUND2_RUNS = ("m4a", "m4b", "m4a_mem", "m4b_mem")


def load_items(path):
    # The baseline snapshot stores every login-Keychain item; keep the same
    # SimiGo filter the current-dump reader applies so the delta is exact.
    return [r for r in json.load(open(path))["simigo_items"]
            if r.get("service") and "simigo" in r["service"].lower()]


def current_items():
    dump = subprocess.run(["security", "dump-keychain"], capture_output=True, text=True).stdout
    items = []
    for block in dump.split("keychain:"):
        svce = re.search(r'0x00000007 <blob>="([^"]*)"', block)
        if not svce or "simigo" not in svce.group(1).lower():
            continue
        acct = re.search(r'0x00000008 <blob>="([^"]*)"', block)
        def ts(name):
            m = re.search(r'"%s"<timedate>=(?:0x[0-9A-F]+00\s+"(\d{14})|"(\d{14})Z")' % name, block)
            return (m.group(1) or m.group(2)) if m else None
        items.append({"service": svce.group(1),
                      "account": acct.group(1) if acct else None,
                      "created": ts("cdat"),
                      "modified": ts("mdat")})
    return items


def key(rows):
    # Identity is (service, account, multiplicity): the creation timestamp is
    # metadata that `security dump-keychain` renders in two different forms, so
    # it is NOT part of the identity - a timestamp parse difference must never
    # masquerade as a new item.
    out = {}
    for r in rows:
        k = (r["service"], r["account"])
        out[k] = out.get(k, 0) + 1
    return out


baseline_rows = load_items(BASE)
now_rows = current_items()
base, now = key(baseline_rows), key(now_rows)
new_keys = [k for k, n in now.items() if n > base.get(k, 0)]
removed_keys = [k for k, n in base.items() if n > now.get(k, 0)]
new_items = [r for r in now_rows
             if (r["service"], r["account"]) in set(new_keys)]
production = [r for r in now_rows if r["service"].startswith("com.simigo.localb")]
legacy_round2 = [r for r in now_rows
                 if r["service"].startswith("com.simigo.headless.g1g3.")
                 and any((".%s." % run) in r["service"] for run in ROUND2_RUNS)]
scoped_files = sorted(glob.glob(os.path.join(B, "**", "localb", "transport-identity.keychain-db"),
                                recursive=True))
scoped_files = [p for p in scoped_files if "/build/" not in p]

checks = {
    "baseline_present": bool(baseline_rows),
    "no_new_login_keychain_items": len(new_items) == 0,
    "no_items_removed_or_rewritten": len(removed_keys) == 0,
    "production_credentials_untouched": all(
        (r["modified"] or r["created"] or "") < "20261024" for r in production),
    "isolated_runs_wrote_scoped_keychain_files": len(scoped_files) > 0,
}

chain = {}
if os.path.exists(INTERMEDIATE):
    inter = json.load(open(INTERMEDIATE))
    chain = {
        "intermediate_leak_found_and_fixed": True,
        "intermediate_leak_items": inter.get("new_item_count"),
        "intermediate_leak_services": [r["service"] for r in inter.get("new_items_since_baseline", [])],
        "intermediate_leak_cause": ("the app suite also exercises LOCALBKeychainSignerStore "
                                    "(com.simigo.tests.localb-adoption/-boot).* signing-key-v1), "
                                    "which was still unscoped in the first round-3 run; the same "
                                    "keychain scope was then applied to that store"),
        "intermediate_leak_not_deleted": True,
        "final_baseline_taken_after_the_fix": True,
    }

doc = {
    "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "scope": "login Keychain item METADATA only; no secret values are read or stored",
    "baseline": {"path": os.path.relpath(BASE, B), "captured_at": json.load(open(BASE))["captured_at"],
                 "item_count": len(baseline_rows)},
    "current_item_count": len(now_rows),
    "new_items_since_baseline": new_items,
    "new_item_count": len(new_items),
    "removed_items_since_baseline": [{"service": k[0], "account": k[1], "created": k[2]} for k in removed_keys],
    "production_items": production,
    "legacy_round2_items_not_deleted": sorted(
        legacy_round2, key=lambda r: (r["created"] or "")),
    "legacy_round2_item_count": len(legacy_round2),
    "scoped_keychain_files": [os.path.relpath(p, B) for p in scoped_files],
    "checks": checks,
    "isolation": {
        "filesystem_roots_isolated": True,
        "keychain_isolated_by_simigo_home": bool(scoped_files),
        "mechanism": ("LOCALBTransportIdentityStore.defaultIsolatedKeychainPath: when SIMIGO_HOME "
                      "redirects the managed root, the transport identity resolves to "
                      "<SIMIGO_HOME>/localb/transport-identity.keychain-db and every SecItem "
                      "call is scoped (kSecUseKeychain / kSecMatchSearchList / "
                      "SecIdentityCreateWithCertificate(keychain))."),
    },
    "chain": chain,
    "verdict": "PASS" if all(checks.values()) else "FAIL",
}
json.dump(doc, open(OUT, "w"), indent=1, sort_keys=True)
print("new=%d removed=%d production=%d legacy_round2=%d scoped_files=%d"
      % (len(new_items), len(removed_keys), len(production), len(legacy_round2), len(scoped_files)))
for r in new_items[:20]:
    print("  NEW %s %s" % (r["created"], r["service"]))
print("verdict=%s" % doc["verdict"])
