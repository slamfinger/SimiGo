# Source/Runtime Estimand Definition v0.1

**状态**：\`DRAFT / STEP ④ DEFINITION — EXTERNAL REVIEW REQUIRED\`  
**日期**：2026-09-22  
**Gate**：Definition / Opening —— §8.1 **STEP ④：estimand 是什么**  
**前置状态**：STEP ③ 已经外审 PASS 并完成仓库登记；见 \`docs/RESEARCH_STATE.md\`。  
**边界**：本文只定义 C1 的目标 estimand，不定义第⑤步 existence criterion、第⑥步 insufficiency criterion、第⑦步 discriminating power、第⑧步 worth measuring，也不决定第⑨步 Path/Harness/Experiment；不产生采数授权。

## 0. 本步要解决什么

STEP ② 已形成 C1 正式问句：

> 在预注册的模型与 workload 边界内，真实 Swift/MLX execution 的访问与驻留相关行为，是否暴露出具有独立 residency / migration 语义的 Model Unit 边界？

STEP ③ 已确认该未知量不是既有模拟研究可以直接推出的结论。

因此 STEP ④ 不回答“有没有 unit”，而只回答：

> **如果要回答 C1，究竟要估计/描述哪一个目标量或目标结构？**

本文件把目标定义为**结构性 estimand**，而不是性能指标。

## 1. Estimand 主定义

### 1.1 目标对象

定义目标 estimand：

> **Runtime Unit Boundary Structure（RUBS）**：在给定模型、workload 与观察边界下，真实 runtime execution 中能够被区分为候选独立 residency / migration 对象的**边界结构**。

这里的 estimand 不是某一个预先指定的 layer、block、tensor slice 或 KV segment。

它的目标是描述：

1. 哪些运行时可观察状态变化可以被稳定地归属于一个局部对象边界；
2. 该边界是否能够与该对象自身的 residency / migration 状态区分开；
3. 对象边界之外的 execution continuation 是否保持语义关联；
4. 在同一观察域内，不同候选边界之间是否存在可区分的结构差异。

**候选 unit 家族仍保持开放。**

因此本步不声明 layer、block、slice、segment 中任何一个已经是目标 unit。

### 1.2 Estimand 的形式

用集合值目标表示，而不是提前压缩成单一标量：

\[
\mathcal{U}^{*}(M,W,O)
\]

其中：

- \(M\)：预注册模型域；
- \(W\)：预注册 workload 域；
- \(O\)：预注册观察边界；
- \(\mathcal{U}^{*}\)：在该定义域内具有目标结构属性的 runtime unit-boundary 候选集合。

每个候选 \(u\) 的目标描述为：

\[
B(u)=
\langle
A_u,\ R_u,\ C_u,\ I_u
\rangle
\]

其中：

- \(A_u\)：与 \(u\) 相关的可观察访问/共访问结构；
- \(R_u\)：与 \(u\) 对应的 residency 状态变量；
- \(C_u\)：与 \(u\) 对应的 migration / continuation 关系；
- \(I_u\)：execution identity / continuation 的语义关联。

**注意：**

\(B(u)\) 是目标结构的组成维度，不是四个已经定义好的测量指标。

具体观测量、阈值、统计形式以及“足以支持”的标准全部留给 STEP ⑤–⑦。

## 2. 为什么是集合值，而不是性能标量

C1 的未知量是“runtime 是否暴露对象边界”，不是“某种实现是否更快”。

因此以下量均不是本步的 estimand：

- decode latency；
- tokens/s；
- memory usage；
- migration time；
- cache hit rate；
- cold-load cost；
- 任何 speedup / slowdown；
- 任何与 Track B/F5 性能矩阵直接对应的指标。

这些量未来可能成为实验的辅助观测，但不能自动成为 C1 的目标量。

## 3. Population / domain

当前 estimand 的目标域由三层组成：

### 3.1 Model domain \(M\)

限定为后续正式研究注册时指定的 Swift/MLX execution model 集。

本文件不提前选择具体模型，也不把“已有测试模型”自动提升为总体。

### 3.2 Workload domain \(W\)

限定为后续正式注册的 execution workload 集。

本文件只规定 workload 必须能够产生与访问、驻留及 continuation 有关的可观察行为。

本文件不提前选择 workload，也不假设 RM-005 的访问模式原则成立。

### 3.3 Observation domain \(O\)

限定为未来设计能够合法观察到的 runtime state / event boundary。

本文件不预设某个 API、allocator、instrumentation hook 或 harness 为观察通道。

因此：

\[
(M,W,O)
\]

是 estimand 的**定义域**，而不是当前已经授权的实验配置。

## 4. Unit of analysis

C1 的基本分析单位不是单个 token、单次 latency sample 或单个 runtime event。

基本分析单位是：

> **候选 runtime object boundary \(u\)**，以及该 boundary 在一个预注册 execution/workload 中对应的状态关系。

因此后续分析可以比较：

\[
u_1,\ u_2,\ ...,\ u_n
\]

但 \(u_i\) 属于哪一个具体粒度族，必须由后续定义与观察过程决定，而不能在 STEP ④ 偷渡确定。

## 5. Estimand 与 C1 双向问题的关系

C1 问的是：

> 是否暴露出具有独立 residency / migration 语义的 Model Unit 边界？

RUBS 对应这个问句的方式是：

- 若 \(\mathcal{U}^{*}\) 在正式观察定义下存在可识别结构，则后续可以评价“暴露”；
- 若观察结果不足以支持这种结构，则后续可以评价“未获得足以支持暴露的证据”。

**但本文件不定义这两个出口的判据。**

特别禁止：

> “\(\mathcal{U}^{*}\neq\varnothing\) 就等于 existence criterion 已通过。”

是否足以称为“存在”，属于 STEP ⑤。

同样禁止：

> “\(\mathcal{U}^{*}=\varnothing\) 就等于 runtime 不存在自然粒度。”

有限观察边界内的“不足以支持”如何形成合法负向出口，属于 STEP ⑥。

## 6. Estimand 与语义等价的关系

C1 研究对象来自 Track B 的 frozen lifecycle semantics，但 Track B 不直接提供 runtime unit。

因此本 estimand 只继承一个**约束关系**：

> 候选 unit 的 residency / migration 语义必须能够与 execution identity / continuation 的关系同时被描述。

它不把 Track B 的具体五元组测试结果直接作为 runtime unit 的测量结果。

Track B 的五元组仍是历史冻结的不变式来源；本研究只把“语义保持关系”作为目标结构的一部分。

## 7. 需要后续定义、但本步刻意不填的变量

| 项 | 当前处理 | 所属后续步骤 |
|---|---|---|
| candidate unit 的具体族 | 不预选 | ⑤及以后 |
| residence 独立性的具体观测 | 未定义 | ⑤ |
| migration 语义的具体观测 | 未定义 | ⑤ |
| “足以支持存在”的阈值/规则 | 未定义 | ⑤ |
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

这些都属于未来可能的观测/实现载体。

如果某一实现载体无法表达目标结构，应由后续 discriminating-power / worth-measuring 阶段暴露问题，而不能反向修改 C1 使其适配工具。

## 9. 与历史研究的边界

本 estimand 不重新打开：

- Track B correctness / lifecycle 结论；
- P3 residency-policy 归因；
- H-P1 结构信号结论；
- nodes-out frozen accounting；
- nodes-out 注册预测。

历史结果只能提供定义约束或 provenance，不构成 \(\mathcal{U}^{*}\) 的 runtime 取值。

## 10. 本步产出

STEP ④ 当前产出仅为：

> **目标 estimand = 给定模型、workload、观察边界下的 Runtime Unit Boundary Structure（RUBS），以集合值的候选 runtime unit-boundary 结构作为目标对象，而非性能标量。**

本步尚未产生：

- existence criterion；
- insufficiency criterion；
- discriminating-power 证明；
- measurement plan；
- harness；
- experiment；
- RQ ID；
- 任何数据。

## 11. 门位快照

\`\`\`text
STEP ① 研究对象        PASS / 已登记
STEP ② 研究问题        Q2.1 已裁定 / RQ ID 未分配
STEP ③ 独立性          PASS / 已登记
STEP ④ estimand        DRAFT / 本文定义
STEP ⑤ existence       NOT STARTED
STEP ⑥ insufficiency   NOT STARTED
STEP ⑦ discriminating  NOT STARTED
STEP ⑧ worth measuring NOT STARTED
STEP ⑨ Path/Harness    NOT STARTED

RQ-F-01               NOT DEFINED
DATA COLLECTION        LOCKED
IMPLEMENTATION         FORBIDDEN
\`\`\`

**本文件是 STEP ④ 的定义草案，不改变 \`docs/RESEARCH_STATE.md\` 的当前状态；只有经过外部审查并由仓库显式登记后，STEP ④ 才可视为完成。**
