# P4-A STEP① — Research Object Definition

**Date:** 2026-09-22  
**Status:** STEP① working definition  
**RQ:** 未分配

## 1. 研究对象
> 由一种可明确描述的计算架构差异所诱导、并影响计算继续执行所需状态的一个 Execution State 属性及其可观察后果。

```
Architecture Feature
    → Computation Dependency
    → Execution State Property
    → Observable Consequence
```

这里研究的是计算架构规律，不是模型承载的全部知识内容。

## 2. 计算架构差异的边界
- 状态由何种计算依赖产生；
- 状态是否随上下文/时间增长；
- 状态是否可共享或复用；
- 状态是否依赖历史顺序；
- 状态访问是否具有特定范围或模式；
- 状态是否需要 materialize / reattach / reconstruct；
- 状态是否存在不同生命周期或未来使用关系。

仅属于模型结构、但不能明确连接到 continuation-relevant state 的特征，不进入研究对象。

## 3. Execution State 的操作性边界
> 为了从当前计算位置继续执行而必须被保留、恢复、共享、物化或转移的 continuation-relevant state。

它不是：模型全部参数、模型全部知识、模型内部所有中间张量的集合、某一种框架的具体内存布局，也不是某一种 Runtime 的对象实现。

## 4. 观察边界
只观察能够连接到以下链条的现象：
```
Architecture
→ Computation dependency
→ Continuation-relevant state
→ State characteristic
```

STEP① 暂不把性能、吞吐、显存占用、加载时间等作为结果指标；它们属于后续 Estimand / Experiment 的候选观察量。

## 5. 最小分析单元
> 一个计算架构差异 + 一个受影响的 State 属性。

例如仅作为定义示例：历史依赖机制差异 → state dependency / growth 差异。该示例不构成实验假设，也不授权选择具体模型或测量数据。

## 6. 排除边界
1. 模型知识、语义、概率分布与知识压缩；
2. 对模型内部所有边界的穷举；
3. 由边界直接推出 Universal Model Unit；
4. 要求所有模型拥有相同物理 State layout；
5. 直接研究 Runtime implementation 而没有经过 State 语义；
6. 以 Track B 历史实验替代 P4-A 的独立证据。

## 7. STEP① 出口条件
- 研究对象能否用一句话稳定描述；
- 观察边界能否与模型内容研究清晰分离；
- 是否存在明确的 continuation-relevance 判据；
- 是否避免预设 Universal Model Unit / Physical Representation；
- 能否在不进行实验的情况下明确下一步要定义的 RQ 对象。

## 8. 当前状态
STEP① 已形成工作定义，但尚未自动进入 STEP②。下一动作是逐项审查上述边界；审查通过后再正式定义 RQ。