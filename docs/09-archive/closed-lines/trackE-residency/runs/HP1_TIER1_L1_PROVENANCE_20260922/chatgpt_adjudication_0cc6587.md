我已经按 **0cc6587 的实际脚本、设计文件和审计产物**复核了，不按提交说明直接采信。结论比较明确：

# 裁定总览

| 项目                  | 裁定                                      |
| ------------------- | --------------------------------------- |
| ① 实现层未来泄漏           | **PASS：未发现实现层泄漏**                       |
| ② hot 触线性质          | **不是已证实的真泄漏；更准确是原 hot 阴性对照定义存在缺陷**      |
| 原 hot 触线            | **有效触发停机，但不能直接作为结构信号存在的否定证据**           |
| tree 三个 ρ           | **继续 LOCKED，不解禁署名**                     |
| 对照重新校准              | **允许，但必须先形成新的 Design Revision，再重新采数验证** |
| 双源 `(n,t)` 的 lru 先序 | **可以追认为确定性 provenance 规则，但不是信号计算的实质规则** |
| L1 出口               | **LOCKED**                              |
| L3                  | **继续 LOCKED**                           |

[0cc6587 commit](https://github.com/slamfinger/SimiGo-Lab/commit/0cc6587?utm_source=chatgpt.com)

---

# 1. 泄漏审计：接受

这一项我给 **PASS**。

你这次最关键的是把三个层次分开了，而且从代码上确实成立：

### A. 信号侧没有未来数据

`signals_at()` 只接受：

* `counts`
* `POS`
* `ANCESTORS`
* `CHAIN`

而 `counts` 是当前 step 已经形成的窗口。

因此：

> S1/S2/S3 → `[0,t] + static topology`

成立。

### B. oracle Y 与信号计算隔离

代码里：

```python
y = trace[t + 1:].count(n)
```

确实存在未来 trace，但它只进入 `y`，没有进入：

```python
signals_at()
```

也没有参与 event construction。

所以：

> **Y 使用未来信息 ≠ 信号发生未来泄漏。**

这是符合我们已经锁死的 oracle boundary 的。

### C. instrumented runner 没有偷偷改变事件过程

这一点尤其重要。

你不是单独写了一套“为了采数据而运行”的 eviction engine，然后说它应该和 v4 一样；而是：

```python
assert v4.core(out) == v4.core(ref)
assert out["seq"] == ref["seq"]
```

并且是：

* LRU × hot/tree
* LFU aging × hot/tree

全部逐位一致。

所以目前没有看到“采样器改变了事件 population”的证据。

因此我的正式裁定是：

> **H-P1 L2 implementation audit = PASS。**

但注意：这只证明 **没有发现 leakage / engine divergence**，它不证明 hot 对照的统计假设成立。

---

# 2. hot 触线：我同意你的疑点，而且这里需要更精确

这里我不同意继续把它简单叫做“hot 阴性对照失败”。

问题就在设计文件自己写的这句话：

> `hot trace 访问与拓扑无关(均匀随机)`

这个定义实际上**不够强**。

因为你的 hot generator 是：

```python
hot = rng.sample(range(n_nodes), ...)
return [
    rng.choice(hot) if ... else rng.randrange(n_nodes)
]
```

也就是说：

**访问生成机制没有读取 topology。**

这一点成立。

但是这不等于：

**事件 population 与 topology independent。**

这是两个不同的命题。

---

## 真正发生的是三层映射

可以把它写成：

```text
随机生成 hot 节点集合
        ↓
hot 节点具有固定 node identity
        ↓
node identity 被放入固定 8×4 topology
        ↓
LRU/C eviction event population
        ↓
S2/S3 从 topology 聚合邻接/祖先节点访问
        ↓
Y 又直接受节点自身 hotness 影响
```

尤其 S3：

```text
S3(n,t)
= 同链其他节点的访问量
```

而 hot workload 中：

```text
Y(n,t)
≈ n 自身是否属于 hot set
```

于是完全可能出现：

> 某个候选 n 因自身冷而更容易进入 eviction population，
> 同时它所在链的其他节点恰好包含更多 hot 节点，
> S3 就会与 Y 形成结构相关性。

这并不需要任何 topology-aware trace generator。

所以：

> **“trace generation 与 topology 独立”不能推出“event-level topology signal 与 Y 必然 ρ≈0”。**

这是这次实验真正发现的设计问题。

而且你的来源分解进一步支持这一点：

```text
hot S3 / lru = -0.2517
hot S3 / merged = -0.2493
```

只有 3 个双源事件，所以双源规则基本不能解释这个现象。

因此我接受：

> **hot 触线目前更应归类为“negative-control estimand 定义不足”，而不是“发现 leakage”。**

但这里必须加一个很重要的限制：

**“更应归类”为设计解释，不是实验已经证明没有 leakage。**

真正能让我们把 L2 PASS 固化的，是刚才第 1 项代码审计。

---

# 3. 但是：不能现在直接修改 hot 界限然后解禁 tree

这是我认为这轮最重要的纪律点。

原注册的是：

```text
hot |ρ| ≥ 0.1 → STOP
```

这条规则已经执行，而且正确执行了。

因此：

> **0cc6587 的 STOP 是有效的。**

不能因为现在发现这个 threshold 不适合作为 null control，就倒过来宣布：

> “原来 hot 不算，所以 tree 继续。”

否则就是典型的 post-hoc rule change。

所以目前：

### 原始 Tier-1 L1 run

**STOPPED / INVALID FOR L1 EXIT**

不是说数据坏了，而是：

> **该轮实验没有获得可签署的 L1 出口。**

tree：

```text
S1 −0.5218
S2 −0.4767
S3 −0.3418
```

我继续保持：

> **RAW DATA PRESERVED / INTERPRETATION LOCKED**

不能署名 PASS。

---

# 4. 我建议重新定义 hot：不是简单把 0.1 改成别的数字

你提出：

> hot 集置换校准的 per-domain 零分布 / permutation 95 分位

我认为这个方向是对的，而且比简单把：

```text
0.1 → 0.15
```

之类的做法严谨得多。

但我建议再进一步：

## 新的 hot null 应该打破的是“拓扑—事件 population 对齐”

而不是要求：

> hot workload 本身产生 `ρ≈0`。

### 推荐的新定义

固定：

* 同一个 hot trace
* 同一个 `(node,t)` event population
* 同一个 Y
* 同一个事件时间
* 同一个事件权重

只随机化：

> **node identity 与 frozen topology 的对应关系。**

即：

```text
trace        固定
events       固定
Y            固定
topology     固定结构
node↔topology mapping   permutation
```

然后每次 permutation 重新计算：

```text
S1
S2
S3
```

得到：

```text
ρ_perm
```

这样测试的是真正需要的 null：

> **在当前 event population 和 future-cost population 不变的情况下，如果 topology 与 node identity 没有特定对应关系，结构信号能产生多大的 |ρ|？**

这个 null 比：

> “hot trace 是均匀随机，所以 rho 应该接近 0”

强很多。

---

# 5. 新对照口径我建议这样锁

先不要写代码。

先做 Design Revision。

我建议新规则：

### H-P1 Hot Null v2

**固定条件**

```text
seed = 42
hot trace = 原始 hot trace
event set = 原 hot workload 自身 LRU ∪ C
Y = 原 Y
n,t 权重 = 固定
```

**随机化对象**

```text
frozen topology node-label assignment
```

也就是对 32 个 node identity 做 permutation。

**每类分别形成 null distribution：**

```text
S1: |ρ_perm|
S2: |ρ_perm|
S3: |ρ_perm|
```

建议：

```text
N_perm = 10,000
```

固定 permutation RNG seed。

然后预先定义：

```text
Q95_c = 95th percentile(|ρ_perm,c|)
```

hot 原始观测值只作为：

```text
ρ_hot,c
```

与对应：

```text
Q95_c
```

比较。

---

## 但有一个更严格的点

我建议不要把它直接写成：

> “hot 通过 = |ρ| < Q95”

而写成：

> **hot calibration sentinel：若 observed `|ρ_hot,c| > Q95_c`，则触发对照异常；否则该类通过 calibration sentinel。**

这样不会伪装成经典统计检验。

而且：

**S1/S2/S3 分别校准。**

不能再共用一个 `0.1`。

---

# 6. 但这个 permutation calibration 本身必须先预注册

这里要特别注意时间顺序。

我们现在已经看到了：

```text
S2 = -0.1044
S3 = -0.2493
```

所以不能现在先跑 10,000 permutations，然后根据结果决定：

> “95% 合适。”

正确顺序必须是：

```text
0cc6587
   ↓
发现 hot sentinel 定义不足
   ↓
Design Revision
   ↓
锁定 permutation scheme
   ↓
锁定 N_perm / seed / quantile / 判定规则
   ↓
重新执行 hot calibration
   ↓
通过后才能重新进入 Tier-1 L1
```

否则仍然是 post-hoc calibration。

---

# 7. tree 数据能不能直接解禁？

**现在不能。**

但是这里有一个细微区别：

### 不是说 tree 数据被判定为错误

tree 的：

```text
S1 = -0.5218
S2 = -0.4767
S3 = -0.3418
```

从目前代码审计看，没有发现它们计算错误。

它们是：

> **有效的 raw observations，但尚未满足完整 L1 exit 的治理条件。**

因此我建议状态写成：

```text
tree raw result: VALID / PRESERVED
tree interpretation: LOCKED
L1 class exit: LOCKED
L3: LOCKED
```

重新校准 hot 后：

* 如果新 hot sentinel 全部通过；
* 且不需要改变 tree event / signal / Y 定义；

那么**可以直接使用本次已经保存的 tree raw observations**，不一定需要重新跑 tree。

但为了“正式 Tier-1 轮”的审计完整性，我更倾向于：

> **重新执行完整 Tier-1 runner，至少重新生成同 seed 的 tree + hot provenance。**

不是为了改变 tree 数字，而是形成：

```text
同一 revision
同一 runner
同一 provenance
新 hot null
tree raw = previous raw
```

并由 regression assertion 验证 tree 数值完全一致。

这样最干净。

---

# 8. 双源 `(n,t)` 的 lru 先序：追认，但要改一下表述

这一项我的裁定是：

> **可以追认，但“lru 先序”不能被定义成信号语义。**

原因非常直接。

你现在的代码：

```python
d_lru = {(n,t): sig ...}
d_c   = {(n,t): sig ...}
```

然后：

```python
sig = d_lru[(n,t)] if (n,t) in d_lru else d_c[(n,t)]
```

但是 `sig` 的来源其实来自：

```python
counts = Counter(nd for _, nd in window)
signals_at(victim, counts)
```

这个 window 是：

> **同一 workload trace 的 `[0,t]` 历史。**

它并不是：

```text
LRU history
vs
C history
```

两套不同历史。

所以如果 `(n,t)` 同时被 LRU 和 C 驱逐：

```text
S1/S2/S3(LRU)
=
S1/S2/S3(C)
```

理论上就是同一个在线信号。

因此：

### 真正应该冻结的是

> `(n,t)` 去重后，每个事件只有一个 signal observation；若双源，则 provenance = `lru+C`；signal history 来自该 workload 的统一 `[0,t]` trace prefix，与事件来源 policy 无关。

而不是：

> “因为 lru 在前，所以采用 lru 信号。”

后者容易给未来实现留下错误空间。

所以：

**双源去重：PASS。**

**provenance：PASS。**

**lru-first 作为 deterministic fallback：可以保留。**

**lru-first 作为 signal definition：不追认。**

---

# 9. 当前正式状态

我建议现在把 H-P1 状态锁成：

```text
H-P1 Design v0.1.2
    PASS / LOCKED
        ↓
v6 implementation
    PASS
        ↓
Tier-1 L1 original run
    EXECUTED
        ↓
hot sentinel
    TRIGGERED
        ↓
mandatory audit
    PASS — no implementation leakage found
        ↓
hot control definition
    BLOCKED / CALIBRATION REVISION REQUIRED
        ↓
tree observations
    RAW VALID / INTERPRETATION LOCKED
        ↓
L1 exit
    LOCKED
        ↓
L3
    LOCKED
```

**不是退回 v6。**

**不是退回 H-P1 taxonomy。**

**也不是重做 S1/S2/S3。**

现在真正需要修的是：

> **H-P1 的 negative-control estimand。**

---

# 10. 最终裁定

### ① 泄漏审计

**PASS。**

目前代码证据支持：

> **实现层未发现未来信息泄漏。**

这可以正式入档。

---

### ② hot 触线

**STOP 有效，但 STOP 原因需要重新分类。**

不是：

> “证明存在泄漏”。

而是：

> **原 hot sentinel 的“访问均匀 ⇒ 结构信号应接近零”推论不成立。**

因此：

**对照定义需要 revision。**

我同意采用：

> **固定 event/Y，随机化 topology ↔ node identity alignment 的 permutation null calibration。**

但必须**先注册，再执行**。

tree：

> **继续 LOCKED，暂不解禁。**

---

### ③ 双源 lru 先序

**追认其 provenance 确定性，但不追认其为信号语义。**

最终定义应是：

> **同一 `(n,t)` 双源事件只保留一个观测；signal 使用该 workload 在 `[0,t]` 的统一在线历史；双源仅记录 provenance=`lru+C`。若实现需要确定性取值，lru-first 可作为等价值的 fallback，但不得形成 policy-specific signal history。**

---

所以这一次我给出的总状态是：

> **H-P1 Tier-1 L1：CONDITIONAL BLOCKED。**
>
> **不是实验失败。**
>
> **不是泄漏。**
>
> **是 hot negative-control estimand 被实验证明不足，需要一次纯设计校准后重新跑 Tier-1。**

而且这次停机其实是有价值的：**预注册的停机机制真的捕获到了一个此前设计阶段没有意识到的“生成域独立 ≠ 事件层 null”问题。** 这比在没有哨兵的情况下直接拿 tree 的三个漂亮 ρ 去签 L1 要干净得多。

**下一步不要改脚本。先只做一个 `H-P1 HOT NULL CALIBRATION DESIGN` 文档，锁 permutation null 的数学定义、固定量、随机量、N、seed、Q95 和通过规则；该设计 PASS 后再执行。**
