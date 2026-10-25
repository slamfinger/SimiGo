#!/usr/bin/env python3
"""Write EVIDENCE_INDEX.md for this batch: what proves what, then every file.

Section A is curated: each row names the claim, the file that carries it and the
field a reader should check. Section B is a complete inventory (path, bytes,
sha256) of everything in the batch except DerivedData (build/, build_v5/) and
the throwaway isolation roots, so a reader can hash any single artefact without
regenerating the whole manifest.
"""
import hashlib
import json
import os

B = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(B, "EVIDENCE_INDEX.md")
SKIP_FILES = {"MANIFEST_SHA256.txt", "EVIDENCE_INDEX.md",
              "logs/manifest.log", "logs/verify_manifest.log", "default.profraw"}
SKIP_TOP_DIRS = {"build", "build_v5"}

CLAIMS = [
    ("门原文“产品里没有逐层 forward 计数插桩”与本仓库事实不符；插桩在运行时包内，"
     "但 HEAD 上没有任何外部调用方",
     "evidence/instrumentation_inventory.json",
     "files / total_lines / references_outside_instrumentation_dir_at_head"),
    ("本批次只改了 2 个文件：1 个 App 源（+112/−1）、1 个测试（+18/−0）；"
     "两处补丁都能重放到字节一致",
     "evidence/patch_attribution.json",
     "entries[*].checks / patch.added / patch.removed"),
    ("补丁与 pre-edit 原文",
     "LAYER_FORWARD_INSTRUMENTATION.patch, TESTS_TRACE_ROLE_COVERAGE.patch, source/",
     "-"),
    ("新安装候选身份：exe、bundle 树、产物=安装、签名、Gatekeeper、Mach-O 成员",
     "evidence/install_identity_new_candidate.json",
     "executable_sha256 / bundle_tree_sha256 / installed_equals_built"),
    ("测试改动没有移动安装候选（改前/改后身份逐键相同；Release 重建 0 次编译）",
     "evidence/install_identity_before_test_change.json, evidence/patch_attribution.json",
     "install_identity.changed_keys / checks.P6_installed_candidate_unmoved_by_test_edit"),
    ("逐层 forward 计数判定：L1–L9 全真，48 层，每层 4/32 次，3264 事件，0 估值",
     "evidence/layer_forward_calls_verdict.json",
     "verdict / checks / numbers"),
    ("每个数字可溯源到守护进程写下的报告文件（sha256 双向对上），并附驱动方独立重算",
     "evidence/layer_forward_trace_raw.json",
     "report_sha256_recomputed / report_sha256_in_evidence / derived"),
    ("插桩实跑的原始产物：pilot 报告、进程证据、pty 日志、隔离根",
     "runs/lf1/layerforwardtrace_lf1.json, runs/lf1/tracepilot_lf1.json, runs/lf1/tracepilot.log",
     "status / g19a1BaselineIdentityPass / g19a2TraceStabilityPass"),
    ("受影响测试：App 套件 210 executed / 14 skipped / 0 failures，隔离根新鲜",
     "run_isolated_lf2/isolation_run_lf2.json",
     "executed_skipped_failures / checks / xctestrun_isolated_sha256"),
    ("非干预：真实用户状态写入 0、违规事件 0、快照前后差分",
     "run_isolated_lf2/snapshot_diff.json",
     "real_user_state_write_count / violation_events"),
    ("新增的 2 个 tracepilot 单测确实在套件里执行并通过",
     "run_isolated_lf2/isolated_tests_lf2.log",
     "grep testTracepilot：started + passed 各两行"),
    ("测试改动之前的套件记录（208/14/0，已被 lf2 取代，保留作对照）",
     "run_isolated_lf1/isolation_run_lf1.json",
     "executed_skipped_failures"),
    ("Service/HTTP 在新候选上原样重跑：五场景全过（200 / 401 / 401 / 503），非法 proof 生成 0",
     "evidence/gate_installed_g2/service_http_gate_verdict.json",
     "overall / scenarios / deviations / candidate"),
    ("五场景原始记录：产品自己的 stdout/stderr、authorized body、negative probes、fresh root",
     "evidence/gate_installed_g2/service_http_gate_installed.json, evidence/gate_installed_g2/A*, B*, C*",
     "positive.authorized_request.result.status / positive.negative_probes / fresh_root"),
    ("重跑期间非干预：真实用户状态 0 写入、0 违规；Keychain 元数据 2035 → 2035",
     "evidence/gate_g2_snapshot_diff.json, evidence/gate_g2_keychain_{pre,post}.json",
     "real_user_state_write_count / violation_events / simigo_items"),
    ("本轮增量 v5 构建：只多一个受控入口 serve-service（只调 Service.shared.start(path:)），"
     "源码 +66 行；exe 83a88048…、bundle 树 aacb6b4a…、installed_equals_built=true",
     "SERVICE_FACADE_LEG.patch, source_v5/, evidence/install_identity_v5_candidate.json",
     "executable_sha256 / bundle_tree_sha256 / installed_equals_built"),
    ("Service/HTTP 在 v5 上重跑：五场景全过；门面 leg 8 项 required 全 true（serving leg 由 "
     "Service.start(path:) 起监听，[NODE]/[READY] 出现在服务了 200 的那次运行）",
     "evidence/gate_v5/service_http_gate_verdict.json, "
     "evidence/gate_v5_facade/service_http_gate_installed.json",
     "overall / facade_leg.facade_leg_passed / facade_leg.required / positive.facade_markers"),
    ("门面 leg 的非干预：真实 defaults 域六个摘要前后一致（20 key 未变），Keychain 2035 → 2035",
     "evidence/prefs_v5_pre.json, evidence/prefs_v5_post.json, "
     "evidence/keychain_v5_pre.json, evidence/keychain_v5_post.json",
     "plist_sha256 / values_sha256 / key_count / simigo_items"),
    ("round-3 台账门 product_service_http 在 v5 上的投影：8/8 判据成立（监听 socket 属于候选 pid；"
     "明文无 HTTP 回应，默认信任 rc=60；未配置授权 503 且 trace 0；授权请求 200 且 trace +8；"
     "无放宽）；台账未并，tls_verify=18 旧 token 不复现也不冒充",
     "evidence/service_http_ledger_projection_v5.json, "
     "evidence/transport_v5/service_http_transport_probe_v5.json",
     "projected_verdict / checks / ledger_modified / tokens"),
    ("v5 上重跑受影响测试与逐层 trace：210/14/0 且真实用户状态 0 写入；48 层 L1–L9 全真、0 估值",
     "run_isolated_lf3/isolation_run_lf3.json, evidence/layer_forward_calls_verdict_v5.json, "
     "evidence/layer_forward_trace_raw_v5.json",
     "executed_skipped_failures / checks / verdict / numbers"),
    ("物理页归还：在新候选上按同一套预注册规则重跑，A5 false → BLOCKED"
     "（0.499600 < 0.50，差 −6.6 MiB）；阈值与规则未动",
     "evidence/os_page_return_verdict_os4.json",
     "verdict / checks.A5_kernel_returned_the_pages / numbers / raw_sha256"),
    ("os4 的原始采样（22,514 点 / 10 ms）与进程自报证据",
     "evidence/os_page_return_raw_os4.json, runs/os4/memprobe_os4.json",
     "rid / identity.exe_sha256 / series / memprobe_evidence"),
    ("os3 与 os4 并列：os4 的失败余量（6.6 MiB）比两候选间收回量差异（147 MiB）小 22 倍；"
     "未调阈值、未改规则、未重定义 A5",
     "evidence/os_page_return_cross_candidate.json",
     "os3_previous_candidate / os4_new_candidate / delta / rule_changed / threshold_changed"),
    ("GUI 前置条件（本轮只测权限，未操作 GUI）：辅助功能已有、屏幕录制缺失 → BLOCKED_PREREQUISITE",
     "evidence/gui_prerequisite_probe.json",
     "accessibility.granted / screen_recording.granted / required_user_action"),
    ("GUI 可达性：候选能启动并完成 bootstrap，但 AXPress 被受理而不派发（按 Quit 后进程仍在）→ 这条通道不可用",
     "evidence/gui_gui4_ax_probe.json",
     "launch / attempts[A2b].position / dispatch.stillRunning / finding"),
    ("GUI 探测的非干预：真实用户状态 0 写入、0 违规（gui4 为权威运行）",
     "evidence/gui_gui4_snapshot_diff.json",
     "real_user_state_write_count / violation_events"),
    ("GUI 取证装置（driver/gui_walkthrough.py）：七个条件全真才写门输入文件；"
     "本轮无人值守自检三项未达 → real_model_output=false，门输入未生成",
     "evidence/gui_walk1_walkthrough.json",
     "checks / real_model_output / screenshot.exit_code / native_mlx_trace.generation_events"),
    ("GUI 自检的非干预：真实用户状态 0 写入、0 违规，bootstrap 在隔离根里 20 模型 / 0 issue",
     "evidence/gui_walk1_snapshot_diff.json, runs/walk1/logs/gui_stderr.log",
     "real_user_state_write_count / violation_events / issueCount"),
    ("GUI 追加探测（gui5）：按 AXShowMenu→按 Settings… 正确顺序仍无窗口；菜单栏项几何报 "
     "[0,30]/[0,0] 且无同级参照 → “x=−1 在屏外”与“AXPress 不派发”均降级为未定",
     "evidence/gui_gui5_ax_probe2.json",
     "attempts[P3].windowsAfter / attempts[P2].processes / attempts[P4].windowsAfter"),
    ("Service 门面在生产代码里只有 AppKit 入口：Service.shared 仅 StatusBarCoordinator，"
     "startSelected 仅 MenuApp/Settings；测试目标与 headless 入口 0 处",
     "evidence/service_facade_inventory.json",
     "findings / patterns[Service.shared] / patterns[startSelected()]"),
    ("GUI 装置同时判定门面是否执行：walk2 用宽的 [CFG] 得假阳性 true，收紧为 "
     "[NODE] backend= / [READY] 后 walk3 为 false",
     "evidence/gui_walk2_walkthrough.json, evidence/gui_walk3_walkthrough.json",
     "service_facade.observed / native_mlx_trace.service_markers"),
    ("验收台账未被本批次修改（仍 12 PASS / 3 BLOCKED / 0 FAIL / 1 NOT_INSTRUMENTED）",
     "evidence/ledger_untouched.json",
     "sha256 / counts / modified_by_this_batch"),
    ("构建、安装、重跑与清单过程日志",
     "logs/build.log, logs/build_for_testing.log, logs/build_release_after_test_change.log, "
     "logs/build_for_testing_lf2.log, logs/trace_lf1.log, logs/service_http_gate_g2.log, "
     "logs/os_page_return_os4.log",
     "BUILD SUCCEEDED / TEST BUILD SUCCEEDED / [gate] wrote"),
    ("工作树脏集（构建前 / 加测试后），用于说明为什么不能拿 git diff 当归因",
     "evidence/worktree_before_build.txt, evidence/worktree_after_test_change.txt",
     "15 条 → 16 条"),
]


def skipped(rel):
    parts = rel.split(os.sep)
    if rel in SKIP_FILES or rel.endswith(".DS_Store"):
        return True
    if parts[0] in SKIP_TOP_DIRS:
        return True
    return any(p == "isolation" for p in parts)


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    rows = []
    for root, dirs, files in os.walk(B):
        if os.path.relpath(root, B) == ".":
            dirs[:] = [d for d in dirs if d not in SKIP_TOP_DIRS]
        dirs[:] = sorted(d for d in dirs if d != "isolation")
        for name in sorted(files):
            path = os.path.join(root, name)
            rel = os.path.relpath(path, B)
            if skipped(rel):
                continue
            rows.append((rel, os.path.getsize(path), sha(path)))
    rows.sort()
    total = sum(r[1] for r in rows)

    lines = []
    lines.append("# 证据索引 — simigo-v2.2.0rc1-layer-forward-calls-20261024")
    lines.append("")
    lines.append("清单条目 %d，合计 %.1f MiB（不含 `build/`、`build_v5/` 与 `run_isolated_*/isolation`，"
                 "理由见 `MANIFEST_SHA256.txt` 生成器注释）。" % (len(rows), total / (1 << 20)))
    lines.append("")
    lines.append("## A. 结论 → 证据映射")
    lines.append("")
    lines.append("| 结论 | 文件 | 关键字段 |")
    lines.append("| --- | --- | --- |")
    for claim, files, fields in CLAIMS:
        lines.append("| %s | `%s` | `%s` |" % (claim, files, fields))
    lines.append("")
    lines.append("## B. 全量文件清单")
    lines.append("")
    lines.append("| 文件 | 字节 | SHA-256 |")
    lines.append("| --- | --- | --- |")
    for rel, size, digest in rows:
        lines.append("| `%s` | %d | `%s` |" % (rel, size, digest))
    lines.append("")
    with open(OUT, "w") as handle:
        handle.write("\n".join(lines))
    print("wrote %s with %d rows, %.1f MiB" % (OUT, len(rows), total / (1 << 20)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
