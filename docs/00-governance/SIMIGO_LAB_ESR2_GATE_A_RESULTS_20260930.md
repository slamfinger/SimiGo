# ES-R2 Gate A Results — Formation Sufficiency Boundary

日期：2026-09-30  
状态：`GATE_A_COMPLETE / FORMATION_SUFFICIENCY_BOUNDARY_DELIVERED / STOPPED PER DIRECTIVE`  
唯一问题：**在不引入生产 ExecutionState 对象/API/schema 的前提下，
checkpoint boundary 若捕获 ES-D1 已观察到的事实，形成一个独立
Computational State 所需的最小充分条件是什么？**  
方法：synthetic carrier 构造（仅用 ES-D1 已观察信息）+ 逐项标记 +
充分性分层推导；Gate C 硬条件（reuse 不读完整 history、不用旧 P）作为
充分性判据的组成部分。零运行时、零修改。

```text
六类标记：authoritative / independent / derived / duplicate / descriptive
/ insufficient
判别标准（human）：「能被计算出来」≠「被系统作为 State 持有」
```

## 1. Synthetic carrier 构造（formation 时刻的在场事实全清单）

checkpoint commit 时刻（performSave），runtime 在场且 schema 未捕获的
事实（ES-D1 Phase F/G/H 已核）：

```text
F-1  identity         = storageKey（寻址链已在文件名固化）
F-2  position         = history.count（=17；Gate H 实测 18 未捕获即死）
F-3  continuation anchor = history 末端（消息 17 的引用/哈希）
F-4  lineage context  = forkPoint（仅 fork 事件；本样本 ABSENT）
F-5  history 全文     = 17 条 transcript（meta 已捕获——唯一已形成项）
F-6  modelId / 生命周期事件本身 / retention 上下文
```

Synthetic carrier 最小捕获集（全部为「形成时刻已在场的标量/引用」）：

```text
S* = { storageKey, position: 17, continuation-anchor: tail(17) }
     捕获成本 = 数字节标量；全部为 formation 时刻 runtime 已知
```

## 2. 逐项标记表

| 信息 | 当前形成状态 | 若 boundary 捕获 | 标记 | 层级 |
|---|---|---|---|---|
| identity（storageKey） | 已独立固化（文件名/寻址链） | 无需额外捕获 | **authoritative / independent / sufficient** | Tier-1 |
| position | 未捕获（runtime 实例随进程死亡——Gate H 实测 18） | 捕获为标量 `position: 17` → 成为 authoritative / independent | **authoritative-capturable / independent（捕获后）** | **Tier-1** |
| continuation anchor | 未捕获（=history 末端引用） | 捕获为引用 `tail(17)` → anchor 权威化 | **authoritative-capturable / independent（捕获后，作为 anchor）** | **Tier-1** |
| lineage | forkPoint 载体存在但零实例；非 fork 不形成 | 捕获为可选字段 | descriptive（本样本）/ latent | Tier-1（可选，非最小集成员） |
| history 全文 | 已捕获（meta.history）——**但这正是问题**：作为载体它是语义本体，作为 Reuse 输入它是被禁止的 full-History 读取 | — | **authoritative（semantic）/ H-dependent / 不可计入最小集** | **Tier-2 边界** |
| recovery（per-token context） | **未捕获且无压缩形态**——per-token KV 只存在于 P（被删）或 full prefill（被禁） | 无可捕获物（观察宇宙内不存在压缩载体） | **INSUFFICIENT** | **Tier-2 缺口** |

## 3. Formation Sufficiency Boundary（两层结构）

```text
FSB-1  DESCRIPTIVE/AUTHORITY TIER（Tier-1）
  最小充分集 = { storageKey, position: N, continuation-anchor: tail(N) }
  性质：捕获后即形成「独立权威的 Computational State 记录」——
  identity/position/continuation 全部 authoritative + independent，
  跨表示丢失与进程死亡存活（标量天然 durable）。
  捕获成本：数标量字节，formation 时刻全部在场。
  ⇒ Tier-1 的形成在【观察宇宙内最小充分】。

FSB-2  OPERATIVE/REMATERIALIZATION TIER（Tier-2）
  使 State 能在不读完整 History、不用旧 P 的条件下驱动 R' 物化的
  信息 = 对 N-token 上下文的【压缩表示】。
  观察宇宙内此类载体不存在：唯一的压缩物就是 per-token KV 本身
  （= Physical Representation，按定义排除在 State 之外）。
  ⇒ Tier-2 在【观察宇宙内 INSUFFICIENT】——缺口不是一个字段，
  而是一类尚不存在的载体（compressed context carrier）。
```

**两层之间的关系（可否证表述）**：

```text
补齐 FSB-1（捕获三个标量）会使系统形成「独立权威的 State 记录」，
  但该 State 仍是【描述性的】：它能回答「我是谁/我在哪/我从哪继续」，
  不能在不读 History 的前提下物化 R'。
补齐 FSB-2 需要的载体在当前系统信息宇宙中不存在——若未来出现
  （如可增量应用的上下文压缩物），它本质上是「另一种 Representation」，
  其与 State 的边界将成为新的研究问题。
⇒ 可否证预测：在观察宇宙不变的前提下，任何 State Reuse 实验要么
  退化为 H→R'（读完整 history），要么退化为 P→R（用旧表示）；
  纯 S→R' 需要 Tier-2 新载体，而该载体的存在性本身未证。
```

## 4. 与既有证据的一致性校验

```text
✔ Gate H（position 18 死亡/17 存活）：与 FSB-1「position 可标量捕获但
  未捕获」一致——捕获发生在 checkpoint commit 则 18 亦固化
✔ E1.5-Q2（transcript 无完整性门）：与 FSB-2「history 是语义载体而非
  压缩载体」一致
✔ R2n/E3（history 语义充分性）：与 FSB-2「history 驱动 R' 但需 full
  prefill」一致——语义充分 ≠ 物理充分
✔ Gate D（无独立五元 carrier）：与 FSB-1「三个标量从未被捕获」一致
```

## 5. 交付与停止

```text
✔ Formation Sufficiency Boundary 已交付（FSB-1/FSB-2 两层，含可否证
  预测）
✔ 六类标记逐项完成（§2）
✔ 停止条件触发：Gate A 完成，立即停——不进 B、不改生产代码、不建
  API、不做 S→R'、不讨论性能
✔ R2-A/E/F 裁定权归 human（本 gate 只交付边界本身）
```
