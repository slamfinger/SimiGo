# BACKEND-1 — Llama Backend Adapter Research Opening

日期：2026-09-28
状态：RESEARCH OPEN / AUDIT FIRST

## 目标
Llama backend 接入现有 SimiGo Execution Runtime，同时保持 backend-neutral 的 Execution 抽象。

目标关系：
Execution → Backend Adapter → Llama
Execution → RepresentationRef → Llama-specific Representation

## 首轮代码审核
- ExecutionControlling
- ExecutionPolicy
- ChatSession / NativeMLX
- NativeMLXPrefixPool
- OversizedRuntime
- model loading / model identity
- prefill / decode / cancellation / error propagation
- session persistence
- HTTP / OpenAI-compatible entry points

## 必答问题
1. MLX 代码哪些是真正的 Execution 语义，哪些只是 MLX 实现细节？
2. Llama 最小 backend seam 在哪里？
3. backend capability 如何表达 cache、prefill、decode、snapshot、restore 差异？
4. RepresentationRef 如何保持 backend-neutral？
5. 哪些接口同步、哪些异步？
6. cancellation、failure、resource release 如何保持一致？
7. Llama 接入是否增加普通小规模 Execution 默认开销？

## 原则
先找 seam，再设计 API；先代码证据，再抽象。不得为了统一 backend 提前重构稳定 MLX 路径。超规模、LAN、remote 是验证 Adapter 完整性的场景，不是第一阶段默认执行路径。