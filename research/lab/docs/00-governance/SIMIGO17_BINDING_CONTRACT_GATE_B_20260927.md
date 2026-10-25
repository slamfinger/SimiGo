# Gate B — Execution↔Representation Binding Contract — Definition

**Date**: 2026-09-27 · **Status**: PASSED (reviewer: B-1/B-2 PASS,
B-3 PASS with semantic tightening; final invariant set §3, rules §4;
this document is FINAL for Gate B)
**First principle (reviewer)**: **Binding is a RELATION, not an
attribute of RepresentationRef.** `RepresentationRef { executionID }` is
forbidden; one Representation bound by multiple Execution States must be
type-level legal — this is the structural basis FORK-3 stands on.

---

## 1. The relation record

```text
ExecutionRepresentationBinding (one relation row, append-only):
  execution            ExecutionID            "我是谁"
  runtimeAddress       AgentExecutionKey      "在哪里"（本次物化/绑定的运行时寻址）
  ref                  RepresentationRef      "绑定了哪份表示"
  boundPositionAtBind  Int                    == ref.boundLength（R-I5）
  generation           Int                    绑定代次（per-Execution 单调递增；
                                               是 Binding 关系版本号——不是 token
                                               position、不是 Representation 版本、
                                               不是 Pool LRU 版本、不是全局事务号）
  state                active | superseded | detached
  boundAt / notes      metadata（永不参与身份）
```

当前解析规则（deterministic）：一个 Execution 的 active binding = 其
generation 最大的 non-detached 记录。历史记录保留（append-only 审计，
与 token ledger 的增长点/标记同构）。

## 2. Semantics

```text
 Binding 回答：该 Execution 最后一次物化/绑定的 Representation 是哪份、
              覆盖到哪个边界。
 它不回答：  Execution 现在算到了哪里——那是 Execution State position
              的职责。二者允许合法偏离（reviewer 例：bind @2048，
              currentPosition 3072 = 已从物化基继续计算）。
 新 Binding 诞生于：bootstrap 物化、池 admission、checkpoint restore、
              （FORK-3）fork point 绑定。
 重绑定发生于：续算后导出新边界、rewind（rewind 必须产生指向新目标的
              新 Binding——禁止陈旧绑定静默延续）。
```

## 3. Final invariant set (reviewer wording, 2026-09-27)

```text
B-I1  Binding is a relation, never a Ref property
B-I2  bind-time position consistency
      (Binding.boundPositionAtBind == Ref.boundLength)
B-I3  monotonic generation (per-Execution)
B-I4  append-only history
B-I5  cardinality: one Execution → ≤1 active Binding;
      one Ref → N active Executions
B-I6  lifecycle independence (Binding ≠ artifact ≠ live KV;
      artifact eviction → rematerialization-required mark,
      never Binding invalidation)
```

Plus three RULES (reviewer-added):

```text
B-R1  RuntimeAddress change increments Binding generation, but NEVER
      changes canonical ExecutionID. (K1 ≠ K2 still ⇒ ExecutionID A;
      this is the F2/F4 resolution: Execution Identity ≠ Runtime
      Address.)
B-R2  Current-Binding resolution is deterministic AND consistency is
      separate: same ExecutionID → at most one active Binding,
      selected by highest generation. max-generation is the RESOLUTION
      RULE; the consistency guarantee is B-I5's ≤1 (two concurrent
      actives = ILLEGAL STATE, not a selection tie).
B-R3  Generation is scoped per Execution — neither token position, nor
      Representation version, nor Pool LRU version, nor a global
      transaction/version ID.
```

Rewind semantics (B-2 PASS): the old record stays SUPERSEDED — a rewind
is still the same Execution State acquiring a new valid version of its
representation/position relation (gen 7 Ref X @ 4096 → rewind → gen 8
Ref Y @ 2048); superseded (not detached) matches markSuperseded.

## 4. What Binding deliberately does NOT do

```text
NOT a residency record        物理驻留仍是 pool/controller 的策略层
NOT a transcript              文本/消息内容仍属会话历史
NOT a position source         Execution position 属 Execution State
NOT PrefixPool's registry     Gate C 分离裁定不变：Pool=表示的
                              生命周期/发现/复用设施；Binding=
                              Execution↔表示的关系
```

## 5. Relation to what already exists

```text
today's ephemeral binding        = sessions-dict entry holds a
                                   materialized copy — unrecorded,
                                   unqueryable, dies with the process
Gate B makes it a first-class    = recorded relation, multi-bind legal,
                                   restart-decidable (disk sidecars +
                                   registry), auditable
oversized strict-ES sessions     = already hold handle+position; Gate B
                                   gives them the representation leg
daily ChatSession path           = Gate B rows created at bootstrap
                                   admit / turn export / restore
```

## 6. Review questions

1. generation 作用域：per-Execution 单调（v1 提议）还是全局时钟？
2. detached 的触发面：discard 之外，restore 到早于绑定边界时旧 Binding
   转 superseded 还是 detached？（v1 提议 superseded——与 token ledger
   的 markSuperseded 同构。）
3. AgentExecutionKey 变更（同 Execution 换运行时寻址）是否产生新
   generation？（v1 提议：是——绑定记录的是事实历史。）

---

## 7. Reviewer verdict — 2026-09-27 — PASS

B-1 generation scope (per-Execution) PASS · B-2 rewind=superseded PASS ·
B-3 address mutation PASS with the tightening (B-R1). Resolution
hardening adopted (B-R2: max-generation = resolution rule; B-I5 ≤1 =
consistency guarantee). rematerialization-required: kept OUT of Binding
state enums — it is artifact availability surfaced through the active
Binding (Binding stays active; Pool eviction ≠ Binding invalidation).
