# Conditional Restore 外部复审登记（第二轮）— 2026-09-19

## Scope

外部复审 `d4fd88c`（自 `7ccd136` 前进 5 commit：F0 探针闭环 + n=2
补 n + V1.5 终局决策）。**Runtime 代码未因本登记变更。**

## Executive conclusion

**通过，V1.5 可以冻结。** 无新增 P0/P1（Core）。

| 层面 | 判定 |
|---|---|
| SimiGo Core 代码 | ✅ 通过，无新增 P0/P1 |
| Conditional Restore 定版 | ✅ 成立 |
| n=2 证据 | ✅ 明显加强 |
| F0 方向判断 | ✅ 成立（问题被证伪而非功能未做） |
| 「MLX 公开面无真共享 fork」 | ✅ 基本成立 |
| copy() 成本表述 | 🟡 需收紧（P2） |
| 终局决策 | ✅ 成立，统计边界需写严（P2） |
| bench harness | 🟡 一个 P1 实验基础设施问题 |

## 特别认可

- 未因 llama.cpp 有 `seq_cp()` 就假定 MLX 可行——先探针后结论
- 停止线正确：不建 KV Tree / BranchManager / ExecutionState，
  避免「MLX Runtime + SimiGo Runtime + SimiGo KV Runtime」三套真值
- F0 零生产 Runtime 侵入（5 commit 仅 docs/ + tools/）

## 采纳的行动项

1. **P1（实验基础设施）**：`last_completion()` 时序竞争——HTTP 返回后
   trace 未 flush 会读到上一轮 completion，跨轮指标拼接；`before_lines`
   算而不用。修复：只接受本轮请求行位置之后的新完成行。
   `discover_key()` 未绑定当前 session，可能误抓并发会话完成行。
   修复：严格窗口 + 多 session 歧义拒绝猜测。
2. **P2（证据措辞）**：F0 文档区分三层——已证实（copy() = independent
   deep copy）/ 源码推断（ellipsis 切片惰性）/ 未实测（首次 eval 物化
   成本）；决策文档 residual 表述保持状态形态对照纪律。
