# PALACE-1 E1.5 Design — Metadata Dependency Perturbation

> **ARCHIVED** 2026-10-20 · line: PALACE / Integrated ES · original: docs/00-governance/SIMIGO_LAB_PALACE1_E15_METADATA_DEPENDENCY_PERTURBATION_DESIGN_20260930.md
> Evidence status: unchanged (content frozen; moved only)


日期：2026-09-30  
状态：`E1.5 DESIGN COMPLETE / AWAITING EXECUTION APPROVAL`  
唯一问题（human 裁定措辞）：  
> 逐字段扰动 durable metadata，区分「State/continuation 所需信息」与
> 「checkpoint restore 所需的保护/优化信息」。  
执行矩阵（human 指令）：`storageKey → history → modelId → generation →
cacheSHA256`；`forkPoint`/`kvFingerprint` 移出执行矩阵（102/102 无物理
落笔 = E0 provenance finding，保留不删）  
性质：设计冻结；执行待 human 批准；预登记 Q-1…Q-5 不得事后改写

```text
observed perturbation response ≠ inferred field role ≠ final State verdict
```

## 1. 关键设计输入（本轮代码核验，决定实验形态）

```text
I-1  load 路径（loadSessionCache/performLoad）零磁盘写入——只读 meta +
     safetensors + 内存注册。⇒ E1.5 restore 扰动【无需写隔离】，可在
     正常测试宿主运行（唯一副作用 = trace append，已在 E1 披露先例）。
     与 E1 的 R2（generate 路径，有 T-1 写入）不同——这是 E1.5 能立即
     执行的结构性原因。
I-2  generation 校验 = presence-only（:1612-1618：guard 非空；无任何
     注册表比对）⇒ 预期任意非空串可通过。
I-3  meta.storageKey 交叉验证未见于 performLoad——文件名由 caller key
     派生（cacheFileName(for: key)），meta 内字段是否被校验 = E1.5 要
     实测的第一个真问题。
I-4  history 无完整性门——cacheSHA256 只覆盖 safetensors 字节；
     transcript 扰动的响应 = 实测第二真问题。
I-5  safetensors 必须在场（与 E1 相反）：E1.5 要隔离「单字段门」，
     缺 payload 会被文件缺失错误掩蔽一切。样本用 E1 baseline 副本
     （双文件完整，/tmp/simigo-palace1-e1/baseline/，714MB）。
```

## 2. 扰动矩阵（每次恰一个字段，基线 = baseline 原样副本）

| # | 扰动对象 | 扰动内容 | 观测层 | 预登记 |
|---|---|---|---|---|
| Q-1 | `meta.storageKey` 字段 | 改为异值（文件名/caller key 不变） | load 成败；载入后 ManagedSession 的 key 归属 | **SUCCEED**（无交叉验证）→ 字段 = informational duplicate；寻址权威在 caller key/文件名 |
| Q-2 | `history` 单条 tool 消息内容 | 尾部加空白字符（规范化可见、语义中性） | load 成败；重建 history 是否携带扰动 | **SUCCEED**（transcript 无完整性门）→ 语义内容无保护地参与 continuation——PALACE 语义研究的核心输入 |
| Q-3 | `modelId` | 改为另一真实存在的 hub id 字符串 | load 成败 + 错误分类 | **FAIL（model mismatch）** → compatibility gate |
| Q-4a | `checkpointGeneration` | 置空串 | load 成败 | **FAIL**（presence gate） |
| Q-4b | `checkpointGeneration` | 换另一非空 UUID | load 成败 | **SUCCEED**（presence-only，无比对）→ commit marker，非 identity |
| Q-5 | `cacheSHA256` | 换合法格式异值 | load 成败 + 错误分类 | **FAIL**（字节比对）→ integrity gate |

## 3. 分类判据（实验后逐字段归层，不在此预答）

```text
恢复必需信息（continuation candidate）
  = 扰动后 cold reconstruction 的输入集（trace 已定：history+modelId
    (compat)+storageKey(caller)）；restore 路径中其缺省/异值若导致
    「载入了错误语义」而非「拒绝」⇒ 最危险类别（无保护语义）
保护/优化信息（restore-only）
  = 扰动只导致拒绝、且 cold path 完全不读（generation/SHA 预期层）
无角色（informational）
  = 双路径均不校验（storageKey 字段值预期层；forkPoint/kvFingerprint
    已由 E0 物理缺席钉死）
```

## 4. Runner 与纪律

```text
载体   = 产品仓 SimiGoTests 加法式新文件 Palace1E15MetadataPerturbation
         Tests.swift（只新增；复用 E1 的 observe/基线机制）
样本   = /tmp/simigo-palace1-e1/baseline/（safetensors+meta 完整；
         每用例从 baseline 重新拷贝工作副本，扰动后即弃——副本间零污染）
执行   = 无需写隔离（I-1）；xcodebuild 常规；E1-a 的 iso8601 decoder
         修正沿用；每用例记录精确错误或成功 + 载入摘要
纪律   = 不修产品代码；原始 ~/.simigo 只读（唯一副作用 trace append，
         沿用披露）；预登记 Q-1…Q-5 不得事后改写；结论只到「字段角色
         分层」，不做 State 终判（那是 E3 + cold-path 运行时实验的事）
PENDING 移交 = cold-path 运行时扰动仍被 E1 同一隔离问题阻塞（但其字段
         依赖已由静态 trace 覆盖：cold path 不读 generation/SHA/
         storageKey 字段值——只读 caller 供给与 history）
```

## 5. Gate sequence

```text
本设计 → human 批准 → 执行（Q-1…Q-5，~6 个测试用例）→ 结果文档
（对照预登记）→ 第二层判断 → 与 E0/E1/R2-trace 合并 → PALACE durable
nucleus 的证据底盘成型
```
