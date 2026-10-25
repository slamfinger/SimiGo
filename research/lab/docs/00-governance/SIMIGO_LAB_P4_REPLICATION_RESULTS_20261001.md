# P4 Replication Results — Common Base Topology under R0 Audit Framework

日期：2026-10-01
状态：`EXECUTED / MECHANICAL VERDICT: PASS / AWAITING HUMAN SECOND LAYER`
任务令：human 2026-10-01（「进入 P4 Replication（使用 R0 audit 框架重新
验证 Common Base topology）」；此前 Empirical Replication Audit Phase-1
计划已签发，Day 1 = R0 ✅ → P4 replication）
性质：复制验证，非新研究命题。只验证已有命题，不新增理论。

---

## 1. 复制对象与判据来源

- 被复制实验：P4 Common Base（原执行 `b0efc99`，human 验收「S₀ 在当前
  样本类中具有 Common Future Base 性质」）
- 判据来源（逐字，未修改）：P4 Design `792afbc`（§1 base-record /
  §2 ID-1..4 / §3 冻结输入 / §4 Independence 换序协议 / §6 J1..J6 预注册
  判读）；实现逐字移植自原执行 harness
  `Palace1R4P4ExecutionTests.swift @ 70081e5`（产品仓本地对象恢复）
- 复制计划原则遵守：①只验证已有命题 ②全部新 runUUID
  ③判定输入不含任何旧 observation/summary（原跑产物
  `/tmp/simigo-p4/` 判读路径零读取）④旧结果仅作预期对照
  ⑤每实验存 harness 源 SHA/runUUID/model+config hash/runtime
  trace/判读输出/人工审计记录

## 2. R0 框架接线（与原跑的证据通道差异）

原跑用共享 append-only 观测文件（无 run-UUID、墙钟）；复制版全部走
`ReplicationAuditRunner`：

- 每 invocation 独立目录 `results/replication/{runUUID}/`
  （metadata.json / events.jsonl / summary.json / hashes.json /
  r0_verify.json），目录已存在即抛错（碰撞防护）
- metadata：gitCommit=dc12a0c + gitDirty=true（harness 按纪律不进产品
  仓 commit，改为 harness 源文件 SHA256 入 metadata）+ modelHash
  （快照 revision + config.json SHA）+ checkpointHash + configHash +
  harnessSHA
- events.jsonl：单调钟（DispatchTime uptimeNs）事件流
  （run_start/model_load_*/restore_*/identity_checks/generate_*/
  isolation_*/run_complete），每目录 r0_verify 全项校验
- Runner 扩展（repoPath/harnessSHA/configHash 可选字段，默认行为
  不变）后 R0 自检重跑再认证：**ALL CHECKS PASSED**（2 tests 含目录
  碰撞检测）

## 3. 执行记录（6 个独立 xcodebuild 进程，2026-10-01 15:06–15:09 +0800）

| # | invocation | runUUID | 时长 | 内容 |
|---|---|---|---|---|
| 1 | S2Form | audit-20261001-333E166E | 56.1s | 冻结脚本→8 轮真实生成→saveSessionCache 形成 S₀′（pos 16） |
| 2 | S1Run1 | audit-20261001-41EB8D2A | 48.4s | restore→A(ΔA₁→ΔA₂)→新 restore→B(ΔB₁→ΔB₂) |
| 3 | S1Run2 | audit-20261001-25E164C0 | 41.8s | 换序：restore→B→新 restore→A |
| 4 | S2Run1 | audit-20261001-3141ECC6 | 13.0s | 同 Run1 剖面 |
| 5 | S2Run2 | audit-20261001-BF2D5DE2 | 13.1s | 同 Run2 剖面 |
| 6 | Adjudicate | audit-20261001-9B526934 | 0.17s | 纯文件判读（0 generate），J1..J6 → judgment.json |

- 模型：Nail-Qwen3.6-35B-A3B-MLX @ 31a0106…（每进程真实加载
  3.7–5.6s）；greedy（temperature=0）、maxTokens=128、tools=nil
- S₁ fixture：`/tmp/simigo-palace1-e1/esr2/t3gateB/b0`（同一 intact
  工件，pos 17）；S₂ fixture 本轮新形成
  `/tmp/simigo-p4-replication/sample2`（不复用原跑 sample2 工件）
- 冻结脚本 8 条 + Δ/锚词/实体在一切计算前写入 events（先冻结后形成）
- 生成真实性：16 个分支 generate 全部 generationTokens>0、
  toolCalls=0（文本通道干净，无 D5 通道疑云）；形成轮 8 generate

## 4. 机械判读（预注册规则逐字适用）

**overall = PASS**（judgment.json @ audit-20261001-9B526934）：

```text
s1: J1 identity PASS / J2 divergence PASS / J3 anchoring PASS /
    J4 order-independence PASS / J5 isolation PASS / J6 evolution PASS
s2: 同上全 PASS
```

- J1：8 次 restore 的 ID-1..4 全 YES；跨 run base-record 四元恒等
- J2/J3：两分支输出非空且互异；锚定判据全中
- J4：换序跨独立进程 **8/8 逐字复现**
- J5：branch-checkpoints 204→204、prefix-pool 2→2（全部 6 目录）
- J6：每分支第二轮非空、衔接本分支、跨分支不雷同

## 5. 预期对照（仅对照，非判定输入）

- **S₁ 全部 8 个输出（Run1+Run2）与原执行逐字相同**（同 fixture 同
  greedy 跨日复现）——原 P4 结果的强复制信号
- S₂ 本轮重新形成（KV 数值必然不同），输出不要求与原跑同；其内部
  换序逐字复现已由 J4 覆盖

## 6. 边界与诚实登记

- gitDirty=true：harness 三个源文件按「实验代码不进产品仓 commit」
  纪律保持产品仓未提交（staged/untracked），完整性改由 harness 源
  SHA256 记录 + 源码归档本仓 `docs/02-evidence/p4-replication-20261001/harness/`
  （P4ReplicationAudit 1f816ebc…/ReplicationAuditRunner 1c5fc1ea…/
  ReplicationAuditSelfTest 9e2cee2e…）
- 判据移植保真：J 规则/锚定判据/n-gram 实现/冻结输入与原 harness
  逐字一致；改动仅=证据通道（R0 工件化）+摘要结构加字段
  （role/order/r0RunUUID）
- Sample-3 模型维度 coverage gap 维持登记（同模型同 vendor），不伪装
- 拓扑级结论，不涉性能（D8）；duration_ms 仅运行时 trace 字段
- 本轮不推翻也不加固原跑以外的任何命题；「旧结果=预期对照」边界遵守
- 原执行 harness 从产品仓本地 git 对象（70081e5，安全事件已撤回的
  公开 commit）恢复——仅本地读取，产品仓工作区零 commit

## 7. 产物索引

- 工件：`docs/02-evidence/p4-replication-20261001/audit-*/`
  （6 runUUID 目录全量）
- Harness 源：`docs/02-evidence/p4-replication-20261001/harness/`
- 原跑产物（预期对照用，未入判定）：`/tmp/simigo-p4/`（本机）
- 复制工作区：`/tmp/simigo-p4-replication/`（本机，含 S₂′ fixture）

**复制结论（预注册措辞）：** 「S₀ 可作为多个未来计算分支的共同基点」
在本样本类上再次成立（拓扑级，不涉性能）——P4 Common Base topology
通过独立复执行 + R0 仪器化通道复制成功。终判归 human second layer。
