nodes-out Experiment runner 实现已按 UNLOCK 门启动。实现 Candidate A 前,有一个操作化决策需要你确认(不确认我不执行 correctness audit 与采数):

## Candidate A 操作化提案(从 P0 探针结构推导,非凭空发明)

node KV 拆分为两个 unit:
- **GDN unit = 61,440 KiB**(P0 实测固定底价,不可压缩部分)
- **attention unit = 16,806 KiB**(P0 实测可变部分)
- 两 unit 均可独立 externalize/rehydrate = **KV 粒度外化通道**
- node decode 需两 unit 均驻留(NORM① 触碰时自动补齐,与 v6 语义一致)
- 策略在 unit 粒度运行(LRU/lfu_aging 语义从 node 平移到 unit)
- 78,246 KiB/node = GDN+ATT 之和,其适用性重验证 = 实验输出之一(不预判)

依据:P0 探针实测"GDN 固定底价 + attention 随深度增长"是唯一有实测依据的 node 内 KV 结构拆分;除此之外的任何拆分都是无实测基础的发明。

## 三层 correctness audit 设计(随操作化更新)

- **L1 event-level**:Candidate A 每个外化/迁回事件完成时所在 decode step t,该 unit 的 KV version(= 该 node 被 trace 触碰的累计次数,trace 驱动与 residency 决策无关)与基线执行同一 step t 的 version 对齐等价;
- **L2 step-level**:每个 decode step 的 continuation 语义(next input、全部 unit 的 KV version)与基线执行逐项等价;
- **L3 terminal-state**:trace 结束后全部 64 个 unit 的 KV version ≡ 基线。

成本通道:Ch1 = migration/re-encoding event count + bytes moved/read + timing(identity mapping,0 modeled conversion cost,无 token-equivalent,无 ±敏感性);Ch2 = violation count + location(v1 不货币化);Ch3 = 计账适用性判定;J 兼容披露(unit 事件计数×C_ext/C_rehy)。

## 请确认

① GDN/ATT unit 拆分作为 Candidate A 操作化是否接受?②三层 audit 设计是否达标?确认后我完成 runner 实现并执行 correctness audit,结果入档后交你署名。
