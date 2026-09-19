# V1.7-0 Runtime Benchmark Matrix（2026-09-19 开工）

**性质**：V1.7-0 首交付——systematic runner `tools/runtime_matrix.py`
（四路语义：Cold/Warm/Restore/Rebuild × 深度档 10K/40K/80K/120K ×
RAM/KV/Swap）+ 10K 冒烟结果 + 校准发现。

## Harness v0 已验证

- 端到端跑通：构建推深 → warm → restore → rebuild → cold → JSON 落盘
- 位置法完成行捕获（traceKey 短串免疫）、`[EXEC]` 血统行已被
  v1.6 Runtime 点亮（遥测与矩阵同源）

## 10K 冒烟发现（Cyber-Tiel，03:17 窗口）

| 路 | 实测 | 判定 |
|---|---|---|
| WARM（plain user 小 delta） | mode=rebuild，9,120 tok / 10.4s，cacheEff=0.00 | **非 extend**——账本失配触发重渲 |
| RESTORE（tool_calls 尾+小 delta） | mode=cold，18,493 tok / 24.3s，reuse=false | **restore 未触发**——账本已失配，退化为全新会话语义 |
| REBUILD（首消息变异） | mode=cold，18,066 tok / 23.2s | 符合预期（全量重渲基线） |
| COLD（全新 session 重放） | mode=cold，18,062 tok / 23.7s | 符合预期 |

## 根因假设（待校准验证）

**客户端回显形状分歧（cdd0272 类，机制此前已确认）**：harness 把
HTTP 响应的 assistant 消息（tool_calls.function.arguments 为 string）
原样回放，引擎账本存的是结构化 object → isPrefix 在首个带 tool_calls
的 assistant 处失配 → 之后每轮全量重渲。与 execution_bench 首跑
"轮间 assistant 回执入库缺失致全 cold"同族——**回显流的账本形状归一化
是矩阵测量的前置校准项**。

## 校准项（进入正式矩阵前必须关闭）

1. 回显归一化：harness 侧按引擎账本形状回放 assistant（或复用
   execution_bench 既定 recipe 逐字段核对）
2. RESTORE 触发路径回归 execution_bench recipe（n=1/n=2 已验证可稳定
   命中 fragment）
3. WARM-extend 需账本尾无 tool_calls 的前置轮（"不调用工具"指令轮）
4. swap 采样正则兼容 M/G 两种单位

## 分相计时验收项（V1.7-0 追加，2026-09-19）

正式矩阵每行除 wall/promptTime/ttft/cacheEff 外，落五相计时：
**tokenization / prefill / KV restore·materialization / MLX
compile-setup / generation**。其中 prefill≈promptTimeS、
generation≈wall−promptTime 可推导，新探针仅前三相。

- **前置条件**：上述四项校准先关闭。rootfix 最终回归 restore=24.6s
  实测 mode=cold/reuse=false——restore 未触发时该格只是第四个 cold，
  分相计时跑在失真路径上等于把 cold 精确测四遍。
- **已有数据注脚（10K）**：四条 cold 路 ~710–775 tok/s 线性
  （9.4K tok=13.3s；18K tok=23.7–25.4s），固定成本（tokenize/
  compile-setup）已被压得很小。分相计时的主战场是校准后的 restore
  真值格与 40K–120K 非线性拐点（10K 档 swap 已 3.5G / footprint 22G）。

## 结果文件

- `results_partial.json` —— 10K 冒烟原始数据
