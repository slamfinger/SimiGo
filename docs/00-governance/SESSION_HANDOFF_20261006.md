# SimiGo-Lab 新会话研究任务交接基线

> **🔴 CURRENT RECOVERY ANCHOR — READ FIRST (2026-10-06)**
> Recovery baseline = `0508e26`。
> Research-state content revision = `bcc6b81`。
> Current `main` = verify dynamically with `git rev-parse HEAD`。
> Recovery anchor: `docs/00-governance/SIMIGO_LAB_RESEARCH_STATE_MEMORY_RECOVERY_ANCHOR_20261006.md`.
> Authoritative restored state: `docs/RESEARCH_STATE.md` → “Restored research state / memory anchor”.
> Canonical source: GitHub `slamfinger/SimiGo-Lab@main`.
>
> **当前全局目标：** 研究 ES 是否能与持久 IS 形成真实计算耦合，使 ES₁ settled
> relation 成为独立 ES₂ 的合法、可验证、可复用计算状态，只计算真正 Δ，并在
> dependency invalid 时 block / recompute。
>
> **当前状态（2026-10-07 override）：** corrected EXECUTION Request v0.7 已
> 开启并提交审查：`e721f7a`。EXEC-004 audit closed，root cause =
> bilateral fixture-runner τ interface contract defect。v0.7 提议先完成
> scoped τN1 interface，再实例化 records 005 和 corrected campaign。当前停点
> = Human authorization review；不得未经批准修改 τ、创建 records 或运行。
>
> **当前唯一 active closure task：**
> `SRS-SEM-01 Minimal Settled Relation State Semantic Boundary`
> Status = `ACCEPT / FROZEN`。
>
> **当前唯一 active closure task：**
> `SRS-VAL-01 Settled Relation State Reuse Validation Predicate`
> Status = `V0.1 REVISE / V0.2 REVISE / V0.3 REVISE / V0.4 DELIVERED FOR HUMAN REVIEW`。
> Implementation / fixture / experiment remain NOT AUTHORIZED。
>
> **Supersession rule：** 下方历史层与旧状态若与 2026-10-07 override、当前
> Recovery Anchor 或 `docs/RESEARCH_STATE.md` 冲突，以后者为准。不要根据旧
> UPDATE、已删除 branch 或对话记忆恢复状态。
> **UPDATE 15：Recovery Anchor CLOSED；Human authorized SRS-SEM-01.**
> Design v0.1 delivered:
> `docs/02-evidence/es-is-20261005/SIMIGO_ES_IS_SRS_SEMANTIC_BOUNDARY_DESIGN_V0.1_20261006.md`.
> Status = `SRS-SEM-01 DESIGN DELIVERED FOR HUMAN REVIEW`. This authorizes only
> semantic-boundary design review; it does not authorize implementation, fixture,
> experiment, IS mutation, SRS-VAL-01, or code change.
> **UPDATE 16 (2026-10-07)：SRS-SEM-01 v0.1 = REVISE；v0.2 DELIVERED FOR HUMAN REVIEW.**
> Corrections: `DECLARED_SETTLED` rather than circular lawful-settlement definition;
> exact revision binding only; conservative lifecycle conflict handling;
> result identity ≠ SRS identity; minimum provenance obligations; freshness
> requirements rather than verdicts. `SRS-VAL-01`, implementation, fixture, and
> experiment remain NOT AUTHORIZED.
> **UPDATE 18 (2026-10-07)：SRS-SEM-01 v0.3 = REVISE；v0.4 DELIVERED FOR HUMAN REVIEW.**
> Corrections: context-independent immutable source-relation identity; exact
> immutable result-state identity/revision target; exact immutable resolution
> rule identity/version; exact immutable policy/semantic version binding;
> recomputation prohibition moved to reuse validation. `SRS-VAL-01`,
> implementation, fixture, and experiment remain NOT AUTHORIZED.
> **UPDATE 20 (2026-10-07)：SRS-SEM-01 v0.5 = ACCEPT / FROZEN；SRS-VAL-01 Design v0.1 COMMISSIONED AND DELIVERED FOR REVIEW.**
> SRS-VAL-01 defines REUSE / BLOCK / RECOMPUTE semantic predicate only.
> Implementation, fixture, experiment, and IS mutation remain NOT AUTHORIZED.
> **UPDATE 21 (2026-10-07)：SRS-VAL-01 v0.1 = REVISE；v0.2 DELIVERED FOR HUMAN REVIEW.**
> Corrections: SRS never authorizes RECOMPUTE; separate exact governing
> recompute/reuse authorization binding added; exact current reuse request
> binding added; single lawful validation observation boundary required;
> failure-to-RECOMPUTE now requires explicit invalidation-class authorization;
> positive freshness-clearing semantics registered. Implementation, fixture,
> experiment, and IS mutation remain NOT AUTHORIZED.
> **UPDATE 22 (2026-10-07)：SRS-VAL-01 v0.2 = REVISE；v0.3 DELIVERED FOR HUMAN REVIEW.**
> Corrections: source-relation invalidation uses failure classification and is
> HARD_BLOCK unless exact I-14 covers the class; I-14 never overrides lifecycle
> blockers. Formal decision precedence frozen: observation inconsistency /
> HARD_BLOCK / applicability failure / all-remaining-failures-covered /
> no-failure map to BLOCK / BLOCK / BLOCK / RECOMPUTE / REUSE. Exactly one
> primary decision; outcomes mutually exclusive. Context Index current design
> pointer corrected to v0.3. Implementation, fixture, experiment, and IS mutation
> remain NOT AUTHORIZED.
> **UPDATE 23 (2026-10-07)：SRS-VAL-01 v0.3 = REVISE；v0.4 DELIVERED FOR HUMAN REVIEW.**
> Corrections: I-14 now requires an exact immutable RECOMPUTE semantic envelope;
> covered target semantic class, result-target identity/derivation boundary, and
> canonical relation-identity generation rule binding. Canonical identity rule
> binds EXACT_RULE_VERSION; authorization cannot implicitly change it. Every
> remaining failure must first be classified RECOMPUTE_ELIGIBLE by a registered
> predicate rule; I-14 coverage alone cannot upgrade an unclassified failure.
> Implementation, fixture, experiment, and IS mutation remain NOT AUTHORIZED.
> **UPDATE 19 (2026-10-07)：SRS-SEM-01 v0.4 = REVISE；v0.5 DELIVERED FOR HUMAN REVIEW.**
> Corrections: canonical identity-generation rule binds EXACT_RULE_VERSION;
> canonical semantic changes require a new rule identity/version; existing SRS
> source identity is never reinterpreted; provenance and lifecycle evidence
> references bind immutable identity / exact revision / immutable content
> address; mutable/unversioned evidence blocks determinate reuse. `SRS-VAL-01`,
> implementation, fixture, and experiment remain NOT AUTHORIZED.
> **UPDATE 17 (2026-10-07)：SRS-SEM-01 v0.2 = REVISE；v0.3 DELIVERED FOR HUMAN REVIEW.**
> Corrections: concrete source-relation instance identity; reusable result must
> be directly consumable or lawfully resolvable; `FRESHNESS_RECHECK_REQUIRED`
> blocks reuse; minimum lifecycle evidence; exact revision equality separate
> from freshness; Context Index stale navigation corrected. `SRS-VAL-01`,
> implementation, fixture, and experiment remain NOT AUTHORIZED.

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
> **UPDATE 7：R01 CLOSED / ACCEPTED；verdict BOUNDED PASS。** Non-blocking `ES-CSP-MF-01` 登记为 distinct-target uniqueness 边界。下一研究缺口 = **PIR — Physical–Information Reconciliation**；PIR implementation/experiment/code change NOT AUTHORIZED。
> **UPDATE 8：PIR Design v0.1 已提交 Human design review**：`docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_PIR_DESIGN_V0.1_20261006.md`。仅设计；PIR implementation/experiment/code change NOT AUTHORIZED。
> **UPDATE 9：Query-Priority Reconciliation direction ACCEPTED；PIR Design v0.2 已提交 Human review**。核心原则 = query scope 优先 reconciliation，而非全库同步；ICAC 为 metric direction；10k/20/5 future shape 仅设计方向，NOT COMMISSIONED。
> **UPDATE 10：PIR v0.2 = CONDITIONAL PASS；Clarification Addendum 已交付**。五项定义已锁死：Information Scope + Physical Scope、Scope Resolution 与 Reconciliation 分测、ICAC cost vector、`W_age`/`W_latency` 分离、request-relative HOT/COLD。Minimal PIR Probe Design NOT COMMISSIONED；PIR implementation/experiment/code change NOT AUTHORIZED。
> **UPDATE 11：PIR v0.2 + Clarification Addendum ACCEPTED；Minimal PIR Probe Design v0.1 COMMISSIONED AND DELIVERED FOR REVIEW**。仅设计；implementation/experiment/fixture/code change 均 NOT AUTHORIZED。
> **UPDATE 12：Minimal PIR Probe v0.1 = CONDITIONAL PASS；v0.2 已提交 Human review**。四项修订：`W_obs_age`、non-circular scope boundedness、phase scaling attribution、MOVE/RENAME protocol。Fixture/implementation/experiment 均 NOT AUTHORIZED。
> **UPDATE 13：ES–IS Settled Relation Coupling audit package 已交付待审**。`Settled Relation State` = 新 canonical composite，不是 cache/bare result/checkpoint；`Information Topology` = ES 累积形成的 Information/Relation/SRS 结构。核心缺口 = **ES₁→IS→ES₂ Settled Relation Reuse**，NOT ESTABLISHED。PIR v0.2 保持 accepted freshness prerequisite design，但 Minimal PIR Probe v0.2 暂停，等待 central architecture ruling。SRS implementation/experiment/code change NOT AUTHORIZED。
> **UPDATE 14：Issue #2 decomposition/control artifact 已交付待审**。只选择一个最小下一封口任务：`SRS-SEM-01 Minimal Settled Relation State Semantic Boundary`，status = SELECTED / NOT STARTED。通过后才允许单独准备 SRS-SEM-01 design；后续依赖是 `SRS-VAL-01`。没有实现、fixture、实验、IS mutation 或 code change 授权。
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
> **UPDATE 24 (2026-10-07)：SRS-VAL-01 v0.4 = REVISE；v0.5 DELIVERED FOR HUMAN REVIEW.**
> Corrections: every RECOMPUTE_ELIGIBLE classification requires an exact immutable
> registered predicate-rule identity/version and integrity/content-address
> binding; classification uses only the exact bound predicate-rule version;
> later revisions cannot retroactively reinterpret earlier validation bases;
> missing/unstable predicate-rule binding forces BLOCK; Context Index all current
> navigation fields unified to v0.4. Implementation, fixture, experiment, and IS
> mutation remain NOT AUTHORIZED.
> **UPDATE 38 (2026-10-07)：Run/Implementation Manifest v0.2 = REVISE；v0.3 DELIVERED FOR DESIGN REVIEW.**
> Corrections: M4 requires a future manifest to exact-bind the accepted/frozen
> Manifest Contract identity and integrity; superseded references stop the
> runner. M5 exact-binds rule representation format, language spec, grammar, and
> interpreter semantics, with interpreter fidelity inside T-IMPL-01 rather than an
> implicit runtime dependency. M6 requires the expected semantic read set to be
> independently produced, root-backed Human-authorized, content-bound, and frozen
> before subject start; observed reads cannot define expected reads.
> Implementation, fixture, execution, and IS mutation remain NOT AUTHORIZED.
> **UPDATE 39 (2026-10-07)：Run/Implementation Manifest v0.3 = REVISE；v0.4 DELIVERED FOR DESIGN REVIEW.**
> Corrections: M7 requires rule/language/interpreter fidelity PASS from a
> pre-authorized external verifier, with an immutable verification record frozen
> before T-IMPL-01; M8 requires exact binding among the executed Decision Core
> artifact, authorized interpreter component, interpreter semantics,
> language/grammar, and rule; M9 requires a pre-authorized semantic-input
> completeness closure to derive the expected read set from every semantically
> necessary binding. Implementation, fixture, execution, and IS mutation remain
> NOT AUTHORIZED.
> **UPDATE 40 (2026-10-07)：Run/Implementation Manifest v0.4 = REVISE；v0.5 DELIVERED FOR DESIGN REVIEW.**
> Corrections: M10 requires required semantic closure, exact implementation
> semantic closure, observed implementation semantic mapping, and expected semantic
> read closure to agree. M11 partitions inputs into disjoint SEMANTIC_INPUT,
> GOVERNANCE_AUTHORITY_INPUT, and OBSERVATION_CONTROL_INPUT categories; only
> semantic inputs may enter the predicate closure. M12 requires the M9 closure
> verifier to have independent, root-backed, non-circular separation from
> T-IMPL-01, implementation, manifest generation, fixture building, expected-read
> generation, and observation. Implementation, fixture, execution, and IS mutation
> remain NOT AUTHORIZED.
> **UPDATE 41 (2026-10-07)：Run/Implementation Manifest v0.5 = REVISE；v0.6 DELIVERED FOR DESIGN REVIEW.**
> Corrections: M13 replaces direct semantic-input/read-set equality with a typed
> partition into materialized values, external semantic reads, and not-used
> dispositions; only the external-read partition enters expected/observed read
> closure. M14 limits classification to inputs capable of affecting predicate
> result, authorization validity, or observation validity; pure
> NON_DECISION_METADATA stays outside closure. M15 requires category assignment by
> an independent root-backed external verifier with non-circular separation.
> Implementation, fixture, execution, and IS mutation remain NOT AUTHORIZED.
> **UPDATE 42 (2026-10-07)：Run/Implementation Manifest v0.6 = REVISE；v0.7 DELIVERED FOR DESIGN REVIEW.**
> Corrections: M16 replaces raw semantic-input identity equality with
> path-sensitive disposition closure; NOT_USED requires no read and exact frozen
> justification, MATERIALIZED requires the exact value, and EXTERNAL_READ requires
> exactly one expected read instance. M17 adds explicit total, one-to-one,
> non-inventive, immutable mappings from required external semantic inputs to
> expected and observed read instances. Implementation, fixture, execution, and IS
> mutation remain NOT AUTHORIZED.
> **UPDATE 33 (2026-10-07)：Authorization Package v0.5 = REVISE；v0.6 DELIVERED FOR HUMAN REVIEW.**
> Correction: v0.6 adds the missing frozen decision-state closure. It defines
> REUSE_PATH, BLOCKED_NON_RECOMPUTE_PATH, and RECOMPUTE_AUTHORIZATION_PATH; makes
> blocked-non-recompute lawful only after higher-precedence resolution or
> completed classification with no eligible failure; and restricts
> I14_NOT_USED_NO_RECOMPUTE_PATH to the three lawful states. Incomplete
> classification with the marker stops as
> PREDICATE_RULE_CLASSIFICATION_REQUIRED. Implementation, fixture, execution, and
> IS mutation remain NOT AUTHORIZED.
> **UPDATE 34 (2026-10-07)：Authorization Package v0.6 = ACCEPT / FROZEN.**
> Final freeze-before-execution state-space attack passed normative restatement,
> decision-state completeness, G-CLASS non-bypassability, trust chain, observer
> authorization/integrity, channel universe, runtime dependency closure,
> IS_MUTATION executor closure, read-instance immutability, TOCTOU/drift, and
> boundary coverage. The package grants no authority. Next lawful object is a
> separate Implementation / Fixture / Execution Authorization Request and
> Run/Implementation Manifest; it is NOT OPENED. Implementation, fixture,
> execution, and IS mutation remain NOT AUTHORIZED.
> **UPDATE 35 (2026-10-07)：Implementation Boundary Audit v0.1 DELIVERED FOR HUMAN REVIEW.**
> Human directed a design-only audit of the minimal authorizable implementation
> target. Audit v0.1 proposes T-IMPL-01 SRS-VAL Decision Core: a pure
> invocation-record predicate returning REUSE/BLOCK/RECOMPUTE plus typed evidence
> trace. It excludes carrier, persistence, runner, observer, fixture builder,
> model/runtime, execution harness, and IS mutation executor. It maps fixture,
> manifest, stage-separation, mutation/runtime evidence, and adversarial
> pre-review requirements. No code, fixture, run, or IS mutation is authorized.
> **UPDATE 36 (2026-10-07)：Implementation Boundary Audit v0.1 = ACCEPT / FROZEN；Run/Implementation Manifest v0.1 DELIVERED FOR DESIGN REVIEW.**
> T-IMPL-01 SRS-VAL Decision Core is fixed as the minimum implementation boundary.
> Manifest v0.1 adds three binding constraints: Registered Predicate Rule Artifact
> is separate from Decision Core; deterministic semantic derivation trace is not
> observer-authoritative evidence; Invocation Record must be a closed immutable
> value graph. The manifest is design-only and authorizes no implementation,
> fixture, execution, or IS mutation.
> **UPDATE 37 (2026-10-07)：Run/Implementation Manifest v0.1 = REVISE；v0.2 DELIVERED FOR DESIGN REVIEW.**
> Corrections: M1 exact-binds each Predicate Rule Artifact to frozen SRS-VAL v0.8
> through content-addressed semantic-basis and normative-extraction bindings plus
> a fidelity verdict; M2 materializes the resolved Predicate Rule semantic value
> inside the closed Invocation Record instead of accepting a pointer/digest alone;
> M3 requires exact expected-to-observed read-instance/content mapping and a
> semantic read-closure verdict. Implementation, fixture, execution, and IS
> mutation remain NOT AUTHORIZED.
> **UPDATE 25 (2026-10-07)：SRS-VAL-01 v0.5 = REVISE；v0.6 DELIVERED FOR HUMAN REVIEW.**
> Corrections: I-16 now explicitly includes I-14, I-15, and the exact
> predicate-rule binding as decision-critical inputs in one observation
> boundary; omission, ambiguity, instability, or mixed-boundary evidence
> forces BLOCK / VALIDATION_INPUT_STATE_INCONSISTENT. Context Index current,
> design, review, and next-transition fields now identify v0.6. Implementation,
> fixture, experiment, and IS mutation remain NOT AUTHORIZED.
> **UPDATE 26 (2026-10-07)：SRS-VAL-01 v0.6 = REVISE；v0.7 DELIVERED FOR HUMAN REVIEW.**
> Correction: I-14 is a conditional RECOMPUTE-path authorization, not an
> every-invocation prerequisite. Pure REUSE records
> I14_NOT_USED_NO_RECOMPUTE_PATH and is not blocked for lacking recomputation
> authorization; RECOMPUTE_ELIGIBLE still requires exact immutable I-14 in the
> same I-16 boundary. I-15 remains mandatory, predicate-rule conditionality is
> unchanged, and navigation identifies v0.7. Implementation, fixture,
> experiment, and IS mutation remain NOT AUTHORIZED.
> **UPDATE 27 (2026-10-07)：SRS-VAL-01 v0.7 = REVISE；v0.8 DELIVERED FOR HUMAN REVIEW.**
> Corrections: surviving failures not already resolved by higher precedence must
> undergo registered predicate-rule classification before
> BLOCKED_NON_RECOMPUTE_PATH or RECOMPUTE; I14_NOT_USED_NO_RECOMPUTE_PATH never
> means skipped classification; the Recovery Anchor commissioned-design field
> now identifies v0.8 and v0.1..v0.7 are superseded lineage. Implementation,
> fixture, experiment, and IS mutation remain NOT AUTHORIZED.
> **UPDATE 28 (2026-10-07)：SRS-VAL-01 v0.8 = ACCEPT / FROZEN；Authorization Package v0.1 DELIVERED FOR HUMAN REVIEW.**
> The Human state-space attack found no unresolved path. G-CLASS closes
> classification bypass; pure REUSE needs no I-14; RECOMPUTE requires exact
> predicate rule, exact I-14, and exact semantic envelope. v0.9 is not
> warranted. The next object is the separately reviewed Implementation /
> Fixture / Execution Authorization Package v0.1. Its review does not authorize
> implementation, fixture preparation, execution, or IS mutation.
> **UPDATE 29 (2026-10-07)：Authorization Package v0.1 = REVISE；v0.2 DELIVERED FOR HUMAN REVIEW.**
> Corrections: ES-IND-01 now requires independent ES1/ES2 process, runtime,
> memory, singleton/static, conversation, object-graph, IPC/shared-memory, and
> runner-cache boundaries; ES2 may use only declared IS/SRS artifacts and
> immutable inputs. Every stage now requires an immutable scope-bound Stage
> Authorization Record; one stage never implies another, and invalid or
> out-of-scope authorization stops the runner. Implementation, fixture,
> execution, and IS mutation remain NOT AUTHORIZED.
> **UPDATE 30 (2026-10-07)：Authorization Package v0.2 = REVISE；v0.3 DELIVERED FOR HUMAN REVIEW.**
> Corrections: v0.3 is self-contained and adds Human Ruling Approval exact
> binding for authorization authenticity; IS_MUTATION is a separate stage/type;
> EXECUTION binds exact repository commit, implementation artifact content
> address, and runtime artifact identity; ES-IND-01 adds expected/observed
> read-set and channel closure; ES1 termination is default, with quiescence only
> as evidenced exception. Implementation, fixture, execution, and IS mutation
> remain NOT AUTHORIZED.
> **UPDATE 31 (2026-10-07)：Authorization Package v0.3 = REVISE；v0.4 DELIVERED FOR HUMAN REVIEW.**
> Corrections: observations require an independent, prebound, tamper-resistant,
> coverage-complete Observation Integrity Boundary; ES2 cannot authoritatively
> define its own observed read-set. Authorization now descends from an immutable
> Authorization Authority Root through Human Ruling and authorized issuer to the
> Stage Authorization Record. EXECUTION closes actual loaded runtime dependencies;
> IS_MUTATION closes exact executor, environment, dependencies, states, and
> effects; semantic input requires read-instance immutability. Implementation,
> fixture, execution, and IS mutation remain NOT AUTHORIZED.
> **UPDATE 32 (2026-10-07)：Authorization Package v0.4 = REVISE；v0.5 DELIVERED FOR HUMAN REVIEW.**
> Corrections: v0.5 is genuinely self-contained and restates frozen predicate,
> G-V, DP, G-CLASS, exclusivity, and faithfulness obligations. It adds an
> immutable Runner Trust Anchor above the authority root, root-backed Observer
> Authorization, Human-approved Channel Universe with COVERED/IMPOSSIBLE-only
> closure, exact semantic dependency equality with mechanical allowlist subset,
> and revision-to-digest read binding. Implementation, fixture, execution, and IS
> mutation remain NOT AUTHORIZED.
> **UPDATE 43 (2026-10-07)：Run/Implementation Manifest v0.7 = REVISE；v0.8 DELIVERED FOR DESIGN REVIEW.**
> Corrections: M17 mappings are phased. PRE-RUN freezes semantic input to
> expected read instance; POST-RUN Observer freezes expected read instance to
> observed read instance; final composition is immutable only after Observation
> Integrity closure. M18 requires observer-authoritative realization for every
> required disposition and exact equality between observed semantic reads and
> required external-read realizations, with no undeclared, missing, or invented
> semantic read. Mapped identities must resolve to complete immutable
> read-instance records. Implementation, fixture, execution, and IS mutation
> remain NOT AUTHORIZED.
> **UPDATE 44 (2026-10-07)：Run/Implementation Manifest v0.8 = REVISE；v0.9 DELIVERED FOR DESIGN REVIEW.**
> Corrections: M18 now defines RequiredExternalSemanticInputSet,
> ExpectedReadInstanceSet, and ObservedReadInstanceSet with distinct identity
> types; closure is verified through semantic-to-expected and
> expected-to-observed domains/codomains and a composed relation, not cross-type
> set equality. Realization evidence is disposition-specific: MATERIALIZED uses
> closed Invocation Record evidence, EXTERNAL_READ uses observer-authoritative
> read evidence, and NOT_USED uses closed negative-realization evidence plus
> observer negative-read closure. Implementation, fixture, execution, and IS
> mutation remain NOT AUTHORIZED.
> **UPDATE 45 (2026-10-07)：Run/Implementation Manifest v0.9 = REVISE；v1.0 DELIVERED FOR DESIGN REVIEW.**
> Correction: M18 now separates observed-read fact authority from semantic-role
> classification authority. Observer provides observed read facts only. An
> independent root-backed Classification Verifier assigns SEMANTIC,
> NON_SEMANTIC_MECHANICAL, or FORBIDDEN_UNDECLARED_SEMANTIC roles using frozen
> semantic-input universe, category assignment, predicate semantic basis, and
> authorization/observation boundaries. Observer cannot alone downgrade a
> decision-relevant read to mechanical. Classification applies to subject
> consumable read universe; governance/observation control inputs are not
> implicitly mechanical. Implementation, fixture, execution, and IS mutation
> remain NOT AUTHORIZED.
> **UPDATE 46 (2026-10-07)：Run/Implementation Manifest Contract v1.0 = ACCEPT / FROZEN.**
> Final review passed M16 path-sensitive disposition, M17 phased read mapping,
> M18 typed realization relations, disposition-specific evidence authority,
> observed-read role authority, hidden semantic-read closure, and negative-read
> closure. Non-blocking execution-stage obligation: if an external read consumes a
> semantic value that should have been INVOCATION_MATERIALIZED_VALUE, it must be
> classified FORBIDDEN_UNDECLARED_SEMANTIC_READ and must not count as a lawful
> EXTERNAL_READ realization. Next lawful object is a separately reviewed Human
> Authorization Request plus filled Manifest Instance; it is NOT OPENED.
> Implementation, fixture, execution, and IS mutation remain NOT AUTHORIZED.
> **UPDATE 47 (2026-10-07)：AUTH-REQ-01 Human Authorization Request v0.1 + IMPLEMENTATION-only Filled Manifest Instance v0.1 = OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW.**
> requested_stage_set = { IMPLEMENTATION }. Authorized repository revision =
> eef3d24901e23b734bb887841528c0c7b4b42aa0. Authorized writable paths are limited
> to trackD-memory/Sources/SettledRelationValidationCore/ and a bounded root
> Package.swift target-registration edit. Execution_run_budget = 0,
> fixture_preparation_budget = 0, and is_mutation_budget = 0. No Stage
> Authorization Record exists. Request SHA256 =
> 0e2e55dec2c9c19291fa98b701838949ee0ecf866392ba5ee7051536684e9a11. Instance
> SHA256 =
> 8ef4912167cd374146e491c89194981940d8e505ef458f56cbf9950b8aa60a73.
> Implementation, fixture, execution, and IS mutation remain NOT AUTHORIZED.
> **UPDATE 48 (2026-10-07)：AUTH-REQ-01 v0.1 = REVISE REQUEST；v0.2 OPENED / SUBMITTED FOR HUMAN AUTHORIZATION REVIEW.**
> Correction: Request, Filled Manifest Instance, and Immutable Bindings now
> exact-bind all four frozen bases with commit, Git blob content address, Git blob
> SHA1 integrity binding, and SHA256. Request v0.2 and Manifest Instance v0.2 also
> receive exact content bindings. requested_stage_set remains { IMPLEMENTATION },
> no Stage Authorization Record exists, and no stage is authorized.
> **UPDATE 49 (2026-10-07)：Research focus reset；SRS-REAL-CLOSURE-01 = ACTIVE RESEARCH PRIORITY.**
> Frozen governance objects remain unchanged and are now frozen research governance
> infrastructure. AUTH-REQ-01 v0.2 remains pending Human authorization review with
> only a final authorization-chain audit allowed (PASS or minimal defect repair).
> Governance refinement is maintenance-only and may not become P0. New research
> priority order: P0 real ES₁ → IS → ES₂ reuse evidence; P1 negative
> mutation/BLOCK/RECOMPUTE evidence; P2 non-recomputation/independence evidence;
> P3 carrier scale/Reality Mapping; P4 topology/multi-backend; P5 governance
> refinement. Registered SRS-REAL-CLOSURE-01 reorientation, critical path, and
> commission artifacts. No implementation, fixture, execution, or IS mutation is
> authorized.
> **UPDATE 50 (2026-10-07)：SRS-REAL-CLOSURE-01 execution chain advanced through implementation, fixture, and fixture revision; next lawful object = EXECUTION Authorization Request v0.3.**
> Same-day chain (all canonical on main): AUTH-REQ-01 v0.2 audit PASS (cd0de60)
> → Human APPROVE IMPLEMENTATION ONLY → SAR IMPLEMENTATION 001 (5119616) →
> T-IMPL-01 SettledRelationValidationCore implemented and completion record
> registered (07176ec; SV 11/11) → Design v0.2 ACCEPT after R1/R2 revisions
> (050b918/2be3477) → FIXTURE_PREPARATION Request v0.2 ACCEPT after R3 (7d590d7)
> → FIXTURE_PREPARATION SAR 001 (4c3def8) → fixture complete (d6507ff, manifest
> v1, 11 artifacts) → EXECUTION Request v0.1/v0.2 both B=REVISE (three-layer
> audit: authorization closure / channel closure / runner semantics; Defect
> Register D-1..D-9 registered) → FIXTURE_PREPARATION REVISION Request
> v0.1..v0.6 six-round closure (F-5 campaign-backdoor rejected; register
> D-SEC-1 strict wording; IMMUTABLE_SNAPSHOT_PRESEALED selected; mapping
> snapshot sealing; snapshot start boundary; never-reread consistency +
> writer audit Option A) → v0.6 ACCEPT → Revision SAR 001 (fdf45ea) → revision
> cycle COMPLETE (e729e32: F-1..F-4 repairs D-6/D-7/D-8/D-9; SV-1..SV-6 30/30;
> FIXTURE_MANIFEST v2 with es_runner.py re-bound 689b0401/ea8e64eb and ten
> artifacts UNCHANGED; completion record v2, zero violations, scope PASS).
> Binding semantics registered: Observer Authorization Record 001 =
> supplemental-observation authorization, NOT a §6 authoritative OIB (post-exit
> observer is not §6-compliant; authoritative-observation claim NOT AVAILABLE
> in round 1); capture pipes COVERED with exact coverage definition deferred to
> v0.3. Core claim ES₁ → IS(SRS) → independent ES₂ lawful reuse remains NOT
> ESTABLISHED (instrument ready ≠ reuse established). Next lawful object:
> EXECUTION Authorization Request v0.3 exact-binding FIXTURE_MANIFEST v2 and
> completion record v2, three-record structure (EXECUTION + scoped IS_MUTATION
> + Observer Authorization), pre-registered expected decisions judged never
> tuned. Standing disciplines: push + ls-remote verify immediately; declared
> changes re-verified before commit; governance text cannot repair instrument
> semantics; authorization boundaries guard against disguised execution via
> validation.
> **UPDATE 51 (2026-10-07)：e729e32 = canonical but NOT accepted final fixture revision state；Request v0.7 opened.**
> Request path:
> `docs/00-governance/SRS_REAL_CLOSURE_01_FIXTURE_REVISION_AUTHORIZATION_REQUEST_V0.7_20261007.md`.
> Human acceptance audit confirms SAR 001 (`fdf45ea`) authorization chain,
> single-commit scope (`e729e32` touching only `es_runner.py`, manifest v2,
> completion record v2), event order, F-1/F-2/F-3, snapshot boundary
> mechanism, writer invariant, and claimed SV-1..SV-6 30/30. It rejects final
> closure because `IMMUTABLE_REVISION` records omit
> `declared_immutable_revision`, `revision_to_content_digest_binding`, and
> `resolved_declared_content_digest`; mapping seals/events omit
> `mapping_snapshot_seal_boundary`; and the metadata post-check happens on a
> path stat after FD close rather than the original FD before close.
> Request v0.7 is canonical at `5cfcc16` and registers RF-4.5/RF-4.6/RF-4.6m.
> It permits no direct repair. Approval must create exact-binding REVISION
> SAR 002 with one work-cycle budget, field-level SV assertions, manifest v3,
> and completion record v3, then STOP for fresh Human acceptance review.
> EXECUTION, IS_MUTATION, Observer campaign, and core claim remain NOT
> AUTHORIZED / NOT ESTABLISHED.
> **UPDATE 52 (2026-10-07)：Request v0.7 APPROVED；REVISION SAR 002 work cycle consumed；STOP for acceptance review.**
> Human approved Request v0.7 (`5cfcc16`) with the directive to proceed.
> REVISION SAR 002 was created at `5296d9f`, exact-binding Request v0.7 and
> authorizing exactly one fixture revision work cycle. The work commit is
> `5eb1ec0`, scoped only to `es_runner.py`, `FIXTURE_MANIFEST.md`, and
> `FIXTURE_PREPARATION_COMPLETION_RECORD.md`. It closes RF-4.5 with complete
> IMMUTABLE_REVISION payload fields, RF-4.6 with explicit
> `mapping_snapshot_seal_boundary`, and RF-4.6m with pre-close FD-level
> fstat checks plus separate path identity. SV-1..SV-6 field-level
> revalidation = 33/33 PASS in a discarded temporary sandbox. Manifest v3,
> completion record v3, and runner blob `875cb1d9` / SHA256 `bc393362` are
> canonical; ten unchanged artifacts were byte-verified. This is DELIVERED
> FOR FRESH HUMAN ACCEPTANCE REVIEW, not final acceptance. EXECUTION,
> IS_MUTATION, Observer campaign, and core claim remain NOT AUTHORIZED /
> NOT ESTABLISHED.
> **UPDATE 53 (2026-10-07)：Fixture REVISION 002 ACCEPTED/FROZEN；EXECUTION Request v0.3 OPENED/SUBMITTED.**
> Human ruling exact form = “acceptance，继续”. Acceptance Record 002 is
> canonical at `d56ff1b`; it accepts `5eb1ec0`, Manifest v3, Completion
> Record v3, runner `875cb1d9 / bc393362`, and SV 33/33. ACCP-1
> `current["content_address"]` pre-call gap and ACCP-2 Completion Record v2
> wording residue are carried checkpoints, not silently erased. Request v0.3
> is canonical at `1088a0c`, blob `a3760c8d…`, SHA256 `b63c71aa…`. It
> replaces deferred runtime registration with deterministic adapter runtime
> SHA256 `e88c996b…`, exact-build/toolchain verification, D-SEC-1 Option B,
> D-SEC-2 capture pipes COVERED, ENV-PROBE-V1 pre-run environment closure,
> full eleven-artifact bindings, and the v3 §9 field contract with ACCP-1.
> It requests three separate cross-bound records and authorizes no stage.
> EXECUTION, IS_MUTATION, Observer campaign, and core claim remain NOT
> AUTHORIZED / NOT ESTABLISHED.
> **UPDATE 54 (2026-10-07)：Human APPROVE A+B+C instantiated three records；campaign exec-001-edf7d4a = INVALID.**
> Human ruling exact form = “批准”. Three records were canonical at
> `c454687` and all exact-bound `edf7d4a` as execution repository commit,
> excluding later governance commits. Step 0 used a detached exact checkout,
> passed Request/Manifest/Completion/Acceptance, eleven fixture artifacts,
> T-IMPL sources, and deterministic adapter build `e88c996b`. ENV-PROBE-V1
> then measured identity `ad2abb68` versus expected `9048aed2`; sole differing
> field was `swiftc_version` wording. STOP code =
> `ENVIRONMENT_CLOSED_UNIVERSE_MISMATCH`. No materialize, ES1, ES2,
> mutate-n1, ESN, observer, or core-claim evaluation ran. Evidence is
> canonical at `6b511da`. Execution budget is consumed; automatic renewal is
> forbidden. Next requires Human evidence audit and a new explicit
> authorization decision.
> **UPDATE 55 (2026-10-07)：EXEC-001 audit closed；root cause = authorization contract defect.**
> Post-campaign audit is canonical at `fa597bc`, blob `3fe6c4f4…`, SHA256
> `d1fe112a…`. Recomputation confirms measured environment identity
> `ad2abb68…` and expected `9048aed2…`; sole differing field is
> `swiftc_version`. Request v0.3 expected swift-driver wording, while its own
> ENV-PROBE-V1 faithfully stored `/usr/bin/swiftc --version` output. Thus the
> root cause is pre-authorization environment-binding inconsistency, not
> runtime drift. Fixture REVISION 002, T-IMPL-01, and adapter runtime are
> non-defective. The campaign remains INVALID; semantic stages did not run;
> execution budget is consumed; IS mutation and observer budgets are
> unconsumed; c454687 records cannot be reused. Next lawful object is Human
> decision on a corrected EXECUTION Request. A future minimal correction
> should preserve the probe and align expected swiftc_version with its actual
> output semantics, but no corrected Request is drafted or authorized here.
> Core claim remains NOT ESTABLISHED.
> **UPDATE 56 (2026-10-07)：Human authorized corrected Request；EXECUTION Request v0.4 OPENED/SUBMITTED.**
> Human ruling exact form = “授权 corrected EXECUTION Request”. This opened
> corrected Request v0.4 only; it did not approve A+B+C, create records, or
> revive old budgets. Request v0.4 is canonical at `79ce4e3`, blob
> `0b892d66…`, SHA256 `d64e4ebc…`. It supersedes consumed Request v0.3 and
> makes the sole contract correction: ENV-PROBE-V1 remains byte-for-byte
> unchanged; expected `swiftc_version` is aligned to `/usr/bin/swiftc
> --version` output semantics; corrected expected environment identity is
> `ad2abb68…`. Exact execution repository commit is `9966d31`; later
> governance commits are not execution state. If approved, it requires new
> EXECUTION SAR 002, IS_MUTATION SAR 002, and OBSERVER AUTHORIZATION RECORD
> 002 with a new independent campaign budget. No stage is authorized; core
> claim remains NOT ESTABLISHED.
> **UPDATE 57 (2026-10-07)：Human authorized corrected Request drafting；EXECUTION Request v0.5 OPENED/SUBMITTED.**
> Human ruling exact form = “授权起草一份新的 corrected EXECUTION Request /
> record set，以处理 A 类 exact-artifact provenance 问题及 B 类
> cross-binding mismatch”. This opened Request v0.5 only; no stage, campaign,
> SAR/OAR, runner repair, or old-record reuse was authorized. Request v0.5 is
> canonical at `888a6a7`, blob `45baf0b8…`, SHA256 `bb3b9e42…`. It keeps exact
> execution repository commit `9966d31` and inherits Manifest v3/Completion
> v3/artifact/T-IMPL/D-SEC/§9/environment/decision bindings. For R-A it adds
> mandatory `EXECUTION_PROVENANCE_RECORDER_003` (SHA256 `492f6f0e…`) to record
> exact executable identity/argv/process timing/stdout/stderr and fail closed
> on missing artifacts. For R-B it adds
> `EXECUTION_PROVENANCE_AND_BINDING_CLOSURE_RECORD_003`, mapping legacy runner
> `_001/V1` constants to authorized OAR 003 / CHANNEL-UNIVERSE-V2 without
> runner modification. If approved, create four records and one new campaign
> budget, then run one frozen campaign through the recorder and STOP. No stage
> is authorized; core claim remains NOT ESTABLISHED.
> **UPDATE 58 (2026-10-07)：Request v0.5 APPROVED；four records instantiated；EXEC-003 = INVALID.**
> Human ruling exact form = “批准APPROVE A+B+C”. Four records were canonical
> at `bda7829`: Provenance/Binding Closure Record 003, EXECUTION SAR 003,
> IS_MUTATION SAR 003, and OAR 003; all exact-bound execution commit
> `9966d31`. Campaign `exec-003-9966d31` used a detached exact checkout.
> Step0, adapter `e88c996b`, and corrected environment identity `ad2abb68`
> passed. EPR003 launched driver, but materialize emitted only
> `process_start` and exited 1: provenance plan used host repository root as
> cwd while exact execution state was the detached worktree, so
> `fixture/inputs/D.md` resolved against the wrong tree; no IS write occurred.
> EPR003 then failed writing its manifest because plan `output_path` was the
> run directory rather than a JSON file. Stop classes:
> `EXECUTION_PROVENANCE_RECORDER_OUTPUT_PATH_INVALID` primary and
> `CAMPAIGN_CWD_SEED_PATH_MISMATCH` secondary. Evidence is canonical at
> `a50ff8b`. Execution/provenance budgets consumed; IS mutation and observer
> budgets unconsumed; no rerun or repair authorized; core claim remains NOT
> ESTABLISHED.
> **UPDATE 59 (2026-10-07)：EXEC-003 Human evidence audit CLOSED；two independent mechanical defects accepted.**
> Read-only audit is canonical at `266e953`, blob `dfb54c7a…`, SHA256
> `b13280a4…`. Audit A accepted
> `PROVENANCE_RECORDER_OUTPUT_PATH_BINDING_DEFECT`: Request v0.5 required
> `execution_provenance.json`, but plan set `output_path` to the run directory;
> EPR003 failed closed with `IsADirectoryError` and did not fabricate a
> manifest. Audit B accepted
> `EXECUTION_CWD_AND_SEED_PATH_BINDING_DEFECT`: frozen `tau1.seed_path` was
> repository-layout-relative and absent under both host repository root and
> detached worktree root, so materialize exited 1 before any IS write. The
> defects are independent; B was causally earlier, while A is the registered
> primary stop. Deeper OS-level mechanism remains unresolved. Campaign remains
> INVALID; semantic experiment NOT RUN; E1–E6, positive REUSE, N1 BLOCK absent;
> execution/provenance budgets consumed; IS mutation and observer budgets
> unconsumed; no rerun or repair authorized. Next lawful object is Human
> decision on a corrected Request/records addressing EPR003 output-path
> preflight, exact cwd/seed-path resolution, and `_001/V1` cross-binding if in
> scope. Core claim remains NOT ESTABLISHED.
> **UPDATE 60 (2026-10-07)：Human authorized corrected Request；EXECUTION Request v0.6 OPENED/SUBMITTED.**
> Human ruling exact form = “授权新的 corrected Request / records”. This
> opened Request v0.6 only; it did not approve A+B+C, create records, execute
> EPR004, revive budgets, or modify runner/fixture. Request v0.6 is canonical
> at `8704c75`, blob `8cc67786…`, SHA256 `a6f0e2c3…`. It supersedes consumed
> v0.5/records 003 and closes both EXEC-003 defects contractually: EPR004
> requires absent regular `execution_provenance.json`, exact repository commit
> `9966d31`, exact cwd
> `<worktree>/docs/02-evidence/srs-real-closure-01`, repository-contained
> D/D' input bindings with SHA256 checks, executable identity/argv/process
> facts, and fail-closed outputs; Closure Record 004 maps `_001/V1` to OAR
> 004/CHANNEL-UNIVERSE-V2 without runner modification. If approved, create
> Closure Record 004, EXECUTION SAR 004, IS_MUTATION SAR 004, and OAR 004,
> then run one frozen campaign through EPR004 and STOP. No stage is
> authorized; core claim remains NOT ESTABLISHED.
> **UPDATE 61 (2026-10-07)：Request v0.6 APPROVED；four records instantiated；EXEC-004 = INVALID.**
> Human ruling exact form = “批准APPROVE A+B+C”. Four records were canonical
> at `b80c17a`: Provenance/Binding Closure Record 004, EXECUTION SAR 004,
> IS_MUTATION SAR 004, and OAR 004; all exact-bound execution commit
> `9966d31`. Campaign `exec-004-9966d31` used a detached exact checkout.
> Step0, EPR004 exact cwd/repository/input/provenance enforcement, adapter
> `e88c996b`, and corrected environment identity `ad2abb68` passed.
> Materialize, es1, and es2 passed; es2 observed the pre-registered REUSE.
> However, mutate-n1 failed `KeyError: d_prime_seed_path`; D' mutation and
> revision-2 mapping were absent; ESN subsequently invalidly returned REUSE
> rather than BLOCK. Observer bounded checks passed, but campaign is INVALID
> because the frozen sequence did not complete. Evidence is canonical at
> `4238529`. Execution, observer, and partial IS campaign budgets are
> consumed; automatic renewal forbidden. Positive REUSE is not campaign
> evidence; hypothesis is neither supported nor refuted; core claim remains
> NOT ESTABLISHED. Next requires Human evidence audit and a new explicit
> authorization decision.
> **UPDATE 62 (2026-10-07)：EXEC-004 Human evidence audit CLOSED；root cause = bilateral fixture-runner τ interface contract defect.**
> Read-only audit is canonical at `df508d4`, blob `6ce66e4f…`, SHA256
> `1aa8e6e0…`. Exact runner consumed undeclared top-level
> `d_prime_seed_path` and `dependencies`; bound τN1 runtime under-declared
> both. No authoritative τ schema assigned these fields. Therefore the defect
> is shared/bilateral, not one-sided τ or runner blame. N1 D' addition and
> revision-2 mapping were absent; ESN then read revision-1, returned REUSE
> instead of expected BLOCK, and that REUSE is invalid derived behavior rather
> than semantic evidence or refutation. Campaign remains INVALID; semantic
> experiment partially launched but not validly completed; E1–E6 incomplete;
> execution/observer/partial IS budgets consumed; no rerun, tau repair,
> runner repair, fixture repair, or automatic renewal authorized. Next lawful
> object is Human decision on a corrected Request/records addressing explicit
> τN1 interface schema, mutate-n1 required fields including D' binding and
> dependency ID source, preflight τ field validation, and the open
> `_001/V1` cross-binding finding if in scope. Core claim remains NOT
> ESTABLISHED.
> **UPDATE 63 (2026-10-07)：Human authorized corrected Request；EXECUTION Request v0.7 OPENED/SUBMITTED.**
> Human ruling exact form = “授权新的 corrected Request / records”. This
> opened Request v0.7 only; it did not approve T+E, modify τN1, create
> records, execute EPR004, or revive budgets. Request v0.7 is canonical at
> `e721f7a`, blob `e04a1219…`, SHA256 `fa393cab…`. It supersedes consumed
> v0.6/records 004 and closes the bilateral τ interface defect by proposing
> one scoped τN1 interface completion work cycle. Completed τN1 schema is
> exact-bound at SHA256 `156fa091…`, adding `dependencies` and
> `d_prime_seed_path` / D' SHA256 / revision. Manifest/Completion advance
> solely to v4 for rebinding. If approved, T+E creates Completion SAR/Record
> 005, then Closure Record 005, EXECUTION SAR 005, IS_MUTATION SAR 005, and
> OAR 005 exact-binding the post-completion commit; run one frozen campaign
> through EPR004 and STOP. APPROVE T ONLY stops after completion. No stage is
> authorized; core claim remains NOT ESTABLISHED.
