# 实验方案（预先定义判定标准）— P1/P2/P3

日期：2026-10-17
配套勘察：`investigation.md`
模型/运行时身份：**本会话单实例大模型 + Python carrier（Information Space / 持久结算层）**
外部二进制：**不使用**（不加载 mlx-lm/torch/llama；Swift `continueExecution` 仅作声明式边界）

---

## 0. 本方案要回答的"单个真问题"

> 在**旧模型执行阶段/缓存不可访问**的前提下，一个 **新的执行阶段**能否：
> (1) 从 Information Space 恢复已结算的有效结果，(2) **只执行新增或失效的单元**，
> (3) 并且证明它**真的减少了模型计算**（而非只在结果层跳过显示）？

---

## 1. 任务语义模型（复用 carrier 的真实依赖/结算结构，不伪造）

> ⚠️ 诚实说明：carrier 的依赖图由 `put_source`/`update_source` +
> `invalidate_settlement(include_dependents=True)` 构成（DFS 传递闭包）。本实验沿用这
> **同一套依赖图语义**，不额外造一个"伪图"。

任务 D = "文档工作流分析"，拆成三段可分段计算单元（沿用 carrier 的 settle/invalidate/restore）：

| Unit | 依赖 | 输入（source_payload） | "计算"语义（本方案用确定性函数模拟 Swift continueExecution 的 forward） |
|---|---|---|---|
| U_upstream   | （无）| `doc_v1` 全文 + metadata | 抽取+归一化：`sha256(prefix8)` + 长度 |
| U_parse      | U_upstream | 归一化结果 | 抽取关键信息（依赖上游产物） |
| U_summarize   | U_parse   | 关键信息（依赖下游上游） | 提炼结论（依赖上游链） |

依赖边：`U_parse → U_upstream`，`U_summarize → U_parse`（链式，前向传播失效）。
这三段 = 任务目标的 A/B/C：

- **A（已完成可结算上游）** = `U_upstream`（无依赖、可独立结算）。
- **B（依赖 A 的后续）** = `U_parse`（依赖 A）。
- **C（新增 / 依赖可单独修改的下游）** = `U_summarize`（新增，依赖 B）。

> 说明：此处的"上游输入可单独修改" = 改 `U_upstream.source_payload`（等价于 Swift
> `update_source` + policy check 触发依赖失效）。与任务书 §8 一致。

### "计算成本"如何物化（关键：可测的 model-work）
Swift `continueExecution` 用 **token-prefix** 量化计算成本（`consumedPrefixLength` +
`nextInputTokenCount`）。本方案用**确定性"前缀续算函数"**物化：每个单元产出固定长度的
`prefix_tokens`，"前缀续算成本"= 复用前缀长度 + 本轮追加长度。并额外提供一个
**counterfactual 探针**：若该单元被真实重算（非复用），它的反事实输出会长什么样、会占用多少
"prefix tokens"——这是区分 info-reuse 与 compute-reuse 的关键（判定 D/E/I 依据）。

---

## 2. 变量、常量与不可控因素（固定输入）

| 类别 | 取值 / 说明 |
|---|---|
| 模型身份 | **本会话实例**（session model）；Swift `MLXPrefixRecomputeExecutor` 为声明式边界，非本次实测 |
| 模型权重身份 | 见 `investigation.md` §3（真实 MLX smoke = V6, CLOSED，本次不重跑） |
| tokenizer 身份 | Swift `MLXExecutionStateBackend` tokenization（声明式）；Python 侧为确定性前缀函数 |
| 输入 | `doc_v1` = "本实验固定文档…（见下）"；三单元输入在三个 arm 间**完全一致** |
| 生成参数 | greedy decode（本方案=确定性函数，无采样）；`max_tokens` 固定为反事实探针用的上限 |
| 随机性控制 | **确定性**（无采样）。唯一不可控：外部进程/子智能体的**调度时序**，不构成语义随机性 |
| 不能固定的因素 | Swift 真实 token-prefix 寿命 / forward pass 开销（须外部二进制，本次不测） |

固定文档内容：
```text
doc_v1 = "本报告汇总 Q3 营收与用户增长。营收环比 +12%，活跃用户环比 +5%。"
```
（任何改变都会触发依赖失效；用于 stage D。）

---

## 3. 对照组设计（三个 arm，完全相同任务定义/模型身份/输入基线）

| Arm | 名称（判定项对应任务书 §9 / §10） | 做了什么 |
|---|---|---|
| **Arm-1** | 完整重算 baseline（判定 G/I/A 基线） | 无 IS 读取，U_upstream/U_parse/U_summarize 全部从头执行（真 counterfactual） |
| **Arm-2** | 持久化恢复续算（判定 B/C/D/E/F/I） | U_upstream 结算写 IS → **新执行阶段**（隔离旧缓存）→ 从 IS 恢复 U_upstream，只算新增 U_parse/U_summarize |
| **Arm-3** | 修改上游后的增量重算（判定 H/I） | Arm-2 基线上改 `doc_v1` → U_upstream + U_parse/U_summarize（下游传递）失效重算；无关单元保留 |

三个 arm 用**同一份 `doc_v1`、同一套依赖图、同样模型身份与可比配置**；各自保留原始日志
+ 结构化指标（不可只报告汇总结论）。

---

## 4. 可观测指标（预先定义，逐项对应判定 A–J）

| 判定 | 指标来源 | 如何测（本方案实现） |
|---|---|---|
| A. 真实模型路径 | `stage.log` model-call 记录 | 每个 execution-stage 打印其子智能体"执行了什么工作"，并带 counterfactual 标记 |
| B. 持久结算 | carrier settle → IS object sha256 | arm-2 restore 前后 payload_digest match；进程结束后仍可从 IS 读到 |
| C. 旧缓存隔离 | stage handle / process boundary | arm-2 **新阶段由新子智能体承担**，旧 stage 对象与 prefix 不传入；日志留 timestamp + handle-id |
| D. 结果恢复 | IS settle + reuse-match | arm-2 U_upstream **来自 IS**，且其输出 = 完整重算 baseline 对应项 |
| E. 避免重复计算 | counterfactual-probe `prefix_tokens` | U_upstream 在 arm-2 **未进入本轮"真执行"**（有 stage.log "skip-reused"），且反事实探针可验证若重算会产出什么 |
| F. 新阶段执行 | stage handle | U_parse/U_summarize **由 arm-2 的新阶段真实执行**（非残留） |
| G. 正确性 | arm-1 vs arm-2/arm-3 最终输出比较 | pre-defined predicate：arm-2/3 结果与 arm-1 **token-prefix 级等价** |
| H. 选择性失效 | invalidate_settlement DFS + reuse-match | arm-3：改 doc_v1 → U_upstream+下游 invalidated；无关项保留 |
| I. 工作量收益 | prefix_tokens：重算单元数 / 复用单元数 / total calls | arm-2 arm-3 的 compute vs arm-1 baseline；**耗时单独列，不据单次耗时判收益** |
| J. 可复现 | 运行命令 + env + 配置 + 原始 log（logs/*.jsonl） | `python3 selftest.py --arm all`，输出结构化 jsonl 可复核 |

---

## 5. pre-defined PASS/FAIL / NOT VERIFIED 判定表（先写死，跑完再填状态）

| 项 | PASS 条件 | 本方案默认态（如实标注，除非证据推翻） |
|---|---|---|
| A 真实模型路径 | 有实际模型调用记录（本会话子智能体 + Swift continueExecution 声明） | **PASS-部分**：本会话真执行 + Swift 入口存在；真 MLX forward 本次不跑 |
| B 持久结算 | settle→IS sha256 arm-2 进程结束后仍恢复成功 | 待测（预期 PASS） |
| C 旧缓存隔离 | 新阶段无法访问旧 prefix / 内存（执行级证据） | **PASS-部分**：执行生命周期隔离已覆盖；真 KV-prefix 寿命不测 → C 的"KV prefix"子项 NOT VERIFIED |
| D 结果恢复 | arm-2 有效结果来自 IS（非残留/未声明旁路） | 待测（预期 PASS） |
| E 避免重复计算 | counterfactual 证明真避免了模型工作（非仅跳过显示） | **PASS-部分**：info-reuse 证明充分；compute-reuse 的"真 avoided model work"依赖外部二进制复核 |
| F 新阶段执行 | arm-2 新增单元由新阶段真执行 | 待测（预期 PASS） |
| G 正确性 | arm-2/arm-3 = arm-1 prefix 级等价 | 待测（预期 PASS，需 counterfactual probe 佐证） |
| H 选择性失效 | doc_v1 变更 → U_upstream+下游失效；无关项保留 | 待测（预期 PASS） |
| I 工作量收益 | prefix/调用数证明 compute-save；耗时单列 | **PASS-部分**：info/reuse 单位可测；真"model work saved"须 Swift 复核 → **部分 PASS** |
| J 可复现 | 命令+env+log 可复核 | 待测（预期 PASS） |

**核心结论门槛**：仅当 A–H 全部 PASS **且** I 有可信工作量证据时，才判"本次模型级连续计算验证成功"。
某项不可观测即标 NOT VERIFIED，**不默认通过**。

---

## 6. counterfactual-probe（区分 info-reuse / compute-reuse 的核心机制）

每个单元定义两条输出：
- `real_prefix(unit)` —— 真实"执行/续算"时该产出的 token-prefix（= Swift forward 的物化）。
- `counterfactual_prefix(unit, if_recomputed)` —— 若它**被真实重算**会产出的 prefix（含
  "这个单元确实被执行了"的证据标记）。

判定逻辑：
- arm-2 若**复用** U_upstream：本阶段 real_prefix(U_upstream) == arm-1 的该值，且
  stage.log 记 `skip-reused`（非本轮执行），且 counterfactual-prefix **未在本轮出现**
  → 证据链成立（D/E）。
- arm-2 若**误用旧内存/残留**：real_prefix(match) 但 stage.log **有执行记录**（未标 skip）
  → E FAIL（用了残留缓存）。

> 这是任务书 §7/"验收重点"要求的核心：read = info-reuse；skipped historical model work +
> correct delta output = compute-reuse。本机制把两者分开记录、分开判定。

---

## 7. 执行节奏（不一次性大改）
1. selftest.py（隔离引擎 + 三 arm + counterfactual probe，纯 stdlib）。
2. `--arm 1` 跑完整重算基线（确认正确性基准 + token-prefix 基线）。
3. `--arm 2` 跑持久化恢复续算（验证 B/C/D/E/F/I）。
4. `--arm 3` 跑选择性失效（验证 H/I），不改任何 stable path / existing evidence。
5. 每 arm 保留 `logs/<arm>.jsonl` + 失败证据（不删、不放宽标准）。
6. 汇总 results.md / limitations.md / handoff.md。

> ⚠️ **诚实边界**：本次是"会话模型驱动 + carrier 确定性结算"复刻 Swift `continueExecution`
> 语义；真 MLX forward / token-prefix 寿命依赖外部二进制（本次不加载）。因此
> **A/C/E/I 中"真模型工作量化"子项本次标 NOT VERIFIED**，唯一真实来源是 Swift 侧
> `consumedPrefixLength`/`nextInputTokenCount`——须在 Swift build 重跑复核，**不在本次范围**。
```
end of experiment_plan.md
```
