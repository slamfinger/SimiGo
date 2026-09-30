# Execution State Seam Stability Audit — S1–S6

日期：2026-09-30  
状态：`SEAM_STABILITY_AUDIT_COMPLETE / AWAITING_REVIEW`  
Audited source state：`b031188`（opening registration tip；全部代码事实与
re-run 绑定此 hash）  
Registered criteria：`SIMIGO_LAB_SEAM_STABILITY_OPENING_REGISTRATION_20260930.md`
（判据采数前冻结，未增删）  
性质：`stability audit only`——无实现、无 contract 变更、无新测试、无存储
选型、无 PALACE 消费、无 performance claim

```text
observed code fact ≠ inferred stability criterion ≠ selected implementation
```

## 1. Evidence basis

```text
判据        = opening registration 冻结版（S1 四轴 / S2 操作化 / S3 分类 /
              S4 抽象化 / S5 判据 / S6 组装），与 draft+review 逐字一致
先证        = Phase B 45/45、Phase C 61/61（ebe4aec）、Round 1 75/75
              （5b47ea8）；本审计不重跑其结论，只引用
re-run      = 75/75 PASS @ b031188（S6 复跑；hash 级绑定；evidence JSON
              results/backend-conformance/seam-stability-audit-rerun-20260930.json）
关键新事实  = contract target 全部历史 = 4 commits（ee07123 B1/B2、
              0774110 L4-A、8c5836e E1、646bc09 E3），全部 2026-09-25；
              此后零变更——期间经历 runtime 封线、oversized 冻结、
              PALACE-1 Phase A/B/C、adapter opening/round1、PALACE 并线
              登记等全部轮次
```

## 2. S1 — 稳定性四轴

### 轴 a — semantic ownership
判据：D/R/P/O/T 归属不被实现便利改写。  
Observed：`ExecutionStateHandle` 全 `let`（contract:70-75）；coordinator
是唯一语义权威；Round 1 adapter 全状态 R/T/P、零 D 新增；三 backend 对
handle 只读；唯一跨组件异常 L-1/G-5 是 P 层 API 渗漏，不触及语义归属。  
**判定：SATISFIED。**

### 轴 b — extension
判据：新 backend/新能力经既有显式降级表达，无需 contract 变更。  
Observed：Round 1 以零 contract 变更组合出真实 adapter；历史上三个异构
backend 过同一 battery；显式降级机制齐备（ResolutionState 四态、
noRepresentationAtPosition、recompute 策略）。适用域限定：已行使者为一类
adapter；可推广性由 S4 在审计层回答。  
**判定：SATISFIED（域限定见 §8）。**

### 轴 c — change discipline
判据：contract 变更必须有登记的语义必要性证明。  
Observed：contract target 自 2026-09-25 E3 落地后 **零 commit**；同一时期
全部研究轮次以组合/适配方式完成（Round 1 的 5b47ea8 工程证据直接证明了
「不需要动 contract 也能穿透 seam」）。变更纪律目前以最强形式成立：
不是「变更被批准得少」，而是「从未被需要」。  
**判定：SATISFIED。**

### 轴 d — composition
判据：已登记未来层（durable store、productization）叠加时不要求重构语义
所有权。  
Observed（判据层）：Phase B 边界按「被消费」设计——durable store 持久化
Execution Semantic Snapshot + tombstones + separately-typed relations，位于
seam 之下/旁，不穿过它；capability boundary 原则规定未来层按真实物理所有权
接入；composition 模式（host-side 组合体）已被 Round 1 验证。  
诚实限定：durable store 与 productization 尚未发生，本轴为**判据层判定**
（设计一致性），非行使层判定——未来激活时本轴接受再检验。  
**判定：SATISFIED（判据层；限定随裁决继承）。**

## 3. S2 — Contract-change 机械检查表

以下任一信号出现即构成 contract change，必须走独立 contract gate（定义门
→ review → 登记），禁止在任何 engineering/adapter commit 内静默发生：

```text
C-1  contract target 路径任何文件 diff（git 可机械检测）
C-2  E1/E3/B1 任一协议方法签名变更
C-3  ExecutionStateHandle 字段集或字段语义变更
C-4  任一 backend 写入 handle（sovereignty 违背）
C-5  四个事务窗口（fork/restore/discard/bind）commit ordering 变更
C-6  契约错误枚举无登记必要性的新增/删除
C-7  payload 具体类型进入 contract target（破坏 opaque 边界）
C-8  B1 被强制化为所有 adapter 必选（违背能力边界原则）
C-9  语义权威从 coordinator 转移
C-10 D/R/P/O/T 已登记字段的重分类（无 registered review）
C-11 lifecycle 值语义变更（attached/active/restored/discarded）
C-12 门纪律绕过（未经 registration 的变更 / 藏于工程 commit——
     evidence-source-state 纪律即为此设）
```

检测机制：C-1/C-2/C-3 由 git path filter + API diff 机械执行；C-4/C-9 由
S6 sovereignty spot-check 执行；其余由 review 阶段对照本表逐项判定。

## 4. S3 — G-gap 稳定性风险地图

```text
G-1   LOCAL-FIXABLE     单 backend guard；不涉及任何契约面
G-2   LOCAL-FIXABLE     coordinator 内部锁；签名与语义不变
G-3   LOCAL-FIXABLE     attach 的 fail-closed 收紧；属行为收紧，需独立
                        review 但非 contract 变更
G-4   LOCAL-FIXABLE     同 G-3 形状
G-5   LOCAL-FIXABLE     P 层 API 重构（opaque store API）；涉产品接线，
                        不涉 contract
G-6   LOCAL-FIXABLE     per-backend content claim 位于 P 层
      ⚠ 触发条件        若「跨 backend 统一 digest」被要求进入契约 →
                        contract gate
G-7   LOCAL-FIXABLE     durable allocator 是契约之上的层；ID 保持 opaque
      ⚠ 触发条件        若跨重启 reservation 语义要求契约可见状态 →
                        contract gate
G-8   LOCAL-FIXABLE     registry 内部存储方式变更
G-9   LOCAL-FIXABLE /   containment 已被 Round 1 证明（术语：adapter-
      ADAPTER-LEVEL     level cancellation containment）
      ⚠ 常备触发条件    任一未来 adapter 的安全语义超出 containment →
                        contract gate（当前唯一活性触发点）
G-10  LOCAL-FIXABLE     durable store 按设计消费 Phase B 边界，契约中立
      （契约中立）⚠ 触发条件 若 store 实际需求迫使 handle/relation schema
                        变更 → Phase B re-opening gate，禁止静默变更
```

结论：**0 项 CONTRACT-BLOCKING-FUTURE**；1 个常备触发点（G-9）+ 3 个条件
触发点（G-6/G-7/G-10）。本表是稳定性风险地图，不是实现队列（登记纪律）。

## 5. S4 — Second-backend 需求分析（审计级 thought experiment）

对象：**抽象类**「in-process physical state backend」——物理表示位于进程
内、由 adapter 直接控制的 backend 类（区别于 llama-server 的外部计算/缓存
权威）。不点名具体技术，不产生实现工件。

| 该类的需求 | seam 落点 | 覆盖判定 |
|---|---|---|
| 更重的物理 capture/derive/restore/release | E3 四操作（async、策略自持） | 已覆盖 |
| 进程内内存对账 | B1（memoryObservation / purgeTransientCaches） | 已覆盖——此类 backend **预期行使 B1**（能力边界原则的正向用例） |
| 物化原子性与取消 | B1 async-atomic（throw = 状态不变） | 已覆盖 |
| 驻留/驱逐策略 | ResidencyController（既有，B1 之上） | 已覆盖 |
| 跨会话共享表示 | BindingRegistry N-bindings（F-I5 结构） | 已覆盖 |
| durable reattachment 内容主张 | per-backend claims（G-6 路径，P 层） | 已覆盖（local） |
| 物理状态不可用时的语义结果 | ResolutionState / rematerializationRequired / recompute | 已覆盖 |

结论：**在该抽象类的审计层分析中，未发现超出已登记 seam 的需求**。诚实
限定：这是抽象类推演，不是任何具体 backend 的证据；「无已知需求超出
seam」≠「一切可想象 backend 均被覆盖」。

## 6. S5 — Productization 边界判据（只定义，不执行）

```text
P-1  contract target 以零模型依赖独立包交付（Lab 已真；产品打包须保持）
P-2  D/R/P/O/T ownership map 随产品交付为可执行文档，S2 检查表进入
     产品 review/CI
P-3  conformance battery 成为产品 backend 准入测试（同一 battery、语义
     断言零分叉）
P-4  产品内 contract 变更走同一门纪律（definition gate → review →
     registration）
P-5  产品工程轮次继承 M-1…M-5 与 evidence-source-state 纪律
P-6  durable identity/store 的产品化继承 Phase B 边界（snapshot +
     tombstones + separately-typed relations）
```

## 7. S6 — Standing drift-detection 面（从既有工件组装）

```text
1. union battery 复跑（75 项；contract-adjacent 变更必跑；hash 级绑定）
   ——本轮已示范：75/75 @ b031188，零漂移
2. S2 检查表：任何变更的分类必经
3. M-1…M-5：任何工程轮次必经
4. sovereignty spot-check：C-4/C-9 扫描（backend 代码 review 固定项）
5. inherited-conditions ledger：每个新 gate 登记时重录全部继承条件
6. PALACE 隔离检查：无 bridging registration 不消费
```

## 8. 三分裁决

```text
裁决：STABLE-AS-REGISTERED
```

依据：四轴判据全部满足——a/b/c 有行使层证据（零 contract commit 史、
零变更穿透、显式降级机制实证），d 有判据层证据（Phase B 边界按被消费
设计 + 组合模式已验证）；S3 风险地图零 CONTRACT-BLOCKING 项；S4 抽象类
需求全部落点既有 seam；standing battery 在审计源码状态零漂移。

**边界（本裁决不外推，随登记继承）**：

```text
≠ immutability——seam 经登记 contract gate 演化的通道保持开放
≠ universal portability / production readiness / performance 结论
轴 d 为判据层判定：durable store / productization 激活时接受再检验
S4 为抽象类推演：具体新 backend 仍须各自 activation
常备触发点：G-9（containment 之外）、G-6（统一 digest 入契约）、
G-7（reservation 语义入契约）、G-10（Phase B 边界不够用时 re-opening）
——任一触发 = contract gate，禁止静默变更
```

## 9. Evidence hierarchy 声明

```text
observed code fact（contract 历史 / Round 1 证据 / re-run @ b031188）
    ↓
stability audit（S1–S6，判据先于证据）
    ↓
bounded engineering conclusion（STABLE-AS-REGISTERED，上述边界内）
```

Gate closure 判定权在 external review 与 human registration；本文件不宣布
closure。
