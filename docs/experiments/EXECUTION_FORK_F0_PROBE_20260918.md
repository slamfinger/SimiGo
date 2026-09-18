# Execution Fork F0：MLX prefix 共享能力探针（2026-09-18）

**性质**：设计登记（未动工）
**定位**：第一性问题研究方向的第一个可判定实验——回答
「MLX 是否允许一个正在运行的 execution state，不重算共同 prefix 就派生
独立、可验证、可继续执行的 child state？」
**前置**：
- `docs/decisions/BRANCH_FORK_PROTOCOL_DRAFT.md`（v1.4 磁盘 fork 已发布；
  `KVCache.copy()` 内存 fork 双向隔离已实证）
- `docs/experiments/BRANCH_FORK_ROLLFORWARD_EXPLORATION_20260918.md`
  （fork = 分歧免疫；roll-forward = 持久化 fork 的窄应用）
- `docs/lessons/kv-fork-checkpoint-experiment-2026-09-17.md`（A1-A4 验收）

## 0. 为什么是 F0

llama.cpp 的 sequence 模型（`seq_cp` 同 stream 仅改元数据、不复制数据）
指出了一条 SimiGo 尚未探明的能力边界：

- SimiGo 已实证的内存 fork 走 `KVCache.copy()`——**数据级复制**
  （≈175MB 级 snapshot，lessons 公式）
- llama.cpp 的 COW 是**元数据级共享**——同 stream copy 零数据复制
- 两者之间的差距就是 F0 要探明的：MLX 公开面是否存在（或可组合出）
  prefix 共享语义

Roll-forward Phase B、阶梯恢复、risk 判据修复等当前工作都是过程性问题
修补；F0 的答案决定 Runtime 演进走「继续堆分歧修复」还是
「Execution continuity 为纲，KV 只是资源」。

## 1. 实验步骤

1. **基线**：活会话 A 推进至 ~60k 上下文，记录 RSS / footprint
2. **copy 成本曲线**：同深度执行 `KVCache.copy()` 内存 fork，记录耗时 /
   内存增量——若增量 ≈ 完整 KV 大小（memcpy 级），证明当前仅有数据级 fork
3. **公开面探查**：遍历 MLX / MLXLMCommon 公开 API——sequence-id 归属、
   lazy copy、COW、cells metadata 级操作（seq_cp/seq_rm 同型能力）
4. **上游对照**：mlx-lm `cache.py` 的 trim/merge/extend 语义在
   MLX Swift 官方 API 的对应物是否存在

## 2. 判定矩阵

| 结果 | 结论 | 下一步 |
|---|---|---|
| copy 增量 ≈ 完整 KV | 只有数据级 fork | 产出上游 issue 草稿（COW / prefix-share 能力请求）；SimiGo 停止在应用层堆 workaround |
| 公开面存在元数据级操作 | 能力已备 | 设计 ExecutionState / sequence identity 最小切片（F1） |
| 公开面无可组合路径但内部可达 | 上游欠账 | issue + fork-no-rewind 数据作为动机证据 |

## 3. 边界

- 不重构现有架构（不建 BranchManager / Node / RefCount / Merge 全家桶）
- 不做 speculative decoding 语义混用
- 一个 parent → 一个 child，成功 promote / 失败 discard，不做 merge
- 探针为只读实验：零运行时行为变更
