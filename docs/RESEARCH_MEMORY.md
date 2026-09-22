# SimiGo-Lab Research Memory Layer

> High-value memory from long-term discussion, especially informal “题外话”, that may influence future SimiGo 2.0 architecture or research direction.
>
> This file is **not** the source of current project state. `RESEARCH_STATE.md` remains authoritative.

## 1. Purpose

Research is not only a sequence of experiments. Important architecture ideas can appear before a formal RQ exists.

This layer preserves only ideas with durable value:

```
题外话 / discussion
        ↓
important insight
        ↓
fork / hypothesis
        ↓
future definition
        ↓
RQ / evidence / architecture knowledge
```

Most conversation is intentionally excluded. A memory item belongs here only if losing it could make a future researcher misunderstand why SimiGo took a particular direction.

## 2. High-value memories

### RM-001 — Research is a branching tree

SimiGo-Lab should be understood as a research tree, not a linear roadmap.

A discussion can create several plausible branches. Some become experiments, some become dead ends, and some remain dormant.

The research tree therefore needs to preserve:
- the parent idea;
- the point of divergence;
- candidate branches;
- why a branch continued or stopped.

Git preserves the implementation/evidence history; this layer preserves the intellectual branching history.

**Status:** CANDIDATE / METHOD INSIGHT

### RM-002 — Model decomposition and sharding are first-class research objects

For a real large model, the unit used by SimiGo does not necessarily have to equal the model's semantic unit.

Potential boundaries include:
- layer/block;
- tensor/tensor slice;
- execution-state-associated object;
- independently resident/migrated object;
- group of objects with tightly coupled access behavior.

The important future question is not “which unit is convenient to instrument?”, but:

> What object has an independently meaningful residency, migration, execution-state, and cost identity?

This may determine how a model should be layered and sharded for SimiGo.

**Status:** CANDIDATE / NOT AN RQ

### RM-003 — Semantic hierarchy may differ from residency hierarchy

A model can have a semantic hierarchy such as:

```
model → layer → block → attention / MLP → tensor
```

SimiGo may need a different operational hierarchy:

```
model
  → residency unit
      → migration unit
          → execution-state unit
```

These two hierarchies may overlap, but they should not be assumed identical.

**Architectural significance:** if true, SimiGo can define its mechanism around runtime behavior rather than hard-coding the upstream model's conceptual decomposition.

**Status:** CANDIDATE / ARCHITECTURE HYPOTHESIS

### RM-004 — Can SimiGo work without upstream semantic dependency?

A particularly important long-horizon question:

> If the current residency / execution-state theory is correct, does SimiGo actually need upstream semantic knowledge?

Distinguish:

```
semantic-assisted
    “this is layer X / attention / MLP / expert”

versus

semantic-dependent
    “the mechanism cannot work without knowing that”
```

The stronger architecture would derive essential information from observable runtime behavior where possible:

```
access
residency
migration
reuse
execution continuity
```

Upstream semantics may remain useful, but they would not be architecturally mandatory.

If this hypothesis survives future validation, it would materially affect portability, model-family coupling, abstraction boundaries, and runtime integration.

**Status:** CANDIDATE / NOT AN RQ

### RM-005 — Access pattern may determine the useful unit

A key principle emerging from the abstract research is:

> useful granularity is determined by access pattern, not by strategy freedom.

The broader architectural hypothesis is that access/co-access behavior may be a more fundamental basis for residency and sharding boundaries than semantic labels.

This is not yet established for a real Swift/MLX runtime.

**Status:** HISTORICAL PRINCIPLE → FUTURE VALIDATION CANDIDATE

### RM-006 — Abstract theory must be separated from runtime embodiment

There is a distinct chain between an abstract mechanism and a real runtime mechanism:

```
abstract mechanism
      ↓
runtime representation
      ↓
runtime-observable state
      ↓
controllable mechanism
      ↓
measurable effect
```

A failure at one transition does not automatically invalidate the previous layer.

This prevents a common research error: treating “we can model it” and “the runtime exposes it in a controllable form” as the same claim.

**Status:** CANDIDATE / FUTURE RESEARCH DIRECTION

### RM-007 — “Unit discovery” precedes implementation choice

Before building a Swift/MLX implementation, the research should establish what the real counterpart of the abstract unit is.

Candidate real units may include:
- layer/block;
- tensor;
- tensor slice;
- allocator/memory region;
- execution-state-associated object;
- dynamically co-accessed group.

The unit should be selected because it has the relevant mechanism semantics, not because it gives the easiest instrumentation.

**Status:** CANDIDATE / PRE-DEFINITION

### RM-008 — Semantic independence is stronger than semantic availability

Upstream semantic information may be available and useful without being architecturally necessary.

The meaningful architectural distinction is:

```
semantic-assisted
        vs.
semantic-dependent
```

This distinction should remain visible in future architecture discussions.

**Status:** CANDIDATE / ARCHITECTURE HYPOTHESIS

### RM-009 — “题外话” can be an architecture-origin event

A casual discussion should normally disappear.

It should enter this memory layer only when it:
- changes a system boundary;
- reveals a hidden variable;
- proposes a fundamentally different decomposition;
- explains a possible dead end;
- creates a durable architecture hypothesis.

Thus this file is intentionally **curated**, not a transcript archive.

**Status:** PROCESS PRINCIPLE

### RM-010 — GitHub as an asynchronous multi-agent research bus

A useful architecture idea emerged from discussion between the local Agent and ChatGPT:

> GitHub can serve as a shared, versioned research dialogue bus between agents, rather than merely as a source-code repository.

The intended separation is:

```
Local Agent
  runtime / filesystem / Swift / MLX / experiments
        ↓
   Git commit / push
        ↓
GitHub research dialogue
        ↓
ChatGPT Agent
  research decomposition / review / boundary challenge
        ↓
   Git commit / push
        ↓
Local Agent
```

The important design principle is **not** to turn GitHub into an unstructured chat transcript. The dialogue should remain provenance-bearing and subordinate to project state:

```
dialogue
   ↓
review / decision
   ↓
explicit registration
   ↓
RESEARCH_STATE / endpoint
```

In particular:

- dialogue must never silently become project state;
- an Agent's proposal must not automatically become an RQ;
- a review must be distinguishable from a registered decision;
- Git history provides provenance, ordering, and recoverability;
- the shared bus can reduce manual copy/paste between local Agent and ChatGPT;
- the two Agents can retain different capability boundaries while collaborating through the same research tree.

Potential future layout:

```
docs/research_bus/
├── INDEX.md
├── inbox/
├── dialogue/
├── decisions/
└── archive/
```

This is an **architecture hypothesis / workflow idea only**. It does not authorize creation of the bus, creation of branches, runtime changes, or any research experiment. A future implementation should be justified independently and should preserve the existing distinction between conversation, decision, and authoritative state.

**Origin:** 2026-09-22 brainstorming between project owner, local Agent, and ChatGPT.

**Status:** CANDIDATE / ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-018 — Compute-once / multiple-futures is the conceptual origin of Execution State

The central Architecture 2.0 insight was not simply “make long-context prefill faster”.

The stronger objective was:

> **Compute once, multiple futures.**

An expensive long-context computation should become a reusable, branchable, recoverable state from which multiple continuations can be derived.

This is the conceptual reason Execution State became a research object above raw KV storage. The durable distinction is:

```
one expensive computation
        ↓
reusable execution state
        ↓
fork / branch / continue / restore
        ↓
multiple futures
```

The idea predates the formal Track B evidence chain and should be treated as an architectural origin, not as evidence that the full runtime mechanism exists.

**Provenance:** curated from Architecture 2.0 session reconstruction, 2026-09-22; see `docs/07-history/ARCHITECTURE_2.0_SESSION_KNOWLEDGE_20260922.md`.

**Forbidden inference:** RM-018 does not prove that an equivalent mechanism is exposed by current Swift/MLX runtime APIs.

**Status:** DURABLE ARCHITECTURE ORIGIN / HYPOTHESIS

### RM-019 — Execution State is a semantic layer above raw KV storage

The early 2.0 reasoning deliberately separated:

```
KV bytes / storage representation
        ≠
execution identity + continuation semantics
```

Existing mechanisms such as checkpoint/restore, prefix reuse, and chunked prefill can manipulate state without necessarily exposing a first-class forkable execution identity.

Therefore future research should not use “we can copy or serialize the state” as a substitute for the stronger Execution State question.

**Provenance:** Architecture 2.0 session reconstruction, 2026-09-22.

**Forbidden inference:** this is not a claim that KV storage mechanisms are insufficient for every practical workload; it defines the stronger research abstraction being investigated.

**Status:** DURABLE CONCEPTUAL BOUNDARY

### RM-020 — Deduplicate before inventing

Architecture 2.0 deliberately moved upward in abstraction after comparing candidate work against existing open-source mechanisms.

The durable research rule is:

> Before treating a mechanism as a new SimiGo research contribution, establish whether the relevant lower layer is already solved or supplied upstream.

The intended boundary was approximately:

```
existing KV / attention / distributed primitives
        ↓
reuse rather than duplicate
        ↓
SimiGo research space
Execution State / residency / policy / planner
```

This is a research-efficiency principle, not a claim that upstream mechanisms are complete or optimal.

**Provenance:** Architecture 2.0 session reconstruction, 2026-09-22.

**Status:** DURABLE METHOD INSIGHT

### RM-021 — Architecture decomposition must respect physical resource boundaries

The early “split one large GPU computation into several application tasks” idea was retained as a useful negative lesson.

Creating more application tasks on a saturated single GPU does not by itself create additional hardware execution resources. Consequently, a decomposition proposal must identify the actual resource boundary it exploits:

- kernel-level decomposition → hardware execution / bandwidth question;
- multi-device decomposition → additional device resources;
- application-level splitting on the same saturated device → not automatically a new parallelism mechanism.

**Provenance:** Architecture 2.0 session reconstruction, 2026-09-22.

**Forbidden inference:** this does not prove every application-level decomposition is useless; it rejects the premise that task multiplication alone creates free parallel hardware.

**Status:** DURABLE METHOD / NEGATIVE KNOWLEDGE

### RM-022 — Mechanism existence must precede implementation authority

A recurring Architecture 2.0 correction was that an appealing implementation should not silently become a research commitment.

The intended order is:

```
mechanism hypothesis
        ↓
independence
        ↓
estimand / existence criterion
        ↓
discriminating observation
        ↓
evidence
        ↓
decision
        ↓
implementation authority
```

This is stronger than merely “do experiments before coding”: it protects the research program from turning an unverified architectural hypothesis into an implementation specification.

**Provenance:** Architecture 2.0 methodological evolution, curated 2026-09-22.

**Status:** DURABLE GOVERNANCE / METHOD INSIGHT

### RM-023 — The research object can move upward when lower-layer mechanisms are already available

The 2.0 discussions repeatedly shifted the question upward:

```
storage optimization
      ↓
execution-state semantics
      ↓
residency / observable boundaries
      ↓
runtime mechanism
```

This upward movement is not scope creep by itself. It can be the correct response when lower layers are already available and the unresolved systems question lies at a higher abstraction boundary.

**Provenance:** Architecture 2.0 session reconstruction, 2026-09-22.

**Status:** DURABLE RESEARCH-DIRECTION INSIGHT

### RM-024 — Execution State should ideally be semantically light

A long-horizon Architecture 2.0 hypothesis is that the core Execution State mechanism should not require upstream model semantics to function. Semantic metadata may assist optimization, but the mechanism should ideally derive essential control from observable runtime behavior such as access, co-access, residency, migration, reuse, and continuation.

**Provenance:** Architecture 2.0 future-mechanism discussion, curated 2026-09-22.

**Forbidden inference:** semantic-independent runtime control has not been demonstrated in current Swift/MLX.

**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-025 — Operational sharding unit may differ from model semantic unit

Future SimiGo sharding should not assume layer/block/tensor is automatically the correct unit. A candidate unit should have meaningful access, residency, migration, continuation, and cost identity. Unit discovery therefore precedes sharding implementation.

**Provenance:** Architecture 2.0 model-decomposition discussion, curated 2026-09-22.

**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-026 — Physical residency should be separated from logical intelligence state

A long-term mechanism candidate is to let the logical model / Execution State exceed the simultaneously resident physical representation, with execution-aware materialization, migration, eviction, and restoration. The target is not ordinary swap; it is preservation of execution identity and useful capability while minimizing the active physical working set.

**Provenance:** Architecture 2.0 future-mechanism discussion, curated 2026-09-22.

**Forbidden inference:** this does not establish that arbitrary model slices can currently be made non-resident and resumed safely or efficiently.

**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-027 — Execution State can be the bridge between sharding and residency

A stronger future architecture would treat Execution State as the logical object that survives physical movement. Thus load/unload is not sufficient: a unit should remain semantically associated with an ongoing execution while its physical residency changes.

**Provenance:** Architecture 2.0 future-mechanism discussion, curated 2026-09-22.

**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-028 — “Intelligence virtualization” is a candidate long-horizon direction

The combined hypothesis is: logical model / Execution State → operational units → residency manager → physical-memory working set → compute/continue. The aim is to make the logical amount of usable model intelligence potentially exceed the simultaneously resident physical representation, subject to correctness and migration-cost constraints.

This is a conceptual direction, not a named implementation architecture.

**Provenance:** Architecture 2.0 future-mechanism discussion, curated 2026-09-22.

**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ


### RM-029 — Intelligence is not identical to its physical carrier

A long-horizon abstraction separates:

model semantics ≠ logical executable state ≠ physical resident representation.

Physical memory is a temporary computational carrier, not intelligence itself. This distinction allows future research to ask what must be resident for a given execution frontier rather than treating the entire logical model as permanently resident.

**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Forbidden inference:** this does not prove arbitrary model state can be non-resident while preserving execution.
**Status:** DURABLE ARCHITECTURE HYPOTHESIS

### RM-030 — Memory Manager may need to become Execution Manager

A future runtime may need to manage not only bytes and ownership, but execution state, residency, migration, reuse, continuation, and lifecycle.

The conceptual shift is: memory management → execution-aware resource management.

The significance is a possible change in the control boundary, not a requirement to create a class named ExecutionManager.

**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-031 — Residency is a state, not merely an operation

load/unload is too weak as a long-horizon abstraction. An execution unit may be non-resident, materializing, resident, shared/partial, migrating, evicting, or recoverable while retaining logical identity.

Therefore residency may need state-machine semantics rather than isolated memory operations.

**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-032 — Residency should ideally be predictive

A stronger future mechanism is: execution frontier → future access/co-access estimate → working-set prediction → residency planning → materialize/migrate/evict.

The objective is to prepare physical residency for upcoming execution rather than reacting only after memory pressure occurs.

**Forbidden inference:** prediction quality, instrumentation cost, and migration economics remain unvalidated.
**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-033 — Planner may unify Execution State, Residency, and Compute

A long-horizon Architecture 2.0 architecture may place a Planner above three coupled concerns: Execution State, Residency/Memory, and Compute.

The Planner would reason about what execution units are needed, what should be resident, what can be reused/forked, and what computation should occur or be deferred.

**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Forbidden inference:** this is not authorization for the current Runtime2 skeleton to implement a Planner.
**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-034 — Runtime Sharding can be behavior-derived

Traditional sharding often starts from deployment-time semantic structure. A future runtime may instead derive operational groups from access/co-access behavior: access graph → co-access groups → operational units → dynamic residency/migration groups.

Thus sharding may be a runtime consequence of execution behavior rather than only a static model-deployment decision.

**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-035 — Execution-State Sharding may be more fundamental than Model Sharding

The object worth independently managing may be a decomposable part of Execution State rather than a model tensor or layer.

Candidate boundaries include continuation, access, residency, migration, sharing/COW, and recomputation dependencies.

This extends the earlier unit-discovery principle from model structure to execution structure.

**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-036 — A computation result can be a reusable execution asset

An expensive computation can be treated as producing an asset with a lifecycle: Create → Reuse → Fork → Continue → Migrate → Materialize → Evict → Restore → Discard.

This reframes execution state from passive cache data into a managed resource whose future value can be preserved or discarded.

**Forbidden inference:** Track B only establishes a bounded tested lifecycle; it does not validate every operation in this long-horizon chain for production runtimes.
**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Status:** FUTURE ARCHITECTURE HYPOTHESIS

### RM-037 — Fork is one lifecycle operation, not the final abstraction

The durable abstraction should not terminate at state → fork. A reusable Execution State may need create, continue, fork, share, migrate, materialize, evict, restore, and discard semantics.

The deeper research question is lifecycle preservation of identity, continuation, mobility, and resource manageability.

**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-038 — Optimize for minimum sufficient working set, not minimum memory

The long-horizon target is not simply min(memory), but a working set sufficient for correctness and useful execution while accounting for latency, migration, recomputation, safety, and concurrency costs.

Conceptually: minimum sufficient working set.

This turns residency from a memory-saving trick into an execution-planning problem.

**Provenance:** Architecture 2.0 Long-Horizon Vision, 2026-09-22.
**Status:** FUTURE ARCHITECTURE HYPOTHESIS / NOT AN RQ

### RM-039 — The research object must not be defined by the current upstream API

The absence of a concept from a current MLX/Swift API does not establish that the concept does not exist at the system level.

The intended order remains: theoretical object → runtime-observable boundary → existence criterion → independent observation → implementation path.

This prevents current API boundaries from silently becoming the definition of the research object.

**Provenance:** Architecture 2.0 Long-Horizon Vision and prior source/runtime boundary work, 2026-09-22.
**Status:** DURABLE RESEARCH-METHOD INSIGHT
### RM-040 — Experiments are local tests of higher-level ideas

A concrete experiment should be understood as a bounded observation generated by a higher-level structural idea or research question.

The durable relationship is:

```
idea / structure
      ↓
testable question
      ↓
experiment
      ↓
local evidence
      ↓
update to the parent understanding
```

An experiment result is therefore not identical to the idea it tests, and a failed implementation path does not automatically invalidate the parent conceptual object.

**Provenance:** Architecture 2.0 / SimiGo-Lab methodology discussion, 2026-09-22; formalized in `docs/00-governance/IDEA_TO_EXPERIMENT_CONTINUITY_MODEL_20260922.md`.

**Status:** DURABLE RESEARCH-METHOD INSIGHT

### RM-041 — The archive must preserve the idea–experiment linkage

Remembering experiment names and results is insufficient. Each important experiment should be recoverable as an answer to:

- which durable idea motivated it;
- which bounded question it tested;
- what observation could distinguish the claim;
- what the result changed;
- what the result did not establish.

This linkage is the continuity mechanism between intellectual history and empirical history.

**Provenance:** SimiGo-Lab archive design discussion, 2026-09-22.

**Status:** DURABLE ARCHIVE PRINCIPLE

### RM-042 — Evidence updates ideas locally, not globally

Evidence should update only the structural claim and scope that it actually observes.

The intended relationship is bidirectional:

```
idea → question → experiment → evidence
                         ↓
                 local model update
```

A positive result does not validate every consequence of the parent idea; a negative result does not automatically erase the parent concept. The archive must preserve scope, branch, and forbidden inference.

**Provenance:** SimiGo-Lab methodology discussion, 2026-09-22.

**Status:** DURABLE RESEARCH-METHOD INSIGHT

### RM-043 — Agent continuity depends on the intellectual tree, not only the experiment ledger

A new Agent should be able to reconstruct not merely “what was tested”, but:

```
why it was tested
what idea it belonged to
which branch it represented
what was learned
what remains hypothetical
what is closed
what may legally happen next
```

Therefore `RESEARCH_MEMORY`, governance registers, evidence/decision records, and `RESEARCH_STATE` form a connected memory system rather than independent document collections.

**Provenance:** Multi-Agent memory and archive design discussion, 2026-09-22.

**Status:** DURABLE MULTI-AGENT MEMORY PRINCIPLE

## 3. Promotion rule

A memory item does not change project state.

If it later becomes important enough to study:

```
Memory ID
   ↓
Definition document
   ↓
RQ ID
   ↓
Evidence
   ↓
Endpoint / Closure
```

Never silently convert:
- hypothesis → fact;
- discussion → RQ;
- registered prediction → result;
- historical insight → current task.

## 4. Authority boundary

Current research state is determined by:

1. `docs/RESEARCH_STATE.md`
2. endpoint / closure documents
3. experiment ledgers and evidence
4. Git history

This file answers a different question:

> **What important ideas have emerged that may explain or shape the future architecture?**

It may inform future research-question definition, but it cannot open a research branch by itself.

## 5. Future structure

If this layer becomes large, split it into:

```
docs/research_memory/
├── INDEX.md
├── insights/
├── forks/
├── architecture_hypotheses/
└── dead_ends/
```

Stable RM IDs must survive any split so future Agents can reconstruct the intellectual tree.


### RM-044 — Architecture 2.0 should study computational-architecture regularity, not model-content regularity

A key direction correction on 2026-09-22:

> Architecture 2.0 should study the stable regularities of a large model as a computational system, not attempt to enumerate the regularities of the knowledge, rules, semantics, probabilities, or compressed content carried by the model.

The latter can approach an effectively unbounded study of machine knowledge/intelligence formation. It is a different research tree.

The Architecture 2.0 mainline is instead:

`expensive computation → reusable Execution State → continuation / fork / lifecycle → representation transition → runtime carrying / reuse → residency / loading / layering / migration`

This correction explains why the earlier “all boundaries → universal object → universal unit” branch should be pruned rather than extended.

**Status:** DURABLE ARCHITECTURE-DIRECTION INSIGHT

### RM-045 — Execution State is the current architecture abstraction boundary

Execution State is valuable because it can abstract continuation-relevant computation without requiring Runtime to understand the model's entire knowledge content.

The intended separation is:

`model implementation` → how to compute  
`Execution State` → what continuation-relevant state exists  
`runtime` → how to carry, reuse, load, reside, and migrate that state

“General Execution State” means shared execution semantics, not identical internal state layout across model families.

**Status:** DURABLE ARCHITECTURE HYPOTHESIS / CORE DIRECTION

### RM-046 — Research maturity is accumulation of invariants, not accumulation of branches

The Architecture 2.0 research path is better represented as local continuation with fork, failure, rollback, and renewed development:

`a→b→c→d`  
`a→b→c→e→f`  
`a→b→c→d→f→g`

The mature result is not that every branch survives. It is that repeated development leaves more stable, reusable structure behind while uncertain branches are pruned.

This is a durable research-history interpretation, not an empirical finding about model behavior.

**Status:** DURABLE RESEARCH-METHOD INSIGHT

### RM-047 — Continuation Requirement 应定义为未来延续的区分能力，而非物理保存对象

P4-A 对“Continuation Requirement”进行对抗性收缩后，当前更稳的语义候选是：在限定计算环境与 admissible continuation 范围内，当前状态为了保持未来延续语义而必须保留的区分信息关系。

候选关系可表示为 Behavior(s, c)；若两个状态对研究范围内所有 continuation probes 不可区分，则暂记为 s1 ≈C s2；存在 probe 使行为可区分，则在该范围内不等价。

重要边界：语义必要性 ≠ 物理保存；语义必要性 ≠ 重算成本；语义必要性 ≠ 资源价值；单次输出相同 ≠ continuation-equivalent。有限 probe 只能支持有限范围结论，不能推出全空间等价。

Status: P4-A CONCEPTUAL CANDIDATE / NOT AN RQ / NO EXPERIMENT AUTHORIZATION

Provenance: Architecture 2.0 P4-A adversarial research, 2026-09-22.
### RM-048 — P4-A 不需要 Universal Probe Set，而需要 scope-bounded sufficient probes

有限 continuation probes 无法证明全空间 continuation equivalence；随机 probe 也可能遗漏低频但关键的分叉。因此 P4-A 应采用 scope-bounded、adversarial、sufficient probe set，而非 Universal Probe Set。

当前三级证伪结构：存在性 → 稳定性 → 区分度。只有架构差异在限定 continuation scope 内产生可重复、可区分的行为差异，才有资格进入更高层 State characterization。

进一步收缩为：Architecture Feature → Computation Dependency → Future-Continuation Distinguishability → Observable Behavior。Execution State 是解释这一关系的中间概念，不要求首先以物理对象直接被观察。

Status: P4-A CONCEPTUAL CANDIDATE / NOT AN RQ / NO EXPERIMENT AUTHORIZATION

Provenance: Architecture 2.0 P4-A probe-set adversarial research, 2026-09-22.

### RM-049 — Behavior Difference 不足以证明 Execution State Difference

P4-A 当前不得从不同输出直接反推 State。行为应视为受 State、Continuation 与受控 Environment 共同影响；single-probe equality 不能证明 State equality，single-output difference 也不能证明 State difference。

Execution State 获得研究资格至少需要更强的结构：在受控 continuation environment 中，存在可干预的 continuation-relevant information，改变该信息关系能够稳定改变一类未来 continuation behavior，并可与其他计算因素区分。

边界保持：
semantic continuation information ≠ physical representation ≠ physical resource；
semantic existence ≠ physical persistence；
physical persistence ≠ semantic necessity。

若只能观察 Architecture A/B 的输出差异而无法建立 continuation scope、重复性、反事实干预及跨-probe稳定性，则不得升格为 Execution State Difference。

Status: P4-A CONCEPTUAL CANDIDATE / NOT AN RQ / NO EXPERIMENT AUTHORIZATION


### RM-050 — P4-A 不再重复证明 Track B 的 State 可操作性

Track B 已在限定范围内验证 Execution State 的 fork / continue / reattach / discard 生命周期。因此 P4-A 不应重新研究 State existence、forkability 或 continuation correctness。

P4-A 若继续，其新增研究对象必须是：**在明确计算上下文下，由计算架构差异诱导的 continuation dependency / State characteristic。**

边界：
Track B = State lifecycle semantics；
P4-A = Architecture-induced State dependency。

错误入口已关闭：通过重新操作 State 来“发现 State”。

新的关键待证伪问题：Continuation Dependency 是否只是 computation dependency / computation graph dependency 的另一种命名？若不能找到最小不可约差异，P4-A 应关闭或并回已有计算架构研究。

Status: P4-A CONCEPTUAL CANDIDATE / NOT AN RQ / NO EXPERIMENT AUTHORIZATION


### RM-051 — Continuation Dependency 的最小不可约候选

P4-A 直接攻击了“Continuation Dependency 是否只是 Computation Dependency 的换名”。

若完整未来计算图已经固定，二者可以退化为同一关系；若 continuation 只有单一路径、普通程序状态已完全表达该关系，Continuation Dependency 不具独立性。

当前唯一保留下来的最小候选是：在未来 continuation 尚未完全确定、但允许 continuation domain 可以被明确描述时，研究“为支持一组可能未来延续而必须保持的区分关系”。其潜在独立性来自 future-not-fully-fixed，而非来自“State”这个名字。

LLM 并不因此获得特殊地位；真正可能有价值的是跨架构比较共同 continuation semantics，同时允许不同物理 representation。

若后续不能证明该关系产生普通 computation dependency / program state 之外的新解释力，P4-A 应关闭或并回普通计算架构研究。

Status: P4-A CONCEPTUAL CANDIDATE / NOT AN RQ / NO EXPERIMENT AUTHORIZATION


### RM-052 — Future Not Fully Fixed 不能单独证明 Continuation Dependency 独立性

P4-A 最后攻击“未来尚未确定”这一独立性依据。显式分支状态机、外部输入、概率转移、LLM token continuation 都可由普通 State + Transition Relation 表达，因此 future-not-fixed、多分支、概率未来均不足以证明新的基础计算抽象。

因此 Execution State 不应再主张为新的基础计算对象。保留的合理形式是：**跨计算架构的共同语义投影候选**。其价值不是理论新颖性，而是是否能跨物理 representation 比较 lifecycle/resource properties，并降低 Runtime 对具体模型实现的耦合。

最终生死条件：共同语义维度是否自然出现、是否非人工硬编码、是否具有可验证的信息价值、是否能解释/预测 Runtime resource behavior；若不能，Execution State 主线应关闭或重新定义。

Status: P4-A CONCEPTUAL CANDIDATE / NOT AN RQ / NO EXPERIMENT AUTHORIZATION


### RM-053 — Execution State 的候选价值转向 task-relative information/cost，而非本体论存在

“不同架构自然收敛到共同语义维度”存在研究者先验污染，只能作为辅助证据。更强的候选判据是：在预先定义的 Runtime resource-decision task 下，semantic projection 相对于 architecture-specific state 是否保留足够决策信息，同时显著降低 instrumentation / adaptation cost。

注意：projection 预测性能接近专用 state 不等于全局充分统计量；最多证明 task/workload scope 内的 task-sufficiency。资源有限提供“有限可描述性”的研究动机，但不能推出低维、稳定、跨架构 projection 必然存在。低维 projection、task-specific representation、high-dimensional dependence 都必须允许成为结果。

当前候选身份：
Execution State = 面向继续计算与 Runtime resource decisions 的、可被压缩/投影/比较的计算状态描述层候选，而非 universal state object。

下一关键问题：低复杂度/低维到底如何定义，且 complexity notion 是否与 Runtime decision utility 真正相关。

Status: P4-A CONCEPTUAL CANDIDATE / NOT AN RQ / NO EXPERIMENT AUTHORIZATION


### RM-054 — Rate-Distortion 只能在预固定 Description Language 下成立

P4-A 将“低复杂度”候选进一步收缩为固定 Runtime-side description language 下的 code length（rate），并以 Runtime resource-decision loss 作为 distortion 的 task-relative rate-distortion 候选。Description language 必须先于观察架构-specific projection 而固定，否则复杂度定义可能被 projection 反向优化。

但固定语言本身仍需继续攻击：opaque primitive 可能把复杂度藏进 decoder / ontology / external knowledge；language expressivity 会改变码长；encoder 可能利用 architecture-specific prior；短码可能只是语义搬运而非 decision-relevant information compression。

同时确认 projection utility 受 deployment regime 影响：architecture adaptation cost 近似 O(A)，per-decision instrumentation/inference/translation cost 近似 O(D)，因此价值依赖 A:D。若最终 B（局部成立），应把 task × architecture family × workload × resource regime 的 applicability boundary 作为主要发现，而不是只报告局部成立。

当前下一攻击固定为 Description Language Attack；仍处 STEP①，不创建 RQ、不授权实验。

Status: P4-A CONCEPTUAL CANDIDATE / NOT AN RQ / NO EXPERIMENT AUTHORIZATION

Provenance: Architecture 2.0 P4-A description-language / rate-distortion attack, 2026-09-22.


### RM-055 — Analytic Encodability 必须先于 Rate-Distortion 独立过门

P4-A 在固定 Description Language、Two-part MDL / 成本会计与 L₀ byte-dump 基线之后，发现新的关键混淆变量：Encoder_X 从哪里获得其规则。

若 Encoder_X 的构造依赖目标 Runtime resource behavior、profiling、decision labels 或其他目标数据，则所谓跨架构 projection 可能只是把信息获取从 O(D) 决策侧搬到 O(A) 架构适配侧。此时即使后续 rate-distortion 结果成立，也无法区分 projection 的信息价值与 codec 构造阶段的数据污染。

因此新增独立概念门：**Analytic Encodability**。其候选定义为：Encoder_X 的构造规则可由 architecture / computation-structure description 与允许的先验知识确定，而不依赖目标 Runtime resource-decision outcome 或 profiling data。

允许架构结构、计算依赖、可由架构推出的 continuation-relevant properties；禁止用目标资源行为、迁移成本、驻留收益、reuse/cache outcome、memory-pressure trace、decision label 等反向选择或拟合编码字段。

该门不要求 encoder 没有 architecture-specific knowledge；恰恰允许 `Architecture X → Encoder_X`。约束的是知识来源：architecture knowledge 可进入 Encoder，target resource outcome 不得反向进入 Encoder。

若 analytic encodability 失败，projection 仍可能作为 data-assisted engineering codec 有价值，但不能把该结果直接解释为跨架构 information-acquisition saving。若通过，才有资格继续检验 fixed language 下的 rate/distortion 与 information value。

Status: P4-A CONCEPTUAL CANDIDATE / NOT AN RQ / NO EXPERIMENT AUTHORIZATION

Provenance: Architecture 2.0 P4-A analytic encodability attack, 2026-09-22.


### RM-056 — Static Derivability、架构边界探针与 Decision-Loss Gate

P4-A 对 Analytic Encodability 进一步收缩为可机械审查的静态来源标准：一个从未运行过目标模型的 agent，应仅凭允许的静态架构/计算结构描述导出 Encoder_X。允许架构规格、声明式结构、计算语义、依赖/类型/shape 信息以及静态阅读源码；禁止执行后通过 trace、benchmark、memory behavior、migration/materialization behavior、decision labels 或 workload trace 发现/调整编码字段。核心约束是知识来源，而不是禁止 Architecture X → Encoder_X 的架构特异性。

隐藏 architecture-family prior 应通过未来的架构多样性采样暴露：熟悉家族、结构不同的已知家族，以及至少一个编码者既有经验之外的架构或 purpose-built variant。若只在熟悉家族成立、面对新结构需大量人工修改，则应视为 applicability boundary，而不是 universal validity。该探针属于未来 STEP②–⑨ 设计约束，当前不授权实验。

同时保留一个非二元候选：Architecture → analytic structural skeleton → minimal measured coefficients → projection → Runtime decision。状态结构字段可能较易静态解析，而 migration granularity、reconstruction order、reattach feasibility 等 transition/materialization 字段可能需要少量实测。若该模式成立，后续问题可从“是否完全 analytic”改写为“完成 analytic skeleton 所需的最小经验信息量”。成本层次保持 A_analytic + A_measurement 与 D_decision 分离。

为避免 STEP① 把研究对象与完整实验协议混为一体，正式区分 Definition Layer 与 Evaluation-Constraint Layer。L、frozen decoder、L₀、A:D regime、analytic provenance requirement 属于对象定义；two-part accounting 的具体执行、decoder-in-the-loop、六项攻击目标的 operationalization、novel-architecture sampling、rate/distortion estimand、measurement budget/threshold 属于未来 STEP④–⑨ 的设计约束，当前仅保留 provenance。

下一概念门固定为 **Decision-Loss Well-Definedness Attack**：在不引入 Runtime implementation 的前提下，Decision Loss D 是否能够被定义为非任意且足以区分 projection 的量。若可由形式化 decision model 给出，则继续定义；若必须引入 decision process / simulation / executable harness，则必须显式开启 Harness Authorization Gate，禁止因 D 难定义而隐式进入实现。

**Status:** P4-A CONCEPTUAL CANDIDATE / NOT AN RQ / NO EXPERIMENT AUTHORIZATION

**Provenance:** Architecture 2.0 P4-A static derivability / analytic skeleton / Decision-Loss Gate discussion, 2026-09-22.


### RM-057 — STEP① 契约接受，正式进入 STEP②

2026-09-22，研究者正式接受 P4-A STEP① candidate contract，并授权进入 STEP② Research Question。

STEP① 契约已形成以下闭环：固定 Description Language、frozen decoder、L₀ byte-dump reference、O(A)/O(D) 成本分账、Static Derivability、analytic skeleton + minimal measured coefficients 候选，以及基于 Bayesian decision problem / Blackwell ordering 的 Decision Loss 定义。Decision problem 采用 `(𝓐, 𝓒, Π_W)`，projection 的风险以 Bayes risk 与 full-information/oracle reference 的 excess cost 表示；参数族内的 dominance boundary 可作为 applicability boundary。

这一步只是**研究治理状态转换**，不是跨架构 projection 存在、低码率、低维度或 Runtime 价值已经成立的证据。

STEP② 的唯一新增权限是：正式定义、压缩和对抗 Research Question。不得因进入 STEP② 自动授权 Runtime、harness、profiling、data collection 或 measurement；STEP⑨ harness 仍需等待注册 RQ 与后续设计门。

如果未来证明预定义 decision-problem family 无法进行解析评估，才可开启 definition-stage executable artifact 的独立 mini-gate；当前 Bayesian / Blackwell / caching formal path 不触发该出口。

**Status:** STEP② OPEN / RQ DEFINITION IN PROGRESS / RQ ID NOT YET ASSIGNED / NO EXPERIMENT AUTHORIZATION

**Provenance:** Architecture 2.0 P4-A Decision-Loss Well-Definedness discussion and explicit human acceptance, 2026-09-22.


### RM-058 — STEP② 第一轮 RQ 压缩与 Rate–Decision-Loss Frontier 攻击

2026-09-22，P4-A 正式进入 STEP② 后，首个 RQ candidate 被压缩为：在固定 Description Language 与预定义 Decision Problem Family 下，由架构静态信息导出的 State Projection，是否能以有限描述成本保持所需决策信息。

STEP② 首轮拆出四个隐藏命题：Analytic、Representational、Informational、Economic；其中 Runtime adoption value 不应进入核心 RQ。信息充分性若不受 Rate 约束会被 L₀/完整 State 平凡满足，因此进一步压缩为 Rate–Decision-Loss frontier 候选：D*(R)=min over P with Rate(P)≤R of D(P)。

当前 core candidate：固定 Description Language 与 Decision Problem Family 下，State representation 的描述成本与 Runtime Decision Loss 之间是否存在可重复、可区分的 frontier；cross-architecture 共性及其边界作为后续 extension，而非前提。

首个 STEP② adversarial attack 已固定：frontier 是否只是研究者选择的 Description Language L 与 Decision Problem Family 所人为定义出来的数学对象？需要分别攻击 Rate 对语言选择的依赖，以及 D 对 decision family / workload prior / cost model 的依赖。当前不假设 robustness 已成立。

**Status:** STEP② OPEN / RQ CANDIDATE UNDER ATTACK / RQ NOT REGISTERED / NO EXPERIMENT AUTHORIZATION


### RM-059 — P4-A STEP② accepted, STEP③ opened

2026-09-22，人类研究者明确授权 P4-A 从 STEP② 进入 STEP③。STEP② 的前置条件与 RQ definition gate 被视为通过；此处是治理转移，不是经验性证据，也不授权实验。

STEP② 携带进入 STEP③ 的对象是 Achievable Static Frontier：由预声明的静态派生策略族 S 实际可达、带 certificate 的 encoder 所形成的 frontier，而非无限 encoder 家族的理想 infimum。L、D、S 均显式化；D 层非退化性已由属性隔离任务证明；per-(L,X) expressibility 属于下游 applicability boundary。

STEP③ 的核心攻击转向 independence：对象是否只是已声明 decision problem + compression rate 的重述；L/D/S 是构成性输入还是隐藏旋钮；跨架构变化是否仍保持对象意义；是否与已 CLOSED 的 Track B 执行状态生命周期研究重复；是否依赖特定 Runtime / MLX-LM / 物理状态布局。

**Status:** STEP③ OPEN / INDEPENDENCE ANALYSIS IN PROGRESS / NO EXPERIMENT AUTHORIZATION
