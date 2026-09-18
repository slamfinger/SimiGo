#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V1.7-0 Runtime Benchmark Harness（外审战略 V1.7-0，2026-09-19）。

按深度档系统化测量 Runtime 四路真实成本，产出证据矩阵
（场景 × Tokens × Cold/Warm/Restore/Rebuild × RAM/KV/Swap）。

四路语义（全部走真实 OpenAI 兼容协议，不模拟）：
  Cold     同一完整对话重放到全新 session（全量预填）
  Warm     活会话小 delta 续跑（账本前缀一致，无 tool_calls 风险 → extend）
  Restore  账本尾 assistant tool_calls 风险 + 小 delta → Conditional
           Restore fragment（复用生成路径真实触发，非模拟）
  Rebuild  活会话首条 user 消息变异 → 账本失配 → fork-no-rewind 全重渲

完成行捕获：位置法（请求前 trace 行数之后的新完成行），同
execution_bench 外审四轮修复；顺序驱动下即本请求完成行。

用法：
    python3 tools/runtime_matrix.py --plan
    python3 tools/runtime_matrix.py --execute --depths 10000
    python3 tools/runtime_matrix.py --execute --depths 10000,40000,80000,120000
前置：SimiGo 运行中、无进行中生成、模型与 --model 一致。
"""
import argparse
import json
import re
import subprocess
import time
import urllib.request
from pathlib import Path

BASE = "http://127.0.0.1:8000/v1/chat/completions"
MODEL = "peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e"
TRACE = Path.home() / ".simigo/logs/native_mlx_trace.log"
NOTE_TOOL = {
    "type": "function",
    "function": {
        "name": "record_note",
        "description": "记录笔记",
        "parameters": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "priority": {"type": "number"},
                "tag": {"type": "string"},
            },
            "required": ["title", "priority", "tag"],
        },
    },
}


def trace_pos():
    return len(TRACE.read_text(errors="replace").splitlines())


def wait_completion(pos0, timeout=180):
    """位置法：只接受 pos0 之后的新 [MLX] 完成行（外审四轮修复同源）。"""
    deadline = time.time() + timeout
    while time.time() < deadline:
        for line in reversed(TRACE.read_text(errors="replace").splitlines()[pos0:]):
            if "[MLX] session=" in line and "promptTokens=" in line:
                def g(pat):
                    m = re.search(pat, line)
                    return m.group(1) if m else None
                return {
                    "mode": g(r"mode=(\S+)") or "(fragment)",
                    "promptTokens": int(g(r"promptTokens=(\d+)") or 0),
                    "promptTimeS": float(g(r"promptTime=([\d.]+)s") or 0),
                    "ttftS": round(int(g(r"ttft=(\d+)ms") or 0) / 1000, 1),
                    "cacheTokens": int(g(r"cacheTokens=(\d+)") or 0),
                    "cacheEff": g(r"cacheEff=([\d.]+)"),
                    "reuse": g(r"reuse=(\w+)"),
                }
        time.sleep(0.5)
    return None


def footprint_gb():
    pid = subprocess.run(["pgrep", "-x", "SimiGo"],
                         capture_output=True, text=True).stdout.split()
    if not pid:
        return None
    out = subprocess.run(["vmmap", "--summary", pid[0]],
                         capture_output=True, text=True).stdout
    m = re.search(r"Physical footprint:\s+([\d.]+)G", out)
    return float(m.group(1)) if m else None


def swap_gb():
    out = subprocess.run(["sysctl", "-n", "vm.swapusage"],
                         capture_output=True, text=True).stdout
    m = re.search(r"used = ([\d.]+)G", out)
    return float(m.group(1)) if m else None


def chat(session_id, messages, tools=None, max_tokens=16, timeout=1800):
    body = {"model": MODEL, "session_id": session_id,
            "messages": messages, "tools": tools,
            "max_tokens": max_tokens, "temperature": 0.0}
    req = urllib.request.Request(
        BASE, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"})
    pos0 = trace_pos()
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = json.loads(r.read())
    wall = round(time.time() - t0, 1)
    comp = wait_completion(pos0)
    msg = data["choices"][0]["message"]
    return msg, wall, comp


def user(text):
    return {"role": "user", "content": text}


def filler(tag, chars):
    unit = f"[{tag}] runtime matrix depth calibration block. "
    return (unit * (chars // len(unit) + 1))[:chars]


def build_to_depth(session_id, depth_tokens):
    """record_note 工具流推深（restore-flavored 轮），返回 messages/采样。"""
    messages = [user("请调用 record_note 记录笔记:标题 bench-start,priority 1,tag cold。")]
    tools = [NOTE_TOOL]
    samples = []
    depth = 0
    i = 0
    while depth < depth_tokens:
        i += 1
        call_id = "call_bench"
        if messages[-1].get("tool_calls"):
            call_id = messages[-1]["tool_calls"][0].get("id", call_id)
        messages.append({"role": "tool", "tool_call_id": call_id,
                         "content": filler(f"B{i}", 40_000)})
        messages.append(user("已收到,请再次调用 record_note 记一条新笔记继续。"))
        msg, wall, comp = chat(session_id, messages, tools=tools)
        messages.append(msg)
        comp = comp or {}
        samples.append({"round": i, "wallS": wall, **comp})
        depth += comp.get("promptTokens") or 0
        print(f"  [build r{i}] wall={wall}s promptTokens={comp.get('promptTokens'):,} "
              f"promptTime={comp.get('promptTimeS')}s mode={comp.get('mode')}", flush=True)
    return messages, tools, samples


def plain_round(session_id, messages, content, max_tokens=8):
    """无工具小 delta 轮（WARM/REBUILD/COLD 测量用）。"""
    messages.append(user(content))
    msg, wall, comp = chat(session_id, messages, max_tokens=max_tokens)
    messages.append(msg)
    return wall, comp


def measure_tier(depth, store):
    session = f"rm{depth}"
    print(f"\n===== 深度档 {depth} tokens =====", flush=True)
    tier = {"depthTokensTarget": depth}

    # 1) 构建（restore-flavored 推深）
    messages, tools, build = build_to_depth(session, depth)
    tier["build"] = build

    # 2) WARM：无 tool_calls 尾 + 小 delta → extend 路径
    m2 = list(messages)
    w = user("不要调用工具,只回复:OK")
    pos0 = trace_pos()
    m2.append(w)
    t0 = time.time()
    with urllib.request.urlopen(urllib.request.Request(
            BASE, data=json.dumps({"model": MODEL, "session_id": session,
                                   "messages": m2, "max_tokens": 8,
                                   "temperature": 0}).encode(),
            headers={"Content-Type": "application/json"}),
            timeout=1800) as r:
        json.loads(r.read())
    warm_c = wait_completion(pos0)
    tier["warm"] = {"wallS": round(time.time() - t0, 1), "trace": warm_c}

    # 3) RESTORE：tool_calls 尾 + 小 delta → 风险命中 → fragment 恢复
    m3 = list(messages)
    m3.append({"role": "tool", "tool_call_id": "call_bench",
               "content": filler("R", 400)})
    m3.append(user("已收到,请调用 record_note 记一条:tag restore。"))
    pos0 = trace_pos()
    t0 = time.time()
    with urllib.request.urlopen(urllib.request.Request(
            BASE, data=json.dumps({"model": MODEL, "session_id": session,
                                   "messages": m3, "tools": [NOTE_TOOL],
                                   "max_tokens": 16,
                                   "temperature": 0}).encode(),
            headers={"Content-Type": "application/json"}),
            timeout=1800) as r:
        json.loads(r.read())
    restore_c = wait_completion(pos0)
    tier["restore"] = {"wallS": round(time.time() - t0, 1), "trace": restore_c}

    # 4) REBUILD：首条 user 变异 → 账本失配 → 全量重渲
    m4 = [dict(messages[0])]
    m4[0] = dict(m4[0])
    m4[0]["content"] = m4[0]["content"] + " [mutated]"
    m4.extend(messages[1:])
    pos0 = trace_pos()
    t0 = time.time()
    with urllib.request.urlopen(urllib.request.Request(
            BASE, data=json.dumps({"model": MODEL, "session_id": session,
                                   "messages": m4, "max_tokens": 8,
                                   "temperature": 0}).encode(),
            headers={"Content-Type": "application/json"}),
            timeout=1800) as r:
        json.loads(r.read())
    rebuild_c = wait_completion(pos0)
    tier["rebuild"] = {"wallS": round(time.time() - t0, 1), "trace": rebuild_c}

    # 5) COLD：同一完整对话重放到全新 session
    pos0 = trace_pos()
    t0 = time.time()
    with urllib.request.urlopen(urllib.request.Request(
            BASE, data=json.dumps({"model": MODEL, "session_id": f"rm{depth}cold",
                                   "messages": messages, "max_tokens": 8,
                                   "temperature": 0}).encode(),
            headers={"Content-Type": "application/json"}),
            timeout=1800) as r:
        json.loads(r.read())
    cold_c = wait_completion(pos0)
    tier["cold"] = {"wallS": round(time.time() - t0, 1), "trace": cold_c}

    tier["memory"] = {"footprintGB": footprint_gb(), "swapGB": swap_gb()}
    store[f"depth{depth}"] = tier

    warm_t = (tier["warm"]["trace"] or {}).get("promptTimeS")
    restore_t = (tier["restore"]["trace"] or {}).get("promptTimeS")
    rebuild_t = (tier["rebuild"]["trace"] or {}).get("promptTimeS")
    cold_t = (tier["cold"]["trace"] or {}).get("promptTimeS")
    print(f"  [{depth}] warm={warm_t}s restore={restore_t}s "
          f"rebuild={rebuild_t}s cold={cold_t}s "
          f"ram={tier['memory']['footprintGB']}G swap={tier['memory']['swapGB']}G",
          flush=True)


def main():
    ap = argparse.ArgumentParser(description="V1.7-0 runtime benchmark matrix")
    ap.add_argument("--plan", action="store_true")
    ap.add_argument("--execute", action="store_true")
    ap.add_argument("--depths", default="10000,40000,80000,120000")
    ap.add_argument("--json-out", default=None)
    args = ap.parse_args()
    depths = [int(x) for x in args.depths.split(",") if x.strip()]

    if args.plan or not args.execute:
        for d in depths:
            print(f"档位 {d}: build(推深) → warm(extend) → restore(fragment) "
                  f"→ rebuild(首消息变异) → cold(全新 session 重放)")
        return

    store = {}
    for d in depths:
        measure_tier(d, store)
        out = args.json_out or "docs/experiments/V17_RUNTIME_MATRIX/results_partial.json"
        Path(out).parent.mkdir(parents=True, exist_ok=True)
        Path(out).write_text(json.dumps(
            {"model": MODEL, "depths": depths, "results": store},
            ensure_ascii=False, indent=1))
        print(f"[checkpoint] 已写 {out}", flush=True)


if __name__ == "__main__":
    main()
