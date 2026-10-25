# P4-A：Continuation Dependency 与 Computation Dependency 不可约性对抗

日期：2026-09-22
状态：概念研究 / STEP① 审查
RQ：未分配
实验：未授权

## 1. 本轮核心问题

上一轮留下的最危险问题是：

> Continuation Dependency 是否只是 Computation Dependency 的另一种命名？

如果二者完全相同，P4-A 没有独立研究对象，应关闭或并回计算架构研究。

## 2. 先区分两个问题

Computation Dependency 问：

> 为了计算当前目标，需要哪些前置计算结果、输入、变量或中间状态？

Continuation Dependency 问：

> 在当前计算已经发生之后，为了让计算能够从此处继续到未来某个合法 continuation，需要哪些信息关系仍然必须可区分？

二者有重叠，但时间方向和研究目的不同。

可写成：

Current computation:
Inputs → intermediate dependencies → current output

Continuation:
Current state → future input / operation → future behavior

因此 Continuation Dependency 不是自动等于普通 Computation Dependency。

## 3. 第一攻击：如果计算图可以完整表达未来

如果把整个程序/计算图提前展开：

Current node → all future nodes

那么所谓 continuation dependency 可以被重新表达为普通计算图上的数据依赖。

在这种极强的静态前提下：

Continuation Dependency ≈ Computation Dependency

这是一个真实反例。

因此不能宣称 Continuation Dependency 在所有计算系统中天然独立。

## 4. 第二攻击：为什么运行时仍可能需要 continuation abstraction？

现实计算通常不是一次性静态展开的：

- future input 尚未出现；
- 分支尚未选择；
- 外部调用尚未发生；
- workload 轨迹尚未确定；
- 长期运行状态可能被重新利用。

此时研究的不是“完整未来计算图”，而是：

> 在未来尚未完全确定时，当前状态需要保留什么区分能力，才能支持一类未来延续。

因此它更接近：

State → possible continuations

而不是：

Full graph → fixed dependency set

这给 Continuation Dependency 留下了潜在独立性。

## 5. 第三攻击：如果未来是已知的，独立性进一步减弱

如果 continuation 完全已知、确定且静态，那么：

当前状态所需信息
可以直接从未来计算图反向求依赖。

这意味着 P4-A 的独立研究价值主要出现在：

> future continuation 未完全确定，但 continuation domain 可以被限定描述。

所以 P4-A 不应研究所有计算依赖，而应研究：

**open-ended / partially specified continuation 下的信息依赖。**

## 6. 第四攻击：这是否又变成“程序状态”？

非常可能。

在普通程序语义中，程序状态本来就包含未来执行所需的信息。

因此如果 P4-A 只是重新命名：

program state / machine state / hidden state

那么没有新的抽象贡献。

所以必须避免声称：

> Execution State 是全新的状态概念。

更谨慎的是：

> Execution State 是一个面向可继续计算语义的统一观察层候选。

## 7. 第五攻击：LLM 的特殊性是否足够？

不能假设。

LLM 的长上下文、KV cache、循环/递归状态、状态空间模型状态等，都可以被解释为某种 continuation dependency。

但这本身并不能证明 Execution State 是 LLM 独有或特殊的。

真正可能有价值的是：

> 不同计算架构可以通过共同的 continuation semantics 被比较，而不要求共享相同物理 state representation。

这才对应 Architecture 2.0 的“通用语义、非通用物理表示”。

## 8. 第六攻击：如果 continuation domain 足够小，会不会失去意义？

会。

如果只定义一个极窄的未来操作集合，例如“再生成一个 token”，那么几乎任何可用缓存都可能被描述成 continuation dependency。

这会使抽象失去区分能力。

因此 continuation domain 必须既：
- 足够明确；
- 又包含有实际结构差异的未来延续。

这仍然是未来研究设计问题，不是当前实验结论。

## 9. 当前最小不可约差异

经过上述攻击，目前还能保留下来的最小区别是：

> **Computation Dependency 主要描述当前/既定计算的依赖关系；Continuation Dependency 描述在未来计算尚未完全确定时，为支持一组允许的未来延续而必须保持的区分关系。**

核心关键词：

**future not fully fixed**

这不是说它一定独立成立，而是当前最小候选。

## 10. 重要负面边界

以下情况下不应把 Continuation Dependency 作为独立抽象：

1. 完整未来计算图已经固定；
2. 未来操作集合被限定到只有单一确定路径；
3. 普通程序状态/数据依赖已经完全表达该关系；
4. 引入 Continuation Dependency 不产生新的可比较性质；
5. 不同架构比较时，该概念没有增加任何解释力。

满足这些条件时，P4-A 应关闭或并回普通计算依赖研究。

## 11. 当前判断

P4-A 尚未被关闭，但已经被压缩到一个非常窄的候选：

> **在未来延续尚未完全确定、但允许 continuation domain 可描述的计算系统中，是否存在一种比普通当前计算依赖更适合跨架构比较的 continuation-oriented information relation？**

注意：

这不是 RQ。

它仍是 STEP① 概念候选。

## 12. 下一步

下一刀不再讨论 State 本身，而直接攻击：

> **“future not fully fixed” 是否真的产生一种新的、不可由普通程序状态 / 数据依赖表达的性质？**

如果找不到反例之外的必要性，P4-A 应关闭。

