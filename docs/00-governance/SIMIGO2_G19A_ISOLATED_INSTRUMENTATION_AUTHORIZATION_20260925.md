# G1.9-A Isolated Instrumentation Authorization — 2026-09-25

Status: G1.9-A ISOLATED_INSTRUMENTATION = AUTHORIZED
Authority: explicit researcher authorization, 2026-09-25 (conversational, fixed here verbatim)
Precondition chain:

```text
⑦ LOCALITY_ANALYSIS_PASS
      ↓
PREDICTOR_STOP_GATE_NO_GO   (6e8b153)
      ↓
STOP
      ↓
【user explicit authorization】
      ↓
G1.9-A ISOLATED_INSTRUMENTATION = AUTHORIZED
      ↓
NOT YET PREDICTOR
```

## Authorization boundary (fixed, verbatim structure)

```text
ISOLATED_INSTRUMENTATION
        ↓
actual execution observation
        ↓
execution trace
        ↓
重新审查 locality
        ↓
决定是否重新开放 Predictor
```

不会直接进入 Predictor 开发。

### 已授权

- 在隔离实验路径中修改/扩展 instrumentation;
- 捕获真实 forward execution 中的 layer/group execution 事件;
- 首先验证 instrumentation 前后:输出 identity;logits / token 一致性;
  execution 是否改变;时间开销;内存开销;
- 形成真正的 measured execution trace;
- 用 measured trace 重新审查:recurrence → transition locality →
  temporal stability。

### 仍未授权

- Predictor;
- probability / demand probability;
- speculative loading;
- Expert / Token×Expert demand 模型;
- production MLX 修改;
- async I/O / I/O-compute overlap;
- 根据结果直接宣称通用架构。

### 第一阶段 STOP 条件(固定)

第一阶段只回答一个问题:

> 能否在不改变模型计算语义的前提下,获得可信的真实 execution trace?

```text
instrumented ≈ baseline
+ trace stable
+ overhead acceptable
```

三者同时成立才进入 measured-locality 分析。若 instrumentation 本身改变
计算、无法可靠对齐、或观测粒度不足,则在第一阶段 STOP,不向 Predictor
深挖。

## Git-level effect

The researcher verified `6e8b153` externally but explicitly did not claim the
authorization was already in Git. This commit is the Git-level opening of the
gate. The next registered step is the G1.9-A instrumentation design /
pre-run audit — not Predictor work.

Design and first-capture history:
docs/00-governance/SIMIGO2_G19A_GROUP_TRACE_DESIGN_PRERUN_AUDIT_20260925.md
(registered when completed).
