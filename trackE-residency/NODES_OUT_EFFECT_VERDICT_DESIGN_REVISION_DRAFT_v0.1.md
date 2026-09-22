# Nodes-out Candidate A Effect Verdict Design / Design Revision Draft v0.1

**状态**：`DRAFT / EXTERNAL DESIGN REVIEW REQUIRED`  
**日期**：2026-09-22  
**边界**：本文件只设计“若要解锁 effect verdict，必须先定义什么”。它不宣布 effect verdict，不修改 Runner、baseline、Candidate A 或已冻结 Contract，也不采数或重跑 Tier-1。

## 0. 冻结锚点

| 项 | 值 |
|---|---|
| Audited Runner | `f4d880e` / Runner v2.2.1 |
| Runner SHA-256 | `ace241fc6ca22bd1dd40d2e6036662ae0b1e2e1564f49fe3a140900e26495f17` |
| Frozen baseline | `17bde28:trackE-residency/residency_policy_simulator_v3.py` |
| Baseline blob | `ff6d4e21df40db800e64bd5c949c39b3d77d22aa` |
| Effect Interpretation Contract | `0918260` / PASS |
| Tier-1 mechanism accounting | `da5efa8` / PASS |
| Mechanism Synthesis Review | `bd414a0` / PASS |
| Current effect verdict | `LOCKED` |

## 1. 当前证据边界

### 已能支持

在 seed 42、hot/tree synthetic traces、node budget=12、unit budget=24、identity mapping 和 slot capacity 的 frozen face 内：

1. correctness chain PASS；
2. current-node coverage 为 2000/2000；
3. capacity compliance PASS；
4. observed state shape 为 pair-coherent：full=12、partial=0、empty=20；
5. GDN/ATT raw event count 呈两倍于 baseline 的模型内形状；
6. identity-mapping byte mass 与 baseline 闭合；
7. deterministic double-run 为 0。

### 仍不能支持

1. Candidate A 性能更好或更差；
2. 真实迁移开销更低或更高；
3. raw event count 可跨 node/unit 粒度比较；
4. compatible J 是跨粒度效果判据；
5. modeled byte mass 等于实测 I/O、带宽、延迟或经济成本；
6. seed 42 synthetic trace 可代表生产 workload；
7. Candidate A 可用于真实模型或生产 KV cache。

因此当前唯一一致门位仍是 `Candidate A Effect Verdict = LOCKED`。

## 2. Effect verdict 类型拆分

| 类型 | 问题 | 当前是否足够 | 需要的动作 |
|---|---|---|---|
| DV0. No-effect-verdict closure | 只保留机制知识，不做效果判定 | 足够 | 封存现有门位 |
| DV1. Simulator accounting effect | 在共同 accounting denominator 下，Candidate 是否改变 modeled migration byte load | 不足 | Design Revision |
| DV2. Instrumented runtime effect | 是否改变实测 migration latency / bandwidth / conversion cost | 不足 | 新 harness + Design Revision |
| DV3. Real-model / production effect | 在真实模型或生产 KV cache 下是否有效 | 不足 | 更高层设计 |

## 3. 不可作为 effect estimand 的候选

1. raw `rehy_count` 差值或比值；
2. raw `ext_count` 差值或比值；
3. unit count 直接折算 node count；
4. compatible `J = 0.69 × ext + 0.72 × rehy`；
5. identity-mapping byte mass 单独作为真实系统成本；
6. deterministic PASS；
7. correctness PASS；
8. pair coherence 或 partial=0；
9. hot/tree 单一结果的外推。

原因：这些读数来自不同粒度对象、不同 slot budget、不同事件语义或非实测成本口径，不能自动构成共同计量基础。

## 4. DV0：封存，不做 effect verdict

DV0 表示当前研究只接受机制知识，不做效果判定。优点是最小改动、不引入新测量义务、与 Contract 边界一致、不需要修改 Runner 或 Candidate A。代价是无法回答真实成本或性能问题，后续若再问效果仍需新设计。

## 5. DV1：Simulator accounting-effect verdict

DV1 不测真实性能，只在 simulator 内预注册共同 accounting denominator，比较 modeled migration byte load。

### 候选 primary estimand

对每个 workload / seed / trace family：

```text
MigrationByteLoad = rehydrate bytes read + externalize bytes written
Δ_MBL = MigrationByteLoad(Candidate A) - MigrationByteLoad(baseline)
```

候选 normalization：

```text
MBL_per_decode_step = MigrationByteLoad / decode step count
MBL_per_node_touch = MigrationByteLoad / node touch count
MBL_per_node_equiv = MigrationByteLoad / 78,246 KiB
```

Design Revision 必须选择且只选择一个 primary normalization；不得事后切换。

### 必须锁定的口径

1. byte 口径：GDN=61,440 KiB，ATT=16,806 KiB，node=78,246 KiB；
2. 方向口径：rehydrate 计 bytes read，externalize 计 bytes written；
3. conversion cost：identity mapping，0 modeled conversion cost；
4. capacity normalization 二选一：C1 slot-normalized（baseline 12 nodes，Candidate 24 units）或 C2 byte-normalized（相同 byte capacity）；
5. partial-state 处理：明确 GDN/ATT 可否不同时迁移；
6. workload 域：至少预注册 trace family 与 seed 数量；
7. 分析单位：step / touch / workload / seed 必须显式定义；
8. 判读形式：只报告估计量、差值、区间和域内结论，不得自动宣布“Candidate A 更优”。

### DV1 的 verdict 上限

若 DV1 外审通过并完成采数，最多只能支持：在指定 simulator、trace family、seed、capacity normalization 和 identity mapping 下，Candidate A 相对 baseline 的 modeled migration byte load 差值为 X。

它不能支持：Candidate A 真实迁移更快或更慢、生产成本更低或更高、性能更好或更差。

### DV1 代价

1. 需要新的 Design Revision；
2. 若修改 Runner 或新增 instrumentation，必须重做对应 correctness / provenance 门；
3. seed 42 现有 frozen face 不足以泛化；
4. 仍无法回答真实 runtime 效果。

## 6. DV2：Instrumented runtime-effect verdict

DV2 在真实执行路径或高保真 harness 中测量 migration runtime cost。

### 候选 primary estimand 家族

必须选择其一，不得混合：

```text
Δ_latency = migration path latency(Candidate A) - node migration path latency(baseline)
Δ_bytes = measured bytes read/written(Candidate A) - measured bytes read/written(baseline)
Δ_decode = decode wall time or throughput(Candidate A) - decode wall time or throughput(baseline)
```

### 最低测量要求

1. baseline 与 Candidate A 使用共同 workload、model、hardware 和容量口径；
2. 必须测量或明确排除 serialization、deserialization、copy、cache effect、allocation、synchronization、re-encoding 和 metadata bookkeeping；
3. runtime benchmark 必须交替运行并报告顺序效应；
4. 必须报告 cold / warm state；
5. 必须报告 p50 / p95 / p99 或等效分布，不得只报均值；
6. 必须定义失败、超时、swap、throttling 和 cache pollution 的处理；
7. 若 Runner 修改，必须重跑三层 correctness audit。

DV2 最多只能支持指定 harness、hardware、model、trace 和 workload 域内的 runtime-effect 结论。除非 DV3 明确采样生产配置，否则不能直接推广为生产收益。

## 7. DV3：Real-model / production-effect verdict

DV3 使用真实模型、真实 trace 和真实部署约束回答生产效果。当前不建议作为下一轮最小实验面，因为还缺少生产 trace 采样协议、容量压力分布、真实模型层形状与 unit 定义、production KV allocator/cache 行为、multi-tenant 干扰、SLO/failure model、成本与风险评估。

## 8. 推荐与硬边界

若确实要继续解锁 effect verdict，推荐下一轮先走 **DV1：Simulator accounting-effect verdict**：

1. 是当前证据链之后最小的跨粒度扩展；
2. 不把 modeled byte mass 冒充真实 runtime cost；
3. 先解决“共同计量基础缺失”这一核心 blocker；
4. 不需要立刻进入真实模型和硬件复杂度；
5. 若 DV1 显示 accounting 差异值得追问，再进入 DV2。

硬边界：

```text
DV1 即使 PASS，也只能得到 simulator accounting verdict；不得表述为 performance verdict。
```

若研究目标是真实性能效果，应直接设计 DV2，并把 DV1 仅作为辅助账本。

## 9. Design Revision 必须补齐的字段

外审通过前，以下字段缺一项即为 `NEEDS DESIGN`：

| 字段 | 必须回答 |
|---|---|
| verdict type | DV0 / DV1 / DV2 / DV3 |
| primary estimand | 精确公式与单位 |
| comparator | baseline、Candidate A、版本与 blob |
| capacity normalization | slot-normalized 或 byte-normalized |
| trace population | workload family、采样方式、数量 |
| seed policy | seed 数量、抽样规则、报告粒度 |
| unit of analysis | step / touch / request / workload / seed |
| primary normalization | 唯一归一化方式 |
| secondary metrics | 是否允许、如何防止 primary switching |
| measurement method | simulator accounting、instrumentation 或真实 profiler |
| decision rule | 估计量、区间、方向、非劣效或等价规则 |
| failure rule | violation、超时、缺数据、异常处理 |
| generalization domain | 明确禁止外推的范围 |
| provenance | Runner / baseline / Candidate A / data / artifact 绑定 |
| rerun rule | 修改 Runner 后必须重做 correctness audit |

## 10. 当前门位

```text
BASELINE REGRESSION                         PASS
RUNNER v2.2.1                              PASS
L1                                          PASS
L2                                          PASS
L3                                          PASS
DETERMINISM                                PASS
CORRECTNESS AUDIT                          PASS
EFFECT INTERPRETATION CONTRACT             PASS
TIER-1 MECHANISM EXTRACTION                PASS
EXTERNAL ACCOUNTING REVIEW                 PASS
MECHANISM SYNTHESIS REVIEW                 PASS
────────────────────────────────────────────
EFFECT VERDICT DESIGN REVISION             DRAFT v0.1
EXTERNAL DESIGN REVIEW                     REQUIRED
DV0/DV1/DV2/DV3                            UNSELECTED
CANDIDATE A EFFECT VERDICT                 LOCKED
RUNNER / BASELINE / CANDIDATE A            FROZEN
TIER-1 RERUN                               NOT REQUIRED
DATA COLLECTION                            LOCKED
```
