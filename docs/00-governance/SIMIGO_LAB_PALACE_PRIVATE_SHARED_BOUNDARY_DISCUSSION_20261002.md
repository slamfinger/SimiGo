# 私有—共享双通道边界讨论（F-7 裁定）— 从 T1/T2/T3 真实行为推导

日期：2026-10-02  
状态：`DISCUSSION DELIVERED / BOUNDARY FREEZE CANDIDATE AT HUMAN`  
授权：human 裁定（选 c；T4 缓办；序列 = c → 冻结边界 → b/Y →
d 收敛 → T4 待 SimiGo 接入后方有资格）  
性质：participant 讨论件——从真实行为裁边界，不先设计数据库；
全部规则为行为推导候选，非 Schema/定义

## 1. 裁定登记（human，逐字要点）

```text
c 先行原因 = T4 现在不能作为 Information Space 的冷启动对照
  ——SimiGo 未接入，当前验证对象仍是 MemPalace 数据库结构；
  现在做 T4 易把「MemPalace 已有能力」误判成「Information
  Space 已经成立」
F-7 触及的真正边界 = 什么信息因为「继续这个 Execution」而
  必须属于私有层；什么信息一旦产生就已经成为 Information、
  可以进入共享空间——这决定 SimiGo 接入 MemPalace 时
  Execution State → Information 的边界
方法 = T1→T2→T3 实际行为证据在手，反过来从真实行为裁边界
防偷换 = 不把 MemPalace 行为证据偷换成未来 Information
  Space 证据
```

## 2. 双通道沉淀/消费台账（T1–T3，逐条）

```text
T1  CJK 陷阱发现
    私有 = 陷阱+修法（可行动配方：LO 不识别系统字体需复制
           进 app 捆绑目录/本机仅 Songti SC·Heiti SC/docx-js
           lineRule 用 exact/行末全角？可能被丢）+ MEMORY.md 索引
    共享 = 环境备忘（事实形态）+ 数据澄清函 room（17 条工作
           记录）+ diary
T2  12 条清单消费（读：palace 搜索 + conversations 原文直读
    + git——三渠道自归因）
    私有 = cross-session-work-records-locations.md（检索指针：
           conversations 原文优先/信息空间 wing 命名/桌面语料/
           工作史谱系 A→B→T1→T2 收尾）+ MEMORY.md 索引行
    共享 = checkpoint：数据核查收尾 room（收尾报告+工作记录）
           + diary
T3  消费（读指针→三处记录位置→读 T2 收尾报告→自提平衡
    报告→palace 尽职检索确认无更新）
    私有 = t23 Edit 更新指针文件（工作史谱系延至 T3——
           活文档，三代持续维护）
    共享 = checkpoint：数据问询复函 room（2 抽屉）+ diary
palace 总增量 = 9,362 → 9,372（+10 抽屉/三代）
```

## 3. 行为边界规则候选（BR-1..BR-6，从证据推导）

```text
BR-1 同一事件按生命周期形态分拆 = 可行动配方（怎么修）
    → 私有；事实形态（发生了什么）→ 共享。T1 同课双投；
    分拆由 Agent 的生命周期语义选择，非内容被迫（修法本可
    共享——保守倾向登记）
BR-2 纯连续性元数据归私有 = 检索指针/路由表/工作史谱系
    ——离开「继续这个执行」的语境即无意义。T2 建立、
    T3 主动维护（活文档形态）
BR-3 产物即信息 = 完成的工作产品与记录在形成时即归属共享
    （三代一致：工作记录/报告全部入 palace）
BR-4 环境事实共享 = 影响任何后继者的机器/环境事实入共享
    （T1 环境备忘）
BR-5 读方向的钥匙当前在私有层 = 跨会话读激活由私有指针
    携带：T3 经指针进入；T1 无指针无需求无进入——
    共享空间不自我召唤
BR-6 双通道写入时机 = 会话收尾 ritual（checkpoint）；执行
    中途未观察到沉淀写入（T3 的 palace 触碰是读非写）
```

## 4. 核心问题的初步裁定（participant 提案，待 human 冻结）

human 问：什么因为「继续这个 Execution」必须私有；什么一旦
产生即 Information？

提议判据 = **执行者可替换性测试**：对每条信息问——换一个
执行者/下一次继续，这条信息是否仍然可用且仍被需要？

```text
通过测试 → Information（共享空间；形成即归属）：
  结论+证据、工作记录、环境事实、工作史——T2 收尾报告
  通过（T3 实际消费）；T1 环境备忘通过
不通过测试 → 私有连续性层：
  检索指针/路由表/谱系地图、进行中状态、个人操作配方、
  「我从哪继续」——T2 指针不通过（仅对继续者有意义）
  → 私有 ✓
边界检验一致：三代全部沉淀/消费行为与该判据无冲突
```

## 5. 动态含义（BR-5 的架构分量，登记不下结论）

```text
边界不是「什么放哪」的静态划分——读方向的激活钥匙当前
由私有层携带。对 SimiGo 接入的含义（登记非设计）：
Execution State → Information 边界必须包含「激活语义」——
ES 需携带「此处有相关历史」的信号，否则 Information Space
不被读（T1 形态）。T3 显示该信号可由私有指针携带并在世代
间传递——与「Information Space 尚未进入 Execution 语义，
只是工具列表里的陌生人」（T1 F-5）精确对接：T3 的进展 =
该语义经私有通道被 Agent 自己补上了
```

## 6. 非主张与限定

```text
❌ 不定义 Execution State；不设计 Schema/存储；不改
   MemPalace；Contract v1.0-amended SEPARATELY SCOPED
   （MLX/runtime 范围，不作为本讨论权威）
n = 三代、单一 Agent 世系、单一任务域——BR 规则为行为
   推导候选非证明
私有层持久性未验证（.zcode 记忆目录生命周期/跨机器迁移
   性未测——与 palace 持久性不对称，登记）
冷启动反事实未测（T4 缓办，待 SimiGo 接入）
```

## 7. 结果门待裁（human）

```text
① BR-1..BR-6 哪些升为冻结边界（哪些留观察）
② 执行者可替换性判据是否采纳为边界的操作测试
③ 冻结后按裁定序列：b/Y 解冻评估 → d 收敛登记
   （T4 待 SimiGo 接入）
```
