# SimiGo v1.5 发布说明

日期：2026-09-19
依赖基准：mlx-swift-lm `dc3ca6197171`（Package.resolved pin）、mlx-swift
`0.31.6`；二进制 `7ccd136` 构建（v1.5 冻结基线，本版 Runtime 代码与
7ccd136 零差异）

## 本版主题：Conditional Restore 定版——分歧税从 300-490s 压到 ≈1×

v1.4 的 Branch-Fork 证明了"从已知正确状态派生新状态"的价值后，v1.5 把
这条思想落成生产主轨道：**Conditional Restore**（风险判定 → delta 规模
门 → checkpoint 恢复 → fragment-continuation），配合 prefill 阶梯恢复，
将历史分歧税（fork-no-rewind 909 万 tok/4 天、单事件 36-490s）压平。

## 变更清单

### Runtime（NativeMLX / Lifecycle）

- **Conditional Restore 主轨道**：每成功轮落 checkpoint（save 实测
  0.15s@58k）；下轮准入前 `rollforwardRisk`（账本尾部 assistant 含
  tool_calls 即风险——形状细化判据经 22,094 tok 生产逃逸实证退役）→
  `conditionalRestoreGate`（delta ≤ 8192 才恢复，大 delta 交回 extend）
  → 恢复后 fragment-continuation（raw-cache 无账本 → 结构性免疫分歧）
- **四重守卫**：kvFingerprint 对账 / rollforwardCompatible 内容对账 /
  sessionReplaced 身份守卫 / checkpointStale 兜底——任何一路不过即回退
  活会话 extend，无回归
- **prefill 阶梯恢复**：<64k→2048 / 64-96k→1024 / >96k→512；2048 深档
  悬崖（66.2k 处 54 tok/s）跨夜双样本确认消除（173/187 tok/s）
- **双口径 delta 估算**（log-only 门校准）：chars÷4 与 CJK 感知并行记录
- checkpoint/restore 失败全路径可观测（checkpointFailed /
  rollforwardFailed / skip reason 家族）

### 证据链（BENCH/EXPERIMENTS）

- Roll-forward Phase A：40 轮 1.7k→58k，fragment 恒定 1,701±9 tok，
  每轮开销 ≈0.16s
- Execution Continuity 三臂：derived/live 同深度比合并两夜样本
  **0.66–1.16（中位 ≈1.0×）**——恢复态剩余成本无数量级税（状态形态
  对照口径）
- F0 能力探针：MLX 公开面无 sequence identity（数据级 fork 双路封顶，
  63.6k checkpoint 1.53GB/1.94s）→ 上游 RFC 已提交
  （mlx-swift-lm#629）
- Post-Freeze Code Audit：P0×3 + P1×4 + 内存动态审查全部闭环
  （leaks 5.6MB/20.8GB=框架噪音级）

### 已知边界

- 2048 压平臂为已退役实验构建，n=1（登记在册，不可在当前二进制复跑）
- 恢复态 residual ≈0.8–1.2× 为受控 benchmark 状态形态对照结论，
  非 universal 承诺
- Execution Fork 真共享等待上游 sequence 原语（F1 前不进 Core）

## 验收

- 单测：58 执行 4 跳过 0 失败（Conditional Restore / rollforward 归一化
  / fork 边界家族）
- 三臂 n=2：derived 15/15 全通 + 连续性检查过；LIVE 9/9 全 extend
- DMG `hdiutil verify` VALID；内嵌 app 版本 1.5、codesign 校验通过
