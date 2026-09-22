# 实验记录

这里记录尚未进入核心架构的方案、原型和验证过程。

实验的目的不是证明方案一定正确，而是用最小成本回答具体问题。

## 标准证据链

```
Research Question / Problem
        ↓
Hypothesis
        ↓
Protocol
        ↓
Observation
        ↓
Evidence
        ↓
Result
        ↓
Conclusion
        ↓
Decision / Architecture
```

实验成功也不意味着自动进入 Core。

必须经过架构评审，并在需要时形成架构决策。

## Experiment 最低要求

每个重要实验至少应能够回答：

- 它要验证什么？
- 如何验证？
- 观察到了什么？
- 原始证据在哪里？
- 结论的边界是什么？
- 是否产生新的 Finding / Lesson？
- 是否触发 Decision / Architecture 变化？

## 特别说明

Batch、Paged KV、连续服务、推测解码等能力，在没有完成正确性与性能验证之前，应保持在实验层，不得反向污染核心架构。

## 与 Research / Knowledge 的关系

- [Research](../research/README.md) —— 研究问题与综合分析
- [Knowledge](../knowledge/README.md) —— 从证据中沉淀的知识
- [Decisions](../decisions/README.md) —— 需要长期约束的架构选择

## 演进路线图

- [EVOLUTION_TRACK.md](EVOLUTION_TRACK.md) —— S1 Controlled Batched Execution → S2 Paged/Block KV + Radix Prefix Cache → S3 Continuous Serving + Speculative 的完整路线（已归档）。含：总体演进原则（守正/精简）、演进纪律管道、各阶段准出标准、Hybrid/Mamba NO-GO 结论、**第二十章 对优秀开源实现的借鉴边界**（mlx-lm / llama.cpp / vLLM / SGLang 各自借鉴什么）、**第二十一章 明确"不照搬"**（不复制 CUDA kernel / Python runtime / C++ 内存架构，把成熟 Serving 思想重映射到 Apple Silicon + MLX + Swift）、**第二十二章 稳定 DMG 发布纪律**。
- [OFFICIAL_CAPABILITY_MATRIX.md](OFFICIAL_CAPABILITY_MATRIX.md) —— 官方 MLX 能力覆盖矩阵（对照 mlx-swift-lm main@238ad74 逐 API 核实）：P0 = KVCacheConfiguration 透传（GenerateParameters.kvCachePlan 入口）与 Raw Token Generation 能力边界；P1 = Prompt Cache Save/Load、Guided Generation、参数补齐；含 SpeculativeDecodingConfig 已内置 ChatSession 的事实修正与明确排除项（LoRA/Fine-tuning/Batch）。
- [EXECUTION_FORK_F0_PROBE_20260918.md](EXECUTION_FORK_F0_PROBE_20260918.md) —— Execution Fork F0 能力探针（设计登记，未动工）：第一性问题「MLX 能否不重算共同 prefix 派生可继续执行的 child state」的最小可判定实验；copy 成本曲线 + 公开面探查 + 判定矩阵（是→F1 ExecutionState 切片 / 否→上游 issue）。
