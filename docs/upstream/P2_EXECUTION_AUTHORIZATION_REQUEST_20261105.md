# P2 真机执行授权请求（C1 · 四阶段）

**Status**: **AUTHORIZED (C1) — E0 已通过（2026-11-05，见配置记录 §5.10）；阶段 1 待用户确认后启动**  
**Date**: 2026-11-05  
**Upstream**: `P2_EXPERIMENT_PLAN_20261105.md`（G1 PASS·CLOSED）、`P2_CONFIG_RECORD_20261105.md`（①–⑤全部定案）  
**请求事项**: 授权执行 **一条 C1 主链**（阶段 1–4）；**不请求 C2**。

> 本文件是授权请求，不是执行授权。用户明确回复“授权执行 C1”之前，不启动预检之后的任何模型加载、生成、注入或状态写入。

---

## 1. 请求摘要

请求授权在本机执行一条完整 C1 链：

```
S0 预检（不加载模型）
  → Run A：阶段 1（真实结算）+ 阶段 2（旧 KV 存活态/释放读数）
  → Gate A（Run A 正常退出后停审）
  → Run B：阶段 3（IS Admission/恢复 + 失效注入）+ 阶段 4（新 ES 续推）
  → Gate B（最终停审）
```

**明确不请求**：

- C2 条件替换链；
- 第二模型加载（探针 A 仅使用 M2 repo ID 字符串）；
- 实现修改、依赖新增、模型下载；
- 对外发送、公开、建 PR；
- 手工修改 settlements 或任何权威状态。

---

## 2. 机器与基线事实（只读核验）

| 项 | 当前读数 |
|---|---|
| 架构 / 系统 | arm64；macOS 27.0.1（Build 26A434） |
| 物理内存 | 32 GiB（34,359,738,368 bytes） |
| 可用磁盘 | 约 466 GiB（数据卷） |
| 主模型 | `mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit` |
| 模型快照 | `6e302ea604ad9ab206367e2c501d1571023e7b6d` |
| 模型体积 / 分片 | 约 16 GiB；4 个 safetensors 分片在场 |
| 仓库 HEAD | `421aaa02d1ad`，分支 `main` |
| 工作树 | **docs-only dirty**：一个已跟踪文档修改 + 若干未跟踪文档；无代码改动 |
| 生产状态 | `~/.simigo/simigo.sqlite3` 存在；本实验**不得写入**该生产库 |

**说明**：工作树不是 clean commit。若实验要求 clean build，需先获得“文档提交/冻结”授权；否则执行时必须把 HEAD、docs diff digest 与 dirty 状态写入证据。不得把 docs-only dirty 说成代码改动，也不得在未授权时提交。

---

## 3. 执行范围

| 段 | 范围 | 关键产物 |
|---|---|---|
| S0 预检 | 身份、路径、端口、数据库、telemetry、内存/磁盘、模型分片核验；不加载模型 | 预检报告；任一项失败即停 |
| Run A / 阶段 1 | 通过公开 HTTP 面发起真实生成；构造 R（检索结算）→ T（答案结算，真实封存 R）；探针 A 元数据拒绝；重复请求恰好一次 | E1.1–E1.4；T→R 依赖边与 payload digest |
| Run A / 阶段 2 | T 结算提交后、正常退出前：SQLite 一致性、旧 KV 存活态、O2.1/O2.2a/O2.2b/O2.3 读数；reattach 探针 | O2.1–O2.3；Run A 身份与退出状态 |
| Gate A | Run A 正常退出后停审：SQLite 已提交、证据已封存、无停止条件 | Gate A 记录；等待用户决定 Run B |
| Run B / 阶段 3 | 全新进程、全新模型加载；以 settlement_id 显式 Admission；真实源文件变更注入；t₂ 恢复拒绝；篡改探针 | E3.1–E3.3；理论/实际失效集合 |
| Run B / 阶段 4 | 新 ES 续推；执行决策计账；冷启动对照；两跳引用链；E4.4 绑定链 | E4.1–E4.4；最终链证据 |
| Gate B | Run B 退出后提交全链结论等级；不自动复刻/外发 | 最终报告 |

**公开路径要求**：阶段 1 必须走公开 HTTP 面，不得用 `SimiGoG1G3Entry` 的 `restricted_production_path` 替代。若公开 HTTP 面在当前构建中不可用，**停在 E0 并请求范围变更**，不得静默改用 headless 路径。

---

## 4. 执行配置（E0 预检必须确认；E0 = §3 的 S0 预检）

| 项 | 建议配置 | 失败处理 |
|---|---|---|
| 进程形态 | 参考 App/runtime 前台 + 公开 HTTP listener；Run A 与 Run B 为两个独立进程 | 若只能 headless：停止，另行请求 |
| HTTP 绑定 | 仅 loopback；端口由 E0 确认并记录 | 非 loopback 或端口冲突：停止 |
| 隔离根 | `SIMIGO_HOME` 与 `SIMIGO_CACHE_ROOT` 指向本次实验专用目录 | 无法隔离：停止，不碰 `~/.simigo` |
| 实验根 | `work/p2-c1/`（证据、源文件、快照、日志） | 路径不可写/空间不足：停止 |
| IS 数据库 | `<实验根>/simigo-home/simigo.sqlite3`；运行时写入经公开流程；分析用只读连接/快照 | 指向生产库：停止 |
| 模型路径 | 本机 HF 缓存快照；零下载 | 分片/digest 不符：停止 |
| 构建身份 | HEAD + docs diff digest + dirty 标记 | 代码 dirty：停止 |
| Telemetry | 公开 restore 事件、typed refusal、[EXEC] 行、token/执行决策计账可读 | 覆盖不足：停止，不以缺席充当证明 |
| O2.3 读数 | 先探测 G1 是否暴露容量/分配；否则按 G2/G3 降级规则 | 只有 G3：O2.3 不足，停链 |
| 变更检测入口 | 公开 work-root reconcile/索引流；E0 记录实际入口 | 不可用：停止，不自动改用后备注入 |
| T→R 绑定 | 通过公开 demand/retrieval settlement 流构造；E0 记录命令与响应 | 无法真实封存 R：停止 |
| 探针 A | begin M1；settle 声明 M2 repo ID 字符串；不加载 M2 | 拒绝路径解析/加载 M2：停止 |
| 源文件注入 | F/N1/N2 均为实验专用真实文件，位于 `<实验根>/source/`；改前/改后记录 digest；不碰生产文件 | 无法确认真实磁盘变更：停止 |

本次建议的实验绝对根：`/Users/mr.simi/Documents/Codex/2026-11-05/agent-1-p2-config-record-20261105/work/p2-c1`；E0 确认可写后固定，所有 `SIMIGO_HOME` / `SIMIGO_CACHE_ROOT` / 证据目录均在其下。

**E0 失败即停**：以上任一项不能满足，必须在任何模型加载前停止并报告；不得以“先跑起来再说”替代配置核验。

---

## 5. 证据输出

所有证据写入 `work/p2-c1/evidence/`，按 `chain/stage/` 分目录，不覆盖旧文件。

| 阶段 | 必留证据 |
|---|---|
| S0 | 机器/系统/内存/磁盘；repo HEAD 与 dirty 状态；模型快照与分片 digest；端口与路径；telemetry 覆盖声明 |
| S1 | 请求/响应原文；settlements 行；payloadDigest；producer model/tokenizer；探针 A 每项 typed refusal；写入边界检查；重复请求次数；T→R 依赖边与 digest |
| S2 | Run A PID/启动时刻/EXEC UUID；模型身份；KV 读数 G1/G2/G3 与采集时点；SQLite 一致性快照；reattach 探针；O2.2a 工件清单；O2.2b 每入口触发/遥测/计账；正常退出状态 |
| S3 | Admission 检查单；依赖图快照；理论受影响集合；实际 invalidated/未受影响集合；t₂ typed refusal；篡改探针；主注入前后 digest |
| S4 | 执行决策计账（recomputed/reusedExecution）；token 计账；冷启动对照；结算行变化；两跳引用链；E4.4 五项绑定链或降级结论 |
| Gate | 每阶段 observed/expected 分列表；停止条件检查；预算消耗；结论等级（PASS/PASS-LIMITED/UNVERIFIED/FAIL/BLOCKED） |

**证据纪律**：日志叙述不作为证据；候选读数必须标注；降级必须写明受限主张；不得把“未观察到”升级为“所有路径不可达”。

---

## 6. 预算（引用 ⑤ 定案）

| 项目 | C1 单链上限 |
|---|---:|
| 模型加载 | 2 次（Run A、Run B 各一次） |
| 真实生成调用 | 8 次 |
| 输入 / 输出 token | 64K / 4K |
| 单次上下文 / completion | 8,192 / 512 tokens |
| 机器执行时间 | 3.5 小时 |
| 外部日历窗口 | 24 小时 |
| 新增磁盘写入 | 4 GiB |
| 峰值进程内存 | 24 GiB（且不超过物理内存减 4 GiB） |
| 外部网络 / 费用 | 0 / 0 |

C2 未授权；任何额外加载、额外调用、额外重跑都不在本次请求内。

---

## 7. 停止条件

沿用 `P2_CONFIG_RECORD_20261105.md` §5.5：

- 红线 1/2 命中；
- 任一预期读数反例；
- 强制证据缺失且不在允许降级内；
- Run A/B 身份无法区分；
- 阶段 3/4 实际消费旧 KV/checkpoint；
- 以 telemetry 缺席作为“未触发”证据但覆盖未验证；
- 需要越过授权边界；
- 环境/模型/DB schema 漂移；
- 预算达到 80% 时禁止新增调用；达到 100% 即停；
- 连续 5 次空转；
- 用户中断；
- 未预期权威写入或 settlement/DB 一致性失败。

**Gate A**：Run A 正常退出后必须停，确认 SQLite 已提交、证据已封存，再由用户决定是否进入 Run B。  
**Gate B**：Run B 退出后必须停，不得自动复刻或外发。

---

## 8. 不请求 / 不做

- 不请求 C2；
- 不请求第二模型权重加载；
- 不请求实现修改或新增依赖；
- 不请求模型下载；
- 不请求对外发送/公开/PR；
- 不请求手工修改 settlements；
- 不请求强制 reexec；
- 不请求应急后备注入；
- 不请求把 headless restricted path 当作公开 HTTP 证据。

---

## 9. 授权记录（2026-11-05）

> 授权 C1，但修改：接受 docs-only dirty，不要求先做 docs-only commit；公开 HTTP 路径保留为 E0 硬门槛。
>
> 裁定：C1 真机执行已获授权，但必须先通过 E0。E0 失败即停止；授权不构成对实验结果的预先认可，也不授权 C2。

**生效解释**：

- 授权仅覆盖 **E0 全部通过后的 C1**；E0 失败不构成执行许可，也不自动触发 C2；
- docs-only dirty 按 §2 记录规则固定；发现任何非文档改动即停；
- 公开 HTTP 路径是 E0 硬门槛；headless restricted path 不得替代；
- Gate A 后必须暂停，提交 Run A 证据并等待用户决定是否进入 Run B；
- E0 只读预检已于 2026-11-05 通过；结论与证据见配置记录 §5.10 与 `work/p2-c1/evidence/s0/e0_report.json`。

