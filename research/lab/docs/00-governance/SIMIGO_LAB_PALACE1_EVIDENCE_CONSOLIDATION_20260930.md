# PALACE-1 Evidence Consolidation — Six-Experiment Chain

日期：2026-09-30  
状态：`EVIDENCE CONSOLIDATION COMPLETE / AWAITING SECOND-LAYER`  
范围：E0 / E1(SEALED) / E1.5 / R2-trace / R2n / E2 / E3 全链封装  
上游参照：Contract v1.0（UPSTREAM REFERENCE）；各实验设计/结果文档  
（本文只引用不重述；每个实验的事实/推论/未证明在此分层定格）  
性质：证据封装——不是 PALACE schema，不是新实验设计，不是 gate closure

```text
observed fact ≠ inference ≠ unproven（本文每一条都落在这三类之一）
```

## 1. 逐实验封装

### E0 — Physical decomposition（`ed6cb87` 前置审计 + 6122ffc/6a1b659 provenance）

```text
FACT    checkpoint = safetensors（80 张量 = 40 层 × K/V，BF16/F32 混合，
        KV 形状含 token 长度物理影子）+ meta.json（transcript 全文/modelId/
        generation/cacheSHA256/storageKey）；prefix-pool 与登记 schema 逐字
        吻合；durable 实物由产品侧写入（writer = NativeMLX performSave，
        三触发路径；retention 预算 64GiB/16GiB）
FACT    forkPoint write-only；kvFingerprint 102/102 物理缺席（运行二进制
        早于 repo HEAD）；schema 无 version 字段
INFERENCE  durable 实物承载的语义与 Contract 五元组不同构（F-1）——
        已被 R2-trace 精化：storageKey↔executionID 运行时映射存在，
        缺口在 durable schema 未完整表达契约语义
UNPROVEN 删除/重建行为（E1/E1.5/R2n 后续补齐）；产品仓外的接线细节
```

### E1 — Representation loss（设计 9953792 / interim dd825cb / SEALED）

```text
FACT    R0 = IDENTIFIED（meta 三键自足识别）；
        R1 = FAILED-FAIL-CLOSED ×3（缺失 safetensors，SHA 校验前的
        文件存在性检查）
FACT    原生 checkpoint restore 路径把 Physical Representation 作为
        恢复前置条件
INFERENCE  R1 失败 ≠ State 失败（隔离守卫三次拦截本身 = 安全基建有效）
UNPROVEN R2/R3/R4 运行时观测（执行边界封存；capability 由 R2-trace 补齐）
```

### E1.5 — Metadata dependency perturbation（设计 8961ef6 / 结果 263700c）

```text
FACT    6/6 零偏离：meta.storageKey 字段值扰动被接受（无交叉验证）；
        history 扰动被接受（transcript 无完整性门）；modelId 异值拒
        （兼容门）；generation 空拒/异值受（presence-only）；
        cacheSHA256 异值拒（仅 safetensors 字节比对）
INFERENCE  restore 验收边界 = 保护/兼容机制，与语义载荷分层
UNPROVEN necessity（本轮刻意不答——R2n 接手）
```

### R2-trace / R2n — cold reconstruction 与 history necessity（f3e49f8 / 132b9b6）

```text
FACT    cold reconstruction 是产品一等分支（NativeMLX:763-778，无
        checkpoint/pool/lineage 依赖）；产品配置面（env + static-var
        tunable）可实现零 durable 写入运行
FACT    P-N1 greedy 确定性（n0a ≡ n0b）；P-N2 内容扰动 → continuation
        质变；P-N3 tool 历史删除 → 指代崩塌（"I don't know what the
        probe refers to"）
INFERENCE  history = observed continuation-bearing durable information
        （integrity + necessity 双边界）；隔离问题被产品配置面消解
        （A/B/C 不再需要）
UNPROVEN 普适性（单样本、单 probe、贪心——存在性证明）
```

### E2 — Prefix Pool dependence（76f1664）

```text
FACT    池缺席运行（SIMIGO_PREFIX_POOL=0）语义能力完整（R2n 归位）；
        只读 admission 探测：think:1 fp=none → HIT 17/17（真实池存有
        本会话全覆盖快照）；指纹/think 变体正确 MISS
INFERENCE  Prefix Pool = 可替换性能 Representation：
        continuation 的加速表示 ≠ continuation 的唯一载体
UNPROVEN 池命中 vs cold reconstruction 的 greedy 逐 token 等价
        （pool-enabled generate 写真实池，授权边界外——【不做】，
        human 已裁定不为闭环补高风险实验）；性能结论（纪律性排除）
```

### E3 — Meta-only locus ladder（设计 d5157f1 / 结果 aa76f95）

```text
FACT    4/4 零偏离：C-0 全历史 ANCHORED（准确概括）；C-1 位置回退
        ANCHORED（细节锚存活）；C-2 主题缺席 UNANCHORED 且模型虚构
        （persona 先验驱动的貌似合理、完全错误概述）；C-3 仅 system
        UNANCHORED（persona 元评论）
INFERENCE  continuation-bearing 语义住在会话正文（含 tool 执行历史），
        不在 persona/寻址/保护/兼容字段
UNPROVEN 普适性；语义缺席检测机制（见 RF-1——只登记现象，不规定方案）
```

## 2. 最终字段/对象角色矩阵

| 对象 | restore 路径角色 | continuation 路径角色 | 证据 |
|---|---|---|---|
| caller key / 文件名 | 寻址（fail-closed 于缺失） | **寻址 carrier（同 key = 同 branch）** | E1-R0/R1；R2-trace |
| history（含 tool） | 无保护载荷（E1.5-Q2） | **semantic continuation carrier** | R2n P-N1/N2/N3；E3 C-0…C-3 |
| modelId | 兼容门（拒异值） | compatibility context（container 选择） | E1.5-Q3；human 裁定移外围 |
| generation | presence commit marker | 不读 | E1.5-Q4a/b |
| cacheSHA256 | 表示字节完整性 | 不读 | E1.5-Q5 |
| safetensors payload | 恢复前置（E1-R1） | 可替代（cold prefill） | E1 + R2-trace/R2n |
| Prefix Pool | — | 可替代加速（缺席不失语义；在场 17/17 命中） | E2 |
| meta.storageKey 字段值 | informational（无校验） | 不读 | E1.5-Q1 |
| forkPoint | write-only | 不读 | E0 |
| kvFingerprint | 物理缺席（旧格式）→ reuse 优化 | 不读 | E0 |

## 3. Research Findings register

### RF-1 — Semantic Absence Is Not Self-Evidently Detectable

**现象（E3-C-2，实验发现）**：语义正文从上下文消失后，模型不报错、不
拒答，而是从 persona 先验生成貌似合理、与真实会话无关的 continuation
（虚构概述）。

**当前系统的对照**：Runtime 层的失配（SHA/generation/model/representation
缺失）全部 fail-closed 可检测；**语义缺席没有任何检测面**——调用方无法
区分 grounded 与 ungrounded 输出。

**边界**：本 finding 只登记现象与危险性（虚构 ≠ 失败，无法被调用方察觉）；
不规定任何解决方案、不升级为产品缺陷判定。解决方案属未来独立 gate。

### RF-2 — Restore dependency ≠ Continuation dependency

同一产品内并存两条依赖结构：

```text
native restore    依赖 safetensors（E1-R1 fail-closed）
continuation      依赖 history + caller-key（R2n/E3），表示可整体替换
                  （E1 KV / E2 Pool）
```

含义：**Physical Representation 消失 ≠ continuation capability 消失**——
以实验方式确立（非架构推导）。

## 4. Nucleus statement（elevated，scope 钉死）

```text
Observed continuation nucleus candidate
  = addressing carrier（caller key）
  + semantic continuation carrier（conversation history，
    including tool-execution history）

限定（不得省略）：
  · 「当前 workload / 当前产品 continuation mechanism 下观察到」
  · 非 PALACE 普适最小 State 定理
  · addressing 与 semantic 是性质不同的两个 carrier（找哪个 session /
    此前发生了什么），不合并为单一字段集合
  · modelId = compatibility context（外围），非 nucleus 组成
```

## 5. 可进入 PALACE framing 的陈述（合法边界内）

```text
✔ 系统内自然存在两个生命周期不同的侧面：
  durable semantic side（caller-key + history，可脱离表示存活并驱动
  continuation 重建）
  physical acceleration side（KV checkpoint / Prefix Pool，可丢失、
  可重建、可替换）
✔ Physical Representation 可删除/替换/再生，而 continuation 依赖的
  语义信息可独立保存——已有工程实例
✔ 语义缺席的失败模式是静默虚构（RF-1），任何长期语义载体设计必须
  面对该现象
✔ restore 保护机制（SHA/generation）与 continuation 需求是两类职责
```

## 6. 禁止进入 PALACE schema 的（当前）

```text
❌ 字段模型 / nucleus 的 schema 化（nucleus 仍是 observed candidate）
❌ 语义缺席检测机制设计（RF-1 只登记现象）
❌ 把 caller-key/history 命名为 State 或 PALACE 字段
❌ storage / persistence format / API 选择
❌ 池命中 greedy 等价性补验（高风险、human 已裁定不做）
❌ 普适最小 State 定理表述
❌ 性能结论（全程无计时 claim）
```

## 7. Gate state

```text
E0/E1.5/R2/E2/E3 = COMPLETE；E1 = SEALED
Evidence chain   = CLOSED（本文封装）
PALACE framing   = OPEN（gate 产物 = 研究边界，即 §5；schema NOT STARTED）
Next cut         = 由 human 决定（framing registration / 其他方向）
```
