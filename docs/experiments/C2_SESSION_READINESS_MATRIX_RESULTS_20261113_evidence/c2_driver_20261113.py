#!/usr/bin/env python3
"""C2 Session Readiness 矩阵驱动（build 60 产品路径）。

不变量：引擎生成窗口串行（requestAdmission level=1）⇒ 我方 grant（[LC]
STATE_TRANSITION to=RUNNING）之后、我方收尾行（[MLX] session=…）之前的
prefill 进度行必属我轮。断连=detach（孤儿名额 1），新请求进准入即触发
yieldDetachedOrphansForContention ⇒ 在途孤儿在预填循环 chunk 边界被硬取消。
"""
import argparse, json, os, subprocess, sys, time, re, urllib.request

BASE = "http://127.0.0.1:8000"
TRACE = os.path.expanduser("~/.simigo/logs/native_mlx_trace.log")
ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), "c2_artifacts")
AGENT = "c2matrix"

FILLER = "The quick brown fox jumps over the lazy dog near the river bank. "
NONCE_TPL = "C2EXP marker={marker} unique-run token.\n"


def filler_text(tok_target: int, marker: str) -> str:
    # ~0.21 tok/char 实测口径；宁多勿少，实际读数以 trace promptTokens 为准
    chars = int(tok_target / 0.21)
    body = (FILLER * (chars // len(FILLER) + 1))[:chars]
    return body + "\n" + NONCE_TPL.format(marker=marker) + "\nAnswer with exactly: OK"


def trace_size() -> int:
    return os.path.getsize(TRACE)


def trace_since(offset: int) -> str:
    with open(TRACE, "rb") as f:
        f.seek(offset)
        return f.read().decode("utf-8", "replace")


def post_chat(payload: dict, out_path: str, max_time: int) -> subprocess.Popen:
    cmd = ["curl", "-sS", "--max-time", str(max_time), "-X", "POST",
           f"{BASE}/v1/chat/completions", "-H", "Content-Type: application/json",
           "-H", f"X-SimiGo-Agent: {AGENT}", "-d", json.dumps(payload), "-o", out_path,
           "-w", "%{http_code}"]
    return subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)


def build_payload(session: str, tok_target: int, marker: str, max_tokens: int = 60):
    return {
        "model": "simigo",
        "stream": False,
        "max_tokens": max_tokens,
        "session_id": session,
        "messages": [{"role": "user", "content": filler_text(tok_target, marker)}],
    }


def build_followup_payload(session: str, tok_base: int, marker: str, tok_delta: int,
                           prior_content: str, max_tokens: int = 60):
    """E 格第二轮：同 key 续接 + 大 delta（U2 长 filler），首条消息不变。"""
    return {
        "model": "simigo",
        "stream": False,
        "max_tokens": max_tokens,
        "session_id": session,
        "messages": [
            {"role": "user", "content": filler_text(tok_base, marker)},
            {"role": "assistant", "content": prior_content},
            {"role": "user", "content": filler_text(tok_delta, marker + "-u2")
             + "\nAnswer with exactly: OK2"},
        ],
    }


def build_followup(session: str, prior: dict, tok_target: int, marker: str, max_tokens: int = 60):
    """同 key 续接：保留首条消息（mapKey 成分之一），追加历史与新消息。"""
    msgs = list(prior["messages"])
    msgs.append({"role": "assistant", "content": "OK"})
    msgs.append({"role": "user",
                 "content": NONCE_TPL.format(marker=marker) + "Answer with exactly: OK2"})
    if tok_target > 0:
        msgs[-1]["content"] = filler_text(tok_target, marker) + "\nAnswer with exactly: OK2"
    return {"model": "simigo", "stream": False, "max_tokens": max_tokens,
            "session_id": session, "messages": msgs}


def wait_running(offset: int, deadline: float, session: str) -> str | None:
    """等待我方 grant：[LC] STATE_TRANSITION r=<r> s=<session 前6位> … to=RUNNING。
    （[ADMIT] grant 行的 agent 恒为 default，不能用作锚点。）"""
    tag = session[:6]
    pat = re.compile(r"\[LC\] STATE_TRANSITION (r=\S+) s=" + re.escape(tag) + r" from=QUEUED to=RUNNING")
    while time.time() < deadline:
        seg = trace_since(offset)
        m = pat.findall(seg)
        if m:
            return m[-1]
        time.sleep(0.12)
    return None


def wait_completion(offset: int, deadline: float):
    """等待我方收尾行（agent 域内出现 [LC] RELEASED r=<my r>）。返回 (released行, session行)。"""
    pat_re = re.compile(r".*")
    while time.time() < deadline:
        seg = trace_since(offset)
        return seg  # 调用方自己正则解析
    return ""


def poll_kill_midprefill(offset: int, r_grant: str, proc: subprocess.Popen,
                         deadline: float, poll_log: list) -> bool:
    """我 grant 后：出现 prefill N/M（N<M）进度行即杀 curl（断连→detach）。"""
    while time.time() < deadline:
        seg = trace_since(offset)
        # 我 grant 之后的内容
        idx = seg.find(r_grant)
        if idx >= 0:
            after = seg[idx:]
            for m in re.finditer(r"\[MLX\] prefill (\d+)/(\d+)", after):
                n, total = int(m.group(1)), int(m.group(2))
                if n < total:
                    proc.kill()
                    poll_log.append(f"killed_at prefill {n}/{total}")
                    return True
            if re.search(r"\[LC\] RELEASED", after):
                poll_log.append("already_released_before_kill")
                return False
        if proc.poll() is not None:
            poll_log.append("curl_exited_before_kill")
            return False
        time.sleep(0.12)
    poll_log.append("deadline_in_watch")
    proc.kill()
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["send", "follow", "start-cancel", "contend", "census", "since", "waitidle"])
    ap.add_argument("--session", default="c2probe")
    ap.add_argument("--tokens", type=int, default=0)
    ap.add_argument("--marker", default=None)
    ap.add_argument("--maxtok", type=int, default=60)
    ap.add_argument("--out", default=None)
    ap.add_argument("--maxtime", type=int, default=420)
    ap.add_argument("--offset", type=int, default=0)
    ap.add_argument("--seconds", type=int, default=250)
    ap.add_argument("--pidfile", default=None)
    ap.add_argument("--prior", default=None)
    ap.add_argument("--follow", action="store_true")
    ap.add_argument("--basetokens", type=int, default=0)
    ap.add_argument("--delay", type=float, default=0.0)
    ap.add_argument("--killdelay", type=float, default=0.0,
                    help=">0 时按墙钟定时杀（trace 落盘滞后，轮询不可靠）")
    args = ap.parse_args()

    os.makedirs(ART, exist_ok=True)
    marker = args.marker or f"{args.session}-{int(time.time())}"
    off = trace_size()

    if args.cmd == "send":
        # 同步小轮；--tokens>0 时为长内容
        payload = build_payload(args.session, args.tokens, marker, args.maxtok)
        out = args.out or os.path.join(ART, f"resp-{args.session}-{int(time.time())}.json")
        t0 = time.time()
        p = post_chat(payload, out, args.maxtime)
        code = p.communicate(timeout=args.maxtime + 30)[0].decode().strip()
        print(json.dumps({"r": code, "wall_s": round(time.time() - t0, 1), "out": out,
                          "offset": off}, ensure_ascii=False))
    elif args.cmd == "follow":
        # 同 key 续接轮：以相同 marker/tokens 重建首条消息，
        # assistant 位必须用上轮真实产出（isPrefix 逐字节比对）
        base = build_payload(args.session, args.tokens, marker, args.maxtok)
        prior_content = "OK"
        if args.prior and os.path.exists(args.prior):
            with open(args.prior) as f:
                body = json.load(f)
            prior_content = body["choices"][0]["message"]["content"]
        payload = build_followup(args.session, base, args.tokens, marker + "-u2", args.maxtok)
        payload["messages"][1]["content"] = prior_content
        out = args.out or os.path.join(ART, f"follow-{args.session}-{int(time.time())}.json")
        t0 = time.time()
        p = post_chat(payload, out, args.maxtime)
        code = p.communicate(timeout=args.maxtime + 30)[0].decode().strip()
        print(json.dumps({"r": code, "wall_s": round(time.time() - t0, 1), "out": out,
                          "offset": off, "prior_bytes": len(prior_content or "")},
                         ensure_ascii=False))
    elif args.cmd == "start-cancel":
        # 启动长轮（后台）→ 等 grant → 出现 prefill N/M 即杀 → 等 RELEASED → 打包证据
        # --follow 时发 E 格续接 payload（复用轮大 delta），其余发首转 payload
        if args.follow:
            prior_content = "OK"
            if args.prior and os.path.exists(args.prior):
                with open(args.prior) as f:
                    prior_content = json.load(f)["choices"][0]["message"]["content"]
            payload = build_followup_payload(args.session, args.basetokens, marker,
                                             args.tokens, prior_content, args.maxtok)
        else:
            payload = build_payload(args.session, args.tokens, marker, args.maxtok)
        out = args.out or os.path.join(ART, f"cancel-{args.session}-{int(time.time())}.json")
        p = post_chat(payload, out, args.maxtime)
        grant = None
        poll_log = []
        killed = False
        if args.killdelay > 0:
            # 墙钟定时杀：发送后固定秒数断连（预填中），随后由 contend 触发让位
            time.sleep(args.killdelay)
            p.kill()
            killed = True
            poll_log.append(f"killed_at_wallclock+{args.killdelay}s")
        else:
            grant = wait_running(off, time.time() + 90, args.session)
            if grant:
                killed = poll_kill_midprefill(off, grant, p, time.time() + args.maxtime, poll_log)
            else:
                poll_log.append("no_grant_within_90s")
                p.kill()
        try:
            code = p.communicate(timeout=30)[0].decode().strip()
        except Exception:
            code = "timeout"
        # 等 RELEASED + 收尾证据落盘（capture/evict 行在 RELEASED 前后）
        time.sleep(4)
        seg = trace_since(off)
        print(json.dumps({"grant": grant, "killed": killed, "poll": poll_log, "curl": code,
                          "offset": off, "trace_after": seg}, ensure_ascii=False))
    elif args.cmd == "contend":
        # 让位触发器：小内容新 key 轮，进入准入即令在途孤儿让位；--delay 控制起跳时机
        if args.delay:
            time.sleep(args.delay)
        payload = build_payload(args.session, 0, marker, 30)
        payload["messages"] = [{"role": "user",
                                "content": NONCE_TPL.format(marker=marker) + "Answer with exactly: OK"}]
        out = args.out or os.path.join(ART, f"contend-{args.session}-{int(time.time())}.json")
        p = post_chat(payload, out, 240)
        code = p.communicate(timeout=270)[0].decode().strip()
        print(json.dumps({"r": code, "offset": off, "out": out}, ensure_ascii=False))
    elif args.cmd == "census":
        # 池普查：请求级 session（不带显式 session_id）+ agent=c2matrix → sessionAdoptMiss 列出本 agent 域候选
        payload = {"model": "simigo", "stream": False, "max_tokens": 20,
                   "messages": [{"role": "user",
                                 "content": NONCE_TPL.format(marker="census-" + str(int(time.time())))
                                            + "Answer with exactly: OK"}]}
        out = os.path.join(ART, f"census-{int(time.time())}.json")
        p = post_chat(payload, out, 90)
        code = p.communicate(timeout=120)[0].decode().strip()
        seg = trace_since(off)
        lines = [l for l in seg.splitlines()
                 if ("sessionAdopt" in l or "residencyLedger" in l or "LIFECYCLE" in l)]
        print(json.dumps({"r": code, "offset": off, "pool_lines": lines}, ensure_ascii=False))
    elif args.cmd == "since":
        print(trace_since(args.offset))
    elif args.cmd == "waitidle":
        time.sleep(args.seconds)
        seg = trace_since(off)
        lines = [l for l in seg.splitlines() if "suspend_done" in l or "resume_done" in l]
        print(json.dumps({"offset": off, "lifecycle": lines}, ensure_ascii=False))


if __name__ == "__main__":
    main()
