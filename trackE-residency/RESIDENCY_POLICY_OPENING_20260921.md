# Track E(命名待定)Residency Policy 开题(2026-09-21)

**状态**:开题(探针未跑,无结果无决策)。命名 Track E 待真源定夺。
**输入**:M 链已封口——M4 终判数字 = 一次性边界成本 **≈0.72 resident
decode-token equivalent**(externalize ~28–33 ms 为主体,rehydrate
~1–1.5 ms;measurement-scope 注记:State 对象重建未入计时)+ 稳态
无超噪声税 + 载荷 = 私有后缀(深度无关)+ 树序依赖 + 表示可选。

## 研究问题(性质转变)

M1–M4 回答"**能不能**"(correctness)与"**多少**"(cost);
Residency Policy 回答"**什么时候**":

```
什么时候 Externalize?
什么时候 Keep Resident?
什么时候 Rehydrate?
什么时候不要 Rehydrate?
```

**研究纪律(M4 终判钉死)**:M4 证明的是"外化/召回的 cost 可接受性
边界",**不证明"应该什么时候外化"**——policy 结论必然依赖 workload
假设,所有结论须带假设标注。

## 决策空间与信号候选(开题清单,待审核取舍)

| 决策 | 信号候选 | 来源 |
|---|---|---|
| Externalize? | 内存压力(vm_stat/swap);节点访问 recency/frequency;E[T_remaining](预计不再使用的节点先走) | Track B adaptive 同构 |
| Keep Resident? | 常驻成本 ≈ KV 驻留字节(18K 语境下 M4 未计——**留白:resident memory cost 未测,属本阶段补课项**) | M4 边界 |
| Rehydrate? | 一次性 ≈0.72 token 等价 + 树序依赖(父代须先回驻留);预期后续使用长度 L 与 0.72 的比值 | M4 + M3-C |
| 不要 Rehydrate? | 无预期使用的节点保持外化;兄弟/祖先链未回驻留时不单独召回子节点 | M3-C 树序 |

同构映射(承 Track B 入档):E[T_remaining] × τ̂ > Ĉ_reattach 的
adaptive representation 决策 ↔ residency 的"预期回流价值 × 回流频率
> 驻留成本"决策;在线税估计 ↔ 在线带宽/延迟估计(τ̂ 热敏感教训沿用:
估计器鲁棒性先入边界)。

## 第一探针候选(建议,待审核确认)

**Policy simulator(F5-3 Step1 同型,数字先于 live)**:
合成 workload(节点集合 + 访问序列 + 内存预算)上比较候选策略——
always-resident / externalize-on-pressure / LRU 召回 / oracle,
指标 = 命中率×回流延迟 + 驻留峰值;M4 数字作为回流成本常量输入。
live 实验仅在模拟显示策略差异大于噪声后进行。

## 验收与止损(预注册草案)

- 验收:模拟层面策略区分度 > 噪声 → live 单变量验证;policy 门 =
  相对 oracle 的 regret(沿用 Track B"regret 仅描述性"纪律)。
- 止损:若合成 workload 上各策略无可分辨差异且 oracle 无优化空间,
  记录"该 workload 域内 residency policy 无独立价值"并关闭,不恋战。

## 边界

- 本开题不构成架构结论;policy 结论带 workload 假设标注;
- 内存成本侧(resident bytes 计价)未实测,为首个补课项;
- Track E 正式命名待真源定夺。
