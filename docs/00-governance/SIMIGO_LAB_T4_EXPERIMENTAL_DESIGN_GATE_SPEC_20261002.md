# Gate Spec — T4 Experimental Design Gate（仅 Spec：零代码、零实验）

Date: 2026-10-02  
Status: `GATE OPENED（SPEC 已登记；Spec 确认 + 执行授权均待 human）`  
位置：SimiGoRuntime FORMAL INTEGRATION PASS 之后；本 Gate 产出 =
T4 实验的**预注册设计**（pre-registration），不含任何实验执行  
纪律：T4 execution = 尚未授权；Spec 确认后才进入最小实现/实验；
实验结果**实验后才裁定**，本 Spec 不预设 T4 PASS。

## 1. 研究问题（T4 的新增证据，非 persistence 复验）

Phase 1 + pre-research 已证：InformationCore 能存能取。**那不是
T4。**T4 的新增证据只有一个：

```text
过去没有历史
      ↓
cold-start executor
      ↓
Information boundary 提供必要事实
      ↓
executor 能否形成后续 continuation
```

即验证 **Information boundary 对 continuation 的贡献**（attribution），
而不是再验证一次 persistence。

## 2. 实验对象与历史条件（S-1/S-2）

**S-1 实验对象**：cold-start SimiGo executor = 独立 fresh
进程/会话，仅绑定 InformationCore 公共面（正式接入形态：
`RuntimeMemory(any InformationStore)` 或直连，二者取一并在执行
授权时钉定）；执行者不携带任何前会话状态。

**S-2 历史条件（cold-start 操作化定义）**：全部满足才算 cold-start——
① fresh 进程 + fresh 数据库（零预置行）② 指令零历史词汇
（T 系列零泄漏纪律）③ 零私有记忆通道（MEMORY.md/palace/私有
目录一律不可读）④ 唯一外部记忆 = InformationCore 边界 ⑤ 工作区
= 仅声明输入，禁止文件系统考古。

## 3. 唯一外部记忆边界（S-3）

InformationCore（经正式接入形态）。可用语义 = 已定稿契约：
Information（S1–S6）/ Relation（R1–R6）。**边界内不预置任何
未登记语义**；除 A 阶段沉淀外零内容。

## 4. 任务（S-4）：受控 continuation 任务的准入条件

具体任务在执行授权时钉定；本 Spec 固定**任务准入条件**：

```text
T-1  两段结构：Phase-A（形成/前端工作）→ 自然停止点 →
     Phase-B（continuation/后端工作），B 段由独立 cold-start
     执行者完成
T-2  B 段指令零历史词汇、零 A 段叙述（仅任务本身）
T-3  A 沉淀中必须含至少一类「仅存在于沉淀中的必要事实」
     （non-derivable facts：任务输入本身无法推出）
T-4  B 段有客观可判的完成标准 + 事实清单（A 沉淀前预登记）
T-5  A 停止点自然产生（反裁剪纪律：不强制中途停）；
     「登记为待办」= ⑧ 态自然产生位
T-6  完成产物可独立验证（第三方可按预登记标准复核）
```

**T-3 是命题强度开关**：无 non-derivable facts ⇒ 实验只能证
「弱命题」（boundary = 提速/保真），证不了「必要贡献」。任务
钉定时必须声明目标命题强度。

## 5. 实验条件与对照（S-5）

| 条件 | 边界 | 内容 | 变量 |
|---|---|---|---|
| **C-E**（实验组） | InformationCore 可用 | 含 A 沉淀 | ★ 唯一自变量 = 沉淀内容 |
| **C-N**（阴性对照，必选） | InformationCore 可用 | **空**（零沉淀） | 其余与 C-E 全等：同执行者形态、同指令文本、同工作区、同输入 |
| **C-A**（无边界对照，可选第二对照） | 无 InformationCore 访问 | —— | 隔离「边界机制本身」变量 |

全等保持手段：B 指令两条件**逐字节相同**；执行者形态/进程环境/
工作区/输入文件全部相同；唯一差异 = store 内容（有沉淀/空）。

## 6. 成功判据（S-6）：attribution 三条件

「continuation 能力来自 Information boundary」成立，当且仅当：

```text
AC-1  C-E 的 B 满足 T-4 客观完成标准
AC-2  C-E 的 B 存在消费痕迹（因果链）：retrieve 沉淀事实发生在
      使用之前（动作日志/会话记录可复核——T3 式入场链证据）
AC-3  C-N 的 B 未达成等价 continuation（失败，或可测劣化：
      缺失必要事实/错误值/显著重解成本——阈值预登记）
```

附加指标（预登记，辅助非判定）：m1 完成判据通过率；m2 必要
事实覆盖率（A 沉淀清单 × B 产物使用）；m3 消费痕迹时序；
m4 C-N 重解标记；m5 动作数/耗时（次要）。

**三种Attribution 结果均预注册**（防裁定被强塞）：

```text
强命题  AC-1∧AC-2∧(C-N 失败)      ⇒ boundary = continuation 的
                                   必要条件（仅当任务含 T-3
                                   non-derivable facts 时可 claim）
弱命题  AC-1∧AC-2∧(C-N 重解成功但可测劣化) ⇒ boundary = 提速/保真
                                   贡献，非必要
无归因  AC-1 但 AC-2 不成立（B 未消费边界仍成功）⇒ continuation
                                   来自任务自证/re-solve，
                                   boundary 无贡献
```

## 7. 失败/证据不足判据（S-7）

```text
F-1  C-E 的 B 未完成 ⇒ boundary 不足，T4 not-established
F-2  C-E 成功但消费痕迹缺失 ⇒ 降级 inconclusive（无法归因）
F-3  C-N 与 C-E 等价成功（零劣化）⇒ 无归因（任务自证）
F-4  任一 run 发现未声明通道（指令泄漏/隐藏缓存/文件考古/
     私有记忆）⇒ 该 run 作废重跑
F-5  A 沉淀被事后改动/回写 ⇒ run 作废（沉淀 = 停止点逐字封存）
F-6  判据偏离本 Spec ⇒ 整轮作废（预注册纪律）
```

## 8. 禁止偷渡（S-8：执行全程零容忍清单）

palace/MemPalace（含 mempalace 工具）、既有 Execution State、
隐藏缓存、预置历史、taxonomy、activation、retrieval/ranking、
私有记忆（MEMORY.md 等）、服务树适配、文件系统考古（声明工作区
之外）、指令历史词汇、Web/人工通道旁路、**任何未在本 Spec 登记
的信息通道**。

## 9. 裁定后置与附加纪律（S-9）

1. 实验结果（强命题/弱命题/无归因/not-established）**实验后才
   由 human 裁定**，本 Spec 与任何实现都不得预设
2. 本 Spec = 预注册；执行中任何偏离必须记 deviation log；
   判据不得事后修改
3. 每个 run 的全部记录（动作日志/会话记录/产物/库快照）归档
   证据目录
4. **T4 execution 尚未授权**：Spec 确认 → 钉定具体任务（满足
   T-1…T-6 并声明命题强度）→ 执行授权（单独指令）→ 才开跑

## 10. 本 Gate 的收口条件

**Spec 确认（human）= 本 Gate 收口**；收口产出 = T4 预注册设计
生效 + 任务钉定授权（仍未到实验执行授权）。实验执行 = 再下一道
单独授权。
