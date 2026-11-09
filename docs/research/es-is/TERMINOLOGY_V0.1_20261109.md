# ES/IS 术语正本 v0.1

日期：2026-11-09　状态：现行（跨文档用词的唯一出处）
适用：论文 §2–§6、`docs/research/es-is/*`、本仓 `README.md`、`docs/AGENT-ACCESS.md`。

## 用法

一个词只在本表出现一次定义。其它文档引用本表，不复述定义；改写定义必须先改这里。
旧称一栏是**检索用**：出现旧称不算错，但必须能指回本表某一行，否则就是漂移。

## 三分：动作 / 本体 / 记录

| 正名（论文用词） | 中文 | 定义（一行） | 代码锚点 | 旧称 / 禁用 |
|---|---|---|---|---|
| settlement | 结算 | 一次判定动作：产出的结果满足其声明契约。归执行侧 | 结算门（无 I/O、无兜底校验器） | 把"结算"当结果本身用 |
| settled result | 已结算结果 | 动作承认的结果本体：校验通过的 payload | `settlements.payload_object_id` 指向的对象 | `settlement value`、`settled unit`、`结算值`、`结算单元` |
| settlement record | 结算记录 | 持久化下来的记录：行、内容寻址 payload、身份绑定、依赖边 | `settlements` / `settlement_bindings` | 把记录说成"结果" |

## 两层与两条谓词

| 正名 | 中文 | 定义（一行） | 代码锚点 | 旧称 / 禁用 |
|---|---|---|---|---|
| execution state (ES) | 执行状态 | 一次计算在轨迹上的可识别位置（锚点、位置、谱系）＋继续关系＋**判定权威**：它有权判定产出是否成立。不是运行时状态的时点快照 | `execution_states`、`previous_es_state_id` | `ES snapshot` |
| information space (IS / PALACE) | 信息空间 | 已结算结果及其记录、依赖与有效性关系所在的语义环境；存储实现它，不等于它 | IS 数据库（`SimiGoESISDatabase`） | 把库说成"空间" |
| Settled(ρ) | 已结算 | 历史事实：动作发生过，之后发生的任何事都不撤销它 | `settlements` 行存在 | — |
| Reusable(ρ, ctx, t) | 可复用 | 当前资格：在时刻 t 按有效性、依赖闭包、声明逐项重判后的结果 | 七步准入 | 把两者当同一个谓词 |
| admission | 准入 | 恢复时点的七步失败即拒（fail-closed）重判 | `SimiGoISAdmission.swift` | — |
| refusal / typed reason | 拒绝 / 类型化理由 | 从封闭公开集合里给出类型化拒绝，不冒充另一族拒绝 | `SimiGoManagedRefusal.swift` | 无类型失败 |

## 三条路径（坐标，不是功能清单）

| 正名 | 中文 | 判据 | 代码锚点 | 旧称 / 禁用 |
|---|---|---|---|---|
| read-only answer reuse（短式 read-only reuse） | 只读应答复用 | 同文本、零模型调用、**不诞生结算**；复用事件 `consumer_state_id: nil` | `HTTPServerChat.swift` 复用分支 | `hint`（仅实现侧绰号）、`cache hit`、`reuse hint` |
| consumption | 消费 | 零模型调用、**诞生结算**：新谱系 + 声明契约 + consumer ES + `DERIVED_CONSUMPTION` | `recordSettlementConsumption` | 与 continuation 混用 |
| continuation | 续接 | 同谱系下一步：`previous_es_state_id` opt-in，子 ES 是下一次准入锚 | `previous_es_state_id` | 把新谱系消费叫 continuation |

## 声明与账本

| 正名 | 中文 | 定义（一行） | 代码锚点 | 旧称 / 禁用 |
|---|---|---|---|---|
| reuse declaration / declared contract | 复用声明 / 声明契约 | 没有这一行就不可消费：可复用性是**声明的**，从不推断 | `declareSettlementReuseContract` | "自动可复用" |
| declared write (C5) | 声明式写入 | 带来源声明（来源身份＋修订）的结算侧写入；与复用声明是两件事 | C5 路径 | 与复用声明互换 |
| declared snapshot (P1) | 声明式快照 | 续接起点固定下来的执行侧输入快照；准入复核它而不重推它 | P1/S 路径 | 与复用声明互换 |
| demand | 需求 | 检索单元：规范输入被摘要并在准入时复核；生命周期 `RESOLVED` → `ADVANCED` | `information_demands` | — |
| dependency edge / closure | 依赖边 / 依赖闭包 | 结算间的有向依赖及其传递闭包；失效沿它传播，不用 TTL | `dependency_edges`、`invalidateSourceFile` | "缓存过期" |
| validity basis | 有效性依据 | 有效性只由追加式事件账本改，行上不再存状态 | `settlement_validity_events`、视图 `settlement_current_validity` | 在 `settlements` 行上改 validity |
| settlement fingerprint | 结算指纹 | 受管流水线六维幂等指纹——**不是** KV 层 `kvFingerprint` | C7 路径 | 与 `kvFingerprint` 混称 |
| carrier independence | 载体独立性 | 语义层：定义不引载体。实现层：换载体能否续接是实验命题，不是定义推论 | MLX / llama.cpp 两条受管路径 | 用单 backend 结论推跨 backend |

## 冻结文档

`docs/upstream/B0_ESIS_GLOSSARY_20261105.md`（ACCEPTED，2026-11-05）是上游冻结词表。本表不与它冲突：
B0 已有条目按 B0 措辞引用；本表补的是 B0 未收的实现词与论文内部对照。改 B0 属于红线，只能在论文里细化。

## 已知例外（允许，但必须能指回本表）

- **逐字引用须与原文同步**：研究文档引用代码注释原文时照抄当时原文；源码原文改词后，引文与行号随之更新并注明
  日期——引文与被引对象不符才是伪造。例：`INVARIANT_PROPOSITIONS` P3 引 `SimiGoESISDatabase.swift` 的
  "a declared property of the settled result"（2026-11-10 随源码正名同步，原引文为 "settled unit"）。
- **代码注释旧称已清零**：2026-11-10 按本表正名改掉当时仍在的 7 处 `settled unit`
  （`SimiGoESISDatabase.swift` 两处、`SimiGoSettlementConsumption.swift` 一处、
  `SimiGoISAdmission.swift` 一处跨行漏检、`SimiGoSettlementConsumptionTests.swift` 一处，
  以及首轮漏查的应用层两处：`SimiGo/Model/SimiGoProducerIdentity.swift`、
  `SimiGoTests/ResponsesSettlementConsumptionHTTPTests.swift` —— 首轮只扫了 `Packages/`，
  评论区与 app target 不在其内，复核时补齐）。原记 6 处中
  `SimiGoESISDatabaseTests` / `SimiGoInformationLoopTests` 的两处已在更早改动中消失。
  无测试断言该字面串；复核命令 `grep -rn -i "settled unit" --include='*.swift' Packages SimiGo SimiGoTests` 现为空。
- **历史版本不改**：`PAPER_S5_ABSTRACT_V0.1_*` 已标"被 v0.2 取代"，其旧词保留作留档。
