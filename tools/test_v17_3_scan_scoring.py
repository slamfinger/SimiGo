#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""scan 评分回归测试（v1.7-3d 外审 P2-1 修复）：key 归一 + 三项核对。

跑法：python3 tools/test_v17_3_scan_scoring.py
无需 SimiGo 运行：runtime_matrix 以 stub 注入，纯评分逻辑单测；
v17_2_concurrency / v17_3_office 仅导入（无网络副作用）。
"""
import sys
import types
from pathlib import Path

_stub = types.ModuleType("runtime_matrix")


class _RM:
    def user(self, t):
        return {"role": "user", "content": t}


_stub.rm = _RM()
sys.modules.setdefault("runtime_matrix", _stub)

sys.path.insert(0, str(Path(__file__).resolve().parent))
import importlib.util
_spec = importlib.util.spec_from_file_location(
    "v17_3_office_docs",
    Path(__file__).resolve().parent / "v17_3_office_docs.py")
mod = importlib.util.module_from_spec(_spec)
try:
    _spec.loader.exec_module(mod)
except SystemExit:
    pass

GT = {"invoices": [
    {"no": 301, "client": "客户甲", "amount": 9876.54, "status": "未付"},
    {"no": 302, "client": "客户乙", "amount": 3210.00, "status": "已付"},
]}

fails = []


def check(name, got, want):
    ok = got == want
    print(f"  [{'ok' if ok else 'FAIL'}] {name}: got={got!r} want={want!r}")
    if not ok:
        fails.append(name)


# --- key 归一 ---
check("canon INV-2026-301", mod._inv_canon("INV-2026-301"), "301")
check("canon inv-301", mod._inv_canon("inv-301"), "301")
check("canon 301", mod._inv_canon("301"), "301")
check("canon 尾随杂字", mod._inv_canon("INV-2026-301号"), "301")
check("canon 空", mod._inv_canon(""), "")

# --- attempt-1 场景回归：文档原样 key 须命中（外审 P2-1） ---
a1 = mod.parse_payload("INV-2026-301|客户甲|9876.54|未付\n"
                       "INV-2026-302|客户乙|3210.00|已付")
check("attempt-1 文档原样 key → 1.0", mod.score_scan_payload(a1, GT), 1.0)

a2 = mod.parse_payload("inv-301|客户甲|9876.54|未付\n"
                       "inv-302|客户乙|3210.00|已付")
check("attempt-2 契约 key → 1.0", mod.score_scan_payload(a2, GT), 1.0)

# --- 真错误仍须被抓（不许放宽掩盖编号/字段错误） ---
bad_status = mod.parse_payload("inv-301|客户甲|9876.54|未付\n"
                               "inv-302|客户乙|3210.00|未付")
check("状态错 → 5/6", mod.score_scan_payload(bad_status, GT), 0.833)

wrong_no = mod.parse_payload("inv-301|客户甲|9876.54|未付\n"
                             "inv-999|客户乙|3210.00|已付")
check("编号错 → 0.5", mod.score_scan_payload(wrong_no, GT), 0.5)

wrong_client = mod.parse_payload("inv-301|客户四|9876.54|未付\n"
                                 "inv-302|客户乙|3210.00|已付")
check("客户错 → 5/6", mod.score_scan_payload(wrong_client, GT), 0.833)

noise = mod.parse_payload("inv-301|客户甲|9876.54 元|未付\n"
                          "inv-302|客户乙|3,210.00|已付")
check("单位/千分位容错 → 1.0", mod.score_scan_payload(noise, GT), 1.0)

print(f"\n{'PASS' if not fails else 'FAIL'}: {len(fails)} failed")
sys.exit(1 if fails else 0)
