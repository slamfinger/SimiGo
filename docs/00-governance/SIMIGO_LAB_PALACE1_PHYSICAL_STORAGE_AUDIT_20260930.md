# PALACE-1 Physical Storage Audit — 2026-09-30

状态：`PHYSICAL REALITY AUDIT COMPLETE / AWAITING SECOND-LAYER`  
Gate 语境：`PALACE1 SEMANTIC OPENING = DEFERRED`（`4744d63`，第二层判定：
研究顺序提前，draft 降级为 semantic hypothesis scaffold）  
本审计取代 D1–D4 理论封口，回答三个工程问题（§6）  
方法：**只读**普查（du / ls / find / mdfind / plutil / python-json 读取）；
**零删除、零修改、零写入**于任何被审计对象；SAME-State 列**全部 UNKNOWN**
（为未来删除/重建实验保留，禁止提前推导）

```text
observed physical fact ≠ inferred role ≠ selected storage implementation
```

## 1. Scope 边界

```text
已审计：~/Documents/SimiGo-Lab（Lab 仓）、~/.simigo（本地运行数据，
        human 指定的真实运行目录）、~/.cache/huggingface（模型缓存）
未审计：SimiGo 产品仓源码（路径未提供）——branch-checkpoints /
        prefix-pool 的写入方代码属产品侧，本审计以实物自证 schema
        （artifact self-evidence）替代源码引用，并标记为边界
零删除  = 未对任何对象执行删除/移动/改名/写入
```

## 2. 磁盘组成普查（问题 A）

### 2.1 `~/.simigo`（本地运行数据）= **79G**

| 目录 | 大小 | 内容 |
|---|---|---|
| `branch-checkpoints/` | **62G** | **102 对** checkpoint：`default_<branch-uuid>_main.safetensors`（单文件 0.7G–4.7G）+ `default_<branch-uuid>_main.meta.json`（各 ~44KB）；最新写入 2026-09-30 13:55（审计当日仍在产生） |
| `prefix-pool/` | **15G** | **2 个 namespace**（`44eaa202ce92e06d` 3.9G / `7cc94e3f614b3e35` 12G）× 24 对 `<boundaryHash>-<tokenCount>.safetensors` + `.json` sidecar |
| `llama.cpp/` | 830M | 本地 llama.cpp 源码+构建（`build/bin/llama-server` 在此） |
| `logs/` | 8.8M | `native_mlx_trace.log` |
| `.venv` | 38M | Python 环境 |
| `harness/` | 1.0M | Swift harness（main.swift + build.sh） |
| `bin/` | 56K | **`llama-server` 启动器 + `hf`** |
| `models/` | 0B | 空（模型实际在 HF cache） |

### 2.2 `~/.cache/huggingface` = **170G**（8 个模型目录）

```text
42G  mlx-community/Qwen3-Coder-Next-4bit          ← Lab App 默认模型
30G  peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX-6bit
21G  peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-GGUF-MTP  ← llama-server 用
20G  peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX    ← checkpoint meta 的 modelId
20G  peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e
16G  mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit
15G  RadixArk/Muse-Glimmer-q4-MLX
 6.3G mlx-community/gemma-4-12b-coder-…
```

### 2.3 Lab 仓 = **4.0G**

```text
.build   3.7G（out 3.2G / checkouts 210M / repositories 140M / prebuilts 115M）
.git     222M（全部登记史）
build/    49M（遗留 Xcode 产物，SimiGo2App binary 45M）
results   19M / 309 files（backend-conformance 183、o5-sweep 37、
          workload-trace 26…；全部已 commit——working tree clean）
Sources 1.0M + Tests 292K；docs 3.1M；track*/exp06 ≈0.9M
```

### 2.4 总览

```text
总足迹 ≈ 253G = HF 权重 170G（67%）+ ~/.simigo 79G（31%）+ Lab 4.0G（1.6%）
语义/证据资产（源码 1.3M + docs 3.1M + results 19M + .git 222M）≈ 245M
  = 总足迹的 0.1%
durable State 载荷（checkpoints + pool）= 77G = 30%
```

## 3. Provenance map（实物 → 生成代码 → 角色）

| 实物 | 生成者（代码证据） | 角色 |
|---|---|---|
| `branch-checkpoints/*` | **产品侧写入**（Lab 源码 grep `.simigo`/`branch-checkpoints` = 零命中，实测）；schema 自证：`storageKey = default/<branch-uuid>/main` | 分支执行的 durable KV 载荷 + 语义 meta |
| `prefix-pool/*` | `PrefixSnapshotStore` exporter（产品接线 B-2；Lab 无实例化点——Phase C 已证） | prefix KV pool 实物 |
| `bin/llama-server`、`llama.cpp/build/bin/llama-server` | 本地 llama.cpp 构建；**Lab 无 Process 启动代码**（Phase C §2.5），启动属外部 | llama 路线二进制 |
| `bin/hf`、`.venv`、`harness/`、`logs/` | 用户/工具环境 | 环境 |
| HF hub cache | mlx-swift-lm hub 加载（`SimiGo2App.swift:94-102` 默认 hub id）+ llama-server `--model` CLI | model weights（环境） |
| Lab `.build` / `build/` | SwiftPM / 历史 Xcode | 工具产物 |
| Lab `results/*.json` | probes/experiments（simigo2ctl 分发 + toJSON），**全部已 commit** | 观测史（git 兜底） |
| `.git` | 登记链 | 证据与治理本体 |

## 4. 物理对象账本（SAME-State 列全部 UNKNOWN——禁止提前推导）

| 实物 | 大小 | 来源代码 | 对应 State | 删除后 | 能否重建 | 重建成本 | 是否仍是 SAME State |
|---|---:|---|---|---|---|---|---|
| branch-checkpoints safetensors ×102 | ~62G | 产品 checkpoint writer | 分支执行的 KV/前缀载荷（`cacheSHA256` 校验） | KV 载荷消失 | ? | ?（重算需 transcript+modelId，见 meta） | **UNKNOWN** |
| branch-checkpoints meta.json ×102 | ~4.5M | 同上 | **durable 语义记录：transcript 全文（role+content）+ modelId + cacheSHA256 + checkpointGeneration + storageKey** | 该分支 durable 语义记录消失（是否存在第二副本未审计） | ?（transcript 可能仅此一份 durable 副本） | ? | **UNKNOWN** |
| prefix-pool safetensors ×24 | ~15G | PrefixSnapshotStore exporter | pool prefix KV | pool 前缀丢失 → recompute 或重导出 | ? | ? | **UNKNOWN** |
| prefix-pool sidecars ×24 | ~5K | 同上 | pool 索引 claims（tokenCount/modelID/chainHash/kvFingerprint/version） | 索引丢失 | ?（safetensors 在但 claims 失） | ? | **UNKNOWN** |
| `bin/llama-server` + `llama.cpp` | ~830M | 本地构建 | environment（llama 路线） | llama 路线不可运行 | 是（源码在，重编译） | 编译时间 | **UNKNOWN** |
| HF cache 8 模型目录 | 170G | mlx hub 加载 / llama-server --model | backend/model（环境） | 对应 backend 不可加载 | 是（hub 重下；**上游可用性是风险**） | 下载带宽/时间 | **UNKNOWN** |
| Lab `.build` + 遗留 `build/` | 3.75G | SwiftPM / 历史 Xcode | none（工具） | 编译产物消失 | 是（`swift build`） | 冷构建（分钟级） | **UNKNOWN** |
| Lab `results/` 309 files | 19M | probes/experiments | 观测史（无实例） | 观测记录消失——**git 已保**（全部 committed） | 是（git restore） | 低 | **UNKNOWN** |
| Lab `.git` | 222M | 登记链 | 证据与治理本体 | 程序证据史消失（remote 备份在） | 是（clone） | 低 | **UNKNOWN** |
| durable Execution Semantic Snapshot（Contract SC-2 定义物） | **零实例** | **无任何写入者** | （将是 E-state 本体） | **无对象可删** | N/A | N/A | UNKNOWN（对不存在对象无意义） |
| durable transcript 独立存储 | 零（仅 checkpoint meta 内嵌） | 产品 writer | （OP-1 相关） | 见 meta.json 行 | ? | ? | UNKNOWN |

## 5. Key findings

```text
F-1 语义方案错位（本审计最重要发现）
    durable 实物携带的语义 = transcript 全文 + modelId + cacheSHA256 +
    checkpointGeneration + storageKey；
    Contract v1.0 五元组（ExecutionID / lineage / position / continuation /
    lifecycle）在物理 durable 层【不存在任何字段】。
    Contract 的 Execution Semantic Snapshot 物理上没有实例；物理存在的是
    另一套以 storageKey/generation/cacheSHA256 为身份的 checkpoint 实物
    方案。两套方案之间无已建立映射。

F-2 transcript 已被持久化（OP-1 物质基础比假设强）
    meta.json history 含全文对话（role+content，示例 17 条）。transcript
    durable 副本存在，但其与 nextInput / ExecutionID 的映射未建立——
    OP-1 重锚定，不解决。

F-3 prefix-pool 与登记 schema 逐字吻合
    namespaceHash 目录 / boundaryHash-tokenCount 命名 / sidecar 字段
    {version, modelID, kvFingerprint, tokenCount, chainHash} 与
    PrefixSnapshotSidecar 登记完全一致——登记的 store 设计在产品侧已有
    物理对应物（两个 namespace = 两组 modelID+kvFingerprint）。

F-4 Lab 树零 durable State 实例
    Lab 源码对 .simigo / branch-checkpoints 零引用（grep 实测）；全部
    durable 实物由产品侧写入。Lab 与实物之间隔着产品仓（本审计边界）。

F-5 llama-server 二进制定位
    ~/.simigo/bin/llama-server（启动器）+ ~/.simigo/llama.cpp/build/bin/
    llama-server（830M 构建树）。binary-swap 实验（environment vs State）
    的对象已具备。CrashReporter plist（2026-08-31）证明运行史。

F-6 无 retention/GC 痕迹
    branch-checkpoints 自 08-16 起持续累积（102 对 / 62G），含 pool-battery
    等测试产物；未见任何清理机制——观察事实，非建议。
```

## 6. 三问作答

**A. simigo 的磁盘空间实际由什么组成？**
≈253G = HF 模型权重 170G（67%，environment）+ `~/.simigo` 运行数据 79G
（31%，其中 durable State 载荷 77G：branch checkpoints 62G + prefix pool
15G）+ Lab 仓 4.0G（1.6%，其中 .build 3.7G 为工具产物）。真正的语义/证据
资产（源码+docs+results+git）≈ 245M = **0.1%**。

**B. 哪些删除只是性能损失，哪些会造成 State 损失？**（假设分级；删除实验
未做，SAME-State 列全 UNKNOWN）

```text
工具级（性能损失）：.build / 遗留 build / llama.cpp 构建树 / .venv
环境级（可重取，上游可用性风险）：HF 权重 / llama-server binary
证据级（git 已保）：results / .git
State 载荷级（唯二候选，影响 UNKNOWN）：
  branch-checkpoints safetensors（KV 载荷）与 meta.json（durable 语义
  记录，含可能是唯一 durable 副本的 transcript）
```

**C. 如果 Physical Representation 全部消失，当前 SimiGo 到底还剩什么？**
源码 1.3M（含 Contract 实现类型）+ git 222M（全部登记链）+ docs 3.1M +
results 19M ≈ **245M 语义与证据资产；零个 durable Execution State 实例**
——进程死亡即具体 State 消失，今天无一例外（Lab 侧）。唯一在进程外存活
的语义记录 = `.simigo` 的 checkpoint meta.json（transcript+modelId）与
pool sidecar——它们是否算「Physical Representation」还是「durable 语义」，
**正是本审计暴露出的、必须由下一阶段定义的第一个问题**。

## 7. Hypothesis register（A/B/C 情况——全部 hypothesis，不结论）

```text
H-A（KV 可扔）   meta.json 已含 transcript 全文 → 理论上从
                 transcript+modelId 重算可得等价 KV——待删除/重建实验
H-B（缺小 metadata） durable meta 缺 Contract 五元组映射字段 → PALACE
                 可能只需 KB 级映射/校验 metadata 而非 77G 载荷——待实验
H-C（KV 不可替代） 若 cacheSHA256 对应的 KV 数值语义不能由 transcript
                 重算恢复 → Contract 的 State≠Representation 需精化——待实验
决定实验 = 受控删除/重建对照（须独立指示；本审计零删除）
前置三分指示点：(i) Lab 最小接线 PrefixSnapshotStore 产生可实验实物；
(ii) 提供产品仓路径/授权，纳入 writer 源码级 provenance；
(iii) 授权对 .simigo 实物做受控实验。本审计不选择。
```

## 8. Non-claims

```text
✔ 零删除 / 零修改 / 零写入被审计对象（只读工具：du/ls/find/mdfind/
  plutil/python-json 读取）
✔ SAME-State 列全部 UNKNOWN（为未来实验保留）
✔ 不修改 Contract；不新增 PALACE 语义；D1–D4 维持 DEFERRED（scaffold）
✔ 产品仓源码未审计（writer 源码引用以 artifact self-evidence 替代，
  已标记边界）
```
