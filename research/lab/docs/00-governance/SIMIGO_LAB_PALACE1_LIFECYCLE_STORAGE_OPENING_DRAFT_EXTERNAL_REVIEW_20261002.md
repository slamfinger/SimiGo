# PALACE-1 Lifecycle Storage Opening Draft — External Review

日期：2026-10-02  
Review artifact：`docs/00-governance/SIMIGO_LAB_PALACE1_LIFECYCLE_STORAGE_OPENING_DRAFT_20261002.md`（rev.1）  
Reviewed commits：`05f4624`（draft）+ `777846e`（entry refresh）+ `3d72485`（rev.1）  
Verdict：`PASS / ACTIVATION_REQUIRED（附两项非阻断修订，修订后即达
registration 门）`  
Role：external methodological review only——本文件是 review decision，
不是 repository registration；PASS 不激活 opening、不授权实验/实现/选型

## 1. 六项固定审查

| # | 审查项 | 结果 | 依据 |
|---|---|---|---|
| 1 | Contract fidelity | **PASS** | 七操作义务引用与 Contract v1.0-amended §5 逐条一致；CH 项全部标注 hypothesis 且来源归属正确（rev.1 已精化至 Architecture Contract v1.0 SC-2/SC-3，冲突让位于 v1.0-amended）；零契约修改 |
| 2 | lifecycle obligation 对齐 | **PASS** | create/fork/continue/save/restore/discard/release 七操作全部映射；每行 = 契约义务 + EF 工程事实缺口 + HYP 承接候选；eviction=release 族与 save 非 mutation 约束原文保留 |
| 3 | fact-hyp 分层纪律 | **PASS** | EF-1…EF-11 全部可溯源至已登记链（附录 A 逐条含 commit + 原文摘引，哈希已在仓内核证）；CH 一律 HYP；U-1…U-4 诚实 UNKNOWN；EF-11 复制状态标注保留（rev.1）；D1–D4 概念先行教训写入方法论约束 |
| 4 | F1-F2-F3 不可合并性 | **PASS** | 三子目标分别以声明模式（§4）/存活边界（§5）/逐操作义务（§3+§6）独立论证；§1 显式禁止合并论证且正文未违反 |
| 5 | OP-G 台账完整性 | **PASS with amendment required** | 见 §2 Finding F-1——原稿 §7 遗漏 OP-4 / OP-6 / RF-2 / RB-1…RB-8 / IC-1…IC-5 携带行 |
| 6 | scope discipline | **PASS** | 禁止清单逐字覆盖：选库/schema/persistence API/RF-1 机制/产品代码/性能基准/改 Contract/消费 OP-7/关闭 OP-G/收编 physical acceleration side；§6 实验矩阵仅为 boundary 声明非授权 |

## 2. Findings（非阻断，修订义务）

### F-1 §7 关系台账不完整（修订后方满足审查项 5）

原稿 §7 携带了 OP-1 / OP-2+G-7 / OP-3+G-10 / OP-5 / OP-7 / RF-1 /
ES-R2 Gate C/D / Contract，但遗漏：

```text
OP-4  contract-level cancellation surface（G-9）——本 draft 映射未消费，
      但台账必须显式「携带不关闭」
OP-6  工程 gaps G-1/G-2/G-3/G-4/G-5(L-1)/G-8——同上
RF-2  restore dependency ≠ continuation dependency（CLOSED FOR CHAIN）
      ——draft 的 restore 映射事实上依赖该已关闭结论，须显式引用
RB-1…RB-8  四态结果法则——restore/discard/release 承接候选均不得
      绕过 reattach/loud-fail/rematerialization/fail-closed 出口
IC-1…IC-5  SAME/NEW 与终态法则——discard 映射（终态 tombstone、
      重复创建 fail-closed）、restore 映射（SAME 不因表示事件破坏）
      直接继承这些法则，须显式携带
```

处置：draft rev.2 补齐 §7 携带行（已随本 review 执行）。补齐后审查项 5
由 PASS-with-amendment 转 PASS。

### F-2 §10 gate 序列的重入合法性归属（说明性修订）

原稿 §10 将「human 第二层判断（重入合法性 + 范围裁定）」列为第一门。
核验：framing registration 明示「当且仅当未来工程事实需要消费本
framing 时，才从显式 gate 重新进入」——2026-10-02 human 方向指令
（研究 PALACE：可灵活拓展、长期存储 Execution State、适配七操作
lifecycle）即为该显式 gate 重入授权本身，重入合法性已确立。据此 §10
标注该步骤由指令满足；**registration 门保留 human 不变**（Phase B
先例：draft → external review → human registration）。

## 3. Boundary check

| Boundary | Result |
|---|---|
| No SQLite / KV / graph / vector / event log / remote selection | PASS |
| No PALACE schema / record layout | PASS |
| No persistence API / serialization / storage transaction protocol | PASS |
| No RF-1 mechanism design | PASS |
| No product code modification / durable-write experiment | PASS |
| No performance benchmark | PASS |
| No Contract / I-P-A-C / SC modification | PASS |
| No OP-7 consumption / OP-G closure by interpretation | PASS |
| Physical acceleration side not absorbed | PASS |
| No experiment/implementation authorization granted | PASS |

## 4. Verdict

```text
六项固定        = 5 PASS + 1 PASS-with-amendment（F-1）
F-1             = 已随 review 修订（draft rev.2 §7 台账补齐）
F-2             = 已随 review 修订（draft rev.2 §10 归属标注）
Verdict         = PASS / ACTIVATION_REQUIRED
下一门          = human registration（唯一剩余 human 步骤；
                  registration 后方可按 §6 矩阵逐项申请实验 gate）
本 review 不授权：实验 / 实现 / 选型 / registration
```
