#!/usr/bin/env python3
"""Write EVIDENCE_INDEX.md for simigo-v2.2.0rc1-os-page-return-20261024.

Section A is curated: each row names the claim, the file that carries it and the
field a reader should check. Section B is a complete inventory (path, bytes,
sha256) of everything in the batch except the manifest and its own logs, so a
reader can hash any single artefact without regenerating the whole manifest.
"""
import hashlib
import os
import sys
import time

B2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(B2, "EVIDENCE_INDEX.md")
SKIP = {"MANIFEST_SHA256.txt", "EVIDENCE_INDEX.md",
        "logs/manifest.log", "logs/verify_manifest.log"}


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()


CLAIMS = [
    ("GUI 前置条件复核（截图 / 辅助功能 / 前台 / 控制台会话 / 候选身份）",
     "evidence/gui_preconditions.json", "verdict / blockers"),
    ("GUI 仍阻塞的唯一原因：screencapture 无法取帧",
     "evidence/gui_preconditions.json", "checks.screen_capture + its stderr"),
    ("GUI 未用 headless 生成或 AX 失败冒充通过（边界声明）",
     "REPORT.md §6", "GUI 一节列出的未做三件事"),
    ("OS 级采样器测什么：kernel 全局页计数 + proc_pid_rusage + 存活探针",
     "driver/run_os_page_return.py", "VMStatistics64 / target_rusage / alive"),
    ("os3 原始记录（10 ms、baseline 20 s、memprobe 角色）",
     "evidence/os_page_return_raw_os3.json", "series / memprobe_evidence / start_epoch_ms"),
    ("os3 判定（脚本派生，锚定 shipped suspend 事件）",
     "evidence/os_page_return_verdict_os3.json", "checks / numbers / verdict"),
    ("shipped suspend 事件序列（reference_release / resource_reclaim / lifecycle_suspend）",
     "runs/os3/memprobe_os3.json", "suspend_events_ordered / footprint_pre_bytes"),
    ("kernel 侧把页还回来了（不是进程自己报的数）",
     "evidence/os_page_return_verdict_os3.json", "numbers.kernel_returned_gib / kernel_returned_over_drop"),
    ("compressor 不是这些页的去处", "evidence/os_page_return_verdict_os3.json",
     "numbers.compressor_delta_gib"),
    ("低占用平台持续时间与连续样本数", "evidence/os_page_return_verdict_os3.json",
     "numbers.longest_low_streak_samples / low_streak_seconds"),
    ("退出 teardown 单独测量且不计入判定",
     "evidence/os_page_return_verdict_os3.json", "numbers.exit_teardown_used_for_verdict / exit_teardown_free_gain_bytes"),
    ("判定时进程仍活着（证据文件写入时间晚于观测窗结束）",
     "evidence/os_page_return_verdict_os3.json", "numbers.evidence_write_epoch_ms / post_window_end_epoch_ms"),
    ("os1/os2 旧规则（R1–R9）判定，保留但已被 os3 取代",
     "evidence/os_page_return_verdict_os{1,2}.json", "checks.R4 / checks.R5"),
    ("旧规则为何被取代：argmin 落在 exit teardown 上",
     "REPORT.md §4.1–§4.3", "方法学更正"),
    ("resume 之后重新分配（说明这不是关机或换进程）",
     "evidence/os_page_return_verdict_os3.json", "numbers.available_max_at_series_ms + raw series"),
    ("逐层 forward_calls 仍未插桩（不允许估值）", "REPORT.md §7", "NOT_INSTRUMENTED"),
]


def main():
    rows = []
    for base, dirs, files in os.walk(B2):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(base, name)
            rel = os.path.relpath(path, B2)
            if rel in SKIP or rel.endswith(".DS_Store"):
                continue
            rows.append((rel, os.path.getsize(path), sha(path)))
    total = sum(r[1] for r in rows)
    lines = ["# 证据索引 — simigo-v2.2.0rc1-os-page-return-20261024", "",
             "生成于 %s；清单条目 %d，合计 %.1f MiB。" % (
                 time.strftime("%Y-%m-%dT%H:%M:%S%z"), len(rows), total / 1048576.0),
             "", "## A. 结论 → 证据映射", "",
             "| 结论 | 文件 | 关键字段 |", "| --- | --- | --- |"]
    for claim, path, field in CLAIMS:
        lines.append("| %s | `%s` | `%s` |" % (claim, path, field))
    lines += ["", "## B. 全量文件清单", "",
              "| 路径 | 字节 | SHA-256 |", "| --- | --- | --- |"]
    for rel, size, digest in rows:
        lines.append("| `%s` | %d | `%s`" % (rel, size, digest))
    with open(OUT, "w") as handle:
        handle.write("\n".join(lines) + "\n")
    print("wrote %s with %d rows" % (OUT, len(rows)))
    # Section A paths must actually exist (the verdict files are written by the
    # verifier, so a typo here would only show up when a reader looks for them).
    missing = []
    for _claim, path, _field in CLAIMS:
        for part in path.replace(" ", "").split(","):
            if part.startswith("evidence/") or part.startswith("driver/") or part.startswith("runs/"):
                if "{" not in part and not os.path.exists(os.path.join(B2, part)):
                    missing.append(part)
    if missing:
        print("MISSING: %s" % missing)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
