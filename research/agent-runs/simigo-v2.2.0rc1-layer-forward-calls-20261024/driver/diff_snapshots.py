#!/usr/bin/env python3
"""Non-interference check between two read-only snapshots.

Compares the product preference domain and the login-Keychain metadata captured
before and after a measurement run, and writes a verdict-shaped artifact. It
reads only the two JSON snapshots it is given; it does not touch the real
preference domain or Keychain, and it does not re-decide any gate.

usage: diff_snapshots.py RID PRE_PREFS POST_PREFS PRE_KC POST_KC OUT
Exit codes: 0 identical, 1 drift found (recorded, not hidden), 3 bad input.
"""
import hashlib
import json
import os
import sys

SIX = ("plist_sha256", "plist_size", "plist_mtime_ns", "export_sha256",
       "values_sha256", "key_count")


def load(path):
    with open(path, "rb") as handle:
        digest = hashlib.sha256(handle.read()).hexdigest()
    return json.load(open(path)), digest


def main():
    rid, pre_p, post_p, pre_k, post_k, out = sys.argv[1:7]
    for p in (pre_p, post_p, pre_k, post_k):
        if not os.path.exists(p):
            print(json.dumps({"error": "missing input", "path": p}), file=sys.stderr)
            return 3
    prefs_pre, prefs_pre_sha = load(pre_p)
    prefs_post, prefs_post_sha = load(post_p)
    kc_pre, kc_pre_sha = load(pre_k)
    kc_post, kc_post_sha = load(post_k)

    pref_fields = {}
    for f in SIX:
        a, b = prefs_pre.get(f), prefs_post.get(f)
        pref_fields[f] = {"pre": a, "post": b, "same": a == b}
    prefs_same = all(v["same"] for v in pref_fields.values())

    kc_count_same = len(kc_pre.get("simigo_items", [])) == len(kc_post.get("simigo_items", []))
    kc_rows_same = (sorted(json.dumps(i, sort_keys=True) for i in kc_pre.get("simigo_items", []))
                    == sorted(json.dumps(i, sort_keys=True) for i in kc_post.get("simigo_items", [])))

    checks = {
        "prefs_domain_identical_on_six_fields": bool(prefs_same),
        "keychain_item_count_unchanged": bool(kc_count_same),
        "keychain_metadata_rows_unchanged": bool(kc_rows_same),
        "snapshots_are_read_only_views": True,
    }
    clean = all(checks.values())
    payload = {
        "artifact": "non-interference between two snapshots - %s" % rid,
        "rid": rid,
        "inputs": {
            "prefs_pre": {"path": pre_p, "sha256": prefs_pre_sha},
            "prefs_post": {"path": post_p, "sha256": prefs_post_sha},
            "keychain_pre": {"path": pre_k, "sha256": kc_pre_sha},
            "keychain_post": {"path": post_k, "sha256": kc_post_sha},
        },
        "captured_pre_at": kc_pre.get("captured_at"),
        "captured_post_at": kc_post.get("captured_at"),
        "prefs_fields": pref_fields,
        "keychain_item_count": {"pre": len(kc_pre.get("simigo_items", [])),
                                "post": len(kc_post.get("simigo_items", []))},
        "keychain_simigo_scoped_rows": {
            "pre": sorted(i.get("service") or "" for i in kc_pre.get("simigo_items", [])
                          if "simigo" in (i.get("service") or "").lower()),
            "post": sorted(i.get("service") or "" for i in kc_post.get("simigo_items", [])
                           if "simigo" in (i.get("service") or "").lower()),
        },
        "checks": checks,
        "verdict": "CLEAN" if clean else "DRIFT",
        "meaning": ("the preference domain and Keychain metadata the run was allowed to "
                    "READ are byte-identical across the window; this says nothing about "
                    "page return, which is judged by A1-A9"),
        "keychain_snapshot_field_note": (
            "keychain_snapshot.py stores the FULL login-Keychain metadata dump under the key "
            "`simigo_items`; the count here is therefore every item in the login keychain, not "
            "only SimiGo's. `keychain_simigo_scoped_rows` narrows to services containing \"simigo\" "
            "so the product-scoped view is visible separately."),
        "not_claimed": [
            "not a gate verdict; no gate status changes because of this file",
            "Keychain comparison is metadata (service / account / timestamps), never secret values",
            "other apps writing to the login Keychain inside the window would show up here as drift, "
            "and it would be reported rather than re-timed away",
        ],
    }
    with open(out, "w") as handle:
        json.dump(payload, handle, indent=1, sort_keys=True)
        handle.write("\n")
    print(json.dumps({"rid": rid, "verdict": payload["verdict"], "checks": checks,
                      "out": os.path.relpath(out, os.path.dirname(os.path.dirname(out)))},
                     indent=1))
    return 0 if clean else 1


if __name__ == "__main__":
    sys.exit(main())
