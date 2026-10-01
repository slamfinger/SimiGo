# G-δR Formalization Gate — Design / Definitions / Formal Replay

日期：2026-10-02
状态：`FORMALIZATION GATE OPENED / DEFINITIONS FROZEN / REPLAY EXECUTED
(ANALYTICAL) / SUFFICIENCY DETERMINATION AWAITING HUMAN`
任务令：human 2026-10-02（先不开 G-δR 实验；进入很短的 formalization
gate；写 `G-δR Formalization Design / Gate`——明确是 formalization
gate，不是 minimality validation v2，避免滑回「增加实验保护
{I,P,A,C}」的老路径）
性质：纯形式化文档。零实验、零模型调用、零产品仓变更。

---

## 0. Gate 要回答的问题（human 原文）

> **"semantic closure" 和 "representation closure" 之间到底是什么
> 形式关系？**

四步：①冻结新定义 ②明确 representation invariant 允许什么
③对 G-δ 结果做 formal replay（不重跑 llama）④判定是否需要实验。

## 1. 定义（冻结）

### 1.1 语义层

```text
ES_semantic = { I, P, A, C }
```

语义关系 X 的**角色分解** Role(X)（X 为 continuation invariant 提供
的功能；本档完成 P 的完整分解，I/A/C 给出已证据覆盖的主功能）：

```text
Role(P) = { P-1 落点断言：续算从哪一计算进度接上,
            P-2 边界完整性：载体进度与所录状态失配可检测,
            P-3 进度记账：position 值本身 }
Role(I) = { I-1 载体绑定：哪个模型/哪个执行谱系,
            I-2 来源区分：不同计算状态的可分辨性 }
Role(A) = { A-1 内容绑定：N 处上下文内容-语义对应 }
Role(C) = { C-1 接续许可：未来输入的合法接续关系 }
```

### 1.2 表示层

一个 representation `R = (Σ_R, C_R, Inv_R, Rules_R)`：

```text
Σ_R    已注册的 record schema（字段集）
C_R    载体（物理字节/工件）
Inv_R  已注册的 representation invariant（任意良构 record 上
       恒成立的确定性事实）
Rules_R已注册的确定性推导规则（封闭集，实验前枚举冻结）
```

### 1.3 Derivable / Irreducible（函数补偿形式）

```text
Compensable_R(f) := 角色-功能 f 可由「剩余关系断言 + Inv_R +
                    Rules_R 中的注册规则」在 R 上确定性提供。

Derivable_R(X)    := X 的全部角色-功能 Compensable_R。
Irreducible_R(X)  := ¬Derivable_R(X)（至少一个角色-功能在 R 上
                     不可补偿）。

注意精确性：可推导的对象是「功能的可提供性」，不是断言值本身。
（Gδ-P 已实测：P-3 的值不可由剩余 record 字段推导——hash 无原像；
被补偿的是 P-2 边界完整性功能。两层读法在本定义下不再冲突。）
```

### 1.4 语义成员判据（本档形式核心，待 human 批准）

```text
X ∈ ES_semantic ⟺ X 至少提供一个角色-功能 f，使得存在某个已注册
                    representation R 有 ¬Compensable_R(f)，
                    且 f 为 continuation invariant 所需。
推论：某关系若其全部角色-功能在所有已注册 representation 上均可
补偿 ⇒ 降级候选（仍须经 closure revision gate，不得静默移除）。
```

此判据使 G-δ 的两向结果**逻辑相容**且给出一般规则——P 因 P-1/P-2
在 R_MLX 上不可补偿（S1）而保有语义成员资格。

## 2. Inv_R 允许/禁止边界（冻结；human 列表逐字）

**允许**：
- 已注册的 representation schema（Σ_R）；
- 已注册的 carrier semantics（载体是什么——如「tokenPrefix = 渲染
  会话的精确 token 序列」）；
- 已注册的确定性推导规则（Rules_R，封闭集）。

**不允许**：
- 偷看 carrier bytes（读取载体内容以**提取被移除断言的值**——如数
  token 数得 position）；
- 临时读取某个隐藏字段；
- 重新跑完整 transcript（H→R' = 放弃 State，M-2 冻结条款）；
- 为让某 relation 可推导而临时创造新规则。

**精确化（消解 Gδ-P 探针与 carrier 排除的表面张力）**：
「carrier 对已注册断言的比对」（如 H(carrier) vs record.anchorHash）
走 Rules_R 注册规则 = **允许**——这正是 Gδ-P 中 A 合法补偿 P-2 的
机制；被排除的是「从 carrier 提取值」。二者在 §1.3 的功能/值区分下
不再含糊。违反边界的后果：Derivable_R 退化为「足够努力总能从
carrier 找回」⇒ minimality 失去意义。

## 3. Formal Replay（G-δ + 在案证据 → 新定义；分析性，零实验）

| Relation | R_llama（full-prefix token 数组） | R_MLX（KV 载体） | 状态 |
|---|---|---|---|
| I | necessity（Gδ-I：I-2 来源区分不可补偿——匿名 record 无差别接受；I-1 model-binding 结构性无补偿；content-mismatch 子功能由 A 部分补偿=partial subsumption） | necessity evidence（结构层：model/lineage 绑定无剩余字段可表达） | 保留 |
| A | **Irreducible**（Gδ-A：same-I/P/C record 关系层全等 + 不同内容 ⇒ 不可分辨而续算分叉） | irreducible evidence（P5-4 PA-2：同计数异内容 ⇒ 语义分叉；E3 锚定检查族） | 保留 |
| C | **Irreducible**（Gδ-C：continuation-of-THIS-state 从 I/P/A 不可构造） | irreducible evidence（P7-1 C4 接续契约；INV-C 断言依赖） | 保留 |
| P | **P-2 Compensable** via A（Gδ-P：注册比对规则检出截断）；P-1/P-3 不可补偿（hash 无原像） | **P-2 不可补偿**（S1：processedTokenCount 31712 ≠ 可渲染数——A 的内容原像不覆盖 KV 进度） | **representation-dependent** |

**Replay 一致性判定：✅ 无逻辑冲突**——两向结果在两层定义下同时为
真；「独立性是 (relation, representation) 属性」由 P-2 的补偿不对称
性直接实例化。语义成员判据（§1.4）逐关系通过：P 经 R_MLX 的 P-1/P-2
不可补偿保有成员资格；I/A/C 各有跨表示不可补偿功能。

## 4. Gate 判定（步骤 ④）

### 形式化已解决的

- 两层定义 + 函数补偿形式使 G-δ 两向结果相容且可一般化（§1/§3）；
- 语义成员判据给出「P 保留」的形式依据（不再依赖直觉）；
- Inv_R 边界的精确化消解 carrier 检视张力（§2）；
- 「独立性是 (relation, representation) 属性」获得形式化表述。

### 形式化暴露的未决语义问题（如实枚举）

1. Role(X) 分解目前 P 完整、I/A/C 仅主功能——完整角色分类学是否
   需要冻结为附录（属形式化内部工作，非实验）；
2. 语义成员判据（§1.4）中的「continuation invariant 所需」谓词
   尚未操作化（哪些功能为 invariant 所需 = 需要一份 invariant
   功能清单）；
3. Rules_R 的封闭集目前仅 R_llama/R_MLX 各注册一条主规则——是否
   够用取决于未来 representation 注册（枚举义务已立）。

### 判定（供 human gate 裁定，本档倾向已注明）

```text
G-δR
├─ Formalization sufficient?
│    本档判定：形式化骨架已成立（定义自洽+replay 无冲突+成员判据
│    给出）；剩余三项均为形式化内部收尾（角色分类学附录/所需谓词
│    操作化/Rules_R 枚举），不需要模型实验即可完成。
│
└─ 未决问题 1-3 若被 human 判定为语义层缺口（而非形式化收尾）
     ⇒ 才设计最小必要实验
```

**本档倾向：Formalization sufficient —— 收尾三项在 G-δR 内以附录
形式完成，冻结当前结论，不设计新实验。** 最终判定归 human。

## 5. 禁止方向（human 列表逐字，冻结至 gate 出口）

再跑 llama necessity / 增加第三个 backend / 测试更多模型 / Qwen4Exp /
大规模性能 benchmark / UI branch sessions / 把 P7-1、G-δ 包装成
「理论已经成立」。

## 6. Non-claims

本档不产生实验结论；不改 G-δ 任何终态；「minimal」仍不可宣称；
两层定义的正式化不等于 universal/general ES theory（仍 ⛔）。

---

## 5. GATE RULING（human，2026-10-02）：FORMALIZATION_SUFFICIENT

四点理由登记：①Semantic layer 已定义（ES_semantic+Role 分解，relation
不再是不可分割单一字段）；②Representation layer 已定义（R=(Σ,Carrier,
Inv,Rules) ⇒ Compensable_R/Derivable_R/Irreducible_R 可正式表达）；
③G-δ 结果无矛盾重放（R_llama: P-2 ∈ Compensable_R(A) / R_MLX:
P-2 ∉ Compensable_R(A) = (relation,representation) 属性而非理论冲突）；
④无语义缺口需要新实验——剩余三项属形式化内部闭合工作。

**强制要求（human）**：「invariant 所需」不得成为事后任意谓词——
`Required_R(f)` 必须按反循环方向操作化：

```text
预注册 invariant（INV-XB，先在）
        ↓
允许的 representation rules（Rules_R，先在）
        ↓
移除某 role function f（G-δ relation-removal 操作化）
        ↓
invariant 能否由 Inv_R + Rules_R + remaining relations 保持？
        ↓
Required / Compensable / Irreducible
```

禁止方向：「P 很重要 ⇒ invariant 需要 P ⇒ P 是 semantic relation」
（循环论证）。

## 6. 收尾附录（三项，本节完成并冻结）

### 附录 A — Role taxonomy（完整版，冻结）

```text
Role(I) = { I-1 模型绑定：restore 拒绝异模型载荷,
            I-2 谱系绑定：不同计算状态可分辨,
            I-3 载荷完整性交叉核对：record↔carrier 失配检出
                〔llama 上被 A 部分补偿——partial subsumption〕 }
Role(P) = { P-1 落点断言：续算接续的计算进度点,
            P-2 边界完整性：载体进度失配可检测,
            P-3 进度记账：position 值 }
Role(A) = { A-1 内容绑定：N 处上下文内容-语义对应
            （同位置异内容状态的可分辨性） }
Role(C) = { C-1 接续许可：未来输入的合法接续关系
            （「continuation of THIS state」的可断言性） }
```

### 附录 B — Required_R 谓词（操作化 + 当前证据实例化）

```text
Required_R(f) := 移除 f 后，INV-XB 无法由 Inv_R + Rules_R +
                 remaining relation assertions 保持/断言。
```

评估机械 = G-δ leave-one-out 电池（同一机制，本附录将其形式化为
谓词）。当前实例化表（证据级标注）：

```text
R_MLX（KV 载体）：
  Required(P-1)=YES〔S1：KV 进度不在内容原像内，落点不可断言〕
  Required(P-2)=YES〔S1 同理：进度失配不可由 A 检出〕
  Required(A-1)=YES〔P5-4 PA-2 原跑〕
  Required(C-1)=YES〔INV-C 断言依赖；P7-1 C4 对照〕
  Required(I-1/I-2)=YES〔ES-R1 restore fail-closed 原跑〕
R_llama（full-prefix token 数组）：
  Required(P-2)=NO——Compensable via A（ρ_L1，Gδ-P 实测）
  Required(P-1)=NO——Compensable via carrier semantics + C
    （全拷贝退化：附加目标=载体结构末端；如实标注为
     full-copy 载体的退化情形）
  Required(P-3)=N/A（值提取被排除——记账功能在本载体无独立判据）
  Required(A-1)=YES（Gδ-A 实测）
  Required(C-1)=YES（Gδ-C 实测）
  Required(I-1/I-2)=YES（Gδ-I 实测：conflation+model-binding
    无补偿；I-3 部分补偿由 A，ρ_L1）
```

**语义成员判定（按 §1.4 判据机械应用）**：

```text
I ∈ ES_semantic（I-1/I-2 双表示 Required）
A ∈ ES_semantic（A-1 双表示 Required）
C ∈ ES_semantic（C-1 双表示 Required）
P ∈ ES_semantic（P-1/P-2 于 R_MLX Required）—
    且 P-2 于 R_llama Compensable（carrier-dependent irreducibility
    的形式化表述）
```

无任何关系满足「全功能×全表示可补偿」的降级条件 ⇒ **零降级**。

### 附录 C — Rules_R 枚举（封闭集，冻结）

```text
Rules_R_llama = {
  ρ_L1 anchor-integrity: anchorHash_R(record) = H(carrier.tokenPrefix)
         ——注册比对规则（Gδ-P 中补偿 P-2 者）,
  ρ_L2 prefix-extension: carrier + tokenize(Δ) = 延接载体
         （续算力学）,
  ρ_L3 server-identity: props.modelPath 绑定（M1 使用）,
  排除：从 carrier 计数/提取 position；重算 transcript }
Rules_R_MLX = {
  ρ_M1 anchorHex: anchorHex(record) = H(canonical transcript tail)
         ——内容级,
  ρ_M2 restore fail-closed: representation restore 须 meta+
         safetensors 配对（ES-R1 证据）,
  ρ_M3 no-bridge〔显式缺席规则〕: 不存在连接 transcript 可渲染
         计数与 KV processedTokenCount 的注册规则——正是 S1 建立
         的缺口，形式化为「缺席」使 P-1/P-2 于 R_MLX 不可补偿,
  排除：KV tensor 计数提值 }
```

## 7. FREEZE — G-δR CLOSED = FORMALIZATION_SUFFICIENT

```text
G-δ        CLOSED
Closure Revision  ACCEPTED
G-δR       FORMALIZATION_SUFFICIENT（附录 A/B/C 收尾完成，
           不进入 execution 分支）
Minimality 未证明——且已重定义为 representation-aware 问题
           （semantic closure × representation-specific
            irreducibility）
```

**理论结构（当前对 Execution State 的正式描述方式，冻结）**：

```text
                 Execution State
                       │
              ┌────────┴────────┐
              │                 │
        Semantic Closure   Representation R
        {I, P, A, C}       Inv_R / Rules_R
              │                 │
              └──────┬──────────┘
                     ↓
             role-level derivability
                     ↓
          Irreducibility is R-dependent
```

SimiGo 对 ES 的表述自此为：「**区分一个 Execution State 的 semantic
closure 与具体 representation 的 irreducibility**」，而非「寻找四个
最小字段」。

**下一道 Gate（不自动开）**：是否把两层模型提升为 SimiGo 正式的
**Execution State Contract**（contract formalization / abstraction
freeze）——属 contract formalization 方向，非 minimality 继续。

**冻结证据链**：P7-1 → bounded cross-backend support；G-δ →
necessity + carrier-dependent compensation；Closure Revision →
accepted；G-δR → formalization sufficient；Minimality → 未证明且
已 representation-aware 化。产品仓 0 commit；本档+Lab 基线 = 闭合
证据。
