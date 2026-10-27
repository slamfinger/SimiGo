#!/usr/bin/env python3
"""Goal step 4, injection #1 (dependency change) replayed after the source-binding
wiring, on the installed product's own HTTP routes with the real model.

Decisive readings this script exists to produce (build 26 could not):
  A. a settled retrieval carries a real file dependency edge
     (settlement_bindings.source_root_id / source_file_id NOT NULL);
  B. changing the cited file invalidates that retrieval settlement;
  C. the model turn that consumed it is invalidated transitively via
     dependency_edges, and its summary stops being citable;
  D. an unrelated settled demand keeps validity='valid';
  E. the demand-side view (retrieval_settlements.status keyed on
     bridged_settlement_id) flips with the authoritative bit, so a reader
     that keys on status alone stops advertising reuse.

The experiment root only: the work-category full reconcile that wedged the HTTP
service earlier today is never called (see is-wedge-mainthread-20261026.txt).
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

ALPHA_Q = "阿尔法-7Q 记录里三种钻机各适用什么地层？一句话。"
BETA_Q = "贝塔-Z9 记录讲了什么？一句话。"


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


def turn(session, question, max_tokens=64):
    st, c = http("POST", "/v1/chat/completions", {
        "model": "simigo", "session_id": session, "stream": False,
        "max_tokens": max_tokens,
        "messages": [{"role": "user", "content": question}]})
    choices = c.get("choices") or [{}]
    return {"http": st, "answer": (choices[0].get("message") or {}).get(
        "content", "")[:220], "error": c.get("error"), "usage": c.get("usage")}


def latest_retrieval(session_hint=None):
    """The newest IS_RETRIEVAL settlement, with its demand id."""
    return q(
        "select r.demand_id, r.bridged_settlement_id, r.hit_count, r.status,"
        " s.validity from retrieval_settlements r"
        " join settlements s on s.settlement_id=r.bridged_settlement_id"
        " order by r.settled_at desc limit 3")


def bindings_of(settlement_id):
    return q(
        "select b.settlement_id, b.name, b.value_digest, b.source_root_id,"
        " f.relative_path from settlement_bindings b"
        " left join external_files f on f.file_id=b.source_file_id"
        "  and f.root_id=b.source_root_id"
        " where b.settlement_id=?", (settlement_id,))


def advancing_turn(retrieval_settlement_id):
    return q(
        "select a.settlement_id, a.state_id from information_advancements a"
        " where a.retrieval_settlement_id=?", (retrieval_settlement_id,))


def validity(settlement_id):
    rows = q("select validity, invalidated_at from settlements"
             " where settlement_id=?", (settlement_id,))
    return rows[0] if rows else None


def demand_status(settlement_id):
    """The demand-side view of the same settlement. It has to agree with
    settlements.validity, otherwise a reader keyed on status alone still
    advertises the invalidated demand as reusable."""
    rows = q("select status from retrieval_settlements"
             " where bridged_settlement_id=?", (settlement_id,))
    return rows[0]["status"] if rows else None


def citable(settlement_id):
    rows = q("select count(*) c from settlement_summaries m"
             " join settlements s on s.settlement_id=m.settlement_id"
             " where m.settlement_id=? and s.validity='valid'"
             "  and s.invalidated_at is null", (settlement_id,))
    return rows[0]["c"] if rows else None


def trace_lines():
    return TRACE.read_text(encoding="utf-8", errors="replace").splitlines() \
        if TRACE.exists() else []


out = {"started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "steps": {}}
trace_start = len(trace_lines())

# 0. baseline: alpha back to v1 bytes, re-register the experiment root only.
(ROOT / ALPHA).write_text(ALPHA_V1, encoding="utf-8")
st, reg = http("PUT", "/v1/simigo/roots", {"path": str(ROOT)})
root_id = reg.get("root_id", "?")
out["steps"]["baseline_register"] = {"http": st, "body": reg}

# 1. two real-model turns on two different files: alpha's demand must bind only
#    alpha, beta's demand must stay outside the closure.
sess = "e4c-" + time.strftime("%H%M%S")
out["steps"]["chat_alpha"] = turn(sess, ALPHA_Q)
alpha_rows = latest_retrieval()
out["steps"]["alpha_retrievals"] = alpha_rows
alpha_set = alpha_rows[0]["bridged_settlement_id"] if alpha_rows else "?"
out["steps"]["A_alpha_bindings"] = bindings_of(alpha_set)
alpha_turns = advancing_turn(alpha_set)
alpha_turn_set = alpha_turns[0]["settlement_id"] if alpha_turns else "?"
out["steps"]["alpha_advancing_turn"] = alpha_turns

out["steps"]["chat_beta"] = turn(sess + "-iso", BETA_Q)
beta_rows = latest_retrieval()
beta_set = next((r["bridged_settlement_id"] for r in beta_rows
                 if r["bridged_settlement_id"] != alpha_set), "?")
out["steps"]["beta_retrieval"] = beta_set
beta_turns = advancing_turn(beta_set)
beta_turn_set = beta_turns[0]["settlement_id"] if beta_turns else "?"

# Before the injection both demands have to read as reusable, otherwise the
# post-change flip proves nothing about the change itself.
out["steps"]["before_alpha_demand_status"] = demand_status(alpha_set)
out["steps"]["before_beta_demand_status"] = demand_status(beta_set)

# 2. INJECT the dependency change and re-register.
(ROOT / ALPHA).write_text(ALPHA_V1 + ALPHA_EDIT, encoding="utf-8")
st2, reg2 = http("PUT", "/v1/simigo/roots", {"path": str(ROOT)})
out["steps"]["after_change_register"] = {"http": st2, "body": reg2}
out["steps"]["after_change_alpha_sha"] = hashlib.sha256(
    (ROOT / ALPHA).read_bytes()).hexdigest()

out["steps"]["B_alpha_retrieval_validity"] = validity(alpha_set)
out["steps"]["C_alpha_turn_validity"] = validity(alpha_turn_set)
out["steps"]["D_beta_retrieval_validity"] = validity(beta_set)
out["steps"]["D_beta_turn_validity"] = validity(beta_turn_set)
out["steps"]["C_summary_citable_alpha_turn"] = citable(alpha_turn_set)
out["steps"]["D_summary_citable_beta_turn"] = citable(beta_turn_set)
out["steps"]["E_after_alpha_demand_status"] = demand_status(alpha_set)
out["steps"]["E_after_beta_demand_status"] = demand_status(beta_set)

# 3. the stale question must not be answered from the invalidated settlement.
out["steps"]["chat_after_change_stale_question"] = turn(sess + "-b", ALPHA_Q)
out["steps"]["after_change_new_bindings"] = bindings_of(
    latest_retrieval()[0]["bridged_settlement_id"])

# 4. restore: revert and re-settle so disk digest == settled digest again.
(ROOT / ALPHA).write_text(ALPHA_V1, encoding="utf-8")
st3, reg3 = http("PUT", "/v1/simigo/roots", {"path": str(ROOT)})
out["steps"]["restore"] = {"http": st3, "body": reg3, "disk_sha": hashlib.sha256(
    (ROOT / ALPHA).read_bytes()).hexdigest()}

KEYS = ("prefill", "promptTokens", "poolExport", "poolHit", "poolBind",
        "poolTokenExport", "poolTokenHit", "prefixDiff", "prefixMismatch",
        "RELEASED", "PROTOCOL", "reuseMiss", "cacheSave")
out["steps"]["trace_window"] = [
    ln for ln in trace_lines()[trace_start:] if any(k in ln for k in KEYS)][-40:]

out["verdict"] = {
    "A_edge_written": any(b["source_file_id"] for b in out["steps"]["A_alpha_bindings"]),
    "B_retrieval_invalidated": (out["steps"]["B_alpha_retrieval_validity"] or {}).get("validity") == "invalid",
    "C_model_turn_invalidated": (out["steps"]["C_alpha_turn_validity"] or {}).get("validity") == "invalid",
    "C_summary_not_citable": (out["steps"]["C_summary_citable_alpha_turn"] or 0) == 0,
    "D_beta_survives": (out["steps"]["D_beta_retrieval_validity"] or {}).get("validity") == "valid",
    # E is only decisive if the demand-side view was 'valid' before the
    # injection — otherwise the flip could have happened for another reason.
    "E_before_views_valid": (out["steps"]["before_alpha_demand_status"],
                             out["steps"]["before_beta_demand_status"]) == ("valid", "valid"),
    "E_alpha_demand_view_invalidated": out["steps"]["E_after_alpha_demand_status"] == "invalidated",
    "E_beta_demand_view_valid": out["steps"]["E_after_beta_demand_status"] == "valid",
}
out["finished_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
path = EXP / f"e4c-depclosure-{time.strftime('%Y%m%d-%H%M%S')}.json"
path.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")
print("WROTE", path)
for k, v in out["steps"].items():
    print("--", k, json.dumps(v, ensure_ascii=False)[:320])
print("VERDICT", json.dumps(out["verdict"], ensure_ascii=False))
