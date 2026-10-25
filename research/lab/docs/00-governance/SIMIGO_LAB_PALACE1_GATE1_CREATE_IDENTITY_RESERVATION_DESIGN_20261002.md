# PALACE-1 Gate① Create Durable Identity Reservation — Observation Design Draft

日期：2026-10-02  
状态：`DRAFT / DESIGN-FREEZE-PENDING-HUMAN（仅设计；无执行授权）`  
Gate：`PALACE1_GATE1_CREATE_ID_RESERVATION（observation only）`  
授权来源：opening registration（2026-10-02）+ human Gate① 指令——
允许设计「如何观测 EF-9」，尚未允许执行实验，尚未允许决定 durable
identity 实现方式  
上游锚点：opening rev.2 §3/§6 create 行 · EF-9 · IC-3/IC-4（契约层）·
Registration 20261002 观测层纪律  
性质：participant design draft——设计冻结后交 human 一次冻结审查，
批准后方执行

## 0. §0 并发核验（执行前须重跑）

```text
git fetch / REMOTE              = 25e1a79（本线起点，零漂移）✓
LOCAL                           = 539fd72（领先 6 commit，全部为
                                  本线工件：05f4624/777846e/3d72485/
                                  5362087/6055073/539fd72）✓
worktree clean                  = 0 项 ✓
opening 登记后无并发漂移        ✓
→ 设计阶段入口合法；执行前重跑并记录
```

## 1. Research Question（固定，单问题）

> PALACE 生命周期中的 `create`，是否需要一个跨进程/跨重启仍可保持
> 语义连续性的 durable identity reservation 机制？

本设计不回答、不预答：

```text
❌ identity 用什么格式（UUID / 其他）
❌ 是否用数据库主键
❌ reservation 存在哪里（何种存储）
❌ allocator 如何实现
❌ 是否/如何修改产品代码
```

## 2. EF-9 Baseline（登记事实，观测起点）

| 已登记事实 | 来源 |
|---|---|
| ExecutionID = opaque caller-supplied String，无 durable allocator / 跨重启 reservation | Seam Audit（G-7 行审计原文）；Adapter Engineering Audit（G-7 INHERITED / NOT CLOSED） |
| Lab 无 durable Execution State store（Phase B gap #1） | G-10（NOT CLOSED） |
| 产品已存在 durable writer（checkpoint 62/64 GiB + prefix pool 15/16 GiB），但其义务面是资源层，非 identity 层 | Writer Provenance Audit（EF-10） |
| 契约层已登记：discarded = 终态 tombstone 且身份保留（reservation）、重复创建对 active 或 reserved-discarded ID fail-closed | IC-3 / IC-4（Architecture Contract v1.0，CONFIRMED-unchanged，契约推导级） |
| identity 寻址链当前经 storageKey（= 文件名 = caller key）跨进程存在 | E-series（A1：storageKey 一物三面） |

## 3. 概念切分（human 指令，禁止合并）

```text
identity 可唯一（caller 纪律即可达成）
      ≠
identity 必须由 PALACE durable reservation 保证

当前实现没有 allocator（EF-9 工程事实）
      ≠
Execution State / PALACE 必然需要某种 allocator（语义主张，
须 positive evidence + 替代解释排除后才可成立）
```

本实验的全部设计围绕这对区分：观测结果只允许回答
「durable reservation 是否有被观测支持的语义需求」，
不允许直接跳到机制或实现。

## 4. Observation Matrix（六个边界格，全部只观测）

| 格 | 边界 | 操作序列 | 观测点 |
|---|---|---|---|
| **O-1** | 创建边界 | 净空间（新 ID `S-g1`）进程 P1 `create` | identity 可断言性；初始 position；创建产物清单（哪些文件/记录生成） |
| **O-2** | 进程内重复边界 | 同进程 P1 再次 `create(S-g1)` | 实际行为：reject / silent-accept / overwrite（IC-4 契约要求 fail-closed——观测实现是否 enforce） |
| **O-3** | 跨重启重复边界 | P1 `create(S-g1)` → 退出 → P2 `create(S-g1)` | 跨重启重复检测是否存在（durable reservation 的直接观测面） |
| **O-4** | 跨重启连续性边界（对照格） | P1 `create(S-g1)` → `save` → 退出 → P2 `restore(S-g1)` → identity 断言 | 经 checkpoint 寻址的 identity 连续性；该格区分「寻址持久」（已知：storageKey 文件寻址）与「reservation 持久」（待观测） |
| **O-5** | discard-后-重启复用边界 | P1 `create(S-g1)` → `discard` → 退出 → P2 `create(S-g1)` | tombstone reservation 跨重启是否阻止复用（IC-3 契约要求；EF-4 tombstone 载体 latent） |
| **O-6** | 并发创建边界（exploratory） | P1 与 P2 同时 `create(S-g1)` | race 行为记录（仅登记现象，不预登记判读） |

隔离配方：每格独立临时空间（一次性 fixture 目录），零真实用户数据
触碰（~/.simigo 原始 79G 边界不动）；进程 = 独立 OS 进程；`create/
restore/discard/save` 均为产品现有生命周期入口，零产品代码修改。
若最小 fixture 可无 generation 完成生命周期调用则不加载模型；确需
生成时用 Nail 模型 + 确定性 probe（PB1 模式）。

## 5. Pre-registered Predictions（预登记 + 分支判读规则）

| # | 格 | 预登记预期 | 分支判读规则（预先冻结） |
|---|---|---|---|
| P-C1 | O-2 | 实现状态 UNKNOWN（契约 IC-4 有要求；产品 enforcement 无登记记录） | (a) reject ⇒ IC-4 进程内 enforced（observation）；(b) silent-accept/overwrite ⇒ 契约-实现缺口 observation。两分支均只记行为，不升格语义结论 |
| P-C2 | O-3 | **EXPECTED：不存在跨重启重复检测**（EF-9 推论：无 durable allocator ⇒ 跨重启重复不可检测） | 符合 ⇒ EF-9 获运行时级直接观测；若实际存在检测 ⇒ **预登记偏离** → 停止并溯源隐藏机制（新事实，归 human 判读） |
| P-C3 | O-4 | **EXPECTED：identity 经 storageKey 寻址跨重启存活**（A1 已知机制） | 符合 ⇒ 确认「寻址持久 ≠ reservation 持久」对照成立；若失败 ⇒ 偏离 → 溯源 |
| P-C4 | O-5 | **EXPECTED：跨重启复用不被阻止**（tombstone 无 durable 载体；IC-3 reservation 仅契约层） | 符合 ⇒ tombstone reservation 缺口获运行时观测；若阻止 ⇒ 预登记偏离 → 溯源隐藏机制 |
| P-C5 | O-6 | 不预登记（exploratory） | 现象原样登记；不作为任何结论的证据 |

## 6. Evidence Classification（positive / negative / 替代解释）

### 6.1 Positive evidence（支持「需要 durable reservation」的全部条件）

同时满足以下三条，才构成支持性证据：

```text
(a) 观测到跨重启语义错误被静默接受
    （O-3 重复未检测 / O-5 tombstone 复用未阻止）
(b) 该错误在契约层被 IC-3/IC-4 明确禁止
    （contract implication 支撑）
(c) 单调用方 caller 纪律在崩溃窗口 / 多写者场景下
    无法合理替代（替代解释排除——见 §7）
```

三条齐备 ⇒ 「create 需要 durable reservation」成立为 **inference**
（EF-9 从实现缺口升格为语义需求候选，仍 bounded：限于已观测边界）。

### 6.2 Negative evidence（只说明实现限制，不得推出语义结论）

```text
单进程 / 单调用方场景下 caller 纪律可替代
⇒ 只能登记为「当前边界样本内 caller 纪律充分」
⇒ 不得写成「PALACE 无需 reservation」（bounded claim 边界；
   单调用方观测不覆盖崩溃窗口 / 多写者 / 长周期场景）
```

## 7. Confounders（预登记排除设计）

| 混淆源 | 排除设计 |
|---|---|
| caller 自己保证唯一性 | harness 的 ID 全部集中管理并记录；观测对象是系统行为非 ID 新颖性 |
| 进程内 session cache / P-I1 自愈回退 | O-3/O-5 的 P2 为全新进程 + 全新空间，cache 复活不可能跨空间；restore 路径（O-4）与 create 路径分开记录，禁止混读 |
| 测试 harness 自身写入产物被误读 | R0 六件套独立观测文件；写入清单预先登记 |
| 模型非确定性 | 优先无 generation 设计；确需生成时 Nail + 确定性 probe（PB1：O1 逐字复现校验） |
| fixture 空间残留 | 每格一次性目录；run 间零共享（跨重启格除外，其共享面 = 被观测产物本身） |
| 双写者时序噪声（O-6） | exploratory 格，现象记录不判读 |

## 8. Stop Conditions（预登记）

```text
一旦观测中出现新的不可约语义关系——例如：
  identity 与 model version 的绑定成为连续性必要条件；
  reservation 与 lineage closure 不可分离；
  出现本设计观测宇宙外的第四类 identity 边界——
立即停止实验，登记发现，进入 Closure Revision gate 判断。
禁止顺手持实验、禁止扩展观测面、禁止机制补丁。
```

## 9. Non-goals（逐字冻结）

```text
❌ schema / 数据库 / 存储选型
❌ serialization format
❌ allocator implementation（任何形式的实现设计）
❌ persistence API
❌ 产品代码修改
❌ OP-7 消费
❌ RF-1 机制设计
❌ identity 格式决策（UUID 与否）
❌ performance 读数
```

## 10. Evidence Grade Rules（登记措辞纪律）

| 级别 | 定义 | 本设计中的适用 |
|---|---|---|
| **observation** | 运行时行为记录（单实现、单环境） | O-1…O-6 的行为登记；C 级证据 |
| **inference** | observation + 契约 implication + 替代解释排除后的结论 | 「create 需要 durable reservation」须走 §6.1 全条件；bounded 于已观测边界 |
| **contract implication** | IC-3/IC-4 契约层要求（Architecture Contract，CONFIRMED-unchanged） | 只用于判读参照，不得当作工程事实引用 |

措辞对齐（Evidence-grade alignment checker，human 2026-10-01 采纳）：
C 级观测不得写 A 级普遍结论；「契约已要求」不得写成「运行时已具备」；
「运行时缺失」不得写成「语义必然需要」。

## 11. Harness Requirements（执行前置，非本设计授权）

```text
R0 仪器化（human 采信规则前置条件）：
  每 invocation 独立 results/{runUUID}/ 目录；
  metadata + events.jsonl（单调钟）+ summary + hashes + r0_verify；
  harness 源码提交产品仓公开（先例 0dc166b 规则——
  公开可查、可独立重放的源码 = 唯一获采信记录）
隔离：一次性 fixture 空间；~/.simigo 原始数据零触碰；
      零产品代码修改（生命周期入口原样调用）
模型：优先零 generation；确需生成 = Nail + PB1 确定性 probe
```

## 12. Gate Sequence

```text
本设计草案 → human 冻结审查（一次：设计完整性 + 边界纪律）
           → 批准后执行（O-1…O-6；结果门 = 原始事实 + 机械判读，
             无追加实验）
           → 结果归 human 第二层判读（EF-9 升格判定归 human）
```

当前无执行授权。
