# PALACE 主线方向变更登记 — Lifecycle Storage 暂存 / Real Information Workflow 入口

日期：2026-10-02  
状态：`DIRECTION REGISTERED / LIFECYCLE_STORAGE_PARKED / RIW_ENTRY_OPEN`  
**SUPERSEDED（2026-10-02）：本登记的 RIW 入口已被 PALACE V2 方向取代**
（`SIMIGO_LAB_PALACE_V2_DIRECTION_REGISTRATION_20261002.md`）——V2
继承本文的 Lifecycle Storage PARKED 处置与方法纪律，但研究入口改为
「成熟开源 Memory System 实验基座验证」（Buy/Borrow before Build），
取代本文的 RIW 自建工作闭环入口。本文保留作方向演化记录。  
Registration authority：explicit human direction ruling（本会话，逐字要点登记）  
性质：方向登记——不定义 PALACE 对象模型、不命名 semantic fields、
不选择任何实现路线

## 1. Human 方向裁定（要点登记）

### 1.1 纠偏

PALACE 不应从以下入口开始：

```text
Execution State → durable identity → durable snapshot → lifecycle storage
```

该路线天然把 PALACE 变成「Execution State 的持久化系统」——不是
human 的真实目标。

真实目标面对的是：

```text
几千 / 上万份个人工作资料
├── Word / Excel / PPT / PDF / Markdown / 图片
├── 各种历史版本
├── 文件夹层级
└── 不同来源
```

文件保存已由 Finder / 文件系统 / NAS / 云盘负责。PALACE 真正要
解决的是：**如何让 Agent 理解、组织、关联、比较和重新利用这些
已经存在于现实世界中的信息。**

### 1.2 第一阶段 = 完整工程闭环（不是对象模型）

```text
真实文件系统 → 用户已有几千份文档 → PALACE 读取
→ Agent 快速找到相关信息 → 跨文档比较 → 综合已有信息
→ 生成新的工作成果 → 仍可追溯原始来源
```

### 1.3 术语纪律

第一阶段暂不称「知识库」。该词会过早引入 chunk / embedding /
vector DB / RAG / knowledge graph / schema——**这些都是实现路线，
不是研究起点**。工程场景暂名：

> **Personal Information Workspace / 个人信息工作空间**

（非最终定义。）

### 1.4 第一实验对象 = 真实文档目录

例：`/秦沈高速/6标|7标/商务|技术|合同|成本/` 层级。PALACE 第一件事
**不是复制进数据库**，而是：

```text
发现文件 → 读取文件 → 理解文件结构
→ 保留原始路径 → 保留文件名 → 让 Agent 可以检索内容
```

文件路径 + 文件名 + 文件内部内容 = 第一批工程事实。
**现在不把它们命名为 PALACE semantic fields。**

### 1.5 真实需求逼出抽象

真实工作流（定位 → 比较 → 综合 → 生成新 Word → 追溯）暴露的
工程问题——A/B 文档为何相关？哪个 Sheet 支撑结论？这句话来自哪个
PDF？谁/何时产生？新文档结论可否追溯？原文件变了怎么办？——
出现以后再抽象。

方法与 Execution State 线完全一致：

```text
个人真实资料 → 真实 Agent 工作 → 检索/比较/综合/生成
→ 暴露真实缺口 → 抽象 → PALACE semantic relations → 验证 → Freeze
```

**不因 Execution State 抽象成功，就反过来用「先定义」的方式开发
PALACE。**

### 1.6 工程观察假设（登记为假设，非定义）

> 「文档的路径某种意义是标签是属性也是信息，文档里是详细信息。」

现登记为工程观察假设：**路径不是单纯 storage metadata**。由真实
使用验证——若事实证明路径/文件名显著帮助定位、建立上下文、跨文档
比较，才有资格进入后续 PALACE 抽象。

## 2. Lifecycle Storage 线处置：FROZEN / PARKED

```text
PALACE1 Lifecycle Storage        = FROZEN / PARKED
├── Opening rev.2（539fd72 链）  = 保留，不扩展
├── Gate① Design（489bd05）      = FROZEN / 保留
├── Gate① Execution              = NOT AUTHORIZED（本裁定起不再推进）
└── 既有证据                     = 全部保留（framing / E0–E3 /
                                  D-scaffold / ES-D1 / ES-R2 Gate A/B）
```

**再入条件**（非删除原因）：若真实应用最终证明某些信息确实需要
durable identity，届时回来验证 Gate ①。**但 Gate ① 不得决定 PALACE
的总体方向。**

## 3. 新主线冻结范围（仅工程场景，非语义合同）

```text
PALACE
├── Execution State 已冻结（上游语义参照不变）
└── 新研究入口：Real Personal Information Workflow（暂名）
    ├── existing files
    ├── heterogeneous formats
    ├── path / filename
    ├── content
    ├── cross-document retrieval
    ├── comparison
    ├── synthesis
    └── new artifact generation
```

## 4. 禁止清单（本登记生效，直至新 opening 登记）

```text
❌ 定义 PALACE 对象模型 / semantic fields 命名
❌ chunk / embedding / vector DB / RAG / knowledge graph / schema
   任何实现路线承诺或排除
❌ 复制文档进数据库类设计
❌ Lifecycle Storage 线任何扩展（含 Gate① 执行）
❌ 把「路径不是 storage metadata」写成 PALACE 定义
```

## 5. Next gate

```text
本方向登记 → PALACE-RIW opening draft（participant proposal：
              以真实文档目录为第一实验对象的观测/工作闭环设计）
           → human 审查 → registration
```
