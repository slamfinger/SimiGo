# SimiGo 既有实验 → Research Question 证据映射（2026-09-22）

> 性质：回溯性研究整理，不是事后把历史实验改写成预注册实验。

## 1. 方法纪律

本文件只做三件事：
1. 从现有证据中识别已经实际提出并回答的问题；
2. 区分 Observation / Finding / Decision，避免把决策文件当成独立证据；
3. 标记哪些问题已经有足够证据，哪些仍属于 Open Problem。

不补造不存在的 Q1/Q2/Q3/Q4 编号，也不把历史实验追认成当时已经完成的研究注册。

## 2. 研究问题族

### RQ-A：官方缓存语义能否解释长上下文分叉与 rebuild？

真实 90K 长上下文 Agent 任务中，13/28 完成轮次出现 cacheEff=0.00。源码审计闭合了机制链：生成 token 账本与冷模板渲染在工具调用处发生 token-prefix 分叉；Qwen3.5 混合架构 GDN 状态不可回卷，因此 rewind 被拒绝并退化为 rebuild。

主要证据：
- docs/experiments/FIELD_OBSERVATION_20260913_LONG_CONTEXT_TASK.md
- docs/experiments/OFFICIAL_CAPABILITY_MATRIX.md
- docs/experiments/jsonvalue-roundtrip-repro.swift
- 相关上游源码审计记录

边界：这是所测试版本、模型和生产任务的机制解释，不是对所有 MLX 模型或未来版本的普遍结论。

### RQ-B：取消能否保持 session 的正确复用资格？

证据显示，“取消不得提交半成品 history”不足以保证 session 可复用安全。新建 session 在 prefill 未成功完成即取消时，必须阻止其进入可复用状态；poisonedSessionEvict 的最小修复经真机对照验证。

主要证据：
- docs/lessons/cancel-mid-prefill-poisoned-session-2026-09-17.md
- 对照 trace
- 2026-09-17 真机回归

边界：rawEv=0 目前只是诊断辅助判据；正式 readiness 状态机仍是后续研究项。

### RQ-C：当前 MLX/MLXLMCommon 是否提供真正的 Execution Fork 原语？

F0 探针回答：在所测试版本与模型条件下，公开 API 没有 sequence identity / shared-prefix primitive。KVCache.copy() 是独立数据复制语义；磁盘 checkpoint fork 可工作但有明确复制成本。因此真共享 fork 保持在上游依赖研究轨。

主要证据：
- docs/experiments/EXECUTION_FORK_F0_PROBE_20260918.md
- docs/experiments/EXECUTION_FORK_F0_PROBE_RESULTS_20260919.md
- docs/research/questions/Q_FORK_AND_UPSTREAM_SEMANTICS_20260922.md
- docs/decisions/V15_ENDGAME_DECISION_20260919.md

边界：F0 不能证明未来 upstream 不会提供该能力。

### RQ-D：协议输入异常能否在 Runtime 层形成全局故障？

2026-09-19 的复现最终定位到 tools:null：旧代码把 NSNull 强制送入 JSONSerialization，触发 Swift try? 无法捕获的 ObjC exception，并表现为服务全局冻结。最小类型守卫修复后 Release + 10K runtime matrix 完整回归通过。

主要证据：
- docs/lessons/incident-app-crash-and-server-hang-2026-09-19.md
- docs/experiments/V17_RUNTIME_MATRIX/

边界：这是已确认的 tools:null 路径，不等价于所有 HTTPServer freeze 都来自协议解码。

### RQ-E：生产长上下文的主要成本来自哪里？

现场任务中 28 个完成轮次有 13 轮 cacheEff=0.00，重复 prefill 约占该任务 wall time 六成。该证据支持当时“先解决缓存稳定性，再讨论局部 decode 优化”的工程优先级。

边界：单任务、特定模型/硬件/版本，不构成跨模型性能排名。

## 3. 证据族与独立性

目前可区分的证据族包括：
- 上游公开语义 / 源码审计；
- SimiGo 真机运行证据；
- 受控实验；
- 历史架构审计。

历史架构审计与生产运行证据存在重叠，不能仅凭文档不同就计作独立参与者。

继续维持 PARTICIPANT_INDEPENDENCE_20260922.md 的保守结论：不能宣称四个独立渠道已经成立。

## 4. 当前主链

现场观察 / 源码审计 / 受控实验
→ Evidence
→ Finding
→ Principle / Invariant
→ Decision / Architecture

典型闭环：
- 长上下文 cache miss → 官方语义源码闭环 → Official Semantics First；
- F0 fork 探针 → public API capability gap → Fork 留在上游研究轨；
- cancel-mid-prefill → readiness 缺口 → session lifecycle invariant；
- tools:null freeze → protocol boundary 类型异常 → 最小边界修复，而不是增加 runtime 大机制。

## 5. 尚未关闭的问题

1. 上游是否会提供 sequence identity / shared-prefix 原语；
2. session readiness 是否应从诊断判据升级为显式状态协议；
3. Qwen3.5 上游协议拼接规则的最终修复及其长期影响；
4. 长上下文 cache miss 在更多模型 / 任务中的可重复性；
5. 当前研究问题是否覆盖 V4.5 → V5.0 的全部关键架构转折。

这些应继续作为 Open Problems，而不是通过补写历史文档强行闭合。
