# PALACE-1 E0 — Checkpoint Decomposition & Dependency Tracing

日期：2026-09-30  
状态：`E0 COMPLETE / AWAITING SECOND-LAYER`  
Gate：`PALACE1 / Controlled Recovery Evidence`（实验顺序 E0→E1→E1.5→E2→E3）  
对象：最新真实 checkpoint `default_5401315f-…/main`（safetensors 713,859,116 B
+ meta.json 43,641 B）+ 产品仓 `dc12a0c` 源码依赖追踪  
方法：**只读**（safetensors 头解析 / meta 字段图 / 逐字段 reader grep）；
零删除、零修改、零写入；E1/E1.5 的运行时实验留待独立执行

```text
observed physical fact ≠ candidate layer classification ≠ final verdict
（终判 = E1/E1.5/E2/E3 运行时实验；本文件只做分解与依赖追踪）
```

## 1. safetensors 物理分解（4.7G 级对象的内部结构）

格式：标准 safetensors，**小端 u64** 头长（8,236 B）；80 张量连续排布
（data 713,850,880 B，与文件大小严丝合缝）。

```text
张量命名 = "<layer>.<0|1>"——40 层 × K/V = 80
dtype 混合：BF16 × 50 + F32 × 30（逐层异构）
形态两类：
  [1, 3, 8192]      BF16 —— 固定尺寸层态（GDN/线性注意力层，数量多数）
  [1, 2, 31712, 256] BF16 —— 注意力 KV（2 KV 头 × 31712 token × 256 维）
__metadata__ = 逐层条目（"L.0"/"L.1" 字符串对，如 "0.0.0"="2"）
```

**结构性观察**：31712 = 序列长度——**position 在 KV 形状上有物理影子**
（注意力层的 token 数随对话长度增长；GDN 层为固定态）。但这是 token 级
长度，不是 Contract 的逻辑 position（轮次数）——两者不同层、不同单位。

对照：prefix-pool 快照（另一 namespace）= 96 张量 = 48 层 × K/V，
`[1,4,15,128]` BF16（4 头 × 15 token）——**同一机制、按 boundary 粒度
存储的更小快照**；两 namespace 对应不同模型架构（4 头/128 维 vs 混合
GDN 40 层）。

## 2. meta.json 字段图（43,641 B）

```text
keys = cacheSHA256 / checkpointGeneration / history / modelId / savedAt /
       storageKey（本样本：无 forkPoint、无 kvFingerprint——见 §4）
history = 17 条（system ×1 / user ×6 / assistant ×7 / tool ×3），
          内容合计 33,925 字符，含 tool 消息（agent 工具循环被完整持久化）
```

**格式演化风险（实测）**：本 checkpoint **缺 kvFingerprint**（该字段
2026-09-18 Phase B 补齐，`decodeIfPresent` 向后兼容）——`SessionCache
Metadata` **无 version 字段**，102 个 checkpoint 横跨多代格式；恢复时
kvFingerprint = nil → pool reuseMiss → 全量重建（pool 连续性收益清零）。
对照：`PrefixSnapshotSidecar` **有** `version:1` 字段。

## 3. 逐字段 dependency tracing（writer / readers / 候选层）

| 字段 | writer | readers（全仓 grep 实测） | 候选层 |
|---|---|---|---|
| `storageKey` | AgentExecutionKey（StreamTokenFilter:170）+ performSave 命名 | **无处不在**：会话池寻址、文件命名、`executionID:` 喂给 Lab 契约调用（:764/:1192）、lineage.attachCheckpoint | **IDENTITY** |
| `history`（transcript） | performSave（historyJSON） | performLoad 重建 ChatSession（makeChatMessages）、pool coveredMessages（:747）、delta 计算（:795）、rollforwardRisk（:816） | **SEMANTIC** |
| `checkpointGeneration` | :1527（每保存新 UUID） | 仅 load fail-closed 校验（:1614-1626） | INTEGRITY / commit-identity |
| `cacheSHA256` | :1526（流式哈希） | 仅 load 校验（:1616-1626） | INTEGRITY |
| `modelId` | :1534 | load 同源校验（:1628-1631） | ENVIRONMENT / compatibility |
| `kvFingerprint` | performSave + ManagedSession | pool namespace（PrefixPool:71）、Ref 派生（:59）、reuse 检查（HTTPServer P0-5：失配 → 全量 prefill） | OPTIMIZATION / reuse |
| `forkPoint` | forkSessionBranch（:1834-1838） | **无 reader（write-only）** | LINEAGE provenance（已写未读） |
| `savedAt` | :1535 | retention 排序（Retention:111/121） | GOVERNANCE |
| safetensors payload | performSave（官方 saveCache） | performLoad（loadPromptCacheSnapshot） | **REPRESENTATION** |
| `checkpointDirty` | 生成轮置位 | 驱逐保护（:417-443）+ 自动保存触发 | LIFECYCLE |

## 4. E0 结构发现

```text
D-1 混合物证实：单个 checkpoint = SEMANTIC（transcript）+ IDENTITY
    （storageKey）+ INTEGRITY（generation+SHA）+ LINEAGE（forkPoint）+
    ENV（modelId）+ OPTIMIZATION（kvFingerprint）+ REPRESENTATION
    （safetensors）七层候选共存——44KB 与 4.7GB 承载的是不同层
D-2 position 有物理影子但非 Contract position：KV 形状编码 token 长度
    （31712），逻辑轮次只在 transcript 结构中隐含
D-3 forkPoint write-only：lineage provenance 已写但无消费者——登记为
    观察事实（是否应被读 = 后续 gate 的事，本审计不设计）
D-4 格式无版本字段：kvFingerprint 缺失样本实测存在 → 旧格式恢复时 pool
    收益清零（reuseMiss）——格式演化风险的实际形态
D-5 tool 消息进入 durable transcript：agent 工具循环是 durable 语义的
    一部分（E3 sufficiency 问题的输入）
D-6 官方格式依赖：cache 格式由 mlx 官方 saveCache 定义（「SimiGo 不自
    定义」，.safetensors 后缀按官方 IO 分派）——representation 层的
    可重建性与官方格式绑定（E1 的实验变量之一）
```

## 5. 对实验矩阵的输入（不预答）

```text
E1（删 safetensors）：R0 可识别 = meta 三键（storageKey/generation/modelId）
    仍在——预期可达；R1/R2 取决于 makeChatMessages 重建路径是否可无 KV
    启动（代码显示 load 路径 fail-closed 于文件缺失 → R1 预期 FAIL，
    但这正是实验要证的）；R4 的 recompute 路径 = 客户端协作式（全量
    对话），非系统自主
E1.5（篡改）：generation/SHA = 预期拒绝（INTEGRITY 判据已在代码）；
    modelId = 预期拒绝（compatibility）；storageKey 篡改 = 预期「找不到
    checkpoint」（IDENTITY 寻址）；forkPoint 篡改 = 预期无响应
    （write-only）——预期全部来自代码追踪，实验验证之
E2（删 prefix）：pool 路径自愈 + nil 回退全量 prefill 已在代码——预期
    仅性能损失（待实验证）
E3（只留 meta）：transcript + modelId 在手，缺的是 KV 重算的执行环境
    与 position→continuation 的映射判据——「最小缺失信息」的候选 =
    无（代码层）？有（运行环境/客户端协作）？= 实验对象
```

## 6. Non-claims

```text
✔ 只读（safetensors 头解析只读前 8KB + os.path.getsize；meta.json 读取；
  grep）——零删除、零修改、零写入
✔ 本文件不给出 E1–E3 的结论；候选层分类是追踪假设，终判 = 运行时实验
✔ 不修改 Contract / 产品代码；不设计 PALACE 语义 / 存储
```
