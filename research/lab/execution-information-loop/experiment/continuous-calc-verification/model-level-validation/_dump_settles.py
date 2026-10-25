#!/usr/bin/env python3
"""Dump the real settle-state sequence from carrier sqlite is_objects/dependency_entries.
This reconstructs what states each settlement revision carried — P0's "real status sequence"."""
import sqlite3, sys, json

def payload_of(dbpath, dependency_id):
    """Fetch content of each revision for a settlement via join to is_objects."""
    db = sqlite3.connect(dbpath)
    cur = db.cursor()
    rows = cur.execute(
        """SELECT de.append_order, de.dependency_id, de.revision, de.reason, oc.content
           FROM dependency_entries de
           JOIN is_objects oc ON de.content_address = oc.object_id
           WHERE de.dependency_id LIKE ? || '%'
           ORDER BY de.append_order""",
        (dependency_id,)).fetchall()
    db.close()
    return rows

def decode(content_blob):
    """is_objects content is stored via carrier; try to show the settle value."""
    raw = bytes(content_blob)
    # carrier stores JSON-ish; attempt json decode
    try:
        obj = json.loads(raw.decode("utf-8", "replace"))
        if isinstance(obj, dict):
            return json.dumps(obj.get("value", obj), ensure_ascii=False)
        return raw.decode("utf-8", "replace")[:120]
    except Exception:
        return raw.decode("utf-8", "replace")[:120]

dbpath = sys.argv[1]
print(f"=== {dbpath}")
sets = ["settlement:U_upstream", "settlement:U_parse", "settlement:U_summarize"] if dbpath.endswith("arm3") else ["settlement:A", "settlement:B", "settlement:C", "settlement:D", "settlement:E"]
for sid in sets:
    rows = payload_of(dbpath, sid)
    if not rows:
        print(f"  (no settle revisions for {sid})")
        continue
    print(f"  -- {sid} --")
    for order, dep_id, rev, reason, content in rows:
        print(f"     op={order} rev={rev} reason={reason!r:24} value={decode(content)!r}")
