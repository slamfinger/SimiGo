# Track E(命名待定)P3 双情景正式模型设计(2026-09-21)

**状态**:DRAFT 待审核(设计文档,无采数;实现待本设计经审核确认后
启动)。**输入依据**:P0.1 v2 正式确认 PASS(v0.1 Policy Objective
Definition,字典序规范依据)+ P0 CONDITIONAL PASS(容量侧实测:
R_node = 78,246 KiB/节点、Available = 4,449 MiB、MaxResidentNodes =
58)+ P0.2 CONDITIONAL PASS(悬崖首轮证据)+ simulator v2(情景一
已实现)。**审计焦点对齐**:本设计按外审锁定的七项审核焦点逐项落实
(见 §1–§7)。

## 0. 模型要素(承 P0.1 v2 正式规范)

- 节点等大小(size 轴属 H-P1 sensitivity,后续);SEM-1..5 语义
  (初始 resident=∅、全体初始外化;非驻留访问 → REHYDRATE 付
  C_rehy;超容量 EXTERNALIZE 付 C_ext/次;working-set:当前节点
  本步不可驱逐;tie-break 最低 id)。
- 预算 B:节点数口径(v0 纪律);真实映射 = 4,449 MiB / 76.4 MiB
  ≈ 58 节点(P0 实测)。

## 1. 焦点①:情景一(硬边界 feasibility-first)严格数学定义

**决策问题**:给定 trace σ(长度 T)、预算 B、策略 π,π 在每步产生
resident 集合 R_t(π)。

**可行域**:

```
π 可行 ⟺ ∀t ∈ [0, T): |R_t(π)| ≤ B  且  SEM-3(当前节点本步驻留)
```

**目标(仅在可行域内比较)**:

```
J₁(π) = C_ext × #ext(π) + C_rehy × #rehy(π)      (token-equivalent)
J₁* = min over 可行 π of J₁(π)
```

**参照**:`dp_optimal` = 缩减实例上的精确 J₁*(已实证与
belady_greedy 重合,P3R2);大网格参照 = belady_greedy(future-aware
reference,**仅 fault 数口径**,不称 J₁ 全局最优——P0.1/P3R2 纪律
延续)。

**违规处理**:任何一步 |R_t| > B ⇒ 该策略判不可行,移出排名
(单独报告违规轨迹,不参与 cost 比较)。

## 2. 焦点②:情景二(压力惩罚)——引入位置与"观测参数"纪律

**与情景一的唯一区别**:超上限不再是不可行,而是产生压力惩罚项。

```
J₂(π) = J₁(π) + Σ_t penalty(t)
penalty(t) = λ_p × C_ref × 1[|R_t(π)| > k_c] × steps_in_excess
```

- `k_c`(悬崖位置):**观测参数**,首轮证据限定 k_c ∈ (48, 56]
  (P0.2 单点 56);sensitivity 必做 k_c ∈ {48, 50, 52, 54, 56};
- `λ_p`(惩罚倍数):**观测参数**,首轮双口径 2.38×(vs k=40)/
  2.54×(vs k=0);sweep 必做 ∈ {1, 1.5, 2.38, 2.54, 3, 4};
- **纪律**:k_c 与 λ_p 一律标注"首轮观测参数",禁止固化为常数;
  任何 J₂ 结论带参数标注;**不得由 J₂ 结果反推完整 C_resident
  经济函数**(审计焦点⑥,见 §6)。
- 引入位置:惩罚作用于**超上限期间的 decode 步**(占用步),不改变
  驱逐规则本身;两情景的驱逐规则集合相同,仅可行性定义不同。

## 3. 焦点③:成本单位(token-equivalent 的边界)

- `C_ext`/`C_rehy`:token-equivalent,**仅用于边界事件成本**
  (J₁/J₂ 第二层);
- resident bytes:**仅出现在约束层**(|R_t| ≤ B)与描述层
  (byte-steps),**任何情况下不与 token 相加**;
- decode 延迟(ms/tok):**独立指标层**(§5),不折算 token
  (折算需显式 λ 定义,属 Deferred);
- 情景二的 λ_p:无量纲倍数,乘于 ms 指标之上**独立报告**,
  不并入 J₁/J₂ 的 token 数值。

## 4. 焦点④:策略集与比较边界

| 角色 | 策略 | 比较边界 |
|---|---|---|
| Reference(精确) | dp_optimal | 仅缩减实例(8 节点级) |
| Reference(fault 口径) | belady_greedy | 全网格;不称 J₁ 全局最优 |
| Baseline | lru | recency 基线 |
| Baseline | lfu_aging | 频率基线(v1 已证中压力域优于 lru) |
| Baseline | pressure-threshold | 主动外化基线 |
| **Target(P3)** | **cost-aware greedy(NEW)** | 驱逐时最小化估计未来成本(含 C_ext 权重);可实现(无未来信息) |
| 对照(阴性形态存档) | tree_lru | H-P1 首形态已 FALSIFIED,保留作对照不入排名 |

**比较边界**:cost-aware greedy 是 P3 的实验目标;它 vs lru/belady
的差距回答 H-P0(可实现 pressure+reuse 是否足够);**structure-aware
policy 不入本轮**(H-P1 另立实验,避免混淆变量——形态探索在
tree_lru 阴性后重开)。

## 5. 焦点⑤:指标(分离报告,禁止合成)

```
A. 可行性:violations per trace(硬约束;always 类策略的排除依据)
B. 边界成本:J = C_ext×#ext + C_rehy×#rehy(token-equivalent)
C. decode 性能:ms/tok per residency level(ms 单位,独立报告)
D. 容量使用强度:byte-steps(描述层)
E. 参照差距:J(π) − J₁*(缩减实例)/ J(π) − belady(大网格,描述性)
```

**禁止**:将 A–D 合成单一分数;不同量纲相加;以单一数字宣布
"最优策略"。

## 6. 焦点⑥:判读纪律

1. 实验结果**只支持对应情景**的结论:情景一结果不得推广至情景二,
   反之亦然;
2. 情景二的首轮参数(k_c/λ_p)**不得反推完整 C_resident 经济函数**
   ——反推属 Deferred;
3. H-P0/H-P1 判读规则:cost-aware greedy vs lru/belady 的差距形态
   = H-P0 的可实现策略检验;structure-aware policy 缺席时 **H-P1
   保持 OPEN 不判读**;
4. 单机/单模型/单 seed 限定随所有结论携带。

## 7. 焦点⑦:P0.2 后续实验隔离

梯度细扫(k=48–56)、重复测量(热漂移分离)、Instruments 机制观测:
**只更新 P0.2 的证据状态**(悬崖位置/压力形态),**不得回写或改变
已 PASS 的 P0.1 规范定义**(字典序框架 = 正式规范)。若细扫更新
k_c/C_pressure 估计 → 进入情景二作为**参数更新 + 重跑**,历史数字
不追溯修改。

## 8. 实现映射与执行序

- simulator v2 已实现情景一(lru/lfu_aging/belady_greedy/dp);
- **v3 扩展(本设计确认后实现)**:情景二 penalty 模式 +
  cost-aware greedy + 指标分离输出(A–E 五通道)+ 双 workload
  (hot/tree)× sensitivity(budget × C_rehy × k_c/λ_p 情景二);
- 前置探针已完成:depth sweep(P0 审计④闭合)。

## 9. 验收与判读

- 验收:双情景各自出完整结论(可行域、成本、参照差距、参数
  敏感性),**不跨情景合成**;
- H-P0 判读:cost-aware greedy vs lru 差距形态(可实现的
  pressure+reuse 证据);
- H-P1:本轮不判读(保持 OPEN);
- 止损:若双情景下所有可实现策略无显著差异且 oracle 空间 < 噪声,
  记录"该 workload 域内 policy 区分度不足"并关闭,不恋战。

## 10. 边界

Track E 命名待 P3 证据;本设计不构成架构结论;所有结论带
workload/参数标注;不反推 Track B / M 链。
