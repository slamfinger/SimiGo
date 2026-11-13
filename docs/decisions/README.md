# 架构决策索引

本目录保存决策、合同、提案与历史方向登记。**文件位于本目录不代表它仍是当前开发计划**；正文中的日期、状态和证据范围优先于目录位置。本页负责区分状态，不重复正文。

## 当前仍需对照实现的决策 / 合同

- [本地离线 prefill 与取消语义（2026-10-30）](ADR_LOCAL_OFFLINE_PREFILL_AND_CANCEL_20261030.md)：当前相关取消 / detach 决策。安装版证据只覆盖正文列出的场景；真机已验证 detach / 孤儿让位，但让位后的前缀保留未成立，手动取消及其他 wire 尚未覆盖。
- [停止适配 Swift-1.5 模型](DECISION_SWIFT15_NO_ADAPT.md)：用户接受的模型适配终止决策；仅约束该模型方向，不是通用模型兼容政策。
- [Tool Governance Contract](TOOL_GOVERNANCE_CONTRACT.md)：2026-09-12 定稿的 v1 契约定义稿。它记录当时的协议目标；是否以及哪些部分已进入当前产品实现，必须对照源码与测试，不应把“契约定稿”读作当前端到端验收。
- [Branch-Fork Protocol](BRANCH_FORK_PROTOCOL_DRAFT.md)：v1 已实现并随 v1.4 发布；文件仍保留 v2 内存后端等未决设计，故标题中的 DRAFT 只适用于后续部分。
- [信任边界：单机可信 与 多人多权限（2026-11-12）](TRUST_BOUNDARY_SINGLE_USER_VS_MULTI_USER_20261112.md)：Owner 裁定。固定「单人本机 + 局域网 + 生产环境可信」为当前语义前提，`result_contract` 不承担防伪；多人多权限所需的是 SimiGo 侧的认证与写闸，不属于 IS 语义，现状未做、未实现。

## 提案与待复核材料

- [信息空间缺口账：四项 → 五项（2026-11-13）](IS_GAP_LEDGER_20261113.md)：设置页缺口数的当前口径。第五项「有摘要、无归属」独立于其余四项，因为归属写入撞锁失败时摘要已经落库，前四项都看不见。

- [入站转录归一化提案](TRANSCRIPT_NORMALIZATION_PROPOSAL_20261016.md)：DRAFT；未获批不构成实施授权。
- [Runtime Reliability Backlog](RUNTIME_RELIABILITY_BACKLOG.md)：2026-09-11 的历史优先级快照。P0 封口记录为 DONE / VERIFIED / DEFERRED；其余条目不能直接当作当前 backlog，须重新对照现行代码和产品问题索引。

## 历史方向与已替代基线

- [V1.5 终局决策](V15_ENDGAME_DECISION_20260919.md)：历史阶段决策。
- [V1.6 方向登记](V16_DIRECTION_REGISTRATION_20260919.md)：历史路线登记，不是当前实施计划。
- [V1.7 方向登记](V17_DIRECTION_REGISTRATION_20260919.md)：历史实验路线登记，不是当前实施计划。
- [v4.5 Stable Foundation 基线](V4_5_STABLE_FOUNDATION_BASELINE.md)：已由 [v5.0 Core Architecture Baseline](../history/CORE_ARCHITECTURE_BASELINE_V5_20260912.md) 取代；仅保留溯源。

## 阅读规则

- 提案、实验结果、已接受决策和实现验收是不同状态。
- 被替代或过期的材料保留历史，不再作为当前实现指引。
- 当前产品问题统一见 [Open Problems](../knowledge/open-problems/README.md)；当前架构与能力须由源码和对应测试 / 实机证据确认。
- 当前代码与历史合同不一致时，先核查差异，不扩大旧文档结论，也不据此自动授权改动。
