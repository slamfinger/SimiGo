# PALACE-1 Lifecycle Storage Opening Registration

日期：2026-10-02  
状态：`REGISTERED / OPENING_ACTIVATED / FIRST_EXPERIMENT_GATE_APPLICATION_NEXT`  
Registration authority：explicit human ruling in research session  
Approved instruction：

```text
登记 review PASS 并激活 PALACE1 LIFECYCLE STORAGE OPENING
```

## 1. Registered review decision

| Artifact | Verdict | Registration |
|---|---|---|
| `SIMIGO_LAB_PALACE1_LIFECYCLE_STORAGE_OPENING_DRAFT_EXTERNAL_REVIEW_20261002.md` | `PASS / ACTIVATION_REQUIRED` | REGISTERED |

Reviewed draft chain：`05f4624`（draft）→ `777846e`（entry）→
`3d72485`（rev.1）→ `5362087`（review + rev.2 amendments，F-1/F-2
已随评审执行）。Human 裁定一并确认：F-1（台账补齐防证据误写）与
F-2（重入归属澄清防恢复路径误读）已正确处置。

## 2. Registered opening

Registered opening：

`SIMIGO_LAB_PALACE1_LIFECYCLE_STORAGE_OPENING_DRAFT_20261002.md`（rev.2）

Research question：

> PALACE 作为 Execution State 的长期 durable 存储层，其记录语义必须
> 满足什么最小集合，才能使 Contract v1.0-amended 的七操作 lifecycle
> （create / fork / continue / save / restore / discard / release）在
> 跨进程、跨时间、跨 backend、Physical Representation 丢失/替换的
> 全部边界上保持可断言、可验证、fail-closed——且存储载体本身可替换、
> 可扩展？

三子目标（不可合并）：F1 灵活拓展（storage-agnostic Store
Declaration 模式）/ F2 长期存储（存活边界 + U-1…U-4 诚实 UNKNOWN）/
F3 七操作适配（durable 缺口逐项映射）。

## 3. Authorization boundary

This registration activates the opening as the registered PALACE-1
lifecycle-storage research line. It does not authorize:

```text
❌ 任何具体实验执行（§6 矩阵每项须独立申请 + human 授权，一次一项）
❌ SQLite / KV / graph / vector / event log / remote 存储选型
❌ PALACE schema / record 字段布局定义
❌ persistence API / serialization format / 存储事务协议
❌ RF-1 解决机制设计
❌ 产品代码修改 / durable 写入实验
❌ 性能基准
❌ OP-7 消费 / 任何 OP-G 关闭
❌ identity → database primary key、lineage → table/schema、
   snapshot → serialization format 一类的实现先行映射
   （human 裁定：第一批实验保持在生命周期语义的观测层）
```

第一批实验顺序（human 指令，观测层纪律）：

```text
1. create → durable identity reservation 的观测层证据（EF-9 基线）
2. fork  → lineage formation 的观测层证据（Gate B 范式）
```

## 4. Next gate

```text
Opening draft rev.2          = REVIEW PASS / REGISTERED
External review              = PASS / REGISTERED
Opening                      = REGISTERED / ACTIVATED
Current work                 = 第一实验 gate 申请：create durable
                               identity reservation 观测设计草案
                               （设计冻结 → human 批准 → 执行）
Next decision point          = 该设计草案的 human 执行授权
```
