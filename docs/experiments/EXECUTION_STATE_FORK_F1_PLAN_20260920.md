# Track B：Execution State Fork F1 原型计划（2026-09-20）

**性质**：SimiGo 2.0 实验室预研；独立于 1.7 production pin。  
**起点**：F0 已证明当前公开 MLXLMCommon 面没有 sequence identity / COW prefix-sharing 语义；现有磁盘 fork 基线为 63.6K、1.53GB checkpoint、save→copy→load 约 1.94s。

## 目标

把 F0 的“能力缺口”转成一个最小可验证的 engine-fork 原型：

1. **Sequence Identity**：一个 execution state 可以拥有稳定、可区分的逻辑序列身份。
2. **Shared Immutable Prefix**：fork 后 parent/child 默认共享共同 prefix storage。
3. **Lazy Materialization / COW**：只有 child divergence 产生私有物理存储。
4. **Restore**：parent / child 可以按逻辑状态恢复，而不是重新做完整 prefix prefill。

## 模型前提

本实验以 qwen3_5_moe 混合布局作为首个验证对象。长上下文工作集主要集中在 attention KV；KV 是 append-only，天然适合“不可变前缀 + 私有 suffix”的 COW 模型。GDN 递归态尺寸与序列长度无关，因此 fork 时按固定尺寸状态复制处理；F0 中 GDN 不可 trim/rewind 不等于 fork/COW 不可行。

该判断必须通过实测验证，不把模型结构假设直接当成实现正确性。

## 三个主指标

### 1. Fork Cost

记录：

- fork wall time
- fork 前后 active / footprint
- 新增物理 KV
- 是否发生完整 KV materialization

参考基线：63.6K 磁盘 fork 1.53GB / 1.94s。

目标方向：进入亚秒级；物理增长只随分叉后的 delta 增长，而不是随完整 prefix 线性增长。

### 2. Restore Depth

建立：

`A → B → C → D`

分别测：

- D → C
- D → B
- D → A

记录 wall time / memory delta，观察成本随深度是否近似平坦。

参考已有 120K restore：18.2s。

### 3. Shared Page Ratio

对每次 fork：

`shared_pages / total_parent_pages`

同时记录：

`private_pages / total_pages`

目标是证明共同 prefix 不发生全量复制。

## 正确性门（硬门）

每一个性能结果都必须先通过：

> fork 出的 child 从相同 prefix 继续 greedy decode，与“同一 prefix 从零 prefill 后再 decode”的结果逐 token 一致。

至少记录：

- token-by-token equality
- 首个 divergence token（若有）
- logits / selected-token 差异（用于定位）

**正确性失败时，Fork Cost / Restore Depth / Shared Page Ratio 的速度收益全部作废。**

## 工程隔离

- engine fork：实验分支；生产 pin 不修改
- vendor 检出后使用 fresh `derivedDataPath`
- 只在实验分支实现 sequence identity / shared prefix / COW / lazy materialization
- 不把 BranchManager、Merge、Speculative Decoding 等更高层机制提前带入
- 实验室代码永不直接迁移进 1.7

## Level 门

- B0：sequence identity 可创建/查询
- B1：parent/child 共享 prefix
- B2：divergence 后只物化 delta
- B3：restore 成本随深度不显著线性增长
- B4：逐 token correctness 通过
- B5：对 1.7 磁盘 fork 有明确成本优势

只有 B4 + B5 通过，才讨论生产版本的引入；迁移必须另立版本，不从实验分支后门进入。
