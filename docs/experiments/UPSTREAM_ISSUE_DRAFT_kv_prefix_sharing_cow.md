# UPSTREAM DRAFT：KV prefix 共享 / sequence identity 能力请求（mlx-swift-lm）

**性质**：上游 issue 草稿（未提交；按项目先例格式登记）
**目标仓库**：ml-explore/mlx-swift-lm（或 mlx-swift 分层讨论）
**动机数据**：`EXECUTION_FORK_F0_PROBE_RESULTS_20260919.md`（F0 探针）+
`docs/lessons/kv-fork-checkpoint-experiment-2026-09-17.md`

## 请求能力

为 `KVCache` 家族提供**sequence identity / prefix 共享**层，使同一 cache
状态可派生多个执行分支而无需全量数据复制：

1. **分支派生**：`fork() -> KVCacheHandle` 语义——子分支与父共享未分歧
   prefix buffer，分歧后（update 写入）自动 COW 物化私有段
2. **参考先例**：llama.cpp `seq_cp`（同 stream 仅改 cells 归属元数据，
   零数据复制）+ unified KV pool 的 per-slot 容量治理
3. **为什么 MLX 惰性图是合适底座**：`$0[.ellipsis]` 切片已是惰性节点，
   差的只是所有权/共享语义——现语义是「首次 eval 物化整份拷贝」，
   请求的是「共享只读段 + 写时物化分歧段」

## 用例（真实生产数据）

- 分支工作流：35B 模型 63.6k 上下文 checkpoint = **1.53GB**；现磁盘
  fork 往返 1.94s、内存 copy() 全量物化——分支每多一条，KV 常驻 ×2
- 恢复态延续：fragment-continuation 已实证（TTFT 0.17–0.74s @
  fragment 17–209 tok）；真共享可把「派生新执行」从 O(context) 降到
  O(delta)

## 现状边界（已核实）

- MLXLMCommon 全库无 sequence_id/seq_cp/seq_rm 概念（grep 零命中）
- `copy()` 9 个子类均为逐层全量切片（惰性全拷贝，非共享视图）
- 局部操作仅 `trim/isTrimmable`（GDN 不可 trim）；无 merge

## SimiGo 侧承诺

不改 fork MLXLMCommon 内部；能力就绪前生产走磁盘 checkpoint fork
（已发布 v1.4），并保留全部 A/B 对照数据回馈上游。
