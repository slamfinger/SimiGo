# {I,P,A,C} 最小性判据（G-δ）— 判据先行文档

日期：2026-10-01
状态：`CRITERIA FROZEN / EXPERIMENTS NOT DESIGNED / AWAITING HUMAN`
任务令：human 2026-10-01（G-δ：先把最小性判据写死，再决定实验怎么
做，不要反过来为了已有实验结果设计判据）
性质：判据冻结文档，零实验零执行。范围 = MLX backend 上候选关系
闭包 {I,P,A,C}（P6 冻结名：Minimal Dependency Closure for MLX-based
Execution State；普适性另行，不入本判据）。

---

## 1. 对象定义（操作化，来自在案记录；非新理论）

候选闭包 C = {Identity, Position, Anchor, Continuation}，各自操作化
（P5-2-0 依赖图 + P5-4 破坏性记录）：

```text
I Identity      寻址与身份绑定：storageKey / modelId / kvFingerprint /
                checkpoint 身份（哪个模型、哪个会话、哪个工件）
P Position      计算进度关系：processedTokenCount ↔ ledger 对齐
                （算到了哪里）
A Anchor        语义锚：history text ↔ prompt tokenization
                （这些 token 对应什么内容）
C Continuation  续算契约：Δ ≥ 0、prefix-compatible 的延接许可
                （未来输入从哪里接上）
```

环境 E（固定常量，显式枚举、不计入 C）：模型权重、tokenizer、
模型 config、解码参数、backend 实现。

## 2. 最小性的三个独立判据（冻结）

「四个都重要」≠「{I,P,A,C} 最小」。最小性分解为三个必须**分别**
成立的判据：

### M-1 不可消除性（irreducibility / necessity-in-context）

∀X ∈ C：在 C\{X} 下 continuation **不成立或产生预注册的可分辨退化**，
且该退化不能被其余三个关系补偿。

- 证据形态：单元素破坏性消融，**每元素预注册失败签名**（signature
  先于采数冻结）：
  - I 摘除 → restore reject（寻址/身份失配拒载）
  - P 摘除 → 续算严重退化（位置关系断裂）
  - A 摘除 → 语义丢失/无先前对话形态（内容-语义对应断裂）
  - C 摘除 → 拒载/rewind/rebuild（续算契约违约）
- 判定：若某 X 的摘除可被其余关系**补偿至不可分辨**（输出与完整 C
  基线在预注册判据下无差别）⇒ C 非最小 ⇒ 有效结果，登记被补偿
  元素与补偿机制，不得修判据重试。

### M-2 不可推导性（non-derivability / non-redundancy）——新增未检验层

∀X ∈ C：X 的**功能**不能由 C\{X} 在实验宇宙内推导/重构/替代。

- **推导空间预先枚举冻结**（这是 M-2 可判定性的前提）：
  - 允许的变换 T = 仅使用 C\{X} 所载信息 + 环境 E 常量的任何确定性
    变换；
  - **排除项（先钉死，防退化为重算）**：T 不得等价于「从 transcript
    全量重算」——那是 H→R' 路径，ES-R1/FSB-2 已证其非 State 复用
    而是放弃 State；用它「补偿」X 不构成推导，构成绕过。
- 判定三分：
  - 找到宇宙内 T 使 C\{X}+T 在预注册判据下与 C 不可分辨 ⇒ X 可
    推导 ⇒ C 非最小（有效结果，登记 T）；
  - 枚举空间内无 T 成功 ⇒ X 不可推导（该元素 M-2 成立）；
  - **枚举空间无法先验穷尽 ⇒ INCONCLUSIVE**——失败的构造只证
    constructibility 未证 non-derivability（D6 构造≠潜藏教训的
    直接移植：无界搜索失败证明力为零）。
- 逐元素问句（human 原话登记）：去掉 I，其他三个能不能推出 I 的
  作用？去掉 P，其他三个能不能补偿？去掉 A？去掉 C？

### M-3 无隐藏依赖（no hidden elements）

continuation 成功可由 **C + E 完全解释**：不存在未列入 C 的负载
关系被环境默认值掩盖。

- 形态：环境枚举审计 + 一次「C 完整 + 环境异常化」探针（如 E 中
  被假设为常量的项发生变化时续算行为是否改变——改变则该项实为
  关系，须升格入 C 或显式声明为环境前提）。
- 判定：发现隐藏负载项 ⇒ C 非完整最小集（有效结果，登记新元素）。

### 判据合取

```text
C 最小（相对环境 E） ⟺ M-1 ∧ M-2 ∧ M-3
任一判据出有效反例  ⇒ 非最小（有效结果，登记细节）
任一判据不可判定    ⇒ INCONCLUSIVE（不计正反证据）
```

**边界**：本最小性是「相对环境 E 的最小关系集」，不是任何形而上
意义的最小；Carrier 替代不属最小性问题（Carrier≠Closure 原则）。

## 3. 已有证据映射（事后记账，非判据输入）

| 判据 | 已有覆盖 | 复制状态 |
|---|---|---|
| M-1（部分） | P5-4 原跑：PA-1（A 摘除→无先前对话）/PA-2（A 破坏 P 完好→语义丢失=**A 不可由 P 补偿**的直接证据）/PA-3（P 破坏→退化）/IC；P5-2-0 #7/#8（I 摘除→fail-closed/not found） | 原跑，未复制 |
| M-2 | **零覆盖**（全新层） | —— |
| M-3 | **零覆盖**（环境从未异常化） | —— |

## 4. Non-claims 与下一步

- 本文档不主张 {I,P,A,C} 最小，也不主张其非最小——只冻结判据。
- 对应复核实验**另行设计门**（实验矩阵 × 判据覆盖映射 → human
  授权）；禁止以「已有实验能跑」反推实验设计。
- M-2 的推导空间枚举是实验设计阶段的核心难点，预留独立设计轮。

## 5. 封口条件（G-δ）

**判据冻结（本文档）+ 对应复核实验 + 结果登记** 三件齐 = G-δ 封口。
本文档交付第一件；后两件待 human 授权实验设计门。

---

## 8. CLOSURE REVISION（human 裁定登记，2026-10-02）

G-δ 执行结果（COMPENSATED on P @ full-prefix 锚载体 + MLX S1 反向
证据）触发本判据文档的首次修正。**M-1/M-2/M-3 框架保留，但其判定
对象从纯关系层修订为两层**（human 裁定「ACCEPTED — SEMANTIC CLOSURE
RETAINED, REPRESENTATIONAL MINIMALITY REVISED」）：

```text
Semantic Closure
  ES_semantic = { I, P, A, C }
  ——「未来计算需要保持哪些关系」（语义必要性层）

Representation Closure
  ES_representation(R)
  ——在具体 representation R 中，哪些语义关系需独立编码、
    哪些可由 Derivable(other relations, R) 推出
    （表示必要性层；irreducibility 是 (relation, representation)
     属性，非纯关系属性）
```

- M-1/M-2 的 necessity/substitutability 输出自此标注为
  **carrier-specific result**；
- 已有输出重标：I·A·C = necessity evidence（tested conditions）；
  P = semantic member retained，independent representational
  necessity carrier-dependent（llama full-prefix：P ∈ Derivable(A,
  R_llama)；MLX KV：P ∉ Derivable(A, R_MLX) [S1]）；
- 「minimal 已证」仍为非法措辞；两层全过才可谈 minimality evidence；
- 正式化（G-δR / closure-revision formalization gate）待 human 决定
  是否开启。
