# SimiGo 架构 2.0 预研报告（2026-09-20）

**性质**：2.0 预研方向定稿（对证收敛版）。本文档只登记方向、机制假设与
验收标准，不含实现；所有引用数据附出处，未核实项显式标注。
**来源**：架构 2.0 讨论文稿（外审长文，"分页/分散/合并计算"两条路线）
× 本仓库现状逐条对证（2026-09-20 会话，三轮修正收敛）。
**地位与边界**：1.7（build 5）已封版。本文档治理 2.0 预研实验室空间，
不触碰 1.x 发布线。README_base（铁律 1–99）仍是 1.x 权威准则；2.0 若
成立将另立基线，不从本文档自动继承。
**修订**：v1.1（2026-09-20 第二轮）——并入开源对重扫描：核心目标重述
（§1.1）、去重地图（§4.1）、Track B 边界收窄与上游联动（§5.1）、
止损条件（§5.1）、出处增补（§8）。
v1.2（同日）——本文档自主仓移入本仓 `docs/architecture/`：2.0 材料
（战略文档 + 实验代码 + 记录）全部归实验室仓，主仓
（slamfinger/SimiGo）回归纯产品线。

---

## 一、问题定义

外审文稿提出两条继续突破本地大模型能力边界的路线：

**路线 1（硬件扩容）**：统一内存 64G → 256–512G → 可承载 70B/100B+ 模型。
SimiGo 的义务不是提升模型智力，而是**不把当前内存规模编码成永久边界**
（加载、内存生命周期、KV、OOM/swap、长时间运行稳定性不因规模失效）。

**路线 2（计算拆解）**："分页、分散、及合并计算"。计算对象不再必须等于
"一个模型 + 一次完整上下文 + 一次完整推理"：

```text
完整 Context → 拆解 → 多个 Page 独立计算 → 中间状态合并 → 二次推理 → 结果
```

外审对现状的核心判断（经对证成立）：

> SimiGo 已走进路线 2 的前半段（chunked prefill / KV checkpoint /
> prefix reuse），缺的是中间的 **Execution State 层**；且 F0 探针已实证
> 摸到这堵墙——MLXLMCommon 公开面无 sequence identity。

### 1.1 核心目标重述（v1.1）

2.0 的目标不是"让 256K Prefill 更快"，而是：

> **让一次昂贵的长上下文计算成为可复用、可分叉、可恢复的
> Execution State——一次计算，多未来（compute once, multiple futures）。**

Track A 与 Track B 是同一目标的互补两半：A 回答"一次 Prefill 能不能
**更快**"（单次计算效率），B 回答"一次 Prefill 能不能**不重复做**"
（计算资产化）。

**定位（v1.1）**：SimiGo 2.0 不是另一个 vLLM / SGLang，更不是重写 MLX。
它是建立在 Metal → MLX → mlx-swift-lm 之上的 **Apple Silicon 长上下文
Execution Runtime（研究型）**——在轮子之上研究轮子之间没有解决的那一层。

---

## 二、对证结论：两条路线的可实施性

### 2.1 路线 1：可实施，低成本，条件已满足

- 上限已是 Runtime Tuning 而非架构常量：
  `RuntimeTuning.swift:8-12`（`mlxMemoryLimitBytes = 22 GiB`、
  `mlxCacheLimitBytes = 4 GiB`）。
- 2.0 语境下直接演进为 **Track D（Adaptive Memory，见 §5.4）**：不再
  假定"机器有多少内存"，而是运行时知道"现在能安全使用多少"。
- 不必现在改 512G 默认值——物理硬件未到位；要做的是公式化与验证清单。

### 2.2 路线 2：数学成立，但"Swift 编排层拆分换并行"在单 GPU 上无收益机制

外审文稿的数学部分正确（GEMM 行分块严格等价；Q 行分块等价；K/V 分块
需 online softmax 统计量合并——FlashAttention 核心思想）。但对照本仓库
实测证据，应用层编排存在一个无法绕过的机制缺口：

1. **单 GPU 上大 GEMM/attention kernel 已占满全部核心。** 应用层拆成
   4 份仍排在同一块 GPU 上执行，并行度增量为零。FlashAttention 的 tile
   是 kernel 内寄存器/SRAM 级组织，不是"多开几个计算任务"。
2. **本仓库工作负载呈带宽受限形状**：decode 2K→237K 劣化 42→4 tok/s
   （09-20 运行日志分析，未入 docs，§6 顺带归档）；120K cold prefill
   512 档 674.5s（177 tok/s）vs 1024 档 1115.4s（107 tok/s），
   `V17_RUNTIME_MATRIX/README.md:115`。带宽是物理常数，拆分不减搬运
   字节数；Swift 层 K/V 拆分反而新增 partial O/max/sum 物化往返。
3. **唯一真实收益机制（降峰值内存避免 swap/spill）已被收割**：512 档
   快于 1024 档正是该机制，载体就是现行 chunked prefill 阶梯
   （`RuntimeTuning.swift:120-122`，<64k→2048 / 64–96k→1024 / >96k→512）。
4. **GDN 递归态时间维不可自由并行**（引擎层属性，与治理无关）。

结论：外审"拆→并行→合并"要活下来，必须迁移执行位置——kernel 层
（Track A）或跨设备（Track C）。而证据最厚、可立即动工的位置是
Execution State（Track B）。

---

## 三、关键修正：1.x 治理约束 ≠ 2.0 物理/数学约束

这是本次对证最重要的方法论产出，直接改变 2.0 研发方式。

### 3.1 随 1.7 封版解除的约束（对 2.0 预研无效力）

| 1.x 纪律 | 管辖范围 | 2.0 预研语境 |
|---|---|---|
| 死代码纪律（OCR 教训） | 出厂路径 | 实验室空间放空实现/探针代码正当 |
| "勿再加机制" | 观察窗口 | 预研期即加机制期 |
| "正解只能在上游" | vendor pin=发版基线 | 可 fork 引擎实验分支自行动工 |

第三条影响最大。F0 报告原文：**"卡点不在 MLX eval 层（惰性图本可承载
COW 式物化），而在 MLXLMCommon 公开 API 无 sequence identity"**
（`docs/experiments/EXECUTION_FORK_F0_PROBE_RESULTS_20260919.md` §1）。
1.x 规则下这是死路（只能等上游）；2.0 规则下这是 SimiGo fork 引擎即可
动工的清单。

### 3.2 不随版本改变的物理事实（2.0 继承的设计输入）

- 单 GPU 算子内并行已饱和；应用层拆分不新增并行度。
- 带宽上限是硬件常数；收益的上界 = 减少搬运字节，不是增加调度。
- softmax 合并必须走 online 统计量（数学正确，工程正身在 kernel 层）。
- GDN 混合架构：递归态不可 rewind/trim（F0 §2），但 fork 为固定尺寸
  拷贝（见 §5.1 架构利好）。
- §2.2 全部实测数据。

---

## 四、外审原方案（七实验平铺）取舍记录

保留：Execution State 定位、先实验后架构、硬验收分级、1.7 不动、
路线 1 保持 tuning 属性。

修正/否决（保留决策记录，防止回潮）：

| 原案 | 处置 | 理由 |
|---|---|---|
| 实验 01 GEMM 等价 | 不单独立项 | 分块 GEMM 即同一计算，等价必然成立，证据价值≈0 |
| 实验 02/03（GEMM/Q 分块性能） | 并入 06 的流量对账 | Swift 编排层拆分，单 GPU 无机制（§2.2.1） |
| 实验 04 K/V 分块+merge | 正身移入 Track A | 数学正确；工程位置在 kernel 层，非 Swift 编排层 |
| 实验 06 瓶颈剖析 | **提前为第一实验** | 唯一有开关价值的实验，决定 Track A 生死 |
| 实验 07 调度收益 | 移入 Track C | 单 GPU 单命令队列无可赢机制；多设备才有对手 |
| Runtime2 全目录先搭 | 降级为接口占位 | 单机世界无对手=为被排除的世界建接口 |

### 4.1 开源对重扫描（v1.1 增补）：不重做的清单

对公开开源实现扫描后的去重结论——以下方向有成熟成果，SimiGo 2.0
**一律不重做**，只消费或借鉴：

| 方向 | 成熟实现 | 处置 |
|---|---|---|
| FlashAttention / IO-aware attention | FlashAttention-2/3 | 不重做算法；Track A 只判断"本 workload 离地板多远" |
| KV Cache 本体 | mlx-swift-lm 七类 Cache（§8 本地核实） | 基础设施，不碰 |
| Chunked Prefill | mlx-lm / mlx-swift-lm `prefill_step_size` | 已是 1.x 基础设施 |
| Prefix Cache | vLLM APC、SGLang RadixAttention | 不重做 |
| Paged KV | vLLM PagedAttention；mlx-lm #1849 提案中 | **上游可能落地，不自行造存储层**（§5.1） |
| Hierarchical KV | SGLang HiCache（L1/L2/L3） | 暂不重复 |
| 分布式通信 | mlx.distributed（MPI/Ring/JACCL 等） | 作底座，不重做 |

**空白区（2.0 的研究空间，逐项无成熟实现）**：

- Execution State Fork / COW（针对 MLX + Swift + Qwen3.5 混合架构）；
- COW attention KV + COW 递归态（GDN）的**统一** fork 语义；
- 可恢复 execution identity 与 fork → restore → branch 执行语义；
- Apple Silicon 长上下文 Execution Planner（单用户策略层）。

判定依据：完整 execution state 的统一抽象在现有系统中均缺位——
mlx-lm #980 实证 hybrid 模型 prefix cache 整体失效（递归态不可按
token 切），#1849 作者仍在提案 storage 层。F0 探针与两个 Issue 三方
收敛：**缺的不是 KV Cache，是 Execution State 抽象**。

---

## 五、2.0 预研三轨 + Track D

```text
                        SimiGo 2.0 预研
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
      Track B              Track A              Track C
  Execution State        Kernel/BW           Multi-device
  立即开工（证据最厚）    条件启动（06 开关）    后置（硬件未到位）
          │
      Track D：Adaptive Memory（独立推进，所有轨道共用）
```

### 5.1 Track B（第一优先）：Execution State Fork

**研究问题**：一个已存在的执行状态，能否低成本派生独立、可验证、可继续
执行的 child state（fork），并以 Page 为单位共享与物化（COW）？

**依据（本仓库已核实的证据链）**：
- F0 探针判定：当前公开面不能 fork；缺口清单 = sequence identity +
  COW prefix sharing + lazily-materialized shared prefix（F0 §1–§3，
  `docs/experiments/EXECUTION_FORK_F0_PROBE_RESULTS_20260919.md`）；
- 磁盘 fork 基线：1.53GB 往返 / 全程 1.94s @63.6K 深度（F0 §1 实测）；
- 现行 restore 收益基线：120K restore 中位 18.2s [14.0–21.4] vs cold
  624.3s [616.0–630.8]，9/9 命中（`V17_RUNTIME_MATRIX/README.md:200,204`）。

**架构利好（本报告新增判断，立项书重点）**：qwen3_5_moe 混合布局恰好
COW 友好——长上下文内存几乎全部集中于 attention 层 KV（**append-only，
天然满足不可变前缀分页**）；GDN 层为 O(1) 尺寸递归态矩阵（与序列长度
无关，fork = 固定尺寸 memcpy，长上下文下相对 KV 是零头）。F0 的
"GDN 不可 trim/rewind"在 fork/COW 语境不构成障碍。Page 模型不需要绕过
这个架构——这个架构恰好长成了 Page 友好的形状。

**形态**：fork mlx-swift-lm 实验分支 + branch requirement（生产 pin 不碰）；
换 vendor 检出即 fresh derivedDataPath。

**边界收窄（v1.1）**：mlx-lm #1849（2026-09-05 开，open）已提案
paged KV storage（page allocation / refcount / copy-on-write /
capacity admission / cleanup），并明确询问维护者要 native 实现还是
"为外部维护的实现留 minimal integration hooks"。两点推论：

1. **不研究"Paged KV + COW"本身**——存储层可能由上游落地。Track B
   研究的是其上一层的空白：**COW KV + COW 递归态（GDN）+ 可恢复
   execution identity + fork/restore/branch 语义 + 单用户策略层**。
2. **fork 结构上让存储层可替换**：若 #1849 以 hooks 形式落地，SimiGo
   恰好就是它要的那个"外部 execution-state 实现"。F0 上游草案
   （`UPSTREAM_ISSUE_DRAFT_kv_prefix_sharing_cow.md`：sequence
   identity + COW shared prefix）与 #1849 是同一缺口的两半——预研期
   关注合流，不各造一半。

**外部证据（v1.1 增补，均验真，详见 §8）**：

- mlx-lm **#980**（2026-03-11 开，**已关闭**）：prefix cache 对全部
  hybrid 架构（sliding window / SSM/Mamba）失效，纯 attention 模型
  独享缓存收益；M3 Ultra 实测 MiniMax M2.5 加速 10.5×，而
  **GPT-OSS-120B 与 Qwen3.5 无加速或倒退**；根因=RotatingKVCache 不可
  有效 trim + 递归态不可按 token 边界切分。与本仓库生产观测
  （fork-no-rewind=0、cacheEff=0.00 形状）交叉印证。修复杂否未核实，
  但本地 pin 栈 grep 零命中（见下），缺口对现行栈成立。
- 本地 vendor 检出（8f37dbc）grep（2026-09-20）：`sequence_id` /
  `seq_id` / `copyOnWrite` / sequence identity 全库**零命中**——F0
  结论在现行栈上仍然成立。

**止损条件（v1.1）**：Track B 不因叙事漂亮而无限投入。原型阶段回答
三个问题——①Fork Cost 是否近 O(1)（而非 O(256K) 全量拷贝）；
②Shared Page Ratio 能否显著高于基线；③正确性门（逐 token 一致）
是否通过。**任一出现结构性失败，Track B 迅速调整方向或关闭。**

**验收指标（三个硬数字 + 一条正确性门）**：

1. **Fork Cost**：fork 延迟 / 新增物理内存 / 是否发生实际 tensor copy。
   基线=磁盘 fork 1.53GB/1.94s。目标：fork 操作亚秒级（元数据 O(1)）；
   分叉后首次写入的物化天然 O(后缀)，计入 physical_growth 而非 fork
   延迟——判据以"物理增长 ∝ 分叉后缀"为准。
2. **Restore Depth**：restore(D→C/B/A) 成本随深度 A→B→C→D 的曲线形状。
   基线=18.2s@120K。平/亚线性=通过；随深度线性陡增=Page 粒度需重设计。
3. **Shared Page Ratio**：N 次 fork 后 shared_ratio 与 physical_growth。
   通过=增长与分叉后缀成正比。
4. **正确性门（一票否决）**：fork 态续跑 greedy decode 必须与同前缀
   从零 prefill 的续跑**逐 token 一致**；不一致则 fork 语义有错，
   全部速度指标作废。

### 5.2 Track A（条件启动）：Kernel / Bandwidth

**研究问题**：现有 MLX→Metal kernel 对本模型 GQA + causal mask +
long-context shape，离硬件可达带宽/计算效率地板还有多远？

**开关实验（实验 06）判定标准——预先钉死为算术，不靠观感**：
- Roofline 对账：理论字节搬运量（长上下文主导项=attention K/V 重读，
  causal 下 ≈ layers × heads × n²/2 × head_dim × bytes）÷ 芯片带宽上限
  = 理论地板时间；与实测时间之比为判据。
- 实测/地板 **≤1.5×** → 已贴顶，Track A 关闭；
  **≥3×** → 存在 kernel opportunity，Track A 开启；
  中间地带 → 逐算子归因后定（判例规则列入 §7 开放问题）。
- 工具链：Instruments GPU counters（逐 kernel 时间+显存流量）+
  `powermetrics`（sudo，GPU 频率/功耗）+ MLX
  `get_peak_memory/get_active_memory` 分相采样。
- 附带复核：512/1024/2048 三档流量对账——对"512 档更快=内存压力"假说
  证实或证伪（`V17_RUNTIME_MATRIX/README.md:115` 只给了结果，机制未归档）。

**若开启**：目标不是"自己写一个 Attention"，而是 MLX fork + Metal
prototype（`baseline.metal` / `candidate.metal` 同契约对比，不集成
SimiGo）。借鉴 FlashAttention 原则（减少统一内存往返 / tile / online
reduction / work partition / fusion），回答"这个具体 workload 是否存在
自己的 FlashAttention-like kernel opportunity"。

### 5.3 Track C（后置）：Multi-device

- 唯一"拆分 = 获得额外计算资源"的世界；`mlx.distributed` 原语已存在，
  SimiGo 的位置是编排不是重做组网。
- Runtime2 骨架显式改标为 **Multi-device Execution Layer 占位**：
  Planner / Scheduler / Reduction / DistributedBackend 全部 `[future]`。
- 硬件与场景未到位前不单独立项、不实现。

### 5.4 Track D（独立推进）：Adaptive Memory

- 公式链：Physical Memory → System Available → Model/KV Requirement →
  Runtime Working Set → **Dynamic Budget**。
- 安全边界（防自杀式自适应）：硬性保留量（物理内存 15–25% 或固定值取
  大者）+ memory pressure 事件**主动**收缩（不等 swap 发生）。
- 落地验证：256K prefill 实测"预算放宽不引入 swap 劣化"（1024 档教训
  的制度化）。
- 不依赖 A/B/C，可立即做；与 §2.1 承接。

---

## 六、执行计划（四步；①②无依赖，可并行）

| 步 | 内容 | 产出 | 量级 |
|---|---|---|---|
| 1 | 实验 06：256K Prefill Roofline 对账 | 地板/实测比值 → Track A 开关判定；顺带归档 09-20 decode 劣化数据与三档机制复核 | 天级 |
| 2 | Track B：fork mlx-swift-lm 实验分支，F0 三缺口动工（存储层可替换设计，跟踪 #1849 合流） | Fork Cost / Restore Depth / Shared Page Ratio 三数 + 正确性验证 | 周级 |
| 3 | Track A 按步 1 结论开关 | 若开：Metal prototype 对比数据；若关：关闭记录（同样入档） | 条件 |
| 4 | Runtime2 仅留接口骨架 | 现期概念=ExecutionState/Page/Fork/Restore/MemoryBudget；`[future]`=Planner/Scheduler/Reduction/DistributedBackend | 随步 2 收敛 |

**边界规则（钉死）**：实验室代码永不经过 1.7 发布路径。Track B fork
分支、Track A Metal 原型、Track D 预算逻辑，迁移回生产的唯一通道是各自
Level 门通过后另立版本，不从后门进。

---

## 七、开放问题（不阻塞开工）

1. 实验 06 中间地带（1.5–3×）的判例规则——待首份数据后定。
2. Track B Page 粒度（层内分页 vs 层间快照 vs 混合）——由 fork 原型
   实测成本决定，不预设。
3. Track D 保留量参数——需一次 256K prefill 实测校准。
4. 外审文稿引用的 120K 数据与 `V17_RUNTIME_MATRIX` 记录存在单次/中位
   差异（674.5s 单次 vs 624.3s 中位）——以 harness 归档为准，外审引用
   不再单独采信。

---

## 八、数据出处注记

| 数据 | 值 | 出处 | 核实状态 |
|---|---|---|---|
| 内存上限 | 22 GiB / 4 GiB | `RuntimeTuning.swift:8-12` | ✅ 2026-09-20 核实 |
| prefill 阶梯 | <64k→2048 / 64–96k→1024 / >96k→512 | `RuntimeTuning.swift:120-122` | ✅ 同上 |
| F0 判定 | 公开面无 sequence identity；磁盘 fork 1.53GB/1.94s @63.6K | `docs/experiments/EXECUTION_FORK_F0_PROBE_RESULTS_20260919.md` §1 | ✅ 同上 |
| restore 基线 | 120K：18.2s [14.0–21.4] vs cold 624.3s [616.0–630.8]，9/9 命中 | `docs/experiments/V17_RUNTIME_MATRIX/README.md:200,204` | ✅ 同上 |
| chunk 档位实测 | 512 档 674.5s（177 tok/s）vs 1024 档 1115.4s（107 tok/s） | 同上 `:115` | ✅ 同上 |
| decode 劣化 | 42→4 tok/s（2K→237K） | 09-20 运行日志分析（**未入 docs**） | ⚠️ 步 1 顺带归档 |
| 70–80K 单会话可用性地平线、重连×重渲循环 | — | 09-18 运行日志复盘 | ⚠️ 记忆/日志，未独立归档 |
| mlx-lm #1849 | Paged KV storage + external cache integration；2026-09-05 开，open；提案含 page allocation/refcount/COW/admission/cleanup，询问 native vs external hooks | github.com/ml-explore/mlx-lm/issues/1849 | ✅ 2026-09-20 WebFetch 验真 |
| mlx-lm #980 | hybrid 架构 prefix cache 整体失效（sliding window/SSM/Mamba）；2026-03-11 开，已关闭；M3 Ultra 实测 Qwen3.5/GPT-OSS 无缓存收益 | github.com/ml-explore/mlx-lm/issues/980 | ✅ 同上 |
| vendor 无 identity/COW | `sequence_id`/`seq_id`/`copyOnWrite` 全库零命中 | `~/Documents/mlx-swift-lm`（8f37dbc）grep Libraries | ✅ 2026-09-20 核实 |
| Cache 类型清单 | KVCacheSimple / Rotating / Quantized / Chunked / Arrays / CacheList / TurboQuant / KVCacheRound / KVCacheStorage | `MLXLMCommon/KVCache.swift` 等 | ✅ 同上 |

---

*本报告为 2.0 方向登记文档与战略唯一真源，驻本仓
`docs/architecture/`；主仓（slamfinger/SimiGo）保持纯产品线（1.x）。
实验记录沿用探针 → 结果 → 决策三段式，全部归档本仓（各 track 目录 +
`docs/`）。主仓 `docs/experiments/` 保留 1.x 时代史料（F0 探针、
V17_RUNTIME_MATRIX 等），本报告跨仓引用其作为基线证据。*
