# Qoder Collection 主线整合记录（2026-11-05）

> 本文保存整合提交、候选快照与验证范围的历史事实。当前 package 行为与边界以 [Packages/SimiGoCollection/README.md](../../Packages/SimiGoCollection/README.md) 为准。

## 整合身份

采集桥进入产品主线的提交为 `b3886bb8`（`feat(collection): link the Qoder transcript bridge as an opt-in read-only collector`）：24 个文件、6,292 行新增。构成为 package 17 个文件（Sources 8、Tests 7、另含 Package.swift 与 README）、App 接线 6 个文件（project 与 Config、MenuApp、QoderCollectionLifecycle、Settings、StatusBarCoordinator）及 CI workflow 1 个。

随后 `d53782e6` 只重算 `release-inputs-v2.2.x.json` 与 `release-exclusions-v2.2.x.json`（+78/−6），不含产品代码。

记录时 HEAD 为 `61bf1990`。此前 `556ae91b`（删除三份逐字节重复 retry 报告）与 `61bf1990` 本身均为档案治理提交，不是采集桥提交。

## 候选快照边界

本地 tag `v2.2.4` 指向 `e21d8f7b`，比上述记录 HEAD 落后 17 个提交，**不包含 Qoder collection bridge**。因此该 tag 对应的 build 34 DMG 不能代表包含 `b3886bb8` 的当前主线源码；如要发行含采集桥的版本，必须从包含该提交的最终源码重新构建并重新验收。

## 验证范围

- Package 的 91 条测试通过。
- App 构建与冒烟只支持“新接入 package 未破坏既有路径”的有限结论。
- `Qoder → QoderCollection → 受控生命周期 → ES/IS` 完整运行时链路**尚未端到端验证**。

| 能力 | 当时证据状态 |
|---|---|
| 只读采集、增量重建、持久 inbox | 已整合，package 测试覆盖 |
| 独占 lease、重启恢复 | 已整合，package 测试覆盖 |
| App 生命周期、菜单与开关 | 已整合；默认关闭，XCTest 宿主不启动 |
| 外部 IS 结算判据 | 已吸收（`ccf6ac8a`）；后续云代理退役（`a7e297c9`） |
| 旧云代理转发 | 已退役，不随 package 恢复 |
| 采集候选 → IS 受控消费 | 未接入；collection-only，不写 IS/ES，不启用 RULED_ALLOW / WA / C-policy |

这些记录描述 2026-11-05 的整合检查点，不应被解释为当前 HEAD 的提交计数、发行身份或 E2E 验收。
