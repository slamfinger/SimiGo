# Nodes-out Candidate A 三层 correctness audit 证据包 v0.1

**状态**：`AUDIT_READY / EXTERNAL SIGNATURE REQUIRED`。  
**边界**：本包只固化 Runner v2.2.1 的 L1/L2/L3 correctness 证据；**不是** Candidate A effect interpretation，也不解锁 Tier-1 采数。

## 1. 审计对象

| 项 | 值 |
|---|---|
| Runner commit | `f4d880efd4cac21e60a55688dd686b801f3b7044` |
| Runner | `trackE-residency/nodes_out_experiment_runner.py` |
| Runner SHA-256 | `ace241fc6ca22bd1dd40d2e6036662ae0b1e2e1564f49fe3a140900e26495f17` |
| Frozen baseline | `17bde28:trackE-residency/residency_policy_simulator_v3.py` |
| Baseline blob SHA | `ff6d4e21df40db800e64bd5c949c39b3d77d22aa` |
| Official artifact | `trackE-residency/runs/NODES_OUT_RUNNER_AUDIT_20260922/runner_audit.json` |
| Artifact SHA-256 | `556ab61f2fe39fdf0db0a392d2bc99496d6ba83b09fc9e427f481aac68216521` |

## 2. 独立复跑口径

在同一工作树中执行三次：

```bash
python3 trackE-residency/nodes_out_experiment_runner.py
```

- 第 1/2 次输出分别保留为 `audit_run_1_stdout.txt` / `audit_run_2_stdout.txt`。
- 第 3 次覆盖 official artifact 后，保留为 `runner_audit_post_rerun.json`。
- 三次 stdout 逐字一致，diff = 0。
- 第三次复跑前后的 official artifact SHA-256 均为 `556ab6…216521`，未漂移。

## 3. 提交审核的门位读数

| 门位 | 结果 |
|---|---|
| Baseline regression | PASS / 0 |
| L1 event-level correctness | hot PASS / tree PASS；formal violation 0 |
| L2 step-level correctness | hot PASS / tree PASS；formal violation 0 |
| L3 terminal-state correctness | hot PASS / tree PASS；formal violation 0 |
| L1 negative test | 检出 synthetic fault=1，PASS |
| Deterministic double-run | hot dd=0；tree dd=0 |
| Runner FINAL | PASS / formal violation 0 |

机器可读证据见 `audit_evidence.json`。

## 4. 审核方仍需独立核验的问题

1. `f4d880e` 实际源码中的 L1 contract 是否与 Candidate A 单 `res` 位状态机一致。
2. L1 是否继续排除当前节点外化、非法 transition、非当前 decode touch，并把 GDN/ATT pair 内间态排除在独立 node event 之外。
3. L2 是否仍逐步比较 frozen baseline five_tuple，而不是重写 baseline。
4. L3 是否仍绑定 frozen terminal state 与 frozen aggregate，并检查 Candidate 驻留上限。
5. L1 negative test 是否真实可触发且不污染 formal violation。
6. deterministic 比较是否覆盖 `events`、`final`、`steps`、`violations`。

## 5. 结论边界

本证据包支持把下一门位交给审核方做三层 correctness audit 的外部署名；  
本包本身不署名 FINAL AUDIT PASS，不做效果优劣判断，不解锁采数。
