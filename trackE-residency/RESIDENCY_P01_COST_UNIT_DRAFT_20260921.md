# Track E(命名待定)P0.1 Cost Unit Definition——定义探针草案 v2(2026-09-21)

**状态**:v1 CONDITIONAL PASS → **v2 按审计五处收紧修订,待审核确认**。
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
