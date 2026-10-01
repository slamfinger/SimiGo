# PALACE-1 Lifecycle Storage Opening Draft — 七操作 Durable 语义映射

日期：2026-10-02  
状态：`DRAFT / PARTICIPANT PROPOSAL（未注册，未激活）`  
Gate：`PALACE1_LIFECYCLE_STORAGE_OPENING（definition gate only）`  
授权来源：human 方向指令「研究 PALACE——可灵活拓展、长期存储 Execution
State、并适配七操作 lifecycle」（2026-10-02）——本 draft 视为 framing
registration 预留的显式 gate 重入；不消费 framing 之外的任何内容  
上游语义参照：Execution State Contract v1.0-amended（freeze candidate，
七操作 lifecycle）  
证据锚：PALACE-1 Framing Registration（`739b967`）· Evidence
Consolidation（`d408729`）· ES-D1 Seal（`180b065`，J-C）· ES-R2 Gate
A/B（`24c4a97` / `92b18c0`）  
性质：participant proposal——不实现、不选库、不解决 OP/G、不触发实验

```text
registered engineering fact ≠ contract-derived hypothesis ≠ selected implementation
```

## 0. §0 并发核验结果（2026-10-02）

```text
git fetch / LOCAL = REMOTE       = 25e1a79 ✓
worktree clean                   = 0 项 ✓
PALACE framing 登记后线状态      = PARKED（framing 未被任何后续登记
                                   消费或修改）✓
Contract v1.0-amended            = freeze candidate / AWAITING FINAL
                                   FREEZE DECLARATION（human）✓
OP-1…OP-7 / G-7 / G-10 台账      = 无未登记漂移 ✓
→ 重入条件：human 显式方向指令（本 draft 授权来源）已满足
```

## 1. 研究问题（固定）

> PALACE 作为 Execution State 的长期 durable 存储层，其记录语义必须
> 满足什么最小集合，才能使 Contract v1.0-amended 的七操作 lifecycle
> （create / fork / continue / save / restore / discard / release）在
> 跨进程、跨时间、跨 backend、Physical Representation 丢失/替换的
> 全部边界上保持可断言、可验证、fail-closed——且存储载体本身可替换、
> 可扩展？

三个不可合并的子目标（继承 framing 生命周期分离纪律）：

```text
F1 灵活拓展   存储载体可替换、声明可版本化（storage-agnostic）
F2 长期存储   durable 记录独立于 runtime / 进程 / backend / P 存活
F3 七操作适配 每个生命周期操作在 durable 层有可验证的义务承接
```

三者暂时禁止合并论证：一种可替换的存储不自动长期有效；长期存活的
记录不自动满足七操作义务；满足七操作义务的记录集不自动可替换。

## 2. 可消费的已注册证据（分层，本 draft 的唯一事实来源）

### 2.1 工程事实（已登记实验链，CONFIRMED 级）

| 编号 | 事实 | 来源 |
|---|---|---|
| EF-1 | durable semantic side（caller key + conversation history 含 tool 历史）与 physical acceleration side（checkpoint / Prefix Pool）生命周期不同；后者可消失/替换/重建 | Framing Registration；E0–E3 链 |
| EF-2 | continuation-bearing 语义位于会话正文（含 tool 历史），不在 system persona、不在寻址/保护/兼容字段 | E3（C-0…C-3，4/4 预登记） |
| EF-3 | 语义缺席失败模式 = 自信虚构而非 fail-closed（RF-1，OPEN） | E3-C-2；Evidence Consolidation |
| EF-4 | Formation gap 位于 checkpoint commit boundary：identity + semantic history 跨界，position / continuation 仅可推导，lineage 仅部分形成（forkPoint latent） | ES-D1 J-C（`180b065`） |
| EF-5 | Tier-1 最小充分集 {storageKey, position: N, continuation-anchor: tail(N)}——标量字节、formation 时刻全部在场；捕获即形成独立权威 State 记录 | ES-R2 Gate A（R2-A） |
| EF-6 | Tier-1 carrier 在 P 丢失 + 进程死亡双边界后 SURVIVED（identity/position/anchor 全部仅凭 carrier 读出） | ES-R2 Gate B（STATE-SURVIVES） |
| EF-7 | Tier-2（不读 history、不用旧 P 的再物化）在观察宇宙内 INSUFFICIENT——缺口是「一类不存在的载体」而非字段 | ES-R2 Gate A（FSB-2） |
| EF-8 | restore 验收边界实测：storageKey 字段值=informational、history 无完整性门、modelId=兼容门、generation=presence-only、cacheSHA256=仅 safetensors 字节 | E1.5（6/6 预登记） |
| EF-9 | durable 身份分配/跨重启 reservation 不存在（caller-supplied opaque string）；Lab 无 durable Execution State store | G-7 / G-10（NOT CLOSED） |
| EF-10 | 产品已存在 durable writer：branch checkpoint（62/64 GiB）+ prefix pool（15/16 GiB），成对回收、ownership-aware | Writer Provenance Audit |
| EF-11 | KV tensor 本身不构成 Execution State；缺关系条件时恢复不能可靠继续 | ES Stage Conclusion §2.1 |

### 2.2 契约推导（semantic hypothesis 级，非工程事实）

| 编号 | 内容 | 来源 |
|---|---|---|
| CH-1 | MUST BE DURABLE 最小集 = SC-2 七字段（id + lineage.root + lineage.parent + position + continuation.nextInput + continuation.continuationID + lifecycle）+ tombstone closure data；binding relations OPTIONAL | Architecture Contract SC-2；Phase B |
| CH-2 | 语义演化仅经登记事务窗口（fork：物理 derive 先行；restore：物理 restore 先行；discard：物理 release 先行；bind：restore 后记录） | SC-3 |
| CH-3 | 七操作义务表（§5 原文：create 明确 identity 绑定+初始 position；fork 双侧 anchor 相等+parent 非污染；continue 严格前缀延接+provenance 可断言；save durable 固化+原子+溯源+非语义 mutation；restore I/P/A 可再断言+C 可再接续+fail-closed；discard 无 ghost continuation+原子；release 绑定清空+无残留+可重试；eviction=release 族） | Contract v1.0-amended §5 |
| CH-4 | D3 场景判定（restore/reattach/rematerialization/recompute/backend-replacement/representation-loss 全 SAME；closure 破损 loud fail；NEW 仅 create/fork） | D1–D4 scaffold（降级为 hypothesis） |

**纪律**：CH 级内容在本 draft 中一律标注 `HYP`；任何升格必须走独立
实验 gate。D1–D4 draft 的「概念先行」降级教训（physical reality 前置）
为本节的方法论约束：本 draft 只做【已注册工程事实 → 七操作 durable
缺口】的映射，不重新推导语义答案。

## 3. 七操作 × durable 层映射（研究映射，非设计裁定）

每行 = Contract 义务（CH-3 原文语义）+ 已注册工程事实 + PALACE 承接
缺口。`HYP` 标注 = 该承接为契约推导，证据化是本线后续 gate 的工作。

| 操作 | durable 层缺口（工程事实侧） | PALACE 承接候选（HYP） |
|---|---|---|
| **create** | identity 分配/跨重启 reservation 不存在（EF-9）；create 不预设 carrier，但长期存储下 identity 唯一性不能依赖调用方纪律 | durable identity reservation 记录（OP-2/G-7 承接）；create 时点即分配并持久化，uniqueness 由 store invariant 保证 |
| **fork** | lineage 仅部分形成：forkPoint writer-only、latent、零部署实例（EF-4）；anchor(child@fork)==anchor(parent@fork) 目前无独立 durable 记录 | fork 边界 durable lineage closure 记录（双侧 anchor 快照 + parent 不可变标记）；tombstone 可解析性继承 Phase B condition 1 |
| **continue** | position/continuation 无权威实例、由 history 推导（EF-4）；Tier-1 carrier 已证可形成并存活（EF-5/6），但产品 schema 不捕获 | 每次 continue 的 durable (position, anchor) append 记录；provenance 链 = Tier-1 记录序列，衔接 EF-2 的语义载体（history） |
| **save** | formation gap 恰在此边界：checkpoint 固化 representation + semantic history，未捕获 position/continuation 为独立 carrier（EF-4） | save 必须（a）固化 P 族，（b）固化 semantic snapshot，（c）固化 Tier-1 formation record 为独立权威记录；原子性覆盖三者（HYP：Gap 闭合 = (c) 落地） |
| **restore** | restore 验收=表示完整性门（EF-8），对 durable 记录无核对；语义缺席静默虚构（EF-3/RF-1） | restore 验证对象从「表示完整性」扩展为「durable 记录一致性」（Tier-1 + history）；fail-closed 子句的 durable 层对应物 = 记录不一致即 loud fail |
| **discard** | tombstone closure data MUST BE DURABLE 且独立持久化（CH-1/Phase B condition 1，HYP）；产品层 lifecycle tombstone 无明确物理表达 | discard = 逻辑 tombstone 先行、closure 数据独立持久（不可由 O 层 history 重建）；原子序 = CH-2 窗口语义 |
| **release** | 成对回收机制已存在（EF-10），但其义务面是资源层，非契约层 | release/eviction 扩展至 durable 记录：绑定清空 + 无跨状态残留 + 失败可重试；资源压力机制不得成为契约外路径（CH-3 原文） |

映射的总体形状：

```text
PALACE durable record 族（候选，HYP）
├── identity reservation record      ← create（EF-9 缺口）
├── lineage closure record           ← fork / discard（EF-4 缺口）
├── continuation record (Tier-1 序列) ← continue / save（EF-5/6 已证载体形状）
├── semantic snapshot record          ← save（SC-2 七字段，CH-1 HYP）
├── tombstone record                  ← discard（CH-1 HYP）
└── representation binding relation   ← OPTIONAL（CH-1 原文）

物理 acceleration side（checkpoint / Prefix Pool）
= 可替代表示，PALACE 只保存可选 binding，不收编（EF-1 纪律）
```

## 4. F1 灵活拓展：storage-agnostic 声明模式

不选型、不定义 schema。拓展性来自复用 Representation Contract 已冻结
的声明-验证模式，把「PALACE store」也变成声明面而非实现面：

```text
PALACE Store Declaration（模式借用，本 draft 不定义内容）
  Σ_S      record schema（七类记录的声明）
  Carrier  载体语义（每类记录是什么、不是什么）
  Inv_S    record 良构不变式
  Rules_S  推导规则封闭集（含显式缺席规则）
  映射义务  invariant→rule 映射表（N-2 模式）
  Required_S  哪些功能 Required / Compensated（附证据级）
  合格性    版本钉定 conformance battery（N-6 模式），
           不靠字段相似性判断
```

由此：

```text
本地文件 / SQLite / KV / remote service / 未来形态
= 不同的 Store Declaration，零 Semantic 变更
存储替换 = 新声明 + 电池重跑（契约既定路径，非架构手术）
长期演化 = 版本钉定 + closure-revision 级事件（仅语义变更时）
```

该模式的合法性直接继承 Contract §3/§6/§8（表示可变、不变式不变、
版本钉定电池），本 draft 不新增契约机制。

## 5. F2 长期存储：存活边界与 UNKNOWN

已证（工程事实）：

```text
EF-6  Tier-1 carrier 跨 P 丢失 + 进程死亡存活
EF-1/2  durable semantic side（caller key + history）独立于 P 存在
```

未证（本线核心命题，不预答）：

```text
U-1  七类记录集在【全消失恢复】下的充分性
     （Gate B 证的是 formation/identity 存活；非无 history 的完整 restore）
U-2  lineage/tombstone 载体类的 formation 证据
     （forkPoint latent，从未运行时观测——需 Gate B 同级的实验）
U-3  restore 对 durable 记录的核对判据集
     （EF-8 只有表示完整性门；记录一致性门不存在）
U-4  跨时间/跨载体迁移后 identity 连续性
     （版本钉定电池模式未在七操作全链验证）
```

U-1…U-4 与 OPEN 台账关系：U-1 继承 D-scaffold UNKNOWN（七字段充分性）；
U-2 继承 EF-4；U-3 继承 reopen 机制问题；U-4 继承 N-6。无一被本 draft
关闭；OP-1（transcript 等价）继续 OPEN 且约束 U-3（transcript-derived
recovery 分类未决）。

## 6. F3 七操作适配的验证纪律（后续 gate 预告，本 draft 不执行）

每个 HYP 承接升格为工程事实所需的证据形状（沿用已登记实验范式）：

```text
create   identity reservation 跨重启唯一性观测（对照 EF-9）
fork     fork 边界双侧 anchor 记录的 formation + 存活观测（Gate B 范式）
continue (position, anchor) append 的跨进程续接观测（PB1/Gate B 范式）
save     三组分原子固化的崩溃窗口观测
restore  记录一致性门的 loud-fail 矩阵（E1.5 范式扩展）
discard  ghost-continuation 排除观测
release  契约义务面回收观测（EF-10 资源面扩展）
```

实验授权不在本 draft 内；矩阵仅为 boundary 声明。

## 7. 与既有 gate 的关系（不消费、不关闭）

```text
OP-1（transcript 等价）        OPEN，约束 U-3
OP-2 / G-7（identity 分配）    OPEN；本 draft 将其定位为 create 承接
                               的前置依赖，不解决
OP-3 / G-10（durable store）   OPEN；本 draft 即其消费前的 definition
                               gate，选型仍禁止
OP-5（binding claim 政策）     OPEN；binding relation OPTIONAL 地位不变
OP-7（PALACE 接口）            OPEN；P7 消费前须独立 bridging
                               registration，本 draft 不预答 OP-7-1/2/3
RF-1（语义缺席不可检测）       OPEN RESEARCH；restore 记录核对（U-3）
                               是其相邻问题但本 draft 不设计机制
ES-R2 Gate C/D                 LOCKED（授权归 human），本 draft 不触碰
Contract v1.0-amended          只消费不修改；final freeze declaration
                               独立归 human
```

## 8. Prohibitions（逐字写死）

```text
❌ database selection（SQLite / KV / graph / vector / event log / remote）
❌ PALACE schema / record 字段布局定义
❌ persistence API / serialization format / 存储事务协议
❌ RF-1 解决机制设计
❌ 产品代码修改 / durable 写入实验
❌ 性能基准
❌ 修改 Contract / I/P/A/C / SC-1…SC-3
❌ 消费 OP-7 或替 P7 预答
❌ 以解释关闭任何 OP/G
❌ 收编 physical acceleration side（checkpoint / Prefix Pool 仍为可替代表示）
```

## 9. 输出分类（CONFIRMED / HYP / OPEN / DEPENDENT / UNKNOWN）

```text
CONFIRMED（工程事实级）
  §2.1 EF-1…EF-11（全部引用已登记链，本 draft 零新增事实）
  §3 映射表中标注工程事实侧的缺口定位（EF 编号可追溯）

HYP（契约推导级，需独立证据升格）
  §3 七类 durable record 族
  §4 Store Declaration 模式对存储面的适用性
  CH-1…CH-4 的全部继承判定

OPEN
  U-1 七记录集全消失恢复充分性
  U-2 lineage/tombstone 载体 formation 证据
  U-3 restore 记录核对判据集
  U-4 跨载体迁移 identity 连续性
  OP-1 / OP-2 / OP-3 / OP-5 / OP-7 / RF-1（原样携带）

DEPENDENT
  create 承接 ← OP-2 / G-7
  U-3 判据 ← OP-1（transcript 等价未决）
  binding relation 语义 ← OP-5 / Phase B condition 3

UNKNOWN
  七操作全链在 P 全丢失 + 进程死亡 + 载体迁移叠加下的
  same-State 恢复能力（Gate B 结论的外推禁止）
```

## 10. Gate sequence

```text
本草案 → human 第二层判断（重入合法性 + 范围裁定）
       → external review（六项固定：Contract fidelity / lifecycle
         obligation 对齐 / fact-hyp 分层纪律 / F1-F2-F3 不可合并性 /
         OP-G 台账完整性 / scope discipline）
       → PASS / ACTIVATION_REQUIRED → registration
       → 后续实验 gate（§6 矩阵逐项授权，一次一项）
```

当前无实验授权、无实现授权、无选型授权。
