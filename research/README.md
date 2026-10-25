# research/ — 研究与证据归档

本目录把 SimiGo-Lab 的研究仓、R01 夹具和 agent 运行证据以归档形式纳入产品仓。
它**不参与产品构建**，也不是产品依赖。

## 来源与锚点

| 内容 | 来源 | 锚点 | 导入方式 |
| --- | --- | --- | --- |
| `lab/` | `/Users/mr.simi/Documents/SimiGo-Lab` | `2a573e86`（2026-10-26） | ours-merge + read-tree，Lab 原始提交哈希与完整历史保留 |
| `fixtures/r01/` | `/Users/mr.simi/Documents/SimiGo-Lab-R01-Fixtures` | 目录快照（2026-10-06 生成） | 逐文件复制，排除 SwiftPM 构建目录 |
| `agent-runs/` | `/Users/mr.simi/SimiGo-Agent-Runs` | 各批次目录（2026-10-22 至 10-26） | 白名单复制，排除构建产物与密钥材料 |

导入日期：2026-10-26。方法与全部排除项见各目录的 `EXCLUSIONS.md` 与 `MANIFEST_SHA256.txt`。

## 边界

- **构建边界**：产品 Xcode 工程和 `Packages/` 均不引用 `research/`。产品消费 Lab 代码仍只走显式回灌线
  `Packages/SimiGoRuntime/Sources/SimiGo2Experimental`（对应分支 `research-backflow-20261026`）。
- **治理边界**：Lab 自己的治理文本（`lab/README.md`、`lab/docs/RESEARCH_STATE.md`）仍是 Lab 内容的权威状态源。
  边界规则第 1 条“实验室代码与产品线严格分离”在这里解释为**依赖与构建分离**；同仓归档不改变任何冻结状态的效力。
- **证据边界**：`lab/` 的冻结/封存资产按原字节导入，不重解释、不重跑、不覆盖。证据结论仍以 Lab 的 gate 文档为准。

## 完整性

- `fixtures/r01/` 与 `agent-runs/` 的每个纳入文件都有 SHA-256 记录，导入时已逐文件与源文件比对，0 处不一致。
- 被排除的文件和目录没有删除或移动，仍在原路径；`EXCLUSIONS.md` 记录了原路径、体积与排除原因。
- 目录内既有 `MANIFEST_SHA256.txt`（如各 gate 批次自带）保持原样；本目录新增的清单只覆盖纳入文件。

已知裁剪：

- `agent-runs/` 不含 `install*/`、`derived/`、`scratch/`、`checkouts/`、`SourcePackages/`、`envtest-*/` 与 App/DMG；
  `noninterference_*.json`（9–26 MiB 的隔离性大快照）保留在原目录，其判定结论与 REPORT 已纳入。
- `fixtures/r01/` 不含 `prep/.build/` 与 `recon/.build/`（约 181 MiB，可再生成）。
- Lab 的 `vendor/`、`.transfer/`、`.build/`、`simigo2-experimental` 构建工作树不在版本控制内，未纳入。

## 更新规则

- 更新 Lab 内容：从 Lab 仓 `main` 重新导入并形成新的合并提交，不直接改写 `lab/` 下的文件。
- 更新证据或夹具：重新执行同一白名单/排除规则，重新生成 `MANIFEST_SHA256.txt` 与 `EXCLUSIONS.md`。
- 任何对冻结证据的改动都属于治理事件，不能作为普通归档维护处理。
