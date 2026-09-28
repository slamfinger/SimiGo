# SimiGo Beta 首发技术路线审计门槛

日期：2026-09-28  
状态：RELEASE GATE / AUDIT NOT STARTED  
对象：现有 Beta 版本真实代码

## 1. 任务定位

本文件定义的是 **Beta 首发前的独立发布门槛任务**，不属于 BACKEND-1 或 PALACE-1 下一阶段架构预研。

目标只有一个：

> 在 Beta 首次发布前，通过多轮代码级审核与必要的实机/性能证据，确认现有核心技术路线完整、正确、可恢复、可持续运行，核心技术指标达到发布要求；不得把核心路线上的 P0/P1 问题以“后续优化”带入首发。

## 2. 审计对象

审计对象是当前 Beta 已实现代码，而不是未来架构设计。

重点包括：

- Execution / ChatSession 生命周期
- Execution State 的真实边界与生命周期
- checkpoint / save / load / restore
- fork / resume / delete
- Lineage / fork point
- RepresentationRef / ExecutionBindingRegistry
- PrefixPool / KV representation
- HTTP / OpenAI-compatible 入口
- OversizedRuntime
- 错误、取消、崩溃恢复与一致性
- 小规模默认热路径的 CPU / 内存 / IO / 延迟成本
- 超规模场景对同一核心路线的验证

## 3. 审计原则

### 3.1 小规模优先

普通日常 Execution 是 Beta 默认路径。

必须证明其：

- 固定管理开销低
- 不发生不必要的大对象复制
- 不发生不必要的全量扫描
- 不承担超规模场景才需要的常驻成本
- resume / fork / delete 等生命周期操作具有可接受的固定成本

### 3.2 超规模验证

超规模不是第二套架构。

使用大 transcript、大 artifact、oversized execution 等场景验证：

> 同一个 Execution State 核心模型能否自然扩展。

超规模中的性能亮点属于加分项，但不能通过污染默认小规模路径换取。

### 3.3 多轮代码级审核

不是一次性架构评审。

至少按以下方向逐轮推进：

1. **结构审计**：真实状态边界、所有权、生命周期。
2. **生命周期审计**：create → append → resume → fork → restore → delete。
3. **一致性审计**：Execution State 与 Representation artifact 的边界、失败窗口、恢复。
4. **性能审计**：小规模热路径固定成本与关键指标。
5. **超规模审计**：大状态、大 artifact、oversized 场景。
6. **回归审计**：修复后重新验证核心路线没有退化。

每轮都必须以真实代码和可复现证据为依据。

## 4. 首发门槛

首发前至少满足：

- 核心 Execution State 路线闭环；
- P0 = 0；
- 核心路线相关 P1 = 0，除非已经明确证明不影响首发核心能力且单独记录为非阻断项；
- 生命周期与恢复不存在已知未覆盖的核心一致性断点；
- 普通小规模路径达到预设性能/资源指标；
- 超规模验证不能暴露架构级缺陷；
- 关键修复具有测试或实机证据；
- Beta release 与实际依赖、代码、文档一致。

“未来可优化”只能用于非核心、非阻断项，不能用于掩盖核心路线缺陷。

## 5. 与下一阶段架构预研的边界

本任务不要求 Beta 首发前完成：

- Llama Backend 接入；
- Palace / Execution State 数据库最终选型；
- LAN / remote Execution State service；
- 通用 KV 数据库化；
- 其他下一阶段架构扩展。

这些属于独立的：

- BACKEND-1 — Llama Backend Adapter
- PALACE-1 — Execution State Physical Storage

两条预研线可以并行，但不得用未来架构方案替代当前 Beta 的代码审计证据。

## 6. 第一轮启动条件

本任务待本地 agent 当前代码修改完成后立即启动。

启动时以 **agent 完成后的实际 Beta commit / working tree** 为唯一审计对象，不提前基于未完成代码下结论。

第一轮：

> **BETA-AUDIT-1 — Execution State / Lifecycle / Persistence Boundary Audit**

首要输出：

- 真实代码路径图；
- Execution State 最小状态集；
- 生命周期状态机；
- checkpoint / Lineage / Binding / PrefixPool 关系；
- 已知一致性窗口；
- 小规模热路径成本点；
- P0/P1 候选问题清单；
- 下一轮审计入口。

## 7. 状态

当前：

**RELEASE GATE OPEN — WAITING FOR LOCAL AGENT**

BACKEND-1 / PALACE-1：

**RESEARCH OPEN — INDEPENDENT TASKS**
