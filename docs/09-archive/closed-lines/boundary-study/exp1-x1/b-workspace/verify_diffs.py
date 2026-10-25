#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""续作验证脚本：独立复核 a-deposits 差异报告的载荷结论。只读原件。
1) 用 a-deposits/extract_docx.py 同样逻辑重提取两版，与存款提取文本 diff（验证存款忠实性）
2) 直接从 document.xml 抽取全部 w:t 文本流做全量 diff（独立枚举全部可见文字差异）
3) docProps 元数据核对（修订号/时间/字数统计）
4) media 图片哈希对比
5) 页眉页脚 strip-rsid 对比
"""
import hashlib
import re
import zipfile
from pathlib import Path

import docx
from docx.document import Document as _Doc
from docx.oxml.ns import qn
from docx.table import Table, _Cell
from docx.text.paragraph import Paragraph

IN = Path("/Users/mr.simi/Documents/SimiGo-Lab/boundary-study/exp1-x1/information-space")
DEP = IN / "a-deposits"
OUT = Path("/Users/mr.simi/Documents/SimiGo-Lab/boundary-study/exp1-x1/b-workspace/verify")
OUT.mkdir(parents=True, exist_ok=True)

DOCS = {
    "0307": IN / "inputs" / "秦沈项目经济运行情况汇报_20260307.docx",
    "0308": IN / "inputs" / "秦沈项目经济运行情况汇报_20260308.docx",
}


def iter_block_items(parent):
    if isinstance(parent, _Doc):
        parent_elm = parent.element.body
    elif isinstance(parent, _Cell):
        parent_elm = parent._tc
    else:
        raise ValueError("unsupported parent")
    for child in parent_elm.iterchildren():
        if child.tag == qn('w:p'):
            yield Paragraph(child, parent)
        elif child.tag == qn('w:tbl'):
            yield Table(child, parent)


def dump(path, out):
    """与 a-deposits/extract_docx.py 完全相同的提取逻辑。"""
    doc = docx.Document(str(path))
    lines = []
    tbl_idx = 0
    for block in iter_block_items(doc):
        if isinstance(block, Paragraph):
            t = block.text.strip()
            style = block.style.name if block.style is not None else ""
            if t:
                prefix = f"[{style}] " if style and style.lower() not in ("normal",) else ""
                lines.append(prefix + t)
        else:
            tbl_idx += 1
            lines.append(f"===== 表格{tbl_idx} ({len(block.rows)}行 x {len(block.columns)}列) =====")
            seen_merged = set()
            for r in block.rows:
                cells = []
                for c in r.cells:
                    key = id(c._tc)
                    if key in seen_merged:
                        cells.append("<同左>")
                    else:
                        seen_merged.add(key)
                        cells.append(" / ".join(x.strip() for x in c.text.splitlines() if x.strip()))
                lines.append(" | ".join(cells))
            lines.append(f"===== 表格{tbl_idx} 结束 =====")
    Path(out).write_text("\n".join(lines), encoding="utf-8")
    return len(lines), tbl_idx


print("=" * 72)
print("[1] 重提取并比对存款提取文本")
fresh = {}
for tag, p in DOCS.items():
    out = OUT / f"fresh_extract_{tag}.txt"
    n, t = dump(p, out)
    fresh[tag] = out
    dep = DEP / f"extract_{tag}.txt"
    same = out.read_text(encoding="utf-8") == dep.read_text(encoding="utf-8")
    print(f"  {tag}: fresh {n} lines / {t} tables; 与 a-deposits 提取文本逐字节一致 = {same}")

print()
print("=" * 72)
print("[2] document.xml 全量 w:t 文本流 diff（独立枚举全部可见文字差异）")


def wt_stream(path):
    """按段落顺序抽取全部 w:t 文本，拼接为整篇文字流（含表格单元格内段落）。"""
    with zipfile.ZipFile(path) as z:
        xml = z.read("word/document.xml").decode("utf-8")
    # 逐段抽文本：以 <w:p ...>...</w:p> 为界
    paras = []
    for m in re.finditer(r"<w:p\b.*?</w:p>", xml, flags=re.S):
        text = "".join(re.findall(r"<w:t(?:\s[^>]*)?>(.*?)</w:t>", m.group(0), flags=re.S))
        text = text.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
        if text.strip():
            paras.append(text)
    return paras


s7 = wt_stream(DOCS["0307"])
s8 = wt_stream(DOCS["0308"])
print(f"  0307 段落数(含表内) = {len(s7)}; 0308 = {len(s8)}")
import difflib

diff_lines = list(
    difflib.unified_diff(
        [x for x in s7 if x.strip()],
        [x for x in s8 if x.strip()],
        fromfile="0307", tofile="0308", lineterm="", n=0,
    )
)
changed = [l for l in diff_lines if (l.startswith("+") or l.startswith("-")) and not l.startswith(("+++", "---"))]
print(f"  文本流 unified diff 中变化的行数: {len(changed)} (期望: 差异1-5 涉及的段落 = 10 行: 5×[-, +])")
for l in diff_lines:
    if l.startswith(("---", "+++")) or (l.startswith(("+", "-")) and not l.startswith(("+++", "---"))):
        print("   ", l[:150])

print()
print("=" * 72)
print("[3] docProps 元数据核对")
for tag, p in DOCS.items():
    with zipfile.ZipFile(p) as z:
        core = z.read("docProps/core.xml").decode("utf-8")
        app = z.read("docProps/app.xml").decode("utf-8")
        names = z.namelist()
    def grab(x, tagname):
        m = re.search(rf"<{tagname}>(.*?)</{tagname}>", x, flags=re.S)
        return m.group(1) if m else "(无)"
    print(f"  --- {tag} ---")
    print("  core.xml:", {k: grab(core, k) for k in
        ("dc:creator", "cp:lastModifiedBy", "dcterms:created", "dcterms:modified", "cp:revision")})
    print("  app.xml :", {k: grab(app, k) for k in ("Pages", "Words", "Characters", "Application", "TotalTime")})
    media = [n for n in names if n.startswith("word/media/")]
    print("  media   :", media)

print()
print("  [3b] media 哈希对比")
with zipfile.ZipFile(DOCS["0307"]) as z7, zipfile.ZipFile(DOCS["0308"]) as z8:
    for name in sorted(set(z7.namelist()) & set(z8.namelist())):
        if name.startswith("word/media/"):
            h7 = hashlib.sha256(z7.read(name)).hexdigest()[:16]
            h8 = hashlib.sha256(z8.read(name)).hexdigest()[:16]
            print(f"  {name}: 0307={h7} 0308={h8} 一致={h7==h8}")

print()
print("  [3c] 页眉页脚/脚注尾注 strip-rsid 对比")
RSID = re.compile(r'\s(?:w:rsidR|w:rsidRPr|w:rsidP|w:rsidRDefault|w:rsidSect)="[0-9A-Fa-f]+"')
with zipfile.ZipFile(DOCS["0307"]) as z7, zipfile.ZipFile(DOCS["0308"]) as z8:
    parts = sorted(set(n for n in z7.namelist() if re.match(r"word/(header|footer|footnotes|endnotes)\d*\.xml$", n))
                   | set(n for n in z8.namelist() if re.match(r"word/(header|footer|footnotes|endnotes)\d*\.xml$", n)))
    for name in parts:
        in7, in8 = name in z7.namelist(), name in z8.namelist()
        if not (in7 and in8):
            print(f"  {name}: 仅一版存在 (0307={in7}, 0308={in8})")
            continue
        x7 = RSID.sub("", z7.read(name).decode("utf-8"))
        x8 = RSID.sub("", z8.read(name).decode("utf-8"))
        print(f"  {name}: strip-rsid 后一致 = {x7 == x8}")
print()
print("完成。")
