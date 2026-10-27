#!/usr/bin/env python3
"""Goal step 4, injection #1 (dependency change) replayed on the installed
product's own HTTP routes with the real model.

Narrow by design: only the dedicated experiment root is re-registered, and the
work-category full reconcile (which wedged the HTTP service on the main thread
earlier today, see is-wedge-mainthread-20261026.txt) is NOT called. The
experiment root is left self-consistent: the appended byte is reverted and the
root re-settled, so disk digest == settled digest again.
"""
import hashlib
import json
import pathlib
import sqlite3
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = "http://127.0.0.1:8000"
DB = pathlib.Path.home() / ".simigo" / "simigo.sqlite3"
TRACE = pathlib.Path.home() / ".simigo" / "logs" / "native_mlx_trace.log"
EXP = pathlib.Path(
    "/Users/mr.simi/Documents/SimiGo/research/agent-runs"
    "/simigo-es-is-realmodel-20261026")
ROOT = EXP / "dep-root"
ALPHA = "marker_alpha_7Q.txt"
BETA = "marker_beta_Z9.txt"
ALPHA_V1 = (
    "阿尔法-7Q 施工记录：旋挖钻机在砂层成孔需加厚泥浆，"
    "冲击钻适用硬岩，回旋钻适合黏土。结论编号 ALPHA-7Q-ONE。\n")
ALPHA_EDIT = "补充：砂层厚度实测由 3.2m 更正为 5.6m，泥浆指标需重新核定。\n"
BETA_KEEP = (ROOT / BETA).read_text(encoding="utf-8")


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


def dep(root_id, rel):
    return http("GET", "/v1/simigo/is/dependency?id=" + urllib.parse.quote(
        f"file:{root_id}/{rel}", safe=":"))


def fil(root_id, rel):
    return http("GET", "/v1/simigo/is/file?root_id=" + root_id + "&path="
                + urllib.parse.quote(rel, safe=""))


def turn(session, question, max_tokens=64):
    st, c = http("POST", "/v1/chat/completions", {
        "model": "simigo", "session_id": session, "stream": False,
        "max_tokens": max_tokens,
        "messages": [{"role": "user", "content": question}]})
    choices = c.get("choices") or [{}]
    return {
        "http": st, "answer": (choices[0].get("message") or {}).get(
            "content", "")[:220], "error": c.get("error"),
        "usage": c.get("usage"),
    }


def trace_lines():
    if not TRACE.exists():
        return []
    return TRACE.read_text(encoding="utf-8", errors="replace").splitlines()


ALPHA_Q = "阿尔法-7Q 记录里三种钻机各适用什么地层？一句话。"
ALPHA_NEW_Q = "阿尔法-7Q 记录里砂层实测厚度是多少？一句话。"

out = {"started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "steps": {}}
trace_start = len(trace_lines())

# 0. re-register the experiment root with the ORIGINAL (v1) alpha bytes so the
#    baseline is exactly what the earlier probes settled.
(ROOT / ALPHA).write_text(ALPHA_V1, encoding="utf-8")
st, reg = http("PUT", "/v1/simigo/roots", {"path": str(ROOT)})
root_id = reg.get("root_id", "?")
out["steps"]["baseline_register"] = {"http": st, "body": reg}
out["steps"]["baseline_alpha_sha"] = hashlib.sha256(
    (ROOT / ALPHA).read_bytes()).hexdigest()
out["steps"]["baseline_dependency"] = {
    "alpha": dep(root_id, ALPHA), "beta": dep(root_id, BETA)}
out["steps"]["baseline_file"] = {"alpha": fil(root_id, ALPHA)}

# 1. baseline real-model turn that must consume alpha's settled content
sess = "e4b-" + time.strftime("%H%M%S")
out["steps"]["chat_before"] = turn(sess, ALPHA_Q)
out["steps"]["retrieval_before"] = q(
    "select demand_id, hit_count, status, result_object_id"
    " from retrieval_settlements order by settled_at desc limit 3")
out["steps"]["settlements_before"] = q(
    "select settlement_id, validation_status, validity from settlements"
    " order by settled_at desc limit 3")

# 2. INJECT the dependency change: append one line to alpha, re-register
(ROOT / ALPHA).write_text(ALPHA_V1 + ALPHA_EDIT, encoding="utf-8")
st2, reg2 = http("PUT", "/v1/simigo/roots", {"path": str(ROOT)})
out["steps"]["after_change_register"] = {"http": st2, "body": reg2}
out["steps"]["after_change_alpha_sha"] = hashlib.sha256(
    (ROOT / ALPHA).read_bytes()).hexdigest()
out["steps"]["after_change_dependency"] = {
    "alpha": dep(root_id, ALPHA), "beta": dep(root_id, BETA)}
out["steps"]["after_change_file"] = {
    "alpha": fil(root_id, ALPHA), "beta": fil(root_id, BETA)}
out["steps"]["after_change_settlements"] = q(
    "select settlement_id, validation_status, validity, invalidated_at"
    " from settlements order by settled_at desc limit 5")
out["steps"]["after_change_retrieval"] = q(
    "select demand_id, hit_count, status from retrieval_settlements"
    " order by settled_at desc limit 3")
out["steps"]["after_change_bindings"] = q(
    "select settlement_id, name, substr(value_digest,1,16) value_digest,"
    " source_root_id, source_file_id"
    " from settlement_bindings order by binding_id desc limit 5")

# 3. stale read: same question as the pre-change turn (must NOT return the
#    pre-change settled answer if the closure is authoritative)
out["steps"]["chat_after_change_stale_question"] = turn(sess + "-b", ALPHA_Q)
# 4. new read: the changed content carries the corrected thickness
out["steps"]["chat_after_change_new_question"] = turn(sess + "-c", ALPHA_NEW_Q)
# 5. unrelated beta record must survive
out["steps"]["chat_beta_unrelated"] = turn(sess + "-iso", "贝塔-Z9 记录讲了什么？一句话。")

# 6. restore: revert the appended line and re-settle (keeps disk == settled)
(ROOT / ALPHA).write_text(ALPHA_V1, encoding="utf-8")
st3, reg3 = http("PUT", "/v1/simigo/roots", {"path": str(ROOT)})
out["steps"]["restore_register"] = {"http": st3, "body": reg3}
out["steps"]["restore_check"] = {
    "disk_sha": hashlib.sha256((ROOT / ALPHA).read_bytes()).hexdigest(),
    "is_file": fil(root_id, ALPHA),
    "beta_bytes_untouched": (ROOT / BETA).read_text(encoding="utf-8") == BETA_KEEP,
}

window = trace_lines()[trace_start:]
KEYS = ("prefill", "promptTokens", "poolExport", "poolHit", "poolBind",
        "poolTokenExport", "poolTokenHit", "prefixDiff", "prefixMismatch",
        "RELEASED", "PROTOCOL", "reuseMiss", "cacheSave")
out["steps"]["trace_window"] = [
    ln for ln in window if any(k in ln for k in KEYS)][-60:]

out["finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
path = EXP / f"e4b-depchange-{time.strftime('%Y%m%d-%H%M%S')}.json"
path.write_text(json.dumps(out, ensure_ascii=False, indent=2))
print("WROTE", path)
for k, v in out["steps"].items():
    print("--", k, json.dumps(v, ensure_ascii=False)[:400])
