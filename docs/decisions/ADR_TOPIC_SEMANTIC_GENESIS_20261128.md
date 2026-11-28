# ADR：话题 Genesis 与近似语义归类（2026-11-28）

- 状态：Accepted（owner 2026-11-28 令「把决策同步到 simigo 仓，以你的研究进行代码实现」）
- 决策来源：IS `D510C61C`，承 `A36E988F`、`A6911144`、`47007ADD`
- 边界：不修改生产账本，不占用生产 `:8000`，不运行模型；本 ADR 不宣称分类准确率

## 背景

话题在 begin 时通常只有粗意图，无法准确枚举关键词。把“初始关键词”或“关键词组”作为话题身份的主表示，会在两个方向上失真：开局被迫猜词，后续又可能被同义改写漏掉。

owner 的口径是：话题头本身就是一段定义；后续粗会话再提取近似语义用于归类。例如“你好”是简单问候，“brief相关***”在上下文中属于 brief 话题。

## 决定

### 1. 话题 Genesis 存 defining paragraph

话题 begin 时创建不可变的 genesis：

- `topic_id`：稳定身份。
- `defining_paragraph`：自然语言话题定义，说明话题是什么、关心什么、大致边界在哪。
- `title`：显示标签，不是身份键。
- `seed_refs`：触发话题创建的轮次／消息引用。
- `reconstructed`：历史补建标记；新话题为 false。

关键词和 alias 不再是必需的主身份表示。alias 可以作为后续辅助信息追加，但不能改写 genesis。

### 2. 轮次或窗口另产 approximate semantics

每个参与归类的轮次／窗口记录：

- `turn_ref`：轮次或窗口引用。
- `approximate_semantics`：一句或一段粗语义标签。
- `context_refs`：为解析指代而使用的前文引用。

标签只回答“这段内容大概在干什么”，不做精确事实抽取。示例：

- “你好” → “简单问候／寒暄，无具体任务”
- “brief相关***” → “关于 brief 的话题；结合前文属于 brief 设计与实现探讨”
- “那个怎么实现” → 必须结合前文，不能孤立判为新话题

### 3. 话题归属是路由结果

`topic_assignment` 状态至少区分：

- `assigned`：归入既有话题。
- `new-topic`：明显的新意图，创建 genesis。
- `non-topic`：问候、寒暄等不构成工作话题的内容。
- `ambiguous`：证据不足，保留候选，不强行归类。

匹配以“轮次近似语义 ↔ 话题定义段”的语义关系为主，关键词／alias 为辅助。实现必须保持在线因果：第 k 轮只能使用 ≤k 的证据，不能事后移动已落账的归属或 fork 点。

### 4. 近似语义不得反写 Genesis

`approximate_semantics` 是路由元数据，不是 brief 的替代品：

- 不得从后期 digest 反提关键词来重建 genesis。
- 不得把标签中的值当精确事实。
- 话题范围澄清只能追加 `scope_clarification`。
- 有效定义 = genesis paragraph + 后续 scope clarification 的确定性折叠。
- 已提交字节不改；精确值仍由 L3 IS 原文负责。

## 最小数据模型

```text
topic_genesis(topic_id, defining_paragraph, title, seed_refs, reconstructed)
topic_scope_clarification(topic_id, clarification, source_refs)
turn_semantics(turn_ref, approximate_semantics, context_refs)
topic_assignment(turn_ref, topic_id?, status, candidate_topic_ids, evidence_refs)
```

既有 `deltas / segments / source refs` 模型保持不变；本 ADR 增加的是话题身份表示与轮次路由层，不把 brief 变成 turn/char 压缩检查点。

## 验证要求

至少覆盖：

1. “你好”归类为 `non-topic`，不创建话题。
2. “brief相关***”在有前文时归类到 brief 话题。
3. 无匹配且无明确新意图时保留 `ambiguous`，不伪造话题。
4. scope clarification 只追加，不修改 genesis 原文。
5. 同一话题跨会话可识别，parent 仍是话题链尾。
6. 近似语义与精确值分离：标签不进入 IS 原文真值面。

## 不做

- 不在本 ADR 中预设语义分类阈值或宣称模型准确率。
- 不改变 `turn_digests.keywords` 作为精确实体检索权威的地位。
- 不把 L52 的 L1 占位结果当作真实话题 brief 的判据。
- 不实现事后回移 fork 点或改写历史前缀。
