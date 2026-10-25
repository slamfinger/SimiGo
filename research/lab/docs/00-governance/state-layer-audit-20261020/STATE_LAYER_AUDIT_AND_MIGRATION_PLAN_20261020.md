# State-Layer Audit & Migration Plan — 2026-10-20

> **Status:** `PARTIALLY EXECUTED — 2026-10-20`（P0 + P1 + P2a 已执行；P2b-SRS 与 P3 未执行，见 §10）
> **Nature:** 盘点 + 迁移计划 + 执行记录。盘点阶段只新增文件；执行阶段（§10）实际移动 147 份（145 份治理文档 + 2 份状态层正文），另有 48 份在闭包复核中移出后原样回退；改写 3 个状态层文件，均逐项登记。所有被移动文件的正文未改。
> **Gate:** P1 / P2 **不得**在 G1 门控实验结果落地并提交之前执行（理由见 §3 F0）。
> **Authority:** 本文件是维护计划，不是研究状态。状态真源仍是 `docs/RESEARCH_STATE.md`。

---

## 0. 一句话结论

仓库文档不是“内容太多”，而是**默认视野太宽**：886 份治理文档里 297 份（43,020 行，占 34.4%）可以移出默认视野而不损失一条证据——其中 145 份已于 2026-10-20 归档，152 份属 SRS / 授权链冻结批次待人类裁定；状态层 8 个文件 31,364 行里，`SESSION_CONTINUITY` 的 55 个标题有 41 个与 `RESEARCH_STATE` 完全同名，实质是索引副本。

---

## 1. 约束（不可越过）

1. **不删证据。** 归档只移动位置、不改内容；移动后原文件名不变，保证正文里的按名引用仍然成立。
2. **不改真源。** `RESEARCH_STATE.md` 的历史段落不重排、不改写、不合并；只允许在头部追加导航指针。
3. **不动冻结对象。** Frozen contract、authorization record、ruling、closure、capsule 一律原位保留。
4. **不碰并发路径。** E-I 实验目录（`execution-information-loop/experiment/**`）在 G1 期间整棵冻结。
5. **一次一条线、一个 commit。** 任何搬迁必须可按线回滚。

---

## 2. 现状量化（2026-10-20 实测）

### 2.1 全仓

| 区域 | md 文件 | 体积 | 性质 |
|---|---|---|---|
| `docs/00-governance`（顶层，审计时） | **886** | 7.4M / 125,148 行 | 一次性裁定/授权/交付记录为主 |
| `docs/02-evidence` | 256（86 个 estate） | 50M | 证据数据，最大 estate `es-is-20261005` 38.6M |
| `docs/07-history` | 124 | 908K | 已是归档语义 |
| `docs/08-research-memory` | 20 | 172K | 活跃审查笔记 |
| `docs/research-capsules/v1` | 17 | 88K | L2 权威 |
| 全仓 md | **1,476** | — | 不含 `.build` / `__pycache__` |

### 2.2 00-governance 处置分布（CSV 逐文件判定）

| disposition | 文件数 | 行数 | 含义 |
|---|---|---|---|
| `ARCHIVE_FOLD` | **297** | **43,020** | 不被任何留存文档或机器工件引用（145 已归档 / 152 冻结批次） |
| `KEEP_REFERENCED` | 484 | 68,080 | 被至少一份留存文档按名引用 |
| `KEEP_CLOSURE` | 75 | 10,298 | 本身无直接引用，但归档后会破坏其它留存文档的按名引用 |
| `KEEP_ARTIFACT_REF` | 10 | 1,459 | 被 run manifest / authorization.json / runner 引用，不能动 |
| `KEEP_STANDING` | 13 | 1,723 | 常驻控制面登记/宪法/依赖图 |
| `KEEP_ACTIVE` | 7 | 568 | 2026-10-13 后的活跃线 |
| **合计** | **886** | **125,148** | — |

归档后 `00-governance` 顶层从 **886 → 741** 份；本次实际移出默认视野 **17,036 行（13.6%）**，可归档总量为 **43,020 行（34.4%）**。判定已用 `verify_refs.py` 复核通过（`PASS: 589 KEEP_* present, 297 ARCHIVE_FOLD unreferenced (145 already archived, 152 in frozen batch)`）。

执行结果（按线，实测）：

| 线 | 已归档 | 归档行数 | 冻结待裁定 |
|---|---|---|---|
| E-I 连续计算 | 59 | 7,031 | 0 |
| 通用治理 / 其他 | 55 | 6,362 | 0 |
| PALACE / Integrated ES | 29 | 3,411 | 2 |
| Small-scale runtime / GUI | 2 | 232 | 0 |
| Persistent SRS / Signer（含 `SRS_VAL_01`、`SRS_REAL_CLOSURE_01`） | 0 | 0 | 150 |
| **合计** | **145** | **17,036** | **152** |

冻结批次构成：`PERSISTENT_SRS` 65、`SRS_VAL_01` 34、`SRS_REAL_CLOSURE_01` 51、`PALACE_INFORMATION_SPACE` 2。该批次内部互引密集（38 份互为引用方），只能整批原子迁移，不能逐份移动。

### 2.3 状态层

| 文件 | 行数 | 角色（建议） |
|---|---|---|
| `RESEARCH_STATE.md` | 27,547 | **唯一真源**，保留全部历史段 |
| `RESEARCH_MEMORY.md` | 1,010 | 长期思想，保留 |
| `NEXT_SESSION_ENTRY.md` | 797 → 29 | 已降级为指针页（正文归档） |
| `SESSION_CONTINUITY.md` | 723 → 32 | 已降级为指针页（41/55 标题与真源重复） |
| `RESEARCH_CONTEXT_INDEX.md` | 617 | 保留为 L0 路由表 |
| `RESEARCH_ESTATES_SUMMARY.md` | 360 | **保留**（2026-10-06 历史综述，非状态副本，见 §10 偏差 1） |
| `RESEARCH_ESTATE_COVERAGE.md` | 78 | 保留（覆盖率台账） |
| `ARCHIVE_INDEX.md` | 62 | 保留并追加归档条目 |

---

## 3. 关键发现

**F0 — 并发窗口（决定一切时序）。** 2026-10-20 13:27，本地 MLX 会话仍在 `prefill 50800/83250`，`exec_command` 持续下发；G1 一旦出结果，必然回写 `results.md` / 新增 `SR_*.md` / 更新 capsule / 头部追加 `RESEARCH_STATE`。在此之前做 P1/P2 会与它的写路径重叠。

**F1 — 状态层是语义重述，不是字面复制。** 8 个状态文件之间**零个**完全相同的长段落；但 `SESSION_CONTINUITY` 55 个 H2/H3 中 41 个与 `RESEARCH_STATE` 标题逐字相同。结论：不能靠“去重脚本”解决，只能靠“降级为指针页”。

**F2 — 真源时间轴断裂。** `RESEARCH_STATE` 114 个 H2 中 110 个带日期，出现 **5 处时间倒序**；头部是 10-15，尾部停在 10-11。头部追加、尾部未归档的写入习惯是结构性原因。

**F3 — 真源内部有 1 个重复 H2 标题**：`Real PALACE Snapshot Consumption Loop PASS — 2026-10-09`。这是唯一字面重复，可安全加消歧后缀。

**F4 — 297 份文档的“无引用”是可信判定。** 判定语料 = 真源 + 索引 + capsules + 08-memory + 03/04/05/06 全部文档 + 13 份常驻登记 + 7 份活跃文档 + `README`/`AGENT_CONTEXT` + 全仓非 md 工件。初判语料只含 `KEEP_ACTIVE` / `KEEP_STANDING`，遗漏了 `KEEP_REFERENCED` 之间的互引；按全仓语料重算引用闭包后，75 份降为 `KEEP_CLOSURE`，可归档量由 372 收敛到 297。被该语料引用的 484 份全部保留，被机器工件钉住的 10 份单列为 `KEEP_ARTIFACT_REF`。判定脚本 `verify_refs.py` 可随时复跑。

**F5 — 28 份同族多版本文件需要人工确认语义**（MLX Smoke V2–V5、D002 V1.1–V1.5、SRS repair authorization V1–V4、Signer design V0.1–V0.6、Manifest instance V1.0–V1.2），其中 19 份仍被真源引用，已归入 `KEEP_REFERENCED`。CSV 用 `version_family_review=yes` 标记，**不自动打 SUPERSEDED**——其中 `MANIFEST_INSTANCE_V1.0/V1.1/V1.2` 很可能是三个不同实例而非三次改稿，自动打标会造成语义错误。

**F6 — `docs/02-evidence` 有 62 个 estate 完全未被引用**（合计 6.17M，仅 9 份 md），其中 9 个是 `database-carrier-equivalence-campaign` 各版本运行目录（每个 0.5–0.6M、0 md）。这些是归档候选，不是删除候选。

**F7 — 关键证据尚未入库。** `model-level-validation/logs/*.jsonl`（P3 三个 arm 的调用证据）与 `.carrier-p3-arm*.sqlite` 目前**未跟踪**，只存在于磁盘。它们被 `SR_P3_CARRIER_SELECTIVE_RECOMPUTE_20261018.md` 按名引用。一旦磁盘损坏或清理，证据链直接断裂。

**F8 — 根目录 `Sources/`（4 文件）与 `Tests/`（2 文件）是 `159eebb0` 的旧副本**，与 `simigo2-experimental/` 活跃版本内容不同，且未被根 `Package.swift` 引用。这是唯一“看起来可删”的实体代码，但属结构性变更，**列为人类裁定项 D1，本计划不处理**。

---

## 4. 目标形态

```text
docs/
  00-governance/            # 只放：常驻控制面 + 活跃线 + 被引用文档
  ...
  09-archive/               # 新增：默认不进视野，index 可查
    execution-information-loop/
    persistent-srs/
    palace/
    runtime-gui/
    execution-state/
    information-space/
    general/
    <YYYY-MM>/              # 二级按年月，保留原文件名
  99-archive-index.md       # 或沿用 docs/ARCHIVE_INDEX.md 追加
```

归档条目统一加 3 行头，**不改正文**：

```markdown
> **ARCHIVED** 2026-10-20 · line: persistent-srs · reason: superseded by <FILE>
> Original location: docs/00-governance/<FILE>
> Evidence status: unchanged (content frozen; moved only)
```

---

## 5. 分阶段执行

### P0 — 零冲突动作（可立即做）

| 动作 | 风险 | 说明 |
|---|---|---|
| 产出本计划 + 2 份 CSV | 无 | 本次已完成 |
| 状态真源加“重复标题消歧后缀” | 极低 | 只改 1 行标题，不动内容（F3） |
| 修正 `README.md` 的 E4/E5 冲突 | 低 | 单文件；与 G1 写路径不相交 |

> 注意：**不要**现在给 E-I 的 `.sqlite` 加 `.gitignore`。其中 `.carrier-p3-arm{1,2,3}.sqlite` 是被 SR 文档引用的证据，应入库；只有 `.carrier-arm4.sqlite`（0 字节）、`.carrier-arm5*`、`.consistency-check.sqlite`、`.baseline.json`、`.last_judgment.json` 属中间产物。要按引用逐个判，不能一刀切。

### P1 — 状态层折叠（G1 结果已提交后）

1. `SESSION_CONTINUITY.md` / `NEXT_SESSION_ENTRY.md` / `RESEARCH_ESTATES_SUMMARY.md` → 各压到 ≤30 行：
   只保留“当前门位、活跃线、禁止事项、去真源哪一节读细节”。
2. `RESEARCH_STATE.md` 头部插入 `State Layer Map`（≤15 行），声明其余文件为指针。
3. 修正 F3 重复标题、F2 的尾部未归档段（只加 `## Historical (frozen)` 分隔，不重排）。
4. 修正 `README.md` E4/E5 与真源的冲突（若 P0 未做）。

**验收：** `wc -l` 六文件合计 ≤ 30,000；`SESSION_CONTINUITY` 不再出现 `## Current` 级正文；任一状态断言可用标题在真源唯一定位。

### P2 — 分线归档（P1 验收后）

按 CSV 的 `disposition=ARCHIVE_FOLD` 执行，**一条线一个 commit**：

```bash
# 示例：E-I 线（60 个文件）
git mv docs/00-governance/<FILE> docs/09-archive/execution-information-loop/2026-10/<FILE>
```

每条线搬完立即校验：

```bash
# 不变式：docs/09-archive/ 之外不得按名引用已归档文件（白名单 = 2 份状态层指针目标）
python3 docs/00-governance/state-layer-audit-20261020/verify_refs.py
# ARCHIVE_FOLD 仍在盘上者视为冻结批次，批内互引不计违规
```

**先做 E-I（60）、PALACE（31）、general（97），P2 后再重算一次 `ref_live`**，因为折叠会改变“留存集合”，第二轮通常还能再折 150–250 份。SRS 线（179 份）最后做——它正被 Signer v0.7 审阅引用，等人类裁定后再动。

> **实际执行（2026-10-20）**：E-I 59、PALACE 29、general 55 已归档（见 §2.2 实测表）；SRS 线经闭包复核收敛为 152 份冻结批次，本轮未移动。

### P3 — 二次收敛（可选）

以 P2 后的留存集合为语料重算 `ref_live`，把“仅被已归档文档引用”的 `KEEP_REFERENCED` 降到归档区。此步不做数量承诺，先出第二版 CSV 再执行。

---

## 6. CSV 字段说明

`GOVERNANCE_DOC_MAP_20261020.csv`（886 行，UTF-8 BOM，Excel 可直接开）

| 字段 | 含义 |
|---|---|
| `file` / `date` / `line` / `lines` / `bytes` | 文件与体量 |
| `ref_top` | 被状态层/索引/capsule/08-memory 引用次数（子串计数） |
| `ref_any` | 被全仓任意 md 引用次数（历史口径，仅参考） |
| `ref_live` | **被“留存集合”引用次数**——处置判定依据 |
| `linked` | 是否存在 markdown 链接式引用（本次实测：0 个治理文件被链接） |
| `version_family_review` | 同族多版本，需人工确认语义，不自动打标 |
| `disposition` | `KEEP_ACTIVE` / `KEEP_STANDING` / `KEEP_REFERENCED` / `KEEP_CLOSURE` / `KEEP_ARTIFACT_REF` / `ARCHIVE_FOLD` |
| `suggested_target` | 建议目标目录 |

`EVIDENCE_ESTATE_MAP_20261020.csv`（86 行）：`estate / md_files / cited_md / bytes / disposition / note`。

---

## 7. 不可动清单

- `docs/RESEARCH_STATE.md` 全部历史段落（只允许头部追加）
- `docs/04-decisions/**`、`docs/06-closure/**`、`docs/03-findings/**`、`docs/research-capsules/**`
- `docs/AGENT_CONTEXT.md`
- CSV 中 `KEEP_REFERENCED` / `KEEP_STANDING` / `KEEP_ACTIVE` 的全部文件
- `docs/02-evidence/es-is-20261005/**`（尤其 4 个 fixture：9.8M tar ×2、7.5M json ×2）
- `execution-information-loop/experiment/**`（G1 期间整棵冻结）
- `calculator-contract-freeze.jsonl` 及任何 Frozen Contract

---

## 8. 风险与回滚

| 风险 | 缓解 |
|---|---|
| 搬迁打断 G1 会话的写路径 | P2 硬门禁：G1 结果 commit 之后才启动 |
| 归档后引用失效 | 保留原文件名 + P2 每线校验脚本；引用均为纯文本，不依赖路径 |
| 与 G1 收尾的 `git add -A` 混合 | P1/P2 的 commit 必须单独、可按线 revert；不与他人改动同 commit |
| 误判“无引用” | 判定语料包含全部留存文档；`ref_any` 列可反查历史引用 |
| 同族版本语义误判 | F5 只标记不自动打标，人工确认后再加 banner |

---

## 9. 本次审计新增文件

```text
docs/00-governance/state-layer-audit-20261020/STATE_LAYER_AUDIT_AND_MIGRATION_PLAN_20261020.md
docs/00-governance/state-layer-audit-20261020/GOVERNANCE_DOC_MAP_20261020.csv
docs/00-governance/state-layer-audit-20261020/EVIDENCE_ESTATE_MAP_20261020.csv
docs/00-governance/state-layer-audit-20261020/verify_refs.py
```

盘点阶段未修改、未移动、未删除任何既有文件；未运行构建或实验。
执行阶段的改动见 §10。

---

## 10. Execution record — 2026-10-20

### 已执行

| 阶段 | 动作 | 结果 |
|---|---|---|
| P0 | `README.md` E4/E5 与真源对齐（E4 VERIFIED / E5 NEXT，注明 mock materializer 边界） | 完成 |
| P0 | 真源重复 H2 加消歧后缀 | 完成（1 行） |
| P1 | `SESSION_CONTINUITY.md` / `NEXT_SESSION_ENTRY.md` 原件归档 + 原位指针页 | 完成（723 + 797 行 → 32 + 29 行） |
| P1 | 真源头部加 `state-layer map` | 完成（13 行） |
| P2a | 145 份非 SRS 折叠文档 → `docs/09-archive/<line>/<YYYY-MM>/`，每份加 2 行 ARCHIVED banner | 完成（E-I 59 / general 55 / palace 29 / runtime-gui 2） |

### 未执行（按计划保留）

- SRS / Signer 线 152 份冻结批次（`PERSISTENT_SRS` 65 / `SRS_VAL_01` 34 / `SRS_REAL_CLOSURE_01` 51 / `PALACE_INFORMATION_SPACE` 2）：等 Signer v0.7 人类裁定，必须整批原子迁移。
- P3 二次收敛：需在 P2a 后重算 `ref_live` 再出第二版 CSV。
- 根目录 `Sources/` `Tests/` 旧副本：人类裁定项 D1。

### 偏差（核实后调整）

1. `RESEARCH_ESTATES_SUMMARY.md` **不降级**：读完全文确认它是 2026-10-06 的历史综述（自标 `DERIVED / NOT AUTHORITATIVE`），不是状态副本；降级会丢独特内容，故保留，只在真源地图中标注其性质。
2. 新增 `KEEP_ARTIFACT_REF`（10 份）：被 `RUN_MANIFEST_INSTANCE.json`、`authorization.json`、`formal_runner.py` 按名引用。移动不会破坏代码执行，但会破坏证据 provenance 的可追溯性，因此不移动。
3. 归档 banner 采用 2 行（计划原写 3 行），去掉空行冗余；被移动文件的正文一字未改。
4. **引用闭包回退 48 份**（P2a 后复查发现）：首轮校验语料只含 `KEEP_ACTIVE` / `KEEP_STANDING`，未把 `KEEP_REFERENCED` 当作“留存文档”，因此漏判了 96 处“留存文档 → 已归档文件”的传递引用。按全仓语料重算闭包后，48 份已移动的非状态层文件移回原位（正则剥离 banner 后 `git diff` 对 HEAD 全部为 0），连同 26 份尚未移动者共 74 份转入 `KEEP_CLOSURE`；同批复核又追加 1 份（`SIMIGO18_BETA_AUDIT1_…_20260928.md`），合计 75。

### 校验

```text
python3 docs/00-governance/state-layer-audit-20261020/verify_refs.py
→ PASS: 589 KEEP_* present, 297 ARCHIVE_FOLD unreferenced (145 already archived, 152 in frozen batch)
00-governance 顶层 md: 886 → 741（已归档 145）
docs/09-archive/ md 合计: 147（145 治理文档 + 2 状态层正文）
回退校验: 48 份闭包回退文件 git diff vs HEAD = 0
```

### 追加修订 — 恢复路径收口（同日复核后，人类确认）

| 项 | 动作 | 结果 |
|---|---|---|
| 恢复入口 | `AGENT_CONTEXT` §3 第 2 步改指 `RESEARCH_CONTEXT_INDEX`（L0 路由），并注明 `NEXT_SESSION_ENTRY` 自 2026-10-06 起仅为指针页 | 完成 |
| 快照戳 | `AGENT_CONTEXT` §7 标题加 `(snapshot 2026-10-02)` + 快照声明，首句由 “latest repository state” 改为 `As of 2026-10-02` | 完成（正文未改） |
| 归档入口 | `RESEARCH_CONTEXT_INDEX` §9 Reading order 增第 11 步：归档查询（`ARCHIVE_INDEX` → `09-archive/<line>/<YYYY-MM>/`） | 完成 |

动机：本次治理收窄了默认视野，但恢复协议仍指向被降级的文件，且 §7 把 2026-10-02 的边界当作“最新”。三处均为指针 / 日期戳修订，不涉及研究内容、证据判定或门位。

标签约定：`RESEARCH_CONTEXT_INDEX` §1 已补 Label note，声明 `Current …` / `Historical SRS …` 只区分“现行证据 vs 已消费序列”，不代表活跃线。仍未处理：C16 capsule 未入库（未跟踪），需随 L0 路由一并提交。
