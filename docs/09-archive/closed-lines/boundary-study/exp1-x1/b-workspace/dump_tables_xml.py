#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""XML 级逐格抽取两版全部表格（含 vMerge/gridSpan 标注），生成 verify/xml_tables_*.txt。
用途：a-deposits/extract_docx.py 的合并判定 id(c._tc) 存在假阳性（lxml 元素代理 GC 地址复用），
其提取文本把表 2-5 大量真实单元格折叠为 <同左>；本脚本直接读 document.xml，不依赖该判定。
可重复运行（幂等覆盖）。只读原件。
"""
import re
import zipfile
from pathlib import Path

IN = Path("/Users/mr.simi/Documents/SimiGo-Lab/boundary-study/exp1-x1/information-space/inputs")
OUT = Path("/Users/mr.simi/Documents/SimiGo-Lab/boundary-study/exp1-x1/b-workspace/verify")
FILES = {
    "0307": IN / "秦沈项目经济运行情况汇报_20260307.docx",
    "0308": IN / "秦沈项目经济运行情况汇报_20260308.docx",
}


def dump_tables(tag):
    with zipfile.ZipFile(FILES[tag]) as z:
        xml = z.read("word/document.xml").decode("utf-8")
    out = [f"# {tag}: vMerge={len(re.findall(r'<w:vMerge', xml))} "
           f"gridSpan={len(re.findall(r'<w:gridSpan', xml))} hMerge={len(re.findall(r'<w:hMerge', xml))}"]
    for ti, tbl in enumerate(re.findall(r"<w:tbl>.*?</w:tbl>", xml, flags=re.S), 1):
        rows = re.findall(r"<w:tr\b.*?</w:tr>", tbl, flags=re.S)
        out.append(f"== 表{ti}: {len(rows)}行 ==")
        for ri, r in enumerate(rows):
            cells = []
            for tc in re.findall(r"<w:tc>.*?</w:tc>", r, flags=re.S):
                vm = re.search(r'<w:vMerge(?:\s+w:val="(\w+)")?\s*/>', tc)
                gs = re.search(r'<w:gridSpan\s+w:val="(\d+)"\s*/>', tc)
                mark = ("|vM:" + (vm.group(1) or "cont")) if vm else ""
                mark += f"|gs{gs.group(1)}" if gs else ""
                txt = "".join(re.findall(r"<w:t(?:\s[^>]*)?>(.*?)</w:t>", tc, flags=re.S))
                cells.append(txt + mark)
            out.append(f"r{ri}: " + " | ".join(cells))
    return out


for tag in FILES:
    lines = dump_tables(tag)
    dest = OUT / f"xml_tables_{tag}.txt"
    dest.write_text("\n".join(lines), encoding="utf-8")
    print(f"{tag} -> {dest} ({len(lines)} 行)")
