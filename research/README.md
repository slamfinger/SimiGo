# research/ — 研究与证据归档

本目录把 SimiGo-Lab 的研究仓、R01 夹具和 agent 运行证据以归档形式纳入产品仓。
它**不参与产品构建**，也不是产品依赖。

## 两层归档

| 层 | 位置 | 是否入 Git | 内容 |
| --- | --- | --- | --- |
| 证据层 | `lab/`、`fixtures/r01/`、`agent-runs/` | 是 | Lab 受管内容、R01 非构建文件、全部 agent 证据/报告/脚本 |
| 原始层 | `_artifacts/` | 否（本地保留） | 三个来源目录的完整副本，含构建产物、App/DMG、`.git`、`vendor/`、`.transfer/` |

原始层清单见 [ARTIFACTS.md](ARTIFACTS.md)。它只存在于本地工作树，不推送。

## 来源与锚点

| 内容 | 来源 | 锚点 | 导入方式 |
| --- | --- | --- | --- |
| `lab/` | `/Users/mr.simi/Documents/SimiGo-Lab` | `2a573e86`（2026-10-26） | ours-merge + read-tree，Lab 原始提交哈希与完整历史保留 |
| `fixtures/r01/` | `/Users/mr.simi/Documents/SimiGo-Lab-R01-Fixtures` | 目录快照（2026-10-06 生成） | 逐文件复制，排除 SwiftPM 构建目录 |
| `agent-runs/` | `/Users/mr.simi/SimiGo-Agent-Runs` | 各批次目录（2026-10-22 至 10-26） | 白名单复制，保留全部证据，排除构建产物与密钥材料 |

导入日期：2026-10-26。三个来源目录已整体移入 `_artifacts/`，原路径不再存在。

## 边界

- **构建边界**：产品 Xcode 工程和 `Packages/` 均不引用 `research/`。产品消费 Lab 代码仍只走显式回灌线
  `Packages/SimiGoRuntime/Sources/SimiGo2Experimental`（对应分支 `research-backflow-20261026`）。
- **治理边界**：Lab 自己的治理文本（`lab/README.md`、`lab/docs/RESEARCH_STATE.md`）仍是 Lab 内容的权威状态源。
  边界规则第 1 条“实验室代码与产品线严格分离”在这里解释为**依赖与构建分离**；同仓归档不改变任何冻结状态的效力。
- **证据边界**：`lab/` 的冻结/封存资产按原字节导入，不重解释、不重跑、不覆盖。证据结论仍以 Lab 的 gate 文档为准。

## 完整性

- `lab/` 的 Git tree 与 Lab 仓 `main` 完全一致（`90f4adb7…`）。
- `fixtures/r01/`：76 个文件 / 2.3 MiB；`agent-runs/`：3,424 个文件 / 640 MiB（含 `noninterference_*.json` 等大证据）。
- 两者均逐文件与源文件比对 SHA-256，0 处不一致；清单见各自目录的 `MANIFEST_SHA256.txt`。
- 被 Git 排除的构建产物、App/DMG、运行时 SQLite、二进制与密钥材料全部保留在 `_artifacts/` 原树中，未删除。

更新规则：

- 更新 Lab 内容：从 Lab 仓 `main` 重新导入并形成新的合并提交，不直接改写 `lab/` 下的文件。
- 更新证据或夹具：重新执行同一白名单/排除规则，重新生成 `MANIFEST_SHA256.txt` 与 `EXCLUSIONS.md`。
- 任何对冻结证据的改动都属于治理事件，不能作为普通归档维护处理。
