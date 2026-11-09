# 分歧臂实验 V0.1（骨架 §3）

日期：2026-11-08
问题：论文说“零调用不等于可复用”。需要一次读数把两条零调用路径分开，并给出朴素键缓存在同一上游变更下的对照。
代码基线：schema v23，契约测试 286/286。

## 装置

`Packages/SimiGoRuntime/Tests/SimiGoRuntimeContractTests/SimiGoESISArmsTests.swift`

两臂都直接调用 HTTP 路径使用的同一组函数，不经过测试专用装配：

- Arm A：`resolve → settleTurn → resolve → reusableAnswer → recordInformationReuse`
- Arm B：`settleWorkRootContents → resolve → settleTurn → 改文件 → settleWorkRootContents → resolve`

## 命令与原始输出

```
swift test --filter SimiGoESISArmsTests

ARM_A reuse_hit=1 model_calls=0 settlements_delta=0 states_delta=0 consumptions_delta=0 source=08E1DD8E
ARM_B naive=stale_silent:5.6 product invalidated=2 new_demand=3cbff273 fresh=7.2
```

## 读数表

| 臂 | 模型调用 | 结算增量 | 执行状态增量 | 消费行增量 | 上游变更后读到 |
|---|---|---|---|---|---|
| A 直出复用 | 0（`information_reuse_events.model_calls`） | 0 | 0 | 0 | 返回原文本，事件行 1 条 |
| B 朴素键缓存 | 1（首次，模拟） | — | — | — | **陈旧的 5.6，无标记** |
| B 产品路径 | 0（第二次 resolve 不调模型） | +1 检索结算（新 demand） | 0 | 0 | **7.2；旧检索结算与旧答案结算同时 invalid** |

## 这组读数支持什么

1. **P4（结构判别）**：两条路径的计数器都是 0。区别在行的种类——A 只有复用事件、无结算；消费臂有 `settlement_consumptions` 行且 `model_calls` 受 `CHECK(=0)` 约束。计数器本身分不开，schema 分得开。
2. **P2（恢复是重判）**：同一查询、同一文件，朴素缓存返回旧值且静默；产品路径把旧结算判 invalid 并产生新 demand，读到新值。差别来自“重判”这一步，而不是缓存键的设计。
3. **P1（单位是结算）**：直出复用没有诞生结算，也没有建执行状态；知识以结算为单位存在，不以会话状态为单位复制。

## 不主张的事

- **不是 LLM 基线**：Arm B 的“第一次调用”是读文件，不是模型调用。它检验的是机制差异，不检验模型输出分布。
- **不计时**：本轮不给延迟区间，也不与既有 11 对试验合并样本。
- **只覆盖 file 命中路径**：chat 与采集桥路径的失效传播不在本轮。
- **单机单库**：一条 SQLite 文件，一次串行执行；并发行为由既有测试覆盖，不由本实验覆盖。

## 复现

```
cd ~/Documents/SimiGo-new-root/Packages/SimiGoRuntime
swift test --filter SimiGoESISArmsTests
```

断言失败即实验失败；两行 `ARM_A` / `ARM_B` 是打印读数，不是断言本身。
