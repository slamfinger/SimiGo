#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V1.7-3c Local Office——文件夹/文件整理 + 多文档提取整合（2026-09-20）。

承接 V1.7-3/3b（Excel+Word+PPT+PDF 已全绿）：本轮新增两类办公能力测试，
纪律完全一致（固定工作流、模型决策+harness 确定性执行、ground truth
同源→精确评分、payload='key|值' 行、per-task attempt、reply 摘录审计、
verify 轮 512 tok、修复轮按目标工具定制）。

任务矩阵：
  organize  文件整理：10 个混合格式/混合命名文件（3 纪要 docx + 2 汇报
            pptx + 3 发票 pdf + 2 数据 xlsx；部分名字不可判读如
            untitled_3.pptx）→ 模型按【文件名+内容摘要】归入 4 个目标
            文件夹 → harness 真实复制归档（office_out/folder/organize/
            a{n}/<文件夹>/）。评分=正确归位 x/10。
  merge     多文档提取整合：3 个团队的 .docx 周报（移动端/后端服务/
            数据组，各含负责人/本周状态(正常|滞后)/风险条数）→ 逐队
            提取（6 项）+ 跨队整合（滞后名单+风险总数，2 项）共 8 项
            精确评分。产物=整合版周报 docs（harness 由模型提交汇编）。

会话命名：g{attempt}o / g{attempt}m（≤6 字符；与前序 runner 的
o*/d*/x* 前缀不撞——session-id-reuse 教训）。smoke 用 h 前缀。

范围边界：整理=复制归档（不删源文件、不改名）；整合=文本型 docx。
"""
import argparse
import json
import random
import shutil
from pathlib import Path

import runtime_matrix as rm
from v17_2_concurrency import anomaly_count, evictions_since, mem_after
from v17_3_office import (_last_call_id, _reply_excerpt, parse_payload,
                          tool_args, tool_payload)

OUT = Path("docs/experiments/V17_RUNTIME_MATRIX/results_v17_3_office_folder.json")
WORK = Path("docs/experiments/V17_RUNTIME_MATRIX/office_out/folder")

FOLDERS = ["01_会议纪要", "02_项目汇报", "03_财务发票", "04_数据表格"]
TEAMS = [("mobile", "移动端", "张伟"), ("backend", "后端服务", "李娜"),
         ("data", "数据组", "王强")]

TASK_SCENARIOS = {"organize": ["organize_t1", "organize_t2"],
                  "merge": ["merge_t1", "merge_t2"]}
SESSION_OF = {"organize": "o", "merge": "m"}


def build_tools():
    from v17_3_office import SUBMIT_TOOL, VERIFY_TOOL
    return [SUBMIT_TOOL, VERIFY_TOOL]


def num_of(raw):
    """带单位数值容错解析（V1.7-3b 教训：'3 条'/'5602.13 元'）。"""
    digits = "".join(ch for ch in str(raw) if ch.isdigit())
    return int(digits) if digits else None


# ---------------- 文件生成（organize 输入） ----------------

def _gen_minutes_docx(path, title, rng):
    import docx
    d = docx.Document()
    d.add_heading(title, level=1)
    d.add_paragraph(f"日期：2026-09-{rng.randint(10, 18):02d}")
    d.add_paragraph("与会人员汇报了各自模块进展，讨论了遗留问题与排期。")
    d.add_paragraph("行动项：负责人跟进遗留问题，期限另行同步。")
    d.save(str(path))


def _gen_deck_pptx(path, title, rng):
    from pptx import Presentation
    prs = Presentation()
    slide = prs.slides.add_slide(prs.slide_layouts[1])
    slide.shapes.title.text = title
    slide.placeholders[1].text_frame.text = "本页为汇报封面与要点索引。"
    s2 = prs.slides.add_slide(prs.slide_layouts[1])
    s2.shapes.title.text = "关键进展"
    s2.placeholders[1].text_frame.text = "各项里程碑按计划推进。"
    prs.save(str(path))


def _gen_invoice_pdf(path, no, client, amount, status):
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.cidfonts import UnicodeCIDFont
    from reportlab.pdfgen import canvas
    pdfmetrics.registerFont(UnicodeCIDFont('STSong-Light'))
    c = canvas.Canvas(str(path))
    c.setFont('STSong-Light', 14)
    c.drawString(72, 780, f"发票编号: INV-2026-{no}")
    c.setFont('STSong-Light', 12)
    c.drawString(72, 755, f"客户: {client}")
    c.drawString(72, 735, f"金额: {amount:.2f} 元")
    c.drawString(72, 715, f"状态: {status}")
    c.save()


def _gen_data_xlsx(path, kind, rng):
    import pandas as pd
    if kind == "expenses":
        df = pd.DataFrame([{"id": i, "摘要": f"差旅报销-{i}",
                            "金额": round(rng.uniform(50, 900), 1)}
                           for i in range(1, 6)])
    else:
        df = pd.DataFrame([{"id": i, "商品": f"SKU-{1000 + i}",
                            "数量": rng.choice([6, 15, 40, 120])}
                           for i in range(1, 6)])
    df.to_excel(str(path), index=False)


def gen_organize_files(rng, smoke):
    """返回 files=[{id, name, path, folder}]；文件夹=ground truth。"""
    src = WORK / "source"
    src.mkdir(parents=True, exist_ok=True)
    spec_full = [
        ("纪要_0912.docx", "docx_minutes", "移动端周例会纪要", "01_会议纪要"),
        ("meeting_notes_a.docx", "docx_minutes", "搜索服务设计评审会纪要", "01_会议纪要"),
        ("文档_20260918.docx", "docx_minutes", "数据组季度规划会纪要", "01_会议纪要"),
        ("deck_final_v2.pptx", "pptx_deck", "PHOENIX 项目季度汇报", "02_项目汇报"),
        ("untitled_3.pptx", "pptx_deck", "客户成功案例汇编", "02_项目汇报"),
        ("INV-2026-101.pdf", "pdf_invoice", ("101", "客户甲", 7686.82, "已付"), "03_财务发票"),
        ("扫描_0023.pdf", "pdf_invoice", ("102", "客户乙", 5602.13, "未付"), "03_财务发票"),
        ("INV-2026-104.pdf", "pdf_invoice", ("104", "客户丁", 14317.90, "未付"), "03_财务发票"),
        ("sheet_q3.xlsx", "xlsx_expenses", None, "04_数据表格"),
        ("data_08.xlsx", "xlsx_inventory", None, "04_数据表格"),
    ]
    spec = spec_full[:5] if smoke else spec_full
    files = []
    for i, (name, kind, arg, folder) in enumerate(spec, 1):
        path = src / name
        if kind == "docx_minutes":
            _gen_minutes_docx(path, arg, rng)
        elif kind == "pptx_deck":
            _gen_deck_pptx(path, arg, rng)
        elif kind == "pdf_invoice":
            _gen_invoice_pdf(path, *arg)
        else:
            _gen_data_xlsx(path, kind, rng)
        files.append({"id": f"F{i}", "name": name, "path": path,
                      "folder": folder})
    return files


def digest_of(path):
    """内容摘要（模型据此判断不可读名文件的类别）。"""
    p = str(path)
    try:
        if p.endswith(".docx"):
            import docx
            paras = [x.text for x in docx.Document(p).paragraphs
                     if x.text.strip()]
            return " / ".join(paras[:3])[:160]
        if p.endswith(".pptx"):
            from pptx import Presentation
            sl = Presentation(p).slides[0]
            texts = []
            for shape in sl.shapes:
                if shape.has_text_frame:
                    t = shape.text_frame.text.strip()
                    if t:
                        texts.append(t)
            return " / ".join(texts)[:160]
        if p.endswith(".pdf"):
            from pypdf import PdfReader
            return PdfReader(p).pages[0].extract_text()[:160].replace("\n", " ")
        if p.endswith(".xlsx"):
            df = __import__("pandas").read_excel(p)
            return "列: " + ", ".join(map(str, df.columns.tolist()))
    except Exception as e:  # 摘要失败不阻塞任务（文件名仍可见）
        return f"<摘要失败: {type(e).__name__}>"
    return ""


# ---------------- 周报生成（merge 输入） ----------------

def gen_reports(rng, smoke):
    import docx
    spec_full = [
        ("mobile", "移动端", "张伟", "正常", 1),
        ("backend", "后端服务", "李娜", "滞后", 2),
        ("data", "数据组", "王强", "正常", 0),
    ]
    spec = spec_full[:2] if smoke else spec_full
    files, gt = {}, {}
    for key, team, owner, status, n in spec:
        d = docx.Document()
        d.add_heading(f"{team}周报", level=1)
        d.add_paragraph(f"负责人：{owner}")
        d.add_paragraph(f"本周状态：{status}")
        d.add_heading("本周风险", level=2)
        if n == 0:
            d.add_paragraph("无。")
        else:
            for i in range(1, n + 1):
                d.add_paragraph(f"{i}. 风险项 {i}：进度依赖外部联调，"
                                f"需协调资源。")
        d.add_paragraph("下周按计划推进收尾工作。")
        path = WORK / f"report_{key}.docx"
        d.save(str(path))
        files[key] = path
        gt[key] = {"team": team, "status": status, "risks": n}
    gt["lagging"] = sorted(v["team"] for k, v in gt.items()
                           if isinstance(v, dict) and v.get("status") == "滞后")
    gt["risk_total"] = sum(v["risks"] for k, v in gt.items()
                           if isinstance(v, dict) and "risks" in v)
    return files, gt


def read_docx_text(path):
    import docx
    return "\n".join(p.text for p in docx.Document(str(path)).paragraphs
                     if p.text.strip())


# ---------------- runner 主干 ----------------

def checkpoint(store):
    OUT.write_text(json.dumps(store, ensure_ascii=False, indent=1))


def add_row(store, **kw):
    store["runs"].append(kw)
    checkpoint(store)
    t = kw.get("trace") or {}
    print(f"  [{kw.get('task')}/{kw.get('scenario')}] wall={kw.get('wallS')}s "
          f"verdict={kw.get('verdict')} mode={t.get('mode')} "
          f"reuse={t.get('reuse')} tok={t.get('promptTokens')}", flush=True)


def chat_turn(store, task, scenario, attempt, session, messages,
              session_key, max_tokens):
    r = rm.chat(session, messages, tools=build_tools(), max_tokens=max_tokens)
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
    row["verdict"] = "pass"
    add_row(store, **row)
    return r[0], row


def repair_once(store, task, tag, attempt, session, messages, session_key,
                max_tokens, tool="submit_result"):
    ask = ("请必须调用 verify(ok,issues) 提交核对结论（简短作答）。"
           if tool == "verify" else
           "请必须调用 submit_result 提交，payload 每行 'key|值'。")
    m = messages + [rm.user(f"你的上一条回复没有按要求调用工具（可能因长度被截断）。{ask}")]
    return chat_turn(store, task, tag, attempt, session, m, session_key,
                     max_tokens)


def run_organize(store, attempt, session, ctx):
    files, gt = ctx["organize_files"], ctx["gt"]["organize"]
    listing = "\n".join(
        f"{f['id']} | {f['name']} | 摘要: {digest_of(f['path'])}"
        for f in files)
    m = [rm.user(
        f"以下是一个待整理文件夹中的 {len(files)} 个文件（id | 文件名 | 内容摘要）。\n"
        f"{listing}\n\n"
        f"请把每个文件归入最合适的目标文件夹：{'/'.join(FOLDERS)}。"
        f"判断依据是文件名与内容摘要。完成后调用 submit_result，"
        f"payload 每行 'F编号|文件夹名'（每个文件一行）。")]
    msg, row = chat_turn(store, "organize", "organize_t1", attempt, session,
                         m, None, 1024)
    skey = (row.get("trace") or {}).get("session")
    parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None and msg is not None:
        msg, row = repair_once(store, "organize", "organize_t1", attempt,
                               session, m, skey, 1024)
        parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None:
        return {"task": "organize", "attempt": attempt, "accuracy": 0,
                "payloadOk": False}

    # harness 确定性执行：按模型决策复制归档
    dest_root = WORK / f"organize_a{attempt}"
    placements = {}
    for f in files:
        given = parsed.get(f["id"], "").strip()
        placements[f["id"]] = given
        if given:
            dest = dest_root / given
            dest.mkdir(parents=True, exist_ok=True)
            shutil.copy2(str(f["path"]), str(dest / f["path"].name))
    ok = sum(1 for f in files
             if placements.get(f["id"]) == f["folder"])
    total = len(files)
    m.append({"role": "tool", "tool_call_id": _last_call_id(m),
              "content": f"执行完成：已按你的分类将 {sum(1 for v in placements.values() if v)}"
                         f" 个文件复制归档到 {dest_root.name}/ 下对应文件夹。"})
    m.append(rm.user("请调用 verify(ok,issues) 确认你的分类与各文件内容相符。"))
    msg2, row2 = chat_turn(store, "organize", "organize_t2", attempt, session,
                           m, skey, 512)
    v = tool_args(msg2, "verify") if msg2 else None
    if v is None and msg2 is not None:
        msg2, row2 = repair_once(store, "organize", "organize_t2", attempt,
                                 session, m, skey, 512, tool="verify")
        v = tool_args(msg2, "verify") if msg2 else None
    return {"task": "organize", "attempt": attempt,
            "accuracy": round(ok / total, 3),
            "placed": f"{ok}/{total}",
            "payloadOk": True, "verifyOk": (v or {}).get("ok"),
            "placements": placements}


def run_merge(store, attempt, session, ctx):
    rep_files, gt = ctx["report_files"], ctx["gt"]["merge"]
    body = "\n\n".join(
        f"【{k}｜{TEAMS_BY_KEY[k]}】\n{read_docx_text(p)}"
        for k, p in rep_files.items())
    key_map = "、".join(f"{k}={TEAMS_BY_KEY[k]}" for k in rep_files)
    m = [rm.user(
        f"以下是团队周报（Word 导出文本），key 对照：{key_map}。\n{body}\n\n"
        f"请先逐队提取（仅上列团队），再做跨队整合。完成后调用 submit_result，"
        f"payload 每队两行：'{'<key>'}_status|…'、'{'<key>'}_risks|…'"
        f"（状态为 正常/滞后，风险为条数）；以及整合项 "
        f"'lagging_teams|滞后团队（用上列 key，逗号分隔，无则填 无）'、"
        f"'risk_total|风险总条数'。")]
    msg, row = chat_turn(store, "merge", "merge_t1", attempt, session, m,
                         None, 768)
    skey = (row.get("trace") or {}).get("session")
    parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None and msg is not None:
        msg, row = repair_once(store, "merge", "merge_t1", attempt, session,
                               m, skey, 768)
        parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None:
        return {"task": "merge", "attempt": attempt, "accuracy": 0,
                "payloadOk": False}

    checks = {}
    hit = 0
    for key, _, _ in TEAMS:
        if key not in gt:
            continue  # smoke 只含部分队
        s_ok = parsed.get(f"{key}_status", "").strip() == gt[key]["status"]
        r_ok = num_of(parsed.get(f"{key}_risks")) == gt[key]["risks"]
        hit += s_ok + r_ok
        checks[key] = {"status": s_ok, "risks": r_ok}
    given_lag = {x.strip() for x in
                 parsed.get("lagging_teams", "").replace("，", ",").split(",")
                 if x.strip() and x.strip() != "无"}
    # 模型可能用 key 或中文团队名回答（smoke 实证 backend/后端服务）——
    # 统一经 key→名称映射归一后比对
    given_lag = {TEAMS_BY_KEY.get(x, x) for x in given_lag}
    l_ok = given_lag == set(gt["lagging"])
    t_ok = num_of(parsed.get("risk_total")) == gt["risk_total"]
    hit += l_ok + t_ok
    checks["lagging"] = l_ok
    checks["risk_total"] = t_ok
    total = 2 * len([k for k, _, _ in TEAMS if k in gt]) + 2

    m.append({"role": "tool", "tool_call_id": _last_call_id(m),
              "content": f"执行完成：逐队提取与跨队整合共 {total} 项已登记，"
                         f"整合版周报由工作流汇编。"})
    m.append(rm.user("请调用 verify(ok,issues) 确认你的提取与各队周报原文一致。"))
    msg2, row2 = chat_turn(store, "merge", "merge_t2", attempt, session, m,
                           skey, 512)
    v = tool_args(msg2, "verify") if msg2 else None
    if v is None and msg2 is not None:
        msg2, row2 = repair_once(store, "merge", "merge_t2", attempt, session,
                                 m, skey, 512, tool="verify")
        v = tool_args(msg2, "verify") if msg2 else None
    return {"task": "merge", "attempt": attempt,
            "accuracy": round(hit / total, 3), "checks": checks,
            "payloadOk": True, "verifyOk": (v or {}).get("ok"),
            "submitted": parsed}


TEAMS_BY_KEY = {k: t for k, t, _ in TEAMS}
RUNNERS = {"organize": run_organize, "merge": run_merge}


def write_digest_docx(store, attempt):
    """整合产物：由 merge 最新提交汇编跨队周报 docx。"""
    import docx
    latest = {}
    for s in store.get("task_summaries", []):
        if s.get("task") == "merge" and s.get("submitted"):
            latest = s
    if not latest:
        return None
    p = latest["submitted"]
    d = docx.Document()
    d.add_heading("跨队周报整合（Local Office 工作流）", level=1)
    d.add_paragraph(f"attempt {attempt} · 由各团队周报提取整合生成")
    for key, team, _ in TEAMS:
        if f"{key}_status" in p:
            d.add_heading(f"{team}（{p.get(key + '_status', '?')}）", level=2)
            d.add_paragraph(f"风险 {p.get(key + '_risks', '?')} 条")
    d.add_heading("整合结论", level=2)
    d.add_paragraph(f"滞后团队：{p.get('lagging_teams', '?')}")
    d.add_paragraph(f"风险总数：{p.get('risk_total', '?')}")
    path = WORK / f"team_weekly_digest_a{attempt}.docx"
    d.save(str(path))
    return path


def task_complete(store, task, attempt):
    have = {r["scenario"] for r in store["runs"]
            if r.get("task") == task and r.get("attempt") == attempt}
    return set(TASK_SCENARIOS[task]) <= have


def main():
    ap = argparse.ArgumentParser(
        description="V1.7-3c office folder & multi-doc merge")
    ap.add_argument("--tasks", default="organize,merge")
    ap.add_argument("--smoke", action="store_true",
                    help="冒烟：5 文件/2 队（独立结果文件与 seed）")
    ap.add_argument("--seed", type=int, default=20260920)
    ap.add_argument("--redo", default="",
                    help="强制重跑为新 attempt（逗号分隔任务名）")
    args = ap.parse_args()
    global OUT
    if args.smoke:
        OUT = OUT.with_name("results_v17_3_office_folder_smoke.json")
    WORK.mkdir(parents=True, exist_ok=True)

    tasks = [x.strip() for x in args.tasks.split(",") if x.strip()]
    rng = random.Random(args.seed + (11 if args.smoke else 0))

    print("[data] 生成待整理文件与团队周报…", flush=True)
    organize_files = gen_organize_files(rng, args.smoke)
    report_files, gt_merge = gen_reports(rng, args.smoke)
    gt = {"organize": {f["id"]: f["folder"] for f in organize_files},
          "merge": gt_merge}
    (WORK / "ground_truth_folder.json").write_text(
        json.dumps(gt, ensure_ascii=False, indent=1))
    print(f"[data] organize={len(organize_files)} files, "
          f"merge={len(report_files)} reports, gt_merge={gt_merge}",
          flush=True)

    store = json.loads(OUT.read_text()) if OUT.exists() else {
        "model": rm.MODEL,
        "meta": {**rm.experiment_meta(),
                 "serializeGeneration": "true (生产常量)",
                 "smoke": args.smoke, "seed": args.seed},
        "design": ("V1.7-3c: organize (10 mixed files -> 4 folders, "
                   "model decides, harness copies) + merge (3 team "
                   "docx reports -> extract 6 + integrate 2, exact "
                   "scored); per-task attempt unit"),
        "runs": []}
    ctx = {"organize_files": organize_files, "report_files": report_files,
           "gt": gt}

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
        prefix = "h" if args.smoke else "g"
        session = f"{prefix}{attempt}{SESSION_OF[task]}"
        assert len(session) <= 6, f"session 超长: {session}"
        print(f"===== folder/{task} attempt {attempt} "
              f"(session={session}) =====", flush=True)
        summary = RUNNERS[task](store, attempt, session, ctx)
        store.setdefault("task_summaries", [])
        store["task_summaries"] = [
            s for s in store["task_summaries"]
            if not (s["task"] == task and s["attempt"] == attempt)]
        store["task_summaries"].append(summary)
        checkpoint(store)

    # 整合产物 docx
    rep = write_digest_docx(store, max(
        (s.get("attempt", 1) for s in store.get("task_summaries", [])),
        default=1))
    if rep:
        print(f"[artifact] 整合周报已写出: {rep}", flush=True)

    print("\n=== V1.7-3c 汇总 ===", flush=True)
    for s in store.get("task_summaries", []):
        extras = {k: v for k, v in s.items()
                  if k in ("placed", "checks", "verifyOk")}
        print(f"  {s['task']} a{s['attempt']}: acc={s.get('accuracy')} "
              f"payloadOk={s.get('payloadOk')} {extras}", flush=True)
    print("=== 完成 ===", flush=True)


if __name__ == "__main__":
    main()
