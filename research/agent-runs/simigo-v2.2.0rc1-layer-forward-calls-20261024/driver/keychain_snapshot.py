#!/usr/bin/env python3
"""Snapshot login-Keychain item METADATA (no secrets) for a later delta.

`security dump-keychain` only exposes attributes here: service, account class and
creation/modification timestamps. Nothing secret is read or stored.

  keychain_snapshot.py <out.json>
"""
import json, os, re, subprocess, sys, time

out_path = sys.argv[1]
dump = subprocess.run(["security", "dump-keychain"], capture_output=True, text=True).stdout
items = []
for block in dump.split("keychain:"):
    svce = re.search(r'0x00000007 <blob>="([^"]*)"', block)
    acct = re.search(r'0x00000008 <blob>="([^"]*)"', block)
    if not svce:
        continue
    def ts(name):
        m = re.search(r'"%s"<timedate>=(?:0x[0-9A-F]+00\s+"(\d{14})|"(\d{14})Z")' % name, block)
        return (m.group(1) or m.group(2)) if m else None
    items.append({
        "service": svce.group(1),
        "account": acct.group(1) if acct else None,
        "created": ts("cdat"),
        "modified": ts("mdat"),
    })
doc = {
    "captured_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    "scope": "login Keychain item METADATA only; no secret values are read or stored",
    "simigo_items": items,
}
os.makedirs(os.path.dirname(out_path), exist_ok=True)
json.dump(doc, open(out_path, "w"), indent=1, sort_keys=True)
print("snapshot items=%d out=%s" % (len(items), out_path))
