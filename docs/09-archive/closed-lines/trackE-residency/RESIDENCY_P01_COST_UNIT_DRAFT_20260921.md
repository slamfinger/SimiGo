# Track E(命名待定)P0.1 Cost Unit Definition——定义探针草案 v2(2026-09-21)

> **终审判定(2026-09-21):PASS — v0.1 Policy Objective Definition。**
> 审核方核对 `cb66671` commit/diff:五收紧纯文档落实,无实验数字或
> 算法变化。七项审核全 PASS(模型定位 / "Keep 免费"删除 / 三层资源
> 语义 / T 三语义拆分 / C_ext/C_rehy 配置范围声明 / byte-steps·λ·
> 机会成本货币化降级 / 字典序边界明确)。
>
> **正式边界(冻结)**:第一层 `resident_bytes ≤ budget` = 硬可行性
> 约束;第二层 minimize `C_ext×#ext + C_rehy×#rehy` = token-equivalent
> boundary cost;描述层 byte-steps/λ sensitivity;延后 opportunity-
> cost 货币化。v1 主问题已解决:bytes 与 token-equivalent 不再进入
> 同一未定义换算率的不等式。
>
> **P0.1 冻结的正式口径(审核表格,原文入档)**:
>
> | 层级 | 正式定义 |
> |---|---|
> | 第一层 | `resident_bytes ≤ budget`,硬可行性约束 |
> | 第二层 | 最小化 `C_ext × #ext + C_rehy × #rehy` |
> | 描述层 | byte-steps、Resident footprint、λ/ρ 敏感性 |
> | Deferred | Resident opportunity cost 货币化、nodes-out 反事实计价 |
>
> **P3 依据与边界**:成本单位依据已具备(token-equivalent boundary
> event cost 可用),但不得扩展解释为完整 Resident 经济成本;
> `C_ext=0.69`/`C_rehy=0.72` 已限定为当前 35B 模型、当前设备、当前
> COW segmented representation 和当前 in-memory 实现下的配置相关
> 参考值,不是跨设备、跨模型的架构常数。
>
> **对当前阶段的正式判定(审核表格)**:P0.1 v2 五收紧 PASS /
> P0.1 Policy Objective Definition 正式确认 PASS / 完整经济成本理论
> Pending-Deferred / P0.2 Resident Pressure Curve CONDITIONAL PASS /
> P3 双情景模型设计解锁 / 将 `58 节点 + 2.4×` 固化为统一经济参数:
> **禁止**。
>
> **P3 现在可以采用的正式框架(审核给出)**:
> 情景一:硬边界 feasibility-first(`resident_bytes > budget` 即
> 不可行;可行域内最小化边界事件成本);
> 情景二:压力惩罚扩展(保留硬边界模型作为基准;超边界后的压力
> 惩罚作为独立、暂定的实验参数;`2.4×` 只能标记为当前 k=56 附近
> 的首轮观测,不得视为全超限区间常数)。
>
> **并行纪律**:P0.2 后续(梯度细扫/重复测量/Instruments 机制观测)
> 继续作为并行验证,不反向修改 P0.1 的正式状态。
>
> **两项非阻断 P3 实现规范注记(带入 simulator 设计,已实现)**:
> 1. 事件计数时序统一:每访问步 = touch(外部节点触发 REHYDRATE,
>    支付 C_rehy)→ 容量检查 → 逐个 EXTERNALIZE(各计 C_ext);边界步
>    与同步多事件逐一计数。
> 2. 字典序 reference tie-break:同优先级并列(victim 选择并列)时
>    固定按最低 node id 打破,保证 oracle 结果不依赖实现顺序。

**状态(封口)**:v1 CONDITIONAL PASS → v2 五收紧 → **审核确认
PASS — v0.1 Policy Objective Definition**。
确认后标记 = **PASS(v0.1 Policy Objective Definition)**——**仅解锁按
该字典序目标进行的 P3 实验,不代表完整经济成本理论已经闭合**。
**修订记录**:v1 → v2 五处收紧(审计原样入档):
① 定位声明(字典序模型 ≠ 完整经济成本函数);② "Keep 免费"删除;
③ external storage 零成本限定资源域;④ T 拆分三语义;
⑤ 0.69/0.03 配置范围声明 + byte-steps/λ 降为 descriptive only。
**命名**:Track E 待真源定夺。**输入**:P0 容量侧事实(R_node =
78,246 KiB/节点;Available = 4,449 MiB;MaxResidentNodes = 58)+
M4 边界成本参数。

## 定位声明(审计收紧①,全文钉死)

**本模型 = 容量约束下的边界事件成本优化模型,不是完整的经济成本
函数。** 冻结表述:

> **Resident capacity is modeled as a hard feasibility constraint;
> resident opportunity cost is not monetized in v0.1.**

即 C_resident 不再作为可加成本出现,而是通过容量约束体现;不得再称
"C_resident 经济成本已闭合"。

## 六个定义项

### 1. Capacity constraint:bytes —— 已闭合,角色 = 硬约束

R_node = 78,246 KiB/节点(含 padding);Available = 4,449 MiB;
MaxResidentNodes = 58。

### 2. Horizon:三种语义(审计收紧④,不得混用)

| 名称 | 含义 | 角色 |
|---|---|---|
| `T_next_access` | 当前时刻到下一次访问的**真实 trace 距离** | oracle/reference 的 trace 变量,不称通用 residency horizon |
| `T_remaining` | 当前时刻到 workload 结束的剩余步数 | 描述量 |
| `T̂_remaining` | 可实现策略对剩余步数的估计 | 估计器输入;**误差与鲁棒性单独评估**(τ̂ 教训沿用) |

注意:到下一次访问的距离 ≠ 节点保持驻留的持续时间——节点在下次
访问后可能继续驻留、也可能再次外化。

### 3. Rehydrate cost:事件成本,token 计

0.72 token-equivalent(M4)/ 28.9–34.9 ms。**不与 bytes 相加**。
配置范围声明见下节。

### 4. Externalize cost:同上

0.69 token / 27.7–33.4 ms。

### 5. External storage cost:零价格 ≠ 零资源占用(审计收紧③)

```
External storage monetary cost   = 0(v0.1 显式设定)
External storage capacity cost   = excluded from v0.1
Resident device-memory capacity  = separately constrained
```

> 在当前 in-process 实验中,外化存储的经济价格暂设为零;其具体内存
> 层级及容量归属不作为 v0.1 的优化成本维度。磁盘、远端及跨设备存储
> 成本另属后续研究范围。

避免把 `zero price` 错写成 `zero resource usage`。

### 6. Resident opportunity cost:v0.1 不货币化(审计收紧①⑥)

三候选(byte-steps+λ sensitivity / nodes-out 挤出计价 / 留白)**全部
移出规范目标**——见下节层级。C_resident(node, horizon) =
f(bytes, memory_pressure, opportunity_cost, horizon, workload) 的
货币化属 Deferred。

## 统一 objective:三层明确(审计收紧⑥)

```
Normative v0.1:
    Capacity hard constraint(resident_bytes ≤ budget,每步)
    Boundary event cost minimization(C_ext×#ext + C_rehy×#rehy;
    token 单位,两事件同单位可直接相加)

Descriptive only:
    Byte-steps;Resident footprint intensity;Optional λ/ρ sensitivity

Deferred:
    Resident opportunity-cost monetization
    Nodes-out counterfactual pricing
```

**不得让读者误以为 byte-steps + λ 已是正式优化目标。**

### "Keep 免费"表述修正(审计收紧②)

v1 的"无预算绑定时 Keep 免费(M4 已证)"删除。替换:

> **在当前模型中,Keep Resident 不额外计入边界事件成本;其资源影响
> 由 `resident_bytes ≤ budget` 硬约束表达。该处理不代表 Resident
> opportunity cost 为零。**

M4 口径限定:M4 证明的是当前实验配置下 rehydration 后未观察到超出
轮间噪声的稳态 decode tax;未证明无机会成本、不影响其他节点、无
预算压力时总成本为零、或 Resident 与 Externalize 可经济等价比较。

### C_ext / C_rehy 配置范围声明(审计收紧⑤)

> **C_ext and C_rehy are configuration-specific token-equivalent
> reference values derived from M4 timing measurements; they are not
> architecture-independent constants.**

适用范围限定:当前 35B 模型 / 当前设备 / 当前 COW segmented
representation / 当前两个测量位置 / 当前 in-memory 实现 / 当前
decode throughput 口径。P3 中不得把 0.69/0.03 当作跨设备跨模型常数。

## 审计记录(v1 CONDITIONAL PASS,2026-09-21)

五收紧:① 字典序性质声明缺失;② "Keep 免费"超出 M4 证据;
③ external storage 零成本未限定资源域;④ T 未区分三语义;
⑤ byte-steps/λ 层级不清。已确认项:容量与边界事件成本分离 ✓、
bytes 不与 token 直接相加 ✓、双目标字典序候选 ✓、C_ext/C_rehy
单位与来源显式化 ✓、byte-steps 未强行升级 ✓。

## 阶段后果

- 本 v2 经审核确认 → **PASS(v0.1 Policy Objective Definition)**
  → **仅解锁按字典序目标的 P3 实验**;
- P3 前置候选:attention 深度 resident-footprint sweep(P0 审计④);
- cost-aware oracle 按字典序定义(先可行、后 boundary cost);
- Track E 命名继续待 P3 证据。
