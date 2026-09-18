# Execution Fork F0 探针结果（2026-09-19）

**性质**：只读探针实测 + 公开面源码审查（零运行时行为变更）
**二进制**：`7ccd136`（生产 App）；**依赖 pin**：mlx-swift-lm `dc3ca6197171` /
mlx-swift `0.31.6`
**模型**：Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e

## 1. 第一性问题的答案

> MLX 是否允许一个正在运行的 execution state，不重算共同 prefix 就派生
> 独立、可验证、可继续执行的 child state？

**答：当前公开面不能。** 两条已知路径都付全量代价：

| 路径 | 实测/源码证据 | 代价 |
|---|---|---|
| 磁盘 fork（生产 v1） | 63.6k 深度实测：checkpoint safetensors
  **1,527,836,839 B（≈1.53GB，≈24KB/token）**；save→file copy→load
  全程 **1.94s**（trace 在册） | 1.53GB 磁盘往返 |
| 内存 `KVCache.copy()`（仅测试轨） | 官方协议语义 = independent deep
  copy（**已证实**）；`KVCache.swift` L502 `s.map { $0[.ellipsis] }`
  为惰性 MLXArray 操作（**源码推断**）；首次 eval 的实际物化成本
  **未独立计时**（见 §5） | 推断 1×KV memcpy + 2×KV 常驻（未实测） |

**卡点定位**：不在 MLX eval 层（MLX 惰性图本可承载 COW 式物化），而在
**MLXLMCommon 公开 API 无 sequence identity 概念**——KV 归属与执行历史
之间不存在可操作的「sequence 标签」层，prefix 共享无从表达。

## 2. 公开面遍历清单（判定矩阵步骤 3/4）

- `sequence_id / seq_id / seq_cp / seq_rm`：**MLXLMCommon 全库 grep 零命中**
- 局部 range 操作：仅 `trim(_:)` / `isTrimmable`（GDN 混合不可 trim，
  与项目 lessons 一致）；无 seq_keep / seq_add / seq_div 同型物
- `copy()`：9 个子类全部逐层全量切片（BaseKVCache 强制子类实现）
- 持久化：`saveCache(to:)` / `loadPromptCacheSnapshot`——仅文件往返，
  无 in-process 快照导出（v1.4 协议稿已知欠账再确认）
- mlx-swift core（0.31.6）：无 cache/sequence 抽象（裸 MLXArray）
- mlx-lm 参照：cache.py 的 trim ✓（Swift 有）/ merge ✗（两边都无）/
  save-load ✓；llama.cpp unified KV pool / slot / seq_cp 元数据共享
  **在 MLX 系公开面无任何对应物**

## 3. 判定矩阵落点与下一步

命中**第一行**：「copy 增量 ≈ 完整 KV（数据级 fork）」→
1. 产出上游能力请求草稿：
   `UPSTREAM_ISSUE_DRAFT_kv_prefix_sharing_cow.md`（sequence identity +
   lazily-materialized shared prefix）
2. SimiGo 侧**停止在应用层堆真共享 workaround**；现有磁盘 fork v1
   继续作为显式分支工作流（省 prefill 语义）保留

## 4. 对 V1.5 终局决策的输入

- Conditional Restore 路线（delta 门 + fragment-continuation + 阶梯）
  residual ≈0.8–1.2×（n=2 已闭环）——生产机制无替代压力
- Execution Fork 真共享被上游能力封顶，**不构成 V1.5 的换代理由**
- 详见 `docs/decisions/V15_ENDGAME_DECISION_20260919.md`

## 5. 证据边界

- copy() 的「惰性物化 = 首次 eval 全量 memcpy」为源码语义判定，未做
  独立计时（需门控 host test 插桩；对判定无影响——两路都是全量代价）
- 磁盘 fork footprint delta 未测（handler 不发 [MEM] 行）；fork 后分支
  KV 是否常驻未量化（cacheLoad 行存在，LRU 列表确认注册）
