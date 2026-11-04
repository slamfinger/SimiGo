#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V1.7-3 Local Office Prototype（方向登记 V1.7-C，2026-09-20）。

规格（docs/decisions/V17_DIRECTION_REGISTRATION_20260919.md）：
  "SimiGo 双翼定位：Runtime + Office。从文件任务起步（多 Excel
   分类/提取/汇总：读文件 → 本地模型理解 → 执行脚本 → 生成 →
   模型检查 → 输出）——Runtime 第一次承载真实办公生产任务。"

设计裁决（红线内）：
  - 固定工作流脚本，不是 Agent Framework（无 Planner/记忆/多工具编排；
    2 个固定工具 submit_result/verify）。
  - **模型出决策、harness 出确定性执行**：pandas 变换由 runner 执行，
    不 exec 模型生成的代码（首版风险裁决，语义等价保留
    理解→执行→生成→检查→输出闭环；README 记录此偏差）。
  - 数据=确定性生成的合成办公数据（固定 seed），ground truth 同源
    生成→任务结果可精确评分（分类/提取=比对，汇总=数值容差 0.01）。
    真实用户文件接入留作后续（原型先证 Runtime 承载力）。
  - 模型检查=执行回执+抽查行复核（verify 工具），抽查独立评分，
    不泄露 ground truth。
  - summary 任务读模型自身上游提交（误差传播可见），发票数回显其
    此前提交=跨 session 一致性检查。

任务矩阵（每任务一个 session；t2 带 tool 尾→restore 风味路径自然出现）：
  expenses  40 行报销流水 → 逐行分类（餐饮/交通/办公/其他）
  inventory 30 行库存     → 提取补货行（数量<20）
  invoices  16 行发票     → 汇总未付总额+笔数
  summary   跨文件 KPI ×3（总行数/补货行数/未付笔数）

V1.7-2 输入落实：客户端账本镜像（normalize_assistant 回填）；payload
轮 max_tokens=1536 防 tool_calls 截断（C5 教训）；malformed tool call
允许 1 次修复轮，再失败=task fail（诚实记录办公就绪度）。

每行 checkpoint（trace 全字段 + evictions + memAfter + anomalyCount）；
per-task attempt 有效性（V1.7-1/2 纪律延续）。

用法：python3 tools/v17_3_office.py [--tasks expenses,summary] [--smoke]
前置：SimiGo 运行中（生产策略）、无进行中生成。
"""
import argparse
import json
import random
from pathlib import Path

import pandas as pd

import runtime_matrix as rm
from v17_2_concurrency import anomaly_count, evictions_since, mem_after

OUT = Path("docs/experiments/V17_RUNTIME_MATRIX/results_v17_3_office.json")
WORK = Path("docs/experiments/V17_RUNTIME_MATRIX/office_out")

CATS = ["餐饮", "交通", "办公", "其他"]
CAT_KEYWORDS = {
    "餐饮": ["午餐", "晚餐", "早餐", "咖啡", "工作餐", "客户宴请"],
    "交通": ["打车", "地铁", "高铁", "机票", "停车", "网约车"],
    "办公": ["打印纸", "墨盒", "文具", "键盘", "办公用品", "硒鼓"],
}
CAT_OTHER = ["团队建设", "书籍资料", "快递费", "会议茶歇"]
CAT_BUDGET = {"餐饮": (18, 260), "交通": (12, 680), "办公": (25, 900),
              "其他": (30, 500)}

SUBMIT_TOOL = {
    "type": "function",
    "function": {
        "name": "submit_result",
        "description": "提交任务结果。payload 为多行文本，每行格式 'id|值'。",
        "parameters": {"type": "object",
                       "properties": {"payload": {"type": "string"}},
                       "required": ["payload"]},
    },
}
VERIFY_TOOL = {
    "type": "function",
    "function": {
        "name": "verify",
        "description": "核对执行结果后提交结论：ok=与你的判断一致，issues=不一致处。",
        "parameters": {"type": "object",
                       "properties": {"ok": {"type": "boolean"},
                                      "issues": {"type": "string"}},
                       "required": ["ok", "issues"]},
    },
}
TOOLS = [SUBMIT_TOOL, VERIFY_TOOL]

TASK_SCENARIOS = {
    "expenses": ["expenses_t1", "expenses_t2"],
    "inventory": ["inventory_t1", "inventory_t2"],
    "invoices": ["invoices_t1", "invoices_t2"],
    "summary": ["summary_t1"],
}
SESSION_OF = {"expenses": "e", "inventory": "i", "invoices": "v",
              "summary": "s"}


# ---------------- payload 解析与评分 ----------------

def parse_payload(raw):
    """'id|值' 行 → dict；不可解析返回 None（触发修复轮）。"""
    if not isinstance(raw, str) or "|" not in raw:
        return None
    out = {}
    for line in raw.splitlines():
        line = line.strip()
        if not line or "|" not in line:
            continue
        k, _, v = line.partition("|")
        k, v = k.strip(), v.strip()
        if k:
            out[k] = v
    return out or None


def tool_payload(msg):
    for call in msg.get("tool_calls") or []:
        fn = call.get("function") or {}
        if fn.get("name") == "submit_result":
            args = fn.get("arguments")
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except (json.JSONDecodeError, ValueError):
                    return None
            return (args or {}).get("payload")
    return None


def tool_args(msg, name):
    for call in msg.get("tool_calls") or []:
        fn = call.get("function") or {}
        if fn.get("name") == name:
            args = fn.get("arguments")
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except (json.JSONDecodeError, ValueError):
                    return None
            return args or {}
    return None


def _last_call_id(messages):
    for msg in reversed(messages):
        if msg.get("role") == "assistant" and msg.get("tool_calls"):
            return msg["tool_calls"][0].get("id") or "call_office"
    return "call_office"


def render_table(rows, cols):
    lines = ["id | " + " | ".join(cols)]
    for r in rows:
        lines.append(str(r["id"]) + " | " +
                     " | ".join(str(r[c]) for c in cols))
    return "\n".join(lines)


# ---------------- runner 主干 ----------------

def checkpoint(store):
    OUT.write_text(json.dumps(store, ensure_ascii=False, indent=1))


def add_row(store, **kw):
    store["runs"].append(kw)
    checkpoint(store)
    t = kw.get("trace") or {}
    print(f"  [{kw.get('task')}/{kw.get('scenario')}] wall={kw.get('wallS')}s "
          f"verdict={kw.get('verdict')} mode={t.get('mode')} "
          f"reuse={t.get('reuse')} tok={t.get('promptTokens')}",
          flush=True)


def _reply_excerpt(msg):
    """模型回复摘录（审计用：content 前 160 字 + tool_calls 概要）。"""
    if not msg:
        return None
    calls = [{"name": (c.get("function") or {}).get("name"),
              "args": str((c.get("function") or {}).get("arguments"))[:200]}
             for c in msg.get("tool_calls") or []]
    return {"content": (msg.get("content") or "")[:160], "tool_calls": calls}


def chat_turn(store, task, scenario, attempt, session, messages,
              session_key, max_tokens):
    """一步：请求→等完成→落行→回填 assistant。失败也落行（fail）并返回
    (None, row)。"""
    r = rm.chat(session, messages, tools=TOOLS, max_tokens=max_tokens)
    pos0 = r[2]
    comp = rm.wait_completion(pos0, session_key)
    row = {"task": task, "scenario": scenario, "attempt": attempt,
           "session": session, "wallS": r[1],
           "trace": comp, "evictions": evictions_since(pos0),
           "memAfter": mem_after(), "anomalyCount": anomaly_count(pos0)}
    if comp is None or not r[0]:
        row["verdict"] = "fail"
        add_row(store, **row)
        return None, row
    row["reply"] = _reply_excerpt(r[0])
    messages.append(rm.normalize_assistant(r[0]))
    row["verdict"] = "pass"  # 请求层成功；任务层评分在 task_summary
    add_row(store, **row)
    return r[0], row


def repair_once(store, task, tag, attempt, session, messages, session_key,
                max_tokens, tool="submit_result"):
    """malformed/缺 tool call 修复轮（V1.7-2 C5 教训：允许 1 次）。"""
    ask = ("请必须调用 verify(ok,issues) 提交核对结论（简短作答）。"
           if tool == "verify" else
           "请必须调用 submit_result 提交，payload 每行 'id|值'。")
    m = messages + [rm.user(f"你的上一条回复没有按要求调用工具（可能因长度被截断）。{ask}")]
    return chat_turn(store, task, tag, attempt, session, m, session_key,
                     max_tokens)


def run_expenses(store, attempt, session, ctx):
    rows, gt = ctx["expenses"], ctx["gt"]["expenses"]
    table = render_table(rows, ["日期", "摘要", "金额"])
    m = [rm.user(f"以下是报销流水表，请把每行归入四类之一：{'/'.join(CATS)}。"
                 f"判断依据是摘要内容。\n{table}\n\n"
                 f"完成后调用 submit_result 提交，payload 每行 'id|类别'。")]
    msg, row = chat_turn(store, "expenses", "expenses_t1", attempt, session,
                         m, None, 1536)
    skey = (row.get("trace") or {}).get("session")
    parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None and msg is not None:
        msg, row = repair_once(store, "expenses", "expenses_t1", attempt,
                               session, m, skey, 1536)
        parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None:
        return {"task": "expenses", "attempt": attempt, "accuracy": 0,
                "payloadOk": False}

    ok = sum(1 for k, v in parsed.items()
             if k in gt and v in CATS and v == gt[k])
    total = len(gt)
    acc = round(ok / total, 3)
    out_rows = [dict(r, 类别=parsed.get(str(r["id"]), "?")) for r in rows]
    pd.DataFrame(out_rows)[["id", "日期", "摘要", "金额", "类别"]].to_excel(
        WORK / f"expenses_classified_a{attempt}.xlsx", index=False)
    missing = [str(r["id"]) for r in rows if not parsed.get(str(r["id"]))]

    m.append({"role": "tool", "tool_call_id": _last_call_id(m),
              "content": f"执行完成：已按你的标签写入 "
                         f"expenses_classified_a{attempt}.xlsx 共 {len(rows)} 行；"
                         f"未提供标签 {len(missing)} 行"
                         + (f"（id: {','.join(missing[:10])}）" if missing else "")})
    # 模型检查：确定性抽查 3 行，不泄露 ground truth
    samples = [rows[len(rows) // 6], rows[len(rows) // 2],
               rows[5 * len(rows) // 6]]
    sample_txt = "；".join(
        f"行 {r['id']}(摘要={r['摘要']},你给的类别={parsed.get(str(r['id']), '?')})"
        for r in samples)
    m.append(rm.user(f"请抽查复核：{sample_txt}。若这些行的类别与摘要语义相符，"
                     f"调用 verify(ok=true)；有误则 ok=false 并在 issues 写明行号。"))
    msg2, row2 = chat_turn(store, "expenses", "expenses_t2", attempt, session,
                           m, skey, 512)
    v = tool_args(msg2, "verify") if msg2 else None
    if v is None and msg2 is not None:
        msg2, row2 = repair_once(store, "expenses", "expenses_t2", attempt,
                                 session, m, skey, 512, tool="verify")
        v = tool_args(msg2, "verify") if msg2 else None
    by_id = {r["id"]: r["真实类别"] for r in rows}
    sample_hit = sum(1 for r in samples
                     if parsed.get(str(r["id"])) == by_id[r["id"]])
    ctx["model_expense_rows"] = len(parsed)
    return {"task": "expenses", "attempt": attempt, "accuracy": acc,
            "applied": ok, "total": total, "payloadOk": True,
            "verifyOk": (v or {}).get("ok"), "sampleHit": f"{sample_hit}/3"}


def run_inventory(store, attempt, session, ctx):
    rows, gt = ctx["inventory"], ctx["gt"]["inventory"]
    table = render_table(rows, ["商品", "数量", "单价", "仓库"])
    m = [rm.user(f"以下是库存表。请找出所有需要补货的行（数量<20）。\n{table}\n\n"
                 f"完成后调用 submit_result 提交，payload 每行 'id|1'"
                 f"（仅列需补货的行）。")]
    msg, row = chat_turn(store, "inventory", "inventory_t1", attempt, session,
                         m, None, 1024)
    skey = (row.get("trace") or {}).get("session")
    parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None and msg is not None:
        msg, row = repair_once(store, "inventory", "inventory_t1", attempt,
                               session, m, skey, 1024)
        parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None:
        return {"task": "inventory", "attempt": attempt, "accuracy": 0,
                "payloadOk": False}

    truth = set(gt)
    given = {k for k, v in parsed.items()
             if v.strip() in ("1", "是", "yes", "true")}
    hit = len(given & truth)
    fp = len(given - truth)
    acc = round(hit / len(truth), 3) if truth else None
    pd.DataFrame([r for r in rows if str(r["id"]) in given])[
        ["id", "商品", "数量", "单价", "仓库"]].to_excel(
        WORK / f"inventory_reorder_a{attempt}.xlsx", index=False)
    m.append({"role": "tool", "tool_call_id": _last_call_id(m),
              "content": f"执行完成：筛出 {len(given)} 行写入 "
                         f"inventory_reorder_a{attempt}.xlsx"})
    m.append(rm.user("请调用 verify(ok,issues) 确认清单是否符合「数量<20」标准。"))
    msg2, row2 = chat_turn(store, "inventory", "inventory_t2", attempt,
                           session, m, skey, 512)
    v = tool_args(msg2, "verify") if msg2 else None
    if v is None and msg2 is not None:
        msg2, row2 = repair_once(store, "inventory", "inventory_t2", attempt,
                                 session, m, skey, 512, tool="verify")
        v = tool_args(msg2, "verify") if msg2 else None
    ctx["model_inventory_ids"] = sorted(given)
    return {"task": "inventory", "attempt": attempt, "accuracy": acc,
            "hit": f"{hit}/{len(truth)}", "falsePositive": fp,
            "payloadOk": True, "verifyOk": (v or {}).get("ok")}


def run_invoices(store, attempt, session, ctx):
    rows, gt = ctx["invoices"], ctx["gt"]["invoices"]
    table = render_table(rows, ["客户", "金额", "月份", "状态"])
    m = [rm.user(f"以下是发票台账。请汇总未付发票的总金额与笔数。\n{table}\n\n"
                 f"完成后调用 submit_result 提交，payload 两行："
                 f"'unpaid_total|金额' 与 'unpaid_count|笔数'。")]
    msg, row = chat_turn(store, "invoices", "invoices_t1", attempt, session,
                         m, None, 512)
    skey = (row.get("trace") or {}).get("session")
    parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None and msg is not None:
        msg, row = repair_once(store, "invoices", "invoices_t1", attempt,
                               session, m, skey, 512)
        parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None:
        return {"task": "invoices", "attempt": attempt, "accuracy": 0,
                "payloadOk": False}

    try:
        t = float(parsed.get("unpaid_total", "nan"))
        c = int(parsed.get("unpaid_count", "-1"))
    except (TypeError, ValueError):
        t, c = None, None
    ok = (t is not None and abs(t - gt["unpaid_total"]) <= 0.01
          and c == gt["unpaid_count"])
    m.append({"role": "tool", "tool_call_id": _last_call_id(m),
              "content": f"已登记：未付总额 {parsed.get('unpaid_total')}，"
                         f"笔数 {parsed.get('unpaid_count')}。"})
    m.append(rm.user("请调用 verify(ok,issues) 确认你的汇总与表中数据一致。"))
    msg2, row2 = chat_turn(store, "invoices", "invoices_t2", attempt, session,
                           m, skey, 512)
    v = tool_args(msg2, "verify") if msg2 else None
    if v is None and msg2 is not None:
        msg2, row2 = repair_once(store, "invoices", "invoices_t2", attempt,
                                 session, m, skey, 512, tool="verify")
        v = tool_args(msg2, "verify") if msg2 else None
    ctx["model_invoices"] = {"unpaid_total": parsed.get("unpaid_total"),
                             "unpaid_count": parsed.get("unpaid_count")}
    return {"task": "invoices", "attempt": attempt,
            "accuracy": 1 if ok else 0,
            "submitted": {"unpaid_total": t, "unpaid_count": c},
            "truthTotal": gt["unpaid_total"], "truthCount": gt["unpaid_count"],
            "payloadOk": True, "verifyOk": (v or {}).get("ok")}


def run_summary(store, attempt, session, ctx):
    """跨文件 KPI：读模型自身上游提交（误差传播可见）；
    unpaid_count 回显其 invoices 提交=跨 session 一致性检查。"""
    gt = ctx["gt"]
    n_exp = ctx.get("model_expense_rows", len(ctx["expenses"]))
    reorder = ctx.get("model_inventory_ids") or gt["inventory"]
    inv = ctx.get("model_invoices") or {}
    m = [rm.user(
        "今天处理了三个文件，以下是你此前的提交结果：\n"
        f"1) 报销分类：{n_exp} 行已分类。\n"
        f"2) 库存补货清单：{len(reorder)} 行。\n"
        f"3) 发票汇总：你提交了 unpaid_total={inv.get('unpaid_total', '?')}、"
        f"unpaid_count={inv.get('unpaid_count', '?')}。\n\n"
        "请做跨文件日报，调用 submit_result 提交 payload 三行：\n"
        "total_expense|报销流水总行数\n"
        "reorder_count|补货行数\n"
        "unpaid_count|未付发票笔数")]
    msg, row = chat_turn(store, "summary", "summary_t1", attempt, session,
                         m, None, 256)
    parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None and msg is not None:
        msg, row = repair_once(store, "summary", "summary_t1", attempt,
                               session, m, None, 256)
        parsed = parse_payload(tool_payload(msg) if msg else None)
    gt3 = {"total_expense": str(n_exp), "reorder_count": str(len(reorder)),
           "unpaid_count": str(inv.get("unpaid_count", "?"))}
    hit = sum(1 for k, v in gt3.items()
              if parsed and str(parsed.get(k, "")).strip() == v)
    (WORK / f"daily_report_a{attempt}.md").write_text(
        f"# 本地办公室日报（attempt {attempt}）\n\n"
        f"- 报销分类：{parsed.get('total_expense', '?')} 行\n"
        f"- 库存补货：{parsed.get('reorder_count', '?')} 行\n"
        f"- 发票未付：{parsed.get('unpaid_count', '?')} 笔\n\n"
        f"（由 Local Office Prototype 工作流生成，SimiGo 本地 Runtime 承载）\n",
        encoding="utf-8")
    return {"task": "summary", "attempt": attempt,
            "kpiHit": f"{hit}/3", "accuracy": round(hit / 3, 3),
            "payloadOk": parsed is not None}


RUNNERS = {"expenses": run_expenses, "inventory": run_inventory,
           "invoices": run_invoices, "summary": run_summary}


def task_complete(store, task, attempt):
    have = {r["scenario"] for r in store["runs"]
            if r.get("task") == task and r.get("attempt") == attempt}
    return set(TASK_SCENARIOS[task]) <= have


def main():
    ap = argparse.ArgumentParser(description="V1.7-3 local office prototype")
    ap.add_argument("--tasks", default="expenses,inventory,invoices,summary")
    ap.add_argument("--rows", default="40,30,16",
                    help="expenses,inventory,invoices 行数")
    ap.add_argument("--smoke", action="store_true",
                    help="冒烟：12/8/6 行（独立结果文件与 seed）")
    ap.add_argument("--seed", type=int, default=20260920)
    ap.add_argument("--redo", default="",
                    help="强制重跑为新 attempt（逗号分隔任务名），供捕获"
                         "增强/判据修复后重测")
    args = ap.parse_args()
    global OUT
    if args.smoke:
        OUT = OUT.with_name("results_v17_3_office_smoke.json")
        rows_cfg = (12, 8, 6)
    else:
        rows_cfg = tuple(int(x) for x in args.rows.split(","))

    tasks = [x.strip() for x in args.tasks.split(",") if x.strip()]

    # 确定性数据生成（ground truth 同源）
    rng = random.Random(args.seed if not args.smoke else args.seed + 1)
    n_exp, n_inv, n_inv2 = rows_cfg
    expenses = []
    for i in range(1, n_exp + 1):
        cat = CATS[(i - 1) % 4]
        memo = (rng.choice(CAT_KEYWORDS[cat]) if cat != "其他"
                else rng.choice(CAT_OTHER))
        lo, hi = CAT_BUDGET[cat]
        expenses.append({"id": i, "日期": f"2026-08-{1 + i % 28:02d}",
                         "摘要": memo, "金额": round(rng.uniform(lo, hi), 1),
                         "真实类别": cat})
    inventory = [{"id": i, "商品": f"SKU-{1000 + i}",
                  "数量": rng.choice([5, 8, 12, 15, 18, 25, 40, 66, 120, 200]),
                  "单价": round(rng.uniform(8, 480), 1),
                  "仓库": rng.choice(["A", "B"])}
                 for i in range(1, n_inv + 1)]
    invoices = [{"id": i, "客户": f"客户{chr(64 + 1 + i % 6)}",
                 "金额": round(rng.uniform(800, 24000), 2),
                 "月份": f"2026-{1 + i % 3:02d}",
                 "状态": "已付" if i % 3 != 1 else "未付"}
                for i in range(1, n_inv2 + 1)]
    gt = {"expenses": {str(r["id"]): r["真实类别"] for r in expenses},
          "inventory": sorted(str(r["id"]) for r in inventory
                              if r["数量"] < 20),
          "invoices": {"unpaid_total": round(
              sum(r["金额"] for r in invoices if r["状态"] == "未付"), 2),
              "unpaid_count": sum(1 for r in invoices
                                  if r["状态"] == "未付")}}
    ctx = {"expenses": expenses, "inventory": inventory,
           "invoices": invoices, "gt": gt}
    WORK.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(expenses)[["id", "日期", "摘要", "金额"]].to_excel(
        WORK / "expenses.xlsx", index=False)
    pd.DataFrame(inventory)[["id", "商品", "数量", "单价", "仓库"]].to_excel(
        WORK / "inventory.xlsx", index=False)
    pd.DataFrame(invoices)[["id", "客户", "金额", "月份", "状态"]].to_excel(
        WORK / "invoices.xlsx", index=False)
    (WORK / "ground_truth.json").write_text(
        json.dumps(gt, ensure_ascii=False, indent=1))
    print(f"[data] expenses={n_exp} inventory={n_inv} invoices={n_inv2} "
          f"gt_reorder={gt['inventory']} gt_unpaid={gt['invoices']}",
          flush=True)

    store = json.loads(OUT.read_text()) if OUT.exists() else {
        "model": rm.MODEL,
        "meta": {**rm.experiment_meta(),
                 "serializeGeneration": "true (生产常量)",
                 "smoke": args.smoke, "seed": args.seed,
                 "rows": {"expenses": n_exp, "inventory": n_inv,
                          "invoices": n_inv2}},
        "design": ("V1.7-3 Local Office Prototype: 3 xlsx "
                   "(classify/extract/summarize) + cross-file KPI; model "
                   "decides, harness executes deterministically; "
                   "ground-truth scored; per-task attempt unit"),
        "runs": []}

    for task in tasks:
        attempts = {r.get("attempt") for r in store["runs"]
                    if r.get("task") == task}
        redo = task in {x.strip() for x in args.redo.split(",") if x.strip()}
        done = None if redo else next(
            (a for a in sorted(attempts, reverse=True)
             if a is not None and task_complete(store, task, a)), None)
        if done is not None:
            print(f"--- {task}: attempt {done} 完整，跳过 ---", flush=True)
            continue
        attempt = max((a for a in attempts if a is not None), default=0) + 1
        # smoke 用 s 前缀隔离服务端 session（避免与正式 o 前缀撞账本——
        # session-id-reuse 教训）
        prefix = "s" if args.smoke else "o"
        session = f"{prefix}{attempt}{SESSION_OF[task]}"
        assert len(session) <= 6, f"session 超长: {session}"
        print(f"===== office/{task} attempt {attempt} "
              f"(session={session}) =====", flush=True)
        summary = RUNNERS[task](store, attempt, session, ctx)
        store.setdefault("task_summaries", [])
        store["task_summaries"] = [
            s for s in store["task_summaries"]
            if not (s["task"] == task and s["attempt"] == attempt)]
        store["task_summaries"].append(summary)
        checkpoint(store)

    print("\n=== V1.7-3 汇总 ===", flush=True)
    for s in store.get("task_summaries", []):
        extras = {k: v for k, v in s.items()
                  if k in ("hit", "falsePositive", "sampleHit", "submitted",
                           "kpiHit", "verifyOk")}
        print(f"  {s['task']} a{s['attempt']}: acc={s.get('accuracy')} "
              f"payloadOk={s.get('payloadOk')} {extras}", flush=True)
    print("=== 完成 ===", flush=True)


if __name__ == "__main__":
    main()
