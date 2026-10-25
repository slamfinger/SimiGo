# E 轮源码差异与覆盖说明

本目录只包含 E 轮（settlement provenance）的源码差异。工作树在 E 轮开始前已存在与本轮无关的改动；`workspace_guard.py` 以 `manifests/workspace-before.json` 为基准，证明本轮只改动了下面列出的 12 个路径。

| 路径 | 产物 | 改前 → 改后 sha256（前 16） |
| --- | --- | --- |
| `execution-information-loop/carrier_loop.py` | `tracked-changes.diff` | 464e5c557275417a → cf724a996a871ec9 |
| `execution-information-loop/production_runtime_bridge.py` | `tracked-changes.diff` | 269f1088b4335f77 → d87e045bfa7c2a05 |
| `simigo2-experimental/Sources/SimiGo2Experimental/ProductionRuntimeInformationIntegration.swift` | `tracked-changes.diff` | de1c2b384b591586 → 0f16472883811959 |
| `execution-information-loop/settlement_provenance.py` | `new-files.diff` | ∅ → 1d385e77da2123df |
| `simigo2-experimental/Sources/SimiGo2Experimental/SettlementProvenanceVerification.swift` | `new-files.diff` | ∅ → 3c07ababd7ee3765 |
| `simigo2-experimental/scripts/ordinary_task/run_phase_e.py` | `new-files.diff` | ∅ → ea866a34b7a3a901 |
| `execution-information-loop/admission_selftest.py` | `untracked-current/execution-information-loop__admission_selftest.py` | f84902887d4ccf07 → 3baead5fd7655d22 |
| `simigo2-experimental/Sources/RealModelHandoff/Causality.swift` | `untracked-current/simigo2-experimental__Sources__RealModelHandoff__Causality.swift` | 160c070bbace50c8 → d3d9cbf2caa78b7d |
| `simigo2-experimental/Sources/RealModelHandoff/main.swift` | `untracked-current/simigo2-experimental__Sources__RealModelHandoff__main.swift` | cbb0aed62f9c688f → 16ebeb34817b4564 |
| `simigo2-experimental/Sources/SimiGoTaskRun/main.swift` | `untracked-current/simigo2-experimental__Sources__SimiGoTaskRun__main.swift` | fd5832478a1dfd32 → 79c872a81a497320 |
| `simigo2-experimental/Tests/SimiGo2ExperimentalTests/ProductionInputAdmissionTests.swift` | `untracked-current/simigo2-experimental__Tests__SimiGo2ExperimentalTests__ProductionInputAdmissionTests.swift` | 7b3ece0672f06da1 → 84fda986744dd4be |
| `docs/02-evidence/settlement-provenance-e-20261022/E_ROUND_SETTLEMENT_PROVENANCE_20261022.md` | 仓库内报告，不在本目录 | ∅ → 939364f93d25e04a |

## 为什么有些文件没有逐行 diff

`git` 只跟踪仓库中已登记的文件。上述 3 个 tracked 文件可以用 `git diff` 给出逐行差异；另外 3 个文件在 E 轮开始前不存在，因此 `new-files.diff` 是完整新增内容。

剩下 5 个文件在 E 轮开始前已存在，但未被 git 跟踪（仓库工作树中还有大量同类未跟踪源码）。轮次前置快照只记录了它们的 sha256、大小和权限，没有保存改前字节，因此无法诚实地重建逐字节 diff。这里保存其当前全文，并在上表给出快照记录的改前摘要；完整性由 guard 的 before/after 摘要与 `workspace_guard.py verify` 保证，而不是靠 diff 文本。

这不是“所有改动都有 diff”的声明。它明确区分了可重建 diff 的文件与只能给出摘要对照的文件。

## 读法

- `tracked-changes.diff` 与 `new-files.diff` 可直接用于代码复核。
- `untracked-current/` 用于复核当前实现；如需确认某段代码是否属于 E 轮，应对照改前摘要与 D 轮证据，而不能仅凭当前文件推断。
- 运行期证据（双世界、篡改矩阵、legacy、身份审计、入口覆盖审计）在运行根的其他目录，不在本目录。
