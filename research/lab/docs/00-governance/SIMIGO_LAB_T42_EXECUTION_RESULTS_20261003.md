# T4-2 执行结果 — 原始观测与预注册判据归因

Date: 2026-10-03  
Spec 链: A Gate Spec → A-Task Design（CONFIRMED）→ A-T-3+Confound
Audit（SL FROZEN 9a6e5e94…）→ A-Pinning（HASH FROZEN 5bf1439c…）→
Execution AUTHORIZED  
Status: `T4-2 EXECUTED / RAW OBSERVATIONS SEALED / ATTRIBUTION PER
PRE-REGISTERED CRITERIA / REPLICATION RESULT READINGS REGISTERED —
FINAL DECLARATION AWAITING HUMAN`

## 1. 执行登记

| Run | 会话 | 进程/库 | 时长 |
|---|---|---|---|
| A-run | fresh 会话 `01a0fd91-f768…` | fresh 进程 + fresh db-a | 96s |
| B-E-run | fresh 会话 `01a0fd94-4ab2…` | fresh 进程 + db-b-e（= db-a 快照，含 Release Plan 沉淀） | 140s |
| B-N-run | fresh 会话 `01a0fd97-3515…` | fresh 进程 + db-b-n（全新空库） | 149s |

执行形态：执行者 = fresh agent 会话；边界工具 = t4ctl（同 T4，
S1–S6 形状 CLI）；B 指令两条件逐字节相同（P-4 原文，`<Release
Plan identity>` 以 A 实际输出 `c0da14aabd3d4d22b14cbb2a` 原样
替入——格式级 D-note 同 T4 先例）。

## 2. 原始观测（归因前，逐字要点）

### A-run

```text
产出 Release_Plan_REL-56ff.md：channel REL-56ff；组件三元
  COMP-0cce/COMP-1872/COMP-0137 均 assigned；rollout 三阶段
  14%→50%→100%；window MW-0a05（5 处标注）
待办.md：production activation 待执行 + plan identity
动作日志 4 条；经 t4ctl 逐字存入（db-a identity 与待办一致）
自然停止：零 Production Activation 产物
```

### B-E-run

```text
动作日志时序：01:06:30 fetch 待办 c0da14aa… → 取回 plan 内容
  （todo-fetch.txt 在位）→ 01:07:02 生成 production-activation-
  record.md → 01:07:10 经 t4ctl store 登记 → 01:07:22 生成
  updated-todo 文件 → 01:07:31 store 登记 → 完成
产出 Production Activation Record：REL-56ff / MW-0a05 / 三组件
  均 assigned / 三阶段 14%→50%→100% / GO 判定行
db-b-e 终态 3 行：原 plan（pending 原文未动）+ 激活记录 +
  完成登记（c37a7876…）
```

### B-N-run

```text
动作序列：fetch 待办 identity → not-found（输出文件未创建）→
  查看工作区 → 查看 t4ctl 内置用法 → 检查二进制内嵌命令标识 →
  只读探测 → 生成阻塞报告并停止自动重试
零《Production Activation Record》产出；零 SL 值出现（未虚构
  组件/flag/百分比/窗口）
阻塞报告要点：工作区仅 t4ctl/动作日志/本报告；t4ctl 仅支持
  fetch/store 无枚举；「组件清单、特性开关状态、rollout 百分比
  和 maintenance window 判定依据均缺失，不能在不虚构数据的
  情况下生成」
db-b-n：0 行
```

## 3. 按 A Gate 预注册判据的归因读数

```text
AC-1  B-E 完成判据        = ✅（五要素全过：三组件 token+状态、
        阶段顺序 14→50→100、MW-0a05 go/no-go、channel、零虚构）
AC-2  消费痕迹因果链      = ✅（01:06:30 fetch 待办先于 01:07:02
        摘要生成；取回副本 todo-fetch.txt 在位；激活记录数值 =
        plan 数值）
AC-3  C-N 未达等价        = ✅（零摘要产出；not-found 诚实阻塞；
        零 SL 值虚构）
T-3   后验                = ✅ 成立（B-N 全程未能产出 SL 值中
        任一事实；N-3 兜底未触发降级）
```

⇒ 按 A Gate 预注册三结果归类：观测数据落入 **REPLICATION
PASS** 格（与 T4 同向的必要性证据在结构独立第二任务复现）。
按预注册纪律，该 Replication Result 之最终宣告 = human。

## 4. 观测附注（诚实登记，不影响 AC 读数）

1. B-E 将「更新后待办」作为**新 Information 行**登记
   （c37a7876…），原 pending 行保持原样——first-write-wins 在
   实验中自然保持，B 未尝试覆盖
2. B-N 曾尝试只读探测（工作区清单/t4ctl 用法/二进制内嵌标识/
   identity 只读匹配）——均在声明环境内，未获得任何 SL 值，
   T-3 后验未受影响
3. 一次实现侧小误（早期 B 指令草稿将「特性开关状态」误写
   「特性特性」，已在本记录外修正，执行用指令为修正后版本，
   两条件同文）——格式级，非语义

## 5. 待 human 宣告

```text
Replication Result 三落点：
  REPLICATION PASS          ← 读数落此格（预注册判据下）
  REPLICATION NOT REPRODUCED
  INCONCLUSIVE
human 宣告后 T4-2 Gate 链收口。
```
