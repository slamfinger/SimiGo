# SIMIGO17 — STEP-10: forkSessionBranch API 插件决策（登记）

> **ARCHIVED** 2026-10-20 · line: 通用治理 / 其他 · original: docs/00-governance/SIMIGO17_FORK_SESSION_BRANCH_PLUGIN_DECISION_20260928.md
> Evidence status: unchanged (content frozen; moved only)


- 日期：2026-09-28
- 状态：`DECIDED / IMPLEMENTED_THIS_CUT`
- 前置：F3_DEVICE_ACCEPTANCE=PASSED；step-8（Binding 类型化）、step-9
  （daily-path Binding wiring）已落地；`UPSTREAM_BACKUP_ON_FORK` 已裁定
  （上游原语路线终止，共享前缀经济性唯一机制 = admission 层 poolBind）。

## 1. 决策对象

`forkSessionBranch`（BranchFork v1：saveCache → 复制 → loadCache 的
agent 面 checkpoint fork）与 FORK-3 产物（RepresentationRef /
ExecutionBindingRegistry / 池边界）之间的关系。

## 2. 裁定

**R1 层级不变**：`forkSessionBranch` 保持 checkpoint-fork 层（复制
语义、覆盖语义、选边提升流程全部不变）。「分支 checkpoint fork」与
「Execution State 共享前缀 fork」的术语两分红线不破；共享前缀经济性
继续只存在于 admission 层（poolBind），不进入本 API。

**R2 FORK-2 落地（fork 点持久化）**：branch metadata 增加
`forkPoint { sourceStorageKey, atMessage, atToken }`（可选字段，
decodeIfPresent 向后兼容）。fork 时写入 target 分支 metadata；
`atToken` 取 fork 时 source 活会话的 token ledger 数。

**R3 绑定登记（registry 插件）**：fork 时 child 在
ExecutionBindingRegistry 绑定该 checkpoint 的 RepresentationRef
（`kind = .residentKV`，contentHash = target meta.json 字节 SHA256
截断，boundLength = atToken）。**不绑 parent**：parent 对池边界的
活跃绑定不得被 supersede（B-R2 单活跃行；checkpoint 是 parent 的
自有存档，不改变其表示关系）。fork 关系 = child 行 + 既有
lineage.recordFork 日志。

**R4 FORK-1 落地（原子替换）**：目标文件先落临时名再原子 rename/
replace，消除 delete→copy 的崩溃窗口。

**R5 明确不做**：不做零复制（上游原语路线已由 UPSTREAM_BACKUP_ON_FORK
终止）；不改 save/load 公开 API 面；不把 forkSessionBranch 变成
poolBind；usage projection 与 disk GC 维持 deferred。

## 3. 验证计划

- BranchForkTests 全绿（生产协议 + 所有权 + 往返）；
- 新增断言：fork 点已持久化进 target metadata、registry 出现
  child 的 .residentKV 绑定行；
- F3 真机电池不回归（本 API 与 admission 层无共享状态）。
