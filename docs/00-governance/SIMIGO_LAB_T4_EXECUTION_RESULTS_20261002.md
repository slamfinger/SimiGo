# T4 执行结果 — 原始观测与预注册判据归因

Date: 2026-10-03（run 时间 2026-10-02 夜间）  
Spec: `SIMIGO_LAB_T4_EXPERIMENTAL_DESIGN_GATE_SPEC_20261002.md`（预注册）  
Pinning: `SIMIGO_LAB_T4_TASK_PINNING_DRAFT_20261002.md`（fb9ae62，
human 已授权执行，授权范围 = 冻结钉定包，零修改）  
Status: `T4 EXECUTED / RAW OBSERVATIONS SEALED / ATTRIBUTION PER
PRE-REGISTERED CRITERIA / AWAITING HUMAN RULING`

执行纪律声明：本件先录原始观测，后按预注册判据归因；归因仅为
按 S-6 判据的读数，**最终裁定（强命题/弱命题/无归因）= human**。

## 1. 执行登记

| Run | 会话 | 进程/库 | 时长 |
|---|---|---|---|
| A-run | fresh 会话 `01a0fd65-9591…` | fresh 进程 + fresh db-a | 70s |
| B-E-run | fresh 会话 `01a0fd67-9802…` | fresh 进程 + db-b-e（= db-a 快照，含 A 沉淀） | 186s |
| B-N-run | fresh 会话 `01a0fd6a-b2b6…` | fresh 进程 + db-b-n（全新空库） | 239s |

执行形态（执行授权时钉定）：执行者 = fresh agent 会话；边界工具
= t4ctl（InformationStore S1–S6 契约的薄 CLI 包装：store 逐字/
fetch by identity/absence=not-found）；B-E 库 = db-a 快照（物理
filing 迁移，boundary 内容 = A 沉淀）；B-N 库 = 全新空库；B 指令
两条件逐字节相同（P-4 原文，`<A 沉淀 identity>` 以 A 实际输出
`9fd1608770a655473b18cddf` 原样替入——P-4 的 `information-` 前缀
为格式示例，实际 identity 为纯 hex，替换即钉定所指；登记为
格式级 D-note，非语义偏离）。

## 2. 原始观测（归因前，逐字要点）

### A-run

```text
产出 ledger.md：三行分配（SUP-9b47|865671|1021491.78、
  SUP-93dc|273063|322214.34、SUP-c1fa|722204|852200.72）+
  预留总额 2195906.84（记录者独立算术复核一致）
todo.md：第二阶段待生成 + identity 9fd1608770a655473b18cddf
动作日志 4 条；经 t4ctl 逐字存入（db-a identity 与 todo 一致）
自然停止：零第二阶段产物
```

### B-E-run

```text
动作日志时序：00:17:24 fetch 待办 9fd1608770a655473b18cddf →
  取回 9fd1608770a655473b18cddf.md → 查看工具帮助 → 生成
  合同摘要.md → 待办完成状态登记（identity 32390793…）→
  自我校验（一次瞬时混淆：误用更新后待办标识比较状态登记，
  自行复核纠正）→ 完成
产出 合同摘要.md：SUP-9b47|1,021,491.78 / SUP-93dc|322,214.34 /
  SUP-c1fa|852,200.72 / 总额 2,195,906.84 / 保证金 43,918.14
  ——与冻结期望值逐项一致（数值相等，千分位格式差异）
另存 9fd1608770a655473b18cddf.md（取回副本）、待办状态登记.md、
  验证文件 ×4（自我校验副本）
db-b-e 终态 4 行：台账 / 摘要 / 状态登记 / 更新后待办
```

### B-N-run

```text
动作序列：fetch 待办 identity → not-found（未重复同一命令）→
  检查工作区既有文件 → 查看工具帮助 → 检查工作目录文件 →
  检查 t4ctl 二进制字符串（寻找枚举/诊断能力）→ 写入并取回
  哨兵（验证通路正常，identity 91576421…）→ 阻塞报告：
  「无法定位第一阶段上下文；缺失供应商代码与预留金额，不能
  安全生成真实摘要」
零《合同摘要》产出；零 F1–F6 数值/代码出现（未虚构）
db-b-n：1 行 = B-N 自写哨兵（非 F1–F6 内容）
```

## 3. 按 S-6 预注册判据的归因读数

```text
AC-1  C-E 完成判据        = ✅（五项数值与冻结期望逐项一致）
AC-2  消费痕迹因果链      = ✅（00:17:24 fetch 待办/台账 →
        00:18 生成摘要；取回副本文件在位；摘要数值 = 台账数值）
AC-3  C-N 未达等价        = ✅（零摘要产出；not-found 阻塞；
        未虚构 F1–F6）
T-3   后验                = ✅ 成立（C-N 全程未能产出 F1–F6 中
        任一事实；N-3 兜底未触发降级）
```

⇒ 按 S-6 预注册三结果归类：观测数据落入 **强命题格**
（AC-1 ∧ AC-2 ∧ C-N 未达等价 ∧ T-3 成立）。按 S-9，该声明之
最终裁定 = human。

## 4. 观测附注（诚实登记，不影响 AC 读数）

1. B-E 一次瞬时自校验混淆（误用更新后待办标识比较状态登记），
   自行复核纠正——过程记录在案
2. B-N 曾探测 t4ctl 二进制字符串寻找枚举能力（声明环境内的
   工具本体，无 F1–F6 内容）并写入自验证哨兵——均为声明环境
   内动作，T-3 后验未受影响
3. B-N db 含其自写哨兵 1 行（非沉淀、非 F1–F6）
4. 两 B-run 会话各自工作区内未出现任何 SimiGo-Lab 仓或 A/B
   声明通道之外的文件（工作区清单审计）

## 5. 待 human 裁定

```text
裁定项 = T4 归因落格：
  强命题（boundary = continuation 必要条件，本任务域）
  / 弱命题 / 无归因 / 实验无效
裁定依据 = 本件 §2 原始观测 + §3 预注册判据读数
```

T4 已执行完毕；T4 语义裁定前，**不开启任何新 Gate**（除 human
另指令）。
