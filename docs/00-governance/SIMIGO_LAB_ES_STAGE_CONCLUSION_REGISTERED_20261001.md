# SimiGo-Lab Execution State 阶段结论 — REGISTERED — 2026-10-01

日期：2026-10-01
状态：`HUMAN STAGE CONCLUSION / REGISTERED（逐字登记，官方可引用表述）`
性质：human 对 Execution State 假设当前证据状态的阶段性结论。取代
任何「Execution State 已被完全证明」的越级表述；本文档只登记，不
新增证据、不改变任何实验的终态。

---

## 1. 注册表述（human 原文，中英双语逐字）

> **Execution State hypothesis is experimentally supported at MLX
> runtime level. The evidence indicates that computational continuity
> depends on a minimal relation closure rather than a physical carrier
> alone. Further replication is required for minimality and
> cross-backend generality.**

> **Execution State 假设已在 MLX runtime 层获得实验支持。现有证据
> 表明，计算连续性依赖的是最小关系闭包，而非单一物理载体。最小性与
> 跨 backend 通用性仍需复核。**

严格形式的约束：不应直接说「Execution State 已经被完全证明」。更
准确的表述即上式——**在 MLX backend 上已得到较强的运行时验证，并有
跨实现映射的初步支持；通用性和完备性仍需进一步复核。**

## 2. 已被支持的部分（三层，登记时保留证据复制状态标注）

### 2.1 「Carrier ≠ State」方向有证据

P5 系列最重要的发现不是失败，而是**排除了一个简单假设**：

> 保存 KV cache 就等于保存状态。

P5-1（protocol-valid INCONCLUSIVE，含复制）与 P5-2-C（原跑，未复制）
共同支持：KV tensor 本身不足；缺少关系条件时，恢复不能可靠继续。

```text
KV cache ≠ Execution State
```

### 2.2 {I,P,A,C} 作为关系集合有实验依据

P5-2-C / P5-4（均原跑，未复制）提供目前最核心证据：破坏 Identity /
Position / Anchor / Continuation 任一项，会导致 restore reject /
rebuild / 语义丢失 / continuation 失败。故当前可说：

```text
Execution State ≈ 满足未来计算连续性的必要关系集合
```

在 MLX 实现中有支持。（最小性的「数学意义」复核未完成——见 §3.1。）

### 2.3 P7-R2-A 提升到 runtime 层

升级路径：之前=代码结构支持→contract 成立；现在=**真实 checkpoint
→进程退出→重新加载→KV 命中→extend continuation** 已经证明：

> 一个 Execution State 可以脱离原进程存在，并恢复未来计算。

这比普通「保存上下文」概念更接近最初目标。注意等级差：MLX =
runtime validated；llama = contract mapping validated——**非同等级**
（见 §3.2）。

## 3. 还没有完全解决的部分（精确边界）

### 3.1 「最小闭包」仍需复核

{I,P,A,C} 是非常合理的候选，但数学意义的「minimal」需更严格：每项
是否真正不可由其他项推导？是否存在更小集合？是否存在隐藏依赖？
P5-4 给出支持，**Replication Audit 会进一步提高可信度**（对应缺口
清单 G-δ）。

### 3.2 跨 backend 还没有完全成立

MLX：runtime validated；llama：contract mapping validated——还不是
同等级。真正跨 backend 需要：

```text
MLX:  save → restore → continue
llama: save → restore → continue
same abstract invariant
```

### 3.3 「所有计算系统中的 Execution State」不能说

目前证明范围 = MLX runtime + 部分 backend abstraction；不是
「所有 AI runtime」。

## 4. 研究问句的层级变化（human 原文登记）

研究已从最初：

> 「能不能保存大模型状态？」

转变为：

> 「什么关系使未来计算能够继续？」

这是一个层级变化。传统方向关注 weights / KV cache / checkpoint /
memory snapshot（保存对象 = 状态）；本实验链逐步排除了这一等式，
转向：

> 状态 = 对象之间保持的计算关系

**这个方向的价值不依赖某一个模型。**

## 5. 路线确认（human 原文语义）

现在做 Replication Audit 的意义，**不是「证明它有没有」**，而是把
它从一个强实验结果**提升为一个别人可以重复验证的研究结论**。暂停
扩展 Palace/Security、先补这一层，是比较稳的路线。

## 6. 与缺口清单的衔接（CONSOLIDATION 文档 §4）

- **G-ζ（总体论证措辞定义门）→ 由本结论关闭**：措辞已由 human
  提供（§1），登记即生效；如需形式化定义门综合，另行授权。
- G-α（P4 human second layer）：维持保留。
- G-β（Sample-3 模型维度）：维持 coverage gap。
- G-δ（最小性复核 = 复制审计的后续消费）：本结论明示「进一步
  复核」——维持开放，方式归 human。
- G-ε（Token Ledger 数字分歧核对）：维持待核。

## 7. Non-claims

本登记不构成：完全证明、跨 backend 通用性证明、最小性的数学证明、
对所有 AI runtime 的适用宣称、任何性能主张。
