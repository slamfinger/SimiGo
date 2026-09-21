# Track E(命名待定)P3 双情景正式模型设计 v0.2(2026-09-21)

**状态**:v0.1 CONDITIONAL PASS(七焦点结构合格;情景二量纲问题 +
cost-aware greedy 未形式化)→ **v0.2 correction commit(五处修改,
不采数)→ 待审核方提升为 P3 Design v0.2 PASS / Implementation
UNLOCKED**。
**修订记录(审核五处,原样落实)**:
① 情景二量纲修正:pressure penalty 与 boundary token cost **分离**,
   不再 `J₂ = J₁ + λ×token`;
② 情景二定性 = **pressure-relaxed analytical scenario(压力扩展
   分析情景)**,不改变 P0.1 normative hard-boundary 定义,禁止跨
   情景优劣推断;
③ `k_c ∈ (48,56]` 降级为**待检验区域**(当前可证据支持 = [41,56]
   的某个未定位区域;{48,50,52,54,56} 仅为 sensitivity grid);
④ **cost-aware greedy 决策公式 + 预测窗口 H 冻结**(不再留给实现
   阶段自行解释);
⑤ 2.38×/2.54× 改名 **observed reference ratios**(不再定义为
   经济意义上的 λ_p)。
**命名**:Track E 待真源定夺。

## 0. 模型要素(承 P0.1 v2 正式规范,未变)

- 节点等大小;SEM-1..5(初始 resident=∅、全体初始外化;非驻留
  访问 → REHYDRATE 付 C_rehy;超容量 EXTERNALIZE 付 C_ext/次;
  working-set:当前节点本步不可驱逐;tie-break 最低 id)。
- 预算 B:节点数口径;真实映射 = 4,449 MiB / 76.4 MiB ≈ 58 节点
  (P0 实测)。

## 1. 情景一:硬边界 feasibility-first(P0.1 normative model)

**可行域**:`π 可行 ⟺ ∀t: |R_t(π)| ≤ B` 且 SEM-3。

**目标(仅可行域内比较)**:

```
J_boundary(π) = C_ext × #ext(π) + C_rehy × #rehy(π)
J*_boundary = min over 可行 π of J_boundary(π)
```

参照:dp_optimal(缩减实例精确 J*_boundary)/ belady_greedy
(future-aware fault 口径 reference)。

**违规处理**:任一步超预算 ⇒ 不可行,移出排名,单独报告。

## 2. 情景二:Pressure-relaxed analytical scenario(压力扩展分析情景)

**定性声明(审计收紧②,钉死)**:情景二**不改变 P0.1 的 normative
hard-boundary 定义**——它是 P0.1 之外的**分析情景**,观察"如果允许
进入压力区会发生什么"。**禁止跨情景优劣推断**(情景二某策略数值
更低 ≠ 优于情景一;两情景结果分开解释,禁止合并总分)。

**双通道结果(审计收紧①,替代原 J₂)**:

```
通道 1(边界事件成本,token-equivalent):
    J_boundary(π) = C_ext × #ext(π) + C_rehy × #rehy(π)

通道 2(压力通道,ms 单位,独立报告):
    P_pressure(π; k_c) = Σ_t I(|R_t(π)| > k_c) × L_t
    P_pressure_ratio(π; k_c) = mean over 超限步 of (L_t / L_ref)

    L_t   = 该步 decode latency(ms)
    L_ref = 该策略在 k ≤ 40 基线区的 ms/tok
    λ_p   = sensitivity multiplier,**仅施加于通道 2 的报告层**,
            任何情况下不加进 J_boundary
```

**通道 1 与通道 2 永不相加。** 原方案
`J₂ = J₁ + λ_p × C_ref × I[|R_t|>k_c] × steps_in_excess` 的量纲
偷换(把 decode latency ratio 写成 token-equivalent 经济惩罚)已
删除。

## 3. k_c 证据纪律(审计收紧③)

- **当前可证据支持**:k_c ∈ [41, 56] 的某个**未定位区域**
  (k≤40 平坦 + k=56 压力 + k=64 未崩;48–56 无细扫);
- **P3 sensitivity grid** = {48, 50, 52, 54, 56}——这是待检验
  参数网格,**不构成悬崖区间的实证结论**;
- 悬崖精确位置由 P0.2 后续梯度细扫闭合,不反向修改本设计。

## 4. 策略集分层(审计:offline reference 与 online implementable
分列,结果表不得混排)

```
Offline reference(不可在线实现):
    dp_optimal        精确 J*_boundary(仅缩减实例)
    belady_greedy     future-aware fault 口径 reference

Online implementable:
    lru               recency 基线
    lfu_aging         频率基线
    pressure_threshold 主动外化基线
    cost_aware_greedy  P3 target(NEW,定义见 §5)

对照存档:tree_lru(阴性形态 FALSIFIED,不入排名)
```

## 5. Cost-aware greedy:冻结定义(审计收紧④,实现前置门)

**触发**:每次容量强制驱逐时(语义同 SEM-3)。

**决策公式(冻结,可实现——无任何未来 trace 信息)**:

```
对每个候选节点 i(≠ 当前访问节点):

    n_i      = 节点 i 在最近 W = 200 步窗口内的访问次数
    P_re(i)  = min(1, n_i / H)
               (窗口内频率对 horizon H 的重访问概率估计)
    Score(i) = C_ext + C_rehy × P_re(i)
               (驱逐 i 的估计增量未来边界成本:
                立即付 C_ext;若 H 内被再次访问,估计付 C_rehy)

驱逐:argmin Score(i)
tie-break:最低 node id
```

- **预测窗口 H ∈ {1, 4, 8, 16}**(sensitivity;主轮 H=8)——实现
  不得自行选择;
- 诚实注记:C_ext 对所有候选相同,不影响 argmin(驱逐成本项计入
  Score 以保持目标完整性,排序实际由 Ĉ_rehy 项驱动);
- H=1 极限 ⇒ P_re=0 ⇒ 退化为 LRU(H 参数即"结构/频率信号的用武
  之地"旋钮)。

## 6. 双情景执行协议(审计:同 trace、分模式、严格并行)

```
same trace / same seed / same workload / same 策略 / same budget
        ├── Scenario 1:hard feasibility(normative)
        └── Scenario 2:pressure-relaxed(分析情景)
```

结果**分开解释,禁止合并总分,禁止跨情景优劣推断**。

## 7. Sensitivity 分相位(审计:第一轮不爆炸)

**Phase P3-A(模型验证)**:workload {hot, tree};budget 固定基线
(0.40);C_rehy 固定 0.72;k_c ∈ {48, 52, 56};pressure ratio ∈
{1, 2.38, 2.54};H ∈ {4, 16}。
——先验证 simulator 语义、参数传递、五通道输出、cost-aware greedy
行为全部正确。

**Phase P3-B(sensitivity 展开)**:k_c = {48, 50, 52, 54, 56};
λ_p = {1, 1.5, 2, 2.38, 2.54, 3, 4};H = {1, 4, 8, 16}。

## 8. 指标五通道(不变,禁止合成)

```
A. 可行性:violations per trace(硬)
B. 边界成本:J_boundary(token-equivalent)
C. decode 性能:ms/tok per residency level(ms,独立)
D. 容量使用强度:byte-steps(描述)
E. 参照差距:J(π) − J*_boundary(缩减)/ J(π) − belady(大网格,描述性)
通道 2(情景二):P_pressure / P_pressure_ratio(ms,独立)
```

## 9. 判读纪律(延续 + 情景二新增)

1. 结果只支持对应情景;两情景结果禁止合并、禁止跨情景优劣排序;
2. 情景二首轮参数(k_c/λ_p)不得反推完整 C_resident 经济函数;
3. H-P0 判读:cost_aware_greedy vs lru/belady 的差距形态(可实现
   pressure+reuse 证据);H-P1 本轮不判读(保持 OPEN);
4. 单机/单模型/单 seed 限定随结论携带。

## 10. 边界

Track E 命名待 P3 证据;本设计不构成架构结论;P0.2 后续(梯度细扫/
重复测量/Instruments)只更新 P0.2 证据,不回写本设计与 P0.1。
