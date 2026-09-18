#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Execution Continuity 合并 harness(实验 A≡B,2026-09-18 定稿)。

因子矩阵 v1:深度(轮次累积)× 路径(restore/extend,由 Conditional Restore 的
delta 门自然分派)× delta 规模(ASCII 填充精确控形,chars/4 估算≈真值)。
状态形态(v1 仅 derived)与步长扫描留待后续;六条 fork 边界由既有单测封口,
此处不重复。

驱动方式:rfdiag 同款——OpenAI 兼容 /v1/chat/completions,固定 session_id,
record_note 三键工具(多键 ⇒ rollforwardRisk 形状命中),非流式。
restore 臂 = 小填充(400 字符,delta 门放行);extend 臂 = 大填充(40k 字符,
est≈10k tok > 8192 ⇒ 门拒 → extend)。extend 臂即「同深度 live-extend 对照」
——灰度首夜缺失的那个数据点。

度量源:trace 完成行(mode/promptTokens/promptTime/ttft/cacheEff/cacheTokens)
+ admission 行 swap + 驱动侧 wall + sysctl vm.swapusage / 进程 RSS。

前置:SimiGo 运行中、无进行中生成(最后一条 LC 行为 RELEASED)。
用法:
    python3 tools/execution_bench.py --plan          # 打印轮次计划不执行
    python3 tools/execution_bench.py --execute       # 执行并写结果 JSON
    python3 tools/execution_bench.py --execute --max-depth 60000
"""
import argparse
import glob
import json
import re
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

BASE = "http://127.0.0.1:8000/v1/chat/completions"
MODEL = "peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e"
SESSION = "ecbench"
TRACE = Path.home() / ".simigo/logs/native_mlx_trace.log"

TOOLS = [{
    "type": "function",
    "function": {
        "name": "record_note",
        "description": "记录一条笔记",
        "parameters": {
            "type": "object",
            "properties": {
                "title": {"type": "string"},
                "priority": {"type": "integer"},
                "tag": {"type": "string"},
            },
            "required": ["title", "priority", "tag"],
        },
    },
}]

SESSION_LINE = re.compile(
    r"\[(?P<ts>[^\]]+)\] \[MLX\] session=\S*{}[^ ]* messages=\d+ history=\d+ ".format(SESSION))


def filler(n_chars, tag):
    """ASCII 填充:chars/4 估算≈真值,内嵌轮次标记防编译器式去重幻想。"""
    unit = f"[{tag}] lorem ipsum execution continuity benchmark block. "
    return (unit * (n_chars // len(unit) + 1))[:n_chars]


def preflight():
    r = subprocess.run(["pgrep", "-x", "SimiGo"], capture_output=True, text=True)
    if not r.stdout.strip():
        sys.exit("preflight 失败:SimiGo 未运行")
    tail = TRACE.read_text(errors="replace").splitlines()[-40:]
    lc = [ln for ln in tail if "[LC]" in ln]
    if lc and (" to=RUNNING" in lc[-1] or "CANCELLING" in lc[-1]):
        sys.exit(f"preflight 失败:有进行中的生成:{lc[-1][:100]}")
    print("preflight ✓ app 运行中,无进行中生成")


def chat_round(messages, max_tokens=512, timeout=900):
    body = {
        "model": MODEL, "session_id": SESSION, "messages": messages,
        "tools": TOOLS, "max_tokens": max_tokens, "temperature": 0.0,
    }
    req = urllib.request.Request(
        BASE, data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        out = json.load(r)
    return out["choices"][0]["message"], time.time() - t0


def trace_tail_lines(n=400):
    return TRACE.read_text(errors="replace").splitlines()[-n:]


def last_completion(timeout=15):
    """等待并返回本 session 最新完成行的解析字段。"""
    deadline = time.time() + timeout
    while time.time() < deadline:
        for line in reversed(trace_tail_lines()):
            if "session=" in line and SESSION in line and "promptTokens=" in line:
                def g(pat):
                    m = re.search(pat, line)
                    return m.group(1) if m else None
                return {
                    "mode": g(r"mode=(\S+)") or "fragment",
                    "promptTokens": int(g(r"promptTokens=(\d+)") or 0),
                    "promptTimeS": float(g(r"promptTime=([\d.]+)s") or 0),
                    "ttftS": round(int(g(r"ttft=(\d+)ms") or 0) / 1000, 1),
                    "cacheTokens": int(g(r"cacheTokens=(\d+)") or 0),
                    "cacheEff": g(r"cacheEff=([\d.]+)"),
                }
        time.sleep(2)
    return None


def mem_snapshot():
    swap = subprocess.run(["sysctl", "-n", "vm.swapusage"],
                          capture_output=True, text=True).stdout.strip()
    pid = subprocess.run(["pgrep", "-x", "SimiGo"],
                         capture_output=True, text=True).stdout.split()
    rss = ""
    if pid:
        rss = subprocess.run(["ps", "-o", "rss=", "-p", pid[0]],
                             capture_output=True, text=True).stdout.strip()
    return {"swap": swap, "appRSSKB": rss}


def build_plan(max_depth):
    """E/R 交替:extend 臂(40k 字符)推深度并给出 live-extend 对照,
    restore 臂(400 字符)测恢复态 delta eval。"""
    plan, depth = [], 17_500  # cold 轮后起点(17.5k 系统提示+首问)
    arms = [("E", 40_000), ("R", 400)]
    i = 0
    while depth < max_depth:
        arm, size = arms[i % 2]
        plan.append({"arm": arm, "fillerChars": size, "depthEst": depth})
        if arm == "E":
            depth += 10_000
        else:
            depth += 150
        i += 1
    return plan


def main():
    ap = argparse.ArgumentParser(description="Execution Continuity harness")
    ap.add_argument("--plan", action="store_true", help="只打印轮次计划")
    ap.add_argument("--execute", action="store_true")
    ap.add_argument("--max-depth", type=int, default=90_000,
                    help="cacheTokens 深度预算(默认 90k)")
    ap.add_argument("--json-out", default=None)
    args = ap.parse_args()

    plan = build_plan(args.max_depth)
    print(f"轮次计划:{len(plan) + 1} 轮(cold 预热 1 轮 + E/R 交替)")
    for i, p in enumerate(plan):
        print(f"  R{i + 1}: {p['arm']} 臂 filler={p['fillerChars']} 字符 "
              f"@ 深度≈{p['depthEst']:,}")
    if args.plan or not args.execute:
        return

    preflight()
    results, notes = [], []

    # cold 预热轮:建账本,不进对比
    user0 = "请调用 record_note 工具记录一条笔记,标题为 bench-start,priority 1,tag cold。"
    msgs = [{"role": "user", "content": user0}]
    print("\n[cold] 预热轮(可能含模型加载)…", flush=True)
    asst, wall = chat_round(msgs)
    msgs.append(asst)
    print(f"[cold] wall={wall:.1f}s tool_calls={'yes' if asst.get('tool_calls') else 'no'}")

    for i, step in enumerate(plan):
        arm, size = step["arm"], step["fillerChars"]
        tc = (asst.get("tool_calls") or [{}])[0]
        call_id = tc.get("id", "call_bench")
        tool_msg = {"role": "tool", "tool_call_id": call_id,
                    "content": filler(size, f"R{i + 1}")}
        msgs.append(tool_msg)
        msgs.append({"role": "user",
                     "content": "已收到工具结果,请再次调用 record_note 记录一条新笔记继续任务。"})
        before_lines = len(trace_tail_lines(2000))
        mem0 = mem_snapshot()
        asst, wall = chat_round(msgs)
        comp = last_completion()
        mem1 = mem_snapshot()
        row = {"round": i + 1, "arm": arm, "fillerChars": size,
               "wallS": round(wall, 1), "trace": comp,
               "mem0": mem0, "mem1": mem1,
               "toolCalls": "yes" if asst.get("tool_calls") else "no"}
        results.append(row)
        c = comp or {}
        print(f"[R{i + 1} {arm}] wall={wall:.1f}s mode={c.get('mode')} "
              f"promptTokens={c.get('promptTokens'):,} "
              f"promptTime={c.get('promptTimeS')}s ttft={c.get('ttftS')}s "
              f"depth(cacheTokens)={c.get('cacheTokens'):,} "
              f"cacheEff={c.get('cacheEff')} swap1={mem1['swap']}", flush=True)
        if not asst.get("tool_calls"):
            notes.append(f"R{i + 1}:模型未再调用工具,任务视为完成,提前收尾")
            break

    # 连续性检查:promote 后会话可用(A-intact 生产形态)
    msgs.append({"role": "user", "content": "用一句话说明你记录了几条笔记。不要调用工具。"})
    asst, wall = chat_round(msgs, max_tokens=128)
    continuity = {"wallS": round(wall, 1),
                  "contentHead": str(asst.get("content"))[:120]}
    print(f"[continuity] wall={wall:.1f}s content={continuity['contentHead']}")

    out = {"session": SESSION, "model": MODEL, "plan": plan,
           "results": results, "continuity": continuity, "notes": notes}
    dest = args.json_out
    if not dest:
        d = Path("docs/experiments/BENCH_EXEC_CONTINUITY_20260918")
        d.mkdir(parents=True, exist_ok=True)
        dest = str(d / "results.json")
    Path(dest).write_text(json.dumps(out, ensure_ascii=False, indent=1))
    print(f"\n结果已写 {dest}")


if __name__ == "__main__":
    main()
