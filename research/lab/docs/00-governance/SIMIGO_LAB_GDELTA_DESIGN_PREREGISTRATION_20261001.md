# G-δ Minimality Validation — Design / Pre-registration

日期：2026-10-01
状态：`DESIGN FROZEN / PRE-REGISTERED / EXECUTION AWAITING SEPARATE
HUMAN AUTHORIZATION`
任务令：human 2026-10-01（P7-1 终验收=有效的阳性 bounded cross-backend
validation；停止堆 P7-1 类实验；建立 G-δ Minimality Validation；先
写 Design / Pre-registration，不马上跑）
判据上游：SIMIGO_LAB_IPAC_MINIMALITY_CRITERIA_20261001.md（M-1/M-2/M-3
已冻结，056e283）+ human 本轮指令（leave-one-out 矩阵/relation≠field/
两层设计/失败=重大结果/措辞克制）

---

## 0. 目标措辞（冻结；human 原文）

> **验证 candidate relation closure 中各关系的必要性，并检查是否
> 存在可移除关系或由其他关系替代的关系。**

核心一问：**如果拿掉 I、P、A、C 中的任意一个，Execution State 的
continuation invariant 是否仍然能够成立？**

明确不做：不证明「数学意义上的绝对最小性」；不宣称 backend-
independent；G-δ 的目标是**让实验决定 I/P/A/C 是不是正确的抽象**
（若某关系被补偿 ⇒ closure 须修正 = 重大有效结果）。

## 1. 核心纪律（冻结；human 原文逐字）

> **G-δ 不能用实现字段删除来证明理论关系不存在/存在。**「我把
> anchorHash 属性删了，测试失败，所以 A 是必要的」不成立——A 可能
> 只是换了一种方式表达。G-δ 研究的是 **relation removal**，不是
> **field removal**。

操作化定义（本设计对 relation removal 的精确化）：

```text
relation removal = 从 state record 中移除该关系的权威断言/绑定
                   （assertion/binding），物理载体（carrier）保留
derivability space = 仅剩余关系的 record 字段
   排除 A：carrier 字节检查（载体自含一切 ⇒ 全关系「可推导」的
           退化情形——那是载体检视，不是关系推导）
   排除 B：从 transcript/全量重算（=放弃 State，M-2 冻结条款）
subsumption 合法输出 = 某关系被剩余关系补偿 ⇒ 登记 subsumption
   关系 + 触发 Layer 2 + closure 修正门
```

## 2. 实验矩阵（第一版，不过大）

| Cell | Closure | 核心问题 | 移除操作化 |
|---|---|---|---|
| Gδ-FULL | {I,P,A,C} | baseline | 无移除（=P7-1 五 cell 电池同判据重跑，新 runUUID） |
| Gδ-I | {P,A,C} | I 是否必要 | state record 移除 identity 断言（无 modelIdentity、无 executionID 绑定——匿名载荷） |
| Gδ-P | {I,A,C} | P 是否必要 | record 移除 position 断言（I/A/C 与 carrier 在） |
| Gδ-A | {I,P,C} | A 是否必要 | record 移除 anchor 绑定（I/P/C 与 carrier 在） |
| Gδ-C | {I,P,A} | C 是否必要 | record 移除 continuation 绑定（I/P/A 在） |

载体 = **llama.cpp（P7-1 harness 家族）**：关系级映射刚建立、
representation 便于构造 relation 手术、P7-1 五 cell 即 FULL 电池
结构。MLX 侧对应（KV 载体下的同矩阵）登记为可选扩展，不在本轮。
环境相对性：M-1/M-2/M-3 判据本就是「相对环境 E」——跨载体普适性
不在本设计宣称范围。

每 cell 电池（human §12）：fork / restore / divergent continuation /
parent non-pollution / replay——与 P7-1 证据结构一一对应。

## 3. 各 cell 设计与必要性签名（预注册）

### Gδ-I（Identity necessity）

- 构造：两个不同会话的 S₀（同模型），checkpoint 各自完整；Gδ-I 臂
  将 record 的 identity 断言移除（匿名化）后互换 payload restore。
- 必要性签名：**无 I 时系统无法区分/拒绝错配**——跨会话载荷互换被
  无差别接受并继续计算，「这是哪个计算状态的延续」不可断言 ⇒
  **I necessity evidence**。
- 结构性观察（如实登记）：modelIdentity 移除后 wrong-model 恢复在
  原理上不可检测（本地单 GGUF 限制，行为验证留扩展）。
- 若互换被剩余关系意外检测/拒绝 ⇒ 触发 Layer 2（谁补偿了 I？）。

### Gδ-P（Position necessity）

- 构造：同一会话同一 anchor 语义下的**不同进度载体**（full prefix
  vs 截断 prefix），record 无 position 断言时 restore。
- 必要性签名：无 position 断言时，系统无法断言「续算落在计算进度
  N」——落点不确定/错位不可检测 ⇒ **P necessity evidence**。
- **预注册合法输出（重要）**：full-prefix 锚（anchorHash 覆盖全
  token 序列）在此载体上**可能 subsume P**（anchor 变化即暴露截断
  ⇒ A 补偿 P）。若实测如此 ⇒ 登记 subsumption「A⊃P（full-prefix
  锚载体）」+ Layer 2 + 对照事实：**MLX KV 载体上 P 不可由 A 推导
  （S1 实证：processedTokenCount 31712 ≠ transcript 可渲染数）** ⇒
  若两载体结论相反，登记为 **P 必要性的载体依赖性**（压缩载体必要
  /全拷贝载体被 subsume）——这是 closure 修正级发现，非实验失败。

### Gδ-A（Anchor necessity）——human 判定最有研究价值

- 构造（PA-2 模式的 llama 版）：**same I、same P（token 计数恒等）、
  different content**——同一会话同一位置的原始前缀 vs 内容替换前缀
  （placeholder 手术，长度严格不变）。
- 必要性签名：无 A 时，两个**逻辑上不同、位置相同**的状态被当作
  同一 continuation point（互换不可检测；续算输出跟随被换入的内容
  ⇒ 语义错位不可分辨）⇒ **A necessity evidence（强）**。
- 直接回应质疑「是不是 Identity + Position 已经足够」——若能构造
  出该 ambiguity，A 的必要性获得最强支持（P5-4 PA-2 已有 MLX 侧
  原跑先例，本轮为 llama 侧关系级复制）。

### Gδ-C（Continuation necessity）——非字段测试

- 构造：I/P/A 全部正确，但 record 移除 continuation 绑定（无
  「未来输入自此接续」的合法关系）。
- 测试：restore 与 append 机械上可能仍可执行（对 token-prefix 载体
  append 永远可行）——**判据不在崩溃，在不变量**：无 C 时，系统
  无法断言「这个未来计算是 THAT state 的延续」（与「同一文本上的
  全新计算」不可区分；INV-C 的锚定/落点断言失去依据）。
- 必要性签名：断言不可构造 ⇒ **C necessity evidence**；反之若
  I/P/A 完整时 continuation invariant 可被完整断言与验证 ⇒ 登记
  「C 在该载体上非独立关系」⇒ closure 修正门。

## 4. Layer 2 — Substitutability（条件触发协议）

任一 Layer 1 cell 出现「被补偿」⇒ 触发：

```text
可构造变换空间（先验枚举，实验前冻结于执行设计门）：
  T ∈ {由剩余关系 record 字段重构被移除断言的确定性变换}
  排除：carrier 检视 / transcript 全量重算（M-2 冻结条款）
  枚举不穷尽 ⇒ INCONCLUSIVE（无界搜索失败证明力为零）
示例问句（human）：P+A 能否隐式确定 I？I+A 能否隐式确定 P？
```

## 5. 判读预注册

- 每 cell 输出 ∈ {**necessity-evidence**（移除后不可分辨/不可断言），
  **compensated**（被剩余关系补偿⇒登记 subsumption+Layer 2），
  **INCONCLUSIVE**（身份/隔离破损或枚举不穷尽）}。
- 四 cell 全 necessity ⇒ 措辞升格为（且仅为此）：
  > **candidate closure with experimentally supported necessity of
  > each relation**
  仍不得说「minimal 已证」——Layer 2 全过后才可谈 minimality
  evidence（M-2 层），数学最小性永远不在措辞内。
- 任一 compensated ⇒ **closure 修正门**（human 裁定 subsumption
  如何改写 {I,P,A,C}）——重大有效结果，不得为保四关系改判据。
- 隔离与仪器：R0 六件套 + 递归内容见证（P7-1 同规范）；placeholder/
  匿名化手术逐字节记录（D6：手术=依赖性扰动，登记非静默）。

## 6. 项目状态链（human §15 登记）

```text
PHASE 1 MLX Runtime Evidence Consolidated
  → Candidate {I,P,A,C}
  → P7-1 Cross-backend Validation（MLX PASS / llama PASS /
    same continuation invariant）
  → Claim F: BOUNDED CROSS-BACKEND SUPPORT（human 终验收）
  → NEXT QUESTION = G-δ MINIMALITY
      ├── Is I necessary?
      ├── Is P necessary?
      ├── Is A necessary?
      └── Is C necessary?
```

## 7. Non-claims 与门位

- 本档零执行零结论；relation removal 操作化与 derivability space
  为本档新增冻结项（判据文档 M-1/M-2/M-3 的落地细化，非修改）。
- 门位：`DESIGN FROZEN → EXECUTION AUTHORIZATION（human 单独授权）
  → G-δ RUN → MECHANICAL ADJUDICATION → SECOND-LAYER REVIEW`。
- 执行前置届时核对（llama-server/GGUF/工作区），同 P7-1 规范。
