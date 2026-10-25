
## Addendum — Floor>0 Escalated to Correctness; Floor Disabled — 2026-09-26

外部复审（对 exp/simigo2-experimental 最新 HEAD 的逐层核对）确认主结论，
并将 floor>0 标记为 P2 语义缺陷。复审后自查升级了严重度：floor 推导为
层级时，`units` 从 `floorCount` 起切——**地板层 0..floorCount-1 被加载
为真实权重却不属于任何流式单元，从未被 forward**（静默跳层；shipped
默认 floor=0 不受影响）。按复审建议改为单元级地板后，floor≥1 又暴露
更深的崩溃：`gather_qmm ... scales.dtype() == int32`（量化投影收到
int32 scales）。

处置（beta）：**floorUnits 强制为 0，floor 参数停用保留**——floor 0 即
实测最优（9.0 s/token @ 8.3 GiB，全绿），floor 重设计（含准入/驱逐顺序
与统一内存的互激问题）列为 GA 工作项。重测矩阵（floor 0，控制器路径）：

```text
unit 8 ×6   9,048 ms/token   peak 8,261 MiB   swap 0   pressure 1
```

全部判据 PASS（严格 Execution State restore-replay 确定性、INV-1 over
segments 192 转移）。复审预览的下一轮审计面（SimiGo2App → Engine →
ResidencyController → Execution State 四层第二状态源）已确认为重点——
app 聊天路径本轮已接入严格 Execution State，四层状态源审计具备条件。
