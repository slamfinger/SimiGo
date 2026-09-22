# 架构决策

这里记录已经做出的、具有长期影响的架构选择。

## 定位

架构决策不是 Bug 记录，也不是设计草稿。

它回答的是：

> **为什么 SimiGo 最终决定这样设计？**

## 证据链

```
Research / Observation
        ↓
Experiment / Evidence
        ↓
Finding / Lesson
        ↓
ADR / Decision
        ↓
Architecture / Invariant
```

决策可以来自工程事故、实验，也可以来自 SimiGo-Lab 的研究结论；但必须能够回溯依据。

## 建议格式

```text
标题
状态：提议 / 已接受 / 已废弃
背景
问题
候选方案
最终决定
理由
证据
代价
影响范围
关联研究 / 经验 / 实验 / 基准
```

## 晋升规则

```
Lesson / Finding
  ↓
Evidence
  ↓
ADR
```

只有已经有充分证据、并且需要长期约束后续实现的选择，才进入这里。

## 与 Research / Knowledge 的关系

- [Research](../research/README.md) —— 为什么我们知道
- [Knowledge](../knowledge/README.md) —— 已沉淀的知识层级
- [Architecture](../architecture/README.md) —— 当前系统是什么

## 已归档决策

- [V4_5_STABLE_FOUNDATION_BASELINE.md](V4_5_STABLE_FOUNDATION_BASELINE.md) —— v4.5 Stable Foundation 唯一权威架构指引全文（原 README.md，铁律 1–99 + 三平面模型 + 工具协议规范 + 生命周期收敛 + BatchedDecode 实验轨章程）。**已被 v5.0《核心架构白皮书》（README_base.md）取代**：99 条铁律收敛为 12 条核心不变量，Physical KV 与资源边界移交官方 ChatSession。保留作历史架构记录与设计依据溯源。
