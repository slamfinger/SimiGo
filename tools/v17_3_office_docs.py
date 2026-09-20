#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V1.7-3b Local Office——文档格式扩展（Word/PPT/PDF 支持测试，2026-09-20）。

承接 V1.7-3（040201c，Excel 已收官）：把办公文件支持测试扩展到三种
文档格式，纪律完全一致（固定工作流、模型决策+harness 确定性执行、
ground truth 同源生成→精确评分、payload='key|值' 行、per-task attempt、
verdict 三值、reply 摘录审计）。

任务矩阵（输入解析走对应格式库，模型只见提取后的文本）：
  word_minutes  2×.docx 会议纪要（python-docx 生成/解析）
                → 提取每份行动项条数+会议类型（闭集）
  ppt_outline   1×.pptx 项目汇报 9 页（python-pptx 生成/解析）
                → 总页数/风险页码/项目代号
  pdf_invoices  4×.pdf 发票单（reportlab STSong-Light 中文 CID 字体）
                → 未付总额+笔数（pypdf 提取，round-trip 已验证）
输出产物：docs_weekly_report_a{n}.docx（python-docx 写出——输出侧
Word 支持同步覆盖），由各任务模型提交的 payload 汇编。

生成/提取库：python-docx 1.2.0、python-pptx 1.0.2、reportlab 5.0.1
（UnicodeCIDFont STSong-Light）、pypdf 6.19.0（pip --user 安装）。
范围边界（能力声明以记录在案的运行为准；2026-09-20 外审核验修正）：
  scan 任务=扫描样式发票 PDF。24238b0 的 attempt-1/2 实为文本层变体、
  pypdf 直抽（模型见干净文本，非 OCR 输出）；attempt-3 起生成真栅格化
  图片型 PDF（pdftoppm 200dpi→Tesseract chi_sim OCR），证据以 results
  JSON 的 genMode/extractMode 为准。仍不在范围：旋转/倾斜/印章遮挡/
  多栏排版/手写体/跨页关联。

用法：python3 tools/v17_3_office_docs.py [--tasks word,ppt,pdf] [--smoke]
前置：SimiGo 运行中（生产策略）、无进行中生成。
"""
import os  # noqa: E402  （OCR/图片路径子进程用）
import shutil  # noqa: E402  （OCR 二进制 PATH 解析）
import argparse
import json
import random
import subprocess
from pathlib import Path

import runtime_matrix as rm
from v17_2_concurrency import anomaly_count, evictions_since, mem_after
from v17_3_office import (_last_call_id, _reply_excerpt, parse_payload,
                          tool_args, tool_payload)

OUT = Path("docs/experiments/V17_RUNTIME_MATRIX/results_v17_3_office_docs.json")
WORK = Path("docs/experiments/V17_RUNTIME_MATRIX/office_out/docs")

MEETING_TYPES = ["周例会", "评审会", "规划会"]
TOOLS = None  # 延迟构建（复用 v17_3 的工具定义形状）


def build_tools():
    from v17_3_office import VERIFY_TOOL, SUBMIT_TOOL
    return [SUBMIT_TOOL, VERIFY_TOOL]


TASK_SCENARIOS = {
    "word": ["word_t1", "word_t2"],
    "ppt": ["ppt_t1", "ppt_t2"],
    "pdf": ["pdf_t1", "pdf_t2"],
    "scan": ["scan_t1", "scan_t2"],
}
SESSION_OF = {"word": "w", "ppt": "t", "pdf": "f",
             "scan": "x"}


# ---------------- 数据生成（确定性） ----------------

def gen_word_docs(rng, smoke):
    """会议纪要 .docx ×2。返回 (files, gt)。"""
    spec = [
        {"file": "minutes_周例会.docx", "title": "移动端 v2.1 周例会纪要",
         "type": "周例会", "date": "2026-09-14", "attendees": 4,
         "n_actions": 1 if smoke else 4},
        {"file": "minutes_评审会.docx", "title": "搜索服务设计评审会纪要",
         "type": "评审会", "date": "2026-09-16", "attendees": 3,
         "n_actions": 1 if smoke else 3},
    ]
    import docx
    people = ["张伟", "李娜", "王强", "刘洋", "陈静", "赵磊"]
    files, gt = [], {}
    for i, s in enumerate(spec, 1):
        d = docx.Document()
        d.add_heading(s["title"], level=1)
        d.add_paragraph(f"日期：{s['date']}")
        d.add_paragraph(f"参会人：{'、'.join(rng.sample(people, s['attendees']))}")
        d.add_paragraph("会议讨论了当前进展、遇到的问题与下一步安排，"
                        "与会人员分别汇报了各自模块的状态。")
        d.add_heading("行动项", level=2)
        for a in range(1, s["n_actions"] + 1):
            who = rng.choice(people)
            due = f"2026-09-{17 + a:02d}"
            d.add_paragraph(f"{a}. {who}：跟进第 {a} 项遗留问题，"
                            f"期限 {due}。")
        d.add_paragraph("下次会议时间另行通知。")
        path = WORK / s["file"]
        d.save(path)
        files.append({"path": path, "title": s["title"]})
        gt[f"m{i}"] = {"type": s["type"], "actions": s["n_actions"]}
    return files, gt


def gen_ppt(rng, smoke):
    """项目汇报 .pptx ×1。返回 (path, gt)。"""
    from pptx import Presentation
    from pptx.util import Pt
    n = 5 if smoke else 9
    risk_at = [3] if smoke else [3, 7]
    code = "PHX7" if smoke else "PHOENIX"
    titles = ["项目季度汇报", "项目进展总览", "进度风险与应对",
              "资源投入情况", "关键里程碑回顾", "质量指标走势",
              "预算风险控制", "下一步计划", "附录与数据来源"][:n]
    # smoke 时保证含 1 个风险页
    if smoke:
        titles[2] = "进度风险与应对"
    prs = Presentation()
    for i, t in enumerate(titles, 1):
        slide = prs.slides.add_slide(prs.slide_layouts[1])
        slide.shapes.title.text = t
        body = slide.placeholders[1].text_frame
        if i == 1:
            body.text = f"项目代号：{code}"
            p = body.add_paragraph()
            p.text = "汇报人：项目治理组"
        elif i in risk_at:
            body.text = "本节识别当前主要风险并提出缓解措施。"
        else:
            body.text = f"第 {i} 节要点与数据。"
    path = WORK / "project_review.pptx"
    prs.save(path)
    gt = {"total_slides": n,
          "risk_slides": sorted(risk_at),
          "project_code": code}
    return path, gt


def gen_pdfs(rng, smoke):
    """发票 .pdf ×N（中文 CID 字体）。返回 (paths, gt)。"""
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.cidfonts import UnicodeCIDFont
    from reportlab.pdfgen import canvas
    pdfmetrics.registerFont(UnicodeCIDFont('STSong-Light'))
    rows = [(101, "客户甲", 7686.82, "已付"), (102, "客户乙", 5602.13, "未付"),
            (103, "客户丙", 18293.49, "已付"), (104, "客户丁", 14317.90, "未付")]
    if smoke:
        rows = rows[:2]
    paths = []
    for no, client, amount, status in rows:
        path = WORK / f"invoice_{no}.pdf"
        c = canvas.Canvas(str(path))
        c.setFont('STSong-Light', 14)
        c.drawString(72, 780, f"发票编号: INV-2026-{no}")
        c.setFont('STSong-Light', 12)
        c.drawString(72, 755, f"客户: {client}")
        c.drawString(72, 735, f"金额: {amount:.2f} 元")
        c.drawString(72, 715, f"状态: {status}")
        c.save()
        paths.append(path)
    unpaid = [(a, s) for _, _, a, s in rows if s == "未付"]
    gt = {"unpaid_total": round(sum(a for a, _ in unpaid), 2),
          "unpaid_count": len(unpaid)}
    return paths, gt


def gen_scan_pdfs(rng, smoke):
    """扫描件发票 PDF ×N（栅格化图片型：无文本层必走 OCR；pdftoppm 缺失时
    回退文本层并在 _GEN_MODE 标注）。返回 (files, gt)。"""
    rows = [(301, "客户甲", 9876.54, "未付"), (302, "客户乙", 3210.00, "已付"),
            (303, "客户丙", 15678.90, "未付")]
    if smoke:
        rows = rows[:2]
    files, gt_invoices = [], []
    for no, client, amount, status in rows:
        path = WORK / f"invoice_scan_{no}.pdf"
        generate_scan_pdf(path, client, amount, status, rng)
        files.append({"name": path.name, "path": path})
        gt_invoices.append({"no": no, "client": client,
                            "amount": round(amount, 2), "status": status})
    gt = {"invoices": gt_invoices}
    return files, gt


# ---------------- 文件文本提取（模型只见文本） ----------------

def read_docx(path):
    import docx
    return "\n".join(p.text for p in docx.Document(str(path)).paragraphs
                     if p.text.strip())


def read_pptx(path):
    from pptx import Presentation
    lines = []
    for i, slide in enumerate(Presentation(str(path)).slides, 1):
        texts = []
        for shape in slide.shapes:
            if shape.has_text_frame:
                for para in shape.text_frame.paragraphs:
                    t = "".join(run.text for run in para.runs).strip()
                    if t:
                        texts.append(t)
        lines.append(f"--- 第{i}页 ---\n" + "\n".join(texts))
    return "\n".join(lines)


def read_pdf(path):
    from pypdf import PdfReader
    return "\n".join(page.extract_text() for page in PdfReader(str(path)).pages)


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
    """malformed/缺 tool call 修复轮（V1.7-2/3 纪律：1 次，提示按目标工具）。"""
    ask = ("请必须调用 verify(ok,issues) 提交核对结论（简短作答）。"
           if tool == "verify" else
           "请必须调用 submit_result 提交，payload 每行 'key|值'。")
    m = messages + [rm.user(f"你的上一条回复没有按要求调用工具（可能因长度被截断）。{ask}")]
    return chat_turn(store, task, tag, attempt, session, m, session_key,
                     max_tokens)


def run_word(store, attempt, session, ctx):
    docs, gt = ctx["word_files"], ctx["gt"]["word"]
    body = "\n\n".join(f"【{d['title']}】\n{read_docx(d['path'])}"
                       for d in docs)
    m = [rm.user(f"以下是两份会议纪要（Word 导出文本）。\n{body}\n\n"
                 f"请对每份纪要提取：会议类型（{'/'.join(MEETING_TYPES)}）"
                 f"与行动项条数。完成后调用 submit_result，payload 四行："
                 f"'m1_type|…'、'm1_actions|…'、'm2_type|…'、'm2_actions|…'。")]
    msg, row = chat_turn(store, "word", "word_t1", attempt, session, m,
                         None, 512)
    skey = (row.get("trace") or {}).get("session")
    parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None and msg is not None:
        msg, row = repair_once(store, "word", "word_t1", attempt, session,
                               m, skey, 512)
        parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None:
        return {"task": "word", "attempt": attempt, "accuracy": 0,
                "payloadOk": False}
    hit = 0
    checks = {}
    for k, g in gt.items():
        t_ok = parsed.get(f"{k}_type", "").strip() == g["type"]
        a_ok = parsed.get(f"{k}_actions", "").strip() == str(g["actions"])
        hit += t_ok + a_ok
        checks[k] = {"type": t_ok, "actions": a_ok}
    acc = round(hit / 4, 3)
    m.append({"role": "tool", "tool_call_id": _last_call_id(m),
              "content": f"已登记两份纪要的类型与行动项条数（4 项）。"})
    m.append(rm.user("请调用 verify(ok,issues) 确认你的提取与纪要内容一致。"))
    msg2, row2 = chat_turn(store, "word", "word_t2", attempt, session, m,
                           skey, 512)
    v = tool_args(msg2, "verify") if msg2 else None
    if v is None and msg2 is not None:
        msg2, row2 = repair_once(store, "word", "word_t2", attempt, session,
                                 m, skey, 512, tool="verify")
        v = tool_args(msg2, "verify") if msg2 else None
    return {"task": "word", "attempt": attempt, "accuracy": acc,
            "checks": checks, "payloadOk": True,
            "verifyOk": (v or {}).get("ok"), "submitted": parsed}


def run_ppt(store, attempt, session, ctx):
    path, gt = ctx["ppt_path"], ctx["gt"]["ppt"]
    body = read_pptx(path)
    m = [rm.user(f"以下是项目汇报 PPT 的逐页文本。\n{body}\n\n"
                 f"请提取三项信息：总页数、含「风险」的页码列表（逗号分隔）、"
                 f"项目代号。完成后调用 submit_result，payload 三行："
                 f"'total_slides|…'、'risk_slides|…'（如 3,7）、"
                 f"'project_code|…'。")]
    msg, row = chat_turn(store, "ppt", "ppt_t1", attempt, session, m,
                         None, 512)
    skey = (row.get("trace") or {}).get("session")
    parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None and msg is not None:
        msg, row = repair_once(store, "ppt", "ppt_t1", attempt, session,
                               m, skey, 512)
        parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None:
        return {"task": "ppt", "attempt": attempt, "accuracy": 0,
                "payloadOk": False}
    t_ok = parsed.get("total_slides", "").strip() == str(gt["total_slides"])
    given_risk = {x.strip() for x in parsed.get("risk_slides", "").split(",")
                  if x.strip()}
    r_ok = given_risk == {str(x) for x in gt["risk_slides"]}
    c_ok = parsed.get("project_code", "").strip().upper() == \
        gt["project_code"].upper()
    hit = sum([t_ok, r_ok, c_ok])
    m.append({"role": "tool", "tool_call_id": _last_call_id(m),
              "content": "已登记：页数、风险页码、项目代号（3 项）。"})
    m.append(rm.user("请调用 verify(ok,issues) 确认你的提取与 PPT 内容一致。"))
    msg2, row2 = chat_turn(store, "ppt", "ppt_t2", attempt, session, m,
                           skey, 512)
    v = tool_args(msg2, "verify") if msg2 else None
    if v is None and msg2 is not None:
        msg2, row2 = repair_once(store, "ppt", "ppt_t2", attempt, session,
                                 m, skey, 512, tool="verify")
        v = tool_args(msg2, "verify") if msg2 else None
    return {"task": "ppt", "attempt": attempt,
            "accuracy": round(hit / 3, 3),
            "checks": {"total": t_ok, "risk": r_ok, "code": c_ok},
            "payloadOk": True, "verifyOk": (v or {}).get("ok"),
            "submitted": parsed}


def run_pdf(store, attempt, session, ctx):
    paths, gt = ctx["pdf_paths"], ctx["gt"]["pdf"]
    body = "\n\n".join(f"【{p.name}】\n{read_pdf(p)}" for p in paths)
    m = [rm.user(f"以下是发票 PDF 的文本内容。\n{body}\n\n"
                 f"请汇总未付发票的总金额与笔数。完成后调用 submit_result，"
                 f"payload 两行：'unpaid_total|金额'、'unpaid_count|笔数'。")]
    msg, row = chat_turn(store, "pdf", "pdf_t1", attempt, session, m,
                         None, 512)
    skey = (row.get("trace") or {}).get("session")
    parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None and msg is not None:
        msg, row = repair_once(store, "pdf", "pdf_t1", attempt, session,
                               m, skey, 512)
        parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None:
        return {"task": "pdf", "attempt": attempt, "accuracy": 0,
                "payloadOk": False}
    try:
        # 模型会带单位提交（smoke 实证 '5602.13 元'/'1 笔'）——剥掉非数值
        # 字符再解析（千分位/单位容错）
        t = float("".join(ch for ch in parsed.get("unpaid_total", "")
                          if ch.isdigit() or ch == ".") or "nan")
        c = int("".join(ch for ch in parsed.get("unpaid_count", "")
                        if ch.isdigit()) or "-1")
    except (TypeError, ValueError):
        t, c = None, None
    ok = (t is not None and abs(t - gt["unpaid_total"]) <= 0.01
          and c == gt["unpaid_count"])
    m.append({"role": "tool", "tool_call_id": _last_call_id(m),
              "content": f"已登记：未付总额 {parsed.get('unpaid_total')}，"
                         f"笔数 {parsed.get('unpaid_count')}。"})
    m.append(rm.user("请调用 verify(ok,issues) 确认你的汇总与发票数据一致。"))
    msg2, row2 = chat_turn(store, "pdf", "pdf_t2", attempt, session, m,
                           skey, 512)
    v = tool_args(msg2, "verify") if msg2 else None
    if v is None and msg2 is not None:
        msg2, row2 = repair_once(store, "pdf", "pdf_t2", attempt, session,
                                 m, skey, 512, tool="verify")
        v = tool_args(msg2, "verify") if msg2 else None
    return {"task": "pdf", "attempt": attempt, "accuracy": 1 if ok else 0,
            "submitted": {"unpaid_total": t, "unpaid_count": c},
            "truthTotal": gt["unpaid_total"], "truthCount": gt["unpaid_count"],
            "payloadOk": True, "verifyOk": (v or {}).get("ok")}


SCAN_TMP = Path("docs/experiments/V17_RUNTIME_MATRIX/office_out/scanstmp")
# provenance：每文件生成/提取走向，随 task_summaries 入 results（外审修正）。
_GEN_MODE = {}
_EXTRACT_MODE = {}
# PDF 是否含文本层由 pypdf 判定；无文本层则走 OCR。
_PDF_HAS_TEXT_CACHE = {}
# psm: 6=假定单块文本, 11=稀疏空格（默认）
_TESS_PSM = 6
# PDF→PNG 分辨率（dpi）。2026-09-20 实测对照（chi_sim psm6，本版式）：
# 150dpi=四行全读但客户甲→客户四；200dpi=客户正确但末行状态常丢；
# 300dpi=双页四行字段值全对（标签偶有噪声：发标/人金额）。定档 300。
_OCR_DPI = 300


def _resolve_bin(name: str) -> str:
    """OCR 外部工具 PATH 解析（v1.7-3d 修正：/usr/bin 硬编码在本机不存在）。"""
    p = shutil.which(name)
    if not p:
        raise RuntimeError(
            f"{name} 不在 PATH（brew install tesseract poppler）——"
            "生成侧回退文本层并在 genMode 标注；提取侧图片型 PDF 无文本层不可虚读")
    return p


def pdf_has_text(path: Path) -> bool:
    """pypdf 判定 PDF 是否含文本层（有则无需 OCR）。"""
    key = str(path)
    if key in _PDF_HAS_TEXT_CACHE:
        return _PDF_HAS_TEXT_CACHE[key]
    try:
        from pypdf import PdfReader
        r = PdfReader(str(path))
        n = 0
        for page in r.pages:
            t = (page.extract_text() or "").strip()
            n += len(t)
            if n > 8:
                _PDF_HAS_TEXT_CACHE[key] = True
                return True
        # 读完仍未累计>8字，记 False（避免重复判定）
    except Exception:
        pass
    _PDF_HAS_TEXT_CACHE[key] = False
    return False


def _pdftoppm(pdf_path: Path, png_prefix: Path) -> list[Path]:
    """用系统 pdftoppm 把单页/多页 PDF 转成 PNG（避免 Tesseract 内部 PDF→pix）。"""
    import subprocess
    st = os.stat(pdf_path)  # 单页 PDF 仍命名 pg-1.png
    cmd = [_resolve_bin("pdftoppm"), "-png", "-r", str(_OCR_DPI),
           str(pdf_path), str(png_prefix)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"pdftoppm failed: {r.stderr.strip()}")
    return sorted(Path(png_prefix.parent).glob(f"{png_prefix.name}-*.png"))


def _tesseract(path: Path, lang: str = "chi_sim", psm: int = 6) -> str:
    """命令行 Tesseract OCR（__version_info==5）。"""
    import subprocess
    env = os.environ.copy()
    env.setdefault("LC_ALL", "UTF-8")
    cmd = [_resolve_bin("tesseract"), str(path), "stdout", "-l", lang,
           "--psm", str(psm)]
    r = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if r.returncode != 0:
        raise RuntimeError(f"tesseract failed: {r.stderr.strip()[:300]}")
    return r.stdout


def generate_scan_pdf(path: Path, client: str, amount: float, status: str,
                      rng) -> None:
    """生成扫描件发票 PDF：reportlab 绘制→pdftoppm 200dpi 栅格化→图片型
    （无文本层，read_scan_pdf 必走 Tesseract OCR）。

    pdftoppm 不可用时回退文本层 PDF 并在 _GEN_MODE 标注——名义扫描件、
    实为文本层提取，provenance 如实入 results（v1.7-3d 外审修正：
    24238b0 版本名为扫描件、实产带文本层，OCR 分支未被记录运行走到）。
    """
    from reportlab.lib.pagesizes import letter
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.cidfonts import UnicodeCIDFont
    from reportlab.pdfgen import canvas
    pdfmetrics.registerFont(UnicodeCIDFont('STSong-Light'))
    SCAN_TMP.mkdir(parents=True, exist_ok=True)
    src = SCAN_TMP / f"{path.stem}_src.pdf"
    c = canvas.Canvas(str(src))
    c.setFont('STSong-Light', 16)
    c.drawString(72, 780, f"发票编号: INV-2026-{int(path.stem.split('_')[-1])}")
    c.setFont('STSong-Light', 14)
    c.drawString(72, 750, f"客户: {client}")
    c.drawString(72, 730, f"金额: {amount:.2f} 元")
    c.drawString(72, 710, f"状态: {status}")
    c.save()
    try:
        pages = _pdftoppm(src, SCAN_TMP / path.stem)
        c2 = canvas.Canvas(str(path), pagesize=letter)
        c2.drawImage(str(pages[0]), 0, 0, letter[0], letter[1])
        c2.showPage()
        c2.save()
        _GEN_MODE[path.name] = f"rasterized-imageonly(pdftoppm {_OCR_DPI}dpi)"
    except Exception as e:
        os.replace(src, path)
        _GEN_MODE[path.name] = f"textlayer-fallback({type(e).__name__})"


def _read_scan_pdf_ocr(path: Path) -> str:
    """无文本层 PDF → pdftoppm→PNG→Tesseract。返回全文（自动跳高分贝页）。"""
    if not path.exists():
        return ""
    SCAN_TMP.mkdir(parents=True, exist_ok=True)
    png_prefix = SCAN_TMP / path.stem
    try:
        pages = _pdftoppm(path, png_prefix)
    except Exception:
        # pdftoppm 不可用回退：直接让 Tesseract 读 PDF。
        return _tesseract(str(path), "chi_sim")
    texts, prev_score = [], -2.0
    for i in range(len(pages)):
        psm = 6 if len(pages) == 1 else 11
        txt = _tesseract_scan_png(pages[i], psm)
        if i == 0:
            prev_score = _text_is_suspicious_score(txt)
        elif i >= 1 and _text_is_suspicious_score(txt) > prev_score + 0.3:
            # 相邻高分贝页→大概率转场噪声，跳过。
            continue
        texts.append(txt)
    return "\n".join(t for t in texts if t.strip())


def _tesseract_scan_png(png_path: Path, psm: int = 6) -> str:
    """从 PNG（_pdftoppm 产物）OCR；LC_ALL=UTF-8 避占位符。

    v1.7-3d 修正：--psm 须分离传参（--psm6 合并写法被 tesseract 拒绝、
    returncode≠0 曾被静默吞成空串）；失败显式抛错，不产垃圾运行。
    """
    import subprocess
    r = subprocess.run([_resolve_bin("tesseract"), str(png_path), "stdout",
                        "-l", "chi_sim", "--psm", str(psm)],
                       capture_output=True, text=True,
                       env={**os.environ, "LC_ALL": "UTF-8"})
    if r.returncode != 0:
        raise RuntimeError(f"tesseract failed: {r.stderr.strip()[:300]}")
    return r.stdout


def _text_is_suspicious_score(txt: str) -> float:
    """启发式：检测 OCR 噪声（大面积连续重复单字符 = 转场/页脚噪声）。"""
    if not txt:
        return -1.0
    import re
    runs = re.findall(r'(.)\1{8,}', txt)  # ≥9 连字
    return len(runs) + sum(len(x) - 8 for x in runs) * 0.5


def read_scan_pdf(path: Path) -> str:
    """扫描件/图片型 PDF 文本提取（harness 端；→ 模型只见此文本）。

    走向由 pdf_has_text 决定并记入 _EXTRACT_MODE——pypdf-textlayer 与
    tesseract-ocr 是两种证据等级，results 如实区分（v1.7-3d 外审修正）。
    """
    if pdf_has_text(path):
        from pypdf import PdfReader
        _EXTRACT_MODE[path.name] = "pypdf-textlayer"
        return "\n".join(p.extract_text() for p in PdfReader(str(path)).pages)
    _EXTRACT_MODE[path.name] = "tesseract-ocr"
    return _read_scan_pdf_ocr(path)


def _inv_canon(key: str) -> str:
    """发票 key 归一：取尾部数字段。INV-2026-301/inv-301/301 → '301'。

    外审 P2-1（24238b0 attempt-1 文档原样 key 被精确匹配判 0）：评分归一
    到业务编号；原始提交键仍在 summary.submitted 留审计；不做全字符串放宽。
    """
    import re
    m = re.search(r'(\d+)\D*$', (key or "").strip())
    return m.group(1) if m else (key or "").strip().lower()


def score_scan_payload(parsed, gt):
    """逐发票客户/金额/状态三项核对（同 pdf runner 风格）；key 归一后匹配。

    回归测试：tools/test_v17_3_scan_scoring.py（无需 SimiGo 运行）。
    """
    def norm_amount(v: str) -> float | None:
        s = (v or "").replace("元", "").replace(",", "").strip()
        try:
            return float(s)
        except ValueError:
            return None

    def norm_status(v: str) -> str:
        v = (v or "").strip()
        if "未" in v:
            return "未付"
        if "已" in v:
            return "已付"
        return v

    canon = {}
    for k, v in (parsed or {}).items():
        ck = _inv_canon(k)
        if ck and ck not in canon:
            canon[ck] = v
    hit, per = 0, 0
    for inv in gt["invoices"]:
        raw = (canon.get(str(inv['no']), "") or "").strip()
        if "|" in raw:
            parts = [x.strip() for x in raw.split("|")]
        else:
            # 模型若用 ':'/',' 分隔字段，退化为单字段
            parts = [x.strip() for x in raw.replace(":", "|").replace(",", "|").split("|") if x.strip()]
        given_client = parts[0] if len(parts) > 0 else ""
        given_amount = norm_amount(parts[1]) if len(parts) > 1 else None
        given_status = norm_status(parts[-1]) if len(parts) > 0 else ""
        c_ok = given_client == inv["client"]
        a_ok = given_amount is not None and abs(given_amount - inv["amount"]) < 0.01
        s_ok = given_status == inv["status"]
        hit += c_ok + a_ok + s_ok
        per += 3
    return round(hit / per, 3) if per else 0.0


def run_scan(store, attempt, session, ctx):
    """扫描行情景 runner：模型见 OCR 文本→提取→payload。"""
    from PIL import Image, ImageEnhance
    files = ctx["scan_files"]  # path→(client, amount, status)
    gt = ctx["gt"]["scan"]     # gt 同 gen_scan_pdfs（见下）
    doc = []
    for p in files:
        body = read_scan_pdf(p["path"])   # 有文本层→pypdf，否则 OCR
        doc.append(f"【{p['name']}】\n{body}")
    body_full = ("以下是扫描版发票 PDF 的 OCR 文本。\n" +
                 "\n".join(doc) + "\n\n")
    m = [rm.user(body_full +
                 "请逐项提取每份发票：客户名称、金额（去掉'元'字）、"
                 "付款状态（已付/未付）。完成后调用 submit_result，"
                 "payload 每行严格按 'inv-<编号>|客户|金额|状态'（编号取"
                 "发票号去掉 'INV-2026-' 后的数字，如 inv-301）。")]
    msg, row = chat_turn(store, "scan", "scan_t1", attempt, session, m,
                         None, 512)
    skey = (row.get("trace") or {}).get("session")
    parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None and msg is not None:
        msg, row = repair_once(store, "scan", "scan_t1", attempt, session,
                               m, skey, 512)
        parsed = parse_payload(tool_payload(msg) if msg else None)
    if parsed is None:
        return {"task": "scan", "attempt": attempt, "accuracy": 0,
                "payloadOk": False}
    acc = score_scan_payload(parsed, gt)
    m.append({"role": "tool", "tool_call_id": _last_call_id(m),
              "content": "已登记全部发票客户/金额/状态。"})
    m.append(rm.user("请调用 verify(ok,issues) 确认提取结果。"))
    msg2, row2 = chat_turn(store, "scan", "scan_t2", attempt, session, m,
                           skey, 512)
    v = tool_args(msg2, "verify") if msg2 else None
    if v is None and msg2 is not None:
        msg2, row2 = repair_once(store, "scan", "scan_t2", attempt, session,
                                 m, skey, 512, tool="verify")
        v = tool_args(msg2, "verify") if msg2 else None
    return {"task": "scan", "attempt": attempt, "accuracy": acc,
            "payloadOk": True, "verifyOk": (v or {}).get("ok"),
            "submitted": parsed,
            "genMode": sorted(set(_GEN_MODE.values())),
            "extractMode": sorted(set(_EXTRACT_MODE.values()))}


RUNNERS = {"word": run_word, "ppt": run_ppt, "pdf": run_pdf,
             "scan": run_scan}


def write_report_docx(store, attempt):
    """输出侧 Word 支持：由各任务最新提交汇编周报 .docx。"""
    import docx
    latest = {}
    for s in store.get("task_summaries", []):
        if s.get("submitted"):
            latest[s["task"]] = s
    d = docx.Document()
    d.add_heading("本地办公室周报（文档任务）", level=1)
    d.add_paragraph(f"attempt {attempt} · 由 SimiGo Local Office 工作流生成")
    w = latest.get("word", {}).get("submitted", {})
    d.add_heading("会议纪要提取", level=2)
    d.add_paragraph(f"纪要1：类型 {w.get('m1_type', '?')}，行动项 "
                    f"{w.get('m1_actions', '?')} 条；纪要2：类型 "
                    f"{w.get('m2_type', '?')}，行动项 {w.get('m2_actions', '?')} 条。")
    p = latest.get("ppt", {}).get("submitted", {})
    d.add_heading("项目汇报 PPT", level=2)
    d.add_paragraph(f"总页数 {p.get('total_slides', '?')}；风险页 "
                    f"{p.get('risk_slides', '?')}；项目代号 "
                    f"{p.get('project_code', '?')}。")
    f = latest.get("pdf", {}).get("submitted", {})
    d.add_heading("发票汇总", level=2)
    d.add_paragraph(f"未付总额 {f.get('unpaid_total', '?')} 元，"
                    f"未付 {f.get('unpaid_count', '?')} 笔。")
    path = WORK / f"docs_weekly_report_a{attempt}.docx"
    d.save(path)
    return path


def task_complete(store, task, attempt):
    have = {r["scenario"] for r in store["runs"]
            if r.get("task") == task and r.get("attempt") == attempt}
    return set(TASK_SCENARIOS[task]) <= have


def main():
    ap = argparse.ArgumentParser(description="V1.7-3b office docs (word/ppt/pdf)")
    ap.add_argument("--tasks", default="word,ppt,pdf,scan")
    ap.add_argument("--smoke", action="store_true",
                    help="冒烟：1 纪要/5 页/2 发票（独立结果文件与 seed）")
    ap.add_argument("--seed", type=int, default=20260920)
    ap.add_argument("--redo", default="",
                    help="强制重跑为新 attempt（逗号分隔任务名）")
    args = ap.parse_args()
    global OUT
    if args.smoke:
        OUT = OUT.with_name("results_v17_3_office_docs_smoke.json")
    WORK.mkdir(parents=True, exist_ok=True)

    tasks = [x.strip() for x in args.tasks.split(",") if x.strip()]
    rng = random.Random(args.seed + (7 if args.smoke else 0))

    print("[data] 生成 word/ppt/pdf 测试文件…", flush=True)
    word_files, gt_word = gen_word_docs(rng, args.smoke)
    ppt_path, gt_ppt = gen_ppt(rng, args.smoke)
    pdf_paths, gt_pdf = gen_pdfs(rng, args.smoke)
    scan_files, gt_scan = gen_scan_pdfs(rng, args.smoke)
    gt = {"word": gt_word, "ppt": gt_ppt, "pdf": gt_pdf,
          "scan": gt_scan}
    (WORK / "ground_truth_docs.json").write_text(
        json.dumps(gt, ensure_ascii=False, indent=1))
    print(f"[data] word={len(word_files)} docs, ppt={gt_ppt['total_slides']}p, "
          f"pdf={len(pdf_paths)} files, scan={len(scan_files)}, gt={gt}",
          flush=True)

    store = json.loads(OUT.read_text()) if OUT.exists() else {
        "model": rm.MODEL,
        "meta": {**rm.experiment_meta(),
                 "serializeGeneration": "true (生产常量)",
                 "smoke": args.smoke, "seed": args.seed,
                 "libs": {"python-docx": "1.2.0", "python-pptx": "1.0.2",
                          "reportlab": "5.0.1", "pypdf": "6.19.0"}},
        "design": ("V1.7-3b docs extension: word_minutes/ppt_outline/"
                   "pdf_invoices; harness parses files (python-docx/"
                   "python-pptx/pypdf), model extracts, ground-truth "
                   "scored; per-task attempt unit"),
        "runs": []}
    ctx = {"word_files": word_files, "ppt_path": ppt_path,
           "pdf_paths": pdf_paths, "scan_files": scan_files,
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
            attempt = done
            continue
        attempt = max((a for a in attempts if a is not None), default=0) + 1
        prefix = "x" if args.smoke else "d"
        session = f"{prefix}{attempt}{SESSION_OF[task]}"
        assert len(session) <= 6, f"session 超长: {session}"
        print(f"===== docs/{task} attempt {attempt} "
              f"(session={session}) =====", flush=True)
        summary = RUNNERS[task](store, attempt, session, ctx)
        store.setdefault("task_summaries", [])
        store["task_summaries"] = [
            s for s in store["task_summaries"]
            if not (s["task"] == task and s["attempt"] == attempt)]
        store["task_summaries"].append(summary)
        checkpoint(store)

    # 输出侧产物：全部任务完成后汇编周报 docx
    if all(task_complete(store, t, 1) for t in ("word", "ppt", "pdf")) or \
            any(s.get("submitted") for s in store.get("task_summaries", [])):
        rep = write_report_docx(store, attempt)
        print(f"[artifact] 周报已写出: {rep}", flush=True)

    print("\n=== V1.7-3b 汇总 ===", flush=True)
    for s in store.get("task_summaries", []):
        extras = {k: v for k, v in s.items()
                  if k in ("checks", "submitted", "verifyOk", "truthTotal",
                           "truthCount")}
        print(f"  {s['task']} a{s['attempt']}: acc={s.get('accuracy')} "
              f"payloadOk={s.get('payloadOk')} {extras}", flush=True)
    print("=== 完成 ===", flush=True)


if __name__ == "__main__":
    main()
