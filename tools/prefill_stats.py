#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Prefill 模态统计（P1 观测指标，2026-09-18 定版）+ Agent 执行级汇总（V1.5）。

对 native_mlx_trace.log 的 `[MLX] session=` 完成行按 mode 聚合：
n / promptTokens 总量·均值·P95 / promptTime 总量·均值·P95 /
fork@common 与 divergenceToken（fork 系模式）/ reuse 分布 /
「既有会话上的 cold」识别（同 key 先前出现过 → 门禁拒收而非新会话）。

用法:
    python3 tools/prefill_stats.py [logfile] [--since "YYYY-MM-DD HH:MM"] [--session KEY] [--json]

仅依赖标准库。mode 取值与引擎透传一致：
cold / extend / rebuild / fork-no-rewind（及其余透传值）。
特殊档：
  fragment   = 恢复态轮（Conditional Restore / 旧 rf 的 fragment-continuation，
               无 mode=，用紧邻 admission 行的 rf=1 判别； latency 取 ttft）。
  noMode     = 旧遥测时代（mode= 字段引入前）的无 mode 完成行，非恢复态。
fork@common 为本仓库 vendor telemetry（非上游原生），fork 系模式独有。
Agent 汇总（每窗口）：分歧税（full-prefill 轮 promptTime 合计）、连续执行比
（既有会话轮中未触发 full-prefill 的占比）、恢复事件计数（按 reason）。
"""
import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

SESSION_RE = re.compile(
    r"\[(?P<ts>[^\]]+)\] \[MLX\] session=(?P<key>\S+) messages=\d+ history=\d+ "
    r"delta=\d+ reuse=(?P<reuse>\w+)"
)
MODE_RE = re.compile(r"mode=(?P<mode>\S+)")
PROMPT_RE = re.compile(r"promptTokens=(?P<pt>\d+) promptTime=(?P<ptime>[\d.]+)s")
COMMON_RE = re.compile(r"fork@common=(?P<common>\d+)/(?P<ledger>\d+)")
CACHE_RE = re.compile(r"cacheTokens=(?P<ct>\d+)")
TTFT_RE = re.compile(r"ttft=(?P<ttft>\d+)ms")
ADM_RE = re.compile(r"\[MLX\] admission .*\brf=(?P<rf>\d)")
ACTION_RE = re.compile(
    r"\[MLX\] action=(?P<action>rollforward|rollforwardSkip|rollforwardFailed|"
    r"checkpointFailed) key=(?P<key>\S+)(?: reason=(?P<reason>\S+))?"
)


def p95(values):
    if not values:
        return 0.0
    s = sorted(values)
    if len(s) == 1:
        return float(s[0])
    pos = 0.95 * (len(s) - 1)
    lo, hi = int(pos), min(int(pos) + 1, len(s) - 1)
    frac = pos - lo
    return s[lo] * (1 - frac) + s[hi] * frac


def mean(values):
    return sum(values) / len(values) if values else 0.0


def main():
    ap = argparse.ArgumentParser(description="prefill 模态统计")
    ap.add_argument("logfile", nargs="?",
                    default=str(Path.home() / ".simigo/logs/native_mlx_trace.log"))
    ap.add_argument("--since", default=None, help='只统计此时间戳之后，如 "2026-09-17 17:53"')
    ap.add_argument("--session", default=None, help="只统计 traceKey 含此子串的会话")
    ap.add_argument("--json", action="store_true", help="输出 JSON（供基准对账）")
    args = ap.parse_args()

    rows = []
    actions = defaultdict(int)
    seen_keys = set()
    last_rf = False
    with open(args.logfile, encoding="utf-8", errors="replace") as f:
        for line in f:
            if args.since and args.since not in line and not rows:
                # --since 语义：跳过首次命中之前的所有行
                continue
            am = ACTION_RE.search(line)
            if am:
                key = am.group("key")
                if not args.session or args.session in key:
                    action = am.group("action")
                    if action == "rollforward":
                        actions["rollforwardFired"] += 1
                    elif action == "rollforwardFailed":
                        actions["rollforwardFailed"] += 1
                    elif action == "checkpointFailed":
                        actions["checkpointFailed"] += 1
                    else:
                        reason = am.group("reason") or "?"
                        actions[f"skip:{reason}"] += 1
            adm = ADM_RE.search(line)
            if adm:
                last_rf = adm.group("rf") == "1"
            sm = SESSION_RE.search(line)
            if not sm:
                continue
            key = sm.group("key")
            if args.session and args.session not in key:
                continue
            mm = MODE_RE.search(line)
            pm = PROMPT_RE.search(line)
            if not pm:
                continue
            if mm:
                mode = mm.group("mode")
            else:
                # 无 mode=：紧邻 admission rf=1 ⇒ 恢复态（fragment-continuation，
                # 无可对照账本故引擎不报 reuse mode）；否则为旧遥测时代完成行。
                mode = "fragment" if last_rf else "noMode"
            last_rf = False
            cm = COMMON_RE.search(line)
            cache = CACHE_RE.search(line)
            ttft = TTFT_RE.search(line)
            reuse = sm.group("reuse")
            pt = int(pm.group("pt"))
            ptime = float(pm.group("ptime"))
            common = int(cm.group("common")) if cm else None
            ledger = int(cm.group("ledger")) if cm else None
            rows.append({
                "ts": sm.group("ts"),
                "key": key,
                "reuse": reuse,
                "mode": mode,
                "promptTokens": pt,
                "promptTime": ptime,
                "forkCommon": common,
                "forkLedger": ledger,
                "divergenceToken": (pt - common) if common is not None else None,
                "cacheTokens": int(cache.group("ct")) if cache else None,
                "ttftS": round(int(ttft.group("ttft")) / 1000, 1) if ttft else None,
                "coldOnExisting": reuse == "false" and mode == "cold" and key in seen_keys,
            })
            seen_keys.add(key)

    if not rows:
        print("no session= completion lines matched")
        return

    by_mode = defaultdict(list)
    for r in rows:
        by_mode[r["mode"]].append(r)

    order = ["cold", "extend", "rebuild", "fork-no-rewind", "fragment", "noMode"]
    rest = sorted(m for m in by_mode if m not in order)
    report = {}
    for mode in order + rest:
        rs = by_mode[mode]
        pts = [r["promptTokens"] for r in rs]
        times = [r["promptTime"] for r in rs]
        divs = [r["divergenceToken"] for r in rs if r["divergenceToken"] is not None]
        commons = [r["forkCommon"] for r in rs if r["forkCommon"] is not None]
        entry = {
            "n": len(rs),
            "promptTokensTotal": sum(pts),
            "promptTokensMean": round(mean(pts), 1),
            "promptTokensP95": round(p95(pts), 1),
            "promptTimeTotalS": round(sum(times), 1),
            "promptTimeMeanS": round(mean(times), 1),
            "promptTimeP95S": round(p95(times), 1),
            "reuseFalse": sum(1 for r in rs if r["reuse"] == "false"),
            "coldOnExisting": sum(1 for r in rs if r["coldOnExisting"]),
        }
        if commons:
            entry["forkCommonMean"] = round(mean(commons), 1)
            entry["divergenceTokenTotal"] = sum(divs)
            entry["divergenceTokenMean"] = round(mean(divs), 1)
        report[mode] = entry

    total_tokens = sum(r["promptTokens"] for r in rows)
    waste_tokens = sum(
        r["promptTokens"] for r in rows
        if r["mode"] in ("fork-no-rewind", "rebuild")
        or (r["mode"] == "cold" and r["coldOnExisting"])
    )
    summary = {
        "requests": len(rows),
        "distinctSessions": len(seen_keys),
        "promptTokensTotal": total_tokens,
        "incrementalTokens": sum(r["promptTokens"] for r in rows if r["mode"] == "extend"),
        "reworkTokens": waste_tokens,
        "reworkRatio": round(waste_tokens / total_tokens, 3) if total_tokens else 0.0,
    }

    # Agent 执行级汇总（V1.5，2026-09-18）：以「既有会话轮」为分母度量
    # Execution Continuity——full-prefill（fork-no-rewind/rebuild/既有会话 cold）
    # 是分歧税，extend 命中与 fragment 恢复是连续执行。
    full_rows = [r for r in rows
                 if r["mode"] in ("fork-no-rewind", "rebuild") or r["coldOnExisting"]]
    existing = [r for r in rows if r["reuse"] == "true" or r["mode"] == "fragment"]
    extend_rows = [r for r in rows if r["mode"] == "extend"]
    fragment_rows = [r for r in rows if r["mode"] == "fragment"]
    tax_by_session = defaultdict(float)
    for r in full_rows:
        tax_by_session[r["key"]] += r["promptTime"]
    top_tax = sorted(tax_by_session.items(), key=lambda kv: -kv[1])[:3]
    agent = {
        "rounds": len(rows),
        "existingSessionRounds": len(existing),
        "continuousRatio": round(1 - len(full_rows) / len(existing), 3)
                           if existing else None,
        "fullPrefillRounds": len(full_rows),
        "fullPrefillTokens": sum(r["promptTokens"] for r in full_rows),
        "divergenceTaxS": round(sum(r["promptTime"] for r in full_rows), 1),
        "extendHitRounds": len(extend_rows),
        "fragmentRounds": len(fragment_rows),
        "fragmentTokens": sum(r["promptTokens"] for r in fragment_rows),
        "fragmentLatencyMeanS": round(mean([r["promptTime"] for r in fragment_rows]), 1),
        "topDivergenceTaxSessions": {k: round(v, 1) for k, v in top_tax},
    }

    if args.json:
        print(json.dumps({"summary": summary, "modes": report, "agent": agent,
                          "events": dict(actions), "rows": rows},
                         ensure_ascii=False, indent=1))
        return

    print(f"窗口: {rows[0]['ts']} → {rows[-1]['ts']}   "
          f"请求 {summary['requests']}  会话 {summary['distinctSessions']}  "
          f"预填总量 {summary['promptTokensTotal']:,} tok")
    print(f"增量(extend) {summary['incrementalTokens']:,} tok   "
          f"重渲/门禁拒收 {summary['reworkTokens']:,} tok   "
          f"浪费占比 {summary['reworkRatio']:.1%}\n")
    header = (f"{'mode':<16}{'n':>4}{'tokens':>10}{'mean':>9}{'P95':>9}"
              f"{'time(s)':>10}{'mean':>8}{'P95':>8}{'coldOnExist':>12}{'divTok':>9}")
    print(header)
    print("-" * len(header))
    for mode, e in report.items():
        print(f"{mode:<16}{e['n']:>4}{e['promptTokensTotal']:>10,}"
              f"{e['promptTokensMean']:>9,.0f}{e['promptTokensP95']:>9,.0f}"
              f"{e['promptTimeTotalS']:>10,.1f}{e['promptTimeMeanS']:>8,.1f}"
              f"{e['promptTimeP95S']:>8,.1f}{e['coldOnExisting']:>12}"
              f"{e.get('divergenceTokenTotal', 0):>9,}")
    print("\nfork 系 divergenceToken = promptTokens - fork@common"
          "（fork@common 为本仓库 vendor telemetry）")
    cold_exist = sum(e["coldOnExisting"] for e in report.values())
    print(f"既有会话上的 cold（门禁拒收，非新会话）: {cold_exist} 次")

    print("\n=== Agent 执行级（Execution Continuity）===")
    cont = agent["continuousRatio"]
    cont_s = f"{cont:.1%}" if cont is not None else "n/a"
    print(f"轮次 {agent['rounds']}（既有会话轮 {agent['existingSessionRounds']}）  "
          f"连续执行比 {cont_s}")
    print(f"full-prefill {agent['fullPrefillRounds']} 轮  "
          f"{agent['fullPrefillTokens']:,} tok  分歧税 {agent['divergenceTaxS']:,}s   "
          f"extend 命中 {agent['extendHitRounds']} 轮")
    frag_lat = agent["fragmentLatencyMeanS"]
    print(f"恢复(fragment) {agent['fragmentRounds']} 轮  "
          f"{agent['fragmentTokens']:,} tok  平均恢复延迟 {frag_lat}s")
    if actions:
        ev = "  ".join(f"{k}={v}" for k, v in sorted(actions.items()))
        print(f"恢复事件: {ev}")
    if agent["topDivergenceTaxSessions"]:
        tops = "  ".join(f"{k}={v}s" for k, v in agent["topDivergenceTaxSessions"].items())
        print(f"分歧税 Top: {tops}")


if __name__ == "__main__":
    main()
