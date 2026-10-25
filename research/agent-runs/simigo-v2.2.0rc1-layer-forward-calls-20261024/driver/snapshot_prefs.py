#!/usr/bin/env python3
"""Read-only snapshot of the product's real preference domain.

The Service/HTTP facade leg is only allowed to touch this domain by *reading*
it. Two independent views are recorded so "nothing was written" is measured,
not assumed:

  * the on-disk plist (`~/Library/Preferences/<domain>.plist`): bytes, size,
    mtime;
  * the authoritative value set as cfprefsd serialises it (`defaults export`),
    digested as canonical JSON so key order cannot fake a difference.

usage: snapshot_prefs.py OUT.json
"""
import hashlib
import json
import os
import plistlib
import subprocess
import sys

DOMAIN = "SwiftUI.SimiGo"
TRACKED = ("SelectedModelPath", "MLXModelPath", "LLaMAModelPath",
           "BackendSelection", "CloudModel")


def sha_bytes(data):
    return hashlib.sha256(data).hexdigest()


def main():
    out = sys.argv[1]
    plist = os.path.expanduser("~/Library/Preferences/%s.plist" % DOMAIN)
    doc = {"domain": DOMAIN, "plist_path": plist,
           "plist_exists": os.path.exists(plist)}
    if doc["plist_exists"]:
        with open(plist, "rb") as fh:
            raw = fh.read()
        stat = os.stat(plist)
        doc["plist_sha256"] = sha_bytes(raw)
        doc["plist_size"] = len(raw)
        doc["plist_mtime_ns"] = stat.st_mtime_ns

    proc = subprocess.run(["defaults", "export", DOMAIN, "-"],
                          capture_output=True)
    doc["export_rc"] = proc.returncode
    doc["export_bytes"] = len(proc.stdout)
    doc["export_sha256"] = sha_bytes(proc.stdout)
    values = None
    if proc.returncode == 0 and proc.stdout:
        try:
            values = plistlib.loads(proc.stdout)
        except Exception as exc:  # noqa: BLE001 - a parse failure is a result
            doc["export_parse_error"] = repr(exc)
    if isinstance(values, dict):
        doc["key_count"] = len(values)
        doc["values_sha256"] = sha_bytes(
            json.dumps(values, sort_keys=True, default=str).encode())
        doc["tracked"] = {}
        for key in TRACKED:
            raw_value = values.get(key)
            if isinstance(raw_value, bytes):
                raw_value = "<%d bytes>" % len(raw_value)
            doc["tracked"][key] = raw_value
    with open(out, "w") as fh:
        json.dump(doc, fh, indent=1, sort_keys=True)
    print(json.dumps({k: doc.get(k) for k in (
        "domain", "plist_size", "plist_sha256", "export_sha256",
        "values_sha256", "key_count")}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
