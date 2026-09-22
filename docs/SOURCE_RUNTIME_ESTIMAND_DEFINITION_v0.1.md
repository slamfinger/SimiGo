# Source/Runtime Estimand Definition v0.1

**状态**：`DRAFT / STEP ④ DEFINITION — REVISED AFTER EXTERNAL REVIEW`  
**日期**：2026-09-22  
**Gate**：Definition / Opening —— §8.1 **STEP ④：estimand 是什么**  
**前置状态**：STEP ③ 已经外审 PASS 并完成仓库登记；见 `docs/RESEARCH_STATE.md`。  
**边界**：本文只定义 C1 的目标 estimand，不定义第⑤步 existence criterion、第⑥步 insufficiency criterion、第⑦步 discriminating power、第⑧步 worth measuring，也不决定第⑨步 Path/Harness/Experiment；不产生采数授权。

## 0. 本步要解决什么

STEP ② 已形成 C1 正式问句：

> 在预注册的模型与 workload 边界内，真实 Swift/MLX execution 的访问与驻留相关行为，是否暴露出具有独立 residency / migration 语义的 Model Unit 边界？

STEP ③ 已确认该未知量不是既有模拟研究可以直接推出的结论。

因此 STEP ④ 不回答“有没有 unit”，而只回答：

> **如果要回答 C1，究竟要估计/描述哪一个目标结构？**

本文件定义一个**观察域条件下的运行时边界结构（Runtime Boundary Structure, RBS）**。

本次修订遵循外部审查意见：estimand 本身不再筛选“已经具有独立 residency / migration 语义”的对象；是否足以把某一边界解释为 Model Unit，明确留给 STEP ⑤。

## 1. Estimand 主定义

### 1.1 目标对象

目标 estimand：

> **Runtime Boundary Structure（RBS）**：在给定模型域、workload 域和合法观察域下，runtime execution 所呈现的**对象边界及其状态/事件关系结构**。

这里的“边界”首先是描述对象，而不是已经被判定为 Model Unit 的对象。

因此本步不定义：

- 哪个边界已经是独立 residency 对象；
- 哪个边界已经具有 migration 语义；
- 哪个边界足以称为 Model Unit；
- 哪种边界最终具有自然性、稳定性或独立性。

这些都是后续判定问题，而不是 estimand 本身。

### 1.2 Estimand 的形式

定义：

[
mathcal{B}(M,W,O)
]

其中：

- (M)：预注册模型域；
- (W)：预注册 workload 域；
- (O)：预注册观察域；
- (mathcal{B})：在该定义域内 runtime 所呈现的边界结构。

对其中任一边界候选 (b)，目标结构描述为：

[
S(b)=langle
A_b, R_b, C_b, I_b
angle
]

其中：

- (A_b)：边界相关的访问 / 共访问关系；
- (R_b)：边界相关的 residency-state 变化关系；
- (C_b)：边界相关的 migration / continuation 变化关系；
- (I_b)：execution identity / continuation 的关联关系。

这里四个分量都是**目标结构中的描述维度**，不是通过/不通过的判定指标。

尤其需要区分：

[
mathcal{B}(M,W,O)

eq
{b: b	ext{ 已经满足 Model Unit 存在条件}}
]

后者属于 STEP ⑤ 的 existence criterion，不属于 STEP ④ estimand。

### 1.3 为什么仍然是结构性 estimand

C1 的未知量不是“某种实现是否更快”，而是 runtime execution 是否呈现出能够支持 Model Unit 解释的边界结构。

因此目标量应保留：

- 边界；
- 边界之间的关系；
- 边界与访问、驻留、迁移及 continuation 的关系。

本步不把这些关系压缩为 latency、tokens/s 或 memory 等性能标量。

## 2. 为什么不是性能标量

以下量均不是本步主 estimand：

- decode latency；
- tokens/s；
- memory usage；
- migration time；
- cache hit rate；
- cold-load cost；
- speedup / slowdown；
- 任何与 Track B/F5 性能矩阵直接对应的指标。

这些未来可以成为辅助观测，但不能自动替代 C1 的目标结构。

## 3. Population / domain

### 3.1 Model domain (M)

限定为后续正式研究注册时指定的 Swift/MLX execution model 集。

本文件不提前选择具体模型，也不把已有测试模型自动提升为总体。

### 3.2 Workload domain (W)

限定为后续正式注册的 execution workload 集。

本文件不提前选择 workload，也不假设 RM-005 的访问模式原则成立。

### 3.3 Observation domain (O)

限定为未来正式研究允许观察的 runtime state / event boundary。

本文件不预设某个 API、allocator、instrumentation hook 或 harness 为观察通道。

因此：

[
(M,W,O)
]

是 estimand 的**条件定义域**，而不是当前已经授权的实验配置。

## 4. Unit of analysis

本步的分析对象不是单个 token、单次 latency sample 或单个 runtime event。

基本分析对象是：

> **runtime 所呈现的对象边界 (b)，以及该边界在预注册 execution/workload 中的关系结构 (S(b))。**

这里的 (b) 仍不是已经认证的 Model Unit。

具体粒度族（layer、block、tensor slice、KV segment 或其他 runtime object）不在 STEP ④ 预选。

## 5. Estimand 与 C1 的关系

C1：

> 是否暴露出具有独立 residency / migration 语义的 Model Unit 边界？

STEP ④ 提供的是：

> **runtime 中“边界及其相关状态关系”究竟是什么。**

然后才可以在 STEP ⑤ 问：

> 哪一种观察到的边界结构，满足预先定义的条件后，才足以支持“Model Unit 存在”的判断？

因此逻辑关系严格保持：

[
	ext{Estimand}
ightarrow
	ext{Existence Criterion}
]

而不是：

[
	ext{Existence Criterion}
ightarrow
	ext{Estimand}
]

本文件不规定箭头右侧的判定内容。

特别禁止：

> “存在某个 (b) 就等于 Model Unit 存在。”

同样禁止：

> “不存在可观察 (b) 就等于 runtime 不存在自然粒度。”

有限观察域内的正、负证据如何解释，属于 STEP ⑤–⑥。

## 6. 与语义等价的关系

C1 研究对象来自 Track B 的 frozen lifecycle semantics，但 Track B 不直接提供 runtime unit。

因此本 estimand 只允许把 execution identity / continuation 等作为**待描述的结构关系**，不把 Track B 的历史测试结果直接作为 runtime boundary 的取值。

Track B 五元组仍是历史冻结的不变式来源；本研究不从其结果预先推出某个 runtime boundary 存在。

## 7. 本步刻意不填的变量

| 项 | 当前处理 | 所属后续步骤 |
|---|---|---|
| candidate boundary 的具体族 | 不预选 | ⑤及以后 |
| residency 独立性的判据 | 未定义 | ⑤ |
| migration 语义的判据 | 未定义 | ⑤ |
| “足以支持存在”的规则 | 未定义 | ⑤ |
| “不足以支持”的规则 | 未定义 | ⑥ |
| 观测噪声与判别能力 | 未定义 | ⑦ |
| 样本量 / 重复次数 | 未定义 | ⑦ |
| 测量成本与信息价值 | 未定义 | ⑧ |
| runtime API / harness | 未决定 | ⑨ |
| RQ ID | 未分配 | 整条 RQ 定义完成后 |

## 8. 防止 implementation-first 的约束

本 estimand 可以独立于具体实现路径表达。

因此：

- MLX API 不是 estimand；
- Swift object/class 不是 estimand；
- allocator handle 不是 estimand；
- tensor pointer 不是 estimand；
- KV-cache data structure 不是 estimand；
- residency manager 不是 estimand；
- harness event schema 不是 estimand。

这些属于未来可能的观测/实现载体。

如果某一实现载体无法表达目标结构，应由后续 discriminating-power / worth-measuring 阶段暴露问题，而不能反向修改 C1 使其适配工具。

## 9. 与历史研究的边界

本 estimand 不重新打开：

- Track B correctness / lifecycle 结论；
- P3 residency-policy 归因；
- H-P1 结构信号结论；
- nodes-out frozen accounting；
- nodes-out 注册预测。

历史结果只能提供定义约束或 provenance，不构成 (mathcal{B}(M,W,O)) 的 runtime 取值。

## 10. 本次修订说明

外部审查指出旧版存在两个主要耦合：

1. (mathcal{U}^{*}) 的定义已经按“具有目标结构属性”筛选候选对象，接近 STEP ⑤ existence criterion；
2. (B(u)) 中的 residency / migration / continuation 关系容易被误读为隐藏的通过条件。

因此本版改为：

[
oxed{mathcal{B}(M,W,O)}
]

即先描述**观察域内的 runtime boundary structure**，不在 estimand 层面判断某边界是否已经构成 Model Unit。

## 11. 本步产出

STEP ④ 当前产出仅为：

> **目标 estimand = 给定模型、workload、观察域下，runtime execution 所呈现的 Runtime Boundary Structure（RBS），以及该边界与访问、驻留、迁移和 continuation 相关的结构关系。**

本步尚未产生：

- existence criterion；
- insufficiency criterion；
- discriminating-power 证明；
- measurement plan；
- harness；
- experiment；
- RQ ID；
- 任何数据。

## 12. 门位快照

```text
STEP ① 研究对象        PASS / 已登记
STEP ② 研究问题        Q2.1 已裁定 / RQ ID 未分配
STEP ③ 独立性          PASS / 已登记
STEP ④ estimand        REVISED DRAFT / 待再次外审
STEP ⑤ existence       NOT STARTED
STEP ⑥ insufficiency   NOT STARTED
STEP ⑦ discriminating  NOT STARTED
STEP ⑧ worth measuring NOT STARTED
STEP ⑨ Path/Harness    NOT STARTED

RQ-F-01               NOT DEFINED
DATA COLLECTION        LOCKED
IMPLEMENTATION         FORBIDDEN
```

**本文件仍是 STEP ④ 定义草案，不改变 `docs/RESEARCH_STATE.md` 的当前状态；本次修订也不授权 STEP ⑤、数据采集或实现。**
