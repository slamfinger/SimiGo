# P2 配置记录（§8 五项真机配置裁定）

**Status**: 活文档 — ①②③④⑤已定案；真机执行授权未授予。本文档是配置决策的唯一权威记录，**不授权任何执行**。
**上游**: `P2_EXPERIMENT_PLAN_20261105.md`（G1 PASS · CLOSED）
**授权边界（持续有效）**: 零实现改动、零模型加载、零真机执行、零对外发送——每一项均须用户单独授权后解除。
**外迁注记（2026-11-07，用户裁定：本文件属治理线留仓）**: 本记录引用的研究线产出文档——`P2_DERIVATION_TECHNICAL_REPORT_20261106.md`、`P2_EVIDENCE_MAINLINE_MAPPING_20261107.md`、`P2_TECH_EXCHANGE_BRIEF_20261106.md`——已按 2026-11-07 裁定正本外迁至 `slamfinger/ES-IS-research`（PRIVATE），simigo 仓剥离并禁入。正文各条目为账本史实，原文保留不动；上述文件名现仅指研究仓正本。

---

## §1 ① 模型与规模 — 已定案（2026-11-05）

**主模型**：本地已缓存 `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`（用户裁定；规模标准②不过 = 用户知悉接受的权衡，16 GB）。

静态核查矩阵（全部通过，未加载模型）：

| 项 | 结果 | 证据 |
|---|---|---|
| 许可 | Apache-2.0、ungated | HF API |
| 注意力架构 | **标准 GQA 全注意力**：`model_type: "qwen3_moe"`、48 层、32Q/4KV、head_dim 128、`sliding_window: null`、无 hybrid/layer_types 标记；MoE 仅 FFN 侧（128 专家/8 激活），不影响 KV 结构 | 本地快照 config.json 实测 |
| Runtime 加载路径 | 注册表含 `"qwen3_moe": create(Qwen3MoEConfiguration.self, Qwen3MoEModel.init)`；text-only 走 `LLMModelFactory`，不触发 VLM fallback | `slamfinger/mlx-swift-lm@6f88129` 注册表；`NativeMLX.swift:352-366` |
| 权重在场 | 4 分片 safetensors 全部在本地（16 GB，blobs 实测），零下载可加载 | `~/.cache/huggingface/hub/models--mlx-community--Qwen3-Coder-30B-A3B-Instruct-4bit/`（快照 `6e302ea604ad9ab206367e2c501d1571023e7b6d`） |

**两项技术限定（用户确认，持续有效）**：
1. KV 容量公式（2×48×4×128×2B ≈ **96 KiB/token**，8K ≈ 768 MiB）**只是理论基准**——实际分配受对齐/分页/缓存策略/运行时实现影响，不能替代 O2.3 的实际资源归因；
2. **MoE 路由确定性不作实验前提**——固定模型与 tokenizer 身份即可；生成结果逐字一致性与 ES/IS 恢复正确性分开（E4.x 均为结构性主张）。

**备选**：`mlx-community/Qwen2.5-1.5B-Instruct-4bit`（存在、apache-2.0、ungated；config 未核，转正前补核）。
**历史背景**：此前真机模型（Qwen3.5 族 / Qwen3-Coder-Next / Gemma4-26B 等，GDN 混合或巨型 MoE）保留为背景，不构成 P2 约束。

## §2 ② 上下文终止方式 — 已定案（2026-11-05）：Process Exit

**单一选定**：Run A 正常退出（非崩溃/强杀）→ Run B 全新进程 + 全新模型加载，不恢复旧 session/checkpoint。B（suspend）只作未来补充研究；C（同进程新 runtime 实例）不进本轮。

**操作定义**：

| 阶段 | 配置 |
|---|---|
| Run A | 加载模型、构造依赖、真实生成、结算并提交 SQLite 事务 |
| Run A 退出前 | 采集阶段 1 证据、KV 存活态读数、DB 只读快照及遥测 |
| 终止 | 正常退出整个 Run A 进程 |
| Run B | 全新进程、全新模型加载，不恢复旧 session 或 checkpoint |
| 阶段 3 | 显式使用 settlement_id 执行 IS Admission |
| 阶段 4 | 在新 ES 中续推，监控旧 checkpoint/KV 消费路径 |

**三项限定（写入配置记录，持续有效）**：
1. 进程退出只证明进程内旧状态消失，**不自动证明磁盘恢复路径安全**——Run B 须核查旧 checkpoint、branch-checkpoints、磁盘 session 存储；文件存在不是失败，阶段 3/4 **实际消费**才是失败；
2. O2.3 分两个读数——Run A 退出前旧 KV 实际分配/容量/可归因存活态 + Run B 新加载 KV 基线及是否有旧状态迁移；**Run B 基线不能替代 Run A 释放证据**，理论容量公式仍只是交叉核对基准；
3. 正常退出前必须确认 SQLite 事务已提交——退出前记录 settlement_id、提交结果与 DB 一致性读数，**不得从退出成功推导结算持久化成功**。

## §3 ③ 失效注入方式 — 已定案（2026-11-05，附四项执行约束）

**主注入 = 真实源文件版本变化**；**settlements 表只读是硬约束**（禁止手工 UPDATE validity / 伪造 invalidated_at / 绕过闭包定点失效）。

**场景预埋（验收点）**：源文件 F → 检索结算 R（绑定 F 的 content_address + rootID/relativePath）→ 答案结算 T（经真实模型生成）。**验收点：T 必须真实封存 R**——T 的依赖边指向 R 的 settlement ID 且 content address 与 R 的实际 payload digest 一致（非仅把 R 放进生成上下文），否则 R→T 传播未建立，不能验证完整闭包。

**注入矩阵**：

| 编号 | 操作 | 预期读数 |
|---|---|---|
| I1 主注入 | 真实修改 F（留前后 digest）→ Run B 变更检测流 | R/T 沿闭包翻转 invalid；传播有界；验证 R6 分离（Settled(T) 仍真、Recoverable(t₂) 假） |
| N1 负对照 | 修改在实际检测范围内但无结算绑定的文件 | 零失效（"A change with no dependents invalidates nothing."，ESISDatabase:4948-4949） |
| N2 负对照 | 修改兄弟结算绑定的另一文件 | 兄弟失效、T/R 保持 valid（须确认兄弟真被检测到） |
| N3 可选 | F 改回原内容 | 不复活（失效不自动可逆） |
| 幂等读数 | 同一公开检测流重复 reconcile | 已 invalid 不重复翻转、invalidated_at 不改写、无新失效范围 |

**四项执行约束**：
- **A**：N1 文件须在实际检测范围内但无绑定；N2 兄弟结算与 R/T 无共享失效依赖路径；
- **B**：M(ρ,t₂) 独立枚举不得循环引用失效结果——先只读 SQL 枚举绑定+dependency_edges 算理论闭包，再读实际事件逐项比对；五份档案分存（注入前依赖图快照 / 理论受影响集合 / 实际 invalidated 集合 / 实际未受影响集合 / typed refusal）；
- **C**：幂等读数须经同一公开检测流重复触发；检测流不支持重复触发则记独立入口语义读数，不混称主注入重复检测；
- **D**：应急后备 `invalidateSourceFile(rootID:relativePath:)` 必须先完成真实磁盘变更+前后 digest，标注 `emergency_fallback_injection` 单独分层；结果只证明失效入口与传播语义，**不得宣称 runtime 检测流已验证**；主注入失败+后备成功不得记主路径 PASS。

**语义确认（重申）**：I1 与 typed refusal 都不是 reexec——无实际 reexec 则 R3 记"本轮未验证"（E3.2b 条件读数）。

**留④/执行配置钉死**：公开变更检测入口（候选：work-root reconcile/索引流）、T→R 绑定构造命令（候选：demand + retrieval_settlement_id 流）、旧 digest 匹配调用点。

## §4 ④ KV 观测与消费路径 — 已定案（2026-11-05，附五项约束）

### §4.0 裁定原文摘录

> ④配置方案批准。
>
> 三层身份分离、Run A 读数阶梯、Run B 消费入口清单、O2.1 α/β 分支，以及探针 A 的元数据主方案，整体方向成立。
>
> 但有几个读数等级和推论边界必须修正。它们不是要求改变方案架构，而是防止实验结束后把结构估算误报成物理资源实测，或者把"没有观察到"误报成"已经证明不存在"。
>
> 模型身份相等不构成 KV 状态相等或迁移的证据。
>
> G2 的 `L_A × 96 KiB/token` 是结构归因估算，不是直接资源读数。不能称为"保底直接等级"。
>
> 没有 telemetry 记录，只有在该入口的遥测覆盖完整性已经得到验证时，才能作为触发条件缺席的证据。不能直接推导：没有日志 = 没有发生。
>
> `L_B × 96 KiB/token` 只能作为结构归因交叉检查。它不能独立证明旧 KV 没有迁移。
>
> β 条件分支批准，但不能自动记为 PASS。
>
> 探针 A 的主张边界是：模型身份变化会触发正确的失效/拒绝机制。它不声称验证真实模型切换后的完整运行行为。

### §4.1 三层身份分离 — 批准

| 身份层 | 记录项 | 裁定 |
|---|---|---|
| 模型身份 | repo id + 快照 revision + config/tokenizer SHA-256 | 通过；相等仅表示模型内容身份一致 |
| 运行实例身份 | PID + 进程启动时刻 + `[EXEC] exec=<uuid>` 集 | 通过；Run A/B 必须不同 |
| KV 状态身份 | 归属实例、执行 id、实际上下文长度 L、可获得的容量/资源读数 | 通过；必须归属具体进程与执行实例 |

**硬约束**：

- 模型身份相等**不构成** KV 状态相等或迁移的证据；
- KV 迁移判定由三项共同支持：token 计账、可归因的 KV 状态/容量读数、Run B 对旧 KV/checkpoint 的消费路径缺席；
- runtime 若提供稳定的 cache/session 对象标识，应记录；若不能提供，**不得自行构造看似唯一的 KV ID**，只能如实使用观察元组并标注其不是物理对象唯一性证明。

### §4.2 Run A 读数等级 — G2 修正为结构估算

| 等级 | 读数 | 正确证据定位 |
|---|---|---|
| G1 | runtime KV offset/token 数，以及可获得的容量/分配读数 | 直接 runtime 读数；只有实际暴露的容量/分配信息才能支持资源量主张 |
| G2 | 实际 KV token 长度 × 96 KiB/token | **结构归因估算；非分配器实测** |
| G3 | RSS、进程内存变化 | 间接辅助读数 |

96 KiB/token 是依据模型结构和假定 KV dtype 得到的名义计算值；实际分配还可能受 dtype、对齐、分页、缓存实现及其他开销影响。

**必要条件**：

- L_A 必须是**实际进入 KV 的上下文长度**；不得直接把 completion tokens 或一般 usage 数字当作 KV offset；只有生成 token 计数时，不能据此推算实际 KV 容量；
- Run A 采集时点固定为：T 结算已提交 → SQLite 一致性读数完成 → 旧 KV 仍存活 → 正常进程退出前；
- 若最终只有 G2/G3、没有可归因的直接 KV 资源读数，O2.3 必须降级表述；**不能以结构估算和 RSS 变化代替直接资源证据**；
- O2.1、O2.2 仍须独立完成，不因 O2.3 降级而放宽。

### §4.3 Run B 入口清单 — 批准，附 telemetry 证明边界

**O2.2a 磁盘工件清单（批准）**：

1. `~/.simigo/branch-checkpoints/`；
2. Run A 遗留 session cache 文件；
3. IS 数据库本身。

IS 数据库是合法恢复来源。磁盘工件存在不等于失败；只有阶段 3/4 实际消费了不应恢复的旧 KV/checkpoint，才构成失败。

**O2.2b 五类消费入口（批准）**：

1. `loadSessionCache`；
2. `forkSessionBranch`；
3. checkpoint 磁盘加载；
4. `PrefixMemoryPool`；
5. IS KV binding consumption。

**证明边界**：

- 没有 telemetry 记录，只有在该入口的遥测覆盖完整性已经得到验证时，才能作为"触发条件缺席"的证据；
- 不得直接推导"没有日志 = 没有发生"；
- 必须分别记录：Run B 配置是否满足入口触发条件、入口是否实际触发、若触发是否有可靠 telemetry/DB 记录、行为计账是否与入口触发状态一致；
- 发现清单外入口，必须扩充观测范围；不得沿用原清单并宣称覆盖所有路径。

### §4.4 O2.3 Run B — 容量估算不能单独判定无迁移

Run B 至少区分五个采集时点：

| 时点 | 应记录状态 |
|---|---|
| 新进程启动、模型加载前 | 进程实例身份、模型身份 |
| 模型加载后、Stage 3 前 | 新实例 KV 初始状态 |
| Stage 3 Admission 后 | 是否发生 KV/checkpoint 消费或绑定解析 |
| Stage 4 续推前 | 新 ES 的 KV 初始状态 |
| Stage 4 续推后 | 新 KV offset、token 计账、可获得的容量读数 |

`L_B × 96 KiB/token` 只能作结构归因交叉检查，不能独立证明旧 KV 没有迁移：旧 KV 与新 KV 可能具有相同模型结构、容量形状，甚至被内存分配器复用。Run B 的结论必须同时来自：

- 新进程身份与 Run A 不同；
- Stage 3/4 旧状态消费路径没有触发；
- 新 KV 的实际 token 计账与新执行过程一致；
- 直接资源读数（若可得）与新 KV 状态相符。

不得仅凭容量"看起来合理"认定没有迁移。

### §4.5 O2.1 α/β 与探针 A — 批准，保留条件分支

**O2.1 α（优先方案，批准）**：阶段 1 普通生成与结算，T 不记录 KV binding；若 IS 契约明确不存在旧 KV 复用授权，则 O2.1 可沿该路径验证。

**O2.1 β（条件分支，批准，但不能自动记为 PASS）**：若 runtime 无条件写入 KV binding：

- 必须读取并记录实际 binding；
- 确认 binding 指向什么对象、具有什么有效性；
- 证明 Run B 的 Stage 3/4 不会通过该 binding 接入 Run A 的旧 KV；
- 扩展 O2.2b 的消费路径观测范围；
- 如果 binding 本身赋予旧 KV 可恢复、可消费的有效权威，O2.1 不能通过；不能以"已扩充观测范围"替代"旧状态不可复用"这一验收条件。

**探针 A 第二身份（元数据主方案批准）**：

- begin 使用 M1；settle 声明 M2 的 repo ID 字符串；不加载 M2；
- 预期身份不匹配导致 typed refusal；
- 执行配置必须核实拒绝路径不解析、不加载 M2 权重，也不产生隐式模型初始化；
- 若实现确实要求 M2 已加载，当前主方案不能自行转为加载后备模型；`Qwen2.5-1.5B-Instruct-4bit` 的加载后备必须另行授权，不能与 P2 主实验授权捆绑；
- 主张边界：只验证"模型身份变化会触发正确的失效/拒绝机制"，不声称验证真实模型切换后的完整运行行为。

### §4.6 证据账本与执行配置待钉死项

统一字段：`run_instance / model_identity / kv_state（含等级 G1/G2/G3）/ settlement_ids / payload_digests / typed_refusals`。

执行配置阶段仍须核验：

- runtime KV 内省暴露面；
- T 结算是否存在 kv binding（α/β）；
- 探针 A 拒绝路径是否解析或加载 M2；
- restore 事件 telemetry 的显形形态与覆盖完整性；
- E4.1 候选字段（`Committed.recomputed` / `reusedExecution`）可读性。

### §4.7 ④ 最终状态

| 项目 | 状态 |
|---|---|
| 三层身份分离 | 已定案 |
| Run A G1/G2/G3 读数阶梯 | 已定案，G2 修正为结构估算 |
| Run A 存活态与 SQLite 同点采集 | 已定案 |
| Run B O2.2a 磁盘工件清单 | 已定案 |
| Run B O2.2b 五类消费入口 | 已定案，保留范围扩充规则 |
| telemetry 缺席证明边界 | 已定案 |
| O2.3 Run B 计账与容量交叉检查 | 已定案，容量估算不能单独证明无迁移 |
| O2.1 α/β | 已定案，β 条件通过 |
| 探针 A 元数据主方案 | 已定案 |
| 探针 A 加载第二模型后备 | **未授权** |
| G1 runtime 实际读数能力 | 待执行配置核验 |
| T 是否存在 KV binding | 待执行配置核验 |
| 公开 restore telemetry 的完整性 | 待执行配置核验 |

## §5 ⑤ 预算与阶段间停止条件 — 已定案（2026-11-05）

> **⑤ ACCEPTED · 配置定案**
>
> 五项全部接受。P2 的①–⑤配置决策至此完成。
>
> S1→S2、S3→S4 连续执行是实验设计的必要条件，不是为了节省操作时间。
>
> G2 可以降级报告"token 计账与结构估算一致，资源侧未直接实测"，不算 O2.3 完整 PASS；不能将 G2 包装成直接资源测量。
>
> C2 不能用于修复语义失败，也不能用来绕过已经封存的失败证据。执行中修改配置，当前链作废。

以下数值均为上限；未使用的额度不得转化为额外重跑。⑤ 定案不产生执行授权。

### §5.1 预算单位与链定义

**一条完整链（chain）** = S0 预检 + Run A（阶段 1–2）+ Gate A + Run B（阶段 3–4）+ Gate B。

- **C1**：主链，最多一条；
- **C2**：条件替换链，最多一条，仅在 C1 发生"非语义、非预期读数"的基础设施/操作故障且受影响阶段尚未封存证据时启用；C2 须用户单独批准；
- 任何语义失败（红线命中、预期读数反例、强制证据缺失）**不得启用 C2 重试**，直接停链并把失败作为有效结果入档。

### §5.2 硬预算

| 维度 | 单链上限 | 全实验上限 | 触发即停 |
|---|---:|---:|---|
| 模型加载次数 | 2（Run A 一次、Run B 一次） | 4 | 超出即停；不得为探针或对照额外加载 |
| 真实生成调用次数 | 8 | 16 | 超出即停 |
| 输入 token 总量 | 64K | 128K | 超出即停 |
| 输出 token 总量 | 4K | 8K | 超出即停 |
| 单次调用上下文 | 8,192 tokens | 8,192 tokens | 超限不得静默截断，停链 |
| 单次调用 completion | 512 tokens | 512 tokens | 超出即停 |
| 机器执行时间 | 3.5 小时 | 7 小时 | 超出即停 |
| 外部日历窗口 | 24 小时 | 24 小时 | 超时链条作废，需重新授权 |
| 新增磁盘写入 | 4 GiB | 8 GiB | 超出即停；开始前至少留 20 GiB 空闲 |
| 峰值进程内存 | 24 GiB（且不超过物理内存减 4 GiB） | 同左 | 超出即停；加载前可用内存不足 20 GiB 则不得开始 |
| 外部网络流量 | 0 | 0 | 仅允许 loopback；零下载、零外发 |
| 外部费用 | 0 | 0 | 任何付费调用即停 |

**时间分段（单链）**：

| 段 | 上限 | 说明 |
|---|---:|---|
| S0 预检 | 20 分钟 | 不加载模型 |
| S1 阶段 1 | 40 分钟 | 含 Run A 模型加载；单次加载上限 15 分钟 |
| S2 阶段 2 | 20 分钟 | 结算后、退出前读数；本段结束前完成正常进程退出 |
| Gate A 归档 | 10 分钟 | Run A 已正常退出 |
| S3 阶段 3 | 40 分钟 | 含 Run B 模型加载；单次加载上限 15 分钟 |
| S4 阶段 4 | 50 分钟 | 续推 + 冷启动对照 |
| Gate B 归档 | 10 分钟 | Run B 已退出 |

以上合计 190 分钟，单链硬上限 210 分钟，余 20 分钟只作不可预见开销，不得用于增加模型调用或阶段尝试。

单次模型调用超时 8 分钟；只读 SQL/HTTP 操作超时 2 分钟。超时按停止条件处理，不自动重试。

**预算计账**：机器时间以单调时钟计；token 以 runtime 计数为准，不可得时用 tokenizer 计数 + 实际 completion 计数并标注为保守估算；磁盘以新增写入量计；内存取峰值采样。任何计数不可得时按上限保守计账，不得在预算不明时继续增加调用。

上述数值是可执行上限，不是对真实耗时的预测。执行配置阶段只能收紧，不得自行放宽；任何放宽须用户重新裁定并记录。

### §5.3 尝试次数与重跑规则

| 阶段 | 每链有证据尝试 | 全实验上限 | 允许的重试 |
|---|---:|---:|---|
| S0 预检 | 2 | 4 | 仅环境检查，不加载模型 |
| S1 阶段 1 | 1 | 2 | 仅 C2，且须用户批准 |
| S2 阶段 2 | 1 | 2 | 仅 C2，且须用户批准 |
| S3 阶段 3 | 1 | 2 | 仅 C2，且须用户批准 |
| S4 阶段 4 | 1 | 2 | 仅 C2，且须用户批准 |

**定义与纪律**：

- "有证据尝试"从首次真实生成、状态变更或注入开始计；只读复查、健康检查、日志重读不计；
- 每个阶段每链只有一次有证据尝试；C1/C2 合计每阶段最多两次；
- 语义失败零重试；
- C2 不能用于修复语义失败，也不能用来绕过已经封存的失败证据；
- 基础设施故障重试必须同时满足：受影响阶段尚未封存证据、未产生相互矛盾的权威状态、故障原因可归因于环境/操作而非被试语义、用户已单独批准；
- 连续 5 次无有效结果的空转，立即停止重复同一命令；不得自动重试，须切换检查状态、日志、替代路径或向用户报告阻塞；
- 应急后备注入不是自动降级路径：主注入失败即停链；如用户另行授权后备，后备作为单独标注的子运行，不得记为主路径 PASS。

### §5.4 阶段门与阶段间停止

**内部连续门（不插入人工等待）**：

- **S1 → S2 必须连续**：S2 依赖 Run A 的旧 KV 仍存活且尚未退出；若 S1 失败，立即停链并让 Run A 正常退出/丢弃，不得等到稍后再补 S2；
- **S3 → S4 必须连续**：S4 依赖 S3 恢复得到的 `(r, ρ, β)` 与新 ES 状态；若 S3 失败，立即停链，不得稍后补 S4；
- 内部门只做证据封存与停止条件检查；通过则立即进入下一阶段。长时间人工等待会改变 KV 存活态与时间读数，不作为可接受的操作方式。

**外部硬门（默认停，等待用户）**：

- **Gate A（S2 完成后）**：确认 Run A 已正常退出、SQLite 事务已提交、S1/S2 证据已封存、无停止条件命中；然后停止并提交阶段报告，等待用户决定是否进入 Run B；
- **Gate B（S4 完成后）**：Run B 已退出，提交全链证据与结论等级；不得在未授权情况下继续复刻、外发或扩展实验。

### §5.5 通用停止条件（任一命中即停链）

1. 红线 1 或红线 2 命中；
2. 任一预期读数出现反例；
3. 强制证据缺失，且不属于 §5.6 允许降级；
4. Run A / Run B 运行实例身份无法区分（PID、启动时刻、EXEC UUID 全部相同）；
5. 观察到阶段 3/4 实际消费旧 KV 或旧 checkpoint；
6. 以 telemetry 缺席作为"未触发"证据，但该入口覆盖完整性未验证；
7. 需要越过授权边界才能继续（实现修改、下载、第二模型加载、外发等）；
8. 模型身份、runtime 构建、配置 digest、数据库 schema 或关键环境在执行中发生变化；
9. 预算达到 100% 硬上限；达到 80% 时只预警并禁止新增调用，不把预警本身当作语义失败；
10. 连续 5 次无有效结果空转；
11. 用户中断；
12. 出现未预期的权威状态写入，或 settlement 提交/DB 一致性无法确认。

**停止后的动作**：记录触发项、已执行命令、observed 读数、已消耗预算、未完成阶段；不自动重试；不把"已停止"表述为"实验失败"或"主张被否定"。

**阶段特定停止条件**：

| 阶段 | 任一命中即停 |
|---|---|
| S0 预检 | 模型文件/digest/分片缺失；runtime 构建或注册表不符；数据库非只读可用；关键 telemetry 不可用；内存/磁盘不足；任何步骤需要外部网络 |
| S1 阶段 1 | 探针 A 未得到 typed refusal；出现预期写入边界外的权威状态变化；重复请求产生第二结算；digest 不一致；T 未真实封存 R（依赖边缺失或 payload digest 不符）；探针 A 路径解析或加载 M2 |
| S2 阶段 2 | Run A 非正常退出（崩溃/强杀）或 settlement 未提交；reattach 探针成功或改变状态；O2.1 β 的 binding 赋予旧 KV 可复用权威；O2.2a 发现活引用；O2.2b 观测范围内发生旧 KV/checkpoint 消费，或存在未验证入口；O2.3 仅有 G3；Run A/B 身份无法区分；SQLite 一致性无法确认 |
| S3 阶段 3 | 恢复跳过任一检查项；失效未沿闭包传播或误伤无关结算；t₂ 仍可恢复同一结算；客户端篡改值被采纳；主注入失败（不得自动切后备）；R/T 依赖闭包未建立 |
| S4 阶段 4 | 无 E4.1 执行决策计账（仅有 token 计账/叙述）；与冷启动对照无计账差异；已结算工作产生第二结算；引用链断裂；观察到旧 KV/checkpoint 消费；E4.4 超出绑定链证据升格 |

### §5.6 允许降级的证据等级

| 判据 | 完整证据 | 允许降级 | 不得降级/必须停 |
|---|---|---|---|
| O2.3 资源释放 | G1 直接可归因读数（含容量/分配；仅 offset/token 时结论受限） | G2 结构估算（G3 若可得则作辅助），结论标注"资源侧未直接实测" | 只有 G3；或只有叙述/日志 |
| E4.4 派生绑定 | 五项绑定链完整，结论"具体值派生关系已验证" | 仅消费关系可核验，结论降为"消费关系已验证" | 无 E4.1 执行决策计账；或把消费关系冒充值派生 |
| E3.2b reexec 范围 | 实际发生 reexec，记录执行集合并比对闭包 | 未触发则标"本轮未验证" | 把 Refuse 当作 reexec 已验证 |
| O2.2b 消费路径 | 清单入口全部有触发条件/遥测/计账读数 | 发现清单外入口则扩充观测范围 | 以原清单宣称"所有路径不可达" |
| 探针 A | 元数据级 typed refusal，且确认未解析/加载 M2 | 主张仅限"身份变化触发失效/拒绝机制" | 自动加载第二模型；或声称验证真实模型切换 |
| telemetry 缺席 | 覆盖完整性已验证 | 覆盖未验证时只能记"未知" | 记作"未发生" |
| O2.1 β | binding 不赋予旧 KV 可复用权威 | 扩大观测范围并如实记录 binding | binding 赋予可恢复权威仍判通过 |

**结论等级定义**：

- **PASS**：全部强制判据达到完整证据；
- **PASS-LIMITED**：仅使用本表允许的降级，且结论明确写出受限主张；
- **UNVERIFIED**：条件读数未触发（如 E3.2b），不作为失败；
- **FAIL**：红线或预期读数反例；
- **BLOCKED**：预算、授权或环境停止，未形成语义结论。

**补充说明**：本定案允许 G2（结构估算）单独构成 O2.3 的降级读数，但结论只能写成"token 计账与结构估算一致，资源侧未直接实测"；G1 若只有 offset/token 而无容量/分配读数，资源量主张同样受限。G3 单独不足以支持 O2.3；若 O2.1/O2.2 已独立通过而 O2.3 仅有 G3，结论至多为"权威与路径不可达，资源侧未知"，不能写成"KV 已释放"。

### §5.7 授权边界（持续有效）

| 动作 | ⑤ 定案后 | 解锁条件 |
|---|---|---|
| 实现修改 | 禁止 | 用户单独授权 |
| 模型下载/替换 | 禁止 | 用户单独授权；本实验零下载 |
| 主模型加载 | 仅执行授权后允许 | ⑤ 定案 + 单独执行授权；每链 2 次、全实验 4 次 |
| 第二模型加载 | 禁止 | 探针 A 后备单独授权，不与主实验捆绑 |
| 真机实验执行 | 禁止 | ⑤ 定案 + 单独执行授权 |
| 外部网络/外发/PR | 禁止 | 届时单独确认，一次一个对象 |
| settlements 手工修改 | 禁止 | 无——只读 SQL 是硬约束 |
| 失效注入 | 仅真实文件变化主路径 | 应急后备须单独授权并单独分层 |
| 强制 reexec | 禁止 | 不为了触发 E3.2b 额外执行 |
| 执行中改配置 | 禁止 | 任何改动使当前链作废，需重新授权 |

### §5.8 ⑤ 裁定结果

| 裁定项 | 最终状态 |
|---|---|
| 预算数值 | 接受，单链及全实验上限生效 |
| 尝试与重跑规则 | 接受，C1 主链；C2 最多一条且需单独批准 |
| 阶段门设计 | 接受，连续阶段与 Gate A/B 生效 |
| 降级边界 | 接受，按 §5.6 证据等级表述 |
| 授权边界 | 接受，配置定案不产生执行授权 |

**⑤ 定案不等于执行授权。**真机执行授权请求已提交（`P2_EXECUTION_AUTHORIZATION_REQUEST_20261105.md`，仅 C1）；在用户明确授权前，不启动 C1，也不启用 C2。

### §5.9 C1 执行授权记录（2026-11-05）

> 授权 C1，但修改：接受 docs-only dirty，不要求先做 docs-only commit；公开 HTTP 路径保留为 E0 硬门槛。
>
> 裁定：C1 真机执行已获授权，但必须先通过 E0。E0 失败即停止；授权不构成对实验结果的预先认可，也不授权 C2。

**生效条件**：

| 项 | 裁定 |
|---|---|
| docs-only dirty | 接受；不新增文档提交；固定 HEAD `421aaa02d1adfac8056a157fd036f8cc877e7dcb`、dirty 标记、全部文档变更清单与内容 digest；发现任何非文档改动即停 |
| 公开 HTTP | E0 硬门槛；headless restricted path 不得替代；不可用则停在 E0 请求范围变更 |
| 授权链 | 仅 C1；E0 通过后执行阶段 1–4；C2 不授权 |
| 连续性与门禁 | S1–S2、S3–S4 不得拆开；Gate A 后必须暂停并等待用户决定 |
| 预算/隔离 | ⑤ 全部上限生效；`SIMIGO_HOME=work/p2-c1`；不得写生产 `~/.simigo/simigo.sqlite3` |
| 边界 | 不允许超预算重试、语义失败补跑、绕过已封存证据、对外发送、擅自改实现/配置/结算表 |

### §5.10 E0 只读预检结果（2026-11-05）

**结论：E0 PASS。** 证据根：`work/p2-c1/evidence/s0/`（汇总 `e0_report.json`）。E0 未加载模型、未执行生成、未写生产库、零外发；阶段 1 尚未启动。

| 项 | 结果 |
|---|---|
| repo 身份 | HEAD `421aaa02d1adfac8056a157fd036f8cc877e7dcb`（main）；docs-only dirty，8 个文档变更；逐文件 sha256 与聚合 digest 记于 `evidence/s0/repo_identity.json`（在该文档定稿后重算，避免自指）；非 docs 差异与未跟踪文件均为空 |
| 构建 | `xcodebuild -scheme SimiGo -configuration Debug`，derivedData 在 `work/p2-c1/build/DD`（仓外）；BUILD SUCCEEDED；app 二进制 sha256 `d2fc953c6ed14c12…` |
| 公开 HTTP（硬门槛） | **PASS**：产品常规启动（无 `SIMIGO_G1G3_*`/`SIMIGO_LOCALB_MGMT`/`SIMIGO_ENV_BOOTSTRAP` 门），`127.0.0.1:8317` 明文回环；`GET /health` 200、`GET /v1/models` 200；`POST /v1/chat/completions` 被直接分派并返回宿主无模型拒绝（非 401/403/503）→ 推理路由不受 LOCALB 证明门拦截；LAN IP 直连失败（仅回环） |
| 隔离 | `/v1/simigo/env` 报告 `managed_root` = `work/p2-c1/simigo-home`；生产库 sha256/size/mtime 前后一致；`~/.simigo` 窗口内 0 文件修改 |
| 模型快照 | 快照 `6e302ea6…`，17 文件 sha256 已记录，4 分片共 16.0 GiB，零下载 |
| telemetry | **PASS-LIMITED**：trace 落 `$SIMIGO_HOME/logs`，可读 `[IS]/[BUDGET]/[ADMIT]/[PROTOCOL]/[LC]/[MEM]/[MLX]/[EXEC]`；覆盖“存在”不等于“完备”，故 telemetry 缺席仍不得充当“未发生” |
| O2.3 读数能力 | **PASS-LIMITED**：无 KV 归属的容量/分配读数（G1 不可得）；可得以 token 计账（G2）与 `[MEM]`/footprint（G3）。O2.3 结论上限为“token 计账与结构估算一致，资源侧未直接实测” |
| O2.1 α/β | **α 成立**：结算期的 KV 表示只由磁盘前缀池 `export()` 产生，其首行 `guard RuntimeTuning.prefixPoolEnabled`，该值仅在 `SIMIGO_PREFIX_POOL=1` 时为真（默认未设）。执行配置须保持不设 `SIMIGO_PREFIX_POOL=1`、不设 `SIMIGO_BRANCH_CHECKPOINTS=1` |
| 探针 A | 拒绝路径为 `simigo_es_settle` 的模型身份比对（只读 SQLite 行），不解析、不加载 M2 |
| reconcile / T→R | 入口已记录：`POST /v1/simigo/is/reconcile`、MCP `simigo_is_reconcile`；T→R 由 `simigo_es_begin` + `simigo_es_settle`（`demand_id` 与 `retrieval_settlement_id` 成对、依赖须为已封存对象）构造 |

**E0 未覆盖（明确记录）**：模型态端到端未在 E0 执行——若在 E0 加载模型，将占用单链 2 次加载预算之一。阶段 1 首轮生成即是对公开 HTTP → 模型 handler 接线的运行时确认；该确认失败按阶段 1 停止条件处理。

**执行期须保持的环境约束**：`SIMIGO_HOME=work/p2-c1/simigo-home`、`SIMIGO_CACHE_ROOT=work/p2-c1/cache`、`SIMIGO_STATE_GRAPH_STORE=work/p2-c1/state-graph/state-graph.json`；不设 `SIMIGO_PREFIX_POOL=1`、不设 `SIMIGO_BRANCH_CHECKPOINTS=1`；端口 8317（回环）。

## §6 配置状态总表

| 项 | 状态 |
|---|---|
| ① 模型与规模 | 已定案：Qwen3-Coder-30B-A3B-Instruct-4bit（本地缓存） |
| ② 上下文终止方式 | 已定案：Process Exit（三项限定） |
| ③ 失效注入方式 | 已定案：真实文件变化主注入（四项约束 + 场景验收点） |
| ④ KV 观测与消费路径 | 已定案（五项约束；G2 为结构估算；β 条件通过） |
| ⑤ 预算与停止条件 | **已定案（2026-11-05）** |
| 真机执行授权 | C1 已授权（2026-11-05），须先过 E0；C2 未授权 |
| E0 只读预检 | **PASS**（2026-11-05，见 §5.10）；含公开 HTTP 硬门槛 |
| 阶段 1–4 | 未启动——等待用户确认进入 S1 |

执行授权请求：`P2_EXECUTION_AUTHORIZATION_REQUEST_20261105.md`（仅 C1；C2 未请求）。

---

## §5.11 C1 失效与 R0/R1/R2 裁定（2026-11-06）

**C1 终态：BLOCKED**（2026-11-05）。S1 在首次生成前因产品 240s 空闲挂起失效（0 生成、0 写库、0 语义读数；根因 `Service.swift:1156` 30s 健康循环 + `NativeMLX.swift:765-781` 空闲阈值 + `lastActivity` 仅 `generate()` 入口刷新）；机器 19:17 重启，Run A 进程随重启消失。预算消耗：模型加载 1、生成 0、S1 段 63 分钟（超 40 分钟上限）。

**C1 身份绑定失效**（2026-11-06 00:29 确认）：执行仓=本主仓；自 09:24 封存后演进至 `e1c8727`（8caaabbb..HEAD 31 提交/6 merge），工作树出现并发线源码改动 → 按用户 11-05 规则「新 HEAD 推进、非文档改动或二进制变化必须停下裁定」停。交接日志：`Codex/2026-11-05/agent-1-p2-config-record-20261105/outputs/HANDOVER_LOG_20261106.md`。

**用户裁定（2026-11-06，接手会话结构化裁定；编号对应交接日志 §5）**：

| 项 | 裁定 | 内容 |
|---|---|---|
| R0 基线 | **R0=1** | 不吸收并发状态外发线；以 `8caaabbb` 冻结只读树为源码基准（git archive 落盘），**沿用 E0 二进制 `d2fc953c…`（免重建）**→ E0 结论全额沿用；身份四元组改记为「冻结树@8caaabbb + 二进制 d2fc953c + 无活 HEAD + 冻结树 tree digest」 |
| R1 链会计 | **R1=1（甲）** | C1 作废入档（BLOCKED，证据原样封存），开 **C2**：全新实验根 `work/p2-c2`，work/p2-c1 原样不动；预算按 ⑤（加载 2/生成 8/3.5h/4GiB；全实验加载累计 1+2=3≤4、S1 尝试 0+1=1≤2）；**本裁定构成 §5.3 要求的 C2 单独批准** |
| R2 结算路径 | **R2=1（B）** | S1 走 chat 单请求自动结算：resolve 自建 demand+检索结算 R，T 的 advancement 指向 R；R 定义为 SQL 读回的 advancement 目标；producer 由引擎写入；dependencies[] 为空；先行 `/v1/simigo/search` 请求省去（search 与 chat 的 demand 结构性不命中，已从冻结树直读核验 `SimiGoInformationLoop.resolve:132-300`） |

**C2 前置新检查**（交接日志 §5/§11）：实验根 IS 须先有 ≥1 个已结算信息源文件，否则 R.hits 为空——依赖边结构成立但「T 基于检索结果」语义不足，不当 E1.1 正例。→ S0 预检含注册流实测（`PUT /v1/simigo/roots` 注册即 `settleWorkRootContents` 结算文件行；`POST /v1/simigo/is/reconcile` 变更检测），预埋在 Run A 启动前完成（无模型）。

## §5.12 C2 启动准备记录（2026-11-06）

- 冻结树：`work/p2-c2/source-tree/`（`git archive 8caaabbb`，553 文件，tree sha `870909bae2b9dfbdecfde2e15572996855b0b551`，逐文件 blob sha 见 `evidence/s0/frozen_tree_ls.txt`）；与 421aaa02 的非 Markdown 差集 = 0（`core.quotepath=false` 复核；`部署指南.md` 曾因引号包路径被误报，已定性为误报）。
- 二进制：`work/p2-c1/build/DD/.../SimiGo`，sha256 `d2fc953c…`（封存时在场复核一致）；主仓 8 份 P2 文档仍与 09:24 封存 digest 逐字节一致。
- 身份记录：`work/p2-c2/evidence/s0/c2_execution_identity.json`；生产库新基线 `e3eb2396…`（11-05 23:54 非实验写入后）。
- 磁盘账本：C2 自 10,452 KB 起算 4 GiB；work/p2-c1 = 1,665,224 KB 原样封存。
- 环境约束（沿用 §5.10）：不设 `SIMIGO_PREFIX_POOL=1`、`SIMIGO_BRANCH_CHECKPOINTS=1`、`SIMIGO_TRANSPORT`；端口 8317 回环；Run A 启动形态 = serve-service + `Service.start(path:)`（与 11-05 S1 相同，公开 HTTP 面）。
- 首次模型加载前须用户单独确认（与 11-05 08:04 单阶段放行同节奏）。

### §5.13 S0 网络硬门故障与 α 修正版处置（2026-11-06）

**故障**：S0 尝试 #1（01:13）的辅助实例以普通启动形态（无 mgmt 门）拉起，产品 `applicationDidFinishLaunching` 的 bootstrap Task **无条件**执行（调用点无守卫）`bootstrapGenerationEnvironment`（`EnvManager.swift:624-668` 硬编码 `selectedEngineID="llama.cpp"`）→ 从 GitHub 完整克隆 `llama.cpp@0878f7c`（231,740 KB）+ HF dist.tar.gz 下载（`s0_app.log:108`）+ Metal 构建至 47% 被 fail-fast 终止。全部产物隔离于 `work/p2-c2`；生产库 sha 未变；四张权威表 0 行；零外发、零模型、零生成。**本链此后不得宣称零网络**（记「非零出网·归因 S0 操作故障·无场景数据外发」）；≈283 MiB 计入 C2 4 GiB，删除不退还。fault 记录：`work/p2-c2/evidence/s0/s0_network_fault_record.json`。

**机制更正（源码直读）**：阻断点 = `SIMIGO_LOCALB_MGMT=serve-service` 命中 mgmt 早退分支，**不是** `-BackendSelection mlx`（后者无效）；serve-service 强制要求 `SIMIGO_LOCALB_SERVE_MODEL`（`SimiGoLocalBManagementEntry.swift:120-122`）→ **无模型 mgmt 实例在结构上不存在** → S0 独立辅助实例取消，**场景预埋并入 Run A 窗口**（health → GET roots 只读验证 → PUT roots → reconcile → [READY] → chat，≤5s）。E0 零克隆与「普通启动必 bootstrap」并存，判定为 E0 探针实例存活短于 bootstrap 到达克隆点（开放条目，不影响 E0 结论）。

**用户裁定：α 修正版，六硬条件（2026-11-06）**：①修正形态 = mgmt 早退分支（Run A 沿用 11-05 S1 形态逐字一致）；②启动前 absence 断言（`sources/llama.cpp`、`build/llama.cpp`、`manifests/*`、`simigo.sqlite3` 均不存在）；③启动后 fail-closed 监听（出现 bootstrap/clone 行即 kill 判 FAIL）；④重置覆盖四类产物 + reset 后 absence 验证；⑤网络账本按日志全量枚举；⑥≈283 MiB 计入预算不退还。S0 第 2/2 次尝试 = 重置 + absence 验证（无 app 实例）；再失败即 S0 耗尽、C2 停链。

### §5.14 Run A 放行前审计与暂缓（2026-11-06）

**用户裁定：暂缓（不确认启动）**。对侧审计在放行前发现 1 处断言缺陷（已修）与 2 条阻塞；接手线独立复核并处置如下：

- **R 断言缺陷（已修，复核成立）**：`settlements.validity` 是 v3 迁移新增的 per-row 列（`ESISDatabase.swift:267`，注释明示与 native gate 的 `validation_status` 语义不同）；检索结算的 `validation_status` 为 `IS_RETRIEVAL`（`:4001-4028`）。原断言 `validation_status='valid'` 会在生成完成后的 Stage 2 误判 → 白烧 S1 2/2。现断言 `validity='valid'` **且** `validation_status='IS_RETRIEVAL'`（更严）。原版备份 `s1_runA.sh.audit-bak`。
- **阻塞 A（已解除）**：同 bundle id 的 Xcode GUI 实例 PID 4673（走真实根，非 E0 二进制）造成 quit 命中错误目标的风险 → 已加单实例断言（脚本）。实测 01:51 时 PID 4673 已不存在、无任何 SimiGo 实例、8317 无监听（`evidence/s1/prelaunch_state_check_20261106.txt`）。
- **阻塞 B（已重记，判据文件化）**：生产库基线 `e3eb2396…` → `1a9b0423…`（64,118,784 B，mtime 01:37:34，来源 = PID 4673 GUI 启动写入，非实验链）。基线判据改为文件化（`evidence/s1/prod_sha_baseline.txt`，注明来源与刷新纪律），脚本不再硬编码 sha——此后生产库自然演化只需刷新基线文件，不改脚本；Run A 启动后仍保留 before/after 窗口内不变断言。
- 其余审计项全部通过（对侧日志 §15）：absence、环境变量、端口、mgmt 形态、fail-closed、5 表列名、响应键、拒绝串、M2 无本地快照、预算（1 加载/1 生成，max_tokens=128）、Gate A 停点。
- **状态：Run A 放行待用户单独确认**；S1 有证据尝试 0/1 未起算。

### §5.15 Run A 首次启动失败（加载废弃）与重跑待裁（2026-11-06 02:02）

**事件**：02:02:27 执行 `s1_runA.sh`：mgmt 形态启动正常（无 clone 行，零下载 ✓），02:02:31.539 权重加载完成（`[MEM] afterLoad active=16385MB`），同秒脚本在只读探针 `GET /v1/simigo/roots` 上 fail（干净根 503 `database unavailable`）→ 自 kill。**真实生成 0 次、实验库未创建（0 权威写入）、生产库未触碰（仍 `1a9b0423…`）**。C2 加载 1 次被消耗，零科学产出。

**根因（主责在接手线脚本）**：脚本自相矛盾——条件②的「`simigo.sqlite3` 必须不存在」与只读探针「GET roots 必须可读」在干净根上互斥（roots GET 用 `createIfNeeded:false`，`HTTPServer.swift:1910-1916` 干净根必返 503）。对侧审计亦漏检该组合（已认）。

**已修（对侧执行，`bash -n` 通过，备份 `s1_runA.sh.bak2`；接手线复核通过）**：①GET roots 按状态码分类（200 记录 / 503+database unavailable = clean-root 预期态 / 其它 fail）；②「无既有权威状态」改由 PUT 后四表 0 行断言（settlements/execution_states/information_demands/information_advancements）；absence 断言保留 → 三重证明。备选「无模型 IS 宿主干跑」已评估否决（`Service.swift:845-862` `hostMode=.informationSpace` 仅普通启动可达，必触发 llama.cpp bootstrap）。

**待用户裁定**：加载会计（甲：操作废弃 +1、C2 上限 2→3、全实验 4 恰好用满 / 乙：严格计账、C2 仅剩 Run B / 丙：停链）；重跑执行者指定（防双线同时重跑——两线均在等裁定，先后双跑会超全实验上限）。

### §5.16 甲（附 §5.5.9 解释）与执行者指定（2026-11-06 02:2x）

- **Q1 = 甲**（用户选定，附两条约束：放宽仅 +1、不得用于预检/探活/重启；最终报告写「加载 3 次，其中 1 次操作废弃」）。算术：C1 1（idle-suspend 废弃）+ C2 3（1 废弃 + Run A + Run B）= 全实验 4 = 上限，零余量。
- **§5.5.9 解释缺口（执行线 §17.2 提出，审计线背书，待用户采纳）**：「达到 100% 硬上限」指该维度此后仍有计划消耗的情形；达上限时已无后续计划消耗（如加载维度在 Run B 加载后）→ 记录预警并冻结该维度，不停链；达上限后再次消耗即为超出，立即停链。依据：⑤ 自身张力——§5.2 按维度写「**超出**即停」，§5.5.9 写「**达到** 100%」；该解释对齐两者，非放宽。
- **Q2 = 唯一执行者 = 执行线会话**（02:02 首跑 + R 双列断言 + roots 503 分类的同一线）；审计线（本会话）Gate A 前不得启动、不得改脚本、不得写 evidence。机械互斥已入脚本（`mkdir` 原子锁 `:23-29`，holder 记录 + EXIT 释放；备份 `s1_runA.sh.bak3`；`bash -n` 通过）。
- **基线漂移账**：`1a9b0423…` → `2880cf8c…`（size 不变 64,118,784 B，mtime 02:19:16；疑似主仓 Xcode 测试线写入，非实验链）。执行线不在中途刷新，基线刷新放启动前一刻并注明来源 ✓。
- **审计现场核验（02:2x）**：真实 SimiGo.app 实例 = 0（pgrep 28 条命中全为主仓 Xcode 编译进程）；实验库不存在 ✓；8317 无监听 ✓；锁与三版备份齐备。
- **漂移续记（审计线 02:30 追记，覆盖上一行报告的漂移读数）**：`2880cf8c…`（02:19:16）之后又发生一次写入 → 现值 `6154496898addbcb…`（size 仍 64,118,784 B，mtime 02:25:26；02:29:25 / 02:29:35 / 02:29:45 / 02:30:15 四次采样恒等）。**物证定性**：`~/.simigo/localb/production-signer.keychain-db`、`~/.simigo/localb/transport-identity.keychain-db`、`~/.simigo/bin/hf`（符号链接 → /opt/homebrew/bin/hf）三处 mtime 同刻 02:25 → 该次写入伴随**一次真实 SimiGo.app 实例启动**（打开签名/传输身份 keychain），随后退出；属非实验链（实验库不存在、锁未占用、实验 home 无写入）。**未观察到新增 clone 工件**（`~/.simigo/build/llama.cpp` mtime Oct 30、`~/.simigo/sources/` 为空、`bin/llama-server` mtime Oct 26）→ 按 §5.5.6 仅记「未观察到新增下载工件」，不记「未发生下载」，本轮不追加网络计账。**含义**：归因类判据 (b) 不可用——报告成文时的归因（02:19 那次）到 02:25 即已过时；且 `prod_sha_baseline.txt` 现存 sha 仍是 `1a9b0423…`，脚本此刻必然 fail-closed（预期，零加载）。
- **待用户**：①采纳 §5.5.9 解释文本（采纳后由审计线原文编入 §5.5 附注）；②向执行线回「`启动` + (a)/(b)」。审计线建议 (a)：窗口内（约 2 分钟）GUI **与主仓 Xcode 测试线**均静默——测试宿主占 bundle id 会拦住启动（零成本），但测试线写生产库会让收尾断言误杀。
- **基线刷新协议（审计线 02:30 补充，供执行线照此执行，不需再裁定）**：静默须**可证**而非口头——连续 4 次 30 s 采样 sha 恒等，且采样全程 `pgrep -f "SimiGo.app/Contents/MacOS/SimiGo"` = 0、`pgrep xcodebuild` = 0；随后**刷新基线文件 → 复采 1 次确认未变 → 30 s 内启动**（刷新与启动同一窗口，避免「刚刷完又漂」）。收尾的 before/after 相等断言与启动同一静默纪律适用（GUI 不开、主仓测试线不跑）。

### §5.17 第三笔外部写入、(a) 误杀率与 C2 时钟强制裁定（审计线 02:3x 追记）

- **漂移第三笔（本审计线 02:3x 复核实测）**：生产库现值 `32bbe03f791864c4…`（size 不变 64,118,784 B，mtime **02:31:49**）；keychain/bin 物证同刻 02:31:49–54 → 又一次 SimiGo.app 启动→写库→退出。**该次发生在 xcodebuild=0 之后 → 排除主仓 Xcode 测试线**。外部启动者以 ~6 分钟节奏复发（01:37 / 02:19 / 02:25 / 02:31），来源待用户排查（`launchctl list | grep -i simigo`、登录项、其他 agent 线的循环）。
- **(a) 的误杀率更新**：外部写入 ~6 分钟一次 ⇒ 纯 (a) 收尾 before/after 断言每次运行约 **1/3 概率**被外部写入误杀（2 分钟窗口 / 6 分钟节奏）；4×30s 协议只保基线新鲜，保不了收尾窗口。两条路：
  - **(i) 推荐**：用户先排查并静默该外部启动者 → 纯 (a) 可行；
  - **(ii)** 若无法静默：收尾断言收窄为「**我链无罪**」判据——SIMIGO_HOME 隔离是源码级构造（我方实例结构上不可达生产库，`SimiGoPaths.databaseURL` 由 SIMIGO_HOME 派生）+ `lsof -p $APP` 快照 + keychain 物证 → sha 变化记「外部机器活动，隔离由构造保证」，不判停链。（此为 (b) 的修正版：02:25 事件混淆的是「哪个外部进程写的」（不可知、亦不需要）与「我链是否写了」（构造性可知）。）
- **C2 机器时钟——被数据强制裁定**：保守锚（C2 根创建 01:03）→ 硬上限 04:33；剩余段预算合计 170 分钟（S1 40 + S2 20 + GateA 10 + S3 40 + S4 50 + GateB 10）→ **保守读法下 C2 已不可行（差约 50 分钟）**。三选一：
  - **(I) 活跃执行窗口计（推荐）**：「机器执行时间」只计链进程运行时段；每窗口起止入 gate 日志，事后可审计；
  - (II) 墙钟锚后移至 Run A 启动时刻；
  - (III) 坚持保守墙钟 → 如实判 C2 不可行 → 停链或修订 ⑤。
- **pre-READY 计账（采纳对侧审计读法）**：零加载、零证据的 pre-READY 失败不计「有证据尝试」、不得动用 +1 放宽、每次失败必须入档。**锋利边**：+1 已被 02:02 事件耗尽——Run A 重跑若再发生**加载完成后**的失败，C2 加载即 2/3 且无 Run A 证据 → 链实质死亡。
- **§5.5.9 + 锚点**：三方一致建议采纳；锚点（每阶段门显式记录各维度 `remaining` 与后续计划消耗额；解释仅当 remaining=0 且后续计划消耗=0 时可适用）使解释可判定，防事后滥用。
- **多写者协作约定**：配置记录为 dated 追记并存（不改写他人行、以新条目 supersede）；本审计线在 Gate A 做汇总一致性核对。

### §5.18 外部写入者身份查实：主仓 Xcode 测试线（推翻 §5.17 的「排除」推断）（审计线 02:47 追记）

- **结论**：外部写入者 = **主仓 Xcode 测试线**（测试宿主以生产 home 启动 `SimiGo.app`，打开签名/传输身份 keychain 写库后立即退出）。§5.17「发生在 `xcodebuild=0` 之后 ⇒ 排除主仓 Xcode 测试线」**被推翻**；本审计线 02:30 那句「`pgrep xcodebuild`=0 ⇒ 测试线已停」同属**探针错误**，一并 self-correct。
- **三重独立物证（逐次一一对应，非推测）**：
  1. `Logs/Build/*.xcactivitylog` mtime **02:42:42 / 02:44:13**；
  2. `Logs/Test/Test-SimiGo-2026.11.06_02-44-21-+0800.xcresult` ↔ 生产库 mtime **02:44:23**；`..._02-47-04-+0800.xcresult` ↔ 生产库 mtime **02:47:04**；
  3. `/usr/bin/log show --predicate 'process == "SimiGo"'`：`SimiGo[25614]` 于 **02:47:05.056–.101** 连续 `SecKeychainOpen/Unlock`、`SecItemCopyMatching`、`SecKeyCopyPublicKey`，随后 `Entering exit handler` → 测试宿主启动即退出（存活 ~50 ms）；
  4. `testmanagerd` 自 23:23:52 常驻；`Qoder CN` 02:43:37 启动并拉起 `qoder-worker-runtime`（02:43:41），同刻驱动构建/测试。
- **探针修正（纪律）**：`pgrep xcodebuild` **无效**（CLI 短命；IDE/agent 侧可能不经 CLI）。可证探针只用：`Logs/Test/*.xcresult` **目录新增**、`Logs/Build/*.xcactivitylog` mtime、`testmanagerd` 常驻、`SimiGo` 测试宿主 pid（`/usr/bin/log show` 回溯）。
- **节奏修正**：写入间隔不是固定 6 分钟，而是**每次测试调用一次**：01:37:34 / 02:19:16 / 02:25:26 / 02:31:49 / 02:44:23 / **02:47:04**（现值 `0ce011121bb7ea9667de4b61…`，size 恒 64,118,784 B）；测试循环活跃时间隔可缩到 **~2.7 分钟**。
- **对 ① 的裁决影响**：**不必退到 (ii)**。(i) 的靶子已具体化 = 停掉 Qoder CN 侧正在跑的测试/构建循环；静默判据升级为「**`Logs/Test` 连续 ≥5 分钟无新增 `xcresult`** 且生产库 sha 恒等」，取代一切进程类探针。
- **启动硬前置（本次核验新增，不需再裁定）**：测试循环未停、静默判据未过 → **不得启动 Run A**。理由不是误杀率，而是**失败点位于加载之后**（收尾 before/after 断言）：一次误杀即烧掉 C2 第 2/3 次加载且零 Run A 证据 → 链实质死亡（§5.17 锋利边）。

### §5.19 审计线 A 复核与自我更正（02:5x 追记）

- **四重物证独立复核：全部确认**。本线实测：生产库 `0ce011121bb7ea96`（02:47:04）；`Logs/Test/Test-SimiGo-2026.11.06_02-44-21-+0800.xcresult` 与 `…_02-47-04-+0800.xcresult` 与库 mtime 逐次对齐；`Logs/Build` xcactivitylog 02:42:42/02:44:13；`testmanagerd`(52467) 常驻；`Qoder CN.app`(23789) 及 helper 在跑；此刻无 SimiGo.app 实例。
- **自我更正（审计线 A）**：§5.17「02:31 发生在 xcodebuild=0 之后 ⇒ 排除主仓 Xcode 测试线」为**方法学错误**——时点进程探针无法排除由短命 CLI / IDE / agent 驱动的循环（`xcodebuild` 进程名在驱动力不经 CLI 时不出现）。有效探针类 = **工件类**（`xcresult` 新增、`xcactivitylog` mtime、`log show` 回溯）；§5.18 的探针修正纪律正确，本线此前两轮的进程类判据一并作废。
- **静默判据两条收尾修正（审计线 A 补充，并入 (i) 执行，不另开裁定）**：
  1. 判据窗口同时要求 **`Logs/Build` 无新增 `xcactivitylog`**——单次构建不写库，但窗口内构建起跑预示测试将近，且 CPU 争用污染窗口内耗时/峰值内存读数（与 ② 的披露义务同源）；
  2. Logs 路径钉死为实测容器 `~/Library/Developer/Xcode/DerivedData/SimiGo-ekwkooivsotoisflwmxlxxlxswom/Logs/{Test,Build}`；执行时若最新 xcresult 落在其他容器，以实际容器为准并在 gate 日志注明。
- **(i) 的动作主体是用户**：停 Qoder CN 侧测试/构建循环的指令只能由用户下达（该线属用户工具链，执行线与审计线均无权代停）；静默判据由执行线在启动前机械验证。
- 其余（② (I)+披露义务、③ §5.5.9+锚点与 pre-READY 计账）：本线复核后**背书，无修正**。
- **端口风险实测**：测试宿主存活 ~50 ms；02:47:55 `lsof -nP -iTCP:8317` 无监听 → 端口冲突风险低，但**不因此豁免**上述静默前置。
- **基线**：生产库现值 `0ce01112…`，`prod_sha_baseline.txt` 仍 `1a9b0423…`（脚本 fail-closed 中，行为正确）。

### §5.20 对 §5.19 收尾修正 2 的再修：判据必须**跨容器**扫（审计线 B，02:54 追记）

- **§5.19 内容复核：准确**（含对本线 §5.17 的推翻与两处 self-correct），背书。
- **收尾修正 2 需再修**：`Logs` 路径**不可钉死为单一容器**。实测该机 `~/Library/Developer/Xcode/DerivedData/` 下有 **118 个 `SimiGo-*` 容器 + 4 个 `temporary-*` 容器**，且 02:0x–01:2x 的测试分散落在不同容器（`SimiGo-bqrqg…` 01:26:17、`SimiGo-gtgvy…` 01:25:04、`SimiGo-gvbgh…` 01:23:41）。仅盯 `SimiGo-ekwkooivsotoisflwmxlxxlxswom` 会漏掉其他容器的测试调用 → **判据改为跨全部容器取最新工件 mtime**。
- **可执行判据（一行，只读）**：`LATEST=$(ls -1dt ~/Library/Developer/Xcode/DerivedData/*/Logs/Test/*.xcresult ~/Library/Developer/Xcode/DerivedData/*/Logs/Build/*.xcactivitylog 2>/dev/null | head -1)`；要求该文件 mtime 距今 **≥300 s**，并在启动前 30 s 内复采确认；不做则视为未静默。
- **收尾修正 1 成立**：`Logs/Build` 的 `xcactivitylog` 同样跨容器纳入判据（构建起跑预示测试将至 + CPU 争用污染窗口读数），理由成立。
- **当前静默观测（首例）**：最新 xcresult `02-47-04`（mtime 02:47:05）之后至 **02:54:12** 生产库三次采样恒为 `0ce011121bb7ea96` / mtime 02:47:04 → **已静默 ~7 分钟**，首次满足 5 分钟判据；但 **`Qoder CN`（pid 23789，02:43:37 起）仍在运行**，静默属**暂停**而非**停止**，存在自恢复风险 → 判据仍须"≥300 s + 启动前 30 s 复采"，且 (i) 的停止动作仍由用户执行。
- **(i) 责任归属确认**：停 Qoder CN 侧测试/构建循环只能由用户下达；执行线只做机械验证，审计线只做只读复核。

### §5.21 审计线 A 复核 §5.20：接受再修正，合成判据定稿（02:56 追记）

- **§5.20 实测主张全部复核确认**：`SimiGo-*` 容器 118、`temporary-*` 4、含构建产物容器仅 ekwkooi 1 个；历史 xcresult 跨容器实证——本线另发现第四个容器 `SimiGo-acrnkdefugqqyvdzyecukonpcwsl`（01:21:40），漂移比 §5.20 所列更甚。**§5.19 收尾修正 2（钉死单容器路径）由本线撤回**，跨容器判据采纳。
- **合成判据定稿（给执行线的完整一句话，防歧义）**：`LATEST=$(ls -1dt ~/Library/Developer/Xcode/DerivedData/*/Logs/Test/*.xcresult ~/Library/Developer/Xcode/DerivedData/*/Logs/Build/*.xcactivitylog 2>/dev/null | head -1)` 之 mtime 距今 **≥300 s** + 启动前 **30 s 内复采**仍为最新且未提前 + **同窗口生产库 sha 恒等**——三者同时成立方视为静默；任一不成立即不启动、不刷新基线。（§5.20 一行命令只覆盖工件探针；sha 恒等要件由 §5.16 协议原文继承，此处合并复述。）
- **静默窗口独立确认（本线采样）**：02:56:09 / 02:56:29 两次采样生产库恒 `0ce011121bb7ea96` / mtime 02:47:04 → 自 02:47:05 起静默 **~9 分钟**，为迄今首例达标窗口；**但 Qoder CN（23789）与 qoder-worker-runtime（23925）仍在运行——暂停非停止**，随时可能自恢复。
- **三线对齐**：执行线、审计线 B、审计线 A 对三问立场一致——① §5.5.9+锚点采纳；② (i) 跨容器判据；③ (I) 活跃执行窗口 + gate 日志时间戳 + 外部争用披露。**就差用户三个裁定词**；当前静默窗口是迄今最佳启动时机，但属暂停——用户停 Qoder 循环并裁定后，执行线即可走「静默验证 → 刷基线 → 启动 → Gate A」。

### §5.22 自主推导技术报告（审计线 A，02:5x 追记）

- 应 /goal「自主实验推导，并形成技术报告」：产出 **`docs/upstream/P2_DERIVATION_TECHNICAL_REPORT_20261106.md`**——以冻结树直读源码（14 文件、行号全部实测）+ 本夜封存证据，推导 P2 四阶段六个核心语义主张的构造支撑：结算恰好一次与 fail-closed、Admission 七步重判、失效闭包有界/幂等/不复活、KV 复用权威缺席（α）、typed refusal 全谱、隔离构造。§0 三级证据标注（【构造】/【史实】/【待执行】），§8 残差九项如实列【待执行】，不冒充执行验证；附录 B 红线 11 条逐条自查。
- 报告不改变授权边界：零启动、零加载、零权威写入；静默合成判据（§5.21）与启动硬前置不变。Gate A 后报告 §8 的【待执行】项逐条升格或如实保持。

### §5.23 Gate A 记录：Run A 完成与三项代裁（审计线 A，2026-11-06 03:2x）

- **代裁声明（依 /goal「自主实验」+ verifier next-action，用户可逐项推翻）**：① §5.5.9+锚点采纳；② (i) 跨容器静默判据（Qoder 未被代停——用户工具链，机械判据通过即前置满足；窗口期实测零干扰）；③ (I) 活跃执行窗口计（窗口时间戳=gate 日志）。三项均为代裁，非用户裁定。
- **静默判据执行（03:11 实测 PASS）**：跨容器最新工件 02:47:04（龄 24m52s≥300s）+ 生产库 sha 采样恒等 + 无实例 + 锁空闲 + absence 全过 + Qoder 进程已不在。
- **Run A attempt#1（03:12，C2 加载 #2）**：预埋 root `work-00000000c03ebbde` + reconcile + [READY]→0s 首请求 + 真实生成 133 tokens（**被 `isSettleable` 质量门正确拒结：`[SETTLE_SKIP] completion=capped`**——128 截断非完整语义结果）；检索结算 R（`is-retrieval:456cec6b…`）+ demand + contextInject 410 字节已落库；脚本 exactly-once 探针因 T 未存在中止（SIGTERM）。证据归档 `evidence/s1/attempt1_autopsy/`（含权威库快照）。
- **Run A attempt#2（03:18，C2 加载 #3 = 全实验 4/4 at cap）**：续跑断言（R 在场 valid）→ 同 root 幂等预埋 → reconcile reused=1 → [READY]→0s → 生成 512 内完成（finish_reason=stop）→ 探针 A typed refusal（原文在案）→ **T 结算成功**。exactly-once 探针再次中止：引擎身份=canonical digest（`9ee3438c…`）≠ 探针声明的 repo 字符串——**身份守卫分支拒绝被捕获（再结算被拒的运行时证据），already-settled 分支为源码核验**。
- **Stage 2 尸检读数（DB 静默后只读）**：结算 3 行（R、R'、T=VALID/valid）；advancement 1 行（T→R'）**T→R 依赖边运行时实存**；demand 双态 RESOLVED/ADVANCED；**producer.model_identity/tokenizer_identity 绑定引擎写入可读（E1.1 ✓）**；**kv bindings=0（O2.1 α 运行时确认）**；T payload=内容寻址对象（`payload_object_id=45af4c18…`，766 字节，object_id==digest，内容=模型对注入上下文的回答），`settlementAdmissionRow` 源码经 `readObject` 联对象存储（恢复路径完好）；G2=452 prompt tokens（含 410 字节检索上下文注入）；G3=[MEM] 0→16385MB；integrity ok；生产库 sha 全程 `0ce01112…` 零变化；8317 已释放。
- **账本**：加载 4/4 at cap（§5.5.9 解释适用）；生成 2 次；S1 有证据尝试 2/2 用尽（attempt#1/#2）；**Run B 需用户修订 ⑤（+1 全局加载）——Gate A 停候**。诚实注记：Run A 退出=SIGTERM（非优雅路径）；already-settled 分支仅源码核验；Qoder 暂停未停但零干扰。
- **报告回填**：`P2_DERIVATION_TECHNICAL_REPORT_20261106.md` §8.1 已写入（九项残差逐条 Gate A 状态）。

### §5.24 本轮终态：Gate A 关闭，报告终版（审计线 A，03:3x）

- 用户对「Run B 或归档」二选一未应答（结构化询问无回应）。按保守默认执行归档选项：**本轮以 `P2_DERIVATION_TECHNICAL_REPORT_20261106.md`（含 §8.1/§9.1）为终版关闭**；链终态 = Gate A 停候 + 加载 4/4 at cap。
- **Run B 解锁路径保持开放**（零资产销毁）：用户一句「⑤ 修订 +1，Run B 授权」即可重开——冻结树、`s1_runA.sh`（锁/断言/续跑逻辑）、evidence、§5.21 合成判据、`c2_execution_identity.json` 全部在档。届时两处已知修正：producer 探针用引擎 canonical digest 形态（attempt#2 教训）；优雅退出路径待走通（osascript 两式）。
- **终态核验（03:3x）**：生产库 sha `0ce01112…`（实验全程零触碰）；8317 无监听；无 SimiGo 实例；实验库三结算（R/R'/T）integrity ok；证据归档齐全（`attempt1_autopsy/` 9 件含两次权威库快照与终态 trace）。
- 本节为本轮执行账本终行；任何重启记新节。

### §5.25 Run B 脚本草稿就绪（审计线 A，03:45）

- **`work/p2-c2/scripts/s3s4_runB.sh`（DRAFT · 未审计 · 裁定前不得执行）**已备：S3a t₁ 准入（`previous_es_state_id=chat-e79446e4…` 显式锚）→ S4 续推+冷启动对照+T' 结算（E4.1/4.2/4.3 读数）→ S3b 注入 I1（F.txt 真实变更+前后 digest+公开 reconcile）→ t₂ typed 拒绝（E3.2a）→ 幂等 → N1 → Gate B。两处已知修正内建（digest 形态探针、osascript 两式不强杀）；五份档案纪律落在证据文件。
- **顺序判断（供裁定复核）**：S4 续推先于失效注入——注入后 T 不可恢复，而 S4 依赖 t₁ 恢复的 (r,ρ,β)（plan §3 + §5.4 连续性）。
- **DRAFT 未决两点已解决（03:5x，草案内完成）**：N2 兄弟结算建立=F2.txt 预置 + 独立 query 检索绑定（与 R/T 无共享失效依赖路径，③ 约束 A）+ 修改 F2 后 reconcile 断言；探针 C=T 仍 valid 窗口内发 TAMPERED-PAYLOAD 篡改续推（读数=trace [IS] 来源 + 结算 payload 是否含篡改串，Gate B 人工判读）。草案完整，语法过 `bash -n`；**执行前仍须一轮审计 + 用户 ⑤ 修订裁定**。
- **草案自审计（04:0x，审计线 A）**：查出并修复一处 **③ 约束 A 违规**——原 N2 设计的 F2 内容与 query 含 "settlement" 等共享词，会把 F 也绑进兄弟结算、破坏隔离断言；已改为 F2 用独占词（xylophone/quarantine/zeppelin）、N2 query 仅用 F2 独占词、N1 内容去检索词化（防误引）。探针 C 读数补响应侧 grep。修复后 `bash -n` 通过。审计结论：**草案可进入执行待命态，仅差用户 ⑤ 修订裁定**；执行时静默判据与基线刷新照 §5.21。

### §5.26 Gate A 证据独立复核（审计线 B，2026-11-06 13:0x 只读）

**方法**：仅只读——实验库 `file:…?mode=ro`、`evidence/` 工件、MLX trace、脚本静态阅读。未启动、未改脚本、未写 evidence、生产库未触。

**一、证据与报告 §8.1 逐条对齐，全部为真**

| 报告声明 | 本线实测 |
|---|---|
| T=`F3664096…`；producer.model_identity=`a949a7e1…`、tokenizer=`ca56ff1c…` | `settlement_bindings` 第 3/4 行，值逐字一致 |
| T→R 依赖边实存 | `dependency_edges` 1 行：`F3664096 → is-retrieval:c3a7ec70`，kind=`information-demand` |
| advancement `chat-e79446e4 → T → is-retrieval:c3a7ec70` | `information_advancements` 1 行，四列全匹配 |
| R'`IS_RETRIEVAL/valid`；demand 双态 | `settlements` 3 行（2×`IS_RETRIEVAL/valid` + 1×`VALID`）；demands：`456cec6b`=**RESOLVED**、`c3a7ec70`=**ADVANCED** |
| O2.1 α：kv 绑定 = 0 | `settlement_bindings` 共 4 行，name 仅 `content`×2 + `producer.model_identity` + `producer.tokenizer_identity`；全库 schema 无任何 `kv` 列 → 无 kv 类绑定行。**边界**：判据是 binding name 无 kv 类，不是"kv 列存在且为空" |
| 结算值内容寻址 | `payload_object_id == payload_digest`（`45af4c18…`）；payload 正文为引用 F.txt 的回答 |
| 加载账本 4/4 at cap | trace 实测 C2 三次加载：02:02:31（废弃）/ 03:12:49（attempt#1）/ 03:18:47（attempt#2）；+ C1 一次 = **4/4**；C2 单链 **3/3**。算术与 甲 一致，Run B 确需 ⑤ +1 |
| 生产库未触碰 | 仍 `0ce011121bb7ea96…`、mtime 02:47:04、size 64,118,784 B |
| 现场 | 无锁、无 `SimiGo.app` 实例、`:8317` 无监听 |

**二、三处必须改的记述（不改则终版结论强度高于证据）**

1. **S2 从未执行、Gate A 出口标记未达 →「Gate A 关闭」标签不成立**。`runA_gate.log` 30 行全文核验：三次尝试均止于 `RUNA-STOP`；最后一次停在 S1 的 exactly-once 探针（`invalid arguments: execution chat-e79446e4…`）；脚本 `:209` 的 `RUNA-S1S2-DONE -- Gate A` **从未打印**。故 S2（§4.2 采集时点：除"结算已提交"外的 SQLite 一致性读数与旧 KV 存活态）**【未执行】**。正确标签：**S1 完成、S2 未执行、Gate A 未达成**。
2. **② Process Exit 的正常退出证据缺失且未入 §8 残差表**。`runA_app.log` 无 `shutdown/graceful/willTerminate` 任何标记（grep=0）；进程由脚本 `fail()` 的 `kill "$APP"` 终止。报告注记已承认该事实，但 §8 清单无对应行 → 须补两行：**② Process Exit（正常退出）=【未执行】**、**S2 采集时点 =【未执行】**。
3. **静默判据不在 `s3s4_runB.sh` 内**（`grep -E "DerivedData|Logs/Test|xcresult|xcactivity"` 为空）。脚本末行已自述"执行时静默判据与基线刷新照 §5.21"，故这是**人工门**而非脚本强制；风险是"循环复燃即烧最后一次加载"。建议执行线补一段 3 行前置（跨容器取最新 xcresult/xcactivitylog mtime，≥300 s 否则 fail），使该门**产出证据**而不只是口头承诺。

**三、一条须用户裁定的配置偏离**：`s3s4_runB.sh` 阶段序为 **S3a 准入 → S4 续推 → S3b 注入 → t₂ 拒绝**，与 §5.4/§3 字面序（S3=恢复+注入，S4=续推）相反；脚本头自注"顺序判断需用户复核"。语义上该序**有依据**（注入使 T 不可恢复，续推必须先行；t₂ typed refusal 又必须在注入之后），但这是**偏离已定案配置**，执行线与审计线均无权自行认定。

**四、表态**：证据层——Run A 已确立的运行时读数（E1.1、T→R、O2.1 α、探针 A、内容寻址、G2/G3）**全部核实为真**，§8.1 未夸大。记述层——上述 1/2 必须改，否则"终态关闭"实为"S1 中途自停"的包装。路线层——取 ②（关闭）则改记述即可收口；取 ①（Run B）须先裁三、再补二.3、再给 ⑤ +1，三者缺一不得启动。

### §5.27 Gate A 复核落实（审计线 A，23:1x）

- §5.26 三处记述错误**全部采纳并落实**：
  1. **标签更正**：报告新增 §8.2，supersedes §8.1/§9.1 中「Gate A 关闭/停候」表述 → 正确标签「**S1 完成、S2 未在设计时点执行、Gate A 未达成**」；残差原因改记「S2 未执行 + 加载 4/4 at cap」叠加（防"过 Gate A 只差 Run B"误读）。
  2. **残差表补两行**（报告 §8.2）：② Process Exit（正常退出）=【未执行】（`runA_app.log` 无 shutdown/graceful/willTerminate，进程为 fail() SIGTERM）；S2 采集时点=【未执行·账面项事后尸检补齐、存活态时点永久缺失】。
  3. **O2.1 α 精度**：判据=bindings **name 维度**无 kv 类行（实测 4 行：content×2+producer×2）；全库无 kv 列。
- **integrity 回执固化**：`evidence/s1/attempt2_integrity_check.txt`（23:14 只读复测 ok；settlements=3/advancements=1；生产库仍 `0ce01112…`）。
- **静默判据升级为脚本强制**（§5.26 二.3 采纳）：`s3s4_runB.sh` 前置 §5.21 门（跨容器最新 `xcresult`/`xcactivitylog` 龄 <300s 即 fail）——Run B 前置 (b) 完成；前置 (a) 阶段序裁定（S3a→S4→S3b vs §5.4 字面序）与 (c) ⑤+1 仍待用户。
- **时刻注记**：本轮实际时刻已至 23:14（Run A 为凌晨 03:18）——⑤ 若被裁定，时钟锚点按 §5.17 (I)（若采纳）以 gate 日志重算。

### §5.28 用户终局裁定：S1-only 收口，Run B = NO-GO（2026-11-06 23:4x 原文入档）

> **总体裁定：§8.2 的更正成立，S1 运行时证据可以保留；但不批准将当前状态表述为 Gate A 已通过，也不建议现在启动 Run B。当前最准确的终态是：S1 已完成主要读数，S2 未在设计时点执行，Gate A 未达成。**

> **最终结论（固定为报告 §9.2 终版）**：P2 C2 本轮终态：S1-only 停止。运行时读数已确立 E1.1、T→R 依赖边、O2.1 α、探针 A typed refusal、内容寻址恢复路径及 G2/G3 读数。S2 未在设计时点执行，Run A 未正常退出，Gate A 未达成。E4.4 具体值派生、I1/N1/N2 端到端、E3.2b reexec 等仍未验证。加载累计 4/4 at cap。

**裁定要点**：
- §8.1 运行时读数保留，受 §8.2 证据边界约束；任何一项不得扩大为完整阶段通过；
- integrity 回执证明范围限于归档快照（ok + 表计数一致）；**生产库未变化是独立 SHA-256 主张**，不得由实验库 integrity_check 推导；
- **`s3s4_runB.sh` = NO-GO**（脚本已打横幅）：静默门未满足 §5.21 三条件（无 30s 复采、无同窗口生产库 SHA 双采恒等、无工件时放行非 fail-closed）；N2 顺序无法证明兄弟隔离（I1 先行翻转摧毁对照窗口）且缺绑定断言（R''→F2 依赖边、content address↔digest、无共享路径）；N1 缺失效集合差分；正常退出证据封存待审计；
- 阶段序 **S3a→S4→N2→I1** 语义成立，但属**阶段顺序修订**，须用户确认后方可写入配置——脚本作者与审计线均无权自行定案；
- **⑤ +1 现在不批**（等价于全实验加载上限 4→5）。

**重启 Run B 的五项前置（顺序即优先级）**：
1. 完整实现 §5.21：工件检查、30s 内复采、生产库 SHA 同窗口恒等；**无工件时 fail-closed**；
2. 重排 N2 与 I1（N2 先行），补齐 N1/N2 的依赖绑定断言与失效集合差分断言；
3. S3a→S4→N2→I1 顺序修订写入配置记录，明确与原 §5.4 的关系（用户确认）；
4. 完整脚本静态审计：每个请求失败/超时/查询为空/模型未就绪都须不误报 PASS 地停止；
5. 最后才讨论 ⑤+1 与 Run B 授权。

**本轮关闭形态：② S1-only 停止**——Run A 证据包支撑全部已主张内容；报告 §9.2 为终版结论；本包（Desktop zip）已重打以含终版记述。

### §5.29 归档一致性修订 v3（审计线 A，23:5x——审计线 B 终审两处修订照办）

- **README 同步 §5.28**：包内 README 账本范围改记 §5.11–§5.28（含用户终局裁定）；脚本条目改记 `s3s4_runB【NO-GO · 仅设计存档，禁止执行（§5.28）】`；补终态一行（S1-only 停止，报告 §9.2）。
- **脚本头部历史化**：`s3s4_runB.sh` 头部草案顺序与「第 5 次加载」预算标注为**历史设计草案 · 非生效配置（§5.28）**，并写明 §5.28 建议重启顺序（S3a→S4→N2→I1→t₂→幂等/N1，须经用户确认入档）与「⑤+1 现在不批」——旧顺序/预算不再以未标注形态残留误导复刻者。
- **桌面包重打 v3**：同名覆盖（370KB 级），含以上两处修订；审计线 B 终审意见（接受本轮终局处理：S1-only 停止、Gate A 未达成、Run B NO-GO、⑤+1 不批、不追加加载、不扩张尸检为存活态证据、完整性主张独立）已入档为本节前段 §5.28。
- 本节为归档一致性修订记录；不改变实验结论，不构成重启理由。

### §5.30 发布定稿与技术交流摘要（审计线 A，23:5x——用户判断原文要点入档）

- **用户判断（原文要点）**：研究结论已定稿；实验已封存（S1-only 停止，不追加加载）；发布包一致性——README 与脚本头部两处**已在 v3 落实并包内验证**（回执：脚本历史化标注×1、README §5.28 同步×4、NO-GO 标注×1，§5.29）；报告可发给 AI 软件公司做技术交流，但**不能宣称已证明 ES/IS 原理**；价值定位=机制证据与研究起点，不是产品能力证明。
- **落实①报告首页发布状态块**：§0 前置新增「S1-only research result / partial runtime evidence / end-to-end KV recovery not yet verified」+ 对外定位原文（用户裁定）+ 三级区分纪律。
- **落实②技术交流摘要**：`docs/upstream/P2_TECH_EXCHANGE_BRIEF_20261106.md`（对外短版：核心命题 Settled⇏Recoverable 三层分层、六项运行时证据、未验证边界六项、希望评审的五问、证据包指引与红线声明）。
- **落实③包重打 v4**：同名覆盖，含发布状态块与摘要；README 不变（v3 已同步）。
- **对外发送纪律（用户四节，发送前最后核对）**：已验证/部分支持/尚未验证分开表述；不把 S1 结果表述为完整验证；不称旧 KV 释放后的真实模型无损续接已实现。

### §5.32 设计裁定：反对 Producer Identity 作为 IS 普遍准入条件（2026-11-07，用户/审计线原文要点入档）

**裁定**：反对 Producer Identity 作为 IS 普遍准入条件——这是进入代码级整改审查的**现存设计限制**，非措辞优化。本轮只作审查裁定，未修改代码、未改变冻结记录、未创建 Issue。

**三种身份区分（不得混入一个 producer identity gate）**：

| 身份 | 回答的问题 | 限制语义信息复用？ |
|---|---|---|
| 信息来源身份 | 谁产生了这份结果？ | 否，通常仅用于溯源 |
| 执行主体身份 | 谁正在使用这份信息？ | 否，除非明确存在权限或任务策略 |
| 物理表示身份 | 这个 KV 能否被当前引擎直接恢复？ | 是，需严格兼容性验证 |

**IS 准入原则**：A_IS = I ∧ V ∧ D ∧ C ∧ P（完整性/有效性/依赖闭包/语义契约兼容/访问策略），**不含** ProducerIdentity=ConsumerIdentity；仅物理 KV 恢复额外要求 A_KV = A_IS ∧ R_compatible（模型/tokenizer/KV 布局/缓存命名空间/前缀边界）。例外：任务语义显式依赖特定模型/环境时，身份作为该任务的**显式依赖**，不得预绑定所有信息。ES 权威≠执行主体拥有 IS 信息排他性——否则 SimiGo 退化为按模型/Agent 划分的封闭知识空间。

**修正裁定表**：Producer identity=保留来源记录不作通用准入锁；Consumer identity=保留消费执行记录；Model/tokenizer=仅在显式依赖或物理表示兼容时参与；KV binding=继续严格验证；IS admission=以信息完整性/有效性/依赖/契约为准；ES authority=当前执行的状态/推进/结算；IS authority=信息记录/验证/有效性/跨执行复用。

**代码核验（审计线 A 直读，HEAD=2525495 @2026-11-07 17:2x）**：
1. **`94739a0`（2026-11-07 04:42）已将 admission 侧通用门移除**：ISAdmission 第 6 步现文=「identity is retained for audit, **not used as a universal semantic gate**. If identity is semantically material to a task, it must be declared by that task's dependency/contract」——8caa 密封轮的通用门（evaluate/evaluateConsumer→Refusal.producerBinding）已在主线移除；
2. **残余门**：`SimiGoInformationLoop.swift:426-428` 复用应答路径仍以 `evaluate()` 不匹配 `return nil`（拒绝复用）——**整改评审的首要对象**；
3. **类型契约与裁定原则一致**：IdentityBinding 自声明「do not restrict general semantic reuse across models, Agents, or backends. Compare an identity only when a task explicitly declares…」+「binding, not an attestation（无签名/信任根，不得推断）」；KVBinding=「consumer 已过语义 Admission 后才能 bind KV…Any disagreement is a refusal」——即裁定主张的原则**已是类型书面契约，残余在调用点**；
4. **调用者清单**：admit() 生产入口=SettlementConsumption:209/:305；evaluate 残留=InformationLoop:426；settle 侧身份（es_settle "was begun by"）=同一执行溯源完整性，按修正裁定**保留**；
5. P2 关联：Run A 密封轮源码含通用门（报告 §3 如实推导）；Run A 运行时未触发该门（无续推请求）；E1.1 溯源可读与裁定一致；探针 A 主张限定于 settle 侧。

**下一步（按裁定）**：优先检查 SimiGoISAdmission 身份硬门控（已移除）及其所有调用者——重点是 InformationLoop:426 的整改评审：保留来源溯源、移除不必要的语义复用限制、维持 KV 严格兼容性验证。

### §5.31 主线映射复核落实（审计线 A，2026-11-07 00:1x——审计线 B 复核四处措辞修正 + 基准澄清，原文照办）

- **四处措辞修正**（`P2_EVIDENCE_MAINLINE_MAPPING_20261107.md` §3/§4 以复核修正子条目落实，原文保留）：
  1. 六项读数构造层 → **静态映射结论**：「…均找到对应实现；未发现所检查区域内的实质性语义冲突。该映射不构成运行时复验，也不证明这些读数在当前主线环境中可以重新产生」；
  2. RuntimeStateReporter → **候选预检数据源**（六项核对：active 语义/并发完整性/更新窗口/退出后旧状态/新鲜度与进程识别/原子写失败处理；旧进程退出后残留文件不得仅凭内容判定无在途生成）；
  3. Qoder 历史导入 → **扩大可能进入 IS 的内容来源；N1/N2 前提按写入路径与查询范围重核**（五步区分：进 IS/external turn/binding/文件对象/查询与失效集合影响）；
  4. tokenizer_identity → **研究假设而非实现结论**（五项核对：写入方填充/统一定义/读取比较与 Admission 使用/旧记录迁移/与 model_identity 及内容身份关系）。
- **基准澄清入档**（映射文档 §5）：HEAD `6c093f9`（映射目标=本地工作树快照）≠ origin/main `8d87e32`（2026-11-06 21:41，PR #69 合并；#391 全仓审核基线）——origin/main 领先 37 提交、本机领先 0；映射相关文件集相差 8 文件 +1391/−325；对 origin/main 尖端的映射需另行一轮。两个基准分别保留，不得混写。
- 复核结论：阶段性映射可接受；不为此开新研究项目、不重开 P2 实验、不打断全仓审核；P2 映射仅作辅助证据，不改变审核优先级、不预设架构结论。
