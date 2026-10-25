# PALACE-1 E1.5 Results — Metadata Dependency Perturbation

> **ARCHIVED** 2026-10-20 · line: PALACE / Integrated ES · original: docs/00-governance/SIMIGO_LAB_PALACE1_E15_RESULTS_20260930.md
> Evidence status: unchanged (content frozen; moved only)


日期：2026-09-30  
状态：`E1.5 COMPLETE / AWAITING SECOND-LAYER`  
设计（预登记）：`SIMIGO_LAB_PALACE1_E15_METADATA_DEPENDENCY_PERTURBATION_
DESIGN_20260930.md`（Q-1…Q-5 预登记不得事后改写）  
执行：`Palace1E15MetadataPerturbationTests.swift`（产品仓，加法式）；
观测 `e15-observations.jsonl`；两测试方法 12.6s，TEST SUCCEEDED  
原始校验：branch-checkpoints 204 项不变；零删除；唯一副作用 trace append

## 1. 预登记对照

| 用例 | 预登记 | 观测 | 判定 |
|---|---|---|---|
| Q-1 meta.storageKey 字段改异值 | SUCCEED | **SUCCEED**，载入后 returned storageKey = 扰动值 | CONFIRMED |
| Q-2 history 单条 tool 消息加空白 | SUCCEED | **SUCCEED**，扰动内容 round-trip 通过 restore（returned meta 含尾空格） | CONFIRMED |
| Q-3 modelId 改真实异库 id | FAIL(mismatch) | **FAIL** | CONFIRMED |
| Q-4a generation 置空 | FAIL | **FAIL** | CONFIRMED |
| Q-4b generation 换非空 UUID | SUCCEED | **SUCCEED**，扰动值原样返回 | CONFIRMED |
| Q-5 cacheSHA256 换合法格式异值 | FAIL(byte-compare) | **FAIL** | CONFIRMED |

**6/6 零偏离。**

## 2. 字段角色表（你要的最终表；restore 列 = 本轮实验，continuation 列
= trace(E0/R2) + 本轮，necessity 仍 PENDING）

| 字段 | restore 接受扰动？ | 拒绝原因 | 谁真正读取 | 保护什么 | 影响 continuation？ |
|---|---|---|---|---|---|
| caller key / 文件名 | —（寻址本体） | 改名即找不到（E1-R1 缺文件先证） | loader 文件寻址 | 分支寻址 | **是：双路径共同的 branch identity 载体** |
| meta.`storageKey` 字段值 | **接受**（Q-1） | 无校验 | 无人校验（returned 原样带出） | 无 | 否（informational duplicate） |
| `history` | **接受扰动**（Q-2） | 无完整性门 | performLoad→makeChatMessages→session；T-1 再落盘 | **无**（SHA 不含 transcript） | **是：cold path 直接输入；restore 路径无保护地携带语义** |
| `modelId` | 拒绝（Q-3） | model mismatch gate | performLoad 同源校验 | checkpoint↔container 兼容 | 间接（container 选择） |
| `generation` | 空=拒（Q-4a）；异值=受（Q-4b） | presence gate | performLoad guard（无比对注册表） | mixed-pair 检测（commit marker） | 否 |
| `cacheSHA256` | 拒绝（Q-5） | 字节比对 | performLoad 流式哈希 | **仅 safetensors 字节**（Q-2 证 transcript 排除在外） | 否 |
| `forkPoint` | —（E0：write-only） | — | 无 reader | — | 未知（保留） |
| `kvFingerprint` | —（E0：102/102 物理缺席） | — | pool namespace（但旧格式 nil→reuseMiss） | reuse/优化 | 否（性能层） |
| safetensors payload | 必须在场（E1-R1） | 缺失即拒 | performLoad | Physical Representation | 否（可由 cold path 替代——trace） |

## 3. E0 → E1 → E1.5 证据链合并读法

```text
E0  4.7GB = 40层×K/V 表示；44KB = 七类候选字段混合体；forkPoint
    write-only；schema 无版本字段
E1  R0：meta 三键自足识别；R1：原生 restore 把 safetensors 作为前置
    （fail-closed ×3）；R2 能力 = cold-start 一等分支（trace，不读
    checkpoint/pool/lineage）
E1.5 restore 验收边界实验钉死：
    - transcript（语义载荷）无完整性保护（Q-2）
    - meta.storageKey 字段值非寻址权威（Q-1）——寻址 = caller key/文件名
    - generation = presence marker 而非 identity（Q-4a/b）
    - SHA 只保护表示字节（Q-5 + Q-2 联合）
    - modelId = 兼容门（Q-3）
```

**浮现中的最小 durable continuation nucleus 候选**（严格保持 candidate，
per 你的裁定）：

```text
caller-key 寻址（分支身份） + history（语义载荷，当前无保护）
+ modelId 同源（兼容前提）
—— 三者即可支撑 cold-path continuation；
    generation/SHA/storageKey 字段值/forkPoint/kvFingerprint
    均不在此集合内（restore-only / informational / 性能层）
```

**纪律重申（human 边界）**：Q-2 只证明了 integrity boundary，不是
necessity boundary；necessity（history 改变 → continuation 行为改变）
待 cold-path 运行时实验，仍被 E1 隔离问题阻塞。

## 4. Non-claims

```text
✔ 六用例零偏离；预登记未改写；结论只到字段角色分层
✔ 未宣称 nucleus「成立」（candidate）；未做 State 终判
✔ 未修改 Contract/产品语义；原始 ~/.simigo 零删除（204 项核验）
✔ 附带偏离处置：无偏离发生（若发生，按纪律记录为发现——本轮未触发）
```
