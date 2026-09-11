# NativeMLX Pressure Policy Audit — 2026-09-09

## 结论

本轮审计 `NativeMLX.evaluateSystemPressure(activeGenerations:memorySnapshot:)` 及其 Admission 调用链。

结论：当前函数仍属于 **Admission-local pressure policy**，不是 Restart Authority，暂时不能删除；但其内部已经混入了三种不同维度的经验阈值，并且没有完全遵守 `RuntimeTuning` 的“调优常量集中管理”边界。

Runtime source 暂不修改。

## 1. 当前实际调用位置

`evaluateSystemPressure()` 当前只在 Admission hard limit 超过后使用：

```swift
if projectedMemory > admissionLimit {
    let activeGenerations = state.withLock { $0.activeGenerationTasks.count }
    let severePressure = evaluateSystemPressure(
        activeGenerations: activeGenerations,
        memorySnapshot: admissionMemorySnapshot
    )

    if projectedMemory <= softAdmissionLimit && !severePressure {
        // soft allow
    } else {
        // reject
    }
}
```

因此当前语义是：

```text
Projected Memory > hard admission limit
        ↓
Pressure probe
        ↓
severe = true/false
        ↓
决定 soft allowance 是否可用
```

没有证据表明它直接触发 restart、cancel、suspend 或 Physical KV eviction。

## 2. 当前 pressure predicate 实际包含三个维度

```swift
if let swapUsed = memorySnapshot.swapUsedBytes,
   swapUsed > 1 * 1024 * 1024 * 1024 {
    return true
}

if activeGenerations >= 3 {
    return true
}

if memorySnapshot.residentGB > 28.0 {
    return true
}

return false
```

即：

```text
Swap pressure       > 1 GiB
Execution pressure  >= 3 active generations
RSS pressure        > 28 GiB
```

这三个条件不是同一种事实：

- Swap 是 OS memory-pressure evidence
- activeGenerations 是 runtime execution concurrency evidence
- RSS 是 process resident-memory evidence

当前用一个 Bool 合并三者，只适合回答一个局部问题：

> “当前是否不适合继续使用 experimental soft admission allowance？”

不能把这个 Bool 向上升级成通用 `MemoryPressureLevel` 或 restart predicate。

## 3. 重要：Swap > 1 GiB 不能与 Service 的 Swap Restart 混淆

当前 NativeMLX admission policy 使用：

```text
swap > 1 GiB → severePressure = true
```

而 Service 当前错误的 GGUF restart policy 使用：

```text
swap > 2 GiB → forceRestart()
```

两者语义完全不同：

```text
NativeMLX swap evidence
    ↓
禁止 experimental soft admission
```

而错误的 Service path：

```text
GGUF swap evidence
    ↓
restart
```

因此未来删除 `swap > 2 GiB → restart` 时，不能顺手删除 NativeMLX 的 `swap > 1 GiB`。

后者目前仍有 Admission policy 证据。

## 4. 三个阈值目前存在 Policy 与 Tuning 混合

`RuntimeTuning.swift` 已经集中定义：

- admission hard limit = 22 GiB
- soft allowance = 2 GiB
- emergency reserve = 1 GiB
- execution working set = 3 GiB
- safety margin = 1 GiB
- OS reserve = 3.5 GiB
- estimated KV bytes/token = 128 KiB

但 `evaluateSystemPressure()` 自己又直接硬编码：

```text
1 GiB swap
3 active generations
28 GiB RSS
```

这造成两个问题：

### A. 调优参数散落

如果这些阈值需要 Benchmark 校准，应进入 `RuntimeTuning`，否则违反“调优常量集中定义”的现有架构意图。

### B. Core 与 Policy 边界不清

Core 应该知道：

```text
pressure can deny a soft admission path
```

但不应该把：

```text
1 GiB
3 generations
28 GiB
```

固化成 Core invariant。

## 5. `28 GiB RSS` 特别需要 Benchmark 证明

Admission hard limit 当前最高为 22 GiB：

```text
admissionLimit <= 22 GiB
```

但 pressure predicate 又使用：

```text
RSS > 28 GiB → severe
```

这不是逻辑错误，因为 projected admission memory 与当前 process RSS 不是同一量；但必须明确它们的关系：

```text
Projected Memory
    = KV projection + working set + safety margin + ...

RSS
    = actual process resident memory
```

所以 28 GiB 只能作为 empirical pressure signal，不能被解释为“Runtime 最大内存 28 GiB”。

当前没有足够证据把 28 GiB 升格为 Core invariant。

## 6. `activeGenerations >= 3` 同样是 Policy，不是 Core

`activeGenerationTasks.count` 是 Runtime execution ledger，可以保留。

但：

```text
>= 3
```

是 policy threshold。

它依赖：

- 并发模型
- Apple Silicon memory capacity
- model size
- generation shape
- KV residency
- execution working set

因此不能形成类似：

```text
Core invariant: activeGenerations < 3
```

正确边界应是：

```text
Core:
    activeGenerationTasks is execution truth

Policy:
    activeGenerationTasks.count contributes to pressure assessment
```

## 7. 当前 `Bool severePressure` 暂时可以保留

当前调用方只需要一个局部答案：

```text
soft admission allowed?
```

所以：

```swift
Bool severePressure
```

暂时没有足够理由为了抽象而立即改成：

```swift
enum MemoryPressureLevel
```

更合理的演进顺序是：

```text
Benchmark / experiments
        ↓
确认三个 pressure signals 的实际价值
        ↓
统一 threshold placement
        ↓
如果多个 subsystem 真正需要共享 pressure semantics
        ↓
再提升为 MemoryPressureLevel / GovernanceDecision
```

避免为了“架构漂亮”提前增加抽象层。

## 8. 与 Memory Governance 的最终边界

最终建议保持：

```text
RuntimeMemoryProbe
       ↓
Observation
       ↓
NativeMLX Pressure Policy
       ↓
Admission Decision
```

而不是：

```text
RuntimeMemoryProbe
       ↓
Pressure
       ↓
Restart
```

Restart 必须经过独立的：

```text
MemoryRestartDecision
```

并满足 activity / lifecycle / backend capability 等条件。

## 9. KEEP / P2 / P1

### KEEP

- `RuntimeMemoryProbe`
- `activeGenerationTasks`
- `evaluateSystemPressure()` 当前 Admission-local 角色
- Swap/RSS/execution pressure 三类 evidence
- hard admission + soft admission 的现有结构

### P2 policy cleanup

如果 Benchmark 证明这些阈值仍需要长期存在：

- 将 1 GiB swap pressure threshold 移入 `RuntimeTuning`
- 将 3 active-generations threshold 移入 `RuntimeTuning`
- 将 28 GiB RSS threshold 移入 `RuntimeTuning`
- 为三个阈值分别记录 Benchmark / Experiment 证据

如果实验最终证明某一 signal 没有预测价值，再删除该 signal，而不是先删除整个 pressure predicate。

### P1

本轮没有发现新的 P1 runtime bug。

已有 P1 保持不变：

- 删除 Service `swap > 2 GiB → forceRestart()`
- `/slots == nil` 必须 fail-closed / recheck
- Restart 不得直接由 pressure evidence 授权

## 10. 审计状态

- Runtime source modified: **NO**
- Service source modified: **NO**
- New deletion candidate: **NO**
- New P1 bug: **NO**
- New P2 policy cleanup: **3 threshold-placement candidates**
- Canonical branch: `audit-candidates-2026-09-09`
