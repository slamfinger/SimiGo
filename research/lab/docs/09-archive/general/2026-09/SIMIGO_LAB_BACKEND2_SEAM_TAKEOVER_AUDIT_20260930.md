# BACKEND-2 Seam Takeover Audit — Read-Only

> **ARCHIVED** 2026-10-20 · line: 通用治理 / 其他 · original: docs/00-governance/SIMIGO_LAB_BACKEND2_SEAM_TAKEOVER_AUDIT_20260930.md
> Evidence status: unchanged (content frozen; moved only)


日期：2026-09-30  
状态：`BACKEND2_SEAM_TAKEOVER_AUDIT_COMPLETE / AWAITING SECOND-LAYER`  
唯一问题（human 指令）：**当前代码距离「Execution State 可脱离 MLX
Representation 被另一 backend 接管」还差什么最小事实缺口？**  
方法：只读（grep/sed/既有实验链引用）；零代码修改、零 Contract 变更、
零 PALACE 扩张  
基线：Lab `3ff9a30`；对象 = Lab seam + `LLAMAServerExecutionStateAdapter`
（Round 1，`2cf5adb`+溯源）+ 产品对照链（E0–E3）

```text
observed code fact ≠ inferred gap ≠ proposed mechanism（本文不设计机制）
```

## 1. Execution State 输入清单（接管发生时必须随行的东西）

| 契约字段 | 类型 | 便携性（跨 backend） | 依据 |
|---|---|---|---|
| `ExecutionID` | caller 供给字符串 | **可移植**（不透明串，无后端语义） | contract:8-14 |
| `lineage.root/parent` | ExecutionID 引用 | **可移植** | contract:20-28 |
| `position` | Int64 逻辑轮次 | **可移植**（但与 token 长度的映射是 per-backend 的） | contract:31；E0 影子发现 |
| `continuation.nextInput` | **String 文本** | **可移植——唯一文本载体** | contract:45-51 |
| `lifecycle` | 枚举 | **可移植** | contract:59-64 |
| RepresentationRef | 含 modelIdentity/kvLayoutIdentity/backendIdentity | **不可移植（by design）**——每 backend 自持 | registry:20-58（backendIdentity 默认 "mlx"） |
| token-prefix payload | `[Int]` | **不可移植**：MLX id 空间（swift-transformers encode，MLXPrefixRecomputeExecutor:54-64）≠ llama id 空间（POST /tokenize） | executor:90-96 |

## 2. 数据流追踪（handle → LLAMAServerExecutionStateAdapter）

```text
Runtime-owned（coordinator，零 MLX，contract target）：
  id / lineage / position / continuation(text) / lifecycle
  + 四事务窗口 commit ordering（coordinator:163-271）
  —— 已被 BackendConformanceMatrixTests 三 backend 同 battery 证明
     backend-neutral（61/61 链内；E0/E1/R2 trace 引用）

Backend-owned（LLAMA 侧）：
  LLAMAServerPrefixPayload.tokenPrefix（llama id 空间 [Int]）
  prefix/boundPositions 绑定字典（NSLock）
  transport = executor（/completion /tokenize /props；URLSession）

Representation-dependent：
  继续执行的前提 = prefix tokens（当前 backend id 空间）在位；
  缺失 → adapter 内等价 cold path：createExecution(text)/continueTurn
  经 /tokenize 重建（Round 1 已实测：tokenize 失败 = 零创建；server
  失败 = 状态不变可重试——T6/T7 证据）

MLX-specific：
  MLXPrefixPayload / OversizedPrefixPayload（各自 id 空间）
  O6SegmentedCore / MLXResidencyBackend（B1 面，server-owned backend
  不需要——E2/R2n 配方）
  —— 全部被 E3 协议隔离在 SimiGo2Experimental 内；contract target
     零 MLX（Package.swift:30-32）

UNKNOWN：
  跨 backend 的「同一模型」判定（mlx 4bit vs GGUF 量化：语义等价性
  无定义、无校验面——executor 仅做 model_path 字符串透传）
```

## 3. 既有测试证明了什么（边界）

```text
✔ 同一 Coordinator 生命周期断言在三个异构 backend 上逐字通过
  （conformance matrix）——seam 的 backend-neutral 性
✔ adapter 在真实 transport 下 create/continue/fork/restore/discard 全
  生命周期 + 失败/取消 fail-closed（Round 1 T1–T8，75/75 链）
✔ 产品侧等价现象：E1-R1（restore 缺 KV fail）+ R2n（meta.history 经
  cold path 重建 continuation，history necessity）
✗ 未证明：把【同一个】Execution State 从 MLX 表示迁移到 LLAMA backend
  继续执行（跨 backend takeover 的运行时实验——本审计的问题本身）
```

## 4. 最小事实缺口（唯一问题作答）

```text
G-B2-1  token id 空间不可移植（结构性事实，by design）
        MLX prefix 与 LLAMA prefix 互不可译；接管方必须从【文本】重建
        自己的表示。文本载体在契约层已存在（continuation.nextInput:
        String），但只覆盖单轮。
G-B2-2  多轮 history 无 Lab 契约载体
        Phase B B2：nextInput 是 D；transcript 权威不在 Lab（OP-1）。
        多轮 State 的接管需要 durable 文本 history——当前只存在于
        产品 sidecar（PALACE 线已证其 continuation-bearing，R2n/E3），
        seam 层没有它的位置。
G-B2-3  「同一模型」跨格式判定缺失
        mlx-community 4bit GGUF 量化的语义等价无定义；当前仅
        model_path 透传，无校验面。接管实验需要先回答「换 backend 时
        什么是同一模型」——UNKNOWN，须独立定义。
G-B2-4  非缺口（澄清）：
        handle 五字段/seam 协议/coordinator——零缺口（零 MLX、已三
        backend 验证）；binding 重建——结构性支持（registry N-bindings
        + restore 后重绑模式）；B1——server-owned backend 不需要。
```

**一句话作答**：seam 与契约层**零缺口**——唯一的缺口是**状态迁移载体**：
跨 backend 接管需要以文本（history/nextInput）为介质、由接管方重新
tokenize 重建表示；而多轮文本的 durable 载体当前不在 seam 内（G-B2-2），
且「同一模型」的跨格式判定未定义（G-B2-3）。前两者恰是 PALACE 线已证的
continuation-bearing 信息；第三者是新的独立未知。

## 5. Non-claims

```text
✔ 只读；零代码修改；不设计迁移机制；不扩 PALACE；不做性能 claim
✔ G-B2-1/2/3 是事实缺口登记，非修复提案；修复属未来独立 gate
✔ 「同一模型」UNKNOWN 不由本审计定义
```
