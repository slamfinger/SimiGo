# SimiGo-Lab 新会话研究任务交接基线

> **⚠️ STATE UPDATE 2026-10-06（晚，终 2）——本文档 §5-§8 的门位与“等 stage-transition review”状态均已过期，当前状态以下为准：**
> **Gate A CLOSED；Gate B CLOSED（UA v1.0 FROZEN）；Gate C = CLOSED / ACCEPT（Human independent ruling）。**
> U-A mechanism implementation = **ACCEPTED**（"U-A Correctness Acceptance"：Ownership/Visibility/Effect 三边界闭合；A/B/C 全 ACCEPT；32/32 测试；MA-DS-1 run 11 VALID；run 10 撤销为 runner defect）。
> Manifest v1.1 = FROZEN / unchanged（§4.2 divergence = acceptance condition，进未来 v1.2 文档收敛）。
> **Gate C Closure Package 已交付并经独立复核**：`docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_GATE_C_CLOSURE_PACKAGE_20261006.md`。其 §8 `CLOSURE RECOMMENDED` 仍为 advisory。
> **正式裁定已登记**：`docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_CCVS01_GATE_C_CLOSURE_RULING_20261006.md`；ruling basis = `c91a20c`，implementation basis = `b9d2ac1`。
> **Stage Transition = ACCEPTED；Probe v0.2 / Representation Contract = ACCEPTED / DESIGN FROZEN**（basis `9b9da6c`）。正式裁定：`docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_ES_CONTINUATION_SUFFICIENCY_PROBE_V0_2_ACCEPTANCE_RULING_20261006.md`。
> **当前停 = Experiment Authorization Package / Run Manifest 审查之前。Experiment NOT AUTHORIZED；Execution Authorization NOT YET REQUESTED。禁止实现、fixture 执行、U-3/U-4/U-5/U-6、Phase D/E、migration、MemPalace integration 或 Frozen Contract/UA v1.0 修改。**
> **UPDATE：Experiment Authorization Package / Run Manifest R01 已提交待审**：`docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_ES_CONTINUATION_SUFFICIENCY_PROBE_EXPERIMENT_AUTHORIZATION_PACKAGE_RUN_MANIFEST_R01_20261006.md`。Candidate run = `ES-CSP-RUN-01`。提交不等于授权；fixture preparation / database / run 均 NOT STARTED。
> **UPDATE 2：R01 first review = REVISE BEFORE S1；R01 Rev1 已提交第二审**。裁定：`docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_ES_CONTINUATION_SUFFICIENCY_PROBE_R01_REVIEW_RULING_20261006.md`。已修正 N-B dual-pointer schema、reconstruction role blinding、opaque stable session locator。S1 NOT APPROVED；Experiment NOT AUTHORIZED。
> **UPDATE 3：R01 Rev1 second review = ACCEPTED；S1 APPROVED**。裁定：`docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_ES_CONTINUATION_SUFFICIENCY_PROBE_R01_REV1_SECOND_REVIEW_RULING_20261006.md`。可准备三套 fixture manifests/checksums；S2 REQUIRED；S3 NOT AUTHORIZED；Experiment NOT AUTHORIZED。
> **UPDATE 4：S1 COMPLETE**。P-POS / N-A / N-B 三套独立 fixture 已物化且 G-R/G-C PASS；完成记录：`docs/02-evidence/es-is-20261005/ES_CSP_R01_FIXTURE_PREPARATION/S1_COMPLETION_RECORD_20261006.md`。当前停 = S2 Human fixture review。S3 NOT AUTHORIZED。
> **UPDATE 5：S2 PASS；S3 AUTHORIZED for ES-CSP-RUN-01 ONLY**。裁定：`docs/00-governance/PALACE_INFORMATION_SPACE_FOUNDATION_ES_CONTINUATION_SUFFICIENCY_PROBE_S2_PASS_S3_AUTHORIZATION_20261006.md`。证据边界 = manifest/evidence-level review；不声称外部 fixture root 物理副本式第二审计。C3 observation only。
> **UPDATE 6：ES-CSP-RUN-01 EXECUTED；bounded verdict = `PASS — CONTINUATION SUFFICIENT`**。完成记录：`docs/02-evidence/es-is-20261005/ES_CSP_R01_EXECUTION/S3_COMPLETION_RECORD_20261006.md`。P-POS passed；N-A blocked on unresolved reference；N-B blocked on ambiguous pointer set；C3 not performed；fixtures unchanged。下一阶段未被 run 开启。
> 权威现状面 = `docs/RESEARCH_CONTEXT_INDEX.md` + `docs/02-evidence/es-is-20261005/SESSION_LOG_20261006.md`。
> 本文档其余部分（接管原则/核心定义/禁止清单 §11）仍然有效。

交接日期：2026-10-06
更新：旧分支已在 GitHub 网页端删除核验；当前远端只保留 `main`。

研究仓库：
- slamfinger/SimiGo-Lab
- 当前唯一 canonical Research State：main
- 当前 main HEAD：以 GitHub 当前 `main` 动态核验为准
- 最近 topology merge：6ad810466695ed0703c5291c1039736185465248

## 1. 接管原则

新会话不要从零推导研究状态。

优先读取：
1. docs/RESEARCH_CONTEXT_INDEX.md
2. 当前 RESEARCH_STATE.md
3. docs/00-governance/EVIDENCE_INHERITANCE_DESIGN_MATRIX_20261006.md
4. docs/00-governance/SIMIGO_LAB_BRANCH_CONSOLIDATION_RULING_20261006.md
5. 本交接文件
6. UA v0.3、Targeted Review、Freeze Review

判断优先级：

Frozen Contract > Human Ruling > L2 authoritative document > L1 capsule > L0 index

未有新的 Human 授权，不得自行实现、迁移、选型、实验、重组或改变冻结协议。

## 2. 当前研究核心

SimiGo 核心路线：

Execution State ↔ Information Space / PALACE

重要定义：
- SimiGo 是 Execution State 技术路线，不是 inference engine。
- PALACE / Information Space 是 SimiGo 一体化层，不是简单外部 MCP。
- Knowledge Base 只是 Information Space 的初始条件。
- Information 与 Relation 是语义对象。
- File 与 Session 是 Unified Carrier 的两个 instance families，不是两套 Information semantics。
- Agent 是 actor / provenance subject，不是新的 Information / Relation semantic entity。

## 3. Information / Relation 状态

当前已接受/冻结：
- I-1 Persistence / Resolve
- I-1c Instantiate Completeness
- Phase 2 Relation Persistence
- Core Sufficiency Audit

当前 PRQ-ISF-01 边界：
- UTF-8
- text-bounded
- task-domain-bounded

当前结论：
- InformationStore 与 RelationStore 独立。
- 不引入 generic Super Store。
- Arbitrary-byte fidelity 只是条件性未来问题。
- MemPalace AS-IS 作为独立 PRQ-ISF-01 semantic carrier = bounded NO-GO；不是全局否定。

## 4. Unified Carrier 当前状态

当前方向：

Existing Information/Relation Semantics
    ↓
Unified Carrier Contract
    ↓
Carrier Representation / Record
    ↓
Derived Access

冻结原则：
File 与 Session 是同一个 Carrier Contract 下的两个实例族。

禁止：
- File Information / Session Information 双语义模型
- AgentInformation / AgentRelation / AgentStore
- FileConcurrencyStore / SessionConcurrencyStore
- 第二套 Information/Relation semantics

## 5. CCVS-01

Phase B：
- CCVS-01-PB v1.2 = FROZEN
- 禁止中途修改协议。

File-side Phase C：
- A1 CarrierSQLite IMPLEMENTED
- conformance 10/10 PASS
- Baseline A SMALL 5/5 VALID
- Baseline A MEDIUM 5/5 VALID
- PB-B1..B14 MET
- P8 F1-F9 EXECUTED
- G2 PASS
- D-A / D-B / D-C VALID

关键证据：
P8 F7 发现 authority 可以恢复身份覆盖，但如果搜索文本只在 derived index 中，就无法宣称 promised searchable coverage 可以完整 rebuild。
该结果保留为 File-side baseline evidence，不是 U-A 模板。

Unified U-2：
- NOT STARTED
- NOT AUTHORIZED
- Unified benchmark NOT AUTHORIZED
- Backend selection NOT AUTHORIZED
- Migration NOT AUTHORIZED
- Lab physical reorganization NOT AUTHORIZED

## 6. UA v0.3

当前状态：
- UA v0.3 delivered
- Targeted Conformance Review = NO BLOCK
- Freeze Gate = OPEN
- Design mainline = ACCEPTED
- U-2 = NOT AUTHORIZED

Freeze Review 的五个条件：

1. UA-P7
   “Layer ① 无新增 semantic concurrency contract”
   不等于 compound operations 可以逃避 carrier-layer atomicity。
   MA-4 继续约束 compound operations。

2. I20
   禁止的是 unintended duplicate Carrier identity / conflicting duplicate
   registration。
   不能解释成一个 Information 只能有一个 representation / locator。

3. Unified concurrency
   统一的是 contract / guarantees，不是一个物理算法。
   CAS、atomic sequence allocation、SQLite transaction、
   build-version+swap 等都可以。
   Universal Lock Manager 不允许。

4. U-A rebuild completeness
   authority 必须持有足够 searchable source content。
   否则只能报告 incomplete rebuild capability。

5. State hygiene
   后续 crash-boundary PASS 应显式记录 expected detached/orphan state。
   已有 P8 不回溯修改。

## 7. CC-MA

Multi-Agent concurrency 已成为 first-class carrier/database constraint。

MA-1 stale-write detection
MA-2 lost-update prevention
MA-3 atomicity
MA-4 consistency / complete provenance
MA-5 identity stability
MA-6 session ordering
MA-7 idempotent retry
MA-8 provenance under concurrency
MA-9 derived-index isolation
MA-10 snapshot / recovery consistency

MA-DS-1 “Multi-Agent Research Day”：
- binding design scenario
- NOT completed validation

## 8. 下一合法入口

Gate A：CLOSED
- File-side Phase C 已完成并形成有效证据。

Gate B：OPEN
- Human 对 UA v0.3 做 ACCEPT/FREEZE、REVISE 或 PARK。
- 尚未冻结前，不写 U-2 implementation。

Gate C：NOT STARTED
Human Freeze 后，若另行授权 U-2：
- 第一交付物：U-A Unified Minimal composition manifest
- FILE + SESSION
- Information/Carrier mapping
- provenance
- CC-MA mechanisms

首轮验证问题：

“在最小 SQLite + POSIX substrate 上，Unified Carrier 是否能让
File 与 Session 共用一个 Carrier contract，并承受 Multi-Agent Research Day？”

首轮不做 horizontal carrier-topology comparison。

## 9. Evidence inheritance

HLC-1..HLC-16 是 bounded evidence，不自动变成 implementation requirements。

当前矩阵：
docs/00-governance/EVIDENCE_INHERITANCE_DESIGN_MATRIX_20261006.md

## 10. 分支状态与本轮收口结果

当前 GitHub 远端分支已核验为：

```text
main
```

旧分支已删除：
- codex/research-recovery-layer-v0.1
- integration/path-a-information-place
- codex/execution-state-research-20260929
- research/es-reuse-program-20260930

历史信息仍通过 main 的 commit graph 保留：
- codex 历史通过 772d1225 进入 main 历史；
- ES-reuse 历史通过 6ad81046 进入 main 历史；
- 旧分支删除不等于历史 commit 丢失。

重要边界：
- 旧 ES-reuse 文件没有导入当前 PALACE main tree；
- 删除旧分支不会重新打开 ES research；
- 新会话只能以 main 作为当前研究入口；
- 不应从已删除分支名称推断当前研究状态。

本轮 branch consolidation 的本质：
“合并 repository history + 删除无用 branch refs”，不是“重新采用历史研究内容”。

## 11. 严格禁止的自动动作

不要自行：
- 从历史分支恢复当前工作；
- cherry-pick / merge 旧内容以改变当前语义；
- 开 U-2；
- 开 Unified benchmark；
- 选 final backend；
- 修改 PB v1.2；
- 修改 Frozen Contracts；
- 实施 MemPalace integration；
- 重组 Lab 物理目录；
- 打开 ES↔IS；
- 创建第二套 Information/Relation semantics；
- 创建 Agent semantic entity/store；
- 创建双 concurrency model；
- 创建 Universal Lock Manager。

## 12. 当前一句话状态

SimiGo-Lab/main = canonical Research State；
Information/Relation 当前语义已接受；
File + Session 的 Unified Carrier Contract UA v0.3 设计主线已接受但仍在 Freeze Gate；
File-side Phase C 已完成有效证据；
U-2、Unified benchmark、backend selection、migration 均未授权；
下一合法动作是 Human 对 UA v0.3 五个 freeze conditions 做正式裁决。
