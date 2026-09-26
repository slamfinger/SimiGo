# SimiGo v2.0.0-beta — Release Notes

**测试版（Beta）** · 分支 `release/v2.0.0-beta` · tag `v2.0.0-beta` · 基线 main@632b1d9

## 一句话

v1.7 全部产品功能保持不变；新增**超规模大模型执行**能力——41.76 GiB 的
模型（超过 32 GiB 物理内存）在 32 GiB 的 Apple Silicon 上通过
OpenAI 兼容 API 正常服务，swap 全程平坦、压力绿、确定性可复现。

## 新增能力（v2.0）

- **超规模模型服务**：`qwen3_next` 架构且权重 ≥ 20 GiB 的模型自动路由到
  分段执行引擎（placeholder-first 加载、persistent-floor 推导、
  ResidencyController 驱动的段驻留 + INV-1 逐转移审计、严格 Execution
  State 会话——每轮消费绑定表示并逻辑推进）。
- 出货档位：6×8 层流式单元——实测 8.8 s/token、峰值 8.2 GiB、cache 0、
  swap 0（系统基线平坦）、压力绿。
- **驱逐时序修复**：段 forward 后立即压力驱回地板，消除 load-before-evict
  双占引发的系统性换页（2-12 GiB 振荡 → 基线平坦）。
- 已验证模型：Qwen3-Coder-Next-4bit（41.76 GiB）；其余模型走 v1.7
  原生路径，行为零变化。

## 产品功能保持

- OpenAI 兼容 API（Chat/Completions/Responses）、流式与非流式、
  多 Session/Branch、KV 与 Prefix Reuse、资源准入与缓存淘汰、
  Tool Calling 与 Governance、Capability Contract——全部不变
  （NativeMLX.swift 仅新增超大模型路由分支；其余零改动）。

## 已知限制（Beta）

1. 超规模路径的 usage 计数为 0（chat 层 token ledger 未接入直连路径——
   v2.0 GA 工作项）；内容与确定性已验证。
2. 超规模生成不可取消（贪心解码）；建议请求侧限制 max_tokens。
3. 单超大模型会话串行（内存本质约束）；fork/branch API 对超规模模型
   返回不支持。
4. 超规模模型无 KV cache——每轮全序列重算，上下文 >~650 tokens 后
   延迟线性上升（段级 KV/前缀复用为 v2.0 GA 方向）。
5. 流式输出按 token 文本块推送；`tokensPerSecond` 等遥测为直连路径
   实测值。

## 验证（真机 Apple M5 / 32 GiB）

- 产品回归：v1.7 全部构建与端点保持（NativeMLX 零行为变更）。
- 超规模 E2E：`/v1/chat/completions` 两次真实请求——200、内容一致
  （restore-replay 确定性）、TTFT/延迟符合预期（~11 s/token）。
- 严格 Execution State 自测：restore-replay 确定性、生命周期记录、
  INV-1（96-192 转移逐转移审计）全部 PASS。
- 引擎回归：SimiGo-Lab 87/87 测试 PASS。

## 安装

1. 将 `SimiGo-v2.0.0-beta.app` 拷入 /Applications。
2. 菜单栏选择模型目录（超规模模型自动识别，日志出现
   `[V2] oversized model detected`）。
3. 启动服务后按 v1.7 相同方式调用 API。
4. 依赖说明：v2.0-beta 依赖本地 `mlx-swift-lm`（分支
   `release/v2.0-beta-ml`，含分段执行 API）与 SimiGo-Lab 本地包——
   正式分发将切远端分支。
