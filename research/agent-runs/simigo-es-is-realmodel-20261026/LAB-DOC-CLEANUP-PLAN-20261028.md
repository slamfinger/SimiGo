# Lab / Research 文档盘点与清理方案（2026-10-28）

> 只读盘点 + 四类分档 + 待批准删除清单。本文件**不改动** `research/lab/` 下任何文件。
> 构建身份：HEAD `b0852511`；工作树 24 个已修改、27 个未跟踪（含本目录 2026-10-28 的新文档）；未提交、无新标签。

## 1. 盘点口径

- 文件数与体积用 `find <dir> -type f | wc -l` 与 `du -sh` 在 2026-10-28 本机工作树实测。
- “引用”指被产品代码、产品文档或其它研究文档按路径/文件名引用。实测：产品代码与 `Packages/` 对 `research/` 的引用为 **0 处**（仅 `.gitignore` 有路径规则），研究层不参与构建。
- 本盘点只覆盖文档与证据层；`exports/`、根目录 DMG、`build/` 等构建产物不在“文档清理”范围内（归阶段 4 的提交范围审查）。

## 2. 层图（实测）

| 层 | 路径 | 文件数 | 体积 | 入 Git | 权威/入口 |
|---|---|---|---|---|---|
| 研究归档入口 | `research/README.md`、`research/ARTIFACTS.md` | 2 | 3 KB | 是 | 本层入口 |
| Lab 冻结导入 | `research/lab/` | 5,213 | 104 MB | 是 | `lab/README.md` → `lab/docs/RESEARCH_STATE.md` |
| — Lab 文档 | `research/lab/docs/` | 4,296 | 78 MB | 是 | `RESEARCH_STATE.md`（唯一状态权威） |
| — 其中证据 | `lab/docs/02-evidence/` | 2,642 | 60 MB | 是 | 各 gate 文档引用 |
| — 其中治理 | `lab/docs/00-governance/` | 759 | 6.8 MB | 是 | 冻结合同与登记 |
| — 其中历史与归档 | `lab/docs/07-history/`、`09-archive/` | 124 + 699 | 9.6 MB | 是 | `ARCHIVE_INDEX.md` |
| 产品期运行证据 | `research/agent-runs/` | 9,609 | 18 GB（本地） | 是（带 `MANIFEST_SHA256.txt`） | 各批次目录 + 验收文档 |
| R01 夹具 | `research/fixtures/r01/` | 78 | 2.3 MB | 是 | `MANIFEST_SHA256.txt` |
| 原始来源副本 | `research/_artifacts/` | 228,281 | 24 GB | 否（gitignore） | `ARTIFACTS.md` |
| 产品期研究叙事 | `docs/`（11 个子目录） | ~216 | ~4 MB | 是 | `docs/research/README.md`、`docs/experiments/README.md` |

## 3. 治理边界（决定哪些动作本次可以执行）

1. `research/README.md` 是 owner 写下的导入规则：`lab/` 按原字节导入、与 Lab 仓 `main` 树一致，“**不重解释、不重跑、不覆盖**”；更新 Lab 内容须从 Lab 仓重新导入，**不直接改写 `lab/` 下的文件**；对冻结证据的任何改动属于**治理事件**，不能当作普通归档维护。
2. `lab/docs/RESEARCH_STATE.md` 自述为该层**唯一**状态权威，其余导航文件都是指针；Lab 自己已经把旧状态正文移入 `09-archive/state-layer/`，指针页只留入口。也就是说 **lab/ 内部的去重已经做过**，再删只能删证据或归档原件。
3. Lab 源仓目录已不存在（整体移入 `_artifacts/`，`research/README.md` 已记载），因此“重新导入”这条通路目前不可用。

**结论**：`lab/` 内部的删除/改写按 owner 自己的规则属于治理事件，需要明确批准；本次只执行**产品层**（`research/README.md`、`research/agent-runs/` 的索引与说明）的收敛，并把 `lab/` 内候选删除项列成清单待批。

## 4. 四类分档

### A. 当前架构 / 使用说明 — 保留、合并、精简

| 对象 | 判定 | 动作 |
|---|---|---|
| 产品根 `README.md`（615 行） | 当前能力入口，仍以 v2.1.0 为下载入口、旧阶段说明多 | **阶段 4** 统一改写（不在本次动） |
| `research/README.md` | 归档入口，事实正确，但缺少“哪些是当前、哪些是历史”的导航 | **本次**追加导航小节（只增不改既有导入事实） |
| `docs/architecture/`、`docs/knowledge/` | 产品架构与知识整理，仍有效 | 保留 |
| `docs/AGENT-ACCESS.md`（2026-10-28 新增） | 唯一一份「Agent 接入方式」使用说明：路由受管/旁路、身份键、复用门控、MCP 九工具与生命周期、首版不支持项 | 保留；能力或默认态变化时同步该文件（其 §6 列了触发点）。不支持项只作**使用范围**说明，边界登记仍以 `STAGE1-GAP-MATRIX` 为准 |
| `docs/research/`（16 文件） | 2026-09 研究叙事层，与 new `research/lab` 叙事重叠但角度不同（“我们如何知道”） | 保留，不合并（合并会丢论点链） |

### B. 当前有效的验收记录与关键证据 — 保留必要证据，避免重复叙述

| 对象 | 判定 | 动作 |
|---|---|---|
| `research/agent-runs/simigo-es-is-realmodel-20261026/ACCEPTANCE-20261026-BUILD-97043902.md` | ES/IS 真机验收的唯一落档处，含 §3.x 逐批读数与收口节 | 保留；后续读数按既有规则新开小节 |
| `lab/docs/02-evidence/`（2,642 文件） | 证明 ES/IS 核心命题的原始证据（gate 证据、JSON、日志） | **保留原件**，不重复叙述 |
| `lab/docs/00-governance/`（759 文件） | 冻结合同与登记，其他文档的上位引用 | 保留 |
| `research/agent-runs/` 各批次 + MANIFEST | 产品期逐批证据 | 保留 |
| `docs/releases/RELEASE_NOTES_v*.md` | 版本历史；缺 v2.1.7–v2.2.1 说明 | 保留；缺口在阶段 4 补 |

### C. 已失效草稿 / 重复报告 / 过时状态表 — 删除或只留明确历史（**需 owner 批准**）

2026-10-28 逐文件核实（存在性、Git 跟踪、sha256、引用）后，**初版判断被推翻了一半**：C1–C3 里只有两份上游 issue 草稿是无引用孤儿，其余都有活文档引用，或落在冻结导入内。精确清单如下（全部已被 Git 跟踪，`git checkout HEAD -- <path>` 可恢复）：

| 候选 | 精确路径与指纹 | 引用核实 | 结论 |
|---|---|---|---|
| C1a 孤儿草稿（2 份） | `docs/experiments/UPSTREAM_ISSUE_DRAFT_chatsession_cancel_ledger_wipe.md`（5,964 B，`113aa501`）<br>`docs/experiments/UPSTREAM_ISSUE_DRAFT_qwen35_tool_restart_rule.md`（7,591 B，`c0ad2ba4`） | 除自身外全仓无引用 | **可删**——本次唯一可安全删除的两份；不动 lab，不需改任何声明 |
| C1b COW 草稿 | `docs/experiments/UPSTREAM_ISSUE_DRAFT_kv_prefix_sharing_cow.md`（4,222 B，`b2083330`） | 被 `UPSTREAM_ISSUE_SUBMISSION_READY.md:92` 与 `EXECUTION_FORK_F0_PROBE_RESULTS_20260919.md:46` 引用，是 sequence identity 细节的唯一落档 | **保留**（初版“已被汇总覆盖”判断错误） |
| C2 派生状态表 | `research/lab/docs/RESEARCH_ESTATE_CENSUS_20261006.md`（5,574 B，`e971eb26`）+ `.tsv`（703,475 B，`54a613f6`）、`RESEARCH_ESTATE_COVERAGE.md`（4,320 B，`1211b146`）、`RESEARCH_ESTATES_SUMMARY.md`（15,324 B，`8a1f9b25`） | 被 `RESEARCH_STATE.md:11-15` 与 `RESEARCH_CONTEXT_INDEX.md:76/320/321/581/587` 当指针引用；文件自述 DERIVED / NOT AUTHORITATIVE | **改判保留**：删除须同步改这两份**活文档**，它们位于冻结导入内，改动量大于收益 |
| C3 指针页 | `research/lab/docs/NEXT_SESSION_ENTRY.md`（1,616 B，`64acb809`）、`SESSION_CONTINUITY.md`（1,547 B，`a5f70d56`） | 被 `RESEARCH_STATE.md:11-12`、`AGENT_CONTEXT.md:27`、`ARCHIVE_INDEX.md:76`、`07-history` 两份引用 | **改判保留**，理由同上 |
| C4 Lab 归档层 | `research/lab/docs/09-archive/`（699 文件） | 历史原件 | **永久保留**：删了即破坏“原字节导入”完整性声明 |

> 初版写的 `lab/docs/...` 是简写，实际路径统一为 `research/lab/docs/...`，上表已校正。
> 若 owner 仍要删 C2/C3，须一并批准两件事：改冻结导入内的活文档，以及把 `research/README.md` 的“与 Lab `main` 树一致”改写为“导入后经治理事件删减，清单见本文件”。
> C1a 若批准，不涉及 lab，也不需要任何声明改写。

### D. 未决问题与已知边界 — 保留精简、单一登记

当前有效的边界登记已经集中在两处，**不再新开第三份**：

- 本目录 `STAGE1-GAP-MATRIX-20261028.md`（阶段 1 缺口与裁定状态）
- `ACCEPTANCE-20261026-BUILD-97043902.md` 收口节的“未执行 U1–U7 / 仍为 NO-GO”清单

本次盘点确认仍开放、需在阶段 1/2 收口的项（与任务板一致）：`SIMIGO_IS_ANSWER_REUSE` 默认值与 R1-A「默认关闭」的冲突待裁定；跨模型真机读数；真实第三方 Agent 的 MCP 端到端；MCP 鉴权分级；失败是否推进 ES 生命周期。

## 5. 本次执行的安全子集

1. `research/README.md` 追加「当前状态导航」小节：当前能力与验收证据入口、Lab 为冻结历史、未决边界入口、以及 `lab/` 冻结声明。**不删除、不改写既有导入事实。**
2. 本盘点文件即 `lab/` 内删除项的批准依据；在获得批准前不动 `lab/`。

## 6. 需要 owner 批准的动作

- C1：删除 3 个上游 issue 草稿（`docs/experiments/`）。
- C2/C3：删除 Lab 派生的 3 份 2026-10-06 盘点/摘要 + 2 个纯指针页，并把 `research/README.md` 的完整性声明改为“治理事件删减 + 清单”。
- 明确 C4（`09-archive/`）保持不动。

## 7. 本次不做

- 不动 `lab/` 任何文件（C2/C3 未批准）。
- 不动根 `README.md`、`docs/releases/`（阶段 4）。
- 不动 `research/_artifacts/`（本地原始副本，gitignore）。
- 不提交、不推送、不打标签。
