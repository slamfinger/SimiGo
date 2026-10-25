#!/usr/bin/env python3
"""Write EVIDENCE_INDEX.md for this batch: what proves what, then every file.

Section A is curated: each row names the claim, the file that carries it and the
field a reader should check. Section B is a complete inventory (path, bytes,
sha256) of everything in the batch except the manifest and its own logs, so a
reader can hash any single artefact without regenerating the whole manifest.
"""
import hashlib
import json
import os
import sys

B2 = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(B2, "EVIDENCE_INDEX.md")
SKIP = {"MANIFEST_SHA256.txt", "EVIDENCE_INDEX.md",
        "logs/manifest.log", "logs/verify_manifest.log"}
# Derived data and the throwaway isolation roots are working state, reproducible
# from the recorded commands; they are not evidence, so they stay out of the
# index (and out of the manifest). Everything an auditor reads is included.
SKIP_TOP_DIRS = {"build"}
SKIP_TOP_PREFIXES = ("m3",)


def skipped(rel):
    parts = rel.split(os.sep)
    if parts and parts[0] in SKIP_TOP_DIRS:
        return True
    if parts and parts[0].startswith(SKIP_TOP_PREFIXES):
        return True
    return "/isolation/" in rel or rel.endswith("/isolation")

CLAIMS = [
    ("源码只改了 2 个 App 文件，13 个冻结路径逐字节未动",
     "evidence/source_delta_vs_rc_tree.json", "delta_vs_frozen_rc_tree / unchanged_frozen_paths"),
    ("完整补丁与新增文件原文", "SERVICE_HTTP_SOURCE_DIFF.patch, source/", "-"),
    ("新安装候选身份（产物=安装、bundle 树、可执行、CDHash、签名、dylib）",
     "evidence/install_identity_new_candidate.json",
     "installed_equals_built / executable_sha256 / cdhash_sha256"),
    ("App 套件 208/14/0，隔离根新鲜，真实用户状态写入 0",
     "run_isolated_r5/isolation_run_r5.json", "executed_skipped_failures / noninterference"),
    ("五场景原始记录（r1）", "evidence/service_http_gate_installed.json", "positive / no_authorization / fresh_root"),
    ("五场景判定（r1，脚本派生）", "evidence/service_http_gate_verdict.json", "scenarios / overall"),
    ("五场景原始记录（r2，不同隔离根与端口）",
     "evidence/gate_installed_r2/service_http_gate_installed.json", "roots_prefix / ports"),
    ("五场景判定（r2，复现一致）", "evidence/gate_installed_r2/service_http_gate_verdict.json", "scenarios / overall"),
    ("非干预：前后快照差分 0 写入 0 违规",
     "evidence/gate_installed_r2/snapshot_diff.json", "real_user_state_write_count / violation_events"),
    ("Keychain 元数据 0 增 0 删（2035 → 2035）",
     "evidence/gate_installed_r2/keychain_{pre,post}.json", "simigo_items"),
    ("普通启动不自动激活（无 localb 目录、无监听、无 checkpoint）",
     "evidence/ordinary_launch_no_auto_activation.json", "verdict"),
    ("round-2 注记修正前后摘要", "evidence/round2_note_correction_{before,after}.json",
     "paths / verdict_changes"),
    ("round-2 注记修正原文（旧批次）",
     "<local-acceptance batch>/REPORT.md §10", "更正原因 / 原注记 / 更正后措辞 / 证据缺口"),
    ("旧批次注记修正后判定不变（12/3/0/1，16 gates）",
     "evidence/round2_note_correction_after.json", "report.counts / verdict_changes"),
]


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    rows = []
    for base, dirs, files in os.walk(B2):
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(base, name)
            rel = os.path.relpath(path, B2)
            if rel in SKIP or rel.endswith(".DS_Store") or skipped(rel):
                continue
            rows.append((rel, os.path.getsize(path), sha(path)))
    total = sum(r[1] for r in rows)
    lines = ["# 证据索引 — simigo-v2.2.0rc1-service-http-20261024", "",
             "生成于 %s；清单条目 %d，合计 %.1f MiB。" % (
                 __import__("time").strftime("%Y-%m-%dT%H:%M:%S%z"), len(rows), total / 1048576.0),
             "", "## A. 结论 → 证据映射", "",
             "| 结论 | 文件 | 关键字段 |", "| --- | --- | --- |"]
    for claim, path, field in CLAIMS:
        lines.append("| %s | `%s` | `%s` |" % (claim, path, field))
    lines += ["", "## B. 全量文件清单", "",
              "| 路径 | 字节 | SHA-256 |", "| --- | --- | --- |"]
    for rel, size, digest in rows:
        lines.append("| `%s` | %d | `%s` |" % (rel, size, digest))
    with open(OUT, "w") as handle:
        handle.write("\n".join(lines) + "\n")
    print("wrote %s with %d rows" % (OUT, len(rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
