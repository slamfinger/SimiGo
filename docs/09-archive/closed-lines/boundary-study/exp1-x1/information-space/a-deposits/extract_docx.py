#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""提取 docx 全文（段落+表格，按文档顺序），输出到工作目录。只读原件。"""
import sys
from docx import Document
from docx.document import Document as _Doc
from docx.table import Table, _Cell
from docx.text.paragraph import Paragraph
from docx.oxml.ns import qn

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
    doc = Document(path)
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
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"{path} -> {out}: {len(lines)} lines, {tbl_idx} tables")

if __name__ == "__main__":
    dump(sys.argv[1], sys.argv[2])
