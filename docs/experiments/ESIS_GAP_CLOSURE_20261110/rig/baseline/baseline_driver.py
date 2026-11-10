#!/usr/bin/env python3
"""SimiGo 结算消费微基线 driver —— BASELINE_DESIGN_V0.1 §二/§二.1 的可执行实现。v2

模式
  --mode manage   真机：管理服务器生命周期（spawn → /health → [READY] → 首请求 <5s 硬门
                  → 全局加载账 → osascript 正常退出 → 生产库 sha 对账 → 端口释放）
  --mode attach   演练：连接已运行服务器（XCTest 嵌入 stub 服务器；跳过加载账与退出）
s0-mode
  chat            真机：/v1/chat/completions 单请求自动结算（P2 R2 裁定路径）
  stage           演练：contract_cli stage 直预埋（镜像 stageConsumableSource）

验收映射（BASELINE_DESIGN §二.1）
  [验收1] C 臂：200 + settlement_consumption.outcome=="consumed" + model_calls==0
          + consumer_es_state_id/consumer_settlement_id 在场 + DB 复核：派生结算挂 consumer state
  [验收2] R 臂：不同 demand 文本 + 新 session；chunk 级 simigo.answer_reuse 必须全 false
          + 输出非空 + 输出 ≠ C 臂服务值
  [验收3] 单加载约束下以"每对唯一 demand + C 只消费本对 S0"实现独立性（偏离已注明）
  [验收4] TTFT（R 流式）/总时延/加载时间三口径分开记录
  [验收5] 记录 idle 阈值（240s）与请求间隔，超 80% 预警
  [验收6] manifest：commit/二进制哈希/模型身份/配置/样本次序/账本

分阶段（批准条件 2 第二次修订）
  --phase pilot → 3 对 + 方差摘要退出；--phase extend --from N 续跑；异常停在整数对不回补
"""

import argparse
import hashlib
import json
import os
import random
import subprocess
import sys
import time
import urllib.error
import urllib.request

IDLE_THRESHOLD_S = 240.0        # P2 C1 教训：NativeMLX 空闲挂起阈值
FIRST_REQUEST_BUDGET_S = 5.0    # [READY] → 首请求硬门（P2 纪律）
TRACE_REL = "logs/native_mlx_trace.log"


def stop(msg):
    print(f"BASELINE-STOP: {msg}", flush=True)
    sys.exit(1)


def log(ev, ledger, **fields):
    rec = {"ts": round(time.time(), 3), "event": ev, **fields}
    ledger.write(json.dumps(rec, ensure_ascii=False) + "\n")
    ledger.flush()
    print(json.dumps(rec, ensure_ascii=False), flush=True)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def run(cmd, timeout=600, cwd=None):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                          cwd=cwd)


def http_once(url, body, timeout):
    """非流式 POST。4xx/5xx 也返回解析后的 body（payload["_status"]），由断言侧处置。"""
    return http_call("POST", url, body, timeout)


def http_call(method, url, body, timeout=30):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            payload = json.loads(resp.read().decode())
            payload["_status"] = resp.status
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {"_raw": raw[:400]}
        payload["_status"] = e.code
    return time.time() - t0, payload


def http_stream(url, body, timeout):
    """流式 chat：逐行读 SSE。

    返回 dict(ttft_s, total_s, chunks, text, answer_reuse_any, chunks_raw_head)。
    [验收2 关键] simigo.answer_reuse 在 chunk 对象里，不在 content 文本里——
    必须在 chunk 级检查，只看文本会漏掉复用。
    """
    data = json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method="POST",
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    ttft = None
    chunks = 0
    text_parts = []
    answer_reuse_any = False
    first_raw = None
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            for raw in resp:
                line = raw.decode(errors="replace").strip()
                if first_raw is None:
                    first_raw = line
                if not line.startswith("data:"):
                    continue
                payload = line[5:].strip()
                if payload == "[DONE]":
                    break
                try:
                    obj = json.loads(payload)
                except json.JSONDecodeError:
                    continue
                simigo = obj.get("simigo") or {}
                if simigo.get("answer_reuse") is True:
                    answer_reuse_any = True
                delta = (obj.get("choices") or [{}])[0].get("delta") or {}
                content = delta.get("content")
                if content:
                    if ttft is None:
                        ttft = time.time() - t0
                    chunks += 1
                    text_parts.append(content)
    except urllib.error.HTTPError as e:
        stop(f"流式请求 HTTP {e.code}: {e.read().decode(errors='replace')[:300]}")
    if ttft is None:
        stop(f"流式响应无内容 chunk（首行={first_raw!r}）")
    return {"ttft_s": round(ttft, 3), "total_s": round(time.time() - t0, 3),
            "chunks": chunks, "text": "".join(text_parts),
            "answer_reuse_any": answer_reuse_any}


def responses_output_text(payload):
    out = payload.get("output")
    if isinstance(out, list) and out:
        content = (out[0] or {}).get("content")
        if isinstance(content, list) and content:
            return str((content[0] or {}).get("text", ""))
    return ""


class DB:
    def __init__(self, path):
        self.path = path

    def q(self, sql, retries=4):
        # [锁重试·真机教训] server 持有 WAL 写锁时，只读查询会撞 SQLITE_BUSY(5)
        # （pair2 实测：S0 结算落库后立刻查询即撞）。CLI 层 .timeout 4s + 应用层退避重试。
        last = ""
        for attempt in range(retries):
            r = run(["sqlite3", "-readonly", "-cmd", ".timeout 4000",
                     f"file:{self.path}?mode=ro", sql], timeout=60)
            out = r.stdout.strip()
            err = r.stderr.strip()
            locked = "database is locked" in out or "database is locked" in err
            if r.returncode == 0 and not locked and not out.startswith("Parse error"):
                return out
            last = err or out
            time.sleep(1.5 * (attempt + 1))
        stop(f"sqlite 只读失败（重试 {retries} 次后）: {last[:200]}")

    def counts(self):
        out = {}
        for t in ("settlements", "execution_states", "information_advancements",
                  "settlement_consumptions", "is_objects"):
            out[t] = int(self.q(f"SELECT COUNT(*) FROM {t};") or 0)
        return out

    def wait_generation_settlement(self, pre_count, timeout_s=30, pair_idx="?"):
        """S0 后等答案结算落库（generation = 非 IS_RETRIEVAL / 非 DERIVED_CONSUMPTION）。"""
        deadline = time.time() + timeout_s
        while time.time() < deadline:
            row = self.q(
                "SELECT s.settlement_id || '|' || s.state_id FROM settlements s "
                "JOIN settlement_current_validity v ON v.settlement_id=s.settlement_id "
                "WHERE v.validity='valid' AND s.validation_status NOT IN "
                "('IS_RETRIEVAL','DERIVED_CONSUMPTION') "
                f"AND s.rowid > {pre_count} ORDER BY s.rowid DESC LIMIT 1;")
            if row:
                sid, state = row.split("|", 1)
                return sid, state
            time.sleep(0.5)
        stop(f"pair{pair_idx} S0 后 30s 内未见到答案结算（chat 自动结算未落库？）")


def build_manifest(args):
    m = {"driver": "baseline_driver.py v2", "started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
         "mode": args.mode, "s0_mode": args.s0_mode, "seed": args.seed,
         "pairs_plan": args.pairs, "max_tokens": args.max_tokens,
         "idle_threshold_s": IDLE_THRESHOLD_S,
         "first_request_budget_s": FIRST_REQUEST_BUDGET_S}
    # --repo：git 必须在仓库里问。不传时退回当前目录——但演练/真机都可能
    # 从别的 cwd 启动，届时会静默写出 "unknown"，让 manifest 的可复现字段变成摆设。
    g = run(["git", "rev-parse", "HEAD"], cwd=args.repo)
    m["commit"] = g.stdout.strip() if g.returncode == 0 else "unknown"
    d = run(["git", "status", "--porcelain"], cwd=args.repo)
    m["worktree_dirty_entries"] = len([x for x in d.stdout.splitlines() if x.strip()])
    if args.binary and os.path.exists(args.binary):
        m["binary_sha256"] = sha256_file(args.binary)
        m["binary_path"] = args.binary
    if args.model_snapshot:
        m["model_snapshot"] = os.path.basename(args.model_snapshot.rstrip("/"))
        for name in ("config.json", "tokenizer.model", "tokenizer.json", "tokenizer_config.json"):
            p = os.path.join(args.model_snapshot, name)
            if os.path.exists(p):
                m[f"model_{name.replace('.', '_')}_sha256"] = sha256_file(p)
        shards = sorted(f for f in os.listdir(args.model_snapshot) if f.endswith(".safetensors"))
        m["model_shards"] = {f: os.path.getsize(os.path.join(args.model_snapshot, f)) for f in shards}
        m["model_weights_full_hash"] = "off（快照 id + config sha 承载模型身份）"
    m["experiment_db"] = args.db_path
    m["work_dir"] = args.work_dir
    m["contract_constants"] = args.contract_constants
    return m


def check_gap(ledger, last_request_end, arm):
    """[验收5] 请求间隔逼近 idle 阈值即预警。"""
    if last_request_end is None:
        return time.time()
    gap = time.time() - last_request_end
    if gap > IDLE_THRESHOLD_S * 0.8:
        log("idle_gap_warning", ledger, arm=arm, gap_s=round(gap, 1),
            threshold_s=IDLE_THRESHOLD_S)
    return time.time()


def pair_queries(i, domain):
    """[验收3] 每对唯一 demand 文本：Q_i 给 S0+C，Q_i' 给 R。文本绝不跨对重复。"""
    return (f"[pair{i:02d}-main] In under 120 words, from the registered work root: "
            f"{domain} — aspect {i}: state the mechanism and its precondition.",
            f"[pair{i:02d}-reexec] In under 120 words, from the registered work root: "
            f"{domain} — different aspect {i}: state the failure mode and its trigger.")


def execute_pair(idx, pre_count, cfg, db, ledger, arm_order):
    q_main, q_re = pair_queries(idx, cfg.domain)
    rec = {"pair": idx, "queries": {"main": q_main, "reexec": q_re}}
    last_end = None

    # ── S0：producer run（不进对照）──
    if cfg.s0_mode == "chat":
        last_end = check_gap(ledger, last_end, "S0")
        body = {"model": cfg.model_id, "messages": [{"role": "user", "content": q_main}],
                "max_tokens": cfg.max_tokens, "session_id": f"{cfg.session_prefix}-{idx}"}
        total, payload = http_once(f"{cfg.base_url}/v1/chat/completions", body, timeout=480)
        if payload.get("_status") != 200 or "choices" not in payload:
            stop(f"pair{idx} S0 chat 失败: {json.dumps(payload)[:300]}")
        msg = (payload["choices"][0] or {}).get("message") or {}
        s0_text = str(msg.get("content", ""))
        rec["s0"] = {"total_s": round(total, 3), "text_head": s0_text[:120]}
        served_value = s0_text
    else:
        if not args_work_dir_ok(cfg):
            stop("stage 模式需要 --work-dir")
        r = run([cfg.contract_cli, "stage", "--db", cfg.db_path,
                 "--root-url", cfg.work_dir, "--value", cfg.stage_value,
                 "--query", q_main, "--state-id", f"es-s0-{idx:02d}",
                 "--model", "rehearsal-model", "--tokenizer", "rehearsal-tokenizer"])
        if r.returncode != 0 or not r.stdout.startswith("STAGED"):
            stop(f"pair{idx} stage 失败: {r.stderr.strip()[:300]}")
        served_value = cfg.stage_value
        rec["s0"] = {"staged": True, "text_head": cfg.stage_value[:120]}

    sid, s0_state = db.wait_generation_settlement(pre_count, pair_idx=idx)
    rec["s0"]["settlement_id"] = sid
    rec["s0"]["state_id"] = s0_state
    log("s0_settled", ledger, pair=idx, settlement=sid, state=s0_state)

    # ── 声明复用契约（走真实 API；产品无远端声明面，故经 contract_cli）──
    r = run([cfg.contract_cli, "declare", "--db", cfg.db_path,
             "--settlement", sid, "--query", q_main, "--roots", cfg.root_id])
    if r.returncode != 0 or not r.stdout.startswith("DECLARED"):
        stop(f"pair{idx} 契约声明失败: "
             f"{(r.stderr.strip() or r.stdout.strip())[:300]}")

    before_counts = db.counts()
    pre_max_set = int(db.q("SELECT COALESCE(MAX(rowid),0) FROM settlements;") or 0)
    pre_max_state = int(db.q("SELECT COALESCE(MAX(rowid),0) FROM execution_states;") or 0)
    arms = list(arm_order)  # [预注册随机] 次序来自启动时算满的 schedule[i]
    rec["arm_order"] = list(arms)
    results = {}

    for arm in arms:
        last_end = check_gap(ledger, last_end, arm)
        if arm == "R":
            # [验收2] 不同 demand + 新 session；chunk 级断言非复用
            body = {"model": cfg.model_id,
                    "messages": [{"role": "user", "content": q_re}],
                    "max_tokens": cfg.max_tokens, "stream": True,
                    "session_id": f"{cfg.session_prefix}-r-{idx}"}
            st = http_stream(f"{cfg.base_url}/v1/chat/completions", body, timeout=480)
            if st["answer_reuse_any"]:
                stop(f"pair{idx} [验收2] R 臂命中 answer_reuse——退化为复用路径")
            if not st["text"].strip():
                stop(f"pair{idx} [验收2] R 臂输出为空")
            text_eq = st["text"].strip() == served_value.strip()
            # [降级·用户裁定] answer_reuse（服务器契约标记）是唯一硬门；文本相等
            # 记录为协变量——30B 对信息不足 prompt 给固定回应很现实，误报不报废整轮。
            if text_eq and cfg.strict_text_eq:
                stop(f"pair{idx} [验收2] R 臂输出了 C 的服务值——--strict-text-eq 硬门")
            # 调用数不可直读：/v1/chat/completions 只在复用路径写
            # simigo.model_calls=0（HTTPServerChat.swift:636/1350），fresh 生成
            # 不写该字段。所以 R 臂只记两个可观测事实，不伪造计数：
            #   1) answer_reuse 标记缺席（上面已硬判）
            #   2) 产出了非空文本（chunks>0）
            results["R"] = {"ttft_s": st["ttft_s"], "total_s": st["total_s"],
                            "chunks": st["chunks"], "text_head": st["text"][:120],
                            "text_equals_served": text_eq,
                            "answer_reuse_seen": st["answer_reuse_any"],
                            "model_calls": "n/a（该端点不暴露生成计数）"}
            last_end = time.time()
        else:
            # [验收1] C 臂：显式消费 opt-in；常量来自 contract_cli constants（非硬编码）
            body = {"model": cfg.model_id, "input": "consume",
                    "settlement_consumption": {
                        "source_settlement_id": sid,
                        "contract": {
                            "id": cfg.contract_constants["contract_id"],
                            "demand_class": cfg.contract_constants["demand_class"],
                            "version": cfg.contract_constants["version"],
                            "extract": cfg.contract_constants["extract"],
                        },
                        "query": q_main,
                        "root_ids": [cfg.root_id],
                        "allow_recompute": False}}
            total, payload = http_once(f"{cfg.base_url}/v1/responses", body, timeout=60)
            sc = payload.get("settlement_consumption")
            if payload.get("_status") != 200 or sc is None:
                stop(f"pair{idx} [验收1] C 臂未消费（HTTP {payload.get('_status')}）: "
                     f"{json.dumps(payload)[:400]}")
            if sc.get("outcome") != "consumed" or sc.get("model_calls") != 0:
                stop(f"pair{idx} [验收1] C 臂断言失败: outcome={sc.get('outcome')} "
                     f"model_calls={sc.get('model_calls')}")
            consumer_es = sc.get("consumer_es_state_id")
            consumer_set = sc.get("consumer_settlement_id")
            if not consumer_es or not consumer_set:
                stop(f"pair{idx} [验收1] C 臂缺 consumer 标识: {sc}")
            got = db.q(f"SELECT state_id FROM settlements WHERE settlement_id='{consumer_set}';")
            if got != consumer_es:
                stop(f"pair{idx} [验收1] DB 复核失败: 派生结算 state={got} != consumer_es={consumer_es}")
            # [验收1 强化·用户复核点1] consumer 标识必须是本对新物——只看 model_calls=0
            # 会被"应答复用"路径骗过（复用不新建 state/结算）。
            new_set = int(db.q("SELECT COUNT(*) FROM settlements WHERE settlement_id="
                               f"'{consumer_set}' AND rowid > {pre_max_set};") or 0)
            new_state = int(db.q("SELECT COUNT(*) FROM execution_states WHERE state_id="
                                 f"'{consumer_es}' AND rowid > {pre_max_state};") or 0)
            if new_set != 1 or new_state != 1:
                stop(f"pair{idx} [验收1] consumer 标识非本对新物: "
                     f"new_settlement={new_set} new_state={new_state}")
            # [验收1值·第六条鱼] 消费的全部意义是把已结算的值交回去——只验握手
            # 不验货物，"路径对、内容不对"会漏。chat 模式的期望值必须经真实准入
            # 读路径从 DB 取（模型原文 ≠ 规范化结算值）；stage 模式直接比预埋值。
            out_text = responses_output_text(payload)
            if cfg.s0_mode == "stage":
                expected_value = cfg.stage_value
            else:
                gv = run([cfg.contract_cli, "get-value", "--db", cfg.db_path,
                          "--state", s0_state], timeout=60)
                if gv.returncode != 0:
                    stop(f"pair{idx} get-value 失败: {gv.stderr.strip()[:200]}")
                expected_value = json.loads(gv.stdout.strip()).get("value", "")
            if out_text != expected_value:
                stop(f"pair{idx} [验收1值] C 臂返回内容 ≠ 结算值: "
                     f"out={out_text[:80]!r} expected={expected_value[:80]!r}")
            results["C"] = {"total_s": round(total, 3),
                            "output_text_head": out_text[:120],
                            "value_verified": True,
                            "consumer_es_state_id": consumer_es,
                            "consumer_settlement_id": consumer_set,
                            "model_calls": sc.get("model_calls")}
            last_end = time.time()

    rec["results"] = results
    rec["counts_before_arms"] = before_counts
    rec["counts_after"] = db.counts()
    rec["ok"] = True
    return rec


def args_work_dir_ok(cfg):
    return bool(cfg.work_dir and os.path.isdir(cfg.work_dir))


def manage_server(args, ledger):
    """[manage] spawn → /health → [READY] → 全局加载账。返回 (proc, t_ready)。"""
    if subprocess.run(["lsof", "-nP", f"-iTCP:{args.port}", "-sTCP:LISTEN"],
                      capture_output=True).stdout:
        stop(f"端口 {args.port} 已被占用")
    # [静默窗获取] 测试宿主会启退 SimiGo.app（P2 记录在案）：数秒级测试活动窗
    # 可整段覆盖 6s 采样——要等的是静默窗，不是某个瞬间的进程缺席。
    # 最多等 15 分钟：每轮 3 采样/3s 间隔，一轮全空即开门；超时如实停（零成本，
    # 加载账未动）。测试线若持续在跑，由用户暂停（停线只能用户下令）。
    def _simigo_running():
        # [自匹配修复] driver 自己的 --binary 参数含同款路径，子串匹配会命中
        # 自己（42 轮全中的真相）。改为：排除 baseline_driver 行 + 命令首词
        # 精确等于 app 可执行路径（真实例可带 -APIPort 等参数）。
        out = subprocess.run(["ps", "-Ao", "pid=,command="],
                             capture_output=True, text=True).stdout
        for line in out.splitlines():
            if "baseline_driver.py" in line:
                continue
            parts = line.strip().split(None, 1)
            if len(parts) == 2 and                     parts[1].split(" ")[0].endswith("/SimiGo.app/Contents/MacOS/SimiGo"):
                return True
        return False
    deadline = time.time() + 900
    wait_rounds = 0
    while True:
        hits = 0
        for k in range(3):
            hits += 1 if _simigo_running() else 0
            if k < 2:
                time.sleep(3)
        if hits == 0:
            if wait_rounds:
                log("quiet_window_acquired", ledger, wait_rounds=wait_rounds)
            break
        wait_rounds += 1
        if time.time() > deadline:
            stop(f"15 分钟内未获静默窗（SimiGo 实例持续在跑，{wait_rounds} 轮全命中）"
                 "——测试线若在跑请暂停后重启本 driver；本次未消耗任何加载")
        log("wait_quiet_window", ledger, round=wait_rounds, hits_last_round=hits)
    trace = os.path.join(args.home, TRACE_REL)
    trace_off = os.path.getsize(trace) if os.path.exists(trace) else 0
    env = dict(os.environ)
    env.update({"SIMIGO_HOME": args.home, "SIMIGO_CACHE_ROOT": args.cache_root,
                "SIMIGO_STATE_GRAPH_STORE": args.graph_store,
                "SIMIGO_LOCALB_MGMT": "serve-service",
                "SIMIGO_LOCALB_SERVE_MODEL": args.model_snapshot})
    log("server_spawn", ledger, binary=args.binary, port=args.port)
    proc = subprocess.Popen([args.binary, "-APIPort", str(args.port),
                             "-APIListenMode", "localhost", "-BackendSelection", "mlx",
                             "-SelectedModelPath", args.model_snapshot,
                             "-MLXModelPath", args.model_snapshot],
                            stdout=open(f"{args.out_dir}/server.log", "ab"),
                            stderr=subprocess.STDOUT, env=env)
    for _ in range(240):
        try:
            urllib.request.urlopen(f"{args.base_url}/health", timeout=2)
            break
        except Exception:
            if proc.poll() is not None:
                stop("进程提前退出（见 server.log）")
            time.sleep(0.5)
    else:
        stop("120s 内 HTTP 面未起")
    ready = False
    for _ in range(1800):
        if os.path.exists(trace):
            with open(trace, "rb") as f:
                f.seek(trace_off)
                if b"[READY]" in f.read():
                    ready = True
                    break
        if proc.poll() is not None:
            stop("进程退出于加载期")
        time.sleep(0.5)
    if not ready:
        stop("15 分钟内未出现 [READY]")
    t_ready = time.time()
    gpath = os.path.join(args.out_dir, "global_load_ledger.jsonl")
    seq = sum(1 for _ in open(gpath)) + 1 if os.path.exists(gpath) else 1
    with open(gpath, "a") as g:
        g.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "seq": seq,
                            "purpose": "baseline-micro", "model": args.model_snapshot,
                            "pid": proc.pid}) + "\n")
    log("model_ready", ledger, global_load_seq=seq)
    return proc, t_ready


def quit_server(proc):
    subprocess.run(["osascript", "-e", 'tell application id "SwiftUI.SimiGo" to quit'],
                   capture_output=True)
    for _ in range(40):
        if proc.poll() is not None:
            return True
        time.sleep(0.5)
    return False


def prod_sha():
    p = os.path.expanduser("~/.simigo/simigo.sqlite3")
    if not os.path.exists(p):
        return "absent"
    return run(["shasum", "-a", "256", p]).stdout.split()[0]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--mode", choices=["manage", "attach"], required=True)
    p.add_argument("--s0-mode", choices=["chat", "stage"], default="chat")
    p.add_argument("--base-url", default=None)
    p.add_argument("--port", type=int, default=8321)
    p.add_argument("--binary", default=None)
    p.add_argument("--model-snapshot", default=None)
    p.add_argument("--model-id", default=None)
    p.add_argument("--home", default=None)
    p.add_argument("--cache-root", default=None)
    p.add_argument("--graph-store", default=None)
    p.add_argument("--db-path", required=True)
    p.add_argument("--work-dir", default=None)
    p.add_argument("--contract-cli", required=True)
    p.add_argument("--out-dir", required=True)
    p.add_argument("--pairs", type=int, default=20)
    p.add_argument("--from", dest="from_pair", type=int, default=0)
    p.add_argument("--phase", choices=["pilot", "extend", "full"], default="full")
    p.add_argument("--max-tokens", type=int, default=512)
    p.add_argument("--seed", type=int, default=20261107)
    p.add_argument("--repo", default=None, help="仓库根，用于 manifest 的 commit/dirty 读数")
    p.add_argument("--domain", default="settlement semantics, retrieval binding, information space")
    p.add_argument("--session-prefix", default="baseline-micro")
    p.add_argument("--stage-value", default="ALPHA BETA GAMMA DELTA")
    p.add_argument("--root-id", default="work")
    p.add_argument("--strict-text-eq", action="store_true",
                   help="R 臂文本==服务值时改硬门（默认记录为协变量）")
    p.add_argument("--keep-server", action="store_true",
                   help="manage 模式结束时不退出服务器（分阶段同一次加载：pilot 后以 "
                        "attach --from N 续跑；收尾须显式 quit + 生产库对账 + 端口检查）")
    args = p.parse_args()

    if args.base_url is None:
        args.base_url = f"http://127.0.0.1:{args.port}"
    if args.model_id is None:
        args.model_id = "baseline-model"
    if args.s0_mode == "stage" and not args_work_dir_ok(args):
        stop("stage 模式需要存在的 --work-dir")
    os.makedirs(args.out_dir, exist_ok=True)
    ledger = open(os.path.join(args.out_dir, "ledger.jsonl"), "a")

    # 契约常量：来自 Swift 真实常量（拒绝脚本侧硬编码猜测）
    cr = run([args.contract_cli, "constants"], timeout=60)
    if cr.returncode != 0:
        stop(f"contract_cli constants 失败: {cr.stderr.strip()[:200]}")
    args.contract_constants = json.loads(cr.stdout)

    manifest = build_manifest(args)
    with open(os.path.join(args.out_dir, "manifest.json"), "w") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    log("manifest_written", ledger, commit=manifest["commit"], mode=args.mode,
        s0_mode=args.s0_mode, seed=args.seed, pairs_plan=args.pairs,
        contract_id=args.contract_constants["contract_id"])

    proc = None
    prod_before = None
    if args.mode == "manage":
        for k in ("binary", "model_snapshot", "home", "cache_root", "graph_store"):
            if not getattr(args, k):
                stop(f"manage 模式缺 --{k.replace('_', '-')}")
        if not args.work_dir or not os.path.isdir(args.work_dir):
            stop("manage 模式需要存在的 --work-dir（root 注册；Run A 先例：库由 PUT roots 创建）")
        prod_before = prod_sha()
        proc, t_ready = manage_server(args, ledger)
        # root 注册 + reconcile（Run A 模式：库由 PUT 创建）
        _, roots_put = http_call("PUT", f"{args.base_url}/v1/simigo/roots",
                                 {"path": args.work_dir}, timeout=30)
        rid = roots_put.get("root_id")
        if not roots_put.get("registered") or not rid:
            stop(f"root 注册失败: {json.dumps(roots_put)[:300]}")
        args.root_id = rid
        _, rec_payload = http_call("POST", f"{args.base_url}/v1/simigo/is/reconcile",
                                   {"category": "work"}, timeout=60)
        if "RECONCILE_FAILED" in json.dumps(rec_payload):
            stop(f"reconcile 失败: {json.dumps(rec_payload)[:300]}")
        log("root_registered", ledger, root_id=rid)
        # [READY] → 首请求 <5s 硬门：记下预算，第一对的第一个请求前检查
        first_gap = time.time() - t_ready
        if first_gap > FIRST_REQUEST_BUDGET_S:
            stop(f"[READY] 到首请求 {first_gap:.1f}s 超出 {FIRST_REQUEST_BUDGET_S}s 硬门"
                 "（P2 纪律：防止加载后空闲挂起）")
        log("first_request_gate", ledger, delta_s=round(first_gap, 2), budget_s=FIRST_REQUEST_BUDGET_S)
        # 首请求硬门已过（本检查即"即时性"证明），后续间隔由 check_gap 管
    else:
        if not args.base_url or not args.db_path:
            stop("attach 模式需要 --base-url 与 --db-path")

    db = DB(args.db_path)
    # 实验库预初始化：stage 模式/全新 home 下，pair 循环的 pre-count 只读查询
    # 需要库文件存在（红案首跑教训：sqlite -readonly 对不存在文件直接失败）。
    if not os.path.exists(args.db_path):
        r = run([args.contract_cli, "init", "--db", args.db_path])
        if r.returncode != 0 or "INIT" not in r.stdout:
            stop(f"实验库初始化失败: {r.stderr.strip()[:200]}")
        log("db_initialized", ledger, path=args.db_path)
    rng = random.Random(args.seed)
    # [预注册随机·第五处缺陷修复] 次序表一次算满全长、按 pair 索引取：
    # 原实现按循环次数消费 rng，pilot+extend 拼成两条独立随机序列，
    # "次序已按 seed 预注册"在分阶段执行时不成立。12/8 类不平衡不调平——
    # 只记录 + 作协变量（用户裁定：手工调平破坏预注册性质）。
    schedule = [rng.sample(["R", "C"], 2) for _ in range(args.pairs)]
    if args.phase == "extend" and args.from_pair == 0:
        stop("--phase extend 必须显式带 --from N（N=pilot 已完成对数，如 3）；"
             "from=0 会把 0..pairs-1 重跑并写入同一账本")
    if args.phase == "pilot":
        lo, hi = 0, 3
    elif args.phase == "extend":
        lo, hi = args.from_pair, args.pairs
    else:
        lo, hi = 0, args.pairs

    pair_recs = []
    try:
        for i in range(lo, hi):
            pre = db.counts()["settlements"]
            rec = execute_pair(i, pre, args, db, ledger, schedule[i])
            pair_recs.append(rec)
            # ok 不能写死：它必须是各臂实测结果的合取，否则下游"复核 ok==true"
            # 是空转（断言一个常量）。execute_pair 失败会走 stop() 抛出，
            # 能走到这里的臂都已通过硬判；把实测读数一并落账，供审计直读。
            log("pair_done", ledger, pair=i, arm_order=rec["arm_order"], ok=rec["ok"],
                c_model_calls=rec["results"]["C"].get("model_calls"),
                value_verified=rec["results"]["C"].get("value_verified"),
                r_answer_reuse_seen=rec["results"]["R"].get("answer_reuse_seen"),
                r_chunks=rec["results"]["R"].get("chunks"))
    except SystemExit:
        raise
    except Exception as e:  # 阶段 3：异常停在已完成整数对，不回补
        log("pair_aborted", ledger, pair=len(pair_recs) + lo, error=repr(e)[:300])
        stop(f"第 {len(pair_recs) + lo} 对异常：{e!r}（已完成 {len(pair_recs)} 对，不回补）")

    r_totals = [pr["results"]["R"]["total_s"] for pr in pair_recs]
    c_totals = [pr["results"]["C"]["total_s"] for pr in pair_recs]
    # 读数是实测的和，不是声明的常数：C 臂取每次响应里的 model_calls，
    # R 臂不可直读（见 results["R"] 注），只报复用标记缺席的合取。
    c_calls = [pr["results"]["C"].get("model_calls") for pr in pair_recs]
    summary = {"pairs_completed": len(pair_recs),
               "R_total_s": {"n": len(r_totals), "min": min(r_totals), "max": max(r_totals)},
               "C_total_s": {"n": len(c_totals), "min": min(c_totals), "max": max(c_totals)},
               "R_ttft_s": {"n": len(r_totals),
                            "min": min(pr["results"]["R"]["ttft_s"] for pr in pair_recs),
                            "max": max(pr["results"]["R"]["ttft_s"] for pr in pair_recs)},
               "model_calls": {
                   "C_observed_per_pair": c_calls,
                   "C_observed_total": sum(c_calls),
                   "R_answer_reuse_absent": all(
                       pr["results"]["R"].get("answer_reuse_seen") is False
                       for pr in pair_recs)}}
    with open(os.path.join(args.out_dir, "summary.json"), "w") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)
    log("summary", ledger, **summary)

    if args.phase == "pilot":
        print("PILOT-DONE: 复核方差后以 --phase extend --from 3 续跑（同一次加载）")
    else:
        print("BASELINE-DONE")

    if proc is not None and not args.keep_server:
        if not quit_server(proc):
            stop("quit 后进程仍存活——停链报告，不得强杀")
        if prod_before != "absent" and prod_sha() != prod_before:
            stop(f"生产库 sha 变化: {prod_before} -> {prod_sha()}")
        listening = subprocess.run(["lsof", "-nP", f"-iTCP:{args.port}", "-sTCP:LISTEN"],
                                   capture_output=True).stdout
        if listening:
            stop("端口未释放")
        log("server_quit_clean", ledger, prod_sha_unchanged=True, port_released=True)
    elif proc is not None and args.keep_server:
        log("server_held", ledger,
            note="pilot 完成、保持加载；extend 以 --mode attach --from 3 续跑；"
                 "收尾须显式 quit + 生产库 sha 对账 + 端口释放检查")


if __name__ == "__main__":
    main()
