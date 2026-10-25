# Nodes-out Candidate A Effect Interpretation / Mechanism Synthesis Review v0.1

**状态**：`DRAFT / EXTERNAL SYNTHESIS REVIEW REQUIRED`  
**日期**：2026-09-22  
**边界**：本文件只把已外审通过的 Tier-1 mechanism accounting 组合为受控机制观察；不修改 Runner、baseline、Candidate A、Effect Interpretation Contract，也不重采数据，不给出 Candidate A 好/坏或 effect verdict。

## 0. 审计锚点

| 项 | 值 |
|---|---|
| Effect Interpretation Contract | `0918260` / PASS |
| Tier-1 mechanism accounting | `da5efa8` / PASS |
| Audited Runner | `f4d880e` / Runner v2.2.1 |
| Frozen baseline | `17bde28:trackE-residency/residency_policy_simulator_v3.py` |
| Baseline blob | `ff6d4e21df40db800e64bd5c949c39b3d77d22aa` |
| Tier-1 report | `trackE-residency/runs/NODES_OUT_TIER1_MECHANISM_20260922/TIER1_MECHANISM_ACCOUNTING_20260922.md` |
| Machine-readable ledger | `trackE-residency/runs/NODES_OUT_TIER1_MECHANISM_20260922/tier1_mechanism_accounting.json` |
| Extractor provenance | independent re-execution of unchanged Runner + read-only accounting |

外审已确认：Tier-1 extractor 不是第二套 Candidate policy；它只从 unchanged Runner 产生的事件做只读重放。  
外审同时记录：该通道是 **independent re-execution + read-only accounting**，不是 artifact-only extraction。本文不得把前者表述成后者。

## 1. 综合范围

本轮只综合以下已署名事实：

1. correctness audit PASS；
2. Effect Interpretation Contract PASS；
3. Tier-1 mechanism accounting PASS；
4. hot / tree 两个 frozen workload 的机器可读账本；
5. deterministic double-run；
6. source / artifact / baseline / Runner 绑定检查。

禁止引入未入档的新解释、新指标、新 workload、新 seed、新 normalization 或新 causal claim。

## 2. 已锁定机制事实

以下事实只能按其原文域陈述，不合并成 effect claim。

### F1. Current-node coverage

hot 和 tree 均为：

```text
M02 decode-ready        2000 / 2000
M04 current coverage    2000 / 2000
```

**允许表述**：在本 frozen face 中，Candidate A 每个 decode step 的当前 node 都具备 GDN+ATT decode-ready 状态。  
**禁止表述**：Candidate A 因此更快、更稳、更适合生产，或比 baseline 更正确。

### F2. Capacity compliance

hot 和 tree 均无容量超限：

```text
baseline:     resident nodes / 12
Candidate A:  resident units / 24
```

终态：

```text
Candidate full node   = 12
Candidate partial node = 0
Candidate empty node  = 20
Candidate GDN resident = 12
Candidate ATT resident = 12
Candidate total units  = 24
```

**允许表述**：两套模型各自满足自己的 slot capacity。  
**禁止表述**：12 node slots 与 24 unit slots 等价、压力相同或成本相同。

### F3. Observed pair coherence

在本 frozen face 中，Candidate A 的 acquisition 全部表现为 GDN+ATT full-pair acquisition：

```text
hot:  any-unit acquisition touches = 696
      full-pair acquisition        = 696

tree: any-unit acquisition touches = 1015
      full-pair acquisition        = 1015
```

终态与逐步聚合均未观察到 partial node。

**允许表述**：本 frozen face 观察到 pair-coherent residency shape；Candidate A 当前未表现出 partial-node state。  
**禁止表述**：Candidate A 结构上永远不可能产生 partial state；partial=0 证明其退化回 node granularity；或该现象适用于其他 trace / seed / budget。

### F4. Raw event count shape

模型内 raw counts 为：

```text
hot:
  baseline    rehy=696   ext=684
  Candidate   rehy=1392  ext=1368

tree:
  baseline    rehy=1015  ext=1003
  Candidate   rehy=2030  ext=2006
```

这些是不同 residency object 下的模型内计数。

**允许表述**：Candidate raw counts 是 baseline 的两倍形状这一 arithmetic fact。  
**禁止表述**：因此 Candidate 更差、更好、开销更高、效率更低，或应按 node/unit 直接折算。

### F5. Byte-mass closure

identity mapping 下：

```text
hot:
  rehydrate byte mass     baseline = Candidate = 54,459,216 KiB
  externalize byte mass   baseline = Candidate = 53,520,264 KiB

tree:
  rehydrate byte mass     baseline = Candidate = 79,419,690 KiB
  externalize byte mass   baseline = Candidate = 78,480,738 KiB
```

这是当前 accounting 的闭合结果：观察到的 GDN+ATT pair migration byte mass 与 node migration byte mass 相等。

**允许表述**：identity-mapping accounting closure。  
**禁止表述**：真实 I/O 相同、带宽成本相同、性能相同、系统开销相同；或将 modeled byte 等同于实测 bytes。

### F6. Compatible J disclosure

```text
hot:
  baseline    J=973.08
  Candidate   J=1946.16

tree:
  baseline    J=1422.87
  Candidate   J=2845.74
```

M13 仍只是兼容披露，不是主判据。

**允许表述**：按既有 node-era 公式披露的 compatible J 读数。  
**禁止表述**：Candidate 效率更低、成本更差、性能失败，或 J 差值可跨粒度归因。

### F7. Reproducibility and stop conditions

hot / tree 均满足：

```text
baseline regression        PASS
Candidate violations       0
deterministic diff         0
all stop conditions        false
```

**允许表述**：本 frozen face 可复现，且未触发停机条件。  
**禁止表述**：可复现性等同于正确性优势或性能优势。

## 3. 受控综合观察

以下观察只组合 F1–F7，不新增实验断言。

### S1. Node-equivalent residency accounting

在本 frozen face 中，Candidate A 的 observed byte mass 与 baseline identity-mapping byte mass 闭合；同时 raw unit event count 是 raw node event count 的两倍形状。

**综合表述**：  
当前候选的对象粒度从 1 node 拆分为 GDN+ATT 2 units，但在 observed pair-coherent 行为和 identity-mapping byte accounting 下，migration byte mass 与 node-level baseline 闭合。该现象只说明 accounting 层闭合，不说明真实系统成本或性能等价。

### S2. Pair-coherent state shape

Candidate A 具备 GDN/ATT unit-level state 表示，但本 frozen face 的所有 acquisition 均表现为 full-pair acquisition，终态和逐步聚合中 partial=0。

**综合表述**：  
当前机制账本支持的观察是“在当前 trace / seed / budget / tie-break / policy 下，驻留状态呈 pair-coherent shape”，而非“Candidate A 的 unit 粒度在结构上总是退化为 node 粒度”。

### S3. Capacity-shape correspondence

Baseline 的 node-slot occupancy 与 Candidate A 的 unit-slot occupancy 在各自分母下呈现相同的 observed occupancy shape；两套模型均无容量超限。

**综合表述**：  
这是各自容量模型内的 shape correspondence，不是 12 node slots 与 24 unit slots 的等价证明。

### S4. Compatible J difference is not an effect verdict

Candidate 的 compatible J 高于 baseline，但该公式由各自 raw counts 组成；当前没有可比较的跨粒度 effect estimand。

**综合表述**：  
J 差异只能作为 node-era compatibility disclosure 的事实记录，不能解释为 Candidate A 更差，也不能解释为 Candidate A 的真实成本。

### S5. Mechanism synthesis is not performance synthesis

correctness PASS、contract PASS、accounting PASS 与 deterministic PASS 组合后，仍不足以给出 Candidate A effect verdict。

**综合表述**：  
当前证据支持的是受控机制观察；不支持优劣、效率、生产可用性、真实系统因果或跨 workload 泛化结论。

## 4. Effect verdict 判定条件

以下条件在当前门位全部不满足，因此 Effect Verdict 继续 `LOCKED`：

1. 没有预注册的跨粒度 effect estimand；
2. 没有实测 migration latency / bandwidth / conversion cost；
3. 没有多 seed 或跨 trace family 泛化证据；
4. 没有真实模型或生产 KV cache 证据；
5. raw unit/node counts 不构成共同计量基础；
6. identity-mapping byte mass 不等于实测系统成本；
7. compatible J 不被 Contract 允许作为主判据。

若未来要解锁 effect verdict，必须先走新的 Design Revision，预注册比较 estimand、normalization、workload 域、seed 域和测量口径，并重做相应 correctness / provenance 门位。

## 5. 外审清单

外部 synthesis reviewer 应核验：

1. 本文所有 F1–F7 是否逐项来自 `da5efa8` 已署名 ledger，而不是新解释；
2. S1–S5 是否只组合已允许事实；
3. F3 / S2 是否明确区分 observed pair coherence 与 structural impossibility；
4. F4 / S4 是否明确阻止 raw count 和 compatible J 的效果解释；
5. F5 / S1 是否明确保留 identity-mapping accounting 边界；
6. 本文是否没有给出 Candidate A 更好 / 更差 / 更高效 / 更低成本的结论；
7. 本文是否没有宣布 Effect Verdict 解锁；
8. 本文是否没有要求重跑 Tier-1 或修改 Runner。

## 6. 当前门位

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
────────────────────────────────────────────
MECHANISM SYNTHESIS REVIEW                 DRAFT v0.1
EXTERNAL SYNTHESIS REVIEW                  REQUIRED
CANDIDATE A EFFECT VERDICT                 LOCKED
RUNNER / BASELINE / CANDIDATE A            FROZEN
TIER-1 RERUN                               NOT REQUIRED
```
