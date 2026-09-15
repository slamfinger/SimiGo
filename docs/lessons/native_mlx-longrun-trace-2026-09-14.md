# NativeMLX 长时运行轨迹复盘（2026-09-14 → 09-15）

**日期：** 2026-09-15
**模型：** peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e-MTP
**数据源：** `~/.simigo/logs/native_mlx_trace.log.txt`（tail -f 捕获，5538 行）
**覆盖窗口：** 2026-09-14 16:04:24 → 2026-09-15 11:35:44（约 19.5 h）

## 背景

用户贴出长期运行期的 NativeMLX 轨迹，要求分析代码运行情况、定位结构性问题。该窗口覆盖冷启动加载、12 个会话的多轮工具调用链、取消/异常分支，是评估引擎健康度与真实延迟形态的完整样本。

## 现象（总览）

| 指标 | 数值 |
|---|---|
| `[MLX] session=` 完成生成 | 458 次 |
| `[LC] RELEASED` completed / cancelled_by_client / cancelled_by_runtime | 458 / 8 / 2 |
| 引擎 ERROR / Traceback / panic / anomaly-state | **0** |
| `[TOOL]` 事件 | 1262（requested 420 / validated 421 / result 421 / rejected 1）|
| `rawB > emitB` | 458/458（全部）——语义预期，非吞没 |
| cold prefill / cacheEff 0.00 | 12 次（`mode=cold`）|
| fork-no-rewind telemetry | 34 次（`fork@common=X/Y`）|

引擎层 **零崩溃、零吞没错误**。458 次生成全部正常完成，生命周期序列在多个会话中反复复用同一 `s=`（无会话污染）。

## 证据

- `[MEM] afterLoad`：active≈19.3GB、cache=3124MB、**peak 31.34GB / swapUsed 峰值约 5.2GB**。swap 未随会话单调增长，无内存泄漏。
- **精确缓存命中路径**：12 次 cold（`cacheEff=0.00`）后全部转入 `mode=extend, reuse=true, cacheEff 0.80–1.00`，后续多轮工具调用维持高位复用。
- **byte 不吞没**：所有生成线 `emitB == rawB`；`rawEv=1`（single-turn 单 assistant message）稳定，未见"漏传 assistant tool_calls"退化。
- **工具链闭环**：requested(420) → validated(421) → result(421)，生命周期完整。
- TP/S 中位 **14.8**、max 39.7；prefillStep 分布 512/1024/2048（阶梯选档生效）。
- 配置（saved profile）：`ctx=131072、gpu=99、temp=1.0、topP=0.95、topK=40、flash=true、draftN=2`。

## 根因（唯一结构性瓶颈：冷预填 TTFT）

**12 次 cold prefill，TTFT 普遍 11–13 s（实测 12.4s / 12.9s）。**

与两因素绑定，非引擎缺陷：

1. **上下文规模**：默认 `ctx=131072 (128k)`，冷态全量预填。
2. **Qwen3.5 MoE 混合架构 rebuild**：`mode=rebuild` 出现 1 次，GDN 层因混合架构不可回卷必须全量重预填——**上游限制**。

`fork-no-rewind` 模式与 cold 场景并存（telemetry `fork@common=60601/60983` 等），是 >30s TTFT 的分布来源，属遥测观测非回归。

TP/S <10/s 共 50 次，全部集中在冷启动段（正常）。

## 处理方式

- 本次为观测/复盘，**无需改码**。
- 若需主动缓解冷 TTFT：可调小默认 ctx，或接受 cold 段 10s+ 的权衡（leverage = idleSuspendTimeout / 上下文规模，非引擎）。

## 失败方案

N/A（无工程变更；当前缓解手段为控上下文规模，与 README_base 既有策略一致）。

## 影响范围

- 仅冷启动 / fork-no-rewind 远端场景。
- `mode=extend`（411/458，90%+）：cacheEff 0.80–1.00，TTFT 正常。

## 长期结论

引擎健康度达标：458/460 请求正常完成，取消仅 10 次（8 client / 2 runtime），零崩溃/零吞没。
冷预填 TTFT = Qwen3.5 MoE rebuild + 128k 上下行的结构性开销，**非代码回归**。
杠杆在上下文规模而非引擎。

## 是否需要 ADR

否。当前缓解（控 ctx / idleSuspendTimeout）已是既有策略；若将来调整默认 ctx，再晋升为决策记录。
