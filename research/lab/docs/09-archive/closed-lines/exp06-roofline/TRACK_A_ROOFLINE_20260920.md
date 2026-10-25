# Track A：256K Prefill Roofline 对账（2026-09-20）

**性质**：SimiGo 2.0 实验室预研；不进入 1.7 发布路径。  
**目的**：用可复核的算术而不是 GPU 利用率观感，决定 Track A（MLX/Metal kernel）是否有资格启动。

## 判定门

对每个目标 kernel / chunk 档：

- 实测时间 <= 理论带宽地板的 1.5x：**Track A 关闭**
- 实测时间 >= 理论带宽地板的 3.0x：**Track A 开启**
- 1.5x < 实测 < 3.0x：按 kernel 分布、算子归因、实际流量继续判断

地板时间：

`T_floor = Bytes_lower_bound / Peak_bandwidth`

其中 `Bytes_lower_bound` 是在给定张量形状、精度和 causal 约束下的理论最小数据搬运量，不是 Instruments 报告的实际流量。

## Attention 长上下文下的 K/V 下界

对 causal self-attention，token pair 数：

`P = N(N+1)/2`

若 K/V 使用 `H_kv` 个 KV heads、head dimension 为 `D`、每元素 `B` bytes，则只计一次 K 和一次 V 的理论读取下界：

`Bytes_KV_lower = L * P * H_kv * D * 2 * B`

其中：

- `L` = Transformer attention layers
- `N` = context tokens
- `H_kv` = KV heads（GQA 时不能误用 attention heads）
- `D` = head dimension
- `B` = element bytes

实际 tiled/fused kernel 可能重复读取 tile，因此 Instruments 流量应单独记录；不能用这个下界反推实际流量。

## 必测矩阵

同一模型、同一输入、同一机器：

- context：256K（必要时补 120K 作为已有基线）
- chunk：512 / 1024 / 2048
- precision：沿用生产模型实际精度
- warm/cold：至少各一组，生产基线保持一致
- 每档至少 3 次，报告中给 median；异常值单独列出

## 工具链

1. Instruments GPU counters：逐 kernel 时间、GPU memory traffic / counters
2. `powermetrics`：GPU 频率、功耗、系统状态
3. MLX 侧：`get_peak_memory` / `get_active_memory`，按阶段采样
4. 本目录的 `roofline_account.py`：统一计算带宽地板、实测/地板倍率、判定

## 结果表最少包含

| chunk | kernel | measured_ms | actual_bytes | floor_ms | measured/floor | peak_memory | decision |
|---:|---|---:|---:|---:|---:|---:|---|

## 设计输入

已有 1.7 证据中，预填步长已冻结为：

`<64K → 2048 / 64–96K → 1024 / >96K → 512`

本实验不是重新调参，而是验证为什么 512 在已有长上下文实测中优于 1024：是内存流量 / working-set / kernel 行为，还是其他因素。

## 边界

- 不修改生产 pin
- 不修改 1.7 Runtime
- 不以“GPU 利用率高/低”单独作 Track A 判据
- 不把理论下界当作实际内存流量
- Track A 只有在本实验门通过后才进入 Metal/MLX fork
