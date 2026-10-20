#!/usr/bin/env python3
"""Cross-check: does arm4's 'recomputed' proxy set actually match the settle_now values?
results.md claims carrier_proxy_recompute for arm4 equals {A,B,C,D}. Verify against DB."""
import sqlite3, json

def settle_now(dbpath):
    """Read the FINAL (max append_order) settle value per item from DB."""
    db = sqlite3.connect(dbpath)
    out = {}
    for item in ("A","B","C","D","E"):
        row = db.execute(
            """SELECT oc.content FROM dependency_entries de JOIN is_objects oc
                ON de.content_address=oc.object_id
               WHERE de.dependency_id='settlement:%s'
                 AND de.append_order=(SELECT max(append_order) FROM dependency_entries
                                      WHERE dependency_id='settlement:%s')""" % (item,item)).fetchone()
        if row:
            c = json.loads(row[0].decode("utf-8","replace"))
            out[item] = {
                "state": c.get("state"),
                "result_value": (c.get("result") or {}).get("value"),
            }
    db.close()
    return out

d = settle_now(".carrier-arm4.sqlite")
print("=== arm4 FINAL settle state per item (from DB) ===")
for k in ("A","B","C","D","E"):
    v = d[k]["result_value"]
    if isinstance(v, list) and len(v) >= 2:
        text = v[1] if isinstance(v[1], str) else (v[0].get("value") if isinstance(v[0],dict) else "?")
    else:
        text = "?"
    print(f"  {k}: state={d[k]['state']:8} value_text={text}")
