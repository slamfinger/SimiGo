# PALACE V2 G1 Real Corpus — Design Draft（秦沈真实文件工作闭环）

日期：2026-10-02  
状态：`DRAFT / DESIGN-FREEZE-PENDING-HUMAN（仅设计；无执行授权）`  
Gate：`PALACE_V2_G1_REAL_CORPUS（observation only）`  
授权来源：human 三项裁定（2026-10-02）——G0 CLOSED / Substrate W /
G1 UNLOCKED  
上游锚点：G0 AUDIT_RESULT（`9d49b88`）· V2 Direction Registration  
性质：participant design draft——冻结审查通过并获执行授权后方实验

## 0. §0 并发核验（执行前须重跑）

```text
设计登记基线 = 本文件入库 commit；执行前重跑 git fetch + 树净核验
```

## 1. G1 定义（human 措辞冻结，替代「知识库」叙事）

> **在真实秦沈文件空间中，观察 PALACE 是否能够支持连续的信息发现、
> 阅读、比较、版本识别与综合工作。**

不是：

```text
❌ 建立一个 500–3000 文件知识库
❌ 先设计知识库 → 导入 3000 文件 → 证明设计正确
```

而是：

```text
文件是事实源 → 建立最初可发现性 → 真实查询
→ 阅读 / 比较 / 综合 → 观察过程中出现什么问题 → 再抽象
```

## 2. 裁定登记（三项，2026-10-02）

```text
R-1  G0 = CLOSED / COMPLETE（G0 未替 PALACE 定义答案，
     只清理出未知空间——符合 SimiGo 方法论）
R-2  Substrate = W（substrate-agnostic / reference implementation）：
     Memory backend 降级为可替换实验组件，真实文件工作负载决定
     需要什么能力。裁定理由：非 X（防 G1 变成「修 MemPalace 的
     Excel ingestion」）、非 Y（防「PALACE 是否应该是一个 Graph」
     偏移——Graph 是已有实现方式非 G0 证明的抽象）、非 Z（组合=
     过早架构设计）。第一轮可选最简单、最易控 substrate，
     不要求本身是成熟 Memory System
R-3  G1 = UNLOCKED
```

G1 第一原则：真实文件工作 → 观察实际问题 → 抽象 → 验证。

**Execution State 定位（human 原文语义）**：Execution State 在 PALACE
里现在只能作为**可被现实重新「召回」的候选机制**，不是 PALACE 已经
拥有的答案。上下游关系：SimiGo = ES 抽象已冻结（验证其作为底层
能力）；PALACE = 先让真实信息工作发生，再观察是否自然产生需要
Execution State 的问题。

## 3. Corpus-1 选择：小型真实文件族（小闭环）

第一轮**不做 500–3000**；取一个有业务关联的小型真实文件族
（来源：真实秦沈项目目录，只读取证）：

```text
一个施工主题
├── Word：施工方案 / 技术文件
├── Excel：预算 / 工程量 / 成本
├── PPT：汇报材料
├── PDF：合同 / 规范 / 批复
├── 会议纪要
└── 后续修改版本
```

入选标准（预登记）：

```text
C-1  文件间存在真实主题关联（同一施工主题）
C-2  存在版本变化（同名/同主题文件的多版本或修订）
C-3  存在数字关联（预算-工程量-成本数字互相引用）
C-4  存在事实引用（会议纪要/方案/合同互相引用事实）
C-5  存在上下文关联（层级路径表达业务结构）
```

规模：以 C-1…C-5 满足为准（预估 10–50 文件）；数量不是目标。
隔离纪律：L0 原件**只读**（任何实验零写入原件）；工作副本与
沙箱 palace 置于 `.build/` 隔离空间；零真实数据外泄（本地运行）。

## 4. 实验链（G1 工作闭环）

```text
真实现有文件
     ↓
初始可发现性建立（substrate-agnostic：最简单可控方式；
     记录：文件在哪里 / 文件是什么 / 当前可发现内容）
     ↓
真实查询（human 示例任务冻结为 G1 主探针）：
  「找出目前成本控制方案中与原施工方案发生变化的部分，
    并说明这些变化来自哪些文件。」
     ↓
阅读 / 比较 / 版本识别 / 综合
     ↓
观察过程中出现什么问题（记录，不立即抽象）
     ↓
再抽象
```

## 5. 待验证假设（H Register，UNVERIFIED，不定义）

```text
H-PALACE-G1-01（动态索引假设）
  内容   = 查询产生的信息（已发现/已读/已比较）会反过来改变
          下一次查询的可发现性
  观察点 = 初始索引 → 真实查询 → 发现 → 新信息结构被发现 →
          下一次查询的可发现性是否变化
  状态   = UNVERIFIED；若成立，「动态索引」才从工作语言升格为
          观察事实（≠ 传统 文件→建索引→查询 单向链）
H-PALACE-G1-02（查询状态候选假设）
  内容   = 连续信息工作会产生需要持久化/继续/比较的查询状态
          （系统是否开始需要记住：已查过什么/为什么查/正在比较
          什么/接下来查什么）
  观察点 = 主探针任务的完整工作过程记录（多轮查询链）
  状态   = UNVERIFIED；若成立，Execution State 作为候选机制
          获得工程事实——届时才是与 SimiGo 冻结抽象对话的时机
```

两假设均不预设实现（无 Dynamic Index Schema / 无 PALACE State
Schema）；观察载体 = 工作过程全记录（查询序列/发现序列/比较
动作/版本识别动作）。

## 6. Evidence Grade

```text
Observation = 工作过程记录 + 系统行为（发现/检索/比较动作）
Inference   = 需求/缺口判断（须替代解释排除）
Open Question = 未验证
禁止：Observation → 直接升级 → PALACE 必须有 XXX
```

## 7. Prohibitions（逐字冻结）

```text
❌ 提前定义：Knowledge Base / Information Object / Relation /
   Graph / Provenance Schema / Dynamic Index Schema /
   PALACE State Schema
❌ 第一轮导入 3000 文件 / 追求数量
❌ substrate 绑定（W 裁定生效；MemPalace 仅可作为已观察基线参照）
❌ 修改 L0 原件 / 真实数据外泄
❌ 把 Execution State 写成 PALACE 已有答案
❌ Gate① / V1 Lifecycle Storage 复活（再激活条件不变）
❌ 性能基准
```

## 8. Gate Sequence

```text
本设计草案 → human 冻结审查（一次）
           → 执行授权（独立状态转换）
           → Corpus-1 选族（按 C-1…C-5 在真实秦沈目录只读取证，
             选族清单交 human 确认）
           → 初始可发现性建立 → 主探针任务执行（工作过程全记录）
           → 结果门（工程事实 + 观察登记，无追加实验）
           → human 第二层判读（H-G1-01/02 判定 + 下一步方向）
```

当前无执行授权。
