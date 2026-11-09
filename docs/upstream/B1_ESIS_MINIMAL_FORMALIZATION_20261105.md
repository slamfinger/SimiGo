# B1 · ES/IS 最小形式化（关系骨架 · 状态转换 · 恢复时约束）

**Status**: B1 **ACCEPTED**（2026-11-05 定案：六项定向复核 PASS；`Settled(ρ)` 脚注按**解释性定案**处理——Settled = 结算事件已发生的历史事实，不蕴含记录永久存续或当前可恢复；记录保留是实现的历史保留方式，不是 Settled 的语义定义；Recoverable 仍须逐次经 Admission 判断。按裁定不为此修改正文）。不再扩写本文件；三项 OPEN 保留，不因通过而宣称已解决。通过仅代表本稿在约定范围内语义自洽，不代表完整形式系统已证明。未修改任何冻结契约、`OPEN_SOURCE.md`、路线 A 文件、历史实验记录；**不包含任何 ES 代码改动**；未提交、未推送、未公开。
**Date**: 2026-11-05
**上游**: `docs/upstream/DEEPSEEK_ES_IS_SEMANTIC_ROUTE_20261105.md`（§7 B1，已授权）；术语基础：`docs/upstream/B0_ESIS_GLOSSARY_20261105.md`（B0 ACCEPTED，含 2026-11-05 裁定修订）
**性质声明**: 本文件是**关系骨架**，不是已证明的完整形式系统。每个形式元素标注语义地位与证据状态；骨架可被证据推翻回改，回改不改契约。

---

## 0. 范围与方法

- **最小形式化** = 精确到可实现、可检验；不做定理化，不引入证明义务。
- 语义地位标注：【定义】术语域内规定；【规则】骨架内有效的关系/约束；【骨架】待证据深化或推翻的结构假设。
- 证据状态沿用 B0 纪律：已验证 / 推导结论（附推导依据）/ 假设 / OPEN。
- 五项工作边界（授权）：① ES、IS、Settlement、Settled Result、Continuation、Branch 的最小关系；② ES 结算结果进入 IS、后续 ES 从 IS 恢复的状态转换；③ 恢复时依赖闭包与有效性依据约束；④ KV Cache 定位为可选 Carrier，不纳入语义成立必要条件；⑤ Branch identity 与可靠结算边界显式 OPEN，不用假设填空。

---

## 1. 裁定输入（B0 → B1，2026-11-05）

B0 ACCEPTED。以下裁定已编入本骨架，不再作为待办：

**① 命名**：ES = Execution State，IS = Information Space（信息空间）。不再使用 Information State，不保留双重解释。ES 与 IS 是**职责不同、能够形成续接闭环的两个组成部分，不是可互换的状态容器**。

**② OQ-2 RESOLVED** — semantic ownership established; implementation mapping evidenced：

| 对象 | 归属 | 含义 |
|---|---|---|
| Settlement Act | ES | 执行结算决策及状态转换，拥有结算行为的权威 |
| Settled Result | IS | 已结算、可供后续续接使用的信息 |
| Settlement Record | IS | 记录结果的来源、依赖、版本及有效性依据 |
| Settlement Outcome | ES → IS | ES 执行结算后产生、并由 IS 接收和保存的结果 |

限制（编入 R1/R2 的语义地位）：IS 保存结算结果**不代表 IS 决定某项执行是否已完成**；ES 拥有结算行为权威**不代表 ES 必须永久保留已结算的全部结果或旧 KV Cache**。`settleValidatedResult` 等实现位置是佐证，不是契约定义本身。

**③ OQ-3 拆分**：两项 RESOLVED（Branch 不以 KV Copy 为定义条件；现实现 fork ∈ storageKey 操作层）+ 一项 OPEN（Semantic Branch ↔ Execution Lineage 正式身份关系、generation 生命周期语义）。层级区分表见 R5。

**④ OQ-1 处理原则**：可靠结算不是一次性认证标签，而是**有条件的可恢复资格**——恢复/续接时逐项重判；七步 admission 检查单是现有实现依据，B1 不将其提升为完整、普遍适用的定义。

**⑤ OPEN 收敛纪律**：只保留三个 OPEN（OQ-1、OQ-3、OQ-8）；OQ-2 与命名歧义关闭；OQ-4/OQ-9 并入本文件工作项③与 R3；OQ-6/OQ-7 暂缓，不在骨架中引用。

---

## 2. 实体与记号

【定义】以下记号在骨架域内使用，均收敛自 B0 术语表：

| 记号 | 实体 | 定义 | 归属（裁定②） |
|---|---|---|---|
| `es` / `ES` | 执行状态 | 执行续接权威：进展锚（anchor）、分支关系（branchRel）、结算行为权威 | ES 域 |
| `ES_n` | 续接链上第 n 个执行状态 | 恢复**铸造新 ES**（ES_{n+1}），不复活旧 ES | ES 域 |
| `IS` | 信息空间 | 已结算信息及其可恢复性、来源、版本、依赖和有效性依据构成的权威状态 | IS 域 |
| `r` | Settled Result | 已结算结果本体 | IS |
| `ρ` | Settlement Record | 结算事实与依据的记录（含身份绑定） | IS |
| `σ` | Settlement Act | 结算行为 | ES |
| `(r, ρ)` | Settlement Outcome | σ 的产出，由 IS 接收保存 | ES → IS |
| `D(ρ)` | Dependency Closure | ρ 的上游依赖传递闭包 | IS 内 |
| `V(ρ)` | Validity Basis | ρ 的有效性依据集合 | IS 内 |
| `A` | Admission | 恢复准入判定 | IS → ES 的守卫 |
| `Settled(ρ)` | 历史结算事实谓词 | ρ 具有有效的历史结算事实（不随 t 变化） | IS 内 |
| `Recoverable(ρ, ctx, t)` | 当前恢复资格谓词 | 在 ctx 与恢复时点 t 通过准入（R6） | IS → ES 守卫结果 |
| `t` | 恢复时点 | **所有有效性谓词按 t 索引** | — |
| `C` | Carrier 域 | KV / sequence / slot / 文件 / 数据库 / 对象存储 | 可选 |

**域分离**【定义】：ES 与 IS 是两个权威域，职责不同、非可互换容器（裁定①）；其协同仅通过 §3 的两条边（σ 产出入 IS；A 守卫出 IS）发生。

---

## 3. 关系骨架

【骨架】核心关系（授权指定的展开）：

```
                σ（Settlement Act · ES 权威 · fail-closed · 部分性）
        ES_n ────────────────▶ Settlement Outcome (r, ρ)
                                     │ put（IS 接收并保存；IS 不判定完成）
                                     ▼
                          IS : (r, ρ, D(ρ), V(ρ))
                                     │ A（Admission · 恢复时点 t · fail-closed）
                     Admit(β) ───────┤
                                     ▼
        ES_{n+1} ◀────── 以 β（已验证绑定）为新锚铸造
        Refuse(γ) ─────▶ 按 γ 分类处置（仅依赖类进入 R3 选择性重执行；
                          其余类型见 R3 分表，不一律导向重执行）
```

一行式：**ES_n ──Settlement──▶ IS ──Admission──▶ ES_{n+1}**

**箭头类型**：

- `σ : ES × Evidence ⇀ Outcome` — **部分函数**：前置门不通过则无任何写入（fail-closed）。
- `put : IS × Outcome → IS′` — IS′ 为保存 Outcome 后的信息空间状态（IS 持续存在，put 不单独生成 IS）；put 全函数但**被动**：IS 只接收保存，不判定执行是否完成（裁定②限制，不变）。
- `A : IS × ρ × Ctx × Time → AdmissionOutcome`，其中 `AdmissionOutcome ::= Admit(β) | Refuse(γ)` — fail-closed；γ 为 typed reason，两类拒绝永不互扮。调用入口提供的 `esStateID` 是**引用标识**：Admission 用它解析对应的 IS 记录，不是语义输入本身（避免把 API 参数误当语义实体）。

**闭环备注（已验证）**：代码中该闭环真实存在——续接结算返回的 `childESStateID` "is returned to the client so the **NEXT continuation admits through it**"（`SimiGo/Protocol/ContinuationSettlement.swift:105-106`）。

**ES 身份区分（修订 2026-11-05）**：以下三个对象在当前实现中可能由同一 ID 关联，语义上**不得未经证明地等同**：

1. Settlement 产生的 child ES **引用 / 续接锚点**（供下一次续接准入使用）；
2. IS 中可供恢复的 settled result 与 bindings；
3. Admission 成功后创建的**新 ES 执行实例**。

骨架表述：**Settlement 可以产生供下一次续接使用的 ES 引用；Admission 成功后，消费经过验证的结果与绑定，创建新的 ES 执行实例。**旧 ES 生命周期结束后仍可续接，正是通过 1 → 2 → 3 的链条表达，而非三者同一。

**关键推论**【骨架】：**ES_{n+1} 的存在不要求 ES_n 或其载体（KV / slot / 进程）仍然存活**。这是"执行生命周期结束后的续接"的形式表达：admission 产出的是 recovered value + verified bindings "for a **fresh ES**"（`ISAdmission.swift:90-91`）。证据状态：由实现推导（恢复铸造新 ES 的路径已验证；跨引擎未验证——不因此宣称普适）。

---

## 4. 骨架规则 R1–R6

### R1 · 结算进入规则【规则】

```
pre(σ, es)  : begun(es) ∧ modelConsistent(es) ∧ ¬settled(es) ∧ sealed(声明依赖)
post(σ)     : 每状态恰好一次结算；产出 Outcome(r, ρ)；put 入 IS（IS × Outcome → IS′）；
              产生 child ES 引用 / 续接锚点（供下一次续接准入；区别于
              Admission 后创建的新 ES 实例，见 §3 ES 身份区分）
es_fail     : 仅落审计，不产生结算，es 保持未结算
```

- 语义地位：规则（骨架内有效；形式化的是现行契约行为，不是新发明）。
- 实现对应（已验证）：前置条件族 `AGENT-ACCESS.md:229-240`；fail-closed 先于任何写入 `SettlementAuthority.swift:5-12`；es_fail 仅审计 `:227`；结算键 `(session_id, request_id, source_kind)` 而非「最近一行」（IS 契约:119）。结算键的一般化（脱离 session/request 特化）是 R1 的参数化方向，随 OQ-8 归拢处理。

### R2 · 恢复准入规则【规则】

```
A(IS, ρ, ctx, t) = Admit(β) ⟺ 以下四项在恢复时点 t 全部成立：
  (i)   record-trustable(ρ)     结算记录存在且可信（receipt + payload digest 完整）
  (ii)  complete(r)             结果完整（现实现取 wire 判据为佐证；一般化判据暂缓）
  (iii) closure-ok(D(ρ), t)     ∀ d ∈ D(ρ): present(d, t) ∧ valid(d, t)
  (iv)  basis-holds(V(ρ), t)    来源、版本、身份绑定仍然成立，无失效事件
否则 Refuse(γ)，γ 为 typed reason；绝不静默降级为普通生成
```

- **时间索引即第五项检查**：裁定 OQ-1 列出的"是否发生使结果失效的变化"不是独立第六步，而是 (iii)/(iv) 按 t 求值的本意——谓词在恢复时点重算，历史成立不外推。
- 实现对应（已验证）：`ISAdmission.swift:92-99` 七步 fail-closed 检查单是 (i)–(iv) 的现行实现细化。
- **裁定红线**：检查单是实现佐证，**不是**完整、普遍适用的可靠结算定义（OQ-1 显式保留）。

### R3 · 选择性重执行规则【规则 + 骨架操作】

**触发边界（修订 2026-11-05）**：`Refuse(γ)` ≠ 重执行命令。Admission 的拒绝是**准入结论，不是执行命令**；是否允许重执行、由谁发起、是否需要新的 ES，由 ES 的执行策略决定。R3 仅当 γ 被判定为**可通过依赖修复的类型**时才进入范围计算。

拒绝原因分表：

| γ 类型 | 后续处理 |
|---|---|
| 依赖缺失、依赖失效 | 可计算选择性重执行范围（R3） |
| 结果不完整 | 重新取得或生成满足完整性要求的结果 |
| 载荷损坏、摘要不匹配 | 拒绝使用损坏记录，重新取得可信结果 |
| 权限不足 | 终止拒绝，不得自动重执行 |
| 来源无法验证 | fail-closed，不得把重执行冒充为来源验证 |

重执行范围（两个方向不可混用，修订 2026-11-05）：

```
依赖方向       D(ρ) 给出 ρ 依赖哪些上游输入
失效传播方向   某上游输入失效后，哪些下游结果受影响

例：A → B → C（B 依赖 A，C 依赖 B）：A 失效时不能只重执行 A 后
    直接复用旧 B、C——B、C 可能需要重算。

范围计算分三步：
  (1) 缺失或失效的依赖集合
        M(ρ, t) = { d ∈ D(ρ) : ¬present(d, t) ∨ ¬valid(d, t) }
  (2) M 中输入所影响的下游结果集合（沿依赖图下行）
        Affected(M) = { x : x 依赖 M 中任一输入 }
  (3) 为恢复 Affected 结果所需的上游依赖集合（沿依赖图上行）

  reexec(ρ, t) = cl_graph(M(ρ, t))     【骨架操作：cl_graph 尚待精确定义】
```

- 边界（裁定原文）：重执行范围**不是**简单地等于所有无效依赖，而是依赖图上**恢复目标所需的受影响闭包**；已结算且有效、不在该闭包上的工作保持复用，不重跑。即授权原文："不满足条件时，只重执行缺失或失效的依赖闭包，而不是无条件重跑全部已完成工作。"
- 重执行产出经 σ 重新结算并重入 IS（骨架闭环闭合）。
- 实现对应：失效传播 `invalidateSourceFile` → 闭包传播、无关结算保持 valid（`ESISDatabase.swift:4943-4982`，"Unrelated settlements keep validity='valid'"）；复用四条件不满足即"走正常生成，不做「尽力而为」的近似回答"（`AGENT-ACCESS.md:102-109`）；policy 门控 `RecomputePolicy`（`never` 默认，输入不匹配锚定证据即拒绝、不静默重生成，`ManagedContinuation.swift:3-10,234-245`）。
- 语义地位：三步范围计算与 `cl_graph` 是本文件给出的**骨架操作**，不是完整的最小重执行算法；算法化（性能与正确性权衡）随 OQ-8 归拢与后续证据深化。

### R4 · 载体可选规则【规则】

```
CarrierOptionality : R1、R2、R3 的陈述不引用任何 capability(c)，c ∈ C
KV Cache ∈ C：可选载体——其存在加速实现，其缺失不使语义不成立
KV 复用权威在 IS 记录，不在引擎自身状态：
  admission outcome 的 kvBindings 为空 ⇒ "the continuation has no authority
  to reuse KV state"（ContinuationAdmission.swift:17-20）
```

- 实现对应（已验证）：载体不 reinterpret 字节（`ESISDatabase.swift:853-855`）；KV 绑定权威引文如上。
- 两层独立性（B0 §1.3 编入）：语义层独立性 = 设计原则（本规则即其形式化）；实现层可迁移性 = 实验命题，逐载体验证，本骨架不作宣称。

### R5 · 分支关系规则【规则 + OPEN】

```
branchRel ⊆ ES × ES：ES 域上的语义分支关系

层级区分（裁定③）：
| 层级              | 定义边界                                   |
|-------------------|--------------------------------------------|
| Semantic Branch   | ES 中具有独立续接意义的执行分支             |
| Execution Lineage | 执行之间的来源、派生关系                    |
| Storage Key       | 当前实现用于定位或区分存储对象的标识        |
| KV Copy           | 可选的载体层操作，不构成 Branch 的语义定义  |

RESOLVED: Branch 的定义不以 KV Copy 为条件
RESOLVED: 现实现 fork ∈ storageKey 操作层
OPEN(OQ-3): Semantic Branch ↔ Execution Lineage 的正式身份关系；
            generation 的生命周期语义由 ES lifecycle 决定，
            不得由 LOCALB 的存在性检查替代（LOCALB 审计 W1，用户引述）
```

- 实现对应（已验证）：`BranchForkEvent` 是 "storageKey 级分支寻址……**不是** execution→execution lineage（当前 fork 不产生执行级父子）"（`ExecutionLineage.swift:28-31`，外审语义钉死）。
- **推论跳跃防范（裁定原文）**：`ExecutionLineage.swift:28-31` 只证明当前实现的 fork 属于 storageKey 层，**不能**证明所有语义分支等于 storageKey，也不能证明未来 ES 的 branch identity 必须采用 storageKey。骨架因此把 branchRel 声明为 ES 域关系，其实现映射显式 OPEN。

### R6 · 可靠结算规则【规则 + OPEN】

历史结算事实与当前恢复资格是**两个谓词**（修订 2026-11-05）：

```
Settled(ρ)              : ρ 具有有效的历史结算事实——过去发生的结算，
                          不因后续变化而抹除（不随 t 变化）
Recoverable(ρ, ctx, t)  :⇔ A(IS, ρ, ctx, t) = Admit(β)
                          该结果在当前上下文与恢复时点通过准入
```

- **分离的含义**：`Settled` 描述过去事实，`Recoverable` 描述当前资格；**历史结算事实不等于当前恢复资格**。例：结果在 t₁ 可靠结算；t₂ 上游依赖变化——结算记录仍真实存在（Settled(ρ) 仍真），但 Recoverable(ρ, ctx, t₂) 为假，不允许直接恢复。
- **时间索引 ⇒ 逐次重判**（裁定④不变）：Recoverable 必须在每次恢复/续接时重判；任何必要条件在 t 不成立，不能仅凭"历史上曾经结算过"复用。
- 必要条件集 = R2 (i)–(iv)（Recoverable 侧）；七步检查单为实现佐证。
- OPEN（OQ-1 不变）：`Settled` 本身的充分必要条件与 Recoverable 规则的完备化；本骨架明确**不**把检查单提升为完整、普遍适用的定义。

---

## 5. 状态转换系统

### ES 侧【规则；实现佐证已验证】

| 转换 | 前置 | 后置 / 约束 |
|---|---|---|
| begin | — | es 进入 begun；其 state_id 可被结算引用（未 begin 不能结算，`AGENT-ACCESS.md:231`） |
| settle（σ） | begun ∧ model 一致 ∧ 未结算 ∧ 依赖封存 | 恰好一次结算；Outcome 经 put 入 IS（IS′）；产生 child es 引用 / 续接锚点（换模型必须新开 state，`:232`） |
| fail | — | 仅审计；无结算；es 保持未结算（`:227`） |
| cancel / 中断 | — | 不产生结算；取消链语义由测试族佐证（`CancelChainInternalTests` 等） |

### IS 侧【规则；契约明文】

| 状态 | 含义 | 资格 |
|---|---|---|
| recorded | 文本与来源已落库 | 任何检索都不选中 |
| committed（= 已结算·已验证） | 回答判定完整 + `verified_at` | 可被准入引用的基础 |
| retrievable | committed 之上通过消费方范围/来源/依赖检查 | 可进入检索 |
| invalid | 来源变更 → 沿依赖闭包传播 | 无关结算保持 valid |

- **C1（约束）**：入库 ≠ 结算 ≠ 可检索——三态分离是契约明文（IS 契约 §1，污染事故根因固化为契约）。
- **C2（约束）**：结算键是 `(session_id, request_id, source_kind)`，不是「最近一行」（IS 契约:119）——在途文本不因"已在数据库里"成为并发请求的已结算知识。

### Continuation 转换【规则；实现佐证已验证】

```
请求显式携带 previous_es_state_id ?
  否 → dispatch 路径 byte-for-byte 不变（opt-in 门，ContinuationAdmission.swift:56-59）
  是 → 以 esStateID 为入口引用调用 A(IS, ρ, ctx, t)——esStateID 仅用于解析对应
       IS 记录，不是语义输入（见 §3 箭头类型）
        ├─ Admit(β) → 创建新 ES 执行实例（消费 β 中经验证的结果与绑定）→ 生成
        │             → σ 结算产出 child ES 引用，供下一次续接准入（无伪造结果通道；
        │             结算门"never re-derives them from mutable execution state"，:9-12）
        └─ Refuse(γ) → typed 终端（422 / 503 / 500 分明，两类拒绝永不互扮，
                      ContinuationSettlement.swift:4-23）；按 γ 类型处置（R3 分表），
                      不一律导向重执行
```

---

## 6. 恢复时约束（授权工作项③）

对任何以 `(r, ρ)` 为锚的 ES_{n+1}，以下约束在恢复时点 t 求值【规则】：

```
C-dep  : ∀ d ∈ D(ρ): present(d, t) ∧ valid(d, t)          依赖闭包逐项满足
C-val  : holds(V(ρ), t)                                    身份（model/tokenizer）一致、
                                                           来源未失效、显式失效制（无 TTL）
C-int  : intact(payload digest)                            载荷完整可信
C-comp : complete(r)                                       结果完整（wire 判据为佐证；
                                                           一般化判据暂缓，不用于强宣称）
```

- 违反任一 ⇒ Refuse(γ)；仅当 γ 属依赖类（依赖缺失 / 失效）时才计算重执行范围 `reexec(ρ, t)`（R3，`cl_graph` 为骨架操作）；已结算且有效、不在受影响闭包上的工作不重跑。
- 无 TTL 是**已验证缺省**（仓库无 TTL/expiry 概念；失效为显式判定+闭包传播），不排除未来依据扩展——扩展属 V(ρ) 内容演化，随 OQ-8 归拢。

---

## 7. 载体定位（授权工作项④）

- **KV Cache 是可选 Carrier**（R4）：R1/R2/R3 的陈述不引用任何载体能力；KV 的存在改变性能与实现层可迁移性，不改变语义成立性。
- 无原生 fork / 无 in-memory snapshot 的引擎上，§3 骨架仍然成立——这正是路线 B 的前提（ES/IS 语义不预设 llama.cpp 式 fork 原语）。
- 载体能力差异的正规出口只有两个：性能特征、实现层可迁移性（实验命题，逐载体验证）。
- 骨架声明：**语义层不出现 KV 字样**——KV 只在实现映射与载体验证层出现。

---

## 8. 实现映射与证据状态总表

| 骨架元素 | 实现对应（证据） | 证据状态 |
|---|---|---|
| σ 部分性 / fail-closed | `SettlementAuthority.swift:5-12`（引文核验） | 已验证 |
| 恰好一次结算 / 前置条件族 | `AGENT-ACCESS.md:229-240`；`CrossPathSettlementIdentityHTTPTests` | 已验证（契约+测试层） |
| put 被动（IS 不判定完成） | IS 契约 §1 三态分离 + C1 | 已验证（契约明文） |
| A 七步 ↔ R2 四条件 | `ISAdmission.swift:92-99`（引文核验） | 已验证；**提升为普遍定义 = OPEN(OQ-1)** |
| child ES 闭环 | `ContinuationSettlement.swift:105-106`（引文核验） | 已验证 |
| child ES 引用 ≠ 新 ES 实例（§3 区分） | 实现中同一 ID 关联（同上）；语义等同性未证明 | 已验证（ID 关联）；等同性不作宣称 |
| ES_{n+1} 不要求 ES_n 载体存活 | admit "for a fresh ES"（`ISAdmission.swift:90-91`）+ 恢复路径测试 | 推导结论（单引擎内已验证；跨引擎未验证） |
| R3 失效闭包传播 | `ESISDatabase.swift:4943-4982`；`AGENT-ACCESS.md:102-109` | 已验证（机制）；`cl_graph` 范围计算 = 骨架操作（待精确定义） |
| R4 KV 绑定权威在 IS | `ContinuationAdmission.swift:17-20`（引文核验） | 已验证 |
| R5 storageKey 钉死 | `ExecutionLineage.swift:28-31`（引文核验） | 已验证 |
| R5 Branch ↔ Lineage 身份关系 | — | OPEN（OQ-3） |
| 时间索引有效性（无 TTL） | `settlements.validity` + `invalidateSourceFile` 传播 | 已验证（缺省）；依据集扩展随 OQ-8 |
| 跨载体结算恒等 | — | 暂缓（实验证据阶段，不作 OPEN 追踪） |

---

## 9. 显式 OPEN（B1 不填空）

| # | 问题 | B1 的处理 |
|---|---|---|
| OQ-1 | `Settled` 本身的充分必要条件；Recoverable 重判规则的完备化 | R6 拆分 Settled / Recoverable 两谓词；Settled 条件不填满；检查单不提升为定义 |
| OQ-3 | Semantic Branch ↔ Execution Lineage 正式身份关系；generation 生命周期语义（ES lifecycle 决定，不由 LOCALB 存在性检查替代） | R5 声明 branchRel 为 ES 域关系，实现映射显式留空 |
| OQ-8 | IS 语义总定义归拢（命名已定；现行语义散布于多份契约） | 本骨架的 IS 记号只绑定契约明文部分；归拢为 B1 后续工作 |

不在骨架中引用的暂缓项：语义充分性一般化判据（占位纪律不变）、跨载体结算恒等（留待实验证据阶段）。

---

## 10. 非目标

- 不是完整形式系统：无定理、无证明义务；骨架元素可被证据推翻回改（回改不改契约）。
- 不在本 B1 中实施任何 ES 代码改动（授权边界）。
- 不修改冻结契约、`OPEN_SOURCE.md`、路线 A 文件、历史实验记录；不提交、不推送、不公开。
- 不宣称跨模型、跨引擎、跨载体普适（`OPEN_SOURCE.md` 证据边界；OQ-7 暂缓）。
