# Principles

本目录保存从 2026-09 阶段具体实验中抽象出的历史工程原则。它们可作为审查启发，不等于当前实现事实或无条件规则。

一个 Principle 至少应有：

- Originating evidence
- Generalization
- Scope
- Counterexamples / limits
- Related decisions

## 当前性边界

- 原则的适用范围由正文限定；不得扩展到未验证的 backend、模型或产品路径。
- 当上游 API、runtime 或产品架构变化时，应重新核验其前提。
- 原则不能替代当前代码审查、测试或实机证据，也不自动授权增加或删除实现。
