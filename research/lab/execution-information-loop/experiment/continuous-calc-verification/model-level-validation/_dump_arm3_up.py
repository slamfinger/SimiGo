import sqlite3
db = sqlite3.connect(".carrier-arm3.sqlite")
sid = "settlement:U_upstream"
for row in db.execute(
    """SELECT de.append_order, de.revision, de.reason, oc.content
       FROM dependency_entries de JOIN is_objects oc ON de.content_address = oc.object_id
       WHERE de.dependency_id=? ORDER BY de.append_order""", (sid,)):
    content = row[3]
    # settle INVALID/rev2 vs SETTLED/rev3 differ in state field; show first 90 chars
    snippet = content.decode("utf-8","replace") if isinstance(content, (bytes,bytearray)) else str(content)
    state_pos = snippet.find('"state"')
    val_pos = snippet.find('A->h')
    print(f"op={row[0]} rev={row[1]} reason={row[2]!r:24} state={snippet[state_pos+7:state_pos+15] if state_pos>=0 else '?':8} tail={'A->'+snippet[val_pos+2:val_pos+10] if val_pos>=0 else '?'}")
db.close()
