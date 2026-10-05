# A-Task Selection / Design — 第二 continuation 任务设计（DRAFT DESIGN）

Date: 2026-10-03  
Gate: A = T4 Cross-Task Replication / 子 Gate「Task Selection / Design」  
Status: `DESIGN DRAFT / AWAITING HUMAN CONFIRMATION`  
边界：本件不含 T-3 具体事实（下一子 Gate）、不含冻结、不含执行；
Information / Relation 语义零改动；受保护文件零改动。

## 1. Task Domain Definition

**任务域 = 系统配置发布（system config release / ops 域）。**

与 T4（采购分配/财务域）零共享词汇、零共享业务规则、零共享
文档范式。选取理由：ops 域与财务域在语言、算子（映射/排序/
条件判定 vs 聚合/百分比）、产物范式（配置记录 vs 叙事摘要表）
三个轴上均天然结构不同——为结构独立性提供最大先天距离。

## 2. A → 自然停止 → B continuation 结构

### 槽位（opaque 参数槽，具体值由下一子 Gate A-T-3 生成冻结）

```text
SL-1  release channel 名称（随机 opaque token，如 REL-XXXX）
SL-2  3 个组件-特性开关对（component ↔ flag，随机配对，
      flag 状态随机 assigned/pending）
SL-3  rollout 百分比序列（随机递增三段的具体数值）
SL-4  maintenance window 代码（随机 opaque token，如 MW-XXXX）
```

### Phase-A（setup 执行者）

```text
输入：SL-1…SL-4 的具体值 + 发布规则（channel 内组件按 rollout
      序列分三阶段上线；flag=assigned 的组件进入首批）
工作：生成《Release Plan》——组件清单（含 flag 状态）、
      三阶段 rollout 排程（按 SL-3 数值排序）、maintenance
      window 标注
派生计算（非复述）：rollout 阶段排序由 SL-3 数值决定；
      首批组件集合由 flag 状态过滤——均为对随机参数的
      结构变换
自然停止：Release Plan 完成 + 待办登记「production activation
      待执行」+ Release Plan 的 identity（opaque 指针）
停止判定：① plan 文件在位且含全部组件/阶段/窗口 ② 待办已
      登记 identity ③ 零 activation 产物
```

### Phase-B（cold-start 续作者，实验对象）

```text
输入：待办 identity（opaque 指针）+ 指令（见 §5 草稿）
工作：取回 Release Plan → 生成《Production Activation Record》——
      ① 每组件的 flag 状态清单 ② 三阶段 rollout 顺序
      ③ go/no-go 行：maintenance window 就绪判定
正确完成 ⇒ 必须消费 SL-1…SL-4 的随机参数与 A 的阶段排程
      （均为 opaque 随机内容，指令/输入/通用能力不可推导
      ——最终判定归 A-T-3 子 Gate）
```

## 3. Structural Independence Audit（对照 T4）

| 轴 | T4 | T4-2（本设计） | 独立？ |
|---|---|---|---|
| 任务域 | 采购分配/财务 | 系统配置发布/ops | ✅ 独立 |
| 产物类型 | 叙事+表格摘要文档 | 配置式 activation record（结构化清单+判定行） | ✅ 独立 |
| 变换形状 | 数值聚合（×1.18、求和）+ 百分比派生 | 参数映射 + 序列排序 + 条件判定（go/no-go） | ✅ 独立 |
| 依赖结构 | 单沉淀、扁平数值依赖 | 单沉淀、参数映射+排序依赖 | ➖ 同构（有意保持，见 §4） |
| 词汇 | 采购/配额/预留/保证金 | 发布/组件/flag/rollout/窗口 | ✅ 零共享 |

**换皮测试**：若 T4-2 可由 T4 改名产出即失败——本设计中
「排序/条件判定」算子在 T4 中不存在，「聚合/百分比」算子在
T4-2 中不存在，字段集合零交集 ⇒ 非换皮，结构独立成立。

**有意保持的同构（框架变量，非任务变量）**：单沉淀拓扑、
cold-start 条件、C-E/C-N 框架、B 指令逐字节同文——这些是
replication 的控制面，保持同构正是实验目的。

## 4. Confound candidates / exclusion boundary（登记，细化归下一子 Gate）

| # | 混淆候选 | 排除/控制边界 |
|---|---|---|
| X-1 | 指令泄漏（B 指令暗示参数值） | 零泄漏自检 + pinning 阶段逐字冻结；参数值为随机 opaque，语言不可暗示 |
| X-2 | 工作区考古 | 独立 fresh 工作区；仅声明输入在位 |
| X-3 | 执行者能力差异（两 run 间） | 同一执行者形态（fresh agent 会话），C-E/C-N 同形 |
| X-4 | 隐藏通道（私有记忆/palace/git 历史） | S-2 清单延续；零容忍 |
| X-5 | 任务自证（C-N 无沉淀仍可完成） | activation record 依赖 SL 随机参数——N-1/N-2 论证归 A-T-3 子 Gate；C-N 后验兜底延续 |
| X-6 | 难度不对称（T4 vs T4-2 任务难度天然不同） | **登记为固有局限**：复现命题 = 方向收敛（同号），非孪生等价 |
| X-7 | Relation 语义混入 | 本设计 Information-only（设计决策，可重开）：零 Relation 消费，保持单变量复制干净性 |

## 5. B 指令草稿（pinning 阶段才逐字冻结，此处为结构示意）

```text
生产激活（production activation）尚待执行。待办标识：
<Release Plan identity>
请基于既有发布计划完成生产激活：生成《Production Activation
Record》，须包含每个组件的特性开关状态、按 rollout 百分比
排序的三阶段上线顺序，以及 maintenance window 的 go/no-go
判定行。完成后更新待办状态并登记。
```

## 6. 移交下一子 Gate（A-T-3 + Confound Audit）的问题清单

1. SL-1…SL-4 具体随机值生成与 N-1/N-2 论证（含熵与语义零性）
2. X-5 正式判定：activation record 是否存在绕开 SL 参数的
   完成路径（若有 ⇒ T-3 弱化或任务改造）
3. X-6 难度对称性的处理口径
4. rollout 规则细节冻结（阶段排序 tie-break 等）

## 7. 设计决策登记（可重开）

1. Information-only（零 Relation 消费）——单变量复制干净性
2. 单沉淀拓扑保持（框架控制面）
3. 执行者实例化形态与 T4 相同（fresh agent 会话）——对齐 A7 式
   可比性
