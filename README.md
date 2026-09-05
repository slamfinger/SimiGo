# SimiGo

> **本地高性能 AI Inference Runtime + Local/LAN 共享推理节点**
>
> External Agent 决定做什么，SimiGo 负责把模型算出来。

SimiGo 是运行在 Apple Silicon Mac 上的本地推理运行时：以菜单栏应用形态常驻，对外暴露 **OpenAI 兼容 API**（Chat Completions / Text Completions / Responses），底层基于 **MLX** 完成真正的推理执行。

```text
External Agent / Client
        ↓
OpenAI-Compatible API（Chat / Text / Responses，Streaming / Non-Streaming）
        ↓
HTTPServer（Protocol Gateway）
        ↓
NativeMLX
        ↓
Local Model（MLX）
```

| | |
|---|---|
| 应用版本 | v1.1（`MARKETING_VERSION = 1.1`） |
| 架构基线 | **v4.5 Stable Foundation Baseline**（长期稳定参考架构，非过渡版本） |
| 平台 | macOS（Apple Silicon），SwiftUI 菜单栏应用（`LSUIElement`） |
| 核心依赖 | [mlx-swift](https://github.com/ml-explore/mlx-swift) · [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm) · [swift-transformers](https://github.com/huggingface/swift-transformers) |
| 测试 | `SimiGoTests`，21 用例（`xcodebuild test` 驱动） |

---

## 1. 产品边界

SimiGo **负责**：

```text
Protocol · Tokenization · Prefill · Decode · Physical KV · Prefix Reuse
Streaming · Cancellation · Memory Governance · Observability
Inference Execution Scheduling · Long-Context Resource Governance
Tool Call Parsing / Normalization / Streaming
```

SimiGo **不负责**：

```text
Agent Planning · Agent Memory · Agent Decision
Tool Executor · Shell / SSH · Skill / Plugin Execution
```

核心边界：**Agent Runtime ≠ Inference Runtime**。Tool Call 的执行属于外部 Agent / Tool Executor，SimiGo 只负责把模型输出解析、归一化、去重、审计后流式送达。

---

## 2. 架构总览：三平面模型

Runtime 按 §63 Final Architecture Model 分为三个平面，逻辑身份、执行调度、资源治理彼此正交：

```text
                 External Agent
                       │
                       ▼
              OpenAI-Compatible API
                       │
                       ▼
                 HTTPServer（Protocol Gateway）
                       │
                       ▼
                 NativeMLX
                       │
        ┌──────────────┼────────────────┐
        ▼              ▼                ▼
   Logical Plane   Execution Plane   Resource Plane
        │              │                │
        │              ├─ Gate          ├─ Admission
        │              ├─ Scheduler     ├─ Residency
        │              ├─ Prefill       └─ Eviction
        │              └─ Decode
        │
        ├─ Agent / Session / Logical Branch / Degeneration
        │
        ▼
   Generation Round（Structured Tool Call / Raw Tool Fallback / Ordinary Text）
        │
        ▼
   Physical Token Ledger → Global Physical KV Pool
```

对应代码结构：

```text
SimiGo/
├── App/            # SwiftUI 菜单栏应用入口、设置、模型选择
├── Protocol/       # HTTPServer + Chat/Completions/Responses 三个 API 域
├── Inference/      # NativeMLX 三平面核心：Gate、Scheduler、KV、Stream Filter
├── Lifecycle/      # RuntimeLifecycleCoordinator（生命周期账本）、RuntimeTuning（集中调参）
├── Model/          # 模型类型与节点配置
├── Observability/  # TraceLogger（native_mlx_trace.log）
└── System/         # 服务编排、进程/环境管理
```

---

## 3. 核心子系统

### 3.1 身份模型（Logical Plane）

```text
AgentExecutionKey = AgentId + SessionId + LogicalBranchId
```

一个 Key 派生两个粒度，语义差是架构不变量（白皮书 §3.2.1）：

| Key | 形状 | 粒度 |
|---|---|---|
| `storageKey` | `agent/session` | Session state 与 KV 归属 |
| `gateKey` | `agent/session/branch` | Generation 串行化 |

同 Session 的不同 Logical Branch **可以并发运行**（gateKey 不同），但共享同一份 Session state（storageKey 相同）。任何修改 `sessionCaches` 的代码都必须假设其他 branch 正在并发读写。该契约由 `AgentExecutionKeyTests` 锚定。

### 3.2 逻辑隔离 + 物理复用（Global Physical KV Pool）

- **Logical State 与 Physical KV 生命周期完全解耦**：逻辑上下文按 Agent/Session/Branch 隔离；物理 KV 以 Revision 形态进入全局池，跨 Session 复用前缀（白皮书 §4–§9、Addendum A）。
- **KV Reuse 不依赖 Session 相同**：任意请求的前缀只要与池内 Revision 物理对齐即可复用，实测已验证跨 Session 前缀命中。
- **Physical Token Ledger**：每个 Generation 的真实产出 token 记账（`PhysicalTokenRecorder`，Mutex 同步），作为 Revision 提交与淘汰的依据。
- **Revision 预算**：Revision 数量上限（16）与内存预算正交，二者严格分工（§36）。

### 3.3 Tool Protocol Robustness

- **双路径解析**：Structured Tool Call 与 Raw Tool Call Fallback 并存，解析失败 fail-fast 而非静默污染（§10–§23）。
- **Tool Fingerprint**：KV 复用前校验工具集指纹，不匹配则进入严格过滤，防止历史工具语义污染本轮输出。
- **跨轮 Degeneration 状态机**：检测工具调用重复退化，阻断"同一调用无限复读"。
- **Stream 出口防护**：`closed/canSend` 检查承担 Emit-After-Close 不变量（铁律 98：存在等价防护时不得引入平行状态机）。

### 3.4 内存治理与准入（Resource Plane）

- **Predictive Admission Control**：请求进入前做内存投影（resident KV + Delta KV + 执行工作集 + 安全边际），超预算先触发 Lossless Eviction，仍超额则硬拒绝（`admissionExceeded`），止住 OOM 掉速。
- **权重感知预算**：`budget = min(22GB, RAM − weights − OS reserve)`；权重体积实测前 resolve HF snapshot 符号链接，杜绝 0.0GB 误判。
- **KVTRIM / Swap 观测**：RSS 与 Swap 是治理输入而非治理目标（§31–§32）。
- 全部调参常量集中在 `Lifecycle/RuntimeTuning.swift`，杜绝裸字面量（铁律 35/63）。

### 3.5 并发与调度（Execution Plane）

双层门禁（§37）：

```text
Tier 1  RuntimeLifecycleGate   Runtime 生命周期互斥（load / stop / 切模型）
Tier 2  SessionGenerationGate  同 gateKey 串行、跨 gateKey 并行、shutdown drain
```

- **PrefillScheduler**：全局 actor，同一 Logical Branch 保持生成顺序，全局 Prefill 并发受资源预算控制（§39）。
- **Shutdown 顺序**：`server.stop → prefillScheduler.cancelAll → gate.beginShutdown → cancel tasks → await tasks → gate.awaitDrain`；drain 不变量由千轮 acquire/shutdown 交替压测钉死。

### 3.6 Observability

统一 Trace 落盘 `native_mlx_trace.log`：ADMISSION OBS / GENERATION START / LIFECYCLE 等前缀事件，覆盖准入投影、调度等待、状态迁移与不变量观测（§48）。

---

## 4. 运行时生命周期（Lifecycle Control Plane）

源自 [SimiGo架构收敛.md](SimiGo架构收敛.md) 的 8 步收敛设计，实现形态见白皮书 Addendum C。

### 4.1 状态机与合法迁移

```text
正常链：CREATED → QUEUED → RUNNING →（STREAMING）→ COMPLETING → COMPLETED → RELEASING → RELEASED
异常链：任何状态（≠RELEASED）→ CANCELLING → DRAINING → RELEASING → RELEASED
```

核心规则：

- **RELEASED 是唯一终态**：之后拒绝一切迁移；无论正常完成、取消、错误或断连，最终必须收敛到 RELEASED（铁律 92）。
- **所有终止路径统一汇入 `finish()`**，重复 finish 幂等（铁律 93）。
- 一切状态变化必须经迁移表校验的 `transition()`，表外迁移记录 `INVALID_TRANSITION` 并写入 Trace（铁律 91）。

### 4.2 实现形态：被动账本

```text
RuntimeLifecycleCoordinator（被动账本）
 ├── states[requestID]      唯一身份 → RuntimeState
 ├── identities[requestID]  agentID + sessionID
 └── finish()               统一终止入口
```

设计裁决：账本**只记录**状态与不变量观测，不拥有、不直接释放 Physical KV / Session / Task / Stream——真实资源释放仍由 NativeMLX 既有 Teardown 链执行（铁律 94）。Agent 是参与者而非资源 Owner，可以请求 Runtime 结束，但不能自己决定 Runtime 如何释放（收敛文档 §1/§7）。

### 4.3 落地状态

| 收敛文档章节 | 状态 |
|---|---|
| §1/§2/§3 对象模型 + 状态机 + 迁移表 | ✅ 已落地（Commit 1–3） |
| §5 Lifecycle Coordinator（唯一 terminate 入口） | ✅ 已落地 |
| §6 Stream 独立状态机 | ⛔ 裁决不引入——SSE 出口既有防护已覆盖等价不变量（铁律 98） |
| §8 Lifecycle Trace | ✅ `[LIFECYCLE]` 事件集写入 Trace |
| §9 Invariant Checker | ✅ 以真实钩子落地（`noteRequestTaskEnded` 观测 Invariant 1） |
| §10 生命周期测试矩阵（17 场景） | ⏳ 下一阶段（需实机 Runtime 环境） |

---

## 5. 实验轨道：Controlled Batched Decode

完整章程见 [BatchedDecode实验轨.md](BatchedDecode实验轨.md)。定位：LAN 多用户并发吞吐，把"GPU 时间分片"升级为"批内真并发"。

### 5.1 必要性证明（2026-09-05 实测）

| 场景 | 每路 decode | 聚合 |
|---|---|---|
| 单流 | 28–33 tok/s | 28–33 |
| 3 流并发 | 7–10 tok/s | ≈25（恒定） |

聚合吞吐 ≈ 单流总量：MoE 每 token 重复读取激活权重，N 路并发 = N× 权重读取，内存侧无压力，**唯一瓶颈是带宽复用**。

### 5.2 Phase 2 NO-GO（架构止损）

对 mlx-swift-lm 3.31.4 包源码逐层核查后确认：目标模型（Qwen3_5Moe）为 **Mamba(线性注意力) + FullAttention 混合架构**，`MambaCache` 递归状态无 batch 语义、自定义 `BatchedKVCache` 无法覆盖 Mamba 层、左填充掩码无注入点。

> 在上游为混合架构提供 batch 语义前，**不实施批处理解码**——带病上线（静默输出污染）的代价高于收益（铁律 82 / §54）。

### 5.3 LAN 容量路线（现状）

```text
1. 多节点横向扩容（第二台 Mac 同构部署 + 客户端路由，线性扩容、零代码）→ 见部署指南
2. 换 KV 更轻模型（dense 7–14B 4bit，KV/token 降 3×，并发 ×3）
3. 上游依赖升级后重开实验轨 Phase 2
```

---

## 6. 工程纪律

架构演化遵循 §1 定义的固定管道，**没有必要性证明、Benchmark 或回归验证的新抽象不进入 Core**：

```text
v4.5 Stable Foundation → 局部能力增量 → Benchmark → Invariant Audit → Stress Test → Stable Capability
```

- **§58 新能力准入**：必要性证明 + 实测数据 + 回退方案三者齐备方可立项。
- **§59 禁止方向**：未经验证的能力不得进入 Core。
- **§60–§62 铁律**：99 条核心铁律（含 Lifecycle Control Plane 新增 91–99）固化全部架构裁决，代码评审以其为准绳。

---

## 7. 构建与测试

**环境要求**：Apple Silicon Mac · Xcode 26.5+ · macOS 26.4+ SDK。

```bash
# 构建
xcodebuild build -project SimiGo.xcodeproj -scheme SimiGo -destination 'platform=macOS'

# 运行单元测试（21 用例：Gate 压测 / 身份契约 / Recorder 并发回归 / 调参常量契约）
xcodebuild test -project SimiGo.xcodeproj -scheme SimiGo -destination 'platform=macOS'
```

运行后从菜单栏图标启动服务、选择本地模型目录即可；API 地址可一键复制。LAN 第二节点部署见 [部署指南.md](部署指南.md)。

---

## 8. 文档索引

| 文档 | 内容 |
|---|---|
| [SimiGo_架构白皮书_v4.5_Stable_Foundation_Baseline.md](SimiGo_架构白皮书_v4.5_Stable_Foundation_Baseline.md) | **权威架构参考**（§1–§65 + 3 份 Addendum + 99 条铁律） |
| [SimiGo架构收敛.md](SimiGo架构收敛.md) | 生命周期收敛设计（对象模型 / 状态机 / Coordinator / Trace / 测试矩阵） |
| [BatchedDecode实验轨.md](BatchedDecode实验轨.md) | Batched Decode 实验轨章程（Phase 2 NO-GO 侦查结论） |
| [部署指南.md](部署指南.md) | LAN 节点部署手册（Mac #2 移植） |

> 本 README 为三份架构文档的导航性整合；**一切架构语义以白皮书为准**。
