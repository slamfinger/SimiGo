#!/usr/bin/env python3
"""生成「格式变了、内容没变」的对照组。

同一个文档/表格的三种存法：
  contract-v1.docx          python-docx 生成
  contract-v1-resaved.docx  同样的段落，只改 docProps 里的时间戳 → 字节全变
  contract-v1.txt           同样的文字，纯文本

  amount-v1.xlsx            openpyxl 生成
  amount-v1.csv             同样的表格，纯文本

`*.extract.txt` 是**抽取结果**，用 python-docx / openpyxl 抽的，
代表 agent 那次抽取动作，不代表 SimiGo 有抽取能力。
重跑：python3 make_fixtures.py
"""
import csv
import datetime
import pathlib

import docx
import openpyxl

HERE = pathlib.Path(__file__).parent
TEXT = "合同额：100万元"
ROWS = [("合同额", 1000000)]


def save_docx(path: pathlib.Path, stamp: datetime.datetime) -> None:
    d = docx.Document()
    d.add_paragraph(TEXT)
    d.core_properties.created = stamp
    d.core_properties.modified = stamp
    d.core_properties.revision = 1 if stamp.day % 2 else 2
    d.save(path)


def main() -> None:
    save_docx(HERE / "contract-v1.docx", datetime.datetime(2026, 1, 1, 9, 0, 0))
    save_docx(HERE / "contract-v1-resaved.docx", datetime.datetime(2026, 11, 11, 3, 0, 0))
    (HERE / "contract-v1.txt").write_text(TEXT + "\n", encoding="utf-8")

    wb = openpyxl.Workbook()
    ws = wb.active
    for row in ROWS:
        ws.append(list(row))
    wb.properties.created = datetime.datetime(2026, 1, 1, 9, 0, 0)
    wb.properties.modified = datetime.datetime(2026, 1, 1, 9, 0, 0)
    wb.save(HERE / "amount-v1.xlsx")

    with (HERE / "amount-v1.csv").open("w", newline="", encoding="utf-8") as fh:
        csv.writer(fh).writerows(ROWS)

    # 抽取结果：agent 的动作，落成文本。
    def paragraphs(path: pathlib.Path) -> str:
        return "\n".join(p.text for p in docx.Document(path).paragraphs if p.text).strip()

    (HERE / "contract-v1.docx.extract.txt").write_text(paragraphs(HERE / "contract-v1.docx") + "\n", encoding="utf-8")
    (HERE / "contract-v1-resaved.docx.extract.txt").write_text(
        paragraphs(HERE / "contract-v1-resaved.docx") + "\n", encoding="utf-8")
    (HERE / "contract-v1.txt.extract.txt").write_text(TEXT + "\n", encoding="utf-8")

    sheet = openpyxl.load_workbook(HERE / "amount-v1.xlsx").active
    cells = "\n".join("\t".join("" if c is None else str(c) for c in row)
                      for row in sheet.iter_rows(values_only=True))
    (HERE / "amount-v1.xlsx.extract.txt").write_text(cells.strip() + "\n", encoding="utf-8")
    (HERE / "amount-v1.csv.extract.txt").write_text(cells.strip() + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
