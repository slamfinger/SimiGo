# ES-D1 Gate G Results — Authority Test

> **ARCHIVED** 2026-10-20 · line: 通用治理 / 其他 · original: docs/00-governance/SIMIGO_LAB_ESD1_GATE_G_RESULTS_20260930.md
> Evidence status: unchanged (content frozen; moved only)


日期：2026-09-30  
状态：`GATE_G_COMPLETE / VERDICT = G-C (PARTIAL AUTHORITY) / AWAITING SECOND-LAYER`  
核心问题（human 界定）：**在 Representation 不存在的情况下，CC-1/CC-2
是否仍然拥有能够独立确定 Computational State 的 authority？**——只问
「系统把谁当作 source of truth」，不问「它像不像 State」。  
方法：决策追踪（谁在什么决策中消费 X；缺失时哪条决策路径改变）；范围
= CC-1 六字段 + CC-2 三子字段 + 边界 B-1/B-2；G 只裁 authority，H 才裁
lifetime（不混裁）。

```text
四类身份：AUTHORITATIVE（决策以其为依据）/ DERIVED（可由其他信息重算）/
DUPLICATE（既有事实副本）/ DESCRIPTIVE（记录用途，不驱动恢复）
依赖标注：P-dependent / H-dependent / independent
```

## 1. CC-1 逐字段裁定

| 字段 | 消费决策（file:line） | 四类身份 | 依赖 | 备注 |
|---|---|---|---|---|
| `storageKey`（字段值） | 无校验者（E1.5-Q1）——决策不读它 | **DUPLICATE**（of caller key/文件名） | independent | 寻址权威在 caller key，字段值非决策依据 |
| caller key / 文件名（寻址链） | 全部会话/加载/绑定决策的寻址依据 | **AUTHORITATIVE**（scope: addressing） | **independent** | 表示缺席仍有效（E1-R0） |
| `history` | restore 后成为 session history → 驱动 delta 计算/reuse isPrefix/后续生成（:677-679/:795） | **AUTHORITATIVE（restore 后）/ DUPLICATE（写入时）**——即 **lifecycle-dependent**（=B-1 裁定，见 §3） | H-dependent（即语义载荷本体） | 唯一驱动 continuation 语义的字段 |
| `generation` | presence 校验门（:1614-1618）——接受/拒绝 checkpoint 的决策输入 | **AUTHORITATIVE**（scope: checkpoint acceptance，presence-only） | P-adjacent（commit 事件标记） | E1.5-Q4：无比对注册表 |
| `cacheSHA256` | 字节比对门（:1620-1626） | **AUTHORITATIVE**（scope: payload integrity） | **P-dependent**（只对 safetensors 字节有意义） | E1.5-Q5；transcript 排除在外 |
| `modelId` | 同源校验门（:1628-1631） | **AUTHORITATIVE**（scope: compatibility） | environment-dependent | E1.5-Q3 |
| `savedAt` | retention 预算驱逐排序（Retention:111/121） | **AUTHORITATIVE**（scope: retention governance） | independent | 驱逐顺序决策的唯一依据 |

## 2. CC-2 裁定（forkPoint：sourceStorageKey / atMessage / atToken）

| 问题 | 实测 |
|---|---|
| 谁产生 | forkSessionBranch 原子盖章（NativeMLX:1830-1845） |
| 谁读取 | **零 reader**（E0 穷举；本轮未发现新 reader） |
| 谁依赖它决策 | **无任何决策路径** |
| 缺失影响 | 无（部署库 0 实例，系统照常运行——事实本身即证明） |
| 生命周期独立于 P | **是**（durable，跨进程；内容为 fork 时点的历史事实，不可由当前对象重算——atMessage/atToken 是历史事实记录） |

**裁定**：**DESCRIPTIVE**（provenance/audit 记录；写入 ≠ authority 的
典型实例）——同时登记为 **latent semantic carrier**（lineage+position
代理的唯一 durable 物理形态；「潜在」指当前无消费者，非指无价值）。
B-2 裁定：**writer-only ⇒ 非 authority**（写入不构成 authority，需
决策消费者）。

## 3. B-1 裁定 — authority 是生命周期属性

代码层事实（确定性、可引用）：

```text
同一份 meta.history 字节：
  进程存活期   = runtime history 的 DUPLICATE（managed.historyJSON 的
                副本；决策依据是内存中的 runtime 对象）
  进程死亡后   = 唯一幸存的语义载体 → restore 路径把它当作 session
                重建的唯一依据（makeChatMessages 输入）——
                DUPLICATE → SURVIVING-AUTHORITATIVE 的转变点是确定性的
                （进程边界），且由代码结构保证
```

**裁定**：**history 的 authority 不是静态字段属性，而是生命周期属性**
——authority 由字段所处的生命周期阶段决定，转移点确定且可预测。
（这直接回答了 human 的 B-1 问题：答案 = 后者，生命周期决定。）

## 4. 核心问题作答（表示缺席场景）

> 表示不存在时，CC-1/CC-2 是否仍拥有独立确定 Computational State 的
> authority？

```text
✔ identity        = 有（寻址链 independent authoritative）
✔ 语义内容        = 有（history 为 surviving authoritative——B-1 裁定）
✘ position        = 无独立 authority（derived：history.count）
✘ continuation    = 无独立 authority（derived：history 末端）
✘ lineage         = 载体在代码层存在（forkPoint）但当前 corpus 零实例
                    且 DESCRIPTIVE——无运作中的 authority
✘ recovery/完整性 = 无（generation/SHA 指向已删除的 P；modelId 只判兼容）
⇒ PARTIAL AUTHORITY：identity + 语义内容可独立确定；
  position/continuation/lineage 只能从语义载荷推导，无独立权威。
```

## 5. Gate G 裁定

```text
VERDICT = G-C — PARTIAL AUTHORITY / PARTIAL-STATE CANDIDATE
（停止条件③命中：identity independent + history surviving-authoritative
 + position/continuation derived + lineage carrier-present-but-
   unpopulated）
```

按指令：**不补齐**。partial-state candidate 原样记录进入 Gate H——
H 的问题因此精确化为：

> 这些「推导出的」position/continuation 观察能否在进程死亡与表示删除
> 后仍然成立（lifetime），以及 partial authority 的组合是否构成
> Formation（J）的前半条件。

## 6. Non-claims

```text
✔ 只读决策追踪；零修改零新增；C-4 续锁；H/I/J 未进入
✔ authority 分类限于「当前产品 + 当前 corpus」；forkPoint 的 latent
  判定不含价值判断
✔ B-1 裁定 = 代码结构事实（转移点确定性），非「State 定义」
```
