# Track E(命名待定)Residency P0 结果(2026-09-21)

> **终审判定(2026-09-21):CONDITIONAL PASS——P0 驻留容量计量探针:
> PASS;完整经济成本模型:待闭合(Economic Cost Closure Pending)。**
> 审核方核对 5ba2e88/c203407/602365b。实验数据 PASS、计量实现 PASS;
> 阻断的是两个表述:"Cost Model Closure 已完成"与"policy 不等式已
> 闭合"。
>
> **四处收紧(原样入档,不补跑)**:
> 1. `C_resident` 未完成经济计价:左式 `KiB × T` 的 T 物理含义与
>    单位未定义;右式混合 token-equivalent 与 KiB;bytes→机会成本
>    换算率缺失;外部存储字节成本未定义;"0 ms/token 计算成本为零"
>    过强(M4 口径 = 未观察到超出轮间噪声的稳态 tax,不等同于零)。
>    正确结论 = **P0 完成驻留字节计量与结构性成本维度探针,尚未完成
>    具有统一单位的经济成本函数闭合**。
> 2. **容量约束 ≠ 机会成本**:当前数据支持 `ResidentCapacity(n) =
>    78,246 KiB × n` 与 `MaxResidentNodes ≈ floor(Available/R_node)`
>    (capacity-side closure);策略优化需要
>    `C_resident(node, horizon) = f(bytes, memory_pressure,
>    opportunity_cost, horizon, workload)`,在此之前 `78,246 KiB × T`
>    不得与 `0.72 token-equivalent` 放入同一不等式。
> 3. "GDN 不可压缩固定驻留底价"收紧为:**当前实现与 dtype 配置下的
>    主要固定驻留占用项;其可压缩性及跨架构行为留待后续实验**。
>    H-P1 可吸收为候选信号,非已验证 decision-relevant signal。
> 4. "attention 随深度增长" = 结构推断:需至少两个深度的驻留字节
>    测量(resident-footprint depth sweep);M3-B 外化载荷平坦性
>    不替代驻留分配的深度扫描。当前表述 = attention 私有页包含与
>    分配长度相关的部分。
>
> **正式记录(审核建议原文)**:"P0 驻留容量计量探针:PASS;完整
> 经济成本模型:待闭合。" 允许继续:保留 78,246 KiB/node 为 resident
> footprint;GDN 80% 为当前配置结构观察;可设计 P3 state-size
> signal;不得称统一单位 policy inequality;P0.1/P3 前补成本单位与
> 换算模型。
>
> **下一步:P0.1 Cost Unit Definition(定义探针,非采数)**——六个
> 定义项:capacity(bytes)、resident opportunity cost(?)、external
> storage cost(?)、rehydrate cost(token/time)、horizon T 定义、
> unified objective unit。定义闭合后 P3 正式策略比较才解锁。

> **首跑记录(史料)**:v1(nbytes 计价基础确立 + activeMemory 瞬态
> 污染教训)与下文数字为容量侧事实,经终审确认有效;初版"Cost Model
> Closure/policy 不等式闭合"表述按终审降级为 capacity-side closure。 代码:`ResidencyP0ResidentCost.swift`(exp 分支)。
> 定位:v0 终判钉死——P0 先于 P3,否则 New Policy = 在成本模型未闭合
> 的目标上优化。

## 靶子

补齐 policy 不等式左边:

```
Keep Resident(C_resident)vs Externalize + Future Rehydrate(≈0.72 token)
```

## 方法(计价基础 = nbytes 精确,非 memory 推断)

对 520 逻辑行的标准子代逐组件取 `nbytes` 实测;GPU activeMemory 降为
粗交叉验证(v1 教训:统一内存计账含 prefill 瞬态,曾出现负增量读数,
不作为定价基础;尾部拟合斜率与 nbytes 差 <1%,量级交叉确认)。

## 结果

**① 每节点驻留字节(520 逻辑行,nbytes 精计)= 78,246 KiB:**

| 组件 | 字节 | 占比 |
|---|---|---|
| attention 私有页(分配 768 行/层,step-256 对齐) | 15,360 KiB | 19% |
| GDN 槽(30 层 × 2 槽) | 62,880 KiB | **80%** |
| LMOutput.State(2 数组) | 6 KiB | ~0% |

GDN 槽形态分解:conv `[1,3,8192]` bf16 × 30 = 1,440 KiB;recurrence
`[1,32,128,128]` fp32 × 30 = **61,440 KiB(驻留成本主体)**。

**② padding 披露**:attention 分配 7,680 行(step-256 对齐)/ 使用
5,200 逻辑行(1.48×)——外部化载荷按逻辑行(73,292 KiB),驻留按
分配行(78,246 KiB);**外化反而省掉 padding**。

**③ 交叉验证**:activeMemory 尾部拟合 78,890 KiB/节点 vs nbytes
78,246 KiB(差 <1%)。

**④ 真实预算上限**:memoryLimit − 权重(20,126 MiB)= 4,449 MiB 可用
→ 折合 **≈58 个 520 行节点**。simulator 的 budget 参数自此有真实
映射(100% 预算 ≈ 4.3 GiB 驻留字节)。

**⑤ 容量侧闭合(capacity-side closure;非统一单位不等式)**:

```
ResidentCapacity(n) = 78,246 KiB × n(容量约束,已实测)
MaxResidentNodes ≈ floor(4,449 MiB / 78,246 KiB) = 58

单位警示:左列字节×T 与右列 token-equivalent 不可直接比较;
完整经济成本函数 C_resident(node, horizon) = f(bytes,
memory_pressure, opportunity_cost, horizon, workload) 待 P0.1
定义。另:M4 口径 = 未观察到超出噪声的稳态 tax,不得写为
"计算成本为零"。
```

## 意义(待终判;措辞按纪律)

1. **C_resident 本体 = 字节机会成本,计算成本为零**(M4);不等式
   两边首次都有数。
2. **结构观察(当前配置):GDN recurrence state(fp32,61,440 KiB/
   节点)是驻留字节的主要固定占用项(80%)**;attention 私有页(19%)
   包含与分配长度相关的部分,其随深度的增长规律需独立 resident-footprint sweep 验证(M3-B 载荷平坦性不替代)。GDN 的可压缩性与跨架构行为留待后续;H-P1 吸收 **state size 为候选信号**(非已验证 decision-relevant signal)。
3. v0 的"低预算 = 策略无关区"获得物理解释:预算绑定时的字节之争
   才是 policy 的用武之地——现在预算有了真实字节数(4,449 MiB /
   ≈58 节点)。
4. 外化省 padding(驻留 78,246 vs 载荷 73,292 KiB)——小而真实的
   结构观察。

## 诚实性注记

1. v1 记录:activeMemory 计账含 prefill 瞬态,曾出现负增量读数——
   计价基础改为 nbytes,activeMemory 降级为交叉验证(不再作为结论
   基础);
2. 单机、单模型、单 config(520 行节点);字节=MLX 分配口径
   (含 fp32 GDN/fp16 KV/bf16 conv 的真实 dtype);
3. 驻留字节的"机会成本换算率"(bytes→token)依赖场景,留白给
   Residency Policy;
4. 本结果不反推 Track B / M1–M4 / simulator v0。

## 决策

1. **P0 数字入档 → 待审核终判;cost model 至此闭合**,P3(New
   Policy discrimination)解锁——其 cost-aware oracle 与 state-size
   信号设计应消费本探针的 GDN 主体发现;
2. Track E 命名继续待定(等 P3 证据)。
