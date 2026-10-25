# ES-R1 Gate D Results — Independent State Existence Test

> **ARCHIVED** 2026-10-20 · line: 通用治理 / 其他 · original: docs/00-governance/SIMIGO_LAB_ESR1_GATE_D_RESULTS_20260930.md
> Evidence status: unchanged (content frozen; moved only)


日期：2026-09-30  
状态：`GATE_D_COMPLETE / VERDICT = D-B (CONTRACT-ONLY) / AWAITING SECOND-LAYER`  
唯一问题（human 界定）：**在不新增 State object/schema/API 的前提下，
现有证据能否证明 Execution State 在 Representation 之外具有独立的
「存在者、生命周期和权威载体」？**  
证据纪律（human）：不找「State 是什么」，只找「有没有已存在的东西实际
承担 State 的独立生命周期」；「能被计算出来」≠「被系统作为 State 持有」。

## D-1 — State Carrier Authority Trace（五元组逐项：权威载体穷举）

### Identity

```text
候选载体（全部实测）：
  caller key / storageKey      —— 权威寻址（sessions 字典键、文件名、
                                  Lab executionID 同值）；不依赖 P 存在；
                                  跨进程持久（文件名在盘上）
  meta.storageKey 字段         —— informational duplicate（E1.5-Q1）
  meta 文件名                  —— durable 投影
判定：identity 有权威载体 = 【寻址链（caller key→文件名）】，
      但该载体只承载 identity（一个身份键），不承载其他四元。
```

### Lineage

```text
候选载体：product ExecutionLineage records（进程内 O 层，随进程死亡）；
          meta.forkPoint（本样本 ABSENT；全 102 meta 无此字段——E0/D-2
          grep 实测）；pool sidecar（无 lineage 字段——本轮 grep）；
          Lab handle.lineage（进程内）
判定：**durable lineage 权威载体 = 不存在**（全部实例进程内或缺席）。
      跨进程后 lineage 仅可由 storageKey 隐含（root）——parent 链丢失。
```

### Position

```text
候选载体：Lab ExecutionPosition（进程内 handle）；product 无字段——
          history.count 为事实代理（A2）；meta 无 position 字段（D-2 实测）
判定：独立权威载体不存在；position = 从 history.count【推导的观察】。
```

### Continuation

```text
候选载体：Lab continuation.nextInput（进程内 handle）；product delta
          契约锚 = history 末端（A3）；meta 无 continuation 字段（D-2）
判定：独立权威载体不存在；continuation = 从 history 末端【推导的观察】。
```

### Recovery

```text
载体：safetensors（= P 本体，已被删）+ meta 完整性标记（generation/SHA
      指向已删 P）+ history 文本（可重算源，R2n/E3 已证）
判定：recovery 权威载体 = P 与 history 的组合；纯 State 字段不携带
      recovery 信息。
```

## D-2 — Lifetime Independence（R 移除后，「State」还剩什么、各活多久）

Fixture = C-1 边界后副本（meta only）。跨进程核验（本轮实测）：

| 事实 | R 删除后是否仍存 | 生命周期终点 |
|---|---|---|
| identity（寻址键/文件名） | **是**（durable） | 随文件存亡——不随进程/表示 |
| history（语义载荷，17 条） | **是**（durable；SHA 与 C-0 冻结一致） | 随 meta.json 存亡 |
| modelId / generation / savedAt | 是（durable） | 随 meta.json |
| position | 仅可推导（=history.count） | 无独立实例——「终点」概念不适用 |
| continuation | 仅可推导（=history 末端） | 同上 |
| lineage | **否**（全 durable 层无实例；进程内已死） | 进程边界 |
| recovery 的表示部分 | **否**（已删） | C-1 边界点 |
| live binding / pool Bind / dirty 态 | 否 | 进程边界 |

**D-2 结论**：R 消失后，仍然独立存活的 = **identity 寻址 + history 语义
载荷 + 环境标记**（即 PALACE 线的 observed nucleus，durable 且跨进程）；
五元组中的 **position / lineage / continuation / recovery-as-P 全部没有
独立存活的权威实例**——只剩对存活载荷的推导。

## D-3 — Source-of-Truth 矩阵

| State field | 独立 carrier | 从 History 推导 | 从 P 推导 | 仅 Contract 描述 | Unknown |
|---|---|---|---|---|---|
| Identity | **✔**（寻址链，identity-only） | 可 | — | — | — |
| Lineage | ✘（durable 全域缺席） | 部分（root 可隐含） | — | Lab handle（进程内） | — |
| Position | ✘ | **✔**（history.count） | ✔（token 长度，物理影子） | Lab handle（进程内） | — |
| Continuation | ✘ | **✔**（history 末端） | —（generation 非位置） | Lab nextInput（进程内） | — |
| Recovery | ✘（纯字段不携带） | ✔（history=重算源） | **✔**（P 本体+SHA/generation） | — | — |

## Verdict

```text
D-B — CONTRACT-ONLY（H-B2 获支持）
```

依据：五元组中只有 identity 拥有独立权威载体（且 identity-only）；
position / continuation 在全系统只以「对 history 的推导」存在；lineage
无 durable 实例；recovery 依赖 P+history。**不存在一个持有
{identity, lineage, position, continuation, recovery} 且拥有独立生命
周期的对象或记录**——Contract 的五元语义在产品层没有对应的权威
State carrier。

精化（避免过度解读）：

```text
D-B ≠ 「什么都没有」。实验同样确认：
  ✔ durable semantic side 真实存在且跨进程
    （identity 寻址 + history 语义载荷——PALACE observed nucleus）
  ✔ Lab 契约层存在五元 State 形状（零 MLX、三 backend 验证）——
    「State 只是 KV 别名」仍被排除
D-B 的精确含义 = **五元 State 目前仅以「寻址键 + 可推导观察」的形式
  存在于 durable 层；position/continuation/lineage 无权威实例**。
R1-B 的相应精化 = 「Runtime 无法消费」之上再进一步：**Runtime 无物可
  消费**——缺的不是 seam 一条边，是 seam 的输入端对象本身。
```

## Non-claims

```text
✔ 只读（fixture 核验 + grep；零修改零删除；真实 store 未动）
✔ D-A 未发生（无独立五元 carrier 被发现）；C-4 保持 LOCKED
✔ 判定限于「当前产品 + 当前 fixture」；非 PALACE 普适命题
✔ persona/虚构发现（RF-1）不受本 gate 影响
```
