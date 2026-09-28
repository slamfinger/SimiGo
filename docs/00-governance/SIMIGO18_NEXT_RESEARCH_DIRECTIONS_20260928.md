# SimiGo 下一阶段预研方向：Llama Backend × Execution State 物理存储

日期：2026-09-28
状态：RESEARCH OPEN / CODE AUDIT FIRST
关联基线：FORK-3 STEP-10 已完成；不得重新打开已关闭的 FORK-3。

## 1. 总目标

两个独立但最终可汇合的预研方向：
1. BACKEND-1 — Llama Backend Adapter：研究 Llama 接入现有 Execution Runtime 的最小、稳定、可扩展边界。
2. PALACE-1 — Execution State Physical Storage：研究 Execution State 物理持久化，即“宫殿记忆数据库”的可行性，并为局域网及远端大模型预留用户接口。

核心路线必须首先服务日常小规模 Execution State：低存储开销、低序列化成本、低恢复延迟、低运行时管理成本。超规模不是默认路径，而是同一核心路线的验证、压力场景和技术亮点。

## 2. 已冻结的架构前提

Execution → RepresentationRef → backend-specific physical representation

Execution 是逻辑运行实体，不暴露 MLX/Llama 物理实现；RepresentationRef 描述可绑定、可定位、可验证的表示；KV/cache/backend artifact 属于后端及其 Representation Store。

Execution State 与物理 Representation 可以拥有不同的一致性边界。当前 MLX 是第一种 backend-specific representation，不应被提升为全局 Execution State 模型。

## 3. 首要目标：小规模 Execution State

代码审核必须首先回答：普通会话需要持久化哪些最小状态；哪些状态可留在内存；恢复普通 Execution 是否无需扫描大型 artifact；fork/resume/delete 是否保持低固定开销；数据库事务是否只覆盖逻辑状态而不强行包住大型 KV artifact。

优先目标：小状态、少 IO、少复制、少锁、快速恢复。

## 4. 超规模定位

超规模必须与小规模共享同一逻辑模型，而不是另建一套架构。重点验证大 transcript、大 Representation artifact、oversized execution、LAN/remote backend、artifact 与逻辑状态分离后的恢复与一致性，以及索引、分页、分层存储和并发访问。

超规模成功后形成技术亮点，但不得为了超规模提前把日常路径数据库化、对象化或远程化，造成默认开销。

## 5. 两条研究线

BACKEND-1：Execution Runtime → Backend Adapter → Llama Runtime；同时保持 Execution → RepresentationRef → Llama-specific Representation。

PALACE-1：Execution State Store 管理 logical state；Representation Store 管理 physical artifact。候选包括 SQLite、SQLite+blob/file、append-only event log + SQLite index、embedded KV、LAN/remote state service、object-storage-style artifact。

暂不锁定最终数据库产品或 API。

## 6. 多轮代码级审核

Audit-1：盘点 Execution、ChatSession、NativeMLX、PrefixPool、Lineage、HTTP API、OversizedRuntime、持久化代码真实边界。
Audit-2：审核小规模热路径的创建、append、resume、fork、delete、restore 固定成本与 IO。
Audit-3：审核 Execution State 与 Representation artifact 的一致性边界及失败恢复。
Audit-4：审核 Llama seam，防止 MLX 特性泄漏到公共 Execution API。
Audit-5：用 oversized、大 transcript、remote artifact 验证同一逻辑模型。
Audit-6：回归审核，确保支持超规模、Llama、LAN/remote 不增加日常默认开销。

## 7. 第一阶段不做

- 不重新打开 FORK-3 已关闭 Gate。
- 不提前实现 usage projection / disk GC 两个已延期候选。
- 不立即锁定 Palace DB 最终产品。
- 不立即把 KV cache 做成通用数据库。
- 不立即把本地 Execution State 默认远程化。
- 不因为支持 Llama 而重写成熟 MLX 路径。

## 8. 下一步

先代码级审核，不直接写生产代码：审核 Execution Runtime / ChatSession 状态边界；session checkpoint 与 Lineage；PrefixPool / RepresentationRef 持久化边界；HTTP API 的本地/LAN/remote 接口潜力；形成 BACKEND-1 与 PALACE-1 的接口和数据模型候选。

本文件作为两个方向的总入口和治理约束。