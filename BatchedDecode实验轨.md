# SimiGo 实验轨章程 — Controlled Batched Decode

**立项：** 2026-09-05 · **状态：** Phase 1（观测基建）已落地 · **总开关：** Phase 2 起置于 `RuntimeTuning`
**定位：** LAN 多用户并发吞吐 —— 把"GPU 时间分片"升级为"批内真并发"
**纪律：** 白皮书 §58 实验轨道 / 铁律 35（Benchmark 背书）/ 铁律 37（一次一个变量）/ §59（未验证不进 Core）

---

## 1. 必要性证明（实测数据，2026-09-05）

| 场景 | 每路 decode | 聚合 |
|---|---|---|
| 单流 | 28–33 tok/s | 28–33 |
| 3 流并发（实测，1×29.8K Agent + 2×200B 测试） | **7–10 tok/s** | **≈25（恒定）** |

聚合吞吐 ≈ 单流总量：GPU 按 token 时间分片，每流解码都完整读取激活权重（MoE 激活 3B ≈ 2GB+/token），N 路并发 = N× 权重读取。内存侧无压力（weight-aware budget + KVTRIM 后 rss 7.1G / sw 1.59G 平稳）——**唯一瓶颈是带宽复用**。

## 2. 依赖侦查结论（Phase 0，已实测包源码）

| 项 | 结论 | 影响 |
|---|---|---|
| `ModelContainer.generate` | prefill 独占（`context.read`），**decode 多流并发**（权重只读） | 并发调度无需改依赖 ✓ |
| `KVCache` 协议 | 单一 `offset` + 均匀 causal mask（`createCausalMask(n:offset:)`） | 通用连续批处理需自定义 BatchedKVCache |
| SDPA / MoE gate | batch 原生（B 维独立注意力；gate 逐 token） | 前向数学 batch-safe ✓ |
| RoPE | `applyRotaryPosition(_:to:offset: RoPEOffset?)` 单一 offset | **每序列位置需 Phase 2 验证 `RoPEOffset` 是否支持向量偏移** |
| 投机解码 | 基建齐备（`speculative_generate_step` / draftModel 路径）；**本模型（Qwen3_5Moe）无 MTP 头** | 路线 C 需外挂兼容 tokenizer 的小 draft，仅单流加速 |

## 3. 技术路线

- **A（主线）Pad-to-align 批处理**：自建 `BatchedKVCache`（K 序列 pad 至组内 S_max，B 维独立注意力天然隔离跨序列）+ 逐序列 RoPE 位置 + 自建 decode loop（绕过 `MLXLMCommon.generate`）。预估 400–600 行 + 模型前向手术。
- **B（否决）同长对齐合并**：仅合并 KV 等长流——LAN 场景几乎不自然对齐，无价值。
- **C（替代路线，单流）投机解码**：需外挂 draft 模型，tokenizer 兼容性风险；不解决并发分片，挂起。

## 4. 阶段计划与成功标准

| 阶段 | 内容 | 准出标准 |
|---|---|---|
| **Phase 1（✅ 本次）** | 并发观测基建：`[GENERATION START] decodeStreams=N`、State 计数、峰值统计 | 三流实测 `decodeStreams=3` 可见 |
| **Phase 2（⛔ NO-GO 门）** | `BatchedKVCache` 原型 | 见 §6 侦查结论：混合架构阻断 |
| **Phase 3** | pad-to-align + 逐序列 RoPE + 流进出（join/leave） | 随 Phase 2 阻断 |
| **Phase 4** | LAN 双客户端 Stress | 随 Phase 2 阻断 |
| **决策** | 依赖升级/上游合入后重开 Phase 2；否则维持现状 | 铁律 35/36 |

**回退**：Phase 2 起全部代码置于 `RuntimeTuning.batchedDecodeEnabled`（默认 false）之后，删除即回退；不改 Logical State Model（铁律 50）。

## 6. Phase 2 NO-GO 门（2026-09-05 侦查结论）

对 mlx-swift-lm 3.31.4 包源码逐层核查后确认：

```text
1. Nail-Qwen3.6 / Tiel-Coder 均为 Qwen3_5MoeForConditionalGeneration
   = Mamba(线性注意力) + FullAttention 混合架构（Qwen35MoEModel: Qwen35Model）
2. FullAttention 层消费 cache.ropeOffset（Qwen35.swift:363，
   applyRotaryPosition 支持 .batch(MLXArray) 逐序列位置 ✓）
3. 线性注意力层使用 MambaCache（递归状态），无 batch 语义，
   自定义 BatchedKVCache 无法覆盖 Mamba 层（状态语义在包内部）
4. 模型侧不消费 LMInput.Text.mask（左填充掩码无注入点）
5. 结论：不等长批处理需要上游（mlx-swift-lm）为混合架构提供
   batch 语义的 MambaCache + 逐序列 RoPE 管线 —— 属上游工程
```

按铁律 82（正确性优先）与 §54（先证明再固化）：**在依赖提供 batch 语义前，不实施批处理解码**。带病上线（静默输出污染）的代价高于收益。

## 7. 修订后的 LAN 容量路线

```text
现状（KVTRIM + weight-aware budget 已落地）：
    1–2 路 30K Agent 并发 + 轻用户，每路 25–33 tok/s
扩容杠杆（按可行性排序）：
    1. 多节点：第二台 Mac 同构部署 + 客户端路由（线性扩容，零代码）
    2. 换 KV 更轻模型（dense 7–14B 4bit，KV/token 降 3×，并发 ×3）
    3. 上游依赖升级（mlx-swift-lm 混合架构 batch 支持）后重开本实验轨 Phase 2
```


## 5. 已确认的非目标

- 不做 PagedAttention 级 KV 分页管理（依赖 KVCache 形状限制）；
- 不动 SessionGenerationGate 语义（铁律 25/26）；
- 不为本能力改动 Protocol 层（§3.1 边界）。
