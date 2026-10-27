#!/usr/bin/env python3
"""Rejection-boundary + KV-lineage probes against the installed SimiGo product entry."""
import json, os, sqlite3, subprocess, time, urllib.request, glob

BASE = "http://127.0.0.1:8000"
HOME = os.path.expanduser("~")
DB = f"{HOME}/.simigo/simigo.sqlite3"
TRACE = f"{HOME}/.simigo/logs/native_mlx_trace.log"
OUT = os.path.dirname(os.path.abspath(__file__))
ANCHOR = "chat-5809b828-f2a1-4177-8573-c3499b5f7fcf"
MODEL = "peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX"
R = {}


def post(path, payload, timeout=600):
    req = urllib.request.Request(BASE + path, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return int(r.status), json.loads(r.read().decode()), round(time.time() - t0, 2)
    except urllib.error.HTTPError as e:
        b = e.read().decode()
        try:
            return e.code, json.loads(b), round(time.time() - t0, 2)
        except Exception:
            return e.code, {"raw": b[:600]}, round(time.time() - t0, 2)
    except Exception as e:
        return -1, {"error": repr(e)}, round(time.time() - t0, 2)


def get(path, timeout=180):
    try:
        with urllib.request.urlopen(BASE + path, timeout=timeout) as r:
            return int(r.status), json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, {"raw": e.read().decode()[:400]}
    except Exception as e:
        return -1, {"error": repr(e)}


def off():
    return os.path.getsize(TRACE)


def since(o):
    with open(TRACE, "rb") as f:
        f.seek(o)
        t = f.read().decode(errors="replace")
    return [l.strip() for l in t.splitlines()
            if any(k in l for k in ("prefill", "promptTokens", "cacheHitTokens", "mode=",
                                    "poolBind", "continuation_admitted", "arrive", "RELEASED",
                                    "contract", "refus", "reject"))]


def q(sql, args=(), ro=True):
    con = sqlite3.connect("file:%s?mode=ro" % DB, uri=True) if ro else sqlite3.connect(DB)
    con.row_factory = sqlite3.Row
    try:
        cur = con.execute(sql, args)
        return [dict(r) for r in cur.fetchall()]
    finally:
        con.close()


# ---- 0. parent settlement payload + declared contract -------------------------
con = sqlite3.connect(DB)
con.row_factory = sqlite3.Row
row = con.execute("SELECT payload,payload_object_id,contract_version,validation_status "
                  "FROM settlements WHERE settlement_id=?", (
                      q("SELECT settlement_id FROM settlements WHERE state_id=?", (ANCHOR,))[0]["settlement_id"],
                  )).fetchone()
pay = row["payload"]
if isinstance(pay, memoryview):
    pay = pay.tobytes()
try:
    R["parent_payload"] = json.loads(pay.decode())
except Exception as e:
    R["parent_payload"] = {"undecoded": str(e), "head": (pay or b"")[:200].decode(errors="replace")}
R["parent_contract_version"] = row["contract_version"]
R["parent_validation"] = row["validation_status"]
obj_id = q("SELECT object_id FROM is_objects WHERE object_id=?", (row["payload_object_id"],))
R["payload_object_indexed"] = bool(obj_id)
print("[P0] contract_version=%s validation=%s object_in_is_objects=%s" % (
    row["contract_version"], row["validation_status"], R["payload_object_indexed"]))
print("     payload keys=" + str(list(R["parent_payload"].keys())
                                 if isinstance(R["parent_payload"], dict) else "?")[:300])
print("     payload=" + json.dumps(R["parent_payload"], ensure_ascii=False)[:700])

# ---- 1. product-entry object integrity verification ---------------------------
st, body = get("/v1/simigo/is/object?id=" + row["payload_object_id"])
R["is_object_route"] = {"http": st, "keys": list(body)[:12],
                        "verified": body.get("verified"), "bytes": len(json.dumps(body))}
print("[P1] GET /v1/simigo/is/object http=%s verified=%s" % (st, body.get("verified")))

# ---- 2. missing settlement / unknown anchor ----------------------------------
o = off()
st, body, secs = post("/v1/responses", {"model": MODEL,
                                        "input": [{"role": "user", "content": "继续"}],
                                        "max_output_tokens": 40,
                                        "previous_es_state_id": "es-does-not-exist-0001",
                                        "continuation_settle": True})
R["probe_unknown_anchor"] = {"http": st, "body": body, "trace": since(o), "secs": secs}
print("[P2] unknown anchor -> http=%s %s" % (st, json.dumps(body, ensure_ascii=False)[:300]))
print("     trace=" + json.dumps(R["probe_unknown_anchor"]["trace"], ensure_ascii=False)[:400])

# ---- 3. valid anchor, recovery without re-settlement -------------------------
o = off()
st, body, secs = post("/v1/responses", {"model": MODEL,
                                        "input": [{"role": "user",
                                                   "content": "只用上一轮已结算的结论：奇数行权重之和乘以 3 等于多少？"}],
                                        "max_output_tokens": 120,
                                        "previous_es_state_id": ANCHOR})
txt = json.dumps(body, ensure_ascii=False)
R["probe_recover_no_settle"] = {"http": st, "secs": secs, "trace": since(o), "body_head": txt[:900]}
print("[P3] anchor, no settle -> http=%s secs=%s" % (st, secs))
for l in R["probe_recover_no_settle"]["trace"]:
    print("     " + l)

# ---- 4. KV lineage positive control: 2nd turn in the SAME session ------------
o = off()
st, body, secs = post("/v1/chat/completions", {
    "model": MODEL, "session_id": "exp-20261026-190528-es1", "max_tokens": 60,
    "messages": [{"role": "system", "content": "你是精确的数据核算助手。只依据给定表格作答。"},
                 {"role": "user", "content": "下面是一张表：\n" +
                  "\n".join(f"第{i}行 编号{i * 7 % 97} 权重{(i * 13) % 53} 记录{i * 911 % 10007}"
                             for i in range(1, 41)) +
                  "\n\n结论：奇数行权重之和=676。"},
                 {"role": "assistant", "content": "已核对：奇数行权重之和=676。"},
                 {"role": "user", "content": "把这个数乘以 3，只给数字。"}]})
R["probe_same_session_kv"] = {"http": st, "secs": secs, "trace": since(o),
                              "usage": body.get("usage")}
print("[P4] same-session 2nd turn (KV lineage) -> http=%s secs=%s" % (st, secs))
for l in R["probe_same_session_kv"]["trace"]:
    print("     " + l)

# ---- 5. dependency change -> invalidation closure via product reconcile ------
roots = q("SELECT * FROM roots LIMIT 5")
cols = list(roots[0].keys()) if roots else []
R["roots"] = roots
print("[P5] roots cols=" + str(cols))
target = None
for r0 in roots:
    path = r0.get("path") or r0.get("root_path") or r0.get("directory")
    if path and os.path.isdir(path):
        files = [f for f in glob.glob(path + "/**/*", recursive=True)
                 if os.path.isfile(f) and 0 < os.path.getsize(f) < 20000][:1]
        if files:
            target = (r0, path, files[0])
            break
if target:
    r0, path, f = target
    before = q("SELECT * FROM is_index_entries WHERE root_id=? ORDER BY rowid DESC LIMIT 1",
               (r0.get("root_id") or r0.get("id"),))
    orig = open(f, "rb").read()
    open(f, "ab").write(b"\n# es-is-acceptance-probe 20261026 appended\n")
    st, stat1 = get("/v1/simigo/is/status")
    st2, rec = post("/v1/simigo/is/reconcile", {})
    st3, stat2 = get("/v1/simigo/is/status?deep=1")
    R["dependency_change"] = {"file": f, "root": path,
                              "status_before": stat1, "reconcile": {"http": st2, "body": rec},
                              "status_after": stat2,
                              "index_entries_before": before}
    print("[P5] touched %s" % f)
    print("     reconcile http=%s body=%s" % (st2, json.dumps(rec, ensure_ascii=False)[:500]))
    print("     status_after=" + json.dumps(stat2, ensure_ascii=False)[:600])
    open(f, "wb").write(orig)
    st4, rec2 = post("/v1/simigo/is/reconcile", {})
    R["dependency_change"]["restore_reconcile"] = {"http": st4, "body": rec2}
    print("     restored, reconcile http=%s body=%s" % (st4, json.dumps(rec2, ensure_ascii=False)[:400]))
else:
    print("[P5] no reachable registered root file found")

with open(os.path.join(OUT, "probes-%s.json" % time.strftime("%H%M%S")), "w") as fh:
    json.dump(R, fh, ensure_ascii=False, indent=1, default=str)
print("[DONE]")
