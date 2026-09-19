#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V1.7-0 Runtime Benchmark Matrix harness——calibration 版（外审十三轮）。

四路语义（全部走真实 OpenAI 兼容协议，不模拟）：
  Cold     同一完整对话重放到全新 session（全量预填）
  Warm     账本尾 = assistant(normal) 后的小 delta 续跑（→ extend 路径）
  Restore  账本尾 = assistant(tool_calls) + 小 delta tool 结果
           （→ 风险命中 → Conditional Restore fragment）
  Rebuild  活会话首条 user 消息变异 → 账本失配 → fork-no-rewind 全重渲

Calibration（外审十三轮 C1-C4 全落实）：
  C1  Warm 前置轮显式制造 assistant(normal) 尾，再测小 delta
  C2  Restore 完全复用 execution_bench 已验证 recipe：真实 tool_call_id
      （自历史最后 assistant tool_calls 提取，绝不硬编码）
  C3  assistant 回显统一 normalize（tool_calls.function.arguments
      string→object，对齐引擎账本形状；解析失败保持原样不折叠）
  C4  完成行捕获绑定 pos0 + session key（key 自首轮完成行发现）；
      discover 阶段多 session 歧义即报错

用法：
    python3 tools/runtime_matrix.py --plan
    python3 tools/runtime_matrix.py --execute --depths 10000
前置：SimiGo 运行中、无进行中生成、模型与 --model 一致。
"""
import argparse
import json
import os
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


def user(text):
    return {"role": "user", "content": text}


def normalize_assistant(msg):
    """C3：assistant 回显形状归一化——tool_calls.function.arguments
    string → 结构化 object（对齐引擎账本形状，消除 isPrefix 形状分歧）。
    解析失败或结果为标量按原样保留（不制造新折叠，同
    ExecutionPolicy.normalizeJSONStrings 语义）。"""
    calls = msg.get("tool_calls")
    if not calls:
        return msg
    out = dict(msg)
    fixed = []
    for call in calls:
        c = dict(call)
        fn = dict(c.get("function") or {})
        args = fn.get("arguments")
        if isinstance(args, str):
            try:
                parsed = json.loads(args)
                if isinstance(parsed, (dict, list)):
                    fn["arguments"] = parsed
            except (json.JSONDecodeError, ValueError):
                pass
        c["function"] = fn
        fixed.append(c)
    out["tool_calls"] = fixed
    return out


def trace_pos():
    return len(TRACE.read_text(errors="replace").splitlines())


def lines_since(pos):
    return TRACE.read_text(errors="replace").splitlines()[pos:]


def parse_completion(line):
    def g(pat):
        m = re.search(pat, line)
        return m.group(1) if m else None
    return {
        "session": g(r"session=(\S+)"),
        "mode": g(r"mode=(\S+)") or "(fragment)",
        "promptTokens": int(g(r"promptTokens=(\d+)") or 0),
        "promptTimeS": float(g(r"promptTime=([\d.]+)s") or 0),
        "ttftS": round(int(g(r"ttft=(\d+)ms") or 0) / 1000, 1),
        "cacheTokens": int(g(r"cacheTokens=(\d+)") or 0),
        "cacheEff": g(r"cacheEff=([\d.]+)"),
        "reuse": g(r"reuse=(\w+)"),
        "cacheHitTokens": int(g(r"cacheHitTokens=(\d+)") or 0),
        "tps": (lambda v: float(v) if v else None)(g(r"tps=([\d.]+)")),
        "fork": (lambda m: f"{m.group(1)}/{m.group(2)}" if m else None)(
            re.search(r"fork@common=(\d+)/(\d+)", line)),
        "provenance": "measured",
        "captureStatus": "primary",
    }


def derive_completion_degraded(pos0):
    """build 3 起 success-path 完成行被 trim（211aa59），从仍存在的
    [MLX] prefill N/N（N==N 即完成）与 prefillStep 行退化推导。
    mode/promptTime/ttft/cacheEff 不可得 ⇒ None（not-observed，不伪装）；
    restore 命中可用 admission rf=1 + 小 delta prefill 判别。"""
    row = {"session": None, "mode": None, "promptTokens": None,
           "promptTimeS": None, "ttftS": None, "cacheTokens": None,
           "cacheEff": None, "reuse": None, "provenance": "derived-prefill",
           "captureStatus": "degraded-prefill-derived"}
    for line in reversed(lines_since(pos0)):
        m = re.search(r"\[MLX\] prefill (\d+)/(\1)\s*$", line.rstrip())
        if m and row["promptTokens"] is None:
            row["promptTokens"] = int(m.group(1))
        if "prefillStep=" in line and row["reuse"] is None:
            row["reuse"] = re.search(r"reuse=(\w+)", line)
            row["reuse"] = row["reuse"].group(1) if row["reuse"] else None
        if "admission" in line and "rf=1" in line:
            row["rf"] = 1
    return row if row["promptTokens"] is not None else None


def wait_completion(pos0, session_key=None, timeout=180):
    """C4：只接受 pos0 之后、且 session 绑定的新完成行。session_key
    未发现前接受首个完成行并同时返回其 session（供后续绑定）。
    build 3 无完成行时退化到 prefill 行推导（derived-prefill）。"""
    deadline = time.time() + timeout
    polls = 0
    while time.time() < deadline:
        for line in reversed(lines_since(pos0)):
            if "[MLX] session=" not in line or "promptTokens=" not in line:
                continue
            comp = parse_completion(line)
            if session_key and comp["session"] != session_key:
                continue
            comp["stepUsed"] = step_used_since(pos0)
            return comp
        # 完成行落盘竞态宽限（3 轮 ≈1.5s）：响应返回时完成行可能尚未
        # flush，立即走降级会抓到 prefill 行丢 promptTime/mode。
        polls += 1
        if polls > 3:
            degraded = derive_completion_degraded(pos0)
            if degraded:
                degraded["stepUsed"] = step_used_since(pos0)
                return degraded
        time.sleep(0.5)
    return None


def step_used_since(pos0):
    """本请求实际生效的 prefillStep（trace prefillStep= 行，pos0 后最近一条）。"""
    for line in reversed(lines_since(pos0)):
        m = re.search(r"prefillStep=(\d+)", line)
        if m:
            return int(m.group(1))
    return None


def discover_session_key(pos0):
    """C4：从 pos0 后首个完成行发现 traceKey（短串规则不可预测）。"""
    for line in reversed(lines_since(pos0)):
        if "[MLX] session=" in line and "promptTokens=" in line:
            m = re.search(r"session=(\S+)", line)
            if m:
                return m.group(1)
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
    m = re.search(r"used = ([\d.]+)([GM])", out)
    if not m:
        return None
    v = float(m.group(1))
    return v if m.group(2) == "G" else v / 1024


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
    msg = data["choices"][0]["message"]
    return msg, wall, pos0


def filler(tag, chars):
    unit = f"[{tag}] runtime matrix depth calibration block. "
    return (unit * (chars // len(unit) + 1))[:chars]


def last_tool_call_id(messages):
    """C2：自历史最后 assistant tool_calls 提取真实 id，绝不硬编码。"""
    for m in reversed(messages):
        if m.get("role") == "assistant" and m.get("tool_calls"):
            return m["tool_calls"][0].get("id")
    return None


def build_to_depth(session_id, depth_tokens):
    """record_note 工具流推深；assistant 回显逐条 normalize（C3）。"""
    messages = [user("请调用 record_note 记录笔记:标题 bench-start,priority 1,tag cold。")]
    tools = [NOTE_TOOL]
    samples = []
    depth = 0
    i = 0
    session_key = None
    while depth < depth_tokens:
        i += 1
        call_id = last_tool_call_id(messages) or "call_bench"
        messages.append({"role": "tool", "tool_call_id": call_id,
                         "content": filler(f"B{i}", 40_000)})
        messages.append(user("已收到,请再次调用 record_note 记一条新笔记继续。"))
        # C5：build 轮 max_tokens 须容得下完整 tool_calls（record_note
        # arguments ≈30+ tok）；16 会截断且引擎丢弃不完整 tool_calls，
        # 历史零 tool_calls → C2 扫空 → restore 退化为第四个 cold
        msg, wall, pos0 = chat(session_id, messages, tools=tools, max_tokens=64)
        messages.append(normalize_assistant(msg))
        comp = wait_completion(pos0, session_key=session_key)
        session_key = session_key or discover_session_key(pos0)
        comp = comp or {}
        samples.append({"round": i, "wallS": wall, **comp})
        depth += comp.get("promptTokens") or 0
        ti = comp.get("promptTimeS")
        ti = "?" if ti is None else f"{ti}s"
        print(f"  [build r{i}] wall={wall}s promptTokens={comp.get('promptTokens'):,} "
              f"promptTime={ti} mode={comp.get('mode') or '?'}", flush=True)
    return messages, tools, samples, session_key


def measure_tier(depth, store):
    session = f"rm{depth}"
    print(f"\n===== 深度档 {depth} tokens =====", flush=True)
    tier = {"depthTokensTarget": depth}

    # 1) 构建推深（restore-flavored 轮）
    messages, tools, build, session_key = build_to_depth(session, depth)
    tier["build"] = build

    # 2) RESTORE 测量（C6：必须先于 warm_setup——rollforwardRisk 只认
    #    账本尾 assistant(tool_calls)（ExecutionPolicy），warm_setup 的
    #    normal 尾会洗掉风险尾使 restore 恒退化 cold（rmc5v/rmc5w 双向
    #    实证：先测 2.1s/617tok/rf=1，洗尾后 26.8s/18616tok 全量）。
    #    C5 后 build 尾 assistant 恰带完整 tool_calls，此刻是唯一合法
    #    测点。回复提示词不索要工具调用：16 tok 下截断的 tool_calls 会
    #    自造畸异尾，把下一轮 warm_setup 打成全量 rebuild。
    call_id = last_tool_call_id(messages)
    m3 = list(messages)
    m3.append({"role": "tool", "tool_call_id": call_id or "call_bench",
               "content": filler("R", 400)})
    m3.append(user("已收到。请只回复:OK"))
    restore_msg, restore_wall, restore_pos = chat(session, m3,
                                                  tools=[NOTE_TOOL],
                                                  max_tokens=16)
    restore_c = wait_completion(restore_pos, session_key)
    tier["restore"] = {"wallS": restore_wall, "trace": restore_c,
                       "toolCallId": call_id}
    m_ledger = list(m3)
    m_ledger.append(normalize_assistant(restore_msg))

    # 3) C1：Warm 前置轮——制造 assistant(normal) 尾（此后账本尾无
    #    tool_calls，下一条小 delta 才是合法 extend 基线）
    m_plain = list(m_ledger)
    m_plain.append(user("不要调用工具,只回复:OK"))
    msg, wall, pos0 = chat(session, m_plain, max_tokens=8)
    m_plain.append(normalize_assistant(msg))
    plain_c = wait_completion(pos0, session_key)
    tier["warm_setup"] = {"wallS": wall, "trace": plain_c}

    # 4) WARM 测量：assistant(normal) 尾 + 小 delta → extend
    pos0 = trace_pos()
    m2 = list(m_plain)
    m2.append(user("只回复:OK"))
    t0 = time.time()
    with urllib.request.urlopen(urllib.request.Request(
            BASE, data=json.dumps({"model": MODEL, "session_id": session,
                                   "messages": m2, "max_tokens": 8,
                                   "temperature": 0}).encode(),
            headers={"Content-Type": "application/json"}),
            timeout=1800) as r:
        json.loads(r.read())
    warm_c = wait_completion(pos0, session_key)
    tier["warm"] = {"wallS": round(time.time() - t0, 1), "trace": warm_c}

    # 5) REBUILD：首条 user 变异 → 账本失配 → 全量重渲
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
    rebuild_c = wait_completion(pos0, session_key)
    tier["rebuild"] = {"wallS": round(time.time() - t0, 1), "trace": rebuild_c}

    # 6) COLD：同一完整对话重放到全新 session
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

    def pt(key):
        t = tier[key].get("trace") or {}
        v = t.get("promptTimeS")
        if v is None:
            v = tier[key].get("wallS")
        return v
    print(f"  [{depth}] warm={pt('warm')}s restore={pt('restore')}s "
          f"rebuild={pt('rebuild')}s cold={pt('cold')}s "
          f"ram={tier['memory']['footprintGB']}G swap={tier['memory']['swapGB']}G",
          flush=True)


def experiment_meta():
    """P2 可复现性：每份结果 JSON 记录 step policy 与构建身份。"""
    meta = {"stepOverrideEnv": os.environ.get("SIMIGO_PREFILL_STEP_EXP"),
            "stepFile": None, "binaryBuild": None, "generatedAt":
            time.strftime("%Y-%m-%dT%H:%M:%S")}
    exp_file = Path.home() / ".simigo/prefill_step_exp"
    if exp_file.exists():
        meta["stepFile"] = exp_file.read_text().strip()
    for app in (Path("build/SimiGo.app/Contents/Info.plist"),
                Path("/Applications/SimiGo.app/Contents/Info.plist")):
        if app.exists():
            try:
                import plistlib
                meta["binaryBuild"] = plistlib.load(
                    open(app, "rb")).get("CFBundleVersion")
                meta["binaryPath"] = str(app)
                break
            except Exception:
                pass
    return meta


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
            print(f"档位 {d}: build → restore(风险尾未洗) → warm 前置(normal 尾) → "
                  f"warm(extend) → rebuild → cold")
        return

    store = {}
    for d in depths:
        measure_tier(d, store)
        out = args.json_out or "docs/experiments/V17_RUNTIME_MATRIX/results_v2.json"
        Path(out).parent.mkdir(parents=True, exist_ok=True)
        Path(out).write_text(json.dumps(
            {"model": MODEL, "depths": depths, "meta": experiment_meta(),
             "results": store},
            ensure_ascii=False, indent=1))
        print(f"[checkpoint] 已写 {out}", flush=True)


if __name__ == "__main__":
    main()
