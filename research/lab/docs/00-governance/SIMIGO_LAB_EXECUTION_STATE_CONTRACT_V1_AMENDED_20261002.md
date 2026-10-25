# Execution State Contract — v1.0-amended（Freeze Candidate）

日期：2026-10-02
版本：`v1.0-amended（freeze candidate）`
状态：`AMENDMENTS INCORPORATED（G-LC1 + N-1..N-6 全 ACCEPT）/
CONSISTENCY REVIEW PASS / AWAITING FINAL FREEZE DECLARATION（human）`
验收记录：human 2026-10-02「CONTRACT ACCEPTED — FORMALIZATION
SUFFICIENT」（draft 1.0 = 2c6df83）；修订裁定=G-LC1 ACCEPT（附
save 语义约束）+ N-1..N-6 全 ACCEPT（Abstraction Freeze Gate
0ee1b53）。证据基线：P7-1（98dbed7）/G-δ（659ebf8）/Closure
Revision（69a8866）/G-δR（3ecb22f）。

修订 incorporated 清单：G-LC1（save/checkpoint 入 lifecycle，附
「非 semantic closure mutation」约束）·create 补入·restore
fail-closed 子句·N-1 INV-XB 内联（§4）·N-2 invariant→rule 映射
义务（§3）·N-3 eviction 归 release 族（§5）·N-5 方向性声明（§9）·
N-6 版本钉定电池（§8）·N-4 两份正式 Representation Declaration
（附录 A/B）。

---

## 1. Scope（契约范围）

冻结四类：①Semantic relations（I/P/A/C，Role 分解见 §2）②Required
invariants（INV-XB，§4 内联）③Lifecycle obligations（七操作，§5）
④Representation boundary（声明面 Σ_R/C_R/Inv_R/Rules_R，§3）。

排除（不得写入契约）：数学最小宣称；具体 backend 字段布局实例；
ρ 规则的实现细节（规则本身属于表示声明内容）；backend-specific
本体判断；性能指标。

前驱关系：Architecture Contract v1.0（20260930）=前驱参照，冲突以
本契约（证据后置版）为准；P6 冻结概念边界=Semantic 层定义来源；
G-δR 两层定义=形式基础；PALACE 与 Security 轨道不在本契约内。

## 2. Semantic Contract（语义契约）

```text
Execution State 必须保持四条语义关系（Role 语义 = G-δR 附录 A）：
  I  Identity      I-1 模型绑定 / I-2 谱系绑定 / I-3 载荷完整性交叉核对
  P  Position      P-1 落点断言 / P-2 边界完整性 / P-3 进度记账
  A  Anchor        A-1 内容绑定（同位置异内容状态的可分辨性）
  C  Continuation  C-1 接续许可（continuation-of-THIS-state 可断言）
```

义务为**语义保持义务**，不指涉字段。成员资格修订机制=closure
revision gate（G-δR §1.4 判据）。

## 3. Representation Contract（表示契约）

任何 backend R 声称承载 Execution State，必须声明四元组并满足：

```text
Σ_R     record schema
C_R     carrier（载体语义：是什么、不是什么）
Inv_R   representation invariant（良构 record 恒立事实）
Rules_R 推导规则封闭集（含显式缺席规则；实验前枚举冻结）
```

**声明义务（N-2）**：每份声明必须附 **invariant→rule 映射表**——
明确「哪条规则判定哪条 invariant」；未注册判定规则的 invariant
视为该表示上须独立断言（Required）。

**不变式**：representation 可以变化，但不得改变 Semantic Contract
所要求的 continuation invariant。

## 4. Invariants（INV-XB 内联，N-1；起源参照 P7-0 §4）

```text
INV-I  restore 后 identity 可断言且与 checkpoint 一致；
       模型/谱系绑定可核验。
INV-P  restore 后落点与所录计算进度一致；进度失配可检测
       （检测机制 representation-dependent，由 Rules_R 声明）。
INV-A  内容-语义对应可核验（锚定可比较且 functional）。
INV-C  未来输出可断言为 THIS state 的延续
       （continuation provenance 可构造）。
```

## 5. Lifecycle obligations（七操作；G-LC1 修订版）

| 操作 | 语义义务 |
|---|---|
| **create** | 新 Execution State 以明确 identity 绑定与初始 position 开始；create 不预设 carrier |
| **fork** | 分叉点两侧 closure 完整保持：anchor(child@fork) == anchor(parent@fork)；parent 非污染 |
| **continue** | 严格前缀延接语义；延续 provenance 可断言（区别于同文本新计算） |
| **save/checkpoint** | **【G-LC1，附 human 约束】**commit 时点状态的 closure 可记录部分（I/P/A/C recordable 断言 + carrier）durable 持久化；save 后 record 满足 INV-XB 的 restore 前提；save 原子性（无部分状态）；形成溯源可记录。**约束：save 是 representation/lifecycle transition，不是 semantic closure mutation——save 不产生新的语义关系，只把当前 closure 固化为 durable representation** |
| **restore** | I/P/A 可再断言、C 可再接续；**fail-closed 子句：无法重新建立契约所要求 relations/invariants 时，必须 fail-closed，不得返回表面成功但无法证明 continuation validity 的半状态**（ES-R1 证据） |
| **discard** | 废止后无 ghost continuation；discard 原子性（逻辑废止与物理释放顺序义务） |
| **release** | 绑定清空、无跨状态残留、失败可恢复可重试；**eviction = release 族（系统发起的 release，义务同表）**——资源压力机制不得成为契约外生命周期路径 |

## 6. Representation-dependent derivability（G-δR 产出条款）

**P 条款（显式非要求项）**：

```text
Semantic Contract 要求：P 的语义必须被正确保持
  （落点可断言、进度失配可检测、记账可用）。
Contract 不要求：P 在每种 representation 中作为独立字段存在。
Representation 层：P may be explicit OR derivable
  ——可 derivable 的前提=推导规则已注册于该声明的 Rules_R；
  ——未注册规则而实际依赖推导 ⇒ 违反表示声明义务。
```

**一般化条款**：上述模式适用于全部四关系——任一关系 X 在表示 R 中
可显式或可推导，条件：(a) 规则注册于 Rules_R；(b) 声明附 Required_R
评估（哪些功能 Required/Compensated，附证据级）；(c) carrier 检视
与全量重算排除（G-δR §2）。necessity evidence 的表示范围随声明
登记。

## 7. Non-claims（非主张清单，原样保持）

- 不主张 {I,P,A,C} 数学最小（未证明，已 representation-aware 化）；
- 不主张 backend-independent（bounded claim 边界保持）；
- 不主张 universal/general Execution State theory；
- 不定义 ES「形而上是什么」（D7 继承）；
- 不含性能主张；
- 实验依据限定于已登记证据链；「未复制」标注义务随引用传递。

## 8. Compatibility & versioning（N-6 显式化）

- ES Contract 版本独立演进（本稿=v1.0-amended freeze candidate）；
  Representation Declaration 独立版本化。
- Semantic Contract 变更 = closure-revision 级事件（human gate+证据）。
- Representation Declaration 变更 = 重新声明 + **版本钉定合格性
  电池重跑**——**semantic compatibility 的判定 = 版本钉定的
  conformance battery（声明 conforms to contract version V iff 其
  V 版电池通过），不靠字段相似性判断**。
- 新 backend/新模型格式 = 新 Representation Declaration，零
  Semantic Contract 变更。

## 9. Directionality declaration（N-5）

> INV-XB 为**行为要求**（对 record 的约束）；四关系为**手段**；
> Required_R/Compensable_R 评估**单向**（invariant → relations →
> Role functions）。本契约不含循环定义：invariant 预设 record 存在
> 并约束其行为，不预设任何关系被独立编码。

## 10. Acceptance record

- draft 1.0：CONTRACT ACCEPTED — FORMALIZATION SUFFICIENT
  （human，2026-10-02，五项批准要点见 Gate 文档 §10）。
- 修订：G-LC1 ACCEPT（附 save 非 mutation 约束）+ N-1..N-6 全
  ACCEPT（无返工实验、无新增实验）。
- 本 v1.0-amended = **freeze candidate**；final freeze declaration
  归 human（一致性复核记录见 Abstraction Freeze Gate 文档修订节）。

## 附录 A — Representation Declaration: R_llama

```text
Σ_R  CheckpointV2 record schema：
     {schemaVersion, executionID, position, continuationNextInput,
      continuationID, tokenPrefix, anchorHash,
      modelIdentity{modelPath, modelHash}}
C_R  token-prefix 数组（渲染会话的精确 token 序列；record 内自含）
Inv_R 良构 record 上：anchorHash = H(tokenPrefix 逗号连接) 恒立；
     model identity 可对照运行时 server 实载
Rules_R（封闭集，G-δR 附录 C）：
  ρ_L1 anchor-integrity / ρ_L2 prefix-extension / ρ_L3 server-identity
invariant→rule 映射（N-2）：
  INV-I ← ρ_L3 + record.modelIdentity 核验
  INV-P ← ρ_L2（落点=载体末端）+ ρ_L1（边界完整性）
          〔P-3 值提取被排除——记账功能无独立判据，如实登记〕
  INV-A ← ρ_L1
  INV-C ← ρ_L2 + continuation 绑定字段
合格性电池参照：P7-1（CONTINUATION_VALIDATED_CROSSBACKEND）、
  G-δ（FULL baseline + 各 cell）
```

## 附录 B — Representation Declaration: R_MLX

```text
Σ_R  SessionCache 记录 schema：meta.json（history/modelId/storageKey/
     checkpointGeneration/cacheSHA256…）+ KV safetensors（融合工件）
C_R  KV tensors（per-token 压缩计算状态：attention KV ∝ position +
     GDN 固定分量）+ transcript meta
Inv_R meta+safetensors 配对完整性（fail-closed restore，ES-R1）；
     checkpointGeneration/cacheSHA256 一致性；
     anchorHex = H(canonical transcript tail)
Rules_R（封闭集，G-δR 附录 C）：
  ρ_M1 anchorHex / ρ_M2 restore fail-closed /
  ρ_M3 no-bridge（显式缺席：不存在连接可渲染计数与 KV
  processedTokenCount 的注册规则——S1）
invariant→rule 映射（N-2）：
  INV-I ← ρ_M2 + modelId 绑定
  INV-P ← 独立 position 断言 Required（P-1/P-2 于本表示无推导规则
          可用——ρ_M3；G-δ P cell=COMPENSATED 仅成立于 full-prefix
          锚表示，此处不适用）
  INV-A ← ρ_M1
  INV-C ← continuation 绑定（meta/ledger）
合格性电池参照：P4/P5-1/P7-1-MLX/G-δ MLX 侧电池
```
