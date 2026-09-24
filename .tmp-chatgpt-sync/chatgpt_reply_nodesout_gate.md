我已经对 `edc4dad` 做了实际提交级审计。结论是：**H-P1 RESULTS 归档完整，可以封存；但 nodes-out 开题前，我建议先锁一个边界：必须把 Track B / M3 中 nodes-out 的原始定义追回来，不能直接用现在的“移除 nodes-out 通道”作为正式定义。**

[edc4dad 提交](https://github.com/slamfinger/SimiGo-Lab/commit/edc4dad8001ac4d9e069b2b756a13ec5279eccac?utm_source=chatgpt.com)

### ① RESULTS：确认完整，PASS / SEALED

我检查了 `edc4dad` 实际提交内容：

* `RESIDENCY_H-P1_RESULTS_20260922.md` 已完整新增；
* 100 行 RESULTS 覆盖了从 Design → v6 regression → 首轮 L1 → Hot Null v2 → L1 重跑 → L3 → 出口的完整链；
* `chatgpt_adjudication_68aa374.md` 也已经作为 provenance 一部分入档；
* 父提交正是 `68aa374`，没有出现断链；
* H-P1 的冻结纪律已经明确写入；
* `nodes-out UNLOCKED` 和 P4 mechanism-list input 已明确落档。

尤其几个容易漏掉的证据，现在都有：

| 证据                            | 状态 |
| ----------------------------- | -- |
| Design v0.1.2 PASS/LOCKED     | ✅  |
| v6 regression gate            | ✅  |
| 首轮 hot 触线及有效停机                | ✅  |
| 泄漏审计                          | ✅  |
| Hot Null v2 先注册后执行            | ✅  |
| Q95 校准，尤其 S3=0.4105           | ✅  |
| S1/S2/S3 L1 逐类署名              | ✅  |
| L2 construction/runtime audit | ✅  |
| L3 主方向 + sensitive direction  | ✅  |
| S1→D / S2→C / S3→C            | ✅  |
| H-P1 CLOSED/SEALED            | ✅  |
| P4 mechanism-list input       | ✅  |
| 原始裁定全文 provenance             | ✅  |

所以**没有必要再补 H-P1 RESULTS 证据**。

唯一一个我认为值得强调、但不是遗漏的问题是：Tier-2 seeds 43–47 没做，RESULTS 已明确限制为 **seed-42 Tier-1 experimental-domain fact**。这恰恰是正确的，不需要为了“完整”再补实验。

---

# ② nodes-out：方向对，但现在不要直接写正式 DRAFT

你提出的研究问题：

> nodes-out 移除后，execution state 迁移正确性与成本如何变化；仅保留 KV 常驻/外化二态？

**研究方向是对的。**

但我建议在正式起草 `nodes-out DESIGN DRAFT` 前，先增加一个极短的 **Definition Lock / Historical Definition Recovery** 门。

原因很简单：

**H-P1 的“结构信号”已经经过严格冻结；nodes-out 是下一条实验链的操作对象。此时最不能发生的，就是我们凭当前理解重新定义 nodes-out。**

我刚才实际在 `SimiGo-Lab` 和 `SimiGo` 中搜索了 `nodes-out`，没有找到可直接作为 Track B/M3 原始定义的命中。因此，**目前不能假装已经恢复了原始定义。**

所以这里应该先锁：

```text
H-P1
  CLOSED / SEALED
       │
       ▼
nodes-out
  Definition Recovery
       │
       ├─ Track B 原始定义
       ├─ M3 原始实验语义
       ├─ nodes-out 究竟移除什么
       ├─ execution state 究竟包含什么
       └─ 与 KV / node residency 的边界
       │
       ▼
Definition Lock
       │
       ▼
nodes-out Design DRAFT
       │
       ▼
Design Review
       │
       ▼
Implementation / Data UNLOCKED
```

### 我特别建议锁住这 5 个问题

**1. “nodes-out”究竟是对象还是通道？**

不能现在就假设它等价于：

> remove nodes-out channel

需要恢复原定义，确认它是：

* 某类 node 的 residency state；
* 某种 execution state migration；
* 某个 parameter/module 的外化路径；
* 还是 Track B/M3 中定义的特定运行机制。

---

**2. “移除”到底是什么意思？**

必须区分：

```text
A. 完全取消 nodes-out
B. nodes-out 不再作为策略选择
C. nodes-out 不再允许 resident
D. nodes-out 状态被迁移到 KV
E. nodes-out execution state 被重新编码
F. 仅取消某个外化/迁移通道
```

这些不是同一个实验。

---

**3. “仅保留 KV 常驻/外化二态”是否真的是原始比较域？**

你现在的描述：

```text
KV resident
    ↕
KV externalized
```

我认为可以作为**候选实验模型**，但暂时不能把它写成 nodes-out 的正式定义。

因为这一步如果定义错，后面即使实验做得再漂亮，也只是验证了我们自己重新定义出来的东西。

---

**4. execution state 必须单独定义**

这会是 nodes-out 比 H-P1 更关键的地方。

至少要拆成：

```text
model state
parameter residency
KV state
execution state
migration state
```

然后明确：

> nodes-out 移除究竟改变哪一个 state transition？

否则“迁移正确性”会变成一个过于宽泛的词。

---

**5. 成本模型不能直接继承 H-P1**

H-P1 的：

```text
J_boundary
C_ext
C_rehy
```

可以作为基础设施，但不能默认 nodes-out 的成本就是同一层含义。

nodes-out 很可能新增：

```text
migration cost
state reconstruction cost
state transfer cost
correctness loss / mismatch
```

而这些必须先定义成独立指标，不能偷偷塞进已有 J。

---

# ③ 因此我的正式裁定

### H-P1

**PASS / SEALED / CLOSED**

`edc4dad` 已经完成全链归档，不需要补证据。

### nodes-out

**UNLOCKED，但 Definition Lock PENDING。**

不是 BLOCKED。

准确地说：

> **允许立项，但暂不允许写入正式实验定义，更不允许实现和采数。**

下一步我建议不是直接写：

`RESIDENCY_NODES_OUT_DESIGN_20260922.md`

而是先做一个很小的：

**`nodes-out Definition Recovery`**

把 **Track B / M3 原始定义**找回来，然后只锁边界，不设计实验。

一旦这个定义恢复，我建议下一份 DRAFT 严格采用：

```text
① 原始定义
② 本轮研究问题
③ nodes-out 的移除边界
④ execution state 定义
⑤ KV / node residency 边界
⑥ correctness 定义
⑦ cost channels
⑧ 与 H-P1 / P3 的继承关系
⑨ 明确禁止哪些实验解释
⑩ Exit criteria
```

**所以你的总体方向不需要改；需要先补的只有一个门：`nodes-out Definition Lock`。**

这一步做完，才进入正式开题 DRAFT。
