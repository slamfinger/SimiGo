# ES-T3 Gate A Results — Representation Component Census

日期：2026-09-30  
状态：`T3A_CENSUS_COMPLETE / VERDICT = T3-A2 CONFIRMED + T3-A3 PARTIAL / AWAITING SECOND-LAYER`  
唯一问题：**GDN 与 Attention 组件在完整生命周期中是一个单元还是两个可
区分的计算构件？**  
方法：只读（vendor 源码 Qwen3Next.swift / KVCache.swift / ChatSession.swift
/ 语言模型基类 + E0 工件分解 + 本链既有 file:line）；零修改零扰动。

## 1. 七问事实表

### Q1 生命周期绑定 — **durable 融合 / 内存分层**

```text
durable 边界：save = save(arrays: flattenedData, …) 单次展平写入全部
  张量（KVCache.swift vendor 实现）；load = loadArraysAndMetadata(url)
  全量读入后按 cache_classes 拆分。无按组件入口。
  产物 = 单 safetensors + 单 meta.generation + 单 SHA 门（E0/E1 已证）。
内存粒度：PromptCacheSnapshot.cache = [KVCache]（逐层数组）；
  MambaCache 可下标 cache[0]=convState / cache[1]=recState
  （Qwen3Next.swift:253-254）。
⇒ 组件粒度存在于【内存】，跨不过【durable 边界】。
```

### Q2 position 承载 — **attention 显式 / GDN 隐式**

```text
attention KV [1,2,31712,256]：尺寸 ∝ position（E0 实测 31712 token）；
  vendor 以 offset/ropeOffset 显式追踪位置（Qwen3Next.swift:93-94、
  KVCache.swift:48/:202）
GDN 固定态 [1,3,8192]：形状与 position 无关——position 被递归态
  【隐式包含】，不可查询
⇒ position-dependent information 的显式载体 = attention KV。
```

### Q3 continuation 参与 — **两者同时必需，无单组件路径**

```text
GDN 层 forward（Qwen3Next.swift:240-258）：消费输入 token + prev
  convState/recState → newConvState/newRecState——逐层推进
attention 层（:88-101）：消费 KV 全范围 + 新 query（rope offset 定位）
每个 next-token 计算同时消费两类组件；无「仅 GDN」或「仅 KV」的
  代码路径（本轮 grep 零命中）。
```

### Q4 独立入口 — **durable/使用面均无组件粒度 API**

```text
loadPromptCacheSnapshot = 全量（且 loadPromptCache 明确拒绝带 state 的
  cache：「Prompt cache contains model state; use
  loadPromptCacheSnapshot(url:) to restore it」——vendor 文档化限制）
ChatSession init = 整 snapshot（cache: PromptCacheSnapshot + state 同行）
product loadSessionCache = 整文件
⇒ 单组件读取/恢复入口：不存在。
```

### Q5 更新方式 — **确认异构**

```text
GDN：in-place 固定尺寸替换（cache[0]=newConvState; cache[1]=newRecState
  ; cache.advance(N)）——每步重写同尺寸状态
attention KV：append-only 增长（新 K/V 追加，offset 前移）
⇒ 更新方式结构性异构（replace vs append），vendor 代码直接可见。
```

### Q6 架构依赖 — **确认不对称**

```text
GDN/Mamba = Qwen3-Next 混合架构特有（线性注意力族）
attention KV = 通用 transformer 分量（通用 KVCache 类处理）
vendor 以通用 cache-classes 机制承载两者，但组件本身架构来源不对称。
```

### Q7 可替换性 — **完全共享，零区别机制**

```text
同一 generation、同一 SHA 门、同一文件单元、同一 save/load 调用——
系统内不存在任何按组件区别对待的机制（Q1–Q6 的粒度都未进入
durable/产品面）。
```

## 2. 生命周期分道图（按组件分道，实测）

```text
                    生成（prefill/decode，每 token）
                     GDN: 输入+prevState → newState(replace)
                     ATT: 新 K/V → append(offset 前移)
                              │
                    save（durable 边界）
                     GDN ──┐
                     ATT ──┴──> flatten → 单 safetensors + 单 meta
                              │        （组件粒度在此【消失】）
                    load
                     全量读入 → cache_classes 拆层（内存恢复分层）
                              │
                    ChatSession 消费（每 next-token）
                     GDN + ATT 同时消费（无单组件路径）
                              │
                    下一 token
```

## 3. T3-A1…A4 归类

```text
T3-A1 纯物理分解      = REJECTED（replace vs append、显式 vs 隐式
                        position、架构不对称——物理行为即已不同）
T3-A2 计算语义差异    = CONFIRMED（position 显式载体=attention；
                        递归计算摘要=GDN；更新方式/架构来源异构）
T3-A3 独立生命周期    = PARTIAL（内存粒度存在：[KVCache] 逐层 +
                        cache[0]/[1] 下标；durable 边界融合——
                        独立生命周期未跨过 durable 边界）
T3-A4 无法形成独立边界 = REJECTED（边界存在且可指认：durable flatten
                        点 + 单组件内存入口缺失点均可定位）
```

**复合裁定：T3-A2 CONFIRMED + T3-A3 PARTIAL（in-memory only）**——
按预注册映射：**A2/A3 成立 ⇒ 具备申请 Gate B（Component Necessity
扰动矩阵）的条件**，申请权归 human。

## 4. observed / inferred / unknown

```text
OBSERVED（file:line）
  Q1 融合 save/load（vendor KVCache.swift 单次 flatten 写入/全量读入）
  Q2 shape 事实（E0）+ ropeOffset 显式追踪（Qwen3Next:93-94）
  Q3 双组件同时消费（GDN forward :240-258 / attention :88-101；
     无单组件路径——grep 零命中）
  Q4 loadPromptCache 拒绝带 state cache（vendor 文档化）
  Q5 replace vs append（:253-255 / attention append）
  Q6 GDN=Qwen3Next.swift 专属 / KVCache 通用类
  Q7 单 generation/SHA/file
INFERRED
  position 显式载体=attention；递归摘要=GDN（从 shape/更新方式+架构
  语义合成——推断级，最终语义判定归 Gate B）
  durable 融合点 = formation gap 的物理坐标（与 ES-D1 J-C 对齐）
UNKNOWN
  单组件扰动后的计算后果（Gate B）
  GDN 分量能否独立承载 continuation（Gate B/C）
  第三形态（非-KV 压缩载体）的存在性（未证，§3 刹车延续）
```

## 5. 停止

```text
Gate A 完成（七问事实表/分道图/T3 归类/三分清单四交付齐）→ 按指令
立即停止。Gate B 申请权归 human；T3-B/C/D 保持 LOCKED。
```
