# 知识索引

本目录保留由证据提炼的产品 / 架构知识，不保存研究过程日志，也不替代证据原件。

## 分类

- [Findings](findings/README.md)：2026-09 历史实验与生产观察形成的有界发现。
- [Principles](principles/README.md)：从历史证据抽象的工程原则，需检查前提是否仍成立。
- [Invariants](invariants/README.md)：以 v5.0 Runtime / Residency 为基线的历史不变量记录，未经复核不代表当前 ES / IS 架构已验证。
- [Open Problems](open-problems/README.md)：当前仍未关闭的问题与待核验风险。

历史迁移材料与来源说明见 [Research archive](../research/README.md) 和 [Evolution](../evolution/README.md)。

## 证据规则

知识层级不是措辞强度：Observation → Finding → Principle → Invariant。升级必须能追溯到具体证据、适用范围和反例；目录存在或文档被命名为“原则”不构成验证。

**当前架构优先级**：根 README 与当前源码 / 测试定义当前产品事实；历史 Knowledge 与 Research 文档提供研究脉络，不反向定义当前实现。
