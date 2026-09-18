# V1.5 终局决策：Conditional Restore 定版，Execution Fork 转上游依赖研究轨（2026-09-19）

**性质**：架构决策（对应审计行动项第 4 步）
**证据链**：审计 `3b74274` → n=2 双臂复跑 `512b32e` → F0 探针（本决策前置）

## 决策

1. **V1.5 停在 Conditional Restore 定版**：delta 门 + fragment-continuation
   + prefill 阶梯为生产分歧对策终态。依据：
   - residual overhead ≈0.8–1.2×（中位 1.0×，两夜双样本，`512b32e`）
     ——措辞纪律：此为当前受控 benchmark 的**状态形态对照**结论，
     不作为 universal restore overhead 承诺（外审 2026-09-19 §七）
   - 2048 悬崖死亡跨夜复认（66.2k：187/173 vs 旧 54 tok/s）
   - 15/15 + 9/9 全通，promote 后连续性检查过
2. **Execution Fork 真共享不进入 Core**：F0 判定「MLX 公开面只有数据级
   fork（磁盘 1.53GB 往返 / 内存惰性全拷贝）」，无 sequence identity——
   换代前提不成立。转研究轨并产出上游能力请求草稿
   （`UPSTREAM_ISSUE_DRAFT_kv_prefix_sharing_cow.md`）
3. **应用层纪律**：停止为「真 prefix 共享」堆 workaround；分支工作流
   沿用磁盘 fork v1（v1.4 已发布语义）；不建 KV Tree / BranchManager /
   ExecutionState 抽象，直至上游提供 sequence 共享原语

## 决策依据表

| 候选 | 数据 | 判定 |
|---|---|---|
| Conditional Restore 定版 | residual ≈1.0×，n=2 闭环 | ✅ 生产终态 |
| Execution Fork（真共享）进 Core | F0：公开面无原语，全量代价封顶 | ❌ 上游依赖 |
| 内存 copy() fork（v2）转正 | 2×KV 常驻 + 全量物化，收益仅省 1.94s 磁盘往返 | ❌ 维持测试轨 |
| 上游 issue | F0 判定矩阵第一行行动 | ✅ 草稿入册待提交 |

## 后续触发条件（何时重开）

- 上游落地 sequence identity / prefix 共享原语 → 重开 F1
  （ExecutionState 最小切片）
- 生产分歧形态出现 Conditional Restore 无法覆盖的新类（delta 门外的
  分歧源）→ 重开对策评审
