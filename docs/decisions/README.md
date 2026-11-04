# 架构决策索引

本目录收录需要长期约束实现的已接受或被替代的架构决策。ADR 正文是决策及其证据边界的来源；本页仅导航。

## 当前重要决策

- [本地离线 prefill 与取消语义（2026-10-30）](ADR_LOCAL_OFFLINE_PREFILL_AND_CANCEL_20261030.md)：撤销 prefill 时间拒绝门；客户端断连采用 detach，显式手动取消仍为硬取消；detach 执行必须有界。安装版证据只覆盖正文列出的场景。真机已验证 detach / 孤儿让位，但让位后的前缀保留未成立；手动取消及其他 wire 尚未覆盖。不能将实现落地写成全场景验收。
- [v4.5 Stable Foundation 基线](V4_5_STABLE_FOUNDATION_BASELINE.md)：历史架构记录，已由 [v5.0 Core Architecture Baseline](../history/CORE_ARCHITECTURE_BASELINE_V5_20260912.md) 取代；保留溯源。

## 阅读规则

- 提案、实验结果和已接受 ADR 是不同状态。
- 被替代决策保留历史，不再作为当前实现指引。
- 当前代码与 ADR 证据范围不一致时，先核查差异，不扩大结论。
