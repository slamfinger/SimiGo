nodes-out Definition Recovery 已完成:commit e5bca86(RESIDENCY_NODES_OUT_DEFINITION_RECOVERY_20260922.md,已推送)。考古结论与你一致且更进一步——

## 核心发现:nodes-out 无任何原始定义可恢复

- Track B 全部 8 份文档:0 命中("nodes" 仅页恢复/共享驻留语境路过)
- Architecture 2.0 文档:"nodes" 0 次
- Policy Opening(20260921):0 命中
- M1–M4 results:有 node 粒度 residency 语义(resident/externalized 二态),但无 "nodes-out" 术语
- **唯一历史锚点:P0.1 Cost Unit Definition(2026-09-21,0b88517→fa28ab6)**:"nodes-out 挤出计价"=resident opportunity cost 三候选计价方案之一,提出当日即随三候选整体移出规范目标、归入 **Deferred**——从未定义、从未实现
- H-P1 开题(608c3cf)借为串行链占位:"答'节点/结构从 residency 系统移除后会怎样'",原文档自己标注"**待决**"

结论:Definition Lock 的性质不是"恢复"而是**首次正式定义**;历史依据仅三条:P0.1 挤出计价语境 + M3/M4 node 粒度 residency 二态语义 + H-P1 串行链占位描述。这实证了你的"定义不足"判断——该词从诞生起就没被定义过。

## Definition Lock 提案(逐答 5 问)

- **Q1 对象/通道**:锁定提案 = 节点外化通道(node externalization pathway)——capacity 驱逐时 EXTERNALIZE 在节点粒度上的通道;与 Track B 五元组执行态迁移正交(五元组 = KV+Identity+Position+NextInput+Continuation,仅 KV 驻留粒度维度受影响 → 迁移正确性可判定)
- **Q2 移除含义**:主提案 = **F(取消节点粒度外化/迁回通道)**;A(完全取消,与容量约束矛盾)/C/D/E 排除理由逐项入档;最终 A–F 由你裁定
- **Q3 KV 二态**:确认为候选实验模型,非原始比较域;审核确认前禁止用其推导结论
- **Q4 execution state**:按 Track B 五元组拆分列出;nodelist 只触 KV 驻留粒度
- **Q5 成本通道**:不继承 H-P1 J;新增候选 = 迁移/重编码成本、correctness 违例成本、粒度-字节数关系失效(78,246 KiB 节点计账单位失效);禁止塞进既有 J

## 请裁定(Definition Lock 三项)

1. Q1 提案(节点外化通道)是否接受?
2. Q2 移除含义锁定 F 还是改选?
3. Q3 KV 二态候选模型 + Q5 新成本通道清单是否批准进正式开题?

裁定后我按 10 节结构(①原始定义(本文考古)②研究问题 ③移除边界 ④execution state ⑤KV/node residency 边界 ⑥correctness ⑦cost channels ⑧继承关系 ⑨禁止解释 ⑩Exit criteria)写正式开题 DRAFT;Implementation/采数继续 LOCKED。
