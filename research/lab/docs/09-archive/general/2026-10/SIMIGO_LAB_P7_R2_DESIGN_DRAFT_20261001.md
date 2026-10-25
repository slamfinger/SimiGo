# P7-R2: Real Carrier Continuation Validation — Design Draft v2

> **ARCHIVED** 2026-10-20 · line: 通用治理 / 其他 · original: docs/00-governance/SIMIGO_LAB_P7_R2_DESIGN_DRAFT_20261001.md
> Evidence status: unchanged (content frozen; moved only)


日期：2026-10-01  
状态：`DESIGN DRAFT v2 / APPROVED WITH REVISIONS / READY FOR HARNESS`  
前置：P6 FROZEN → P7 contract-level validated → audit complete  
核心命题：B(S) + Δ → Continuation  
Contract v1.0：不变  
v1→v2 变更：native-produced state / cross-process / cold fallback
rejection / anchor functional observation / continuation evidence requirement

---

## §0 核心命题（v2 最终）

> 对任意 backend B，若存在一个由 B 产生的 Execution State S，使得
> 跨进程 restore 后，B 能在保持 Identity、Position、Anchor、Continuation
> 四项关系的情况下接受新输入 Δ，则 B 支持 Execution State closure。

形式：B(S) + Δ → Continuation

## §1 Hard boundaries

```text
❌ 不验证 MLX output == llama output
❌ 不验证 KV layout / internal cache / token id identical
❌ 不验证 fake state → restore（必须是 native-produced state）
❌ 不验证 same-process save → restore（必须跨进程）
❌ 不接受 cold fallback 作为 continuation 证据
❌ 不进入 Palace / Security
```

## §2 五项 v2 修正

### 修正 1：S 必须由真实 backend runtime 产生

```text
✅ 正确流程：
  runtime computation → backend native state → adapter extraction
  → Execution State representation

❌ 禁止流程：
  fake Execution State → restore
  （退化为 contract test，不是 runtime validation）
```

### 修正 2：Checkpoint 必须跨进程

```text
✅ 正确流程：
  Process A: create → generate → checkpoint → exit
  Process B: load → restore → continue

❌ 禁止流程：
  同一 process: create → save → restore
  （内存残留 / singleton / cache pool 污染结果）
```

### 修正 3：Position monotonic requirement

```text
必须满足：
  P_restore == P_checkpoint
  P_continue > P_restore

禁止：
  P_restore > P_checkpoint（位置跳跃 = 状态污染）
```

### 修正 4：Anchor 双层观测

```text
Layer 1 (Identity)：anchor_hash equal before/after restore
Layer 2 (Functional)：change Δ input → continuation boundary changes

如果只有 Layer 1 没有 Layer 2 → anchor 可能是无作用的 metadata
两层都观测到 → anchor 真正参与计算
```

### 修正 5：Continuation 判定排除 cold fallback

```text
P5 教训：KV exists ≠ KV used

PASS 必须 observe 至少一个 backend-native continuation evidence：
  MLX: cache reuse / extend mode / cacheHitTokens > 0
  llama: context continuation / prefix reuse

如果 backend 未暴露 continuation evidence → INCONCLUSIVE（非 PASS）

❌ 禁止：
  restore → discard state → fresh generate → 标记为 PASS
```

## §3 实验流程

```text
Process A:
  Start backend runtime (real model)
    ↓
  Create session / context
    ↓
  Generate history (real model inference)
    ↓
  Checkpoint: extract native state → save to storage
    ↓
  Destroy runtime (exit process)

─── process boundary ───

Process B:
  Start backend runtime (same model)
    ↓
  Restore from checkpoint
    ↓
  Observe: C1 Identity / C2 Position / C3 Anchor
    ↓
  Apply Δ (new user input)
    ↓
  Observe: C4 Continuation (backend-native evidence required)
```

## §4 Observation Schema

```json
{
  "backend": "mlx",
  "run_id": "...",
  "timestamp_wall": "...",
  "timestamp_monotonic": "...",

  "identity": {
    "same_lineage": true,
    "evidence": "execution_id match"
  },

  "position": {
    "before_destroy": 1200,
    "after_restore": 1200,
    "monotonic_ok": true,
    "after_delta": 1234
  },

  "anchor": {
    "identity_hash_before": "...",
    "identity_hash_after": "...",
    "hash_equal": true,
    "functional_test": {
      "delta_changed": "different input text",
      "continuation_boundary_changed": true
    }
  },

  "continuation": {
    "accepted": true,
    "backend_evidence": "cacheHitTokens=1200, mode=extend",
    "cold_fallback_detected": false
  },

  "resource_observation": {
    "memory_before_mb": 0,
    "memory_after_load_mb": 19000,
    "memory_after_generate_mb": 20500
  }
}
```

## §5 四项判据（v2）

### C1 Identity
```text
PASS：restore(S) → same execution lineage
FAIL：new unrelated session
```

### C2 Position
```text
PASS：P_restore == P_checkpoint AND P_continue > P_restore
FAIL：P_restore ≠ P_checkpoint OR P_continue ≤ P_restore
```

### C3 Anchor（双层）
```text
PASS：hash_equal AND functional_test confirms computation participation
PARTIAL：hash_equal but no functional evidence
FAIL：hash mismatch OR anchor points to unrelated context
```

### C4 Continuation
```text
PASS：backend-native continuation evidence observed (extend/reuse)
INCONCLUSIVE：continuation occurs but no backend-native evidence available
FAIL：cold start / rebuild / state discarded after restore
```

## §6 Failure 分类

```text
CONTINUATION_VALIDATED  closure 保持 + native evidence
CLOSURE_REJECTED        状态无法继续
MAPPING_LIMITED         adapter 无法表达
INCONCLUSIVE            观测不足（含 continuation evidence 缺失）
```

## §7 实验矩阵

| Backend | Runtime | Process boundary | State 来源 |
|---|---|---|---|
| MLX | 真实模型（Nail-Qwen3.6-35B-A3B-MLX） | YES | nativeMLX loadSessionCache |
| llama.cpp | 真实模型（llama-server） | YES | LLAMAServerExecutionStateBackend |

## §8 预注册措辞

```text
MLX VALIDATED + llama VALIDATED:
  "Both MLX and llama.cpp backends independently satisfy the
   continuation invariant across process boundaries: native-produced
   state S, destroyed and restored, accepts Δ as valid continuation
   with backend-native evidence. Execution State closure preserved."

One VALIDATED, one not:
  "{backend} satisfies; {other} does not. Closure definition may
   need backend-specific qualification."

Both fail:
  "Neither backend preserves continuation invariant across
   process boundary save/restore. ES closure requires revision."
```
