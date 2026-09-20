# SimiGo-Lab — SimiGo 2.0 预研实验室

**性质**：预研实验仓（research lab）。装的是**未验证的实验与探针**，
不是产品代码，不构成任何版本承诺。
**产品仓**：`github.com/slamfinger/SimiGo`（1.x 线；1.7 build 5 已封版）。
**方向真源**：本仓
`docs/architecture/ARCHITECTURE_2.0_PRERESEARCH_20260920.md`（v1.2）——
各实验的研究问题、开关判据、验收标准以该报告为准，track 目录内
不重复维护。

## 边界规则（不可协商）

1. **实验室代码永不经过 1.7 发布路径。** 迁回生产的唯一通道：对应
   Level 门通过后迁入主仓另立版本；本仓使命完成后归档。
2. **主仓 vendor pin（dc3ca61）不出现在本仓任何工作流中。** 本仓依赖
   统一走 `~/Documents/mlx-swift-lm` 实验分支（branch / file:// 引用）；
   换 vendor 检出须 fresh derivedDataPath。
3. 实验记录沿用 F0 三段式：**探针 → 结果 → 决策**；2.0 材料（文档 +
   代码 + 记录）全部归档本仓。主仓 `docs/experiments/` 保留 1.x 史料
   （F0 探针、V17_RUNTIME_MATRIX），仅作跨仓基线引用。
4. 止损入档：任一实验结构性失败立即记录并关闭对应 track，不恋战。

## 结构（对应报告 §5/§6）

| 目录 | Track | 状态 | 开关/验收 |
|---|---|---|---|
| `exp06-roofline/` | 实验 06 剖析 | 未开工（第一优先，与 trackB 并行） | 实测/地板 ≤1.5× 关 A；≥3× 开 A |
| `trackA-kernel/` | Track A Kernel | 条件启动（06 开关） | Metal 原型成对对比 |
| `trackB-execution-state/` | Track B Execution State | **探针收官(2026-09-20,F1–F3):四项验收指标全过,模型级零税;转 F4 工程化** | Fork Cost / Restore Depth / Shared Page Ratio + 逐 token 一致性门 |
| `trackD-memory/` | Track D Adaptive Memory | 未开工（独立推进） | 预算放宽不引入 swap 劣化 |
| `runtime2-skeleton/` | Runtime2 接口占位 | 笔记态，`[future]` 不实现 | — |

## 远端

2026-09-20 建仓并推送私有仓 `slamfinger/SimiGo-Lab`（main）。
