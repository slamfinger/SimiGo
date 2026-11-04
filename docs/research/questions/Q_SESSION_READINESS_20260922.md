# Research Question：Session Readiness 是否应成为独立生命周期语义（2026-09-22）

> 预注册研究问题。本文不改变实现，不把 rawEv == 0 提升为正式语义。
> 研究目标是判断：SimiGo 是否需要一个显式、可观察、与 Physical KV 实现解耦的 Session Readiness contract，以阻止“对象存在但不可复用”的状态进入生产复用路径。

## 1. Research Question

在当前 SimiGo + 官方 ChatSession 语义下，能否用一个最小的显式 Readiness 状态模型稳定区分“已注册但尚不可复用”“可复用”“正在执行”“已失效”，并避免把 Physical KV 内部状态重新纳入 SimiGo 的第二套事实来源？

目标状态模型：

ABSENT → READY → RUNNING
           ↘ INVALID

- ABSENT：不存在可用 Session。
- READY：满足复用资格，可以被后续请求选择。
- RUNNING：正在被请求使用；不是“可任意复用”的同义词。
- INVALID：曾被注册/使用，但已不能安全进入复用池。

## 2. Scope / Population

- SimiGo 的 Session 生命周期与复用资格；
- 新建 Session 的首次 prefill / stream readiness；
- cancellation、failed prefill、successful completion 后的 readiness；
- 同 key 后续请求的 reuse selection；
- 当前 pinned MLX / mlx-swift-lm 组合；
- Apple Silicon 真机运行。

不研究：Physical KV 内部实现、官方 ChatSession token ledger 的重新实现、Prefix/Radix Cache、Batch Scheduler、Agent memory、future upstream API 预测。

## 3. Existing Knowledge

1. 2026-09-17 真机事故证明：新建 Session 在 prefill 未成功完成前被取消，如果对象继续留在池中，后续同 key 请求可以命中该对象并进入长时间无输出状态。
2. 最小修复在真机验证中通过：rawEv=0 的新建 session 被逐出；同 key 下一请求重新建立健康 session。
3. 复用路径的中途取消表现不同：已有对照显示官方 rebuild 可以继续完成，因此不能把所有 cancel + rawEv=0 归为同一种“毒 session”。
4. 当前 rawEv == 0 只是诊断辅助判据，不是完整 readiness 语义。
5. 当前 Knowledge invariant 已明确：Session object existence ≠ Session reuse readiness。

## 4. Unknown

- 首次 successful stream event 是否足以作为 READY 的可靠证据；
- prefill 完成与 stream event 之间是否存在必须区分的状态；
- failed generation、protocol rejection、model error、client cancellation 各自应进入 READY 还是 INVALID；
- READY → RUNNING → READY 的转换是否需要显式 commit point；
- readiness 是否能够完全独立于 Physical KV token count / cache telemetry；
- 一个最小状态模型是否能覆盖所有生产终止路径，而不产生第二套生命周期权威。

## 5. Evidence Channels

### C1 — Historical real-device incident / A-B evidence

观察对象：真实 Session 池与同 key 后续复用行为。修复前被 cancel 的新建 session 被再次 reuse 并连续挂死；修复后逐出后同 key reuse=false、冷重建成功。性质：直接运行时证据。

### C2 — Controlled lifecycle matrix

计划建立最小受控矩阵：

| Initial state | Event | Expected readiness |
|---|---|---|
| ABSENT | register, no execution | not reusable |
| registered | prefill succeeds | READY |
| registered | prefill cancelled | INVALID / evicted |
| registered | prefill fails | INVALID / evicted |
| READY | request starts | RUNNING |
| RUNNING | successful completion | READY |
| RUNNING | cancellation | depends on reusable execution-state validity |
| READY | idle eviction | ABSENT |

该通道观察的是状态转换本身，而不是具体 KV 内容。

### C3 — Production trace / regression observation

观察长期运行中的 reuse decision、readiness transition、cancellation、release、subsequent same-key reuse、poisoned-session recurrence。

C1/C2/C3 不是三个自动独立的证明。独立性必须根据具体观察对象、数据来源和实验协议逐项判断；同一 trace 重新命名不得形成独立证据。

## 6. Falsification Conditions

1. 某个 READY Session 在没有 Physical KV corruption 的情况下仍能稳定进入不可复用状态；
2. READY 的判定必须读取 SimiGo 不应拥有的 token-level Physical KV 内部事实；
3. successful prefill / stream readiness 无法稳定区分可复用与不可复用；
4. 某种正常生产路径要求“未 READY 的 Session”进入复用池；
5. 显式 readiness 状态与官方 ChatSession 生命周期语义发生不可消解冲突。

## 7. Acceptance Conditions

- 所有已知 cancellation / failure / completion 路径都有明确 readiness 结果；
- 同 key reuse selection 只接受 READY；
- 不依赖第二套 token ledger / Physical KV authority；
- C2 受控矩阵通过；
- C3 长时回归没有复现已知 poisoned-session 模式；
- 任何新增状态都有可解释的生产事件，而不是为了覆盖测试临时增加。

## 8. Expected Finding

当前仅允许登记为假设：

**H1：Session Readiness 是 Logical/Execution 生命周期语义，而不是 Physical KV 语义；因此可以用最小显式状态模型表达，并在不拥有第二套 Physical KV authority 的前提下控制 reuse eligibility。**

H1 尚未被证明。

## 9. Boundary With Existing Knowledge

本问题不重新研究 cancelCommitSkip 的 history 提交不变量、Physical KV official ownership、Execution Fork shared-prefix capability。

它只研究一个交叉边界：

**Session object lifecycle → reuse eligibility**

## 10. Research Discipline

在 C2 完成前：

- 不新增复杂 Session State Machine；
- 不把 rawEv 改名成 ready；
- 不增加 token-count-based readiness；
- 不恢复本地 KV ledger；
- 不以单次成功运行宣称 Core invariant 已证明。

研究结果应进入 Observation → Finding → Invariant update（如有必要），而不是 Observation → implementation expansion。

## 11. Current Conclusion

**OPEN / PRE-REGISTERED**

已有强实机动机，但当前仍缺少系统化生命周期矩阵。下一步是建立最小 C2 controlled lifecycle matrix，然后用 C3 生产 trace 做反证和边界覆盖。

关联知识：INVARIANT_SESSION_READINESS_BEFORE_REUSE.md；cancel-mid-prefill-poisoned-session-2026-09-17.md；FINDING_SIMPLIFICATION_REDUCES_RUNTIME_AUTHORITY.md；INVARIANT_LOGICAL_PHYSICAL_STATE_SEPARATION.md
