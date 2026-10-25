# Execution State Continuation Criteria — D1（A 线交付）

日期：2026-10-01  
状态：`A_LINE_DELIVERED / CRITERIA_DRAFT_D1 / READ_ONLY_SYNTHESIS / NOT_A_STATE_DEFINITION`  
任务令：R4-0 → A1-A4（human 2026-10-01，Lab `f1e35be`；Phase R4）  
性质：只读综合——零实验、零代码、零实现方案。输出是**能力判据**，
不是 State 定义；不指定 KV、hidden state、cache 或任何内部实现。

```text
判据形式（任务令原式）：
  S + X → Y
  若存在 State S 使得未来计算 Y 只依赖 (S, X)、无需重新执行已完成的
  历史计算，则称 S 对该类输入具有 continuation capability。
```

证据底座（只引用仓内封存文档）：ES-R1 Phase A inventory（A1–A4）、
ES-D1（G-C / H-B / J-C）、ES-R2（FSB-1 / Gate B / Gate C）、R2n
（P-N1/N2/N3）、E3（C-0…C-3 / RF-1）、E2、PB1、RF-2。

---

## 0. 判据的对象与范围

```text
过去计算 → State S → 未来输入 X → Continuation Y
```

- 判据只约束 **S 与 X 是 Y 仅有的可容许输入**（admissible inputs）——
  这是 RF-2（restore 依赖 ≠ continuation 依赖）在判据层的落实：本线
  只处理 continuation 一侧。
- S 的物理形态、内部构成、承载方式**一律不在判据内**（T3/C-0 边界
  延续；「backend 负责增量计算」的分工由纠偏地图确立）。
- 判据面向**验证**：A2 的每一条都可被未来实验按预注册方式判定。

---

## A1 — Continuation Preconditions（未来计算需要哪些条件）

```text
C1 语义落地（grounding）
   Y 必须能确定「过去的计算是什么」，粒度满足任务需要。
   证据：R2n P-N2（内容扰动→continuation 质变）；P-N3（删 tool
   历史→指代崩塌）；E3 C-0/C-1 ANCHORED vs C-2/C-3 UNANCHORED。
   缺失时的两类失败模式（充足性测试必须都能检出）：
     · 自信虚构（RF-1：貌似合理、完全错误的概述）
     · 明示索要上下文（ES-R2 Gate C attempt 2 逐字）

C2 位置断言（position）
   基点必须断言「过去的计算在哪里结束」。
   证据：H-B（position 持久性是事件门控的——checkpoint 提交的 17
   跨进程存活且权威，runtime 推进的 18 死亡）；ES-R2 attempt 2
   （无 State 时会话始于 position 2 而非 17）。

C3 即时输入 X
   未来输入本身（probe / delta）。

C4 执行能力（execution capacity）
   从断言位置向前计算、且不重算历史，运行时/backend 所需的一切。
   纠偏地图分工：**提供 C4 是 backend 的责任**；判据只要求
   Continue(S, X) 可执行，其物理形态故意不指定。

C5 兼容性（compatibility）
   continuation 只对兼容的计算系统（模型/tokenizer）有定义。
   G-B2-3（跨格式「同一模型」判定）保持 OPEN UNKNOWN——判据限定
   在固定兼容系统内。
```

---

## A2 — State Sufficiency（什么叫「State 足以支持未来计算」）

对目标输入类 X，S 足以支持 continuation，当且仅当：

```text
SUFF-1 良定义性
  Y 在固定解码（greedy）下可复现。
  证据：PB1 / P-N1 确定性基线使逐字比较成为有效方法。

SUFF-2 基线等价
  Y(S, X) ≡ Y_baseline(X)（greedy 逐字），其中 baseline = 完整
  history 携带/重执行下的 continuation（R2n 证其为产品一等分支）。
  这是最强可用等价目标；偏离须逐字登记，不得平均化。

SUFF-3 内容敏感性
  Y 必须随 S 的落地内容变化：扰动→P-N2 型质变；删除→P-N3 型
  崩塌。此条防「空壳载体」假阳性——对自身内容无感的「State」
  不得判为 sufficient。

SUFF-4 历史独立性
  Continue 路径只消费 (S, X)；不得以「读 H / 读旧 P」方式完成。
  （S 内部物理包含什么不在判据内——只约束可容许输入关系。）
```

注：SUFF-1/2/3 的判定规则逐字继承 Gate B 的 P1/P2 裁定规则（greedy
逐字 / 锚词）——方法连续性，非新方法论。

---

## A3 — State Identity（如何判断两个 State 是同一个计算基点）

两个 State 是**同一计算基点**，当且仅当：

```text
IDENT-1 寻址同一        同一 caller key
                        （ES-R1 A1：storageKey 一物三面；E1-R0：
                        meta 三键自足识别）
IDENT-2 位置同一        同一事件提交的位置 N（H-B）
IDENT-3 边界同一        同一 continuation anchor（N 处 transcript
                        尾哈希——ES-R2 Gate B carrier 实测跨进程
                        可验证；FSB-1 最小集）
```

即：**基点身份 = FSB-1 最小集 {key, position, anchor}**。

两条刻意**不作**的声明：

```text
✘ 内部载体字节同一性不在此判据内——重算载体 vs 恢复载体的等价性
  明确未证（E2 pending / Gate D 域）
✘ 分叉子分支彼此的同一性不在此判据内——子分支在 S₀ 处共享基点
  身份、此后沿各自的 (position, anchor) 演化分叉；lineage 力学
  （forkPoint=latent carrier，D1-B2 writer-only）不在本判据断言
```

---

## A4 — State Boundary（状态的边界在哪里）

```text
S 的边界内：
  · 寻址/身份（key）
  · 位置断言（C2）
  · 边界锚（anchor）
  · 落地载荷（满足 C1 的那部分——现证据定位其住于会话正文含
    tool 历史（R2n/E3）——此为证据记录，非定义声明）

S 的边界外（证据支撑的排除）：
  · 性能表示（E2：池=可替换性能 Representation）
  · 完整性/验收门字段（generation/SHA/modelId——D1 G-C：各门
    AUTHORITATIVE，属保护/兼容机制非语义 State）
  · 身份之外的生命周期记账
  · backend 执行内部（设计性不指定）
  · 完整 History 本身（S 可由其承载；S ≠ 它——三层分离）

边界注记：现行产品把 S 载体与 P+H 融合封装（ES-R1 A4 / B′-1 ①③）
——融合是当前系统事实，不是边界陈述；判据描述 S 的边界，
不描述现行封装。
```

---

## Non-claims

```text
✔ 不是 State 定义；未指定任何物理形态（KV/hidden state/cache 零提及
  为定义）
✔ 判据是 B 线充足性测试的 schema——本轮未执行任何实验
✔ 除标注 A 级者外，证据锚点限单样本/单 vendor（§5 分级延续）
✔ C4 的物理形态不指定 ≠ 断言其不存在——是分工（backend 责任）+
  T3 边界的延续
```
