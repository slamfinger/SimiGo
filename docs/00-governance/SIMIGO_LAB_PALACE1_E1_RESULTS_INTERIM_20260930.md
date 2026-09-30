# PALACE-1 E1 Results — Checkpoint Representation Loss (Interim: R0/R1 complete, R2 blocked)

日期：2026-09-30  
状态：`E1 PARTIAL / R2-R4 BLOCKED ON ISOLATION MECHANISM / AWAITING SECOND-LAYER`  
设计（预登记）：`SIMIGO_LAB_PALACE1_E1_RECOVERY_EXPERIMENT_DESIGN_20260930.md`  
执行记录：`/tmp/simigo-palace1-e1/observations.jsonl`（7 轮观测）；运行日志
`/tmp/e1-run{1..7}.log`；加法测试 = 产品仓 `SimiGoTests/Palace1E1Recovery
ExperimentTests.swift`（**未提交产品仓**，工作树保留待 human 决定）

## 1. 预登记对照（P-1…P-5，未因结果改写）

| 预登记 | 观测 | 判定 |
|---|---|---|
| P-1 R0 = IDENTIFIED | meta 三键完整可读：storageKey `default/5401315f…/main`、generation `c1185f0a-…`、modelId `peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX`；history 17 条；kvFingerprint/forkPoint ABSENT（与 E0 一致） | **CONFIRMED** |
| P-2 R1 = FAILED-FAIL-CLOSED | **三次独立复现**：`NSCocoaErrorDomain Code=4 "The file …safetensors doesn't exist"`（缺失文件即拒，generation/SHA 校验前即 fail） | **CONFIRMED** |
| P-3 R2 = CONTINUABLE-WITH-FULL-RECOMPUTE | **NOT OBSERVED**——三次被安全守卫拦截（见 §2） | BLOCKED |
| P-4 / P-5 | 依赖 R2 | PENDING |

## 2. R2 隔离机制的穷尽记录（守卫三次按设计拦截）

```text
M-1  TEST_RUNNER_HOME 重定向 → 测试进程 home = /Users/mr.simi
     （homeDirectoryForCurrentUser 不读 HOME env，读 pwd 数据库）→ 守卫拦截
M-2  全量 HOME= 重定向（xcodebuild 级）→ 同样无效（同因）→ 守卫拦截
M-3  sandbox-exec 写拒绝 profile（~/.simigo 与 HF cache deny-write）：
     独立验证有效（touch 探针被拒）；但嵌套进 xcodebuild 时其内部
     sandbox_apply 报 "Operation not permitted"（沙箱不可叠加）→
     包解析失败；叶子级沙箱（直接跑 xctest bundle）因 BUNDLE_LOADER
     宿主符号解析不可行
→ R2 需要的「写隔离」在当前授权内无可用机制。守卫三次全部按设计
  工作并拦截（capability boundary 的实验守卫本身就是有效证据）。
```

## 3. 已钉死的工程事实

```text
E1-F1  R0：纯 meta 足以识别 execution/branch/generation/model——
       44KB 侧车在 identity 层自足（P-1）
E1-F2  R1：原生 loadSessionCache 对缺失 safetensors fail-closed
       （三次复现，错误在 SHA 校验前的文件存在性检查）——原生恢复
       路径依赖 Physical Representation（P-2）
E1-F3  R1 失败 ≠ State 失败：R1 只钉死「原生 checkpoint 恢复路径的
       依赖」；R2/R3/R4 的协作重建问题仍未被实验触碰——保持 OPEN
E1-F4  安全守卫机制有效且必要：实验运行时产品侧写入路径
       （auto-checkpoint/pool export/trace log）真实存在，守卫拦截
       防止了对原始 ~/.simigo 的任何实验性写入
```

## 4. 副作用披露（诚实账目）

```text
✔ branch-checkpoints：前后 204 项不变；最新条目日期不变（Sep 20）
✔ prefix-pool：24 对不变
✔ 无探针残留；原始目录零删除/零内容修改
⚠ trace log：~/.simigo/logs/native_mlx_trace.log 被追加（start/stop 的
  MEM 行 ×3 轮运行——append-only，无删除；M-3 轮运行甚至未进入测试执行）
```

## 5. R2 执行的三选项（交 human 裁定）

```text
A  批准「加写模式」：允许实验向真实 ~/.simigo 追加新文件（不删不改
   既有 204 项；retention ownership-aware 会保护 probe key）——最便宜；
   实验后清理 = 删除实验产物（需再次授权）
B  批准一个 additive 产品改动：SIMIGO_HOME 式路径覆写 env（研究用途
   常驻）——隔离最干净，但触碰产品代码（与「不修代码让它通过」的
   纪律需要 human 豁免：这是改隔离机制，不是改恢复能力）
C  继续叶子级沙箱工程（宿主测试直跑 xctest + DYLD 注入）——不触产品
   不触原始数据，但工程量小时级、成功率不确定
```

## 6. Non-claims

```text
✔ 未宣称 meta.json 是/不是 State（E3）
✔ 未宣称 KV 可/不可重建（R2 未执行）
✔ 未把 R1 fail-closed 解释为「KV 是 State」（human 纪律遵守）
✔ 预登记 P-1…P-5 未因结果改写；P-3…P-5 标 PENDING 而非放弃
```
