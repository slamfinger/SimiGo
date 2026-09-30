# ES-R1 Gate H Results — Lifetime Test

日期：2026-09-30  
状态：`GATE_H_COMPLETE / VERDICT = H-B (FORMATION GAP EVIDENCED) / AWAITING SECOND-LAYER`  
唯一问题（human 界定）：**CC-1 的 partial authoritative information 在
表示消失、进程结束/重启之后，哪些仍作为 authoritative information 存活？
推导出的 position/continuation 跨生命周期后是否仍具同样语义有效性？**  
执行：双真实进程实验（SideA 进程 A：restore(17)→probe→推进至 18（仅
内存，tunables off 不落盘）→退出；SideB 全新进程：durable 检查→
restore→同 probe→对照 O_A）；隔离配方同前（零 durable 写入，204 前后
核验）；观测 `gateH-observations.jsonl`（已落库）。

## 1. 双进程实测记录

```text
进程 A（SideA，48.7s）：
  restore → position 17 → probe → O_A =「你是想继续查看其他目录吗？
  比如：- **三公司管理制度及规定**（另一个4号文件夹）- **国家及地方法」
  （55 字符）→ 推进至 position 18（仅内存）→ 退出（无 checkpoint）
进程 B（SideB，36.0s，全新进程）：
  durable 检查：checkpoint 位置 = 17（runtime 18 已随进程 A 死亡）
  restore → position 17（非 18）
  同 probe → O_B = O_A 逐字相同
  → O_B_equals_O_A = YES
```

## 2. 观察矩阵（三边界 × 七维度）

| 信息 | P 消失后 | Process 死亡后 | Restart 后 | Authority 来源 |
|---|---|---|---|---|
| identity | 存活（E1-R0：meta/文件名） | 存活（文件名） | 存活 | caller key/文件名 |
| history（语义载荷） | 存活（meta，SHA 冻结核验） | 存活（meta） | 存活（meta） | meta/history |
| position | 推导存活（=history.count） | **checkpointed 17 存活；runtime 18 死亡（本轮实测）** | 重导出（=17） | history.count——**事件门控**（仅 checkpoint 提交时固化） |
| continuation | 推导存活（history 末端） | 推导存活 | 重导出（本轮 O_B 语义有效） | history 末端 |
| lineage | 不存活（forkPoint 缺席；进程 records 死） | 死亡 | 不存活 | forkPoint（代码级载体，0 部署实例） |
| model compatibility | 存活（meta.modelId 门） | 存活 | 存活 | modelId |
| representation integrity | 死亡（P 已删，SHA 指向消失目标） | 指针存活/目标消失 | 同 | SHA/generation |

## 3. 裁定

```text
VERDICT = H-B — 只有 identity + history 以权威形式跨边界存活；
          position/continuation 每次都必须从 history 重新推导；
          formation gap 在运行时层获得直接实验证据。
```

精确事实（本轮新增，避免过度解读）：

```text
① position 的持久性是【事件门控】的：position 17（checkpoint 提交时
   固化）跨进程存活且权威；position 18（runtime 推进、未 checkpoint）
   随进程死亡——同一字段的两个值，一个存活一个死亡，分界线 =
   最后一次 checkpoint 事件。
② 存活的 position 17 并非独立 carrier：它嵌在 checkpoint 对
   （P+meta）中，与表示绑定；Gate D 的「无独立五元 carrier」结论在
   运行时层保持一致。
③ re-derived position/continuation 跨边界语义有效（O_B = O_A）——
   「还能算出来」成立，但按纪律这记为「可推导」，不记为「State 存在」。
```

## 4. 与 Gate G 的合流（partial authority + lifetime）

```text
Gate G：identity authoritative（independent）+ history surviving-
        authoritative（lifecycle-dependent）+ position/continuation
        derived
Gate H：上述 authority 结构跨表示丢失 + 进程死亡 + 重启全部保持——
        存活/死亡的分工不变，且 position 的「事件门控持久性」被
        双进程实验直接演示
⇒ H-B 成立：formation gap 位于「checkpoint 提交事件只固化表示+history
  副本，从不固化 position/continuation/lineage 载体」
```

## 5. Non-claims

```text
✔ 单样本、贪心、两进程——结论限于当前系统当前 workload
✔ 未做 Sufficiency（Gate I 待授权）；未答 Formation（Gate J）
✔ 未新增 State object/字段/persistence；未给 forkPoint 加 reader
✔ 真实 store 204 项前后核验不变
✔ 「position 18 死亡」是配置使然（tunables off）的实验性生命周期终点，
  非产品缺陷判定
```
