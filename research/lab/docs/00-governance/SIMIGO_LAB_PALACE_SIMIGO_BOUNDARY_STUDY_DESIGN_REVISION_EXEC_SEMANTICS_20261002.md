# PALACE-Simigo Boundary Study — 设计修订登记：Execution State 语义精化（human 方向）

日期：2026-10-02  
状态：`DESIGN REVISED & RE-FROZEN / FIRST-MINIMAL-EXPERIMENT AUTHORIZED（NOT STARTED）`  
修订对象：设计草案
（`SIMIGO_LAB_PALACE_SIMIGO_BOUNDARY_STUDY_DESIGN_DRAFT_20261002.md`，
起草 `7da9c3f` / 冻结+首实验授权 `87fc9f5`）§1–§12  
修订权威：human 方向（本会话，逐字登记见 §2）  
性质：design revision 登记——非实验结果；方向登记件
（`SIMIGO_LAB_PALACE_SIMIGO_BOUNDARY_STUDY_DIRECTION_20261002.md`）
原文不动，本件登记其精化

## 1. 修订一句话

```text
ES 从「PALACE 恢复不了的残留」
精化为「PALACE 信息空间中具有执行语义的特殊信息类」；
首实验探针从「缺什么 → 归属哪边」
改为「完整保存 → 恢复 → 逐项观察：
      可直接作为信息消费 vs 必须以 ES 语义恢复才能继续执行」
```

## 2. human 方向登记（本会话，逐字/近逐字）

概念图（human 原文结构）：

```text
                 信息空间
                    │
        ┌───────────┴───────────┐
        │                       │
     普通信息              Execution State
        │                       │
  文档/事实/关系          工作中的中间状态
  文件/知识/结果          分支/进度/上下文
        │                       │
        └───────────┬───────────┘
                    │
                 PALACE
```

概念精化（human 原语，冻结）：

```text
· 「Execution State 本身也是一种信息，只不过它是具有执行
   语义的信息。」
· 「PALACE 是信息空间；Execution State 是其中一种特殊的
   信息结构。区别在于语义和可操作性，而不一定是物理存储
   位置。」
· 关键不是「⑥⑦⑧ 应不应该放到另一个数据库？」而是：
  「PALACE 能不能保存它们，并且保持它们原本的 Execution
  State 语义？」
· 不变量：「Execution State 的语义不能因为信息被存储、迁移、
  恢复、重新组织而丢失。」
```

示例分类（human ①–⑧，逐字保留；性质 = 探针刺激词汇非预设
答案——⑥⑦⑧ 的语义能否由信息承载正是实验要测的）：

```text
① 找到 17 个相关文件          → 信息
② 读取其中 8 个               → 信息
③ 建立文件之间的关系          → 信息
④ 完成部分计算                → 信息
⑤ 发现两个数据冲突            → 信息
⑥ 已选择其中一个作为当前分支  → Execution State
⑦ 当前正在处理第 9 个文件     → Execution State
⑧ 某工具调用已完成但后续未执行 → Execution State
```

研究问题精确化（human 原文）：

```text
原问（父问，保留）= PALACE 能恢复到哪里，而 SimiGo 从哪里
    开始不可替代？
精确问（operative，冻结）= 一个真实工作的全部必要信息进入
    PALACE 后，其中哪些信息仅仅是可描述的，哪些信息必须
    保持 Execution State 语义才能继续执行？
```

首实验流程修订（human 原文，冻结）：

```text
不是：A 做工作 → B 缺什么 → 判断缺口属于 PALACE 还是 ES
而是：A 做工作 → 将工作完整保存到 PALACE 信息空间
      → B 从 PALACE 恢复
      → 观察哪些信息可以直接作为信息消费，
        哪些信息必须以 Execution State 语义恢复才能继续执行
```

SimiGo 位置精化（human 原文语义，冻结）：

```text
PALACE 负责让信息存在于一个可持续的空间中；
SimiGo 负责让其中具有 Execution State 语义的部分真正成为
「可执行状态」：
  fork / restore / commit / discard / cancellation /
  physical representation
重申 = SimiGo 不是 inference engine；
ES 不必然物理存放在 SimiGo 自己的内部；
真正重要的是 ES 语义在存储/迁移/恢复/重组中不丢失。
收束公式（human 原文）= 「Execution State 不再是 PALACE 的
对立面，而可能是 PALACE 信息空间中最特殊、最需要语义保护的
一类信息。」
（与方向登记终态公式「PALACE 负责世界 / SimiGo 负责人在世界
中的持续行动」为精化关系，非替换。）
```

Contract 对应 guard：上述 SimiGo 语义域清单与 Contract
v1.0-amended lifecycle 七操作（create/save/restore/eviction→
release 族/fork 等）为观察级呼应；Contract = MLX/runtime 范围
冻结件，不作为本研究（信息世界层）权威——SEPARATELY SCOPED。

## 3. 据此修订的设计条款（草案 §13 = operative 读法）

```text
修订项：
  §13.1 概念精化与不变量（§2 登记）
  §13.2 精确问（operative；父问与 §1 原冻结措辞保留）
  §13.3 首实验流程（A 半程从「沉淀自由」升为「完整保存」，
        含 ⑥⑦⑧ 类工作状态项；观察轴 = 语义存活；
        六问转置 = A 的保存清单 + B 恢复时次级问答探针）
  §13.4 Boundary Evidence Table v2（取代 §12.3 v1 表：
        逐项观察 信息消费 vs 语义存活；闭合测试转置到语义）
  §13.5 判别力门 = 任务须自然产生 ⑥⑦⑧ 类事件
        （分支选择/执行位置/未完成操作），否则换任务不硬做
不变项（文本冻结，读法按 §13 转置）：
  §4 真值分离（真值仍封存，用于核对 v2 表归属）
  §7 闭合测试与残留资格规则（「补一条合法信息」→「补一条
     合法信息记录能否恢复语义」）
  §8 判读纪律 / §9 禁令 / §12.1 最小范围（仅 A 半程+B 半程）
  执行第 0 步提名门（≥2 候选 × 五标准 + §13.5 核验 → human
  钉定）
```

## 4. 三项冻结审查重跑（修订后设计）——PASS ×3

```text
① 问题唯一明确 PASS = 父问保留、精确问唯一 operative；
    信息消费轴与 ES 语义轴是同一问的两面，无第二问夹带
② L0+G0-G3 足以构造 PASS = 信息空间组成不变；「完整保存」
    设置更贴近 RQ-G3-2 Tier-4 已证可行形态（原样全量记录
    可落盘）；human ①–⑧ 示例与 G2 T-1..T-3 真实任务形态
    高度同构（finding/mapping/conflict 形态在案已发生）
③ A→停止→B 能暴露目标现象 PASS（证据基更新）=
    信息轴近饱和由 Tier-4 全保真先例支持（故判别轴恰在
    语义——discriminating power 反而增强）；语义/载体分离
    有在案先例（P5：KV cache = Representation fragment 非
    独立 continuation carrier；PA-2：Position ≠ Semantic
    Anchor，「ES 不能只存 KV」——backend 范围发现，本研究
    仅作类比级锚点非证明，SEPARATELY SCOPED）；CF-① 证明
    「记录在而语义错」的操作性风险真实存在（Tier-3 量级
    错配假候选）
→ 修订后设计 RE-FROZEN；首实验授权延续（NOT STARTED）
```

## 5. 状态

```text
PALACE-SIMIGO BOUNDARY STUDY
DESIGN STATUS: FROZEN (REVISED — §13 operative)
EXECUTION STATUS: NOT STARTED
EXECUTION AUTHORIZATION: FIRST MINIMAL A→B EXPERIMENT ONLY
    (revised probe: full-preservation → recover →
     semantic-survival observation)
```

## 6. Next

```text
不变：执行第 0 步任务提名（≥2 候选 × §10 五标准 + §13.5
判别力核验）→ human 钉定任务 X
→ A 半程（真实工作 + 完整保存，含 ⑥⑦⑧ 类）
→ 登记停止点 → B 半程（仅信息空间恢复 + 逐项观察）
→ Boundary Evidence Table v2 构建 + 真值核对
→ 结果门 = human 判读（含是否进入四 case 全量与知识库问题）
```
