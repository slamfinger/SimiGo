# PALACE-1 E1 Experiment Design — Checkpoint Representation Loss

> **ARCHIVED** 2026-10-20 · line: PALACE / Integrated ES · original: docs/00-governance/SIMIGO_LAB_PALACE1_E1_RECOVERY_EXPERIMENT_DESIGN_20260930.md
> Evidence status: unchanged (content frozen; moved only)


日期：2026-09-30  
状态：`E1 DESIGN COMPLETE / AWAITING EXECUTION APPROVAL`  
上游：E0（`ed6cb87`）+ human 指令（实验矩阵定序；E1 只验证一个问题；先判据
后删除；不修代码让它通过）  
本文件 = 恢复判据定义 + 副本操作设计。**执行待 human 批准。**

## 1. E1 的唯一问题

> 当 Physical Representation 完全丢失时，现有系统还能恢复到什么程度？

观察对象 = **能力损失曲线**（R0–R4 分层）。不问「meta.json 是否是 State」
（E3 的事）；不比较 KV 字节（那是 Representation）；不修改代码使实验通过
（现有能力边界本身就是结果）。

## 2. 样本选择（schema 普查后确定）

实测（102/102 全量）：**所有 checkpoint 均无 kvFingerprint 与 forkPoint
字段**——含今日 13:55 最新文件。两字段存在于 HEAD 代码但从未物理落笔
（运行二进制早于 repo HEAD，或 encoder 省略 nil）——本身即 provenance
发现：**运行二进制 ≠ repo HEAD**；E1.5 扰动对象收窄为 generation /
cacheSHA256 / modelId / storageKey。

```text
主样本 = default_5401315f-faa7-4984-9639-fccef06ae188_main
         （safetensors 713,859,116 B + meta 43,641 B；2026-09-30 13:55；
          代表幸存实物的真实 schema；无 forkPoint/kvFingerprint）
模型   = peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX（HF cache 在位，30G）
副本量 = ~714 MB（仅样本对；原始 ~/.simigo 79G 不动）
```

## 3. 隔离工作区与副本操作

```text
REAL ~/.simigo                        ← 不动（只读来源）
      │ copy（仅样本对，2 文件）
      ▼
$WORKSPACE = /tmp/simigo-palace1-e1/  ← 隔离实验区（ephemeral）
      ├── baseline/                   ← 原样副本 + 基线记录（先于一切 mutation）
      │     ├── <pair>.safetensors
      │     ├── <pair>.meta.json
      │     └── baseline-records.json
      └── mutation/
            └── <pair>.meta.json      ← mutation：仅删除同目录 .safetensors
```

**Pre-mutation record（mutation 前必录，baseline-records.json）**：
checkpoint SHA256、meta SHA256、tensor 数与逐张量 (dtype, shape)、
transcript 规范化 SHA（对 history JSON 规范化序列化哈希）、消息数与角色
分布、storageKey、generation、modelId、forkPoint（本样本=absent，记录
absent 本身）、消息数即 position 代理、branch 状态（storageKey 后缀）。

**mutation**：仅 `rm mutation/<pair>.safetensors`；meta.json 不动；
原始目录无任何操作。

## 4. 恢复判据 R0–R4（观察层，非 pass/fail 门）

### R0 — Identity（可识别）
程序：解析 mutation/meta.json；核对与 baseline-records 一致。
证据：storageKey / generation / modelId 可读且与 baseline 相等；文件名↔
storageKey 映射完好。
结果类：IDENTIFIED / NOT-IDENTIFIED。

### R1 — Recovery（原生恢复）
程序：在隔离副本目录上调用现有 `loadSessionCache(agentId:sessionId:
logicalBranchId:from:)`（现有公共 API，零修改）。
预登记预期（来自 E0 代码追踪）：performLoad 解码 meta 成功 → 通过
generation/SHA 存在性检查 → `sha256HexOfFile` 对缺失 safetensors 抛
FileHandle 异常 → **R1 预期 FAIL（fail-closed）**。
证据：精确错误（类型 + 描述）；不捕获不翻译。
结果类：RECOVERED-NATIVE / FAILED-FAIL-CLOSED（+ 精确错误）。
**注意**：R1 失败 ≠ E1 结论；R1 失败只是能力曲线的第一层。

### R2 — Continuation（客户端协作重建）
程序：用现有公共能力（不改代码）：以 meta.history 经 `makeChatMessages`
重建消息数组 → 以产品正常会话创建路径新建会话（storageKey 不变 = 同一
logical branch）→ 追加一个 probe 用户轮 → 记录系统行为。
必须记录：是否重算 KV（全量 prefill）；是否只需要 meta.history（不依赖
客户端本地副本）；tool 消息是否回灌；modelId 是否必须同源；能否继续原
branch（storageKey 寻址）；probe 轮是否产生正常生成。
结果类：CONTINUABLE-WITH-FULL-RECOMPUTE / NOT-CONTINUABLE。

### R3 — Semantic Equivalence（对照记录基线，非对照活体）
程序：比较 mutation 前记录 vs 重建后状态：
transcript 逐字等价（重建会话 history ≡ meta.history + probe 轮）、
消息数（position 代理）、branch identity（storageKey）、continuation 点、
lineage（forkPoint：absent≡absent）、下一轮执行语义（probe 响应定性记录）。
**限制声明**：baseline KV 已删，无法对照活体执行；R3 = 对「记录基线」的
等价，不是对「删除前活体」的行为等价。

### R4 — Representation Independence（最严格层，合成判定）
```text
R4-evidenced（cooperative）  = R2 CONTINUABLE + R3 记录等价成立
                               → 「representation 被替换，State 连续性未
                               必然消失」在客户端协作级成立
R4-not-autonomous            = 系统自主恢复路径不存在（R1 fail-closed）；
                               独立性只在协作级成立
R4-failed                    = R2 也不可达（representation 丢失即不可继续）
```
E1 预期落在 cooperative + not-autonomous 之间——**以实验观测为准，不预答**。

## 5. Runner 设计（加法式，零修改）

```text
载体   = 产品仓 SimiGoTests 新增测试文件
         Palace1E1RecoveryExperimentTests.swift（additive，仅新增；
         文件头标注 PALACE-1 实验性质与「非产品语义」声明）
分阶   = E1-a：R0（纯 meta 分析，不加载模型）
         E1-b：R1（加载 Nail-Qwen3.6 30G —— HF cache 在位；调用现有
               loadSessionCache 于 mutation 副本；记录精确错误）
         E1-c：R2/R3（现有公共路径重建会话 + probe 轮 + 记录比对）
纪律   = 不修改任何既有文件；不加 recompute 代码；不做 performance
         claim（耗时仅作运行记录）；原始 ~/.simigo 全程只读
环境   = 模型 Nail-Qwen3.6-35B-A3B-MLX 在 HF cache（30G，本机曾运行）；
         Xcode test（产品仓 Xcode-only，无 SPM）
```

## 6. 预登记预期（E0 代码追踪给出；实验对照之，不得事后改写）

```text
P-1  R0 = IDENTIFIED
P-2  R1 = FAILED-FAIL-CLOSED（sha256HexOfFile 于缺失文件抛错）
P-3  R2 = CONTINUABLE-WITH-FULL-RECOMPUTE（现有公共路径支持）
P-4  R3 = 记录等价可达成（transcript 逐字 + storageKey + probe 定性）
P-5  R4 = cooperative + not-autonomous
任何与 P-1…P-5 的偏离都是发现，按偏离记录，不改预期。
```

## 7. E1 不回答的事

```text
❌ meta.json 是否为 State（E3）
❌ prefix-pool 角色（E2）
❌ generation/SHA/modelId 的 identity-vs-integrity 终性（E1.5）
❌ PALACE 应保存什么（全部实验完成后由证据逼出）
❌ 任何 performance 结论（probe 耗时只作运行记录）
```

## 8. 执行清单（human 批准后）

```text
1. 建工作区 + 复制样本对 + 生成 baseline-records.json（只读来源）
2. mutation：删副本内 safetensors
3. 新增 Palace1E1RecoveryExperimentTests.swift（additive）
4. 依次执行 E1-a / E1-b / E1-c，记录全部观测
5. 产出 E1 结果文档（观测 vs P-1…P-5 预登记对照）
6. 原始 ~/.simigo 校验未动（前后 mtime/清单比对）
```
