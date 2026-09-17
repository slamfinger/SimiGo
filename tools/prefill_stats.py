#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Prefill 模态统计（P1 观测指标，2026-09-18 定版）。

对 native_mlx_trace.log 的 `[MLX] session=` 完成行按 mode 聚合：
n / promptTokens 总量·均值·P95 / promptTime 总量·均值·P95 /
fork@common 与 divergenceToken（fork 系模式）/ reuse 分布 /
「既有会话上的 cold」识别（同 key 先前出现过 → 门禁拒收而非新会话）。

用法:
    python3 tools/prefill_stats.py [logfile] [--since "YYYY-MM-DD HH:MM"] [--session KEY] [--json]

仅依赖标准库。mode 取值与引擎透传一致：
cold / extend / rebuild / fork-no-rewind（及其余透传值）。
fork@common 为本仓库 vendor telemetry（非上游原生），fork 系模式独有。
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
    seen_keys = set()
    with open(args.logfile, encoding="utf-8", errors="replace") as f:
        for line in f:
            if args.since and args.since not in line and not rows:
                # --since 语义：跳过首次命中之前的所有行
                continue
            sm = SESSION_RE.search(line)
            if not sm:
                continue
            key = sm.group("key")
            if args.session and args.session not in key:
                continue
            mm = MODE_RE.search(line)
            pm = PROMPT_RE.search(line)
            if not mm or not pm:
                continue
            cm = COMMON_RE.search(line)
            cache = CACHE_RE.search(line)
            reuse = sm.group("reuse")
            mode = mm.group("mode")
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
                "coldOnExisting": reuse == "false" and mode == "cold" and key in seen_keys,
            })
            seen_keys.add(key)

    if not rows:
        print("no session= completion lines matched")
        return

    by_mode = defaultdict(list)
    for r in rows:
        by_mode[r["mode"]].append(r)

    order = ["cold", "extend", "rebuild", "fork-no-rewind"]
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

    if args.json:
        print(json.dumps({"summary": summary, "modes": report,
                          "rows": rows}, ensure_ascii=False, indent=1))
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


if __name__ == "__main__":
    main()
