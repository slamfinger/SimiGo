# V1.6 Final Baseline 封存记录（2026-09-19）

**基线提交**：`7aced19`（= tag `v1.6`，git describe exact-match 核实）
**发布物**：[Release v1.6](https://github.com/slamfinger/SimiGo/releases/tag/v1.6)
DMG SHA256（前 128bit）：`f4db058658fd5a4256a8cbeac206fb88`
**构建配置**：Release / MARKETING_VERSION 1.6 / TeamIdentifier YPXU8M53F9
**依赖**：mlx-swift-lm `dc3ca6197171` / mlx-swift `0.31.6`（与 v1.5 一致）

## 基线测试（封版当日实测）

```
xcodebuild test（SimiGoTests 全量，macOS）
Executed 72 tests, with 5 tests skipped, 0 failures (0 unexpected)
```

5 项门控跳过 = 需真机权重/环境变量（SIMIGO_FORK_EXP / SIMIGO_ROLLFWD_EXP /
SIMIGO_LIFECYCLE_RACE），另可按需执行。

## 基线内容速览

- Runtime 行为与 v1.5 零回归（S1–S5 每片零行为变更验收）
- 新增能力：ExecutionID 遥测 / ExecutionPolicy 判定边界 /
  ConditionalRestoreConfiguration 单请求快照 / ExecutionControlling
  五动作协议面 / ExecutionLineage 血统日志
- 证据：docs/audit/EXECID_TEST_QUALITY_REVIEW_2026-09-19.md（九~十二轮）

## 后续路径指针

V1.7 方向登记：`docs/decisions/V17_DIRECTION_REGISTRATION_20260919.md`。
V1.6 基线冻结后不再加功能；一切 V1.7 实验以本基线为对照参照系。
