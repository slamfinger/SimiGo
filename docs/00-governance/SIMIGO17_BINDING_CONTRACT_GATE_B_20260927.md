# Gate B — Execution↔Representation Binding Contract — Definition

**Date**: 2026-09-27 · **Status**: DEFINITION_DRAFT / AWAITING_REVIEW
(no implementation code — per the Gate-A ruling order)
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
  generation           Int                    绑定代次（同执行多次绑定单调递增）
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

## 3. Invariants

```text
B-I1  relation, not attribute   Ref 不携带执行身份；多执行绑定同一
                                Ref 在类型层合法（FORK-3 基础）
B-I2  bind-time consistency     boundPositionAtBind == ref.boundLength
                                （Gate A R-I5，仅约束绑定时刻）
B-I3  forward monotonicity      active 绑定期间 currentPosition ≥
                                boundPositionAtBind；任何 rewind ⇒
                                新 Binding（旧记录转 superseded）
B-I4  append-only               superseded/detached 记录保留；当前解析
                                确定性（最大 generation）
B-I5  cardinality               一个 Execution 至多一个 active Binding；
                                一个 Ref 可被多个 Execution 同时 active
                                绑定
B-I6  lifecycle independence    Binding 存续 ≠ Ref artifact 存续 ≠ 活 KV
                                存续。Ref artifact 被驱逐（Gate D）时
                                Binding 不消失——转 rematerialization
                                required（契约标记，绝非 LRU 隐含）；
                                Execution 有效性由重物化义务承接
```

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
