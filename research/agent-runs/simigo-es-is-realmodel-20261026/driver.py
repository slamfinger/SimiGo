#!/usr/bin/env python3
"""SimiGo ES->IS->new ES real-model two-stage experiment (product HTTP entry only).

Stage 1: POST /v1/chat/completions  -> real model computes over a long source, turn settles to IS.
Isolate: move prefix-pool + branch-checkpoints aside (old persisted KV unreachable).
Stage 2: POST /v1/responses with previous_es_state_id=<stage-1 ES> + continuation_settle=true
         -> IS admission, fresh ES, generation continues from recovered settled value.
Control: POST /v1/responses without anchor (same question, no IS) -> what the model must recompute.

Reads metrics from ~/.simigo/logs/native_mlx_trace.log and the authoritative DB.
"""
import json, os, shutil, sqlite3, subprocess, sys, time, urllib.request, hashlib

PORT = 8000
BASE = f"http://127.0.0.1:{PORT}"
HOME = os.path.expanduser("~")
DB = f"{HOME}/.simigo/simigo.sqlite3"
TRACE = f"{HOME}/.simigo/logs/native_mlx_trace.log"
OUT = os.path.dirname(os.path.abspath(__file__))
NONCE = time.strftime("%Y%m%d-%H%M%S")
ISOLATE = os.path.join(OUT, "isolated-" + NONCE)

metrics = {"nonce": NONCE, "events": []}


def log(msg):
    print(msg, flush=True)


def post(path, payload, timeout=600):
    req = urllib.request.Request(
        BASE + path, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return int(r.status), json.loads(r.read().decode()), round(time.time() - t0, 2)
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        try:
            return e.code, json.loads(body), round(time.time() - t0, 2)
        except Exception:
            return e.code, {"raw": body}, round(time.time() - t0, 2)
    except Exception as e:
        return -1, {"error": repr(e)}, round(time.time() - t0, 2)


def get(path, timeout=120):
    try:
        with urllib.request.urlopen(BASE + path, timeout=timeout) as r:
            return int(r.status), json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, {"raw": e.read().decode()[:400]}
    except Exception as e:
        return -1, {"error": repr(e)}


def trace_offset():
    return os.path.getsize(TRACE) if os.path.exists(TRACE) else 0


def trace_since(off):
    with open(TRACE, "rb") as f:
        f.seek(off)
        return f.read().decode(errors="replace")


KEYS = ("arrive", "prefill", "prefillStep", "promptTokens", "cacheHitTokens", "cacheEff",
        "mode=", "poolBind", "poolExport", "cacheSave", "continuation_admitted",
        "RELEASED", "STATE_TRANSITION", "sessionClientSplit", "poisoned", "restore", "fork")


def digest_trace(text):
    return [ln.strip() for ln in text.splitlines() if any(k in ln for k in KEYS)]


def db_rows(sql, args=()):
    con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in con.execute(sql, args).fetchall()]
    finally:
        con.close()


def src_block(n=40):
    lines = []
    for i in range(1, n + 1):
        lines.append(f"第{i}行 编号{i * 7 % 97} 权重{(i * 13) % 53} 记录{i * 911 % 10007}")
    return "\n".join(lines)


# ---------------- S0 identity ----------------
def s0_identity():
    env = {}
    env["commit"] = subprocess.run(["git", "-C", "/Users/mr.simi/Documents/SimiGo", "rev-parse", "HEAD"],
                                   capture_output=True, text=True).stdout.strip()
    dirty = subprocess.run(["git", "-C", "/Users/mr.simi/Documents/SimiGo", "status", "--porcelain"],
                           capture_output=True, text=True).stdout
    env["dirty_files"] = len([l for l in dirty.splitlines() if l.strip()])
    env["dirty_digest"] = hashlib.sha256(dirty.encode()).hexdigest()[:16]
    env["binary_sha256"] = hashlib.sha256(
        open("/Applications/SimiGo.app/Contents/MacOS/SimiGo", "rb").read()).hexdigest()
    info = json.loads(subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", "/Applications/SimiGo.app/Contents/Info.plist"],
        capture_output=True, text=True).stdout)
    env["plist"] = {k: info.get(k) for k in
                    ("CFBundleShortVersionString", "CFBundleVersion", "CFBundleIdentifier")}
    st, models = get("/v1/models")
    env["models_http"] = st
    env["model"] = models["data"][0] if models.get("data") else None
    tok = db_rows("SELECT * FROM settlement_bindings ORDER BY rowid DESC LIMIT 1")
    env["latest_binding"] = tok
    st, isstat = get("/v1/simigo/is/status")
    env["is_status_http"] = st
    env["is_status"] = isstat
    metrics["identity"] = env
    log("[S0] " + json.dumps({k: env[k] for k in
                              ("commit", "dirty_files", "dirty_digest", "binary_sha256", "plist",
                               "is_status_http")}, ensure_ascii=False))


# ---------------- S1 stage 1: real model + settle ----------------
def s1_stage1():
    src = src_block(40)
    sess = f"exp-{NONCE}-es1"
    off = trace_offset()
    payload = {
        "model": metrics["identity"]["model"]["id"],
        "session_id": sess,
        "max_tokens": 220,
        "messages": [
            {"role": "system", "content": "你是精确的数据核算助手。只依据给定表格作答。"},
            {"role": "user", "content": "下面是一张表：\n" + src +
             "\n\n请先逐行核对，再给出：编号为奇数的行的权重之和，以及记录列中出现次数最多的数的前三位数字。"
             "结论请明确写出这两个数值。"},
        ],
    }
    code, body, secs = post("/v1/chat/completions", payload)
    tr = digest_trace(trace_since(off))
    text = ""
    try:
        text = body["choices"][0]["message"]["content"]
    except Exception:
        pass
    metrics["stage1"] = {"http": code, "seconds": secs, "session": sess,
                         "usage": body.get("usage"), "answer_head": text[:400],
                         "trace": tr}
    log(f"[S1] http={code} secs={secs} usage={body.get('usage')}")
    for ln in tr:
        log("     " + ln)
    if code != 200:
        log(json.dumps(body)[:800])
    return text


def s1b_es_anchor():
    time.sleep(1.5)
    states = db_rows("SELECT state_id,parent_id,model_identity,position,lifecycle,anchor,"
                     "continuation_id FROM execution_states ORDER BY created_at DESC LIMIT 3")
    settles = db_rows("SELECT settlement_id,state_id,validation_status,validity,payload_digest,"
                      "payload_object_id,contract_version,settled_at FROM settlements "
                      "ORDER BY settled_at DESC LIMIT 3")
    binds = db_rows("SELECT * FROM settlement_bindings ORDER BY rowid DESC LIMIT 4")
    adv = db_rows("SELECT advancement_id,demand_id,state_id,settlement_id,"
                  "retrieval_settlement_id,actions_json FROM information_advancements "
                  "ORDER BY advanced_at DESC LIMIT 3")
    summ = db_rows("SELECT settlement_id,session_id,query,substr(summary,1,60) AS summary,"
                   "summary_object_id FROM settlement_summaries ORDER BY created_at DESC LIMIT 3")
    demands = db_rows("SELECT demand_id,state_id,session_id,state,retrieval_settlement_id,"
                      "input_digest FROM information_demands ORDER BY created_at DESC LIMIT 3")
    metrics["es_records"] = {"states": states, "settlements": settles, "bindings": binds,
                             "advancements": adv, "summaries": summ, "demands": demands}
    settled_ids = {s.get("state_id") for s in settles}
    anchor = next((s["state_id"] for s in states if s["state_id"] in settled_ids),
                  states[0]["state_id"] if states else None)
    metrics["anchor_state_id"] = anchor
    metrics["anchor_settlement"] = next(
        (s for s in settles if s.get("state_id") == anchor), None)
    log(f"[S1b] anchor={anchor}")
    log("      settlements=" + json.dumps(settles, ensure_ascii=False, default=str)[:600])
    log("      summaries=" + json.dumps(summ, ensure_ascii=False, default=str)[:400])
    log("      advancements=" + json.dumps(adv, ensure_ascii=False, default=str)[:300])
    log("      demands=" + json.dumps(demands, ensure_ascii=False, default=str)[:300])
    log("      bindings=" + json.dumps(binds, ensure_ascii=False, default=str)[:300])
    return anchor


# ---------------- S2 isolate old KV ----------------
def s2_isolate():
    moved = {}
    os.makedirs(ISOLATE, exist_ok=True)
    for d in ("prefix-pool", "branch-checkpoints"):
        p = f"{HOME}/.simigo/{d}"
        if os.path.isdir(p):
            dest = os.path.join(ISOLATE, d)
            shutil.move(p, dest)
            moved[d] = dest
    metrics["isolation"] = {"moved": moved, "marker": "renamed so no persisted KV/checkpoint is reachable",
                            "verified_absent": {d: not os.path.exists(f"{HOME}/.simigo/{d}")
                                                for d in moved}}
    log("[S2] isolated KV artifacts: " + json.dumps(metrics["isolation"], ensure_ascii=False))
    return moved


def s2_restore(moved):
    for d, dest in moved.items():
        if os.path.exists(dest) and not os.path.exists(f"{HOME}/.simigo/{d}"):
            shutil.move(dest, f"{HOME}/.simigo/{d}")
    log("[S2] restored KV artifacts; prefix-pool=" +
        str(os.path.isdir(f"{HOME}/.simigo/prefix-pool")) +
        " branch-checkpoints=" + str(os.path.isdir(f"{HOME}/.simigo/branch-checkpoints")))


# ---------------- S3 stage 2: IS recovery in a NEW ES ----------------
def s3_stage2(anchor):
    q = ("只用上一轮已结算的结论回答：编号为奇数的行的权重之和是多少？"
         "把这个数乘以 3 后取两位有效数字写出来。不要重新读取任何表格。")
    off = trace_offset()
    payload = {"model": metrics["identity"]["model"]["id"],
               "input": [{"role": "user", "content": q}],
               "max_output_tokens": 160,
               "previous_es_state_id": anchor,
               "continuation_settle": True}
    code, body, secs = post("/v1/responses", payload)
    tr = digest_trace(trace_since(off))
    out = json.dumps(body, ensure_ascii=False)
    metrics["stage2"] = {"http": code, "seconds": secs, "question": q, "trace": tr,
                         "body_head": out[:1500],
                         "continuation_settlement": body.get("continuation_settlement"),
                         "usage": body.get("usage")}
    log(f"[S3] anchor={anchor} http={code} secs={secs}")
    for ln in tr:
        log("     " + ln)
    log("      settlement=" + json.dumps(body.get("continuation_settlement"), ensure_ascii=False)[:400])
    if code != 200:
        log("      body=" + out[:1200])
    return body


def s4_control(anchor):
    """Same stage-2 question with the long source re-sent and NO IS anchor:
    the cost the IS recovery is supposed to replace."""
    src = src_block(40)
    off = trace_offset()
    payload = {"model": metrics["identity"]["model"]["id"],
               "input": [{"role": "user", "content": "表格：\n" + src + "\n\n" +
                          "只用这张表回答：编号为奇数的行的权重之和是多少？乘以 3 后取两位有效数字。"}],
               "max_output_tokens": 160}
    code, body, secs = post("/v1/responses", payload)
    tr = digest_trace(trace_since(off))
    metrics["control_no_is"] = {"http": code, "seconds": secs, "trace": tr,
                                "usage": body.get("usage")}
    log(f"[S4] control(no anchor, source re-sent) http={code} secs={secs}")
    for ln in tr:
        log("     " + ln)


def s5_measure():
    def num(rec, *keys):
        for k in keys:
            if k in rec and rec[k] is not None:
                return rec[k]
        return None
    rows = []
    for label in ("stage1", "stage2", "control_no_is"):
        rec = metrics.get(label)
        if not rec:
            continue
        tok = rec.get("usage") or {}
        rows.append({"case": label, "seconds": rec.get("seconds"),
                     "prompt_tokens": num(tok, "prompt_tokens", "input_tokens"),
                     "completion_tokens": num(tok, "completion_tokens", "output_tokens"),
                     "trace_prefill": [ln for ln in rec.get("trace", []) if "prefill" in ln],
                     "trace_cache": [ln for ln in rec.get("trace", [])
                                     if any(k in ln for k in ("cacheHit", "cacheEff", "mode=", "poolBind"))]})
    metrics["measurement"] = rows
    log("[S5] " + json.dumps(rows, ensure_ascii=False, indent=1)[:2000])


if __name__ == "__main__":
    skip = sys.argv[1:] 
    s0_identity()
    if "s1" not in skip:
        s1_stage1()
        s1b_es_anchor()
    else:
        s1b_es_anchor()
    moved = {} if "nkv" in skip else s2_isolate()
    anchor = metrics.get("anchor_state_id")
    if anchor:
        s3_stage2(anchor)
        s4_control(anchor)
    if moved:
        s2_restore(moved)
    s5_measure()
    with open(os.path.join(OUT, "run-" + NONCE + ".json"), "w") as f:
        json.dump(metrics, f, ensure_ascii=False, indent=1)
    log("[DONE] " + os.path.join(OUT, "run-" + NONCE + ".json"))
