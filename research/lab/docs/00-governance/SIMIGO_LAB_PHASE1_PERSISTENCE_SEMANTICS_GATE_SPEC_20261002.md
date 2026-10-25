# Gate Spec — Phase 1: Persistence Semantics Gate

Date: 2026-10-02  
Status: `GATE OPENED（SPEC 已登记；冲突情形待 human 裁定后实施）`  
Baseline: `089e88a`（Backend Independence Gate = PASS）  
纪律：不加新 backend（PostgreSQL/LMDB/Core Data = 重复同类证据，
违反不扩面纪律）；不因实现便利自决未裁语义；5+1 本地提交不
推送，Gate 完成后成链一次推送；T4 = BLOCKED。

## 1. 目的

不再问「能不能换数据库」（已证），改问：

> **`InformationStore` 这个稳定边界的行为契约是否足够明确，
> 让未来 backend 独立实现而不产生语义漂移？**

把已实测行为收敛为 **backend-independent contract**：

```text
InformationStore
├── store
│   ├── new identity                    → 已证：持久化
│   ├── same identity + same value      → 已证：幂等 no-op 确认
│   └── same identity + conflicting value → ★ 本 Gate 待裁
└── fetch
    ├── present                          → 已证：返回该值
    └── absent                           → 已证：nil
```

## 2. 为什么冲突情形是本 Gate 核心

当前两个 backend 对「same identity + different value」**恰好
行为一致**（SQLite `INSERT OR IGNORE` / InMemory 字典保留先存
事实），但这是**实现巧合**而非**裁定契约**。不锁定则未来：

- SQLiteStore 与任何新 backend 可能对同一冲突输入产生不同语义
- 两者都可能各自通过 K5–K8 类验证，却在冲突输入上语义漂移

这正是「语义在边界里，不在实现里」必须显式化的地方。

## 3. 冲突情形裁定面（human 裁定项）

**情形**：`store(I₂)`，其中 `I₂.identity == I₁.identity` 但
`I₂` 与已存储的 `I₁` 在其他字段上不同。

| 选项 | 行为 | 语义代价 |
|---|---|---|
| ① **first-write-wins**（扩展 B2 字面：已存在 identity 一律 no-op 确认，existing 保持不变，与值无关） | 忽略 I₂ | 零重开：B2 冻结文本「an identity that already exists → no-op, stored Information remains unchanged」**无条件成立**，本选项 = 显式 codify 其对冲突值同样适用 |
| ② **reject / throw Conflict** | 拒绝 I₂ | 需**重开并修正 B2**（冻结文本是无条件的），store 契约变为值依赖；且「比较是否相同」引入 Core 语义新问题（比较=另一种语义行为） |
| ③ overwrite / merge | — | 与 A1（不可变）与 C3（verbatim）直接冲突，**不在裁定面内**（列出仅为完备性） |

**记录者非绑定预分析（锚定已冻结裁定）**：

1. A1：Information 不可变 ⇒ 同一 identity 不可能「被修改成
   另一个事实」
2. identity 是 Information 自身事实的确定性派生（A2′链）⇒
   同 identity + 不同内容 = 语义矛盾态（确定性配方下不可能
   自然产生；出现即 formation/recipe 误用，而非两种合法事实）
3. B2 冻结文本已是无条件的（不区分值是否相同）⇒ ① 是对
   已裁语义的显式 codify；② 是重开冻结面
4. 故 ① = 契约澄清；② = 语义修订——代价不对称

**待 human 裁定**：① 或 ②（或另述）。

## 4. 契约收敛表（裁定后即为 backend-independent contract）

| # | 输入 | 契约 | 状态 |
|---|---|---|---|
| S1 | store，new identity | 持久化，返回成功 | 已证 |
| S2 | store，same identity + same value | 成功 no-op，确认已有事实 | 已证（B2） |
| S3 | store，same identity + conflicting value | **★ 待裁（①/②）** | 本 Gate |
| S4 | fetch，present | 返回该 Information | 已证 |
| S5 | fetch，absent | nil（非异常） | 已证 |
| S6 | storage failure | throw（仅 failure，永不表 absence） | 已证（实现层） |

## 5. 验证方式（裁定后实施）

1. harness 增设**冲突链路**：同一 identity + 不同 value 分别
   驱动 **两个 backend**，断言行为逐项一致且符合裁定
2. 契约表 S1–S6 双 backend 全项回归
3. diff 审计：三已验收文件 + UpperLayer 零改动（除非裁定②
   要求改 B2/Store——那将作为裁定的一部分显式登记）
4. 符号/负空间声明级审计零命中；Build 零警告

## 6. Negative Space

同已封存清单全项；另加：契约中不得出现 merge / compare-and-swap /
version 条件写 / overwrite 等任何值依赖写入语义（除非裁定②
明确引入 reject——那也仅是「拒绝」，不是值比较 API）。

## 7. Pass / Fail

- **PASS** = 冲突情形获 human 裁定 + 契约表 S1–S6 定稿 +
  双 backend 行为一致且符合裁定 + 四文件 diff = 0（或按裁定②
  的显式登记改动）+ Build 零警告
- **FAIL** = 双 backend 对冲突输入行为不一致且无法按裁定对齐
  ⇒ 停止，登记语义缺口重开裁定
