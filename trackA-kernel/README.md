# Track A — Kernel / Bandwidth（条件启动）

**开关**：exp06-roofline 判定 ≥3× 地板。

**研究问题**：本模型 GQA + causal mask + long-context shape 下，
MLX→Metal 当前执行路径离硬件可达带宽/计算效率地板的差距，能否由
kernel 层工作关闭？

**形态（报告 §5.2）**：MLX fork + Metal prototype；
`baseline.metal` / `candidate.metal` 同输入输出契约成对对比，
**不集成 SimiGo**。借鉴 FlashAttention 原则（减少统一内存往返 / tile /
online reduction / work partition / fusion）——回答"这个具体 workload
是否存在自己的 FlashAttention-like kernel opportunity"，
**不是重写 FlashAttention**。

**状态**：未启动（等 06 判定；若 ≤1.5× 贴顶则本 track 关闭并记录）。
