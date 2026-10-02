# PALACE-Simigo Boundary Study — 同一信息世界工作状态恢复边界 设计 Draft

日期：2026-10-02（同日两次修订：§12 首实验最小化；§13 ES 语义
精化——现行 operative 读法见 §13）  
状态：`FROZEN (REVISED §13) / FIRST-MINIMAL-EXPERIMENT AUTHORIZED（NOT STARTED）`  
冻结审查：`SIMIGO_LAB_PALACE_SIMIGO_BOUNDARY_STUDY_DESIGN_FREEZE_
REVIEW_20261002.md`（三项全 PASS；修订后重跑亦 PASS×3）  
修订登记：`SIMIGO_LAB_PALACE_SIMIGO_BOUNDARY_STUDY_DESIGN_REVISION_
EXEC_SEMANTICS_20261002.md`  
Gate：`PALACE_SIMIGO_BOUNDARY_STUDY（observation only）`  
授权来源：G3 主线收束裁定（Boundary Study ENTRY OPEN）+ 方向登记
（`SIMIGO_LAB_PALACE_SIMIGO_BOUNDARY_STUDY_DIRECTION_20261002.md`）
+ human 发起指示与冻结审查指令（本会话，2026-10-02）  
性质：冻结设计——§1–§11 冻结不变；§12 = human 冻结指令修订
（首实验最小化 + B 行为六类 + Boundary Evidence Table）

## 0. §0 并发核验（执行前须重跑）

```text
设计登记基线 = 本文件入库 commit；执行前重跑 git fetch + 树净核验
```

## 1. 核心问题（human 措辞，冻结）

边界问（G3 收束登记措辞）：

> **当信息空间已经保存足够多历史信息后，哪些内容仍然必须属于
> Execution State？**

两工作者问（方向登记措辞，同一问题的观察形态）：

> **如果 PALACE 已经拥有足够完整的信息，两个工作者面对同一个
> 信息世界时，为什么仍然不能互相恢复对方的工作状态？**

## 2. 研究对象声明（非题外化）

```text
不是「PALACE 信息能力扩展」（信息层工程题）
不是「SimiGo ES 功能设计」（产品题）
而是：工作状态的哪些部分在信息空间足够完整时
      仍然无法仅由信息空间恢复
```

方法 = 同一信息世界 → 多个独立工作流（不同工作者/不同任务/
不同路径）→ 各自到达登记停止点 → 其他工作者仅凭信息世界尝试
恢复 → 与封存的工作状态真值逐条对照 → 观察不可恢复残留。

## 3. 「同一 PALACE」的操作化（执行事实声明，非新实现）

```text
信息空间 = 现实信息 as-is：
  L0 语料（只读，Corpus-1 = 16 文件）
  + G0-G3 实际信息侧产物原样
    （baseline-inventory.json / discovery-set+corrections /
    t1-mapping-results.json / corpus-change-rqg3-1.json /
    G3 结果与五项恢复矩阵等）
零新整理；不写 PALACE 代码；不实现 Palace database
信息空间组成在执行第一步钉定并落盘清单，此后只读
工作者可自由向信息空间沉淀记录（沉淀自由 = 真实工作的一部分）
```

## 4. 工作状态真值与信息侧的机械分离（可判读前提）

沿用 G3 已证 A（L0 only）≠ B（L0+工作状态记录）的操作化：

```text
(i)  信息侧沉淀 = 另一工作者仅凭读信息空间应能获得的部分
(ii) 工作状态记录 = 「我正在做什么/为什么这样走/走到哪」级记录
     ——不入信息空间，执行期原样封存 = 恢复探针 ground truth
分类逐条按规则执行并记录；不预建结构、不造字段表
真值在恢复探针全部完成前对恢复方封存（泄漏禁令见 §9）
```

## 5. 四情况观察矩阵（human 原文冻结）+ 分叉连接

```text
同一 PALACE
   ├── 人 A / 任务 X / 路径 X     ← Case-1 基准工作流
   ├── 人 A / 任务 Y / 路径 Y     ← Case-2 同工作者换任务
   ├── 人 B / 任务 X / 路径 Z     ← Case-3 独立工作者
   └── Agent / 任务 X / 路径 W    ← Case-4 自动化工作者
```

各 case 观察角色：

```text
Case-1 = 六问的主要被恢复对象；其工作状态真值 = 主对照
Case-2 = 分叉连接的组内对照（同一工作者、不同任务 → 不同路径
         → 不同 ES；「路径 X ≠ 路径 Y 即 ES 不同」的实证载体）
Case-3 = 主恢复探针发起方（B→A）＋自身同为被恢复对象（A→B）
Case-4 = 同任务第三路径；检验残留是否跨工作者种类（人/Agent）
         成立——「ES 候选边界」资格判据之一（§7）
```

分叉连接（方向登记原文，冻结）：

```text
信息空间的分叉 → 不同工作 → 不同探索路径 → 不同 Execution State
```

路径独立纪律 = 四 case 工作路径独立形成；case 之间禁止交换
工作状态记录（只可共读信息空间）——独立形成非事后镜像
（no construct-then-claim 纪律延续）。

工作者承担方式（人 A / 人 B 由谁承担：human 亲自 / 独立 Agent
会话 / 混合）= 冻结审查时钉定；无论何种承担，独立性纪律不变，
执行者知识污染如实声明。

## 6. 六问恢复探针（human 原语，逐字冻结）

PALACE 能恢复所有共同信息的情况下，若仍无法回答：

```text
· A 已经检查过什么？
· A 为什么跳过某个文件？
· A 已经排除了什么？
· A 当前正在验证什么？
· A 下一步准备做什么？
· B 接手 A 的工作时究竟缺什么？
```

则这部分才真正有资格成为 **Execution State 的候选边界**。

探针设计：

```text
问答探针 = 每个工作流到达登记停止点后，恢复方仅凭信息世界
           逐问作答；主探针 = B→A；交叉探针（Agent→A / A→B /
           B→Agent）按执行授权决定，记法相同
接手探针（第六问）= B 仅凭信息世界从 A 的停止点真实续作任务 X
           至下一停止点；「究竟缺什么」以续作行为记录
           （额外读取/重推导/中断点）逐条登记——非问答自评
答案五形态（预注册读法；分布不预设）：
  ① 可答且经真值核对为真
  ② 可答但经真值核对为错（误导）——CF-① 已证信息空间可制造
     错误确定性（Tier-3 量级错配假候选先例），此形态必须单列
  ③ 部分可答（可答部分为真）
  ④ 无答案（真值中有此工作状态、信息空间无对应）
  ⑤ 真值中亦无（所问在该工作流中未发生——空问对照，不计残留）
对照 = 答案逐条对照封存真值，对照记录原样落盘
```

## 7. 停止点与恢复判据（设计阶段冻结——方向登记 §8 要求）

```text
停止点 = 每个工作流在真实工作自然段落处登记（逐字状态声明；
         参照 G2 T-3 停止点先例）；一经登记不得回改
残留资格规则（逐条过）：
  (a) 跨工作者种类复现（人/Agent 至少两方工作流同现），或
  (b) 具 CF-② 型缺失形态证据（该判断在工作流中确实发生且
      从未持久化）
  满足 (a) 或 (b) → 有资格进入「ES 候选边界观察清单」
  否则 → 登记为一次性信息缺口（PALACE 责任域）
信息缺口 vs 工作状态缺口区分（逐条记录）= 对每个残留项问：
  「若信息空间补一条合法记录能否闭合」
  能闭合 = 信息缺口；不能闭合 / 补后引出新的六问残留
  = 候选边界。此区分是观察产出，不在设计期预写。
价值判定闭环（方向登记原文）：
  若同一 PALACE 中工作者路径仍无法由 PALACE 恢复 → SimiGo
  存在价值被 PALACE 实验反向逼出（实证闭环非概念）；
  若 PALACE 足以回答六问 → 同样是有效结果（ES necessity 保持
  UNPROVEN 的诚实出口）。两向皆开放，判据先注册后读数。
```

（探针对照维度与 G3 收束登记的五项工作恢复要素天然对齐——
登记非 Schema，不据此造评分表。）

## 8. Evidence Grade 与判读纪律

```text
Observation = 四 case 工作流 + 恢复探针 + 接手续作（原样落盘）
Inference   = 「X 属 ES 候选边界」须跨 case 对照 + 信息缺口
              排除；单 case 失败 ⇏ 边界（可能任务超纲/执行偶然）
Open        = 记录缺陷 vs 世界变化区分（OQ-B 纪律延续）；
              执行者知识污染声明（本线执行 Agent 已知 G0-G3
              历史与六问框架——机械层探针可执行，内容判断
              显式声明并记录规避方式）
禁止比较「哪类工作者更好」；禁止把六问/矩阵变成产品 API
```

## 9. Prohibitions（逐字冻结）

```text
❌ 先造 DurableInformation / WorkState / Provenance / Relation
   类再拿实验证明（方向登记纪律原文）
❌ PALACE Schema / 数据库 / PALACE State 设计；不写 PALACE 代码
❌ ES Schema / ES 定义（本研究只产出候选边界观察清单；定义走
   Definition 门）
❌ L0 原件写入
❌ 工作状态真值向恢复方泄漏（含经信息侧记录夹带）
❌ 四情况矩阵/测试六问变产品 API
❌ Gate① 复活 / G0-G3 实验重做（产物作为信息空间原样复用）
❌ 性能基准 / Corpus 扩容
❌ 预设「ES 必然必要」或「PALACE 必然足够」——两向皆开放
```

## 10. 任务 X / 任务 Y 提名标准（冻结）与提名时点

```text
提名标准（全部满足才算真实工作样本）：
  1 真实性   = 以秦沈真实语料为对象，答案可在 L0 中检验
  2 多路径性 = 存在 ≥3 条都合理但读取顺序/中间产物不同的
               探索路线（否则路径 X/Z/W 无意义）
  3 未答性   = 信息空间中无现成完整答案（否则六问被既有
               记录平凡回答）
  4 有界性   = Corpus-1（16 文件）范围内可达
  5 双任务性 = 任务 Y 与任务 X 不同质（不同信息需求 → 天然分叉）
具体提名 = 冻结审查时由 human 钉定（本草案不预占——防执行者
既提名又执行的选择偏差；示意方向[非锁定]：S8 未闭合项的独立
重查、RQ-OQB-2 相关整理风险实例采集）
```

## 11. Gate Sequence

```text
本设计草案 → human 冻结审查（冻结：矩阵/六问/停止点与恢复
             判据/禁令/任务提名/工作者承担方式/信息空间清单）
           → 执行授权
           → 信息空间钉定（清单落盘只读）
           → 四 case 真实工作（各自登记停止点）
           → 恢复探针（问答六问 + 接手续作）
           → 真值对照判读（五形态 × 六问 × case 矩阵
              + 残留资格清单 + 信息缺口/边界区分）
           → human 判读（含 ES 必要性状态更新与下一门处置）
```

当前执行授权 = 仅首实验（§12.5）；四 case 全量矩阵无授权。

## 12. 修订登记（human 冻结审查指令，2026-10-02）——首实验最小化

冻结审查 = 三项全 PASS（登记见文首冻结审查件）。本节按 human
指令收窄首实验范围并新增观察产物；§1–§11 冻结不变；§11 全量
序列保留，首实验结果门后回到 §11 全量裁定。

```text
PALACE-SIMIGO BOUNDARY STUDY
DESIGN STATUS: FROZEN
EXECUTION STATUS: NOT STARTED
EXECUTION AUTHORIZATION = FIRST MINIMAL A→B CONTINUATION
EXPERIMENT ONLY（四 case 全量 = NOT AUTHORIZED）
```

### 12.1 首实验范围（A→停止→B 接续，单一任务）

```text
范围收窄 = 只跑 Case-1 的 A 半程 + Case-3 的 B 半程：
  A：建立工作上下文 → 产生若干信息/文件/中间结果（沉淀自由）
     → 登记停止点（逐字）→ 主动停止
  B：只获得钉定信息空间（L0 + G0-G3 产物 + A 沉淀）
     → 尝试继续工作 → 行为逐条记录
  不跑：任务 Y（Case-2）、Agent cell（Case-4）、交叉探针
  工作状态真值照 §4 封存，事后核对 Evidence Table 归属
```

### 12.2 B 行为观察六类（human 原语，逐字冻结）

```text
· B 能直接继续
· B 需要重新询问
· B 能从文件恢复
· B 能从关系恢复
· B 缺少过程信息
· B 缺少 Execution State
记录方式 = 行为记录非自评（接手探针纪律延续）
注：「缺少 Execution State」为观察标签（= 接续在信息侧闭合
失败处中断）；是否归属 ES 仍须经 §7 闭合测试 + 残留资格规则
判定——类别标签不得当预设结论。
```

### 12.3 Boundary Evidence Table（首要新产物）

```text
列 = 缺失内容 / B 是否能恢复 / 缺失来源 / 初步归属
初步归属词汇 = PALACE / PALACE 候选 / ES 候选 / ES / 待验证
归属判读原则链（human 原文语义，冻结）：
  恢复不了本身不能证明属于 Execution State
  → 先问：PALACE 再多保存一条合法信息，B 是否就能继续？
  能 → 留在 PALACE
  信息已经充分 → 仍然无法恢复 → 不是知识缺失
    → 才进入 ES Boundary Candidate
  （= §7 闭合测试与残留资格规则的判读出口）
```

### 12.4 首实验禁令（§9 全部继承 + 本次新增）

```text
❌ 设计数据库 / PALACE Schema
❌ 决定大文件归属 / 设计多个子库
❌ 写 PALACE API / 把 PALACE 做成 RAG
❌ 修改 SimiGo Execution State（既有契约与产品线不变）
❌ 知识库必要性在本实验内判定（延后——第一步不是建立知识库，
   而是用真实接续实验确定知识库究竟需要保存什么）
```

### 12.5 Gate Sequence（首实验）

```text
第 0 步 任务提名（≥2 候选 × §10 五标准核验）→ human 钉定
→ A 半程（建上下文 → 沉淀 → 登记停止点 → 停止）
→ B 半程（仅信息空间接续 → 行为六类记录）
→ Boundary Evidence Table 构建 + 真值核对
→ 结果门 = human 判读（含：是否进入 §11 四 case 全量矩阵 /
   知识库问题是否开线）
```

首实验执行授权生效；四 case 全量仍无授权。

## 13. 第二次修订（human 方向，2026-10-02 同日）——Execution State 语义精化

登记件 = `SIMIGO_LAB_PALACE_SIMIGO_BOUNDARY_STUDY_DESIGN_REVISION_
EXEC_SEMANTICS_20261002.md`（human 方向逐字 + 三项冻结审查重跑
PASS×3）。§1–§12 文本冻结保留，本节为现行 operative 读法。

### 13.1 概念精化与不变量（human 原语）

```text
· Execution State 本身也是一种信息——具有执行语义的信息。
· PALACE = 信息空间；Execution State = 其中一种特殊的信息结构。
  区别在语义和可操作性，不一定是物理存储位置。
· 关键不是「⑥⑦⑧ 应不该放另一个数据库」，而是「PALACE 能不能
  保存它们，并且保持它们原本的 Execution State 语义」。
· 不变量：ES 的语义不能因为信息被存储、迁移、恢复、重新组织
  而丢失。
· SimiGo = 让具有 ES 语义的部分真正成为「可执行状态」
  （fork/restore/commit/discard/cancellation/physical
  representation——与 Contract v1.0-amended lifecycle 七操作
  为观察级呼应；Contract = MLX/runtime 冻结范围，SEPARATELY
  SCOPED，不作为本研究权威）。
· SimiGo 不是 inference engine；ES 不必然物理存放在 SimiGo 内部。
· 收束公式：ES 不再是 PALACE 的对立面，而可能是 PALACE 信息
  空间中最特殊、最需要语义保护的一类信息。
```

### 13.2 研究问题精化（human 措辞，冻结）

```text
父问（保留）= PALACE 能恢复到哪里，而 SimiGo 从哪里开始
    不可替代？
精确问（operative，冻结）= 一个真实工作的全部必要信息进入
    PALACE 后，其中哪些信息仅仅是可描述的，哪些信息必须
    保持 Execution State 语义才能继续执行？
```

### 13.3 首实验流程修订（human 原语，冻结）

```text
A 做工作 → 将工作完整保存到 PALACE 信息空间
→ B 从 PALACE 恢复
→ 观察哪些信息可以直接作为信息消费，
  哪些信息必须以 Execution State 语义恢复才能继续执行

变更点：
· A 半程从「沉淀自由」升为「完整保存」——工作状态项
  （human ①–⑧ 示例中 ⑥⑦⑧ 类：当前分支/执行位置/未完成
  操作）必须作为信息保存入空间。保存本身是实验设置，
  非自由变量。
· 观察轴从「缺什么」转为「语义存活」。
· 六问转置 = A 的保存清单（保证空间里有料）+ B 恢复时
  次级问答探针（答案存在性；答案五形态保留于此）。
  主判读 = §13.4 v2 表。
```

### 13.4 Boundary Evidence Table v2（取代 §12.3 v1 表）

```text
列 = 已保存项 / B 能否直接作为信息消费（可描述）/
     信息形态下 B 能否从此继续执行（语义存活）/
     若语义未存活：补一条信息记录能否恢复语义 /
     初步归属

语义存活判据（机械）= B 的续作把该项当「要从中继续的状态」
  还是「可知道的历史事实」；事实化后续作出现重推导/重决策/
  重执行/偏离 = 语义未存活。

初步归属词汇 = 语义可由信息记录承载（留在 PALACE 信息空间，
  含「执行语义信息」类）/ 语义需执行机制承载（ES——SimiGo
  语义域）/ 待验证

判读原则链（闭合测试转置，human 原文语义）：
  语义未存活 ≠ 自动归属 ES
  → 先问：补一条（或一组）合法信息记录，语义能否恢复？
  能 → 属信息可承载（PALACE 信息空间）
  信息已经充分 → 语义仍无法恢复 → 非知识缺失
    → 才进 ES Boundary Candidate
```

B 行为六类照 §12.2 记录；「缺少 Execution State」读法转置 =
「语义未存活」的观察标签（guard 不变：类别标签不得当预设
结论）。

### 13.5 判别力门（discriminating-power，既有纪律）

```text
语义存活轴要有观测点 → 任务必须自然产生 ⑥⑦⑧ 类事件
（分支选择/执行位置/未完成操作）。
执行第 0 步任务提名须核验此点；不满足 → 换任务，不硬做。
（可行性支持：human ①–⑧ 示例与 G2 T-1..T-3 真实任务形态
高度同构——finding/mapping/conflict 形态在案已真实发生。）
```

### 13.6 三项冻结审查重跑（修订后设计）

```text
① PASS = 父问保留、精确问唯一 operative；信息消费轴与 ES
  语义轴是同一问的两面，无第二问夹带
② PASS = 信息空间组成不变；「完整保存」更贴近 Tier-4 已证
  可行形态；①–⑧ 示例 ≈ G2 真实任务形态
③ PASS = 信息轴近饱和由 Tier-4 全保真先例支持（判别轴恰在
  语义）；语义/载体分离在案先例（P5：KV = Representation
  fragment 非 continuation carrier；PA-2：Position ≠
  Semantic Anchor——backend 范围，类比级锚点非证明）；
  CF-① 证明「记录在而语义错」操作性风险真实
→ RE-FROZEN；首实验授权延续（NOT STARTED；第 0 步提名门不变）
```

### 13.7 状态

```text
PALACE-SIMIGO BOUNDARY STUDY
DESIGN STATUS: FROZEN (REVISED — §13 operative)
EXECUTION STATUS: NOT STARTED
EXECUTION AUTHORIZATION: FIRST MINIMAL A→B EXPERIMENT ONLY
    (revised probe: full-preservation → recover →
     semantic-survival observation)
```
