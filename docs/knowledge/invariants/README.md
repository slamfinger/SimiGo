# Invariants

本目录保存 2026-09 至 2026-09-27 期间、以 v5.0 Runtime / Residency 架构为基线的历史不变量与合同记录。

**重要边界：目录名称不代表这些条目已经在当前 ES / IS 研究架构、所有 backend 或当前发行版上重新验证。** 尤其 D1 和 GA-0 是特定 Runtime / Residency 实现合同，不是 PALACE settlement、跨执行载体恢复或 Agent Continuity 的证明。

每条记录仍需回答：

- 为什么它成立？
- 哪些证据支持它，且证据对应哪个 commit / 版本 / 机器？
- 破坏它会造成什么？
- 哪些实验验证过它？
- 它与哪些 Architecture / Decision 相关？

## 当前性规则

- 本目录条目首先按其正文日期与 v5.0 历史基线理解。
- 若要把某条提升为当前产品不变量，必须针对当前源码、测试和对应实机范围重新确认；不能只因旧报告写有 IMPLEMENTED / VERIFIED 就自动继承。
- 不将 Runtime / Residency 层不变量扩大为 ES / IS 语义合同。
- 当前产品问题统一见 [Open Problems](../open-problems/README.md)；当前研究主张以根 README、现行源码和新证据为准。
