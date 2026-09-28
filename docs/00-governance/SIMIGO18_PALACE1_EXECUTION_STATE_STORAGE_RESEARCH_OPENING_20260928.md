# PALACE-1 — Execution State Physical Storage Research Opening

日期：2026-09-28
状态：RESEARCH OPEN / AUDIT FIRST

## 目标
研究 Execution State 的物理持久化，即“宫殿记忆数据库”的可行性，并为局域网及远端大模型预留用户接口。

核心原则：Execution State ≠ Physical Representation Artifact。

研究模型：
Palace / Execution State Store
├─ Execution metadata
├─ transcript / message state
├─ lineage / fork point
├─ RepresentationRef
├─ backend / model identity
└─ artifact locator

实际 KV/cache/model artifact 继续由对应 Representation Store 管理。

## 首要目标：日常小规模
- 小记录体积
- 低序列化/反序列化成本
- 低 IO
- 快速 resume
- 快速 fork
- 快速 delete
- 不因未来超规模能力承担额外常驻开销

## 超规模验证
使用大 transcript、大 artifact、oversized execution、LAN/remote backend 验证同一 Execution State 模型的扩展性；重点验证分层/分页、artifact locator、索引、一致性、崩溃恢复、GC、网络失败、多进程/多节点访问。

## 候选存储路线
1. SQLite
2. SQLite + blob/file artifact
3. append-only event log + SQLite index
4. embedded KV database
5. LAN/remote Execution State service
6. object-storage-style representation artifact

暂不做最终选型。

## 用户接口方向
local UI / CLI / HTTP / gRPC
↓
Execution State API
↓
ExecutionStateStore
↓
Backend / Representation Store

接口首先由代码级审核驱动，不提前锁死 API。

## 必答问题
1. Execution 的最小持久化单元是什么？
2. transcript 是否完整存储，还是事件化/分段化？
3. fork point、lineage、binding 如何持久化？
4. RepresentationRef 是否持久化，而 ExecutionBindingRegistry 是否保持 execution-scoped runtime state？
5. logical state 与 physical artifact 的一致性边界是什么？
6. 普通小规模路径最低 IO/CPU/内存成本是多少？
7. 超规模路径如何扩展而不污染默认热路径？
8. LAN/remote 如何建立在同一逻辑状态模型上？

## 第一阶段边界
不立即实现数据库；不把 KV cache 变成通用数据库；不默认远程化；不重新打开 FORK-3。先完成多轮代码级审核和技术矩阵。