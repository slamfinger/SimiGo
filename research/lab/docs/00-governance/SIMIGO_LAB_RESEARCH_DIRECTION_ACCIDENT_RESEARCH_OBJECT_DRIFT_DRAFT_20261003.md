# SimiGo-Lab Research Direction Accident Record — Research-Object Drift

日期：2026-10-03  
状态：**DRAFT / PARTICIPANT PROPOSAL / HUMAN REVIEW REQUIRED**  
关联草案：`SIMIGO_LAB_CORE_RESEARCH_OBJECT_REALIGNMENT_DRAFT_20261003.md`

本文只登记研究方向事故、根因与治理缺口。  
它不修改 R3 数据，不重跑 R3，不复审 R3，不删除实验记录，不授权
实验、实现、PALACE 集成或新研究线。

## 1. 事件分类

```text
事件类型   = Research Direction Accident / 研究方向事故
具体机制   = Research-Object Drift / 研究对象漂移
核心后果   = 辅助边界问题被误当作核心 continuation 问题推进
R3 实验有效性 = LOCAL VALID / BOUNDED / CLOSED
R3 研究地位   = bounded exploratory / boundary characterization branch
R3 核心资格   = NOT QUALIFIED AS CORE CONTINUATION VALIDATION
```

本事故不是“实验失败”。R3 的实验在其自定边界内可以是有效的；失败
发生在研究问题层级：严谨治理验证的是漂移后的对象，而不是原始核心
对象。

## 2. 漂移链

### 原本核心问题

```text
Execution State
      +
Information Space / PALACE 发生变化
      ↓
若影响计算延续性的条件仍然成立，
原 Execution State 能否真正继续已有计算？
继续结果的语义如何规定与判定？
```

### 漂移后问题

```text
Information Space 变化
      ↓
I / A / C 是否 BROKEN？
      ↓
哪些变化定向击穿？
哪些变化 HOLD？
复合变化是否存在 interaction？
```

两个问题相关，但研究对象不同。前者研究 continuation computation；
后者主要研究 condition sensitivity / boundary detection。

## 3. 根因分层

### D1 — 条件替代了 continuation

“可继续计算的条件”被逐步误当成“继续计算本身”。条件状态本是候选
观察层，却在研究推进中变成了研究对象终点。

### D2 — 易验证问题替代困难核心问题

`IS 变化 → I/A/C 状态` 具有机械化、可审计、结果清楚的优点。真正的
continuation 问题更困难：

```text
什么叫同一个计算？
哪些已完成计算可以保留？
哪些信息变化不会使既有计算失效？
continuation 是 resume / reuse / replay 还是其它语义？
如何证明没有偷偷重算？
如何证明延续结果符合规定语义？
PALACE 保存的信息是否真是 continuation 所需 Information Space？
```

研究易验证辅助问题本身不是错误；错误是让它替代核心问题。

### D3 — 缺少研究对象漂移闸门

既有治理严格回答了：

```text
这个实验是否被严格执行？
```

但缺少更上游的问题：

```text
这个实验是否仍在回答核心研究问题？
```

因此出现危险闭环：

```text
研究对象轻微漂移
      ↓
design freeze
      ↓
严格实验
      ↓
严格审计
      ↓
局部结果稳定
      ↓
更难发现研究对象已偏移
```

### D4 — 局部成功强化漂移

R3 的 BROKEN/HOLD/interaction 结果整齐、可复现、审计通过。这些局部
成功提高了路线“看起来扎实”的程度，但没有证明研究对象正确。

### D5 — PALACE 被错误剥离

核心问题中的 Information Space 本来应包含 PALACE 所承载的历史、文件、
记录、索引、摘要、session 上下文和变化信息。把它暂时隔离出主线的
建议，是由错误研究对象派生的二次方向错误。

## 4. 后果分级

```text
一级事故   核心研究对象漂移；
二级后果   大量资源投入次级问题；
三级后果   辅助实验结果被误读为核心研究证据；
四级后果   基于这些证据提出错误后续路线建议；
潜在最重后果 PALACE 被错误移出 Information Space 主线。
```

## 5. 不造成的后果

```text
不删除或篡改 R3 数据；
不宣称 R3 实验记录无效；
不把 R3 重写为失败实验；
不因方向事故修改历史结果；
不授权重新解释 R3 为核心 continuation 证明。
```

R3 的准确定位是：

```text
对 Information Space 变化及其对若干候选条件的影响，
提供一组受控、有限范围的边界观察。
```

它失去了作为核心研究证明的资格，但没有失去作为辅助边界资料的
证据价值。

## 6. 治理缺口修复：Research Object Alignment Gate

未来任何实验、实现或研究线在设计冻结前，必须先通过一个更上游的
检查：

```text
Research Object Alignment Gate
```

它先于 experimental design gate，只回答：

```text
1. 当前要研究的是不是已登记的核心研究对象？
2. 核心对象是否被悄悄替换成更容易验证的代理？
3. 计划产出能否改变对核心问题的答案？
4. 如果计划完全成功，最多支持哪一层 claim？
5. 如果计划失败，是否仍然值得执行？
6. 相关系统实体（如 PALACE）是否被错误移出对象边界？
```

最低通过条件：

```text
Core object named
    = 明确写出核心对象；
Proxy relationship
    = 明确代理与核心对象的关系；
Answer linkage
    = 说明结果如何连接核心问题；
Claim ceiling
    = 预登记结论上限；
Non-claims
    = 预登记不得主张的范围；
Scope entities
    = 明确 Execution State / Information Space / PALACE /
      continuation 的边界。
```

若不能通过，不得进入 design freeze。

## 7. 状态建议

```text
Research Direction Accident Record = DRAFT / HUMAN REVIEW REQUIRED；
Core Research Object Re-alignment  = 关联主轴草案；
Post-R3 Direction Gate             = SUSPENDED AS ROUTE INPUT；
R3                                 = CLOSED bounded exploratory /
                                     boundary characterization branch；
R3 core-validation qualification   = REVOKED AT DIRECTION LEVEL；
PALACE                             = CORE INFORMATION SPACE ENTITY，
                                     implementation NOT AUTHORIZED；
successor RQ                       = NOT ASSIGNED；
experiment authorization           = NONE。
```

## 8. Human decision points

human 需要决定：

```text
1. 是否接受本记录对 Research Direction Accident /
   Research-Object Drift 的定义；
2. 是否接受 R3 的新定位；
3. 是否接受 Research Object Alignment Gate 作为未来 design freeze
   前的强制前置；
4. 是否授权把本记录与 Core Re-alignment 一起提交；
5. 是否继续冻结实验授权。
```
