# SimiGo-Lab Research Line Review — 哪些在验证 SimiGo，哪些被 backend 带偏

日期：2026-10-01  
状态：`RESEARCH_LINE_REVIEW_DELIVERED / HUMAN_DECISION_GATE_OPEN`  
性质：只读复盘——零实验、零代码、零新实现方案。证据=research state /
governance 封存文档 / experiment artifacts / commit history / C-0。  
任务令：human 2026-10-01（Lab `2591551`）。

```text
复盘纪律（任务令原样约束本文）：
❌ 不得因近期讨论倒推「Execution State = 中间结果 / KV / hidden state /
   cache」
❌ 「共同计算基点」只能作为候选 reframing hypothesis（S ?= Future
   Computation Base），升级为正式命题归 human
❌ 最后一节只给选项，不替 human 裁定
✔ 每个实验都过反事实检查：换掉当前 backend，结论还成立吗？
```

---

## 1. Executive State of Research

主证据链（2026-09-29 route redefinition 之后约 48 小时内）完成了一条
干净的**边界发现序列**：存在边界（ES-R1：无独立 durable State）→ 形成
边界（ES-D1：checkpoint schema 不捕获）→ 执行边界（ES-R2：Tier-1 存活
但不可重物化）→ 载体形态缺口（ES-T2：信息不缺、第三形态缺）→ P 内部
分解尝试（ES-T3：A/B/B′）→ 命题守护与能力缺口定位（C-0/Closure
Review）。同时语义侧证据链（PALACE-1 R2n/E3/E2）已把「continuation
语义住在 transcript、池是可替换性能表示」钉死。

**复盘总结论**：概念/方法层高度可复用且大部分 backend-independent；
**证据层重度集中于单一 backend/单一模型/单一样本**。「命题用架构级语
言陈述、证据是 backend 局部材料」的错位，是支线形成的机制；三次 human
刹车（Gate B 终审 premature-abstraction、B′ 封存、C-0 命题守护）防止
了滑移固化为错误结论。左支（Execution State 语义：durable identity/
authority/lifecycle/equivalence）仍有 Contract 继承的未完成项。

## 2. Original SimiGo Question

Route redefinition（2026-09-29）收束的核心问题（原文）：

> **Execution State 能否从当前 MLX 实现与具体 Physical Representation
> 中抽象出来，成为可持久化、可恢复、可跨 Representation / Backend
> 演进的一等运行时状态？**

其上层动机（memory/主线索引在案）：机器不重算已算过的前缀、不重推已
定案的结论——**过去的计算成为未来计算的基点**；日常小规模大模型路径
是产品根基。

本文的坐标即由此展开：

```text
                    SimiGo 核心（左支）
   「过去计算能否成为未来计算的基点？」
                         │
        ┌────────────────┴────────────────┐
        ▼                                 ▼
  Execution State                   Backend mechanism（右支）
  persist/restore/fork/             KV / GDN / cache /
  lifetime/reuse                    model-specific state
```

## 3. Research Line Timeline

```text
2026-09-29  route redefinition（核心问题收束；oversized 冻结；
            Contract-first 分层树）
2026-09-30  PALACE-1 六实验链：E0 工件解剖 → E1 表示丢失（fail-closed
            ×3）→ E1.5 meta 扰动（保护/语义分层）→ R2-trace/R2n
            （history necessity）→ E2 池可替换 → E3 定位阶梯+虚构发现
            （d408729 证据封装；RF-1/RF-2 登记）
2026-09-30  ES-R1 存在边界（PB1 基线 / A1-A4 / C-3 穷举 7 入口 /
            R1-B FINAL SEAL 9015f 段）
2026-09-30  ES-D1 形成边界（F 13 事件 / G-C PARTIAL AUTHORITY /
            H-B 事件门控 / J-C PARTIAL FORMATION，180b065 SEAL）
2026-09-30  ES-R2 执行边界（FSB-1/FSB-2 / STATE-SURVIVES / C-2 FINAL /
            三层分离，0b7b976 SEAL）
2026-09-30  ES-T2 载体形态缺口（T2-A2 carrier-FORM gap，fe35722）
2026-09-30  ES-T3 设计锁定（a272424）→ Gate A census（19c1ffc，
            A2 CONFIRMED/A3 PARTIAL）→ Gate B 扰动（fa21551，
            VERDICT B-3 + premature-abstraction 刹车）
2026-09-30  T3-B′-1 源码追踪（424b07b PARTIAL INCONCLUSIVE）
            → B′-2 差分（ab20168 EXECUTED-UNINFORMATIVE）
2026-10-01  B′-2 裁定 + B′-3 观测面差分（5108427/09332a2，null
            difference 限缩读数）→ B′ SEALED CLOSED-LIMITED（39c701e）
            → C-0 readiness review（795352f）+ human 审阅（d169b74）
            → Closure Review（5b55599：L3 UNVERIFIABLE-AS-IS）
2026-10-01  本复盘（Research Line Reset）
```

## 4. Proposition → Evidence Matrix

每行：命题（可验证形式）→ 实验 → 证据 → 结论 → 当前是否仍成立。

| # | 命题 | 实验 | 证据 | 结论 | 仍成立？ |
|---|---|---|---|---|---|
| P-a | Execution State 能否抽象为可持久化/可恢复/跨 backend 的一等状态（route 原问） | ES-R1/ES-D1/ES-R2/Contract 线 | R1-B / J-C / C-2 | 当前 stack 内：State=架构抽象+Tier-1 残存，无独立 durable 状态资产 | **OPEN（核心未答）** |
| P1 | 是否存在可持久化的 Execution State（独立 runtime State）？ | ES-R1 | C-3 穷举 7 入口零消费；R1-B FINAL | 无独立 durable runtime State（限被审 stack） | 成立（as-scoped） |
| P2 | Representation 消失后 State 是否仍存在？ | ES-R2 Gate B | 三标量 carrier 跨进程+P-loss 存活 | Tier-1 SURVIVED | 成立 |
| P3 | State 能否恢复未来计算？ | ES-R2 Gate C | seam 缺 P；无 history 位置 2 | C-2：存在≠可执行 | 成立（否定向） |
| P4 | State 能否作为 fork 的共同基点？ | —（研究线未直接测） | D1-B2：forkPoint=writer-only latent carrier | 研究线未回答；产品线 fork 钩子在案但未作为 State 基点验证 | **未触及** |
| P5 | 未来计算是否只需增量部分？ | 产品线（池/token ledger）+ ES-T2 | 池命中 84×/17-17 快照；T2-A2 位置执行需 H 或 P | 同会话前缀：已证；独立 carrier 增量：第三形态缺口 | 分裂（产品证/研究开） |
| P6 | continuation 语义住在 transcript（含 tool 历史） | R2n/E3 | P-N1/N2/N3；C-0…C-3 | 是；persona/寻址/保护字段不是 | 成立 |
| P7 | P 内部存在可独立复用的计算分量 | ES-T3 全链+C-0/Closure | B-3 KV operative；L3 UNVERIFIABLE-AS-IS | 候选有 operative 证据，独立性当前不可验证 | 未决（不可验证-as-is） |
| P8 | 语义缺席会被识别并拒绝 | E3-C-2 | 模型自信虚构 | RF-1：缺席不可自证 | 成立（否定向发现） |

## 5. Backend-Independent / Backend-Mediated / Backend-Specific Matrix

```text
A = 换 backend 后命题仍成立
B = 命题成立，但证据依赖当前 backend
C = 换 backend 后基本失去意义
（概念/方法 与 证据 分列——错位即 drift 机制）
```

| 阶段 | 概念/方法层 | 证据层 | 备注 |
|---|---|---|---|
| PALACE-1 E0 工件解剖 | A（工件解剖法） | **C**（80 张量/形状/performSave） | 内容随 backend 作废 |
| PALACE-1 E1 fail-closed | A（保护基建概念） | B | 「restore 需 P 前置」他 backend 未证 |
| PALACE-1 E1.5 保护/语义分层 | A | B/C（本 stack meta schema） | |
| R2n history necessity | **A**（LLM 通用命题） | B（单样本单 probe 贪心） | 换 backend 大概率复现，未证 |
| E2 池=可替换性能表示 | **A**（SimiGo 层，不涉 backend） | A | 全链最干净的 A |
| E3 定位阶梯 + RF-1 | A（LLM 行为层） | B（单样本） | |
| FSB-1/FSB-2 | **A**（架构级边界陈述） | B（「唯一压缩物=KV」前提是 B） | |
| ES-R1 存在边界 | A（边界方法学） | **B/C**（7 入口=本 stack API 面，vendor 版本钉死） | |
| ES-D1 形成边界 | A（authority=生命周期属性；formation gap 概念） | **C**（断点位置=SessionCacheMetadata，mlx-swift-lm 产物） | 换 backend 断点位置会移动 |
| ES-R2 执行边界 | A（存在≠可执行；三层分离） | B | |
| ES-T2 carrier-FORM gap | A（信息不缺形态缺） | B（「上游 API 通用」实际只查了一个上游） | |
| ES-T3-A census | A（组件分离性=合法架构问题） | **C**（七问事实=Qwen3-Next+vendor） | 左→右滑移入口 |
| ES-T3-B（B-3） | A（结构必要性≠内容必要性） | **C**（KV/GDN 必然性=本模型架构） | |
| ES-T3-B′ | A（观测面技术；P-1 教训） | **C**（GDN 消费语义） | |
| C-0/Closure | A（constructibility≠pre-existence；可引用断点） | B/C（融合载体=本 stack） | 支线收束回主线的枢纽 |

**读法**：概念列几乎全是 A，证据列大量 B/C。**凡是以 A 级语言书写、
却只有 C 级证据支撑的句子，都是潜在支线句**。复盘未发现已固化的此类
句子（各 SEAL 文档的 non-claims 边界把措辞守住了），但发现了三条在
C 级证据上继续加码的实验投入（见 §7）。

## 6. Mainline / Supporting / Off-Mainline Classification

```text
MAINLINE（直接验证 SimiGo 核心命题——保留在主线链条里）
  route 原问（§2）
  R2n + E3 + RF-1/RF-2        语义侧：过去计算住在 transcript；
                              缺席不可自证
  E2                          划清「加速表示 ≠ 唯一载体」
  FSB-1/FSB-2                 Tier-1/Tier-2 边界（存在≠可执行）
  ES-R1 边界陈述（R1-B 概念）  无独立 durable State（as-scoped）
  ES-D1 概念                  authority=生命周期属性；formation gap
  ES-R2 三层分离              知识≠计算状态≠可执行状态
  ES-T2 T2-A2                 carrier-FORM gap
  C-0/Closure 概念            constructibility≠pre-existence；
                              「可引用」断点

SUPPORTING（方法与基建——随主线保留，不独立成线）
  PB1 确定性基线法 / 隔离配方（零 durable 写入+204 核验）
  B′-3 观测面技术（text/toolCalls/token 计数；P-1 教训）
  证据封装法（fact/inference/unproven 分层）
  E1 fail-closed 特征化 / E1.5 扰动协议

OFF-MAINLINE / BACKEND-LOCAL（降级——归档保留，不再作为主线证据引用）
  E0 的张量级内容（80 张量/形状/写入路径）
  ES-T3-A 七问事实（vendor/model 局部）
  ES-T3-B B-3 判定（KV/GDN 必然性——本模型架构产物）
  ES-T3-B′ GDN 消费结论（A/B 双未决，源码偏向 A——限本模型）
  ES-D1 断点具体位置（SessionCacheMetadata 字段集）
  ES-R1 的 7 入口清单（vendor 版本钉死）
```

降级不删除：上述每一条的档案价值与「教训价值」（结构/内容必要性分离、
观测截断教训）完整保留在各自 SEAL 文档中；降级的含义仅是——**它们
不再被引用为「Execution State 是什么」的证据**。

## 7. Where Research Drifted

按时间定位左支→右支的滑移：

```text
滑移点 1（合法入口）：E0 工件解剖
  要回答「State 能否脱离 P」，必须先知道 P 是什么——合法。
  副作用：backend 解剖材料进入证据库。

滑移点 2（真正分叉）：ES-T3 设计假设「第三形态可能已潜藏于 P 内部」
  问题从「State 与 Representation 的边界」（左支）变成「P 内部分量
  （KV/GDN）的分解与必然性」（右支）。这是 human 定义的合法替代假
  设检验——但自此工作对象全是 vendor/model 内部，且无多后端/多模型
  抽样策略，全部纵深压在单一证据点上。

滑移点 3（未遂，被刹车）：三次 human 刹车
  ① Gate B 终审：premature-abstraction——「P 的组件 ≠ Execution State」
  ② B′ 封存：切断「实验退化成寻找差异」
  ③ C-0/Closure：命题守护（不偷换成「证 GDN 无用」/「造 KV-only」）
  滑移被控制在了「多花了实验」而未变成「错误结论」。
```

**验收 Q3 的回答**：若今天从零开始——

- ES-R1→ES-D1→ES-R2 主干**会重选**：存在→形成→执行的边界序列是干
  净的架构工作，结论层次与顺序都对。
- ES-T2→ES-T3 分叉**可辩护但应改造**：T3 的替代假设是合法假设检验，
  其负/边界结果有真实价值（把「第三形态缺」从猜想变成实测地形）；
  但起点就该绑定**抽样策略**（多模型/多 backend 最小样本矩阵），否
  则任何单样本结论都只是 C 级。路径偏移的准确节点 = **T3 Gate A 之
  后**：假设已被判定为「值得检验」，而后续 B/B′ 的投入在无抽样计划
  下继续加深单点——这是偏移的发生处与原因（把「检验一个假设」做成
  了「挖透一个 backend」）。
- 语义侧（R2n/E3）会**更早**做、并且更早把「左支语义（durable
  identity/authority/lifecycle）」与「右支物理（P 解剖）」分 staffing——
  前者才是 route 原问的主战场。

## 8. What Previous Experiments Still Prove（验收 Q1）

可复用事实（按 A 优先排序）：

```text
① 池 = 可替换性能表示；语义能力不依赖池（E2）——SimiGo 层，A
② continuation 语义住在会话正文（含 tool 历史）；persona/寻址/保护
   字段不承载（R2n/E3）——LLM 通用命题，B 级证据
③ 语义缺席的失败模式是自信虚构而非拒绝（RF-1）——工程级警告，A 偏
④ restore 依赖 ≠ continuation 依赖（RF-2）
⑤ Tier-1 State（三标量）可跨进程死亡+P 丢失存活（FSB-1/ES-R2-B）——
   概念 A，演示 B
⑥ State 存在 ≠ State 可执行（C-2 FINAL）——架构级，A
⑦ formation gap：形成事件在场、durable schema 不捕获（J-C）——概念 A，
   断点位置 C
⑧ 载体形态缺口：信息不缺，缺第三形态（T2-A2）——概念 A
⑨ 观测截断会制造假 null 结果（B′-2→B′-3 P-1）——方法论，A
⑩ 结构必要性与内容必要性可分离（B1 vs B3）——方法论，A
⑪ constructibility ≠ pre-existence（C-0）——方法论，A
⑫ 产品 runtime 侧：fork/restore/delete/cancellation/原子性/generation
   门等核心语义已验证（route redefinition 前提，Beta 审计 PASS）
```

## 9. What They Do NOT Prove

```text
❶ P 的任何分量可独立复用为计算基础（L3 UNVERIFIABLE-AS-IS）
❷ GDN 被消费或不被消费（B′ 封存：A/B 双未决，源码偏向 A）
❸ Execution State = 任何特定物理对象（KV/hidden state/cache——禁令在
   案；全部证据只到「融合载体的内部分量」为止）
❹ 任何结论跨 backend/模型普适（全部证据来自单 vendor/单模型/单样本
   纵深；§5 证据列大量 B/C）
❺ 第三载体形态不可能存在（只证了「观察宇宙内不存在」——FSB-2 刹车
   措辞延续）
❻ 独立 carrier 的增量式 continuation（P5 研究侧）
➋ 「共同计算基点」作为 Execution State 定义（仅候选 reframing
   hypothesis，S ?= Future Computation Base，未升级）
```

## 10. Current Core Unknown

```text
UK-1「可引用」断点：现有 Representation 是否具有（或能否不改语义地
    获得）可分解·可引用·可重组的内部计算结构（Closure Review 蒸馏；
    严格条件=不构造不证明）
UK-2 左支语义未完成项：durable Execution State 的语义定义与实现边界
    ——Contract v1.0 继承条件（durable identity allocation /
    continuation-vs-transcript equivalence / 独立 binding 边界 /
    crash consistency / discarded-binding gap）+ Phase B 开门的
    D1-D4 四问（什么必须 durable/可 reconstruct/SAME 判据/P 丢失后
    State 如何继续存在）
UK-3 S ?= Future Computation Base—— reframing hypothesis，未升级
UK-4 抽样面：任何右支命题的 A 级化都需要多 backend/多模型最小矩阵
```

## 11. Candidate Research Line After Reset

按「回到主线」重排的候选（互斥性未裁定，仅并列呈现）：

```text
候选 A【左支语义线】Execution State durable 语义定义门
  内容：UK-2 的 D1-D4 + Contract 继承条件逐条审；产出=最小 durable
  语义的定义决议（不含实现/存储选型）
  依据：route 原问的主战场在左支；产品日常小规模路径直接受益
        （前缀 KV 池已是产品根基——把「什么必须 durable」钉死）
  性质：与「小规模是根基」的路线裁定对齐度最高

候选 B【能力缺口线】UK-1 定义门
  内容：为「可分解·可引用·可重组」候选问题开独立定义门（先定义
  「可引用」的观测语义，不造 carrier）
  依据：Closure Review 蒸馏的断点；但注意——在当前系统内它可能
  直接命中「不可满足 ⇒ 不可分解计算整体」出口（本身即结果）

候选 C【reframing 门】S ?= Future Computation Base 升级裁定
  内容：human 决定是否把「共同计算基点」升级为正式研究命题；
  若升级，须先过独立定义门+外审
  依据：本复盘获授权呈现为候选；不预装任何物理形态含义

候选 D【抽样基建线】右支命题 A 级化的最小矩阵设计
  内容：定义「换 backend 结论仍成立」的操作判据 + 多 backend/多模型
  最小样本矩阵（为未来任何右支工作预置抽样纪律）
  依据：Q3 的直接教训；不立即执行任何 backend 工作
```

## 12. Human Decision Gate（只给选项，不裁定）

```text
D-1 复盘采信：本 §4-§9 的分级与降级清单是否获 human 采信？
    （采信后降级条目按 §6 语义归档；不采信条目须指出）

D-2 主线选择：候选 A/B/C/D 的进入顺序（含「都不进入、停车」）？
    A=左支语义线（与产品根基对齐）
    B=能力缺口定义门
    C=reframing 升级裁定（可独立于 A/B 先做）
    D=抽样纪律预置

D-3 T3 终判衔接：Closure Review 推荐的岔 3（T3 关闭+缺口转出）是否
    随本次复盘一并终判？

D-4 支线归档确认：§6 OFF-MAINLINE 条目按「降级保留」处理，是否
    确认？（确认后其结论不得再被引用为 Execution State 定义证据）
```

---

```text
本复盘零执行。全部证据锚点出自仓内封存文档与 commit history；
未产生任何新实验、新代码、新实现方案。
一句话收束：SimiGo 已经精确知道自己「证明了什么、没证明什么、
缺的是实验还是能力」——剩下的分岔全部在左支语义、能力定义、
reframing 三者之间，由 human 择路。
```
