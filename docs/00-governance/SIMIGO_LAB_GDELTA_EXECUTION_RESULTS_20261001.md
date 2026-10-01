# G-δ Minimality Validation — Execution Results

日期：2026-10-02（执行跨 10-01 深夜至 10-02 凌晨）
状态：`EXECUTED / MECHANICAL VERDICT: CLOSURE_REVISION_REQUIRED
（subsumption registered）/ I·A·C = necessity evidence /
P = compensated(full-prefix 锚载体) / AWAITING HUMAN CLOSURE REVISION
GATE`
任务令：human 2026-10-01（授权 G-δ 按 8151458 冻结预注册执行；十二
条纪律在案；「four relations cannot be removed」禁止升级为数学
minimal）
上游：G-δ Design/Pre-registration（8151458）+ 最小性判据（056e283）

---

## 1. 执行过程（两 pass；implementation failure 按 #10 路由）

### Pass 1 = implementation-failure pass（留档，不入判读）

6 个 invocation 成功但 Gδ-FULL 偏离：C1=INCONCLUSIVE（J-I2=NO）+
C4=FAIL。归因=**harness 两处实现缺陷**：①form 的 modelHash 存了
占位符 `"RECOMPUTED-AT-USE"` 而非真实 GGUF 哈希；②FULL 的 child
分支漏 gen-continue 步骤（child checkpoint 停在 user 消息，与 P7-1
电池结构偏离 → ΔR 落在连续 user 消息上，锚定实体未及出现）。按
冻结路由=implementation failure：修复 harness、全部重跑，不与原始
运行混判。runUUIDs：form F20A01AB / full 7CDECD94 / I 91CDE249 /
P 7B37F86D / A 6BF1DC48 / C E66D4EC6。

**过程教训（如实登记）**：pass-1 原始工件被 pass-2 form 的工作区
清空（`removeItem(work)` 先于归档）覆写，未能留存；其记录=本会话
审计输出逐字引用（上列 runUUIDs + FULL cells 判值 + 四 cell
outcome 字符串）。今后多 pass 执行必须先归档再清场。

### Pass 2 = valid pass（7 个独立进程，19:57–20:00 +0800）

| # | invocation | runUUID | 时长 |
|---|---|---|---|
| 1 | form（双会话 S_A/S_B + placeholder 变体） | audit-20261001-569B3782 | 54.7s（含 2×GGUF 全字节哈希） |
| 2 | Gδ-FULL | audit-20261001-0395FB3E | 44.0s（GGUF 重哈希核验） |
| 3 | Gδ-I | audit-20261001-1FF4E887 | 0.10s |
| 4 | Gδ-P | audit-20261001-EF8CC84C | 0.09s |
| 5 | Gδ-A | audit-20261001-DF19FB70 | 9.8s |
| 6 | Gδ-C | audit-20261001-694661AC | 10.8s |
| 7 | Adjudicate | audit-20261001-8C960D38 | 0.09s |

git=dc12a0c+dirty（harness 未提交纪律）；r0_verify 全 PASS；单调钟
全真。仪器异常登记：FULL 目录 events.jsonl 仅 4 条（中间事件
fork_attach/generate 等未落盘），summary（判读输入）完整、r0_verify
对在场所含事件全过——事件完整性问题登记为仪器观察，不影响判读。

## 2. Gδ-FULL baseline — 与 P7-1 一致 ✅

```text
C1_identity PASS（J-I1/J-I2 双 YES，GGUF 全字节 SHA256 0bbcf3cc…）
C2_position PASS / C3_anchor PASS / C4_continuation PASS
C5_parent_non_pollution PASS / J-A2_divergence PASS
restore_output 与 P7-1 逐字同型：
  "The folder is called \"ReferenceFiles\" and it contains project
   management documents."
baseline_consistent = YES（电池有效前提成立）
```

## 3. 四个 leave-one-out 结果（机械判读，逐 cell）

### Gδ-I（移除 identity 断言）→ **NECESSITY_EVIDENCE**（含分解）

- **provenance conflation**：两个不同会话的 identity-stripped record
  匿名 restore 双双 `ACCEPTED_NO_DETECTION`——剩余关系（P/A/C）对
  「这是哪个计算状态」零区分力；
- **model-binding 结构性无补偿**：无 modelIdentity 后剩余字段无一
  引用模型，wrong-model 恢复在原理上不可检测（单 GGUF 行为验证
  留扩展，如实登记）；
- **partial subsumption（Layer 2 登记）**：content-mismatch 子功能
  被 A 补偿——跨载荷互换中 anchor 检出失配（cross_swap_detected=YES）。

### Gδ-P（移除 position 断言）→ **COMPENSATED — closure revision gate**

- derivability：position 从剩余关系 record 字段**不可推导**（hash
  无原像；carrier 计数被排除）；
- 但 **boundary integrity 被 A 补偿**：截断载体探针中 anchor 检出
  失配（truncation_detected=YES(A)）——full-prefix 锚在此载体上
  **A ⊇ P**；
- **载体依赖性（预注册路径命中）**：MLX KV 载体上 P **不可**由 A
  推导（S1 实证：processedTokenCount 31712 ≠ transcript 可渲染数）。
  ⇒ 同一关系在不同物理载体上必要性不同：**P 在压缩载体（KV）必要
  /在全拷贝载体（token-prefix）被锚 subsume**。

### Gδ-A（移除 anchor 绑定）→ **NECESSITY_EVIDENCE**（最强 cell）

- same-I（同执行绑定）、same-P（同 position、同 token 计数）、
  same-C 的两条 record 在关系层**完全相等**（relation_level_equal=
  YES），仅 carrier 内容不同（placeholder 手术等长替换）；
- 移除 A 后两状态**不可分辨**；续算输出证实语义分叉
  （outputs_differ=YES；original_anchored=YES）——两个逻辑上不同、
  位置相同的 continuation point 被合并 = A 的必要性获得最强实验
  支持（PA-2 模式的 llama 关系级复制成立）。

### Gδ-C（移除 continuation 绑定）→ **NECESSITY_EVIDENCE**（不变量断言级）

- I/P/A 完整时两个不同 append（Δ1/Δ2）均被无差别接受——无契约
  区分合法延续与任意输入；
- 判据按冻结设计在**不变量断言层**：无 C 时「这个输出是 THAT state
  的延续」从 {I,P,A} **不可构造**（INV-C 断言失去依据）——非崩溃
  测试。

## 4. 机械判读（audit-20261001-8C960D38/judgment.json）

```text
FULL_baseline_consistent = PASS
Gδ-I = NECESSITY_EVIDENCE（provenance+model-binding；content 子功能
       由 A 部分补偿——partial subsumption 登记）
Gδ-P = COMPENSATED（A ⊇ P，full-prefix 锚载体）— closure revision gate
Gδ-A = NECESSITY_EVIDENCE
Gδ-C = NECESSITY_EVIDENCE（不变量断言级）
overall = CLOSURE_REVISION_REQUIRED（subsumption registered）
```

## 5. 结果的准确读法（预注册措辞上限内）

- **获得 necessity evidence 的关系：I（provenance+model-binding）、
  A（最强）、C（不变量断言级）**；
- **P 的必要性是载体依赖的**：在 full-copy token-prefix 载体上被
  A subsume；在 MLX KV 压缩载体上必要（已有 S1 反向证据）。⇒
  candidate closure 的修正问题=「P 是 closure 关系，还是压缩载体
  才需要的载体级断言？」——**此问题归 human closure revision gate
  裁定**，本结果文档不预设答案；
- 措辞上限遵守：本档不写「minimal 已证」；「necessity of each
  relation」的全称升格**未达成**（P compensated），按冻结规则输出
  CLOSURE_REVISION_REQUIRED。

## 6. Non-claims

不宣称数学最小性；不宣称跨载体普适；Gδ-I 的 model-binding 行为
验证受单 GGUF 限制（结构观察级）；FULL events 完整性异常已登记；
pass-1 原始工件覆写教训已登记。

## 7. 产物索引

- Pass-2 工件：`docs/02-evidence/gdelta-minimality-20261001/audit-*/`
- Harness：`docs/02-evidence/gdelta-minimality-20261001/harness/`
  （GDeltaMinimalityTests.swift）
- Pass-1（implementation-failure，工件已覆写）：记录见 §1 与本会话
  审计引文
- 工作区：`/tmp/simigo-gdelta/`（本机）

**终判待 human closure revision gate：P 关系在 closure 中的地位**
（保留为关系并注明载体依赖 / 重述为载体级断言 / 其他修正）。

## 8. OPS 注记（2026-10-02 补）：llama-server 运行卫生

- 本轮启动未设 `-c`，llama-server 按模型元数据取 `n_ctx_slot=140544
  × 4 slots` 巨量 KV 分配；实验结束 server 空转仍占 ~75% CPU（日志
  证实 20:00 后零请求却持续高负载）+ 21GB mmap 驻留，系统内存空闲
  曾降至 13%、swap 1.8GB。
- 用户报告推理期间内建屏间断性闪烁。因果链=Metal GPU 推理（21GB
  权重统一内存高频读写 + iGPU 同时承担 WindowServer 合成）+ 内存
  压力/换页 ⇒ 合成器丢帧。server 停止后系统恢复 89% idle。
- **未来 llama.cpp 实验运行规范**：①启动必加 `-c 8192` 限 KV；
  ②可选 `--n-gpu-layers` 调节 GPU 压力（换速度）；③**跑完即关
  server**，不得留驻后台。

---

## 8. CLOSURE REVISION GATE — HUMAN RULING — ACCEPTED — 2026-10-02

**科学裁定原文：`ACCEPTED — SEMANTIC CLOSURE RETAINED, REPRESENTATIONAL
MINIMALITY REVISED`**（机械判读 CLOSURE_REVISION_REQUIRED 之上的正式
裁定；Lab 659ebf8 = 本次 closure revision 的执行证据基线）。

### 8.1 裁定内容：选 (a) 带关键限定

P **保留为 Execution State 的语义关系**；不再把「P 在所有
representation 中都不可由其他关系补偿」作为其必要性条件。

| 关系 | G-δ 结果 | 裁定 |
|---|---|---|
| I | NECESSITY_EVIDENCE | 保留 |
| P | COMPENSATED | **保留为语义关系，标记 carrier-dependent irreducibility** |
| A | NECESSITY_EVIDENCE | 保留 |
| C | NECESSITY_EVIDENCE | 保留 |

### 8.2 正式科学结论（human 原文，英文逐字）

> **G-δ establishes necessity evidence for I, A, and C under the
> tested conditions. P remains a semantic member of the candidate
> closure, but its independent representational necessity is
> carrier-dependent: it is compensated by A in the tested full-prefix
> anchor representation, while prior MLX evidence indicates that P is
> not derivable from A in the tested KV representation.**

中文：G-δ 在当前实验条件下为 I、A、C 获得了 necessity evidence。P
继续保留在 candidate semantic closure 中，但其独立表示必要性呈现
载体依赖：在本次 full-prefix anchor 载体上，P 可由 A 补偿；而既有
MLX KV 证据表明 P 不能由 A 推导。

**禁止升格**：不得说 {I,P,A,C} 已被证明 minimal；不得说 {I,A,C} 已
取代 {I,P,A,C}。

### 8.3 为什么不选 (b)（human 论证，登记）

两个方向相反的实证（llama full-prefix anchor：A 可检测 prefix
truncation；MLX KV：31712 ≠ 可渲染数）证明的是「**P 不是 record 层
universally irreducible**」，还没证明「**P 只是 representation-
specific carrier metadata**」——后者过强。若现在把 P 从 closure 降级，
是用一次载体上的可推导性去修改跨载体的语义模型——违背 G-δ 原本
「让实验决定抽象」的纪律。

### 8.4 两层 closure 定义（本次修正的核心）

```text
Semantic Closure
  ES_semantic = { I, P, A, C }
  描述「未来计算需要保持哪些关系」

Representation Closure
  ES_representation(R)
  描述在具体 representation R 中，哪些语义关系需要独立编码，
  哪些可由其他关系 + representation invariant 推导

干净表达：
  llama full-prefix representation:
      P ∈ Closure_semantic
      P ∈ Derivable(A, R_llama)
  MLX KV representation:
      P ∈ Closure_semantic
      P ∉ Derivable(A, R_MLX)   [based on S1 evidence]
```

### 8.5 方法论产出（G-δ 隐含假设的修正）

G-δ 原隐含假设：「若某关系能在某 carrier 上被另一关系推出⇒它可能
非 closure 独立关系」。实验修正为：

> **独立性不是纯关系属性，而可能是 (relation, representation) 的
> 属性。**

后续协议相应改为：remove P → remaining relations +
representation-specific invariants 能否 derive P？→ YES/NO →
carrier-specific result。（P7-1 跨 backend + G-δ 连起来才暴露此层：
前者证不同 native representation 可表达同一 invariant，后者证同一
语义关系的独立编码需求随 representation 改变。）

### 8.6 已裁定与待决

- **已裁定**：①P 保留为 semantic relation；②增加 representation-
  dependent derivability 层；③minimality 定义从单纯 relation-level
  改为 semantic closure + representation-specific irreducibility。
- **待决**：④是否需要 **G-δR / closure-revision formalization
  gate**（判据文档的两层定义正式化与否）。
- **已裁定（路线）**：⑤不继续堆重复的 llama necessity cell。
- Claim F 维持 bounded cross-backend claim；Gδ-A 与 Gδ-C 的干净性
  （relation record 完全相同 ⇒ continuation 分叉；continuation
  provenance 无法由 I/P/A 构造）作为两层定义的证据锚点登记。
