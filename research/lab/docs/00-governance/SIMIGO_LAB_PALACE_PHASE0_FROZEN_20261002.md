# Phase 0 Semantic Surface = FROZEN — 终裁封存

Date: 2026-10-02  
Status: `PHASE 0 SEMANTIC SURFACE = FROZEN`  
Chain: REGISTERED → REVIEW IN PROGRESS → Finding-1 → 服务树重锚 →
语义结论全部存活 → **FROZEN**

## 1. human 终裁理由（逐字要点）

翻转条件满足的依据**不是**「原审计件没问题」，而是：

1. **发现并纠正了证据树错误**——3.3.3/48 模块 vs 3.10.0/126
   模块的偏差被显式登记，没有隐瞒
2. **重锚到实际服务代码**——§2 每项均有
   `file → function → behavior` 级服务树证据
3. **重锚后语义结论没有反转**——content_date、id_recipe 等暴露
   了原树遗漏，但未导致四类（Information / Execution / Index /
   Physical persistence）重新分类
4. **borderline 仍保持 borderline**——wing/room/hall 未被强行
   纳入或排除
5. **§6 冻结粒度没有越界**——冻的是语义原则，不是提前冻
   Swift API/schema

## 2. Finding-1 = 正式审计教训（长期纪律，不得修正后抹掉）

> **以后所有涉及 MemPalace 行为的研究，代码基准必须首先确认：
> 实际运行的 service tree / environment / version。**
>
> 不得假设用户环境里安装的 Python package 就是实际服务代码。

本教训的价值判词（human 逐字）：这次发现本身强化了 Phase 0
的价值——如果直接开始 Swift 重写，旧树上的错误观察很可能已经
进入新架构。

效力范围：适用于后续全部 Phase 1+ 源码证据动作与 T 系列后续
轮次的代码基准声明。

## 3. 冻结效力

```text
Phase 0 Semantic Surface = FROZEN
  ├─ §2 三分表（服务树锚点版）= 语义事实基线
  ├─ §6 分级冻结生效：
  │    taxonomy  = 开放设计边界（不入 Core 本体）
  │    diary     = 分层原则冻结 / schema 开放
  │    KG        = 事实冻结 / 一等身份不冻结
  │    activation= 存在事实冻结 / 形状开放
  │    Swift API = 保持开放
  └─ 审计件范围表述更正（48→126 模块、锚定树更换）= 有效
```

## 4. Phase 1 Gate

```text
Phase 1 Swift Core = NOT YET DESIGNED / awaiting boundary 裁定
```

下一动作 = **Swift Core 最小边界裁定**（不是写 Swift）：

依据已冻结语义面裁定——

**必须进入 Core 的语义候选**：`Information`（identity / content /
provenance / time·content date）、可持久化的 Information 生命周期、
`InformationStore` 必须表达的操作。

**明确不进入 Core**（初始清单，human 列）：Chroma/HNSW、BM25、
entities、closet、hallway、Memory taxonomy 具体组织实现、
activation 具体机制、diary 具体 schema、KG 一等最终设计、
MCP tool 表面、MemoryStack 历史实现结构。

裁定完成前不产生任何 Swift 文件。

## 5. 未变项

T4 = BLOCKED；边界冻结 BR-1/2/3/5 不变；Git 本地不推送。
