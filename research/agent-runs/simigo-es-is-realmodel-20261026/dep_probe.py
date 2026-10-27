#!/usr/bin/env python3
"""Goal step 4: inject a dependency change into a DEDICATED experiment work root
(never the user's real Desktop roots) and measure the invalidation closure and
whether a stale settled retrieval is reused, through the installed product's own
routes.
"""
import json
import pathlib
import sqlite3
import time
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:8000"
DB = pathlib.Path.home() / ".simigo" / "simigo.sqlite3"
EXP = pathlib.Path(
    "/Users/mr.simi/Documents/SimiGo/research/agent-runs"
    "/simigo-es-is-realmodel-20261026")
ROOT = EXP / "dep-root"
ALPHA = "marker_alpha_7Q.txt"
BETA = "marker_beta_Z9.txt"
ALPHA_BODY = (
    "阿尔法-7Q 施工记录：旋挖钻机在砂层成孔需加厚泥浆，"
    "冲击钻适用硬岩，回旋钻适合黏土。结论编号 ALPHA-7Q-ONE。\n")
ALPHA_EDIT = "补充：砂层厚度实测由 3.2m 更正为 5.6m，泥浆指标需重新核定。\n"
BETA_BODY = "贝塔-Z9 无关记录：办公区用电巡检要点，结论编号 BETA-Z9-ONE。\n"


def http(method, path, body=None, timeout=600):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        BASE + path, data=data, method=method,
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"raw": raw[:400]}


def q(sql, params=()):
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in con.execute(sql, params).fetchall()]
    finally:
        con.close()


def dep_id(root_id, rel):
    return f"file:{root_id}/{rel}"


out = {"started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "steps": {}}

ROOT.mkdir(parents=True, exist_ok=True)
(ROOT / ALPHA).write_text(ALPHA_BODY, encoding="utf-8")
(ROOT / BETA).write_text(BETA_BODY, encoding="utf-8")

# 1. register + settle the experiment root through the product route
st, reg = http("PUT", "/v1/simigo/roots", {"path": str(ROOT)})
out["steps"]["register"] = {"http": st, "body": reg}
root_id = reg.get("root_id", "?")

# 2. baseline dependency + settled file state for BOTH files
base = {}
for rel in (ALPHA, BETA):
    st, d = http("GET", "/v1/simigo/is/dependency?id=" + urllib.parse.quote(
        dep_id(root_id, rel), safe=":"))
    st2, f = http("GET", "/v1/simigo/is/file?root_id=" + root_id + "&path="
                  + urllib.parse.quote(rel, safe=""))
    base[rel] = {"dep_http": st, "dependency": d, "file_http": st2, "file": f}
out["steps"]["baseline"] = base
alpha_sha_v1 = base[ALPHA]["file"].get("content_sha256")
beta_sha_v1 = base[BETA]["file"].get("content_sha256")
out["steps"]["baseline_digests"] = {
    "alpha_v1": alpha_sha_v1, "beta_v1": beta_sha_v1,
    "on_disk_alpha": None}

# 3. one real chat turn whose retrieval must hit the experiment root, so a
#    settled record now depends on alpha's content revision
sess = "exp-dep-" + time.strftime("%H%M%S")
st, chat = http("POST", "/v1/chat/completions", {
    "model": "simigo", "session_id": sess, "stream": False, "max_tokens": 64,
    "messages": [{"role": "user",
                  "content": "阿尔法-7Q 记录里三种钻机各适用什么地层？一句话。"}]})
out["steps"]["chat_baseline"] = {
    "http": st,
    "usage": chat.get("usage"),
    "content_len": len((chat.get("choices") or [{}])[0]
                       .get("message", {}).get("content", ""))}

retr_before = q(
    "select demand_id, substr(inputs_digest,1,120) inputs, hit_count, status,"
    " result_object_id from retrieval_settlements order by settled_at desc limit 3")
out["steps"]["retrieval_before"] = retr_before
settle_before = q(
    "select settlement_id, validation_status, validity, payload_object_id"
    " from settlements order by settled_at desc limit 3")
out["steps"]["settlements_before"] = settle_before

# 4. inject the dependency change (append to alpha only) and re-settle
(ROOT / ALPHA).write_text(ALPHA_BODY + ALPHA_EDIT, encoding="utf-8")
st, reg2 = http("PUT", "/v1/simigo/roots", {"path": str(ROOT)})
out["steps"]["after_change_register"] = {"http": st, "body": reg2}
st, rec = http("POST", "/v1/simigo/is/reconcile",
               {"category": "work", "max_age_seconds": 0})
out["steps"]["after_change_reconcile"] = {"http": st, "body": rec}

after = {}
for rel in (ALPHA, BETA):
    st, d = http("GET", "/v1/simigo/is/dependency?id=" + urllib.parse.quote(
        dep_id(root_id, rel), safe=":"))
    st2, f = http("GET", "/v1/simigo/is/file?root_id=" + root_id + "&path="
                  + urllib.parse.quote(rel, safe=""))
    after[rel] = {"dep_http": st, "dependency": d,
                  "file_http": st2, "file": f}
out["steps"]["after_change"] = after

sha = __import__("hashlib").sha256
out["steps"]["digest_check"] = {
    "alpha_v1_expected_new": sha((ALPHA_BODY + ALPHA_EDIT).encode()).hexdigest(),
    "beta_unchanged": sha(BETA_BODY.encode()).hexdigest() == beta_sha_v1,
}
out["steps"]["after_change_file_contents"] = q(
    "select relative_path, content_sha256, status, object_id from file_contents"
    " where root_id=? order by settled_at desc limit 6", (root_id,))
out["steps"]["after_change_retrieval"] = q(
    "select demand_id, substr(inputs_digest,1,120) inputs, status"
    " from retrieval_settlements where inputs_digest like ? or query like ?"
    " order by settled_at desc limit 5",
    (f"%{alpha_sha_v1}%", "%阿尔法-7Q%"))
out["steps"]["after_change_settlements"] = q(
    "select settlement_id, validation_status, validity, invalidated_at"
    " from settlements order by settled_at desc limit 5")

# 5. does a follow-up query reuse the stale settled retrieval?
st, chat2 = http("POST", "/v1/chat/completions", {
    "model": "simigo", "session_id": sess + "-b", "stream": False,
    "max_tokens": 64,
    "messages": [{"role": "user",
                  "content": "阿尔法-7Q 记录里三种钻机各适用什么地层？一句话。"}]})
out["steps"]["chat_after_change"] = {
    "http": st, "usage": chat2.get("usage"),
    "content": (chat2.get("choices") or [{}])[0]
               .get("message", {}).get("content", "")[:220]}
out["steps"]["retrieval_after_query2"] = q(
    "select demand_id, substr(inputs_digest,1,160) inputs, hit_count, status"
    " from retrieval_settlements where query like ? order by settled_at desc"
    " limit 4", ("%阿尔法-7Q%",))

# 6. unrelated beta-dependent record must survive the closure
st, chat3 = http("POST", "/v1/chat/completions", {
    "model": "simigo", "session_id": sess + "-iso", "stream": False,
    "max_tokens": 64,
    "messages": [{"role": "user",
                  "content": "贝塔-Z9 记录讲了什么？一句话。"}]})
out["steps"]["chat_beta_unrelated"] = {
    "http": st, "usage": chat3.get("usage"),
    "content": (chat3.get("choices") or [{}])[0]
               .get("message", {}).get("content", "")[:220]}
out["steps"]["beta_dependency_final"] = http(
    "GET", "/v1/simigo/is/dependency?id=" + urllib.parse.quote(
        dep_id(root_id, BETA), safe=":"))

out["finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
path = EXP / f"dep-{time.strftime('%Y%m%d-%H%M%S')}.json"
path.write_text(json.dumps(out, ensure_ascii=False, indent=2))
print("WROTE", path)
for k, v in out["steps"].items():
    print("--", k, json.dumps(v, ensure_ascii=False)[:300])
