# ES-D1 Phase F — Lifecycle / Event Census

> **ARCHIVED** 2026-10-20 · line: 通用治理 / 其他 · original: docs/00-governance/SIMIGO_LAB_ESD1_PHASE_F_CENSUS_20260930.md
> Evidence status: unchanged (content frozen; moved only)


日期：2026-09-30  
状态：`D1-F CENSUS COMPLETE / STOPPED PER DIRECTIVE / GATE G NEXT（待授权）`  
研究总问题：**计算状态在什么条件下从 transient runtime phenomenon 转变为
independent durable computational asset？**（H1 Emergence / H2 Contract-only
/ H3 Partial / H4 Formation Gap 四假设待 G–J 裁定）  
方法：只读 census（file:line 均出自本轮及既往已核验底账：provenance
audit、E0/E1/E1.5/R2n/E2/E3、Gate D）；零修改零删除零新机制  
基线：产品 `dc12a0c`；Lab `431cef0`

## 1. 生命周期事件全集（13 事件普查表）

| # | Event | State-like output（P 之外的新事实） | Carrier | durable | 依赖 P | 依赖 H | authority 初判 | A/D 类 |
|---|---|---|---|---|---|---|---|---|
| E1 | turn commit（成功生成轮，T-1 自动） | transcript 副本 + generation/SHA/modelId/storageKey | checkpoint 对（meta.json 为非 P 部分） | **是** | KV 输出=P；meta 非 P | meta.history=H 副本 | 进程内=runtime 权威；进程死亡后=**survival 权威（边界项 B-1）** | DUPLICATE→post-hoc authoritative |
| E2 | 驱逐保护保存（T-2） | 同 E1 | 同 E1 | 是 | 同 | 同 | 同 E1 | DUPLICATE |
| E3 | 显式 saveSessionCache（T-3） | 同 E1 | 同 E1 | 是 | 同 | 同 | 同 E1 | DUPLICATE |
| E4 | **fork** | 新分支 checkpoint 对 + **forkPoint{sourceStorageKey, atMessage, atToken}** + 进程内 lineage record | pair + meta.forkPoint 字段（原子写入，:1830-1845）+ O records | **是**（forkPoint=代码层存在） | 副本自 P | history 副本 | forkPoint=**authoritative-but-unread**（writer 有、reader 无） | AUTHORITATIVE（unconsumed） |
| E5 | restore（loadSessionCache） | 内存注册（sessions 字典）——无新 durable 事实 | ManagedSession（内存） | 否 | **是**（P→R） | history 重建 | runtime 权威（进程内） | AUTHORITATIVE（transient） |
| E6 | eviction | 内存移除（±T-2 保存） | — | 视 T-2 | — | — | — | — |
| E7 | representation release | 绑定内存清除 | — | 否 | 是 | — | — | — |
| E8 | process restart | 破坏事件：R 层全灭；幸存者=checkpoint 对 + pool 条目 | 既有 durable 载体 | — | — | — | 幸存者见 B-1 | — |
| E9 | lineage recording | 进程内 records | ExecutionLineage（内存） | **否** | 否 | 部分 | 描述性 | DESCRIPTIVE |
| E10 | backend attach/detach（start/stop） | 无 durable 事实（trace 除外） | trace log（O） | append | 否 | 否 | descriptive | DESCRIPTIVE |
| E11 | **pool export**（轮末，pool-enabled） | pool 快照 + sidecar claims{tokenCount/modelID/kvFingerprint/chainHash} | pool 对 | **是** | **是**（KV 快照=P） | 消息链哈希源自 H | performance-P + descriptive claims | DUPLICATE/DESCRIPTIVE |
| E12 | pool admission/hit | 只读（E2：17/17 HIT 实测） | — | — | 读 P | 读 H | — | — |
| E13 | trace append | 观测行 | trace log | append | 否 | 否 | descriptive | DESCRIPTIVE |

Lab 侧事件（coordinator create/fork/continue/restore/discard、binding
bind/supersede/detach）：全部**进程内**（handles/records/registry——R/O
层，无 durable store，G-10）；无新 durable 事实，不重复列表。

## 2. Candidate carrier 登记（F 退出条件①命中）

```text
CC-1  checkpoint meta.json（E1/E2/E3 类事件的非 P 部分）
      内容 = history 副本（语义载荷）+ identity 寻址投影 + generation/
      modelId（完整性/兼容标记）+ [forkPoint/kvFingerprint：代码层载体
      存在，部署库 0 实例——版本偏差]
      ⇒ 全 census 中唯一「事件之后系统拥有 P 之外新事实」的载体
CC-2  meta.forkPoint（E4 独有）= durable lineage 片段
      （atMessage=history.count ⇒ position 代理已进入 lineage 字段——
      A2 落差的直接物证）
CC-3  pool sidecar（E11）= E2 已裁定的可替换性能表示的元数据
      （performance-P 附着物，不计入 State candidate——E2 裁定延续）
```

## 3. Source-of-truth 初判（G gate 预分类，非终判）

```text
identity      → authoritative（寻址链；E1.5-Q1 证 meta 字段值为 duplicate）
history       → 进程内 authoritative；durable 副本 = duplicate-by-write，
                post-process authoritative-by-survival【B-1 边界】
position      → 无权威实例（=history.count 推导）；forkPoint.atMessage
                为其在 lineage 字段的唯一物理出现（E4 类事件才有）
continuation  → 无权威实例（=history 末端推导）
recovery      → P + history 组合（无独立字段）
forkPoint     → authoritative（unconsumed）【G gate 须裁：writer 有
                reader 无的字段，authority 如何计？】
```

## 4. 生命周期起止（census 口径）

```text
checkpoint 对   = 起：E1/E2/E3/E4 保存成功；讫：retention 回收（预算）
meta.forkPoint  = 起：E4；讫：同 pair
pool 对         = 起：E11；讫：预算驱逐
进程内全部       = 起：事件发生；讫：进程边界（E8）
```

## 5. 依赖标注汇总

```text
P 依赖事件：E1/E2/E3（KV 输出）、E4（副本）、E5（读）、E7/E11/E12
H 依赖事件：E1/E2/E3/E4（副本）、E11（链哈希）、E5（重建）
两独立事件：无——所有 state-like 输出都同时依赖 P 或 H 之一
            （H4 formation-gap 假设的 census 侧正面证据，终判归 J）
```

## 6. 第一个无法确定的 authority/lifetime 边界（产出物 10）

```text
B-1  meta.history 的 authority 身份：
     进程内它是 runtime history 的 DUPLICATE；进程死亡后它成为唯一的
     durable 语义副本——「duplicate」与「authoritative」的分界点 =
     进程死亡这一刻，即 authority 随 survival 转移。census 层无法判定
     这种 survival-authority 是否等价于「State 被系统持有」（这正是
     Gate H 的 lifetime 问题 + human 的 A/B-form 判别标准）。
B-2  forkPoint 的 authority 计法：authoritative-but-unread 字段在
     「系统相信它」标准下算 authoritative 还是 descriptive——G gate
     裁定。
```

## 7. Gate F 退出

```text
退出条件①命中（candidate carrier = CC-1/CC-2 登记）→ 按指令停止。
G gate（Authority Test）待授权；假设 H1–H4 不预判。
禁止事项全程遵守（零修改/零新增/零 C-4/零性能）。
```
