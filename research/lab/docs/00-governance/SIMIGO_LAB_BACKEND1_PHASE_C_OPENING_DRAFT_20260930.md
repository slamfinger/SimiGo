# BACKEND-1 Phase C Opening Draft — Backend Seam Architecture Audit

日期：2026-09-30  
状态：`PARTICIPANT PROPOSAL / AWAITING EXTERNAL REVIEW`  
被对照审阅的 opening：`SIMIGO18_BACKEND1_LLAMA_RESEARCH_OPENING_20260928.md`  
对齐基准（已登记）：Phase A boundary（45/45）+ Phase B boundary
`SIMIGO_LAB_PALACE1_PHASE_B_AUDIT_REGISTRATION_20260930.md`  
性质：participant proposal + 对照审阅，不是 repository registration

本草案不实现 Llama adapter，不选存储，不定义 persistence format，不做
performance benchmark claim。所有内容区分：

```text
observed code fact ≠ inferred architecture contract ≠ selected implementation
```

## 1. 对照审阅 — 2026-09-28 opening vs 已登记 Phase B boundary

| 09-28 opening 元素 | 对照已登记边界 | 处置 |
|---|---|---|
| 目标关系 `Execution → RepresentationRef → Llama-specific Representation` | Phase B 已裁定 `RepresentationRef` 是 P 层 locator/claim，不是语义层一跳；durable relation 是 separately typed binding relation | **修正**：目标关系改为 `Execution →(separately typed binding relation)→ backend-specific P payload` |
| 「保持 backend-neutral 的 Execution 抽象」 | Phase A/B：semantic continuity 属于 Execution Semantic Snapshot 契约；backend-neutrality 是契约边界属性，不要求 representation 通用化 | **保留并重述**：中立性锚在契约，不在 representation |
| 首轮代码审核 scope（ExecutionControlling / ExecutionPolicy / ChatSession+NativeMLX / NativeMLXPrefixPool / OversizedRuntime / model loading+identity / prefill+decode+cancellation+error / session persistence / HTTP entry points） | 与 D/R/P/O/T 词汇无冲突 | **保留**，逐项按 D/R/P/O/T 重分类（见 C1） |
| Q4「RepresentationRef 如何保持 backend-neutral」 | 前提已被 Phase B 修正：RepresentationRef 不是语义状态 | **改写**为 C4 representation contract（见下） |
| Q7「Llama 接入是否增加普通小规模 Execution 默认开销」 | 测量类开销归 RQ3（SEPARATELY SCOPED）；Phase C 禁 performance claim | **拆分**：结构性问题留 C7；测量归 RQ3 |
| 原则：先 seam 后 API；先代码证据后抽象；不提前重构稳定 MLX 路径；oversized/LAN/remote 只是验证场景 | 与 route redefinition §Phase C 一致 | **保留** |

09-28 opening 没有把 route redefinition 的目标问题列为第一问题，本次草案补上
（C8）。

## 2. Re-anchored research question

> 在已登记的 Execution Semantic Snapshot 边界内，当前 Lab runtime 的
> backend 接触面里哪些是 Execution 语义、哪些是 MLX 实现细节？最小
> backend seam 是什么，才能使 Execution State 在 backend / representation
> 变化后保持语义连续——而不把 Runtime Binding、Backend State 或
> Physical Representation 提升为 Durable Semantic State？

Llama 是验证 backend，不是新的 Execution State 定义。目标不是「接入
llama.cpp」本身。

## 3. Registered prior evidence inventory（只引用，不重跑、不吸收）

| 线 | 状态 | Phase C 可用性 |
|---|---|---|
| RQ1 Backend Conformance | `PASS_WITH_BOUNDARY / CLOSED-FOR-CURRENT-CONTRACT` | 可引用：三个 adapter（MLX prefix / oversized segmented / `LLAMAServerExecutionStateBackend`）通过同一 conformance battery；FBC-001 已修；live smoke `semanticIdentical+branchDiverged`。**边界**：仅 current contract，非 universal |
| RQ3 LLAMA hot path / isolation | `OPEN` | **SEPARATELY SCOPED**：hot-path A/B、cancellation isolation、并发、`BACKEND_EXECUTION_PATH_ISOLATED` 全部留在 RQ3，Phase C 不重跑、不下性能结论 |
| RQ2 跨架构 | `PARTIAL / NOT CLOSED` | 不动 |
| Phase A boundary audit | `PASS / REGISTERED` | D/R/P/O/T 分类基准 |
| Phase B minimal durable unit | `PASS / REGISTERED` | Execution Semantic Snapshot + recoverable set + 六条件 |

## 4. Proposed subquestions

### C1 — MLX-specific leakage
对 09-28 opening 的审核 scope 逐项分类：哪些接触面是 Execution 语义
（D 级：identity / lineage / position / continuation / lifecycle），哪些是
R（runtime binding / runtimeAddress）、P（prefix payload / model 权重）、
O（history / stats）、T（in-flight / cache 暖态）。输出 leakage 清单：
凡是把 MLX 类型体系带进 D 级语义的位置都是 leakage candidate。

### C2 — Minimal backend seam
从代码证据推断最小 seam：backend 必须向契约提供什么（create/fork/continue/
restore/discard 的 representation 侧能力），契约必须向 backend 隐藏什么。
只推断 seam 形状，不设计 API、不写协议签名。

### C3 — Capability requirements
cache / prefill / decode / snapshot / restore 的 backend 差异如何表达。
按 Phase B：capability 是 R/T 层元数据，不是 D 级字段；capability 缺失时
语义结果必须是显式降级（如 `rematerializationRequired`），不是静默换语义。

### C4 — Representation contract
`RepresentationRef` 保持 P 层；binding relation 保持 separately typed
（executionID / representation key / boundPositionAtBind / binding state /
relation generation）。per-backend payload 需要显式 content claim 与
validation policy（对应条件 3；当前无 universal content digest）。

### C5 — Synchronous / asynchronous boundary
哪些 seam 操作必须同步提交语义（fork/restore/discard 的 commit 点），
哪些可以异步（物理 derive、export、release）。对齐 Phase B crash-window
ordering：semantic commit 与 physical outcome 的先后已登记，Phase C 只分类
seam 侧哪些环节允许 async，不设计并发协议。

### C6 — Cancellation / failure propagation / resource release
seam 侧错误如何映射到已登记 fail-closed 结果（loud fail / 不绑定 /
`rematerializationRequired` / defer deletion）。cancellation 的语义边界
（token 边界、取消后 restore+replay 一致性）已有 RQ3/harness 证据，Phase C
只做 seam 侧分类，不重做测量。

### C7 — Default-path non-interference（结构性）
backend-neutral seam 是否强制改动稳定 MLX 默认路径、是否把额外 bookkeeping
塞进普通小规模 Execution 的结构里。**只答结构问题**（改不改、碰不碰），
不答快慢问题；测量归 RQ3。

### C8 — Cross-backend semantic continuity（目标验证问题）
Execution State 是否可以在 backend / representation 变化后保持语义连续：
同一 Execution Semantic Snapshot 的 recoverable set 在 MLX backend 与非 MLX
backend 之间迁移时，identity / lineage / position / continuation / lifecycle
语义保持，representation 侧按 B5 矩阵显式降级或 reattach。Phase C 以代码级
审计 + targeted tests 回答「契约是否支持」，不回答「生产是否可用」。

## 5. Inherited conditions（六条件及其 Phase C 读法）

```text
1. lineage tombstone closure — 跨 backend restore 仍须可解析 root/parent，
   至少 tombstone
2. transcript equivalence — llama 路径恢复仍以 nextInput 为 D；不得以
   transcript 推导替代，除非先过 bounded equivalence 计划
3. representation content claim — GGUF / llama prefix payload 须有显式
   per-backend content claim + validation policy 才可 durable reattach
4. binding separately typed — LLAMAServerPrefixPayload 绑定是 relation；
   runtimeAddress 是 R；llama slot / native cache 状态不是语义状态
5. crash-window classification — llama-server slot/cache 行为按已登记
   crash-window 规则分类；不设计 transaction protocol
6. concurrency / durable identity reservation — coordinator locking、
   discarded-binding guard、durable ID allocator 只在独立 engineering gate
   解决；Phase C 只登记 gap
```

## 6. Explicit non-goals

```text
❌ Llama adapter 实现 / 产品化（已存在的 LLAMAServerExecutionStateBackend
   只是 conformance 先证，不是产品路径，也不在本轮扩展）
❌ SQLite / KV / event log / remote 存储选型
❌ persistence file format
❌ performance benchmark claim（测量归 RQ3，SEPARATELY SCOPED）
❌ oversized 特殊语义（oversized 只是验证载荷）
❌ 吸收或重跑 RQ1 / RQ2 / RQ3 的已登记工作
❌ API / 协议签名设计（只推断 seam 形状）
```

## 7. Acceptance criteria

Phase C 审计完成的判据：

1. C1–C8 全部有代码级回答，逐条区分
   `observed code fact ≠ inferred contract ≠ selected implementation`。
2. C1 产出 leakage 清单；C2 产出最小 seam 推断；C3 产出 capability 分类；
   C4 产出 representation contract 推断；C5–C6 产出 sync/async 与错误分类；
   C7 产出 default-path 接触判定；C8 产出契约支持性结论与边界。
3. 全部证据基于 clean HEAD worktree；targeted tests 给出通过计数。
4. 审计不改变 D/R/P/O/T 已登记分类；任何 reclassification 请求显式列出并
   留给 external review。
5. 六条件逐条落在审计结论里，不允许无声跳过。

## 8. Gate sequence

```text
本草案（participant proposal）
  → external review（PASS / FAIL / RETURN FOR REVISION）
  → explicit human registration（激活 Phase C）
  → Phase C code-level seam audit（clean HEAD + targeted tests）
  → external review of audit
  → explicit human registration
  → 之后才可能讨论 adapter engineering gate（另行开启）
```
