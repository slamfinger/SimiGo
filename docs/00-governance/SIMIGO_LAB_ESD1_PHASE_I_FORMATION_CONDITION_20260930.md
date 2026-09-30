# ES-D1 Phase I Results — Formation Condition

日期：2026-09-30  
状态：`PHASE_I_COMPLETE / VERDICT = J-C PARTIAL FORMATION / AWAITING SECOND-LAYER`  
唯一问题（human 界定）：**系统从 transient computation 到 durable
computational state 之间，究竟缺少哪一个事实性生命周期转换？**  
范围：只回溯 F/G/H 已发现的事件（turn commit / checkpoint commit / fork /
restore / process death-restart / representation release / pool export）；
对每个事件裁定「事件前后是否新增了能独立识别 computation/position/
continuation/lineage 的 authoritative carrier」。禁止以增字段/增 reader/
增 State object 制造 formation。  
依据：Phase F census（`8e30510`）+ Gate G（`02643b3`）+ Gate H
（`f5b4690`）+ provenance/E0 底账。

## 1. Formation-condition 对照表（逐事件）

| 事件 | 新增 authoritative carrier？ | identity | position | continuation | lineage | 形成效果 |
|---|---|---|---|---|---|---|
| successful turn commit（运行时） | **是——但仅运行时**（history 推进 = 位置/继续点在内存中前进，Gate H：18 随进程死亡） | 运行时 | 运行时（无独立字段） | 运行时（末端） | 无 | **运行时形成、不持久** |
| checkpoint commit | **是——部分固化**（文件名=identity 寻址；meta.history=语义载荷；generation/SHA/modelId=标记） | **durable ✔** | 嵌入式（history.count 可推导 + KV 长度绑 P）——**非独立载体** | **不形成**（无 marker；继续点=transcript 末端隐含） | **不形成**（schema 无字段） | **PARTIAL** |
| fork | **是——唯一 lineage 形成事件**（forkPoint{sourceStorageKey, atMessage, atToken} 原子写入 target meta） | durable ✔ | **position 代理入 durable lineage**（atMessage）——唯一物理实例路径 | 不形成 | **durable 片段 ✔（但 writer-only：零 reader + 部署库 0 实例）** | PARTIAL（lineage-only，unconsumed） |
| restore | 否（P→R 消费；无新 durable 事实） | — | — | — | — | 无形成 |
| process death / restart | 否（破坏事件：R 层全灭；幸存者=checkpoint 对+pool） | — | — | — | — | 无形成（生存检验） |
| representation release | 否（内存解绑） | — | — | — | — | 无形成 |
| pool export | 是——但为性能-P + descriptive claims（E2 裁定） | — | — | — | — | 非-State 形成 |

## 2. 逐维度形成结论

```text
identity    = FORMED（checkpoint commit → 寻址链 durable；跨进程/跨表示
              存活——E1-R0/Gate H 实测）
history     = FORMED（checkpoint commit → meta.history 副本 durable；
              R2n/E3 实证 continuation-bearing）
position    = NOT FORMED as independent carrier。事实在形成时机在场
              （performSave 持有 managed.history，count 已知），但
              SessionCacheMetadata schema 无 position 字段——
              【形成时机信息在场、形成事件未捕获】。仅两处代理实例：
              meta.history.count（可推导）与 forkPoint.atMessage
              （仅 fork 事件）
continuation= NOT FORMED。继续点 = transcript 末端，隐含于 history
              副本；无独立 marker 字段/记录（同上：在场未捕获）
lineage     = PARTIALLY FORMED：唯一形成事件 = fork（forkPoint）；
              writer-only、零部署实例；非 fork 路径完全不形成
recovery    = FORMED as P+markers（表示完整性），表示门控
```

## 3. Formation gap 的精确形态（本 gate 核心产出）

```text
 formation gap ≠ 「缺少一次形成事件」
 formation gap = 【形成事件存在（checkpoint commit），且形成时刻信息
                  在场（position/continuation/lineage 事实 runtime 可知），
                  但形成 schema 不捕获它们】
 + 唯一例外 = fork 事件的 forkPoint（lineage 片段形成存在，但
   unconsumed + 零部署实例）
```

这是 F/G/H 三门事实的合成：F 证明事件存在且产出非 P 事实（transcript
副本）；G 证明哪些字段 authoritative（identity+history）哪些 derived
（position/continuation）；H 证明 authority 结构跨边界保持、且 position
持久性被 checkpoint 事件门控。三者合成 ⇒ **formation 是部分发生的
（J-C）**，且断点位置精确可指：checkpoint commit 的 durable schema。

## 4. 裁定

```text
VERDICT = J-C — PARTIAL FORMATION
（J-A Natural Formation 被排除：无事件形成独立 position/continuation/
  lineage 权威载体；J-B No Formation 被排除：identity+history 的形成
  真实发生；J-C Partial Formation 成立——形成事件存在、信息在场、
  schema 不捕获，外加 fork 的 unconsumed lineage 片段形成）
```

按纪律登记（非设计提议）：形成断点的结构位置 = checkpoint commit 的
durable schema（SessionCacheMetadata 字段集）；结构性落差（Contract
五元 vs 该 schema）至此获得形成条件级的精确定位——观察登记，修复归
未来独立 gate。

## 5. Non-claims

```text
✔ 纯合成裁定（F/G/H 事实倒推）；零新实验、零修改、零机制设计
✔ J-C 限于当前系统当前 corpus；非 PALACE 普适命题
✔ 不构成任何修复/字段新增授权；ES-D1 Phase I = 终 gate，待第二层总审
✔ RF-1（语义缺席虚构）不受影响；C-4 续锁
```
