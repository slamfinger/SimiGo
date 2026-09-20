# 实验 06 — 256K Prefill Roofline 对账

**研究问题**：MLX + Apple Silicon + Qwen3.5 35B（GQA + causal +
long-context shape）的 prefill 实测时间，离理论带宽地板还有多远？

**判据（预先钉死，报告 §5.2）**：
- 理论地板 = 理论字节搬运量（主导项 = attention K/V 重读，causal 下
  ≈ layers × heads × n²/2 × head_dim × bytes）÷ 芯片带宽上限；
- 实测/地板 **≤1.5×** → 贴顶，Track A 关闭；**≥3×** → 开启；
  中间地带 → 逐算子归因后定（判例规则待首份数据）。

**工具链**：Instruments GPU counters（逐 kernel 时间 + 显存流量）/
`powermetrics`（sudo，GPU 频率功耗）/ MLX `get_peak_memory` ·
`get_active_memory` 分相采样。

**附带归档项**：
1. 09-20 decode 劣化数据（42→4 tok/s @2K→237K，目前未入 docs）；
2. 512/1024/2048 三档机制复核——对"512 档更快 = 内存压力"假说证实或
   证伪（既有结果：`V17_RUNTIME_MATRIX/README.md:115`，机制未归档）。

**状态**：**测量计划已预注册(2026-09-20)**——
`MEASUREMENT_PLAN_20260920.md`:参数表(M5 带宽 153GB/s 已核实)、
公式集(含**权重重读补项**:chunked prefill 每 chunk 全量重读 ~20GiB
权重,小 chunk 下占主导,忽略会把"贴顶"误判成"kernel opportunity")、
M1–M5 测量清单、执行顺序。下一步:M1 本机基线(基线产自生产机,
跨机比值无效)。
