# BACKEND-1 Adapter Engineering Audit — A1–A8 Boundary

日期：2026-09-30  
状态：`ENGINEERING_ROUND1_COMPLETE / AWAITING_SECOND_LAYER_REVIEW`  
基线：`5ab7247`（adapter engineering opening = PASS / REGISTERED）  
性质：`engineering boundary audit + minimal integration skeleton + targeted evidence`  
角色边界：本文件是本地 Agent 的工程产出，交由 human 做第二层研究判断与
gate 审查；**Engineering 不得自行宣布 gate closure**。

依据：adapter engineering opening registration（M-1…M-5 强制检查项、七条
stop conditions、G-1…G-10 INHERITED / NOT CLOSED）。

本文不选存储，不设计 persistence format / API / protocol，不做 performance
claim，不做 artifact portability claim，不加 oversized 特殊语义，不修改
E1/E3/B1 语义所有权，不顺手修复 L-1/G-5 或关闭任何 G-gap。全程区分：

```text
observed code fact ≠ engineering finding ≠ bounded engineering conclusion
```

## 0. 前置核验（执行方案 §0）

```text
git fetch                 = up to date
branch / remote tip       = codex/execution-state-research-20260929 @ 5ab7247（一致）
git status                = clean（0 项）
last 20 commits           = 全部为本线已登记/已核验 commit，无未知语义代码提交
治理文档重读              = NEXT_SESSION_ENTRY / RESEARCH_STATE / registration /
                            draft / external review / Phase C seam audit
                            （本会话全程持有全文，基线后无变更）
→ 无 STOP 条件
```

## 1. 真实 adapter 定性（执行方案 §3 的必答问题）

> 当前 LLAMA-server backend 究竟是「真实 adapter」还是「validation payload」？

Observed facts：

```text
1. LLAMAServerExecutionStateBackend 自述为 "RQ1 — non-MLX conformance
   vehicle"（LLAMAServerExecutionStateBackend.swift:4）——其存在目的是证明
   契约面不绑 MLX 类型；E3 四操作本身是真实的 representation 策略。
2. LLAMAServerExecutionStateExecutor 是真实 Swift transport（URLSession 可
   注入，executor:60；/completion、/tokenize、/props），但没有任何类型把它
   与 backend + coordinator 组合成可持有的会话形 adapter。
3. ForkRestore / Cancellation / AB 三个 harness 均自标 HARNESS_LEVEL
   （ForkRestore:9-11、Cancellation:10-12），per-sample 一次性创建
   backend+coordinator 并丢弃，不拥有 transport 生命周期与失败所有权。
4. 无 runtime model identity 接线：executor.props() 存在但无消费者。
5. 无 cancellation 语义边界：harness 级 HTTP cancel 存在，但没有
   「取消 → 不 commit」的确定性保证被类型化。
```

Engineering finding：**当前是 validation payload，不是真实 adapter**——
但组成件（E3 策略、transport、E1 coordinator）全部真实且可复用。按执行
方案 §3：`reuse + compose`，不重新设计。

## 2. A1–A8 matrix

| Question | Code fact | Engineering finding | Status |
|---|---|---|---|
| A1 Boundary sufficiency | E3 四操作 + E1 七生命周期 + 3 adapter 同 battery 3/3；B1（`RuntimeResidencyBackend`）面向 layer 物化（RuntimeBackendContract:43-67），llama-server 的模型物化归 server 所有 | 真实 adapter 所需的全部操作落点：representation 生命周期 = E3；语义生命周期 = E1；transport/session/model-identity = adapter R/T 层；**B1 不为本 adapter 形状所必需**（server 拥有权重物理生命周期），缺席不产生语义损失 | PASS |
| A2 State containment | `ExecutionStateHandle` 全 `let`（contract:70-75）；adapter 只读 handle、只写自身私有状态 | 全部 backend-specific 状态（§3 表）落在 R/P/T/O；无一进入 D；server session/cache/artifact/transport 均为 adapter 或 server 所有 | PASS |
| A3 Representation lifecycle | capture 位置校验（backend:50-59）、derive 位置相等+foreign 双 guard（:61-81）、restore foreign guard（:83-92）、release stale-safe no-op（:98-105）；coordinator 四个事务窗口物理先行 | 四操作完整覆盖真实 adapter 生命周期；physical failure → 逻辑不提前 commit（见 T2/T3/T6 证据）；stale release 不杀 live binding（FBC-001 不变量在 LLAMA backend 同样成立） | PASS |
| A4 Capability boundary | 契约无 capability 字段；`ResolutionState` 四态显式降级（registry:205-221）；`noRepresentationAtPosition` fail closed（coordinator:214-221） | capability 差异（/props 可用性、cache 策略、健康状态）全部表达为 adapter-local policy（R/T）+ 既有显式结果（recompute / rematerializationRequired / noRepresentationAtPosition）；**未新增任何 D-level capability field**（方案 §A4 的反例设计未出现） | PASS |
| A5 Cancellation / failure / concurrency | E1/E3 无 cancellation 面（G-9 inherited）；LLAMA backend 内部 NSLock（:19）；executor 经 `session.data` 天然响应 Task 取消 | cancellation = adapter-level transport cancel + 「commit 前取消 → 不 commit」（T7）；HTTP failure → 不 commit、可重试（T6）；adapter 以自身 NSLock 串行化会话级操作（adapter-local，**不是** G-2 的修复）；G-2/G-7/G-9 维持 INHERITED，未改 contract | PASS |
| A6 Sync / async boundary | 语义 commit 与物理结果的因果仅存在于四个登记窗口；executor 全部 I/O 为 async（executor:65-119） | 真实执行管线 = tokenize → complete（async，seam 外）→ 成功后才 `continueExecution` + `bindRepresentation`（同步语义 commit）；取消/失败发生在 commit 之前；**语义 ordering 未变成 backend-specific async 状态机** | PASS |
| A7 Default-path non-interference | 本次改动 = 新增 2 个文件 + 1 个测试文件；零改动 contract target / coordinator / 既有三 backend / MLX 路径 / OversizedSegmentedEngine / E5 | 无 Runtime semantic ownership 变更；无 MLX 类型进 contract（adapter 仅 import Foundation + SimiGoRuntimeContract）；无第二套 Execution State semantics（T8 复用同一断言集）；无全局 backend branching | PASS |
| A8 Semantic continuity | 同一 `LLAMAServerExecutionStateBackend` 类型已是三 backend conformance matrix 成员；adapter 生命周期测试使用与 matrix 相同的语义断言 | 同一 id/lineage/position/continuation/lifecycle 在 backend 改变时语义保持；representation 侧显式降级（recompute 策略 = representation 缺失时从逻辑 continuation 重token化）；**证明的是 semantic continuity，不是 artifact portability**（MLX KV artifact ≠ llama artifact，未声称） | PASS |

## 3. D/R/P/O/T classification（真实 adapter 全部重要状态）

```text
D（Durable Semantic State）——adapter 新增：无（硬要求达成）
  仅有的 D 仍是 Runtime 独占的 ExecutionStateHandle：
  id / lineage / position / continuation / lifecycle
  owner = ExecutionContinuityCoordinator；adapter 从不写 handle。

R（Runtime Binding）
  field                    owner        lifetime         recovery meaning
  prefixes/boundPositions  E3 backend   session-scoped    rebindable via
  （绑定字典）                                            capture/restore；
                                                          丢失 → recompute
  adapter 会话串行锁       adapter      session-scoped    重建即可，无语义
  transport session        adapter      session-scoped    重建即可，语义不变
  （URLSession）

P（Physical Representation）
  LLAMAServerPrefixPayload E3 payload   per-binding       丢失 →
  .tokenPrefix（[Int]）                                   rematerialization
                                                          Required / recompute
  model identity           adapter      open-scoped       信息性元数据；
  （/props model_path）                 （缓存）          非语义；丢失 → 重新
                                                          open 拉取

O（Observability / History）
  coordinator lifecycle    coordinator  session-scoped    replay/observability；
  records / representation                                非最小 D（Phase B）
  history
  open() 返回的 props 结果 adapter      open-scoped       观测；不参与语义

T（Transient / Reconstructable）
  llama-server native      EXTERNAL     request-scoped    策略性忽略
  KV / slot cache          server                         （cache_prompt:false）；
                                                          污染 → 重放路径已有
                                                          RQ1 live smoke 先证
  in-flight HTTP 请求      adapter      per-call          失败/取消 → 无语义
  （tokenize/complete）                                   commit
  生成中 tokens            adapter      per-call          要么全量 commit，
                                                          要么全量丢弃
  seed / 请求参数          per-call     per-call          确定性旋钮，非状态
```

## 4. Adapter boundary diagram

```text
Host / product layer（拥有 ID、驱动回合）
   │
   ▼
LLAMAServerExecutionStateAdapter           ← 本次最小 integration skeleton
   │  semantic ownership: 无（组合体，不新增 D）
   │  failure ownership: transport 失败/取消 截停在语义 commit 之前
   │
   ├── E1 ─ ExecutionContinuityCoordinator
   │        owns: id / lineage / position / continuation / lifecycle
   │        commit ordering: fork（derive 先行）/ restore（restore 先行）/
   │                          discard（release 先行）——Runtime 独占
   │
   ├── E3 ─ LLAMAServerExecutionStateBackend（复用，未改）
   │        owns: token-prefix representation strategy
   │        └── LLAMAServerPrefixPayload（opaque [Int]）＝ P 层
   │
   └── transport ─ LLAMAServerExecutionStateExecutor（复用，未改）
            owns: URLSession / baseURL（R/T）
            └── 外部 llama-server（compute + native cache 权威，进程生命周期外部）
```

反向依赖检查：不存在 `backend → mutate ExecutionStateHandle` 代码路径
（handle 全 `let`；adapter 仅调用 coordinator 公共 API）。

## 5. Minimal integration skeleton（执行方案 §4）

新增 `LLAMAServerExecutionStateAdapter`（Sources/SimiGo2Experimental/
LLAMAServerExecutionStateAdapter.swift）：

```text
复用（未改一行语义）：E3 = LLAMAServerExecutionStateBackend；
                      transport = LLAMAServerExecutionStateExecutor；
                      E1 = ExecutionContinuityCoordinator
新增（组合 + 所有权 + 失败边界）：
  open()               /props → model identity（P）；失败 → 无语义状态
  createExecution      tokenize 先行 → create(position 0) → bind；tokenize
                       失败 → 什么都不创建（fail closed）
  continueTurn         bound prefix → tokenize 追加 → /completion 真实生成
                       → commit 前取消检查 → continueExecution + bind
                       （I/O 失败/取消/缺 tokens → 无 commit，可重试）
  forkExecution / restoreExecution / reattach / discardExecution
                       coordinator 透传，语义结果与契约逐字一致
  executionStateBackend 只读暴露 → T8 复用同一 conformance 断言集
```

真实 backend 通路：真实 HTTP（测试中经 URLProtocol stub 确定性驱动失败/
取消路径；live server 先证 = RQ1 live smoke，未重跑）。

## 6. Targeted evidence（T1–T8）

测试：`LLAMAServerExecutionStateAdapterTests.swift`（新增）。运行结果见
§7 与 evidence artifact。逐类对应：

```text
T1 Capture     正确位置 PASS；错误位置 → representationPositionMismatch；
               foreign payload → foreignRepresentationPayload；unbound →
               noBoundRepresentation
T2 Derive      有效 parent → child 绑定 parent prefix；foreign derive →
               throw 且 child 无 handle（无逻辑 commit）；位置不等 →
               fail closed
T3 Restore     有效 representation → restored（且后续 turn 从恢复前缀继续
               ——端到端连续性）；缺失 → noRepresentationAtPosition；
               backend restore 失败 → 逻辑状态不变
T4 Release     current release → 物理绑定清除；stale release → no-op 且
               live binding 完好；foreign release → fail closed；
               release 失败（注入）→ discard 可重试
T5 Lifecycle   create / continue / fork / restore / reattach / discard 全链
               经 adapter，语义结果与契约逐字一致（无第二套断言）
T6 Atomicity   /completion 500 → 抛错且 position/绑定不变 → 重试成功；
               completion 缺 tokens → fail closed 无 commit
T7 Cancellation commit 前取消 → 抛错且逻辑状态停在旧 position（G-9 依赖
               已记录为 adapter-level resolution，未新增契约面）
T8 Conformance adapter 的 E3 backend 即 matrix 中同一类型（3/3 先证 +
               本次 evidence 复跑）；adapter 断言与 matrix 逐字同集
```

## 7. Evidence artifact 与结果

```text
命令：swift test --filter 'LLAMAServerExecutionStateAdapterTests|
ExecutionContinuityContractTests|…（Phase C battery 全集并集）'
结果：75 / 75 PASS（SimiGoRuntimeContractTests 19 + selected
SimiGo2ExperimentalTests 56 = Phase C 42 全数复过 + 新增 adapter
battery 14）
Evidence artifact：
results/backend-conformance/backend1-adapter-engineering-evidence-20260930.json
```

定点证据类别与结果（最终数字以 evidence JSON 为准）：

```text
T1–T8 全部 PASS（14/14）；Phase C 全部既有 suite 在并集中零回归。
失败/取消/缺 tokens 路径经 URLProtocol stub 对真实 URLSession transport
确定性驱动；live server 先证（RQ1 live smoke）未重跑。
```

## 8. Gaps disposition（G-1…G-10，不得写 CLOSED）

```text
G-1   INHERITED / NOT CLOSED；NOT RELEVANT TO THIS ADAPTER PATH
      （LLAMA backend derive 自带位置 guard；本次未创建任何 oversized
      direct entry；guard 缺失本身仍待未来 engineering gate）
G-2   INHERITED / NOT CLOSED（adapter 自身串行锁是 adapter-local 方案，
      不是 coordinator 修复）
G-3   INHERITED / NOT CLOSED（adapter 不使用 attach 绕过路径）
G-4   INHERITED / NOT CLOSED（bindRepresentation 行为未改）
G-5   INHERITED / NOT CLOSED；NOT RELEVANT TO ADAPTER（PrefixSnapshotStore
      未被触及——M-3 遵守）
G-6   INHERITED / NOT CLOSED（payload 仍为 [Int] 前缀，无 universal digest）
G-7   INHERITED / NOT CLOSED（ID 由 host 提供，无 durable allocator）
G-8   INHERITED / NOT CLOSED（BindingRegistry 未触及）
G-9   INHERITED / NOT CLOSED；ADAPTER-LEVEL RESOLUTION RECORDED（契约无
      cancellation 面的情况下，本 adapter 的取消语义可安全实现：commit 前
      取消 → 无 commit；未新增契约 API——M-5/Draft §A5 遵守）
G-10  INHERITED / NOT CLOSED（adapter 为会话内存态，未声称 durable store）
```

## 9. 三分法裁决

```text
裁决：SUFFICIENT（在下列边界内）
```

依据：现有 E1 + E3 + B1 足以承载真实 backend adapter engineering——

```text
✔ 全部真实 adapter 职责落点既有 seam（A1）
✔ 无任何 backend-specific state 需要 D 化（A2；硬要求达成）
✔ 四个 E3 操作 + 四个登记事务窗口完整覆盖 representation 生命周期（A3）
✔ capability 差异以显式降级表达，无 D-level capability（A4）
✔ cancellation/failure/concurrency 在 contract 外 adapter-local 解决（A5）
✔ 语义 ordering 与物理机制分离保持（A6）
✔ 默认路径零结构性干扰（A7）
✔ backend 替换下语义连续，显式降级（A8）
```

边界（本裁决不外推）：

```text
≠ universal backend portability
≠ production readiness（无长稳/并发压测/错误恢复矩阵）
≠ performance conclusion（延迟/吞吐归 RQ3，本轮无任何计时结论）
≠ durable Execution State / artifact portability
```

## 10. Evidence hierarchy 声明

```text
observed code fact（§1/§2 引用的 file:line）
    ↓
targeted adapter evidence（T1–T8 测试 + evidence JSON）
    ↓
bounded engineering conclusion（§9 SUFFICIENT，上述边界内）
```

无跳跃。Gate closure 判定权在 human 第二层审查与后续 external review +
registration；本文件不宣布 closure。
