# BACKEND-1 Adapter Engineering Round 1 — External Review

日期：2026-09-30  
Reviewed artifacts：

```text
audit  = SIMIGO_LAB_BACKEND1_ADAPTER_ENGINEERING_AUDIT_20260930.md（7f1fa4a）
impl   = LLAMAServerExecutionStateAdapter.swift（2cf5adb）
tests  = LLAMAServerExecutionStateAdapterTests.swift + evidence JSON（5b47ea8）
base   = adapter engineering opening registration 5ab7247
```

Verdict：`PASS / REGISTRATION_REQUIRED`  
Role：external methodological review only

本文件是 review decision，不是 repository registration。PASS 不封 engineering
round 1、不授权扩大实现、不改变 contract、不构成 performance 或 portability
claim。

## 1. Review basis

Human second-layer verdict（2026-09-30，先行记录）：认可 `SUFFICIENT（有界）`，
A1–A8 全 PASS（A5/A8 有界），进入 External Review。本 review 按其固定的四个
审查点独立核验，不重复工程审计，也不以其裁决替代本审查。

审查边界（human 指令，遵守）：不修改 contract，不扩大测试面。

## 2. 四个审查点

### R-1 `SUFFICIENT` 是否被当前证据真正支撑

PASS。支撑链完整：

```text
E1 七生命周期 + 四事务窗口（契约既有，19/19）
+ E3 四操作（三异构 backend 同 battery，3/3）
+ 真实 transport 组合体实际穿透 seam（adapter battery 14/14）
+ A2 状态围堵（无 D 化）+ A5 取消 containment + A8 restore→continue 闭环
= 现有 seam 承载了本 adapter 类的全部工程职责，无一处需要改 contract
```

`SUFFICIENT` 的适用域被正确限定：本 adapter 类 = server-owned-weights +
prefix-recompute 策略。B1 未参与被裁定为能力边界行为而非 seam 缺口（见
R-3），因此「E1+E3+B1 seam 足以承载」成立且未被削弱。

### R-2 adapter 是否夺取了 Execution State ownership

PASS。结构证据：

```text
1. ExecutionStateHandle 全 let 字段（ExecutionContinuityContract:70-75），
   不存在被 adapter 写入的路径
2. adapter 全部语义变更经 coordinator 公共 API
   （create/continueExecution/fork/restore/reattach/discard）——它扮演的是
   host-side composition，不是语义层
3. adapter 自有状态（pipelineLock/stateLock/openState/modelIdentity）全部
   私有，R/T/P 层，不触碰任何契约类型
4. M-2 direct-entry 检查已被测试：foreign 与 mispositioned derive 在直连
   路径上双双 fail closed（testDeriveForeignAndMispositionedFailClosed…）
```

A2 与 A8 同时成立（human 指出的关键组合）：架构隔离没有被「能跑」稀释，
真实通路也没有破坏隔离。

### R-3 B1 不参与是否有明确 architectural justification

PASS，且理由具有登记价值：B1（`RuntimeResidencyBackend`，
RuntimeBackendContract:43-67）面向 layer-group 物化与内存对账；llama-server
自身拥有模型权重及其物理生命周期，若强行在 adapter 实现 B1，adapter 必须
声称一份它并不拥有的物理所有权——那才是真正的所有权失真。

由此登记一条 seam 原则（随本 review 固化）：

> **Seam 是能力边界，不是强制组件清单。** 未来 backend 按其真实物理所有权
> 决定接入哪些 seam 面；不为「接口完整」制造虚假 B1。

同时钉死反向误读：B1 仍是 registered seam 的组成部分；本轮未行使 ≠ B1 可
废弃。未来 client-side 物理状态型 backend（如本地 KV 复用策略）预期会行使 B1。

### R-4 证据是否被叙事性夸大成 universal portability

PASS（含一处术语钉死）。audit/commit/evidence JSON 的边界声明一致：
≠ universal portability、≠ production readiness、≠ performance、≠ artifact
portability、≠ durable store。测试文件与 evidence JSON 的 nature 字段同口径。

术语钉死（随本 review 固化，替换 audit 中「adapter-local 解决」的读法）：

```text
✔ adapter-level cancellation containment
✘ universal cancellation abstraction
✘ 「已解决 backend cancellation」
```

G-9（contract-level cancellation surface）保持 NOT CLOSED。

## 3. Boundary check

| Boundary | Result |
|---|---|
| E1/E3/B1 语义所有权未变 | PASS |
| 无 backend-specific state 进入 D（A2） | PASS |
| 无 storage / persistence format / API·protocol design | PASS |
| 无 performance claim（含计时性语言） | PASS |
| 无 artifact portability claim | PASS |
| 无 oversized 特殊语义；oversized 未被 adapter 触碰 | PASS |
| L-1/G-5 未被顺手修复（M-3）；G-1 未新增 direct entry | PASS |
| M-1…M-5 逐项落在产物中 | PASS |
| 七条 stop conditions 未触发 | PASS |
| `observed code fact ≠ engineering finding ≠ bounded conclusion` held | PASS |

## 4. Evidence check

```text
union battery = 75 / 75 PASS
  ├─ Phase C 61/61（seam/conformance evidence，零回归）
  └─ adapter 14/14（concrete integration evidence，T1–T8）
```

证据边界钉死（随登记继承）：transport 代码路径是真实的（URLSession →
HTTP 语义 → 失败/取消/畸形响应均被确定性驱动），但 server 响应为 stub；
live-server 端到端证据仍是 RQ1 live smoke 先证、未重跑。后续任何轮次不得
把 stub 证据表述为 live validation。

## 5. Review strengthening（随登记固化，不阻塞）

1. **Terminology pin**：cancellation 表述统一为 adapter-level cancellation
   containment；G-9 保持 NOT CLOSED。
2. **B1 原则**：§2 R-3 的 seam 能力边界原则登记为路线级方法论资产。
3. **Evidence boundary**：stub-transport 证据与 live-server 证据分层表述；
   不得互称。
4. **SUFFICIENT scope pin**：sufficiency 限于已测 adapter 类（server-owned
   weights + recompute 策略）；不预支未来 backend 类型的结论。

## 6. Gate state

```text
Engineering Round 1  = PASS / REGISTRATION_REQUIRED
Current blocker      = explicit human/repository registration
Gate closure         = 待 registration；Engineering 不自封（已遵守）
Next stage（登记后）  = 由 human 决定：seam 稳定性研究（长期 backend-
                       independence 边界）优先于第二个 backend 的功能堆量
                       ——human 已给出方向性判断，登记时确认即可
```
