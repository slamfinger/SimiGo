# Nodes-out Candidate A Effect Interpretation Contract v0.1

**状态**：`DRAFT / EXTERNAL REVIEW REQUIRED`  
**日期**：2026-09-22  
**边界**：本文件只定义 Runner 结果的解释语义和后续最小采数方案；不改 Runner、不改 frozen baseline、不改 Candidate A、不采数、不做效果结论。

## 0. 审计锚点

| 项 | 值 |
|---|---|
| Correctness evidence commit | `38043cc` |
| Correctness external audit | PASS |
| Audited Runner | `f4d880e` / Runner v2.2.1 |
| Frozen baseline | `17bde28:trackE-residency/residency_policy_simulator_v3.py` |
| Baseline blob | `ff6d4e21df40db800e64bd5c949c39b3d77d22aa` |
| Runner artifact | `trackE-residency/runs/NODES_OUT_RUNNER_AUDIT_20260922/runner_audit.json` |
| Artifact SHA-256 | `556ab61f2fe39fdf0db0a392d2bc99496d6ba83b09fc9e427f481aac68216521` |

Correctness PASS 只说明：Candidate A 在冻结输入上的事件完成态、逐步五元组、终态五元组、容量合规和确定性满足预注册 correctness contract。  
Correctness PASS **不说明** Candidate A 更好、更差、更省、更快或更适合上线。

## 1. 解释对象与对齐单位

### 1.1 执行对象

| 模型 | residency object | 容量单位 | 语义 |
|---|---:|---:|---|
| Baseline | node | 12 node slots | 一次 node 外化或迁回移动一个 node 粒度对象 |
| Candidate A | KV unit | 24 unit slots | 每个节点拆成 GDN 与 ATT 两个 unit；每个 unit 只有 `res` 一个状态位 |

Candidate A 的 GDN 与 ATT 在容量模型中各占一个 unit slot；KiB 只作披露，不参与容量加权。

### 1.2 唯一对齐锚点

效果指标只允许在以下对齐单位上报告：

```text
workload w ∈ {hot, tree}
  × decode step t ∈ [0, 1999]
  × current node n = trace_w[t]
```

禁止把 hot 与 tree 合并，禁止把不同 step 无序聚合后解释成普适行为。

### 1.3 事件语义边界

Baseline：

```text
rehydrate = non-resident node → resident node
externalize = resident node → non-resident node
```

Candidate A：

```text
rehydrate   = non-resident KV unit → resident KV unit
externalize = resident KV unit   → non-resident KV unit
```

Runner 的 Candidate `rehydrate` 是 acquisition umbrella，同时覆盖：

1. cold-load：该 unit 从未 resident 后的首次获取；
2. historical rehydration：该 unit 曾 resident 后被容量驱逐后的再获取。

当前 Runner artifact 不拆分这两类。因此在没有 Design Revision 和 Runner 修订前，禁止宣称已经测量 cold-load 与 rehydrate 的差异。

### 1.4 已知读数只能作背景

`f4d880e` artifact 中已经出现以下读数：

| model / workload | rehydrate count | externalize count |
|---|---:|---:|
| baseline hot | 696 | 684 |
| baseline tree | 1,015 | 1,003 |
| Candidate A hot | 1,392 | 1,368 |
| Candidate A tree | 2,030 | 2,006 |

这些数字只作为解释语义设计背景。由于 baseline 与 Candidate A 的 residency object、slot budget、事件粒度和 acquisition umbrella 均不同，上述表内数字不得相互相减、求比值或直接排序。

## 2. A. 可解释指标注册表

每项指标必须按下表解释。未列出的派生指标不得进入 effect verdict。

| ID | metric | definition | unit | baseline counterpart | normalization | allowed interpretation | forbidden interpretation |
|---|---|---|---|---|---|---|---|
| M01 | logical KV version vector | 每个 node 的逻辑版本号；Candidate 用 `logical_versions`，baseline 用 frozen runtime state 中的 `kv_versions` | integer / node | direct | none | 判断逻辑 KV 是否连续、可复现 | 解释为性能、质量或效果优劣 |
| M02 | decode-ready | 当前 node 在完成本 step 驻留操作后可解码：baseline 为 current node resident；Candidate 为 `(GDN,current)` 与 `(ATT,current)` 都 resident | boolean / step | direct | none | 报告当前 decode 触达是否可执行 | 解释为速度、吞吐或输出质量 |
| M03 | frozen five-tuple equivalence | Identity / Position / Next Input / KV versions / Continuation 在同 step 与 frozen baseline 比较 | equivalence / step | direct | none | 陈述 correctness contract 是否成立 | 推导 performance PASS |
| M04 | current-node coverage | 本 step 当前 node 的必要驻留对象是否齐备；baseline 是 node resident，Candidate 是 GDN+ATT unit 都 resident | boolean / step | direct at current node | none | 报告粒度策略是否覆盖当前 decode 触达 | 把 unit 齐备等同于 node-level policy 等价 |
| M05 | residency state shape | baseline 为 resident node set；Candidate 映射为 `full_node` / `partial_node` / `empty_node`：分别是 GDN+ATT 都 resident、恰一 unit resident、无 unit resident | state class / node / step | mapped, not identical | none | 描述 Candidate 的粒度状态形状 | 把 Candidate full node 与 baseline resident node 当作同一容量或行为对象 |
| M06 | slot occupancy ratio | baseline = resident nodes / 12；Candidate = resident units / 24 | ratio / step | same ratio form only | by own slot budget | 检查各自容量模型内的占用与合规 | 跨模型比较容量效率，或宣称 12 node slots 等于 24 unit slots |
| M07 | resident byte exposure | baseline = resident node 数 × 78,246 KiB；Candidate = 当前 resident units 的 GDN/ATT KiB 之和，即 GDN 61,440 KiB、ATT 16,806 KiB | KiB / step | byte-denominated disclosure | common KiB denominator | 作为 identity-mapping byte-accounting 披露 | 解释为性能、节省、成本收益或容量等价；当前容量强制仍按 slot，不按 byte |
| M08 | raw rehydrate count | baseline 计 node acquisition；Candidate 计 unit acquisition umbrella | event count / workload | name-only counterpart | none，禁止跨粒度归一 | 如实报告各自模型内事件数 | 直接相减、求比值、排名，或用高低宣布改善/劣化 |
| M09 | rehydrate byte mass | baseline = rehydrate count × 78,246 KiB；Candidate = 按 event unit 分别累计 61,440 或 16,806 KiB | KiB / workload | byte-denominated counterpart | common KiB event mass | 在 identity mapping、0 modeled conversion cost 前提下披露 migration accounting | 解释为延迟、吞吐、真实开销或策略更优 |
| M10 | node-touch acquisition incidence | baseline：current node 是否发生 node acquisition；Candidate：current node 是否至少一个 GDN/ATT unit 发生 acquisition；另可披露 `full-pair acquisition` 子集 | incidence / node touch | mapped, not identical | none | 描述触达时是否发生粒度对象获取 | 用该 incidence 替代或等价化 raw rehydrate count |
| M11 | raw externalize count | baseline 计 node eviction；Candidate 计 unit eviction | event count / workload | name-only counterpart | none，禁止跨粒度归一 | 如实报告各自模型内事件数 | 直接相减、求比值、排名，或用高低宣布改善/劣化 |
| M12 | externalize byte mass | baseline = externalize count × 78,246 KiB；Candidate = 按 event unit 分别累计 61,440 或 16,806 KiB | KiB / workload | byte-denominated counterpart | common KiB event mass | 在 identity mapping、0 modeled conversion cost 前提下披露 migration accounting | 解释为延迟、吞吐、真实开销或策略更优 |
| M13 | compatible J disclosure | `J = 0.69 × ext_count + 0.72 × rehy_count`，分别用各自模型自身计数计算 | score / workload | name-only compatibility channel | none | 仅作为与既有 H-P1/P3 口径的兼容披露 | 作为 Candidate A 的主判据、效率结论或跨粒度优劣结论 |
| M14 | deterministic reproduction | 同进程双跑比较 `events`、`final`、`steps`、`violations` | diff count / workload | same | none | 陈述实验可复现性 | 把确定性等同于正确性或效果优势 |
| M15 | workload isolation | hot 与 tree 分开统计、分开解释 | domain | same | none | 报告 frozen workload 内事实 | 合并域、跨域泛化、选择单一有利域下结论 |

## 3. B. Baseline ↔ Candidate A comparison matrix

| 指标 | baseline | Candidate A | 是否可直接比较 | 解释规则 |
|---|---|---|---|---|
| logical KV version | ✓ | ✓ | 是 | 只作 continuity/correctness 事实 |
| next input / continuation | ✓ | ✓ | 是 | 只作 step-level correctness 事实 |
| decode-ready current node | ✓ | ✓ | 是 | 只说明当前触达可解码 |
| terminal capacity compliance | ✓ | ✓ | 是，但分模型 | baseline ≤12 nodes；Candidate ≤24 units；禁止互换容量单位 |
| resident node set | ✓ | △ | 需映射 | Candidate 只能映射成 full/partial/empty node shape |
| GDN/ATT unit residency | ✗ | ✓ | 否 | Candidate-only descriptor |
| raw rehydrate count | ✓ | ✓ | 否 | 粒度不同，禁止直接比较 |
| raw externalize count | ✓ | ✓ | 否 | 粒度不同，禁止直接比较 |
| rehydrate byte mass | ✓ | ✓ | 条件性可披露 | 仅 identity mapping + 0 modeled conversion cost 下的 accounting，不是性能 |
| externalize byte mass | ✓ | ✓ | 条件性可披露 | 同上 |
| compatible J | ✓ | ✓ | 仅兼容披露 | 不并入新通道，不作主判据 |
| determinism | ✓ | ✓ | 是 | 只说明可复现性 |
| workload effect | hot/tree 可分别描述 | hot/tree 可分别描述 | 否，禁止合并 | tree 是后续 Tier-1 主域，hot 是披露域 |

## 4. C. Effect verdict 的禁止条件

以下结论在当前门位一律禁止：

1. 不得因 Candidate `rehy_count` 高于或低于 baseline 而宣布 Candidate 更差/更好。
2. 不得因 Candidate `ext_count` 高于或低于 baseline 而宣布 Candidate 更差/更好。
3. 不得直接比较 unit event count 与 node event count。
4. 不得假设 24 unit slots 与 12 node slots 具有相同物理容量、压力或成本。
5. 不得把 Candidate 的 acquisition umbrella 拆释成已测量的 cold-load / historical rehydrate 差异。
6. 不得把 byte exposure 或 byte mass 解释为延迟、带宽实测、经济成本或真实系统收益。
7. 不得把 compatible J 用作 Candidate A 的主判据，也不得把三个 cost channel 合并。
8. 不得从 correctness PASS 推导 performance PASS、机制优势或系统可上线性。
9. 不得把 hot 与 tree 合并、平均、相互补证，或从单一 workload 推广到通用 workload。
10. 不得做 event-level one-to-one 对齐；唯一合法锚点是 decode step 边界。
11. 不得在未通过本 contract 外审前启动 Tier-1 采数。
12. 不得修改 Runner 后继续引用旧 artifact 证明新行为；Runner 修订必须触发新的 correctness audit。
13. 不得把当前合成 trace、seed 42、identity mapping、slot capacity 的结果宣称为真实模型或生产 KV cache 的因果结论。

## 5. D. Tier-1 最小采数方案预定义

本节只有在 Effect Interpretation Contract 外审 PASS 后才可执行。当前仍为 `LOCKED`。

### 5.1 不变量

| 项 | 锁定值 |
|---|---|
| Runner | `f4d880e` Runner v2.2.1，零逻辑修改 |
| baseline | `17bde28` frozen `simulate_v3` |
| Candidate A | GDN/ATT 二态 unit 模型 |
| seed | 42 |
| trace | hot、tree 各 2,000 steps |
| node budget | 12 |
| unit budget | 24 |
| costs | `C_ext=0.69`, `C_rehy=0.72`，仅 compatible J 披露 |

### 5.2 最小实验面

1. workload 只保留 frozen `hot` 与 frozen `tree`，分开报告。
2. 不新增 seed、trace、policy、budget、model 或 Candidate 变体。
3. 使用 Runner 既有双跑口径验证 determinism。
4. 允许新增独立的 read-only extraction artifact，从未修改 Runner 的内存事件中读取 `unit` 类型；extractor 不得改变 residency、容量、policy 或 violation 逻辑。
5. 若必须让 Runner 直接输出新字段，则先做 Design Revision，并重跑三层 correctness audit；不得复用 `f4d880e` 旧 artifact 冒充新行为。

### 5.3 首轮必报读数

按 workload 分离报告：

1. M02 decode-ready；
2. M04 current-node coverage；
3. M05 full/partial/empty node state shape；
4. M06 slot occupancy ratio；
5. M07 resident byte exposure；
6. M08 raw rehydrate count；
7. M09 rehydrate byte mass；
8. M10 node-touch acquisition incidence；
9. M11 raw externalize count；
10. M12 externalize byte mass；
11. M13 compatible J disclosure；
12. M14 deterministic reproduction。

### 5.4 首轮报告形状

每个 workload 至少输出：

```text
workload
  baseline:
    raw event counts
    byte event mass
    compatible J disclosure
  candidate_a:
    raw event counts
    byte event mass by GDN/ATT
    node-touch acquisition incidence
    full/partial/empty state accounting
    slot occupancy
    resident byte exposure
    compatible J disclosure
  explicit_non_comparisons:
    raw count delta/ratio: forbidden
    performance verdict: forbidden
    cross-workload generalization: forbidden
```

### 5.5 停机条件

出现任一情况立即停机，不得进入效果解释：

1. baseline regression FAIL；
2.任一 L1/L2/L3 formal violation；
3. deterministic diff 不为 0；
4. current node 丢失必要 unit；
5. Candidate resident units 超过 24；
6. artifact 与 Runner SHA-256 或 commit 绑定不一致；
7. extractor 改变了 Runner 决策路径。

### 5.6 首轮出口

首轮不是性能 PASS/FAIL。唯一出口是：

```text
granularity mechanism accounting = as-recorded mechanism knowledge
```

报告必须显式区分：

```text
可比较层：logical state / decode feasibility / own-budget compliance
披露层：byte mass、compatible J、state shape
禁止层：raw count 优劣、跨粒度效率、跨域泛化、因果与生产结论
```

## 6. 当前门位

```text
BASELINE REGRESSION                 PASS
RUNNER v2.2.1                      PASS
L1                                  PASS
L2                                  PASS
L3                                  PASS
DETERMINISM                        PASS
CORRECTNESS AUDIT                  PASS
────────────────────────────────────────
EFFECT INTERPRETATION CONTRACT     DRAFT v0.1
EXTERNAL CONTRACT REVIEW           REQUIRED
Candidate A effect verdict         LOCKED
TIER-1 DATA COLLECTION             LOCKED
```
