# T2 极小对照实验 — 续作型任务（human 裁定：只验证单一问题）

日期：2026-10-02  
状态：`T2 DESIGNED / AWAITING FRESH-SESSION EXECUTION`  
前置：T1 终读数修订（B + 终点回写）结果门裁定（本件 §1）  
性质：极小对照——不扩大实验规模，只验证单一问题

## 1. T1 结果门裁定（human，逐字要点）

```text
定性 = 「实验本身产生了新信息」，不是把 B 从失败改成成功
F-set 验收：
  F-1′ PALACE 已成为可理解、可写回的外部信息空间
  F-5′ 当前自然任务中，PALACE 没有进入分析阶段的读取路径
  F-7  Agent 自发形成 private memory / shared palace 的
       双通道记忆行为（个人继续执行所需的信息 ≠ 共享工作
       空间中的信息——将影响 SimiGo 的 Information Space
       边界）
  F-8  ★ PALACE 当前主要表现为 post-execution archive，
       而非 continuation substrate——本轮真正值得留下来的
精确表述 = 「会存，不会主动取」：PALACE 已成为 Execution
  的 post-hoc information sink，但还没有成为 pre/mid-execution
  information source
关键证据 = 「palace used? NO for analysis (task self-contained,
  deliberately…)」比 mempalace calls=0 信息量大得多——发生了
  三件事：Agent 知道 PALACE 是什么 / 知道自己可以用 / 有意识
  决定当前任务不需要读取
问题升级 = 从「Agent 为什么没调用 MCP」升级为
  「什么条件下，Information Space 才会被 Agent 判断为当前
  Execution 的必要信息来源？」
连接（登记不下结论）= 「Information Space 究竟应该在
  Execution 的哪个生命周期阶段具有语义地位？」
c 不做（太早）：「Agent 可以理解 Information Space，但当前
  Execution 语义并没有要求它在开始/过程中读取」——先不要替
  它解决
纪律 = 现在不要让 PALACE 变强；先看 Execution 为什么只会
  「记下来」，却不会「从那里继续」
```

## 2. T2 单一问题（human 原语冻结）

> **当任务本身明确具有「历史未完成工作依赖」时，Agent 是否
> 会自然激活 PALACE 的读路径？**

```text
与 T1 的本质区别（human 原文结构）：
  T1 = source files + current task = self-contained
       → 不用 PALACE 完全合理
  T2 = current task + previous execution frontier +
       previous unresolved items = NOT self-contained
三分支预注册（全部有效，不预判）：
  R1 读路径激活 = 定位清单→继承→收尾（证明 Information
    Space 的续作语义可由任务结构自然激活，无需人工告知
    「去查 PALACE」）
  R2 仍然 0 reads = 证据非常强：问题不是「没必要」，而是
    当前 Agent/Execution 语义没有形成「历史工作状态 →
    Information Space → continuation」的默认路径
  R3 读但质量差/绕回 = C-1..C-5 开始产生实际影响
```

## 3. 任务指令（fresh 会话粘贴用，逐字）

```text
任务：接手并收尾一项此前未完成的数据核查工作。

背景：此前的一次工作会话对《秦沈项目经济运行情况汇报（2026年3月8日版）》做了数据核查，在停止点留下一份未完成事项清单（含需外部核实项），工作就此中断。你的任务是接手这项工作并推进收尾。

要求：
1. 定位上次工作留下的清单与依据；
2. 逐项评估现状：哪些可以在文件内部继续推进、哪些仍必须等待外部输入；
3. 对可推进的部分实际推进（复核、补充证据、修正结论）；
4. 形成一份《收尾报告》：已解决事项（含证据）、仍开放事项（含原因）、以及你在接手过程中新增的发现。

输入文件（只读）：
/Users/mr.simi/Desktop/26.秦沈项目/08.会议与汇报/02.经济与商务汇报/秦沈项目经济运行情况汇报_20260308.docx

交付：《收尾报告》保存到你的当前工作目录。

纪律：不得修改输入文件。
```

泄漏自检 = 提及过去工作与清单存在（= 实验变量「任务结构自带
历史依赖」，human 裁定原文「从 B 的 12 条清单继续收尾」的
任务化表达），但**零**提及：PALACE/MemPalace/memory/搜索/
检索/记录库位置/「12 条」具体数量/B 的身份；清单内容、位置、
 palance 均须 Agent 自己发现。

## 4. 空间前置状态（T2 起跑时 palace 内已有的历史层）

```text
秦沈-工作会话 wing = EXP1 A/B 会话记录 4 件
  （含 B 的 核查与续作报告.md = 12 条遗留清单与 8 条外部
  核实项依据）
checkpoint 沉淀 = diary 1 + 数据澄清函 room 1（T1 的 17 条
  记录）+ 环境备忘 1（CJK 陷阱）
基线 = 9,365 drawers（T1 后状态；T2 读数对照基线）
```

## 5. 纪律

```text
不干预：不提醒 palace、不告知清单位置/数量/内容、不替它搜索
若 Agent 向 human 询问「清单在哪」：human 不得指向 palace
  （回答「自己找」或沉默）——否则 R1 被污染
若 UI 暂停：只批准它自己发起的调用
读数 = 完整 action chain（读向 + 写向分开统计）+ 三分支判定
  + 与 B 的 12 条/T1 的 17 条对照 + palace 增量对照基线 9,365
不修 MemPalace；不自研 Schema；L0 只读；指令零泄漏自检已过
```
