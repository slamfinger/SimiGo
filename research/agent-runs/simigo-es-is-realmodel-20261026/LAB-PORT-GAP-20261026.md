# Lab→产品移植缺口：ES→IS→执行器「权威桥」从未进入产品模块

取证时间：2026-10-26 19:56–19:58（本轮）。
代码基准：产品仓 `main` HEAD `97043902075b67eb1693749fd6ed50421eccf3ba`（`git log -1` 实读），构建/二进制身份见同目录 `ACCEPTANCE-20261026-BUILD-97043902.md` 第 0 节（安装版 `/Applications/SimiGo.app`，pid 83135）。
方法：源码 grep（限定产品目录，排除 `research/` 与 `.build/`）+ `git ls-files` + 对安装二进制 `nm -U`。全部为静态代码事实，可复核（命令见第 7 节）。

本节把审查报告的 P0 从「测不到避免计算」收敛到「实现层面缺少哪一块」，并**修正**审查报告 P0-2 的定位。

---

## 1. 事实：产品 App 确实链接了 `SimiGo2Experimental`，但只用了其中一部分

产品 `SimiGo/` 里 `import SimiGo2Experimental` 共 4 个文件：

- `SimiGo/Inference/NativeMLXPrefixPool.swift`
- `SimiGo/Inference/NativeMLX.swift`
- `SimiGo/Inference/OversizedRuntime.swift`
- `SimiGo/Headless/SimiGoG1G3Entry.swift`

这 4 个文件引用的该模块类型（按出现次数）：`NativeMLXPrefixPool`(12)、`RuntimeLifecycleCoordinator`(9)、`SimiGoRuntimeCachePaths`(5)、`OversizedRuntime`(4)、`PrefixPoolNamespace`(3)、`SimiGoRuntimeContract`(2)、`LOCALBPairingCoordinator`(2)、`LOCALBHostRuntime`(2)、`SessionGenerationGate`(1)、`RuntimeLifecycleGate`(1)、`ExecutionStatePrefixPool`(1)。

即：模块是活的，产品用的是**前缀池 / 常驻 / 运行时**这一支。

## 2. 事实：`MLXPrefixRecomputeExecutor`（研究用的续跑执行器）在产品源码树里零调用者

在 `SimiGo/`、`Packages/`、`SimiGoTests/`（排除 `.build/`）中，除定义文件自身外，对 `MLXPrefixRecomputeExecutor` 的引用只有一处，且仍在实验模块内部：

- `Packages/SimiGoRuntime/Sources/SimiGo2Experimental/MLXExecutionStateBackend.swift:14`（注释提及）
- `Packages/SimiGoRuntime/Sources/SimiGo2Experimental/E5ExecutionStateScenario.swift:90`（构造）

而 `E5ExecutionStateScenario` 在产品侧（`Packages/` 源码与测试、`SimiGo/`、`SimiGoTests/`）除自身定义（`:62`）外无任何引用；它唯一的调用者是 lab 归档里的 CLI：`research/lab/simigo2-experimental/Sources/simigo2ctl/Simigo2CTL.swift:256`。

同时，安装二进制里该类型是有代码的：`nm -U /Applications/SimiGo.app/Contents/MacOS/SimiGo | grep -c PrefixRecompute` = **106** 个符号（含 `continueExecution`、`tokenizeText`、`tokenizeSeedText` 的地址级符号 `T`/`t`）。

→ 结论（基于以上两条事实）：**链接进产品、但产品入口链不可达**。它是随 target 一起编进二进制的研究代码，不是产品功能。

## 3. 事实 + 修正：审查报告的 P0-2 逐行成立，但它不在产品真机链路上

审查报告称 `continueExecution` 用 `context.model(running, cache: nil)` 重算完整前缀。在产品文件中确认：

- `Packages/SimiGoRuntime/Sources/SimiGo2Experimental/MLXPrefixRecomputeExecutor.swift:72` `public func continueExecution(`
- `Packages/SimiGoRuntime/Sources/SimiGo2Experimental/MLXPrefixRecomputeExecutor.swift:85` `let logits = context.model(running, cache: nil)[0, -1]`

**修正定位**：该文件在产品中无调用者（第 2 节），所以它不是产品「重复计算」的实际成因；把它当作 P0 会引向错误的修法（改 `cache:` 参数不会改变任何产品行为）。产品真实续跑路径的 KV 复用是 token 链前缀哈希池（`NativeMLXPrefixPool.swift`，键公式与机制见 `IS-KV-WIRING-GAP-20261026.md` 第 1 节），与 IS 结算无关。

## 4. 事实：lab 的「IS 是恢复权威」桥接层根本没有被移植进产品

lab 侧承担核心命题的桥接文件：`research/lab/simigo2-experimental/Sources/SimiGo2Experimental/ProductionRuntimeInformationIntegration.swift`

- `:20-22` 注释即研究主张本体：*The Information Space holds no settled (ADVANCED) execution state, so it cannot authorize recovering an ES. **IS is the recovery authority**: without a settled result there is nothing legitimate to resume.*
- `:34` `case settlementCheckpointMissing(executionID:)` — IS 已授权但 ES 无结算检查点 → 拒恢复
- `:40` `case settlementCheckpointMismatch(executionID:field:)` — 检查点与 IS 当前结算状态分歧 → 在任何新副作用前拒绝
- `:56` `public protocol ProductionRuntimeModelContinuationExecutor: Sendable`（`tokenizeText`/`tokenizeSeedText`/`continueExecution`）
- `:66` `extension MLXPrefixRecomputeExecutor: ProductionRuntimeModelContinuationExecutor {}` ← 把执行器接到 IS 权威上的那一行
- `:79-85` 结算动作记录带 `settlementObjectID`，注释明确目的是让后续阶段能证明复用**同一条**已结算记录

该产品文件**不存在**：`Packages/SimiGoRuntime/Sources/SimiGo2Experimental/` 目录里没有 `ProductionRuntimeInformationIntegration.swift`。
`git ls-files | grep ProductionRuntimeInformationIntegration` = 9 条路径，**全部以 `research/` 开头**（lab 源码 + lab 测试 + agent-runs 快照/diff），一条都不在产品源码树。

产品源码（`SimiGo/` + `Packages/*/Sources/`）中 grep `settlementCheckpoint` / `SettlementProvenance` / `DurableExecutionStateStore` = **0 命中**。

→ 结论：产品里**没有任何代码**用 IS 结算去授权、校验或驱动模型状态恢复。审查报告说的「IS 能保存与验证结果，不等于执行器能消费它」，比报告写得更硬：消费侧的桥在产品里不存在。

## 5. 事实：合并是「归档整仓 + 精选部分文件」，精选漏掉的正是这条链

`Sources/SimiGo2Experimental/` 文件数：lab 92 → 产品 67。lab 有而产品没有的 25 个顶层文件中，与核心命题直接相关的是：

| 未移植文件 | 它承载什么 |
| --- | --- |
| `ProductionRuntimeInformationIntegration.swift` | IS 作为恢复权威 + 结算检查点 fail-closed（第 4 节） |
| `SettlementProvenanceVerification.swift` | 复用必须指向同一结算对象的溯源验证 |
| `DurableExecutionStateStore.swift` | 持久 ES 句柄（恢复的另一半） |
| `NativeCarrierLifecycle.swift` | 载体退役/墓碑语义（=「旧 KV 释放」的产品化表达） |
| `MLXPrefixCrossSessionCache.swift` / `MLXPrefixSnapshotLoader.swift` | 跨会话前缀缓存与快照装载 |
| `PersistentSRSRepresentation.swift` / `TypedRepresentationPayloadPersistence.swift` | 表示（SRS）持久化与类型化载荷 |
| `G3PerArmKVCache.swift` / `G3KVAllocationGateway.swift` / `G3MLXRuntimeResourceProbe.swift` | G3 双臂 KV 释放/持有与资源探针 |
| `RepresentationConsistencyBoundaryExperiment.swift` / `CanonicalPrefill*.swift` / `F1*`/`F3*` | 表示一致性、前计量与收益协议 |

这与用户既有判断一致：lab 的单项能力「已实现，但没连接落地」——而且此处不是「没接线」，是**代码没进产品模块**。

## 6. 结论与假设（分开陈述）

结论（有第 2、4 节 file:line 支撑）：
1. 核心命题在产品侧未闭合的**根因**是「IS→执行器权威桥未移植」，而非移植后跑不通。
2. 审查报告 P0-2（`cache: nil`）事实成立但定位偏移；产品真实 KV 复用不由 IS 驱动，且 IS 文本注入会破坏 token 链命中条件（`IS-KV-WIRING-GAP-20261026.md`）。第 3 步真机读数（3 次全部 `mode=cold`、`cacheHitTokens=0`）与此一致。

假设（未证实，不得当作结论引用）：
- 把该桥移植进产品后能否真的避免计算，**未知**。lab 侧该桥自身的真实模型证据受 G3 D1 `NO-GO` 限制（`SIMIGO2_G3_D1_ENTRY_BOUNDARY_DECISION_V0.1_20261021.md`），移植 ≠ 验收。
- 两条候选落地路线（均未实施，均需明确授权后改产品代码）：
  A. 移植 `ProductionRuntimeInformationIntegration` 及其 fail-closed 两分支，并把协议接到产品 chat/Responses 入口；
  B. 更小改动：沿用现有 `poolBind`，把 IS 已验证结算的表示身份（`kv.pool_key`/`kv.cache_fingerprint`）作为绑定前置条件，任一不过回退全量 prefill 并记 `isKvBindRejected`（见 `IS-KV-WIRING-GAP-20261026.md` 第 3 节）。
  A 更贴近研究主张（IS 为权威），B 改动面小但仍是「KV 层被 IS 门禁」，不是「IS 存表示」。

## 7. 复核命令

```bash
cd /Users/mr.simi/Documents/SimiGo
grep -rl "import SimiGo2Experimental" SimiGo
grep -rn "MLXPrefixRecomputeExecutor" SimiGo Packages SimiGoTests --include="*.swift" | grep -v "/.build/"
sed -n '70,90p' Packages/SimiGoRuntime/Sources/SimiGo2Experimental/MLXPrefixRecomputeExecutor.swift
git ls-files | grep ProductionRuntimeInformationIntegration
ls Packages/SimiGoRuntime/Sources/SimiGo2Experimental/ | wc -l
comm -23 <(ls research/lab/simigo2-experimental/Sources/SimiGo2Experimental/ | sort) \
         <(ls Packages/SimiGoRuntime/Sources/SimiGo2Experimental/ | sort)
nm -U /Applications/SimiGo.app/Contents/MacOS/SimiGo | grep -c PrefixRecompute
```
