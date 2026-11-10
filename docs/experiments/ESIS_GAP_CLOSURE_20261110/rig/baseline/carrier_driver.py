#!/usr/bin/env python3
"""载体独立性真验收 driver —— A 项：释放旧进程与 KV → 冷启动 → 消费。

问的问题：真实模型结算 → 进程被 SIGKILL（载体与 KV 随进程死亡）→ 全新进程
冷启动（同一实验库）→ 显式消费该结算：零模型调用？值经真实准入读路径相等？
consumer 标识是否全是相对杀前账本的新物？

与 baseline_driver 的关系：消费判据全部沿用 [验收1]（DB 复核 + 新物 discipline +
值经 get-value 准入读路径比对）；新增的是"进程死"这一事件插在 S0 与 C 臂之间，
以及 R 控制臂证明冷启动服务器本身能生成（零调用不是服务器死）。

偏离声明（用户裁定 2026-11-10，"保留实例并行跑"）：静默窗门豁免——生产 SimiGo
实例（IS 载体，闲置挂起态 RSS≈166MB、未挂大模型，用户确认）并行运行。隔离论证：
独立 SIMIGO_HOME / SIMIGO_CACHE_ROOT / 端口 / 实验库；生产库 sha 前后对账照做。
后果标记：全部时延类读数（S0 生成、C/R 臂耗时、TTFT）受 CPU/GPU 并发污染，
记 contaminated=true，不作区间引用；结构断言（consumed / model_calls=0 / 新物 /
值相等）不依赖时延，不受影响。残余风险已声明：实验期间若生产实例被唤醒加载
模型，32GB 机器上两份 16GB 权重争内存（用户已确认当前未挂）。
"""
import argparse
import json
import os
import signal
import subprocess
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import baseline_driver as bd  # 复用：DB / http_* / prod_sha / quit_server / 常量

PURPOSE = "carrier-independence"


def log(ev, ledger, **f):
    bd.log(ev, ledger, **f)


def manage_server_nq(args, ledger, session_tag):
    """manage_server 的静默窗豁免版：其余流程逐行同源（spawn→/health→[READY]→加载账）。"""
    if subprocess.run(["lsof", "-nP", f"-iTCP:{args.port}", "-sTCP:LISTEN"],
                      capture_output=True).stdout:
        bd.stop(f"端口 {args.port} 已被占用")
    log("quiet_window_exempt", ledger, session=session_tag,
        reason="用户裁定 2026-11-10：生产实例(IS载体)保留并行；未挂大模型(用户确认)")
    trace = os.path.join(args.home, bd.TRACE_REL)
    trace_off = os.path.getsize(trace) if os.path.exists(trace) else 0
    env = dict(os.environ)
    env.update({"SIMIGO_HOME": args.home, "SIMIGO_CACHE_ROOT": args.cache_root,
                "SIMIGO_STATE_GRAPH_STORE": args.graph_store,
                "SIMIGO_LOCALB_MGMT": "serve-service",
                "SIMIGO_LOCALB_SERVE_MODEL": args.model_snapshot})
    log("server_spawn", ledger, session=session_tag, binary=args.binary, port=args.port)
    proc = subprocess.Popen([args.binary, "-APIPort", str(args.port),
                             "-APIListenMode", "localhost", "-BackendSelection", "mlx",
                             "-SelectedModelPath", args.model_snapshot,
                             "-MLXModelPath", args.model_snapshot],
                            stdout=open(f"{args.out_dir}/server-{session_tag}.log", "ab"),
                            stderr=subprocess.STDOUT, env=env)
    for _ in range(240):
        try:
            urllib.request.urlopen(f"{args.base_url}/health", timeout=2)
            break
        except Exception:
            if proc.poll() is not None:
                bd.stop("进程提前退出（见 server 日志）")
            time.sleep(0.5)
    else:
        bd.stop("120s 内 HTTP 面未起")
    ready = False
    for _ in range(1800):
        if os.path.exists(trace):
            with open(trace, "rb") as f:
                f.seek(trace_off)
                if b"[READY]" in f.read():
                    ready = True
                    break
        if proc.poll() is not None:
            bd.stop("进程退出于加载期")
        time.sleep(0.5)
    if not ready:
        bd.stop("15 分钟内未出现 [READY]")
    t_ready = time.time()
    gpath = os.path.join(args.out_dir, "global_load_ledger.jsonl")
    seq = sum(1 for _ in open(gpath)) + 1 if os.path.exists(gpath) else 1
    with open(gpath, "a") as g:
        g.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "seq": seq,
                            "purpose": PURPOSE, "session": session_tag,
                            "model": args.model_snapshot, "pid": proc.pid}) + "\n")
    log("model_ready", ledger, session=session_tag, global_load_seq=seq, pid=proc.pid)
    return proc, t_ready


def ps_rss_kb(pid):
    r = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True)
    return int(r.stdout.strip()) if r.stdout.strip() else None


def kv_binding_reading(db):
    """载体证据：KV 绑定类表在库中的行数（论文口径：结算绑定表零 KV 绑定）。"""
    names = [r for r in (db.q(
        "SELECT name FROM sqlite_master WHERE type='table' AND "
        "(name LIKE '%kv%' OR name LIKE '%carrier%');") or "").splitlines() if r.strip()]
    return {n: int(db.q(f"SELECT COUNT(*) FROM \"{n}\";") or 0) for n in names}


def register_root(args, ledger, session_tag):
    _, roots_put = bd.http_call("PUT", f"{args.base_url}/v1/simigo/roots",
                                {"path": args.work_dir}, timeout=30)
    rid = roots_put.get("root_id")
    if not roots_put.get("registered") or not rid:
        bd.stop(f"root 注册失败: {json.dumps(roots_put)[:300]}")
    _, rec_payload = bd.http_call("POST", f"{args.base_url}/v1/simigo/is/reconcile",
                                  {"category": "work"}, timeout=60)
    if "RECONCILE_FAILED" in json.dumps(rec_payload):
        bd.stop(f"reconcile 失败: {json.dumps(rec_payload)[:300]}")
    log("root_registered", ledger, session=session_tag, root_id=rid)
    return rid


def responses_output_text(payload):
    return bd.responses_output_text(payload)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--binary", required=True)
    p.add_argument("--model-snapshot", required=True)
    p.add_argument("--model-id", required=True)
    p.add_argument("--home", required=True)
    p.add_argument("--cache-root", required=True)
    p.add_argument("--graph-store", required=True)
    p.add_argument("--db-path", required=True)
    p.add_argument("--work-dir", required=True)
    p.add_argument("--contract-cli", required=True)
    p.add_argument("--out-dir", required=True)
    p.add_argument("--port", type=int, default=8321)
    p.add_argument("--max-tokens", type=int, default=256)
    p.add_argument("--repo", default=None)
    a = p.parse_args()
    a.base_url = f"http://127.0.0.1:{a.port}"
    a.s0_mode = "chat"

    os.makedirs(a.out_dir, exist_ok=True)
    ledger = open(os.path.join(a.out_dir, "ledger.jsonl"), "a")

    # manifest（构建身份 + 偏离声明）
    m = {"driver": "carrier_driver.py v1", "purpose": PURPOSE,
         "started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
         "binary_sha256": bd.sha256_file(a.binary), "binary_path": a.binary,
         "model_snapshot": os.path.basename(a.model_snapshot.rstrip("/")),
         "max_tokens": a.max_tokens, "port": a.port,
         "quiet_window": "EXEMPT（用户裁定 2026-11-10 保留生产实例并行；"
                         "生产实例未挂大模型，用户确认）",
         "timing_readings": "contaminated（CPU/GPU 并发）",
         "contract_constants": {"contract_id": "simigo.settlement-consumption",
                                "demand_class": "exact-repeat", "version": "v1",
                                "extract": "content"}}
    if a.repo:
        g = bd.run(["git", "-C", a.repo, "log", "--oneline", "-1"])
        m["commit"] = g.stdout.strip()
        d = bd.run(["git", "-C", a.repo, "status", "--short"])
        m["worktree_dirty_entries"] = len([l for l in d.stdout.splitlines() if l.strip()])
    with open(os.path.join(a.out_dir, "manifest.json"), "w") as f:
        json.dump(m, f, ensure_ascii=False, indent=2)
    log("manifest", ledger, **{k: m[k] for k in ("driver", "commit", "binary_sha256",
                                                 "quiet_window") if k in m})

    prod_before = bd.prod_sha()
    db = bd.DB(a.db_path)
    if not os.path.exists(a.db_path):
        r = bd.run([a.contract_cli, "init", "--db", a.db_path])
        if r.returncode != 0 or "INIT" not in r.stdout:
            bd.stop(f"实验库初始化失败: {r.stderr.strip()[:200]}")
        log("db_initialized", ledger, path=a.db_path)

    q_main = ("[carrier-main] In under 120 words, state what content addressing is "
              "and its precondition for cache invalidation safety.")
    q_ctrl = ("[carrier-ctrl] In under 120 words, state what a reuse contract is "
              "and its precondition for admission.")

    # ── 会话 1：真实生成 → SIGKILL ──
    proc1, t_ready1 = manage_server_nq(a, ledger, "s1")
    rid = register_root(a, ledger, "s1")
    a.root_id = rid
    gap1 = time.time() - t_ready1
    log("first_request_gate", ledger, session="s1", delta_s=round(gap1, 2),
        budget_s=bd.FIRST_REQUEST_BUDGET_S, contaminated=True)

    pre_counts = db.counts()
    body = {"model": a.model_id, "messages": [{"role": "user", "content": q_main}],
            "max_tokens": a.max_tokens, "session_id": "carrier-s1-main"}
    total, payload = bd.http_once(f"{a.base_url}/v1/chat/completions", body, timeout=480)
    if payload.get("_status") != 200 or "choices" not in payload:
        bd.stop(f"S0 chat 失败: {json.dumps(payload)[:300]}")
    s0_text = str(((payload["choices"][0] or {}).get("message") or {}).get("content", ""))
    sid, s0_state = db.wait_generation_settlement(pre_counts["settlements"], pair_idx="s0")
    log("s0_settled", ledger, settlement=sid, state=s0_state, gen_total_s=round(total, 3),
        contaminated=True, text_head=s0_text[:100])
    r = bd.run([a.contract_cli, "declare", "--db", a.db_path,
                "--settlement", sid, "--query", q_main, "--roots", rid])
    if r.returncode != 0 or not r.stdout.startswith("DECLARED"):
        bd.stop(f"契约声明失败: {(r.stderr.strip() or r.stdout.strip())[:300]}")

    # 载体在场的证据（杀前取）
    carrier_evidence = {
        "rss_kb": ps_rss_kb(proc1.pid),
        "kv_binding_tables": kv_binding_reading(db),
        "runtime_json": None,
        "pre_kill_max_set_rowid": int(db.q(
            "SELECT COALESCE(MAX(rowid),0) FROM settlements;") or 0),
        "pre_kill_max_state_rowid": int(db.q(
            "SELECT COALESCE(MAX(rowid),0) FROM execution_states;") or 0),
        "pre_kill_max_cons_rowid": int(db.q(
            "SELECT COALESCE(MAX(rowid),0) FROM settlement_consumptions;") or 0),
    }
    # 口径注记（v1 首跑教训）：各表 rowid 序列独立，消费账的新物基线必须取
    # settlement_consumptions 自己的杀前最大 rowid，不得跨表借结算表的。
    rj = os.path.join(a.home, "state", "runtime.json")
    if os.path.exists(rj):
        carrier_evidence["runtime_json"] = json.load(open(rj))
    log("carrier_alive", ledger, **carrier_evidence)

    # SIGKILL：载体死亡事件（非优雅退出——KV 随进程由 OS 回收）
    kill_ts = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    os.kill(proc1.pid, signal.SIGKILL)
    for _ in range(60):
        if proc1.poll() is not None:
            break
        time.sleep(0.5)
    else:
        bd.stop("SIGKILL 后进程未退出")
    log("carrier_killed", ledger, pid=proc1.pid, signal="SIGKILL", ts=kill_ts,
        graceful=False, rss_kb_at_kill=ps_rss_kb(proc1.pid))
    listening = subprocess.run(["lsof", "-nP", f"-iTCP:{a.port}", "-sTCP:LISTEN"],
                               capture_output=True).stdout
    if listening:
        bd.stop("杀后端口未释放")
    log("port_released_after_kill", ledger, port=a.port)

    # ── 会话 2：全新进程冷启动 → 冷消费 ──
    proc2, t_ready2 = manage_server_nq(a, ledger, "s2")
    register_root(a, ledger, "s2")
    gap2 = time.time() - t_ready2
    log("first_request_gate", ledger, session="s2", delta_s=round(gap2, 2),
        budget_s=bd.FIRST_REQUEST_BUDGET_S, contaminated=True)

    # C 臂：冷消费（判据同 [验收1]，新物基线 = 杀前账本）
    cbody = {"model": a.model_id, "input": "consume",
             "settlement_consumption": {
                 "source_settlement_id": sid,
                 "contract": {"id": "simigo.settlement-consumption",
                              "demand_class": "exact-repeat", "version": "v1",
                              "extract": "content"},
                 "query": q_main, "root_ids": [rid], "allow_recompute": False}}
    ct, cpayload = bd.http_once(f"{a.base_url}/v1/responses", cbody, timeout=120)
    sc = cpayload.get("settlement_consumption")
    if cpayload.get("_status") != 200 or sc is None:
        bd.stop(f"[验收1] 冷消费未消费（HTTP {cpayload.get('_status')}）: "
                f"{json.dumps(cpayload)[:400]}")
    if sc.get("outcome") != "consumed" or sc.get("model_calls") != 0:
        bd.stop(f"[验收1] 冷消费断言失败: outcome={sc.get('outcome')} "
                f"model_calls={sc.get('model_calls')}")
    consumer_es = sc.get("consumer_es_state_id")
    consumer_set = sc.get("consumer_settlement_id")
    if not consumer_es or not consumer_set:
        bd.stop(f"[验收1] 冷消费缺 consumer 标识: {sc}")
    got = db.q(f"SELECT state_id FROM settlements WHERE settlement_id='{consumer_set}';")
    if got != consumer_es:
        bd.stop(f"[验收1] DB 复核失败: 派生结算 state={got} != consumer_es={consumer_es}")
    new_set = int(db.q("SELECT COUNT(*) FROM settlements WHERE settlement_id="
                       f"'{consumer_set}' AND rowid > {carrier_evidence['pre_kill_max_set_rowid']};") or 0)
    new_state = int(db.q("SELECT COUNT(*) FROM execution_states WHERE state_id="
                         f"'{consumer_es}' AND rowid > {carrier_evidence['pre_kill_max_state_rowid']};") or 0)
    if new_set != 1 or new_state != 1:
        bd.stop(f"[验收1] consumer 标识非杀后新物: new_settlement={new_set} "
                f"new_state={new_state}")
    gv = bd.run([a.contract_cli, "get-value", "--db", a.db_path, "--state", s0_state],
                timeout=60)
    if gv.returncode != 0:
        bd.stop(f"get-value 失败: {gv.stderr.strip()[:200]}")
    expected_value = json.loads(gv.stdout.strip()).get("value", "")
    out_text = responses_output_text(cpayload)
    if out_text != expected_value:
        bd.stop(f"[验收1值] 冷消费返回内容 ≠ 结算值: out={out_text[:80]!r} "
                f"expected={expected_value[:80]!r}")
    cons_row = db.q(f"SELECT COUNT(*) FROM settlement_consumptions WHERE rowid > "
                    f"{carrier_evidence['pre_kill_max_cons_rowid']};")
    log("cold_consumed", ledger, settlement=sid, consumer_es=consumer_es,
        consumer_settlement=consumer_set, model_calls=sc.get("model_calls"),
        value_verified=True, new_consumption_rows=cons_row,
        total_s=round(ct, 3), contaminated=True, out_head=out_text[:100])

    # R 控制臂：冷启动服务器本身能生成（零调用不是服务器死）
    rbody = {"model": a.model_id,
             "messages": [{"role": "user", "content": q_ctrl}],
             "max_tokens": a.max_tokens, "stream": True,
             "session_id": "carrier-s2-ctrl"}
    st = bd.http_stream(f"{a.base_url}/v1/chat/completions", rbody, timeout=480)
    if st["answer_reuse_any"]:
        bd.stop("[控制臂] 冷启动 R 臂命中 answer_reuse——控制失效")
    if not st["text"].strip():
        bd.stop("[控制臂] 冷启动 R 臂输出为空")
    log("cold_generate_control", ledger, chunks=st["chunks"],
        answer_reuse_seen=st["answer_reuse_any"], ttft_s=st["ttft_s"],
        total_s=st["total_s"], contaminated=True, text_head=st["text"][:100])

    # 收尾：优雅退出 + 生产库对账 + 端口释放
    if not bd.quit_server(proc2):
        bd.stop("quit 后进程仍存活——停链报告，不得强杀")
    if prod_before != "absent" and bd.prod_sha() != prod_before:
        bd.stop(f"生产库 sha 变化: {prod_before} -> {bd.prod_sha()}")
    listening = subprocess.run(["lsof", "-nP", f"-iTCP:{a.port}", "-sTCP:LISTEN"],
                               capture_output=True).stdout
    if listening:
        bd.stop("端口未释放")
    log("server_quit_clean", ledger, prod_sha_unchanged=True, port_released=True)

    summary = {"cold_consumed": True, "c_model_calls": sc.get("model_calls"),
               "value_verified": True, "consumer_new_objects": {"settlement": new_set,
                                                                "state": new_state},
               "new_consumption_rows": cons_row,
               "control_arm": {"chunks": st["chunks"], "answer_reuse_seen": False},
               "carrier_evidence": {k: carrier_evidence[k] for k in
                                    ("rss_kb", "kv_binding_tables")},
               "loads": 2, "timing": "contaminated（并发）"}
    with open(os.path.join(a.out_dir, "summary.json"), "w") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)
    log("summary", ledger, **summary)
    print("CARRIER-DONE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
