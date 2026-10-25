# P5-2-ER: Execution State Dependency Closure External Review — Task Order

日期：2026-10-01  
状态：`TASK ORDER ISSUED / REVIEW PENDING`  
审查对象：`SIMIGO_LAB_P5_2_DEPENDENCY_CLOSURE_OPENING_DRAFT_20261001.md` (`d1a415f`)  
审查范围：Review A (Minimal Closure) + Review B (Security Boundary)  
纪律：只审查，不扩展，不实现，不运行模型

---

## Review A: Minimal Closure Review

核心问题：当前四关系 `{I, P, A, C}` 是否构成最小闭包？

### A1 Identity necessity

问题：没有 Identity，`state + Δ` 是否仍然定义明确？

风险：`same bytes / different model / different config / different execution` →
`same carrier, different computation`

审查输出要求：
```yaml
identity_necessary: ?        # 必要 / 非必要
evidence_grade: ?            # code-fact / inferred / speculative
failure_if_absent: ?         # 具体失败模式
```

### A2 Position necessity

问题：没有 Position，是否知道"下一步从哪里继续"？

重点区分：`data exists ≠ execution boundary exists`

审查重点：position 是 counter 还是 semantic location？

```yaml
position_necessary: ?
position_type: ?             # counter / semantic location / anchored location
evidence_grade: ?
failure_if_absent: ?
```

### A3 Semantic Anchor necessity

最关键项。问题：有 `{KV, position, identity}` 后，是否仍需要 anchor？

P5-1 证据：history 可能不是内容载体，而是 alignment proof。

审查输出：
```yaml
anchor_necessary: ?
anchor_role: ?               # content carrier / alignment proof / both / neither
evidence_grade: ?
failure_if_absent: ?
```

### A4 Continuation: state or capability?

挑战点：continuation 是能力（capability）还是状态（state）的组成部分？

如果没有 continuation relation，State 是否只是 snapshot？

审查输出：
```yaml
continuation_in_state: ?     # yes / no / partially
snapshot_vs_execution: ?     # continuation 是否区分 snapshot 和 execution state
evidence_grade: ?
```

### A5 Minimality proof

Remove-one-relation 概念测试：

| 移除 | 检验 | 结果 |
|---|---|---|
| Identity | 能否确认状态归属？ | |
| Position | 能否定位未来起点？ | |
| Anchor | 能否解释状态含义？ | |
| Continuation | 能否产生未来路径？ | |

输出：
```yaml
minimal_closure_confirmed: ?  # yes / no / partially
non_member_identified: ?      # 是否发现应移除的项
missing_member_identified: ?  # 是否发现应加入的项
```

---

## Review B: Security Boundary Review (P5-2-S)

核心问题：Execution State 是否携带超越数据本身的能力？

### B1 State possession → capability

拥有 Execution State 是否 = 拥有 future continuation capability？

区分：
```text
普通数据:   copy, read
Exec State: resume, continue, branch
```

```yaml
possession_equals_capability: ?
capability_boundary: ?        # 具体能做什么/不能做什么
```

### B2 State leakage → what leaks?

State 泄露时泄露的是什么？

审查层次：
```text
1. user privacy（历史对话内容）
2. model state（内部表示）
3. tool authority（工具权限状态）
4. environment binding（会话绑定）
```

```yaml
leakage_classification:
  data: ?
  capability: ?
  authority: ?
risk_level_per_layer: ?
```

### B3 State delegation

```text
Agent A → State → Agent B
```

B 是否继承 A 的：
```text
context（对话记忆）
authority（工具权限）
hidden assumptions（隐含前提）
```

```yaml
delegation_semantics: ?       # full inherit / partial / none
consent_required: ?           # A → B 转移是否需要 A 明确授权
audit_trail_required: ?
```

### B4 State revocation

如何 invalidate 一个可以继续计算的 State？

```text
如果 State = 能力凭证
则 revoke = 撤销计算授权
不是删除数据
```

```yaml
revocation_mechanism: ?       # 存在 / 需要设计 / 不可能
revocation_scope: ?           # single state / all descendants / lineage tree
revocation_proof: ?           # 如何证明已 revoke
```

---

## Review output format（统一）

```yaml
P5-2-ER Result

Definition:
  accepted / revised / rejected
  revision_notes: (if revised)

Minimal Closure:
  Identity:      necessary / not-necessary / uncertain
  Position:      necessary / not-necessary / uncertain
  Anchor:        necessary / not-necessary / uncertain
  Continuation:  in-state / capability-only / uncertain
  minimality:    proven / not-proven / partially

Security:
  capability_level: ?         # data-level / execution-level / authority-level
  risk_boundary: ?            # 具体边界描述
  revocation_feasible: ?      # yes / no / requires-design
  delegation_semantics: ?
  open_questions: [list]

Verdict:
  PASS / PASS-WITH-REVISIONS / FAIL / INCONCLUSIVE
```

---

## Post-review route

```text
P4 PASS
 └─▶ P5-1 INCONCLUSIVE
      └─▶ P5-2 Dependency Closure
           └─▶ [P5-2-ER External Review]  ← 当前
                ├─▶ Security Boundary Review
                └─▶ Palace Mapping (Knowledge Topology)
                     └─▶ P6 Architecture Synthesis
```

Palace Mapping 不得在 P5-2-ER 完成之前激活——否则 Palace 设计可能
固化一个尚未审计完成的 Execution State 定义。
