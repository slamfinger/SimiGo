#!/usr/bin/env python3
"""intake paired trials —— B 项：第二/第三 intake 过消费判据。

第二 intake（cross-model reading，论文 §6.7 点名的未测项）：
  外部 agent 保留自己的云端 API，只向产品声明身份并调用结算工具
  （MCP simigo_es_begin → 自己调云 API → simigo_es_settle）。
  产品从未执行那次模型调用；声明身份是 provenance 不是 verification。
  消费判据：C 臂零调用 + 值经准入读路径相等 + consumer 双新物。
  控制臂：本地真模型对不同 demand 重新生成（复用标记缺席）——
  跨模型对照：外部声明的结算被消费，本地模型的重执行照常发生。

第三 intake（外部轮次，无结算）：
  与 app 的 ExternalTurnSink 同一函数组（recordExternalTurn/Response/verify），
  刻意不写结算——我们没执行过的调用没有执行状态。
  读数：intake 本身 settlements/states 增量 = 0；外部轮次 committed 后可被
  resolve 检索命中（检索结算是 resolve 自己的，与 intake 无关）。

运行形态：phase 1 纯 CLI（不加载模型、不起服务器）；phase 2 需服务器
（一次模型加载，供控制臂真生成与消费面）。静默窗豁免同 carrier_driver
（用户裁定 2026-11-10 保留生产实例并行；生产实例未挂大模型）。
"""
import argparse
import json
import os
import subprocess
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import baseline_driver as bd

PURPOSE = "intake-trials"

Q_EXT_USER = "How does a reuse contract gate admission in SimiGo?"
Q_EXT_ANSWER = ("A reuse contract admission discipline: exact-repeat demands consume "
                "the settled result, and the exact-repeat token gates the admission "
                "against a stale reuse.")
Q_EXT_RESOLVE = "reuse contract admission exact-repeat"

Q_MCP = "In one sentence, what does the settlement consumption contract guarantee?"
V_MCP = ("EXT-AGENT-SETTLED-VALUE: the contract guarantees the consumed result equals "
         "the settled record with zero model calls.")
Q_CTRL = ("[intake-ctrl] In under 120 words, state what content addressing is and "
          "its precondition for cache invalidation safety.")


def mcp_call(base_url, tool, args):
    body = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
            "params": {"name": tool, "arguments": args}}
    total, payload = bd.http_call("POST", f"{base_url}/mcp", body, timeout=60)
    txt = ""
    try:
        txt = payload["result"]["content"][0]["text"]
    except Exception:
        bd.stop(f"MCP {tool} 响应形状异常: {json.dumps(payload)[:400]}")
    if payload.get("result", {}).get("isError"):
        bd.stop(f"MCP {tool} 报错: {txt[:300]}")
    try:
        return json.loads(txt), total
    except Exception:
        return {"raw": txt}, total


def phase1_cli(args, ledger):
    """第三 intake：纯 CLI，无模型。"""
    db = bd.DB(args.db_path)
    r = bd.run([args.contract_cli, "init", "--db", args.db_path])
    if r.returncode != 0 or "INIT" not in r.stdout:
        bd.stop(f"实验库初始化失败: {r.stderr.strip()[:200]}")
    pre = {t: int(db.q(f"SELECT COUNT(*) FROM {t};") or 0)
           for t in ("settlements", "execution_states", "chat_messages",
                     "settlement_consumptions")}

    r = bd.run([args.contract_cli, "ext-turn", "--db", args.db_path,
                "--session", "ext-trial:proj-a/sess-01", "--request", "req-ext-001",
                "--user", Q_EXT_USER, "--answer", Q_EXT_ANSWER,
                "--provider", "qoder", "--model", "ext-cloud/declared-model-alpha"])
    if r.returncode != 0 or not r.stdout.startswith("EXT-TURN"):
        bd.stop(f"ext-turn 失败: {(r.stderr.strip() or r.stdout.strip())[:300]}")
    post = {t: int(db.q(f"SELECT COUNT(*) FROM {t};") or 0)
            for t in ("settlements", "execution_states", "chat_messages",
                      "settlement_consumptions")}
    delta = {t: post[t] - pre[t] for t in post}
    rows = db.q("SELECT role, turn_state, source_kind, source_provider, "
                "ifnull(model,'-') FROM chat_messages WHERE session_id="
                "'ext-trial:proj-a/sess-01' ORDER BY rowid;")
    reading = {"phase": "third-intake", "delta": delta, "rows": rows,
               "settlements_delta_must_be_0": delta["settlements"] == 0,
               "states_delta_must_be_0": delta["execution_states"] == 0}
    print(json.dumps({"event": "third_intake", **reading}, ensure_ascii=False))
    with open(args.ledger_path, "a") as f:
        f.write(json.dumps({"event": "third_intake", **reading},
                           ensure_ascii=False) + "\n")

    # committed 外部轮次必须可检索：resolve 命中它（检索结算是 resolve 自己的）。
    # 外部轮次在 chat 行里——resolve 必须 includeChat=1（--chat 1），首轮教训：
    # 缺省 false 时零命中是装置口径错，不是检索资格缺失。
    loop = bd.run([args.contract_cli, "resolve", "--db", args.db_path,
                   "--query", Q_EXT_RESOLVE, "--request", "req-ext-resolve-1",
                   "--chat", "1"])
    if loop.returncode != 0:
        bd.stop(f"resolve 失败: {loop.stderr.strip()[:300]}")
    resolved = json.loads(loop.stdout.strip()[len("RESOLVED "):])
    hit_reading = {"phase": "third-intake-retrieval", "hits": resolved["hits"],
                   "demand": resolved["demandID"], "reused": resolved["reused"]}
    print(json.dumps({"event": "third_intake_retrieval", **hit_reading},
                     ensure_ascii=False))
    with open(args.ledger_path, "a") as f:
        f.write(json.dumps({"event": "third_intake_retrieval", **hit_reading},
                           ensure_ascii=False) + "\n")
    if resolved["hits"] < 1:
        bd.stop("外部轮次 committed 后 resolve 零命中——检索资格未建立")
    return reading, hit_reading


def phase2_server(args, ledger):
    """第二 intake：cross-model 消费 + 本地模型控制臂。一次加载。"""
    prod_before = bd.prod_sha()

    # spawn（静默窗豁免版，同 carrier_driver）
    if subprocess.run(["lsof", "-nP", f"-iTCP:{args.port}", "-sTCP:LISTEN"],
                      capture_output=True).stdout:
        bd.stop(f"端口 {args.port} 已被占用")
    with open(args.ledger_path, "a") as f:
        f.write(json.dumps({"event": "quiet_window_exempt",
                            "reason": "用户裁定 2026-11-10 保留生产实例并行；未挂大模型"},
                           ensure_ascii=False) + "\n")
    env = dict(os.environ)
    env.update({"SIMIGO_HOME": args.home, "SIMIGO_CACHE_ROOT": args.cache_root,
                "SIMIGO_STATE_GRAPH_STORE": args.graph_store,
                "SIMIGO_LOCALB_MGMT": "serve-service",
                "SIMIGO_LOCALB_SERVE_MODEL": args.model_snapshot})
    proc = subprocess.Popen([args.binary, "-APIPort", str(args.port),
                             "-APIListenMode", "localhost", "-BackendSelection", "mlx",
                             "-SelectedModelPath", args.model_snapshot,
                             "-MLXModelPath", args.model_snapshot],
                            stdout=open(f"{args.out_dir}/server-s3.log", "ab"),
                            stderr=subprocess.STDOUT, env=env)
    for _ in range(240):
        try:
            urllib.request.urlopen(f"{args.base_url}/health", timeout=2)
            break
        except Exception:
            if proc.poll() is not None:
                bd.stop("进程提前退出")
            time.sleep(0.5)
    else:
        bd.stop("120s 内 HTTP 面未起")
    gpath = os.path.join(args.out_dir, "global_load_ledger.jsonl")
    seq = sum(1 for _ in open(gpath)) + 1 if os.path.exists(gpath) else 1
    with open(gpath, "a") as g:
        g.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "seq": seq,
                            "purpose": PURPOSE, "model": args.model_snapshot,
                            "pid": proc.pid}) + "\n")

    # S0'：第二 intake —— 外部 agent 声明身份并自调结算工具（产品零模型调用）
    db = bd.DB(args.db_path)
    pre_set = int(db.q("SELECT COALESCE(MAX(rowid),0) FROM settlements;") or 0)
    pre_state = int(db.q("SELECT COALESCE(MAX(rowid),0) FROM execution_states;") or 0)
    begun, _ = mcp_call(args.base_url, "simigo_es_begin",
                        {"model": args.ext_model, "tokenizer": args.ext_tokenizer,
                         "session_id": "ext-trial:mcp/sess-01", "query": Q_MCP})
    state_id = begun.get("state_id")
    if not state_id:
        bd.stop(f"begin 无 state_id: {json.dumps(begun)[:300]}")
    if begun.get("reusable_answer") is not None:
        bd.stop("begin 暴露了历史答案（reusable_answer 非 null）——语义漂移，停链")
    settled, _ = mcp_call(args.base_url, "simigo_es_settle",
                          {"state_id": state_id, "model": args.ext_model,
                           "tokenizer": args.ext_tokenizer, "output": V_MCP,
                           "session_id": "ext-trial:mcp/sess-01", "query": Q_MCP,
                           "idempotency_key": "intake-trial-t1"})
    sid = settled.get("settlement_id") or settled.get("settlementID") or ""
    if not sid:
        bd.stop(f"settle 无结算标识: {json.dumps(settled)[:400]}")
    with open(args.ledger_path, "a") as f:
        f.write(json.dumps({"event": "second_intake_settled", "state": state_id,
                            "settlement": sid, "declared_model": args.ext_model,
                            "product_model_calls": 0},
                           ensure_ascii=False) + "\n")

    # 声明复用契约（与 paired trials 同一路径）
    r = bd.run([args.contract_cli, "declare", "--db", args.db_path,
                "--settlement", sid, "--query", Q_MCP, "--roots", "work"])
    if r.returncode != 0 or not r.stdout.startswith("DECLARED"):
        bd.stop(f"契约声明失败: {(r.stderr.strip() or r.stdout.strip())[:300]}")

    # C' 臂：消费外部声明的结算（cross-model reading）
    cbody = {"model": args.model_id, "input": "consume",
             "settlement_consumption": {
                 "source_settlement_id": sid,
                 "contract": {"id": "simigo.settlement-consumption",
                              "demand_class": "exact-repeat", "version": "v1",
                              "extract": "content"},
                 "query": Q_MCP, "root_ids": ["work"], "allow_recompute": False}}
    ct, cpayload = bd.http_once(f"{args.base_url}/v1/responses", cbody, timeout=120)
    sc = cpayload.get("settlement_consumption")
    if cpayload.get("_status") != 200 or sc is None:
        bd.stop(f"[验收1] intake 消费未消费（HTTP {cpayload.get('_status')}）: "
                f"{json.dumps(cpayload)[:400]}")
    if sc.get("outcome") != "consumed" or sc.get("model_calls") != 0:
        bd.stop(f"[验收1] intake 消费断言失败: outcome={sc.get('outcome')} "
                f"model_calls={sc.get('model_calls')}")
    consumer_es = sc.get("consumer_es_state_id")
    consumer_set = sc.get("consumer_settlement_id")
    got = db.q(f"SELECT state_id FROM settlements WHERE settlement_id='{consumer_set}';")
    if got != consumer_es:
        bd.stop(f"[验收1] DB 复核失败: {got} != {consumer_es}")
    new_set = int(db.q(f"SELECT COUNT(*) FROM settlements WHERE settlement_id="
                       f"'{consumer_set}' AND rowid > {pre_set};") or 0)
    new_state = int(db.q(f"SELECT COUNT(*) FROM execution_states WHERE state_id="
                         f"'{consumer_es}' AND rowid > {pre_state};") or 0)
    if new_set != 1 or new_state != 1:
        bd.stop(f"[验收1] consumer 标识非新物: {new_set}/{new_state}")
    gv = bd.run([args.contract_cli, "get-value", "--db", args.db_path,
                 "--state", state_id], timeout=60)
    if gv.returncode != 0:
        bd.stop(f"get-value 失败: {gv.stderr.strip()[:200]}")
    expected = json.loads(gv.stdout.strip()).get("value", "")
    out_text = bd.responses_output_text(cpayload)
    if out_text != expected:
        bd.stop(f"[验收1值] 值不等: out={out_text[:80]!r} expected={expected[:80]!r}")
    with open(args.ledger_path, "a") as f:
        f.write(json.dumps({"event": "cross_model_consumed", "settlement": sid,
                            "consumer_es": consumer_es, "model_calls": 0,
                            "value_verified": True, "declared_model": args.ext_model,
                            "total_s": round(ct, 3), "contaminated": True},
                           ensure_ascii=False) + "\n")

    # R' 控制臂：本地真模型对不同 demand 重新生成
    rbody = {"model": args.model_id,
             "messages": [{"role": "user", "content": Q_CTRL}],
             "max_tokens": args.max_tokens, "stream": True,
             "session_id": "intake-s3-ctrl"}
    st = bd.http_stream(f"{args.base_url}/v1/chat/completions", rbody, timeout=480)
    if st["answer_reuse_any"] or not st["text"].strip():
        bd.stop("[控制臂] 复用标记在场或输出为空——控制失效")
    with open(args.ledger_path, "a") as f:
        f.write(json.dumps({"event": "local_generate_control", "chunks": st["chunks"],
                            "answer_reuse_seen": False, "contaminated": True},
                           ensure_ascii=False) + "\n")

    if not bd.quit_server(proc):
        bd.stop("quit 后进程仍存活")
    if prod_before != "absent" and bd.prod_sha() != prod_before:
        bd.stop(f"生产库 sha 变化: {prod_before} -> {bd.prod_sha()}")
    listening = subprocess.run(["lsof", "-nP", f"-iTCP:{args.port}", "-sTCP:LISTEN"],
                               capture_output=True).stdout
    if listening:
        bd.stop("端口未释放")
    with open(args.ledger_path, "a") as f:
        f.write(json.dumps({"event": "server_quit_clean", "loads": 1},
                           ensure_ascii=False) + "\n")
    return {"consumed": True, "model_calls": 0, "value_verified": True,
            "new_objects": {"settlement": new_set, "state": new_state},
            "control_chunks": st["chunks"]}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--binary", required=True)
    p.add_argument("--model-snapshot", required=True)
    p.add_argument("--model-id", required=True)
    p.add_argument("--ext-model", default="ext-cloud/declared-model-alpha")
    p.add_argument("--ext-tokenizer", default="ext-tokenizer-alpha")
    p.add_argument("--home", required=True)
    p.add_argument("--cache-root", required=True)
    p.add_argument("--graph-store", required=True)
    p.add_argument("--db-path", required=True)
    p.add_argument("--contract-cli", required=True)
    p.add_argument("--out-dir", required=True)
    p.add_argument("--port", type=int, default=8321)
    p.add_argument("--max-tokens", type=int, default=256)
    p.add_argument("--repo", default=None)
    a = p.parse_args()
    a.base_url = f"http://127.0.0.1:{a.port}"
    os.makedirs(a.out_dir, exist_ok=True)
    os.makedirs(a.home, exist_ok=True)
    os.makedirs(a.cache_root, exist_ok=True)
    os.makedirs(a.graph_store, exist_ok=True)
    a.ledger_path = os.path.join(a.out_dir, "ledger.jsonl")

    m = {"driver": "intake_driver.py v1", "purpose": PURPOSE,
         "started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
         "binary_sha256": bd.sha256_file(a.binary),
         "ext_declared_identity": f"{a.ext_model} / {a.ext_tokenizer}",
         "quiet_window": "EXEMPT（同 carrier_driver，用户裁定）",
         "timing_readings": "contaminated（CPU/GPU 并发）"}
    if a.repo:
        m["commit"] = bd.run(["git", "-C", a.repo, "log", "--oneline", "-1"]).stdout.strip()
    with open(os.path.join(a.out_dir, "manifest.json"), "w") as f:
        json.dump(m, f, ensure_ascii=False, indent=2)

    r1, r2 = phase1_cli(a, a.ledger_path)
    r3 = phase2_server(a, a.ledger_path)
    summary = {"third_intake": r1, "third_intake_retrieval": r2,
               "second_intake_cross_model": r3, "loads": 1}
    with open(os.path.join(a.out_dir, "summary.json"), "w") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)
    print("INTAKE-DONE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
