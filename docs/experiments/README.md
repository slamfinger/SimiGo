# 实验记录

这里记录尚未进入核心架构的方案、原型和验证过程。

实验的目的不是证明方案一定正确，而是用最小成本回答具体问题。

## 推荐流程

```text
假设
 ↓
最小原型
 ↓
真实硬件验证
 ↓
正确性测试
 ↓
性能测量
 ↓
结论
```

实验成功也不意味着自动进入 Core。

必须经过架构评审，并在需要时形成架构决策。

## 特别说明

Batch、Paged KV、连续服务、推测解码等能力，在没有完成正确性与性能验证之前，应保持在实验层，不得反向污染核心架构。

## 演进路线图

- [EVOLUTION_TRACK.md](EVOLUTION_TRACK.md) —— S1 Controlled Batched Execution → S2 Paged/Block KV + Radix Prefix Cache → S3 Continuous Serving + Speculative 的完整路线（已归档）。含：总体演进原则（守正/精简）、演进纪律管道、各阶段准出标准、Hybrid/Mamba NO-GO 结论、**第二十章 对优秀开源实现的借鉴边界**（mlx-lm / llama.cpp / vLLM / SGLang 各自借鉴什么）、**第二十一章 明确"不照搬"**（不复制 CUDA kernel / Python runtime / C++ 内存架构，把成熟 Serving 思想重映射到 Apple Silicon + MLX + Swift）、**第二十二章 稳定 DMG 发布纪律**。
