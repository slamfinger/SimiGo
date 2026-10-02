# T4-2 Task Pinning Package（七件钉定包 / HASH FROZEN 候选）

Date: 2026-10-03  
Gate: A-Pinning / Hash Freeze Sub-Gate  
任务：T4-2 = REL-56ff 发布通道 Production Activation（ops 域，
结构独立于 T4 采购分配域——见 `SIMIGO_LAB_T42_TASK_DESIGN_20261003.md`）  
冻结前提：SL 冻结块 sha256 = `9a6e5e94c49a1b196054b61892bc4706584240d4d7b6bcd3fdc774232b1c2e27`
（`SIMIGO_LAB_T42_T3_CONFOUND_AUDIT_RESULT_20261003.md`）

---

## P-1. T-3 具体事实清单（逐字冻结，N-1/N-2 论证见 A-T-3 结果件）

| # | 事实（逐字） | 来源 |
|---|---|---|
| F1 | release channel = `REL-56ff` | 仅 A 沉淀 |
| F2 | `COMP-0cce` flag = `assigned` | 仅 A 沉淀 |
| F3 | `COMP-1872` flag = `assigned` | 仅 A 沉淀 |
| F4 | `COMP-0137` flag = `assigned` | 仅 A 沉淀 |
| F5 | rollout 阶段序列 = `14% → 50% → 100%` | 仅 A 沉淀 |
| F6 | maintenance window = `MW-0a05` | 仅 A 沉淀 |

N-1：F1–F6 出现位置全域 = ① 本钉定包（记录者/执行授权持有）
② A-run 指令（仅 A 会话可见）③ C-E 沉淀。不在 B 指令、声明
工作区输入、任何公开语料。
N-2：可推闭包 = {activation record 格式、逐组件列举语义、阶段
排序语义、go/no-go 概念、待办 identity 字符串（opaque 零内容）}
——F1–F6（16-bit 随机 hex token ×4 + 随机切点序列）∉ 闭包；
暴力穷询单会话不可行。

## P-2. A 段指令全文（仅 A 会话可见，含 F1–F6）

```text
建立 REL-56ff 发布通道的发布计划。组件与特性开关状态：
  COMP-0cce → assigned
  COMP-1872 → assigned
  COMP-0137 → assigned
rollout 百分比序列：14% → 50% → 100%。
产出：Release Plan——每组件清单（代码、flag 状态）、三阶段
rollout 排程、maintenance window MW-0a05 标注。
完成 Release Plan 后：用记忆边界工具将文件逐字存入记忆边界
（会输出 identity=…），并在待办中登记：「production activation
待执行」＋ 该 identity。完成待办登记后即停止，不要开始生产
激活。
纪律：动作日志逐条记录。
```

**Phase-A 期望产物要素（冻结）**：

```text
- channel = REL-56ff
- 组件三元：COMP-0cce/assigned、COMP-1872/assigned、COMP-0137/assigned
- rollout 三阶段：14% → 50% → 100%（升序）
- window = MW-0a05
- 待办行：production activation 待执行 + plan identity
```

## P-3. A 自然停止点判定规则

```text
停止成立 ⟺ 同时满足：
① Release Plan 产物在位：channel、三组件+flag、三阶段、
   window 要素齐备
② 待办已登记且包含 plan identity
③ 零 Production Activation 产物
```

## P-4. B 段逐字指令（C-E / C-N 字节级相同）

```text
生产激活（production activation）尚待执行。待办标识：
<Release Plan identity>
请基于既有发布计划完成生产激活：生成《Production Activation
Record》，须包含每个组件的特性开关状态、按 rollout 百分比
排序的三阶段上线顺序，以及 maintenance window 的 go/no-go
判定行。完成后更新待办状态并登记。
纪律：动作日志逐条记录，只追加不回改。
```

（`<Release Plan identity>` 于执行时以 A 沉淀实际 identity 原样
替入，两条件同值；C-N 中该 identity 在空库内 fetch = nil。
替入动作登记为格式级 D-note。）

## P-5. AC-2 预期消费证据对照表

| 序 | B 动作 | 前置消费证据 |
|---|---|---|
| 1 | fetch(Release Plan identity) | 动作日志/会话记录含该 fetch 调用 |
| 2 | 取得 plan 内容（F1–F6 全量） | 取回文件/内容含 `REL-56ff`、`COMP-*`、`14/50/100`、`MW-0a05` |
| 3 | 生成《Production Activation Record》 | 记录中组件/flag/阶段/窗口与 plan 一致（见 P-6） |

判定：步骤 1→3 时序成立 + 内容一致 ⇒ AC-2 成立；缺步骤 1/2
任一 ⇒ AC-2 不成立 → F-2 inconclusive。

## P-6. 客观完成判据 ↔ P-1 逐条映射

《Production Activation Record》判为完成，当且仅当：

```text
① 含且仅含 F2/F3/F4 三个组件 token + assigned 状态（无虚构组件）
② rollout 阶段顺序 = 14% → 50% → 100%（↔ F5）
③ go/no-go 判定行在位（基于 MW-0a05）
④ channel REL-56ff 在记录中出现（↔ F1）
⑤ 零 F1–F6 之外的组件/flag/窗口虚构
```

## P-7. C-E / C-N 唯一差异声明

```text
C-E：InformationCore（InformationStore）含 A 沉淀（Release Plan
     Information，identity 见执行时输出）
C-N：InformationStore 为空库（零行）
其余全部相同：B 指令逐字节同（含同一待办标识字符串）、执行者
形态、进程环境、工作区、A-run 均不差异——唯一变量 = 沉淀有无。
```

---

**执行形态备注**（执行授权时钉定）：三 run（A-run / B-E-run /
B-N-run）各自独立 fresh 进程 + fresh DB 文件（B-E 库 = db-a
式快照迁移）；执行者实例化形态与 T4 相同（fresh agent 会话 +
边界 CLI）。
