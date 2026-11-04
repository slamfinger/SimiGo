# 外审三轮登记：生命周期专项（2026-09-19）

**基线**：`main`（v1.5 发布 + Post-Freeze Audit 后 8 commit）
**结论**：V1.5 Core 通过，无新 P0；两个 P1 候选要求**先测试后架构**——
①generate() 与 suspendIfIdle() 生命周期竞态 ②挂起中间态恢复能力

## 采纳与执行状态

| 外审建议 | 状态 |
|---|---|
| ① 生命周期竞态测试 | ✅ 已建 `SimiGoTests/LifecycleRaceTests.swift`（门控
  `SIMIGO_LIFECYCLE_RACE=1`）；测试缝隙
  `RuntimeTuning.suspendIdleTimeoutOverrideSeconds`（默认 nil 零行为）；
  真机权重实跑：**击中挂起窗口 1 次，generate 全部存活**（24.4s，
  3 轮锤击×200 快打 + 挂起→自动恢复往返 + 重复挂起幂等） |
| ② 挂起中间态恢复回归 | ✅ 并入同文件：挂起→自动恢复→再挂起→重复
  挂起幂等全链断言；headless 侧补未加载实例 loadSessionCache/suspend
  不留半初始化状态回归 |
| ③ 发布产物与源码追溯 | ✅ 已有（DMG 随 tag v1.5 + Release Notes 注明
  二进制基线 7ccd136）；治理三行（源码仓库/Release/Git 历史不重写）
  登记于本文件 |
| ④ ExecutionPolicy 设计文档 | ✅ V1.6 规格 §3（数据/决策分离）已覆盖 |
| ⑤ ExecutionID 最小 PoC（只设计不迁移） | ✅ S1 落地为 log-only 遥测
  （独立新 ID，非现有 ID 升级——符合外审 §Identity 警示） |
| ⑥ KV Fork/COW 等上游 | ✅ 维持（RFC#629 在册） |
| ⑦ 大规模重构 | ✅ 暂缓 |

## 治理三行（外审 §四 采纳）

```text
源码仓库：源代码、测试、文档
Release：DMG、签名发布物（tag 对应 + Release Notes 注明二进制基线 commit）
Git 历史：暂不重写
```

## 下一轮代码审查焦点（外审指定，登记待执行）

`NativeMLX` 生命周期调用时序 → `LifecycleGates` 锁语义 →
`ManagedSession` 恢复路径。
