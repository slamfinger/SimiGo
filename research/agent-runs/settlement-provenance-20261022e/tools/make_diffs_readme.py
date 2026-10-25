#!/usr/bin/env python3
"""Regenerate diffs/README.md from the current guard verification record."""
from __future__ import annotations

import json
from pathlib import Path

RUN_ROOT = Path(__file__).resolve().parents[1]
GUARD = RUN_ROOT / "logs" / "workspace-guard-verify.json"
OUTPUT = RUN_ROOT / "diffs" / "README.md"

ROWS = [
    ("execution-information-loop/carrier_loop.py",
     "`tracked-changes.diff`"),
    ("execution-information-loop/production_runtime_bridge.py",
     "`tracked-changes.diff`"),
    ("simigo2-experimental/Sources/SimiGo2Experimental/"
     "ProductionRuntimeInformationIntegration.swift", "`tracked-changes.diff`"),
    ("execution-information-loop/settlement_provenance.py",
     "`new-files.diff`"),
    ("simigo2-experimental/Sources/SimiGo2Experimental/"
     "SettlementProvenanceVerification.swift", "`new-files.diff`"),
    ("simigo2-experimental/scripts/ordinary_task/run_phase_e.py",
     "`new-files.diff`"),
    ("execution-information-loop/admission_selftest.py",
     "`untracked-current/execution-information-loop__admission_selftest.py`"),
    ("simigo2-experimental/Sources/RealModelHandoff/Causality.swift",
     "`untracked-current/simigo2-experimental__Sources__RealModelHandoff__"
     "Causality.swift`"),
    ("simigo2-experimental/Sources/RealModelHandoff/main.swift",
     "`untracked-current/simigo2-experimental__Sources__RealModelHandoff__"
     "main.swift`"),
    ("simigo2-experimental/Sources/SimiGoTaskRun/main.swift",
     "`untracked-current/simigo2-experimental__Sources__SimiGoTaskRun__"
     "main.swift`"),
    ("simigo2-experimental/Tests/SimiGo2ExperimentalTests/"
     "ProductionInputAdmissionTests.swift",
     "`untracked-current/simigo2-experimental__Tests__"
     "SimiGo2ExperimentalTests__ProductionInputAdmissionTests.swift`"),
    ("docs/02-evidence/settlement-provenance-e-20261022/"
     "E_ROUND_SETTLEMENT_PROVENANCE_20261022.md",
     "仓库内报告，不在本目录"),
]


def short(record: dict) -> str:
    return record.get("sha256")[:16] if record.get("exists") else "∅"


def main() -> int:
    guard = json.loads(GUARD.read_text(encoding="utf-8"))
    by_path = {change["path"]: change for change in guard["changed_files"]}
    if set(by_path) != {row[0] for row in ROWS}:
        raise SystemExit("guard paths do not match the README mapping")
    lines = [
        "# E 轮源码差异与覆盖说明",
        "",
        "本目录只包含 E 轮（settlement provenance）的源码差异。工作树在 E 轮"
        "开始前已存在与本轮无关的改动；`workspace_guard.py` 以 "
        "`manifests/workspace-before.json` 为基准，证明本轮只改动了下面列出的 "
        "12 个路径。",
        "",
        "| 路径 | 产物 | 改前 → 改后 sha256（前 16） |",
        "| --- | --- | --- |",
    ]
    for path, artifact in ROWS:
        change = by_path[path]
        lines.append("| `%s` | %s | %s → %s |"
                     % (path, artifact, short(change["before"]),
                        short(change["after"])))
    lines += [
        "",
        "## 为什么有些文件没有逐行 diff",
        "",
        "`git` 只跟踪仓库中已登记的文件。上述 3 个 tracked 文件可以用 "
        "`git diff` 给出逐行差异；另外 3 个文件在 E 轮开始前不存在，因此 "
        "`new-files.diff` 是完整新增内容。",
        "",
        "剩下 5 个文件在 E 轮开始前已存在，但未被 git 跟踪（仓库工作树中还有"
        "大量同类未跟踪源码）。轮次前置快照只记录了它们的 sha256、大小和权限，"
        "没有保存改前字节，因此无法诚实地重建逐字节 diff。这里保存其当前全文，"
        "并在上表给出快照记录的改前摘要；完整性由 guard 的 before/after 摘要与 "
        "`workspace_guard.py verify` 保证，而不是靠 diff 文本。",
        "",
        "这不是“所有改动都有 diff”的声明。它明确区分了可重建 diff 的文件与"
        "只能给出摘要对照的文件。",
        "",
        "## 读法",
        "",
        "- `tracked-changes.diff` 与 `new-files.diff` 可直接用于代码复核。",
        "- `untracked-current/` 用于复核当前实现；如需确认某段代码是否属于 E 轮，"
        "应对照改前摘要与 D 轮证据，而不能仅凭当前文件推断。",
        "- 运行期证据（双世界、篡改矩阵、legacy、身份审计、入口覆盖审计）在运行根"
        "的其他目录，不在本目录。",
    ]
    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(OUTPUT), "rows": len(ROWS)}, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
