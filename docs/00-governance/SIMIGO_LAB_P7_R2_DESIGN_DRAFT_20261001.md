# P7-R2: Real Carrier Continuation Validation — Design Draft v1

日期：2026-10-01  
状态：`DESIGN DRAFT v1 / AWAITING HUMAN REVIEW`  
前置：P6 FROZEN → P7 contract-level validated → audit complete  
核心命题：∀ backend: restore(S) + Δ → valid continuation  
Contract v1.0：不变

---

## §0 核心命题

> 验证不同 backend 是否存在满足 continuation invariant 的 runtime
> closure——不是验证它们保存相同的数据结构。

每个 backend 独立运行 save → destroy → restore → continue 流程，
观察 closure 四项 invariant 是否在真实 runtime 中保持。

## §1 Hard boundaries

```text
❌ 不验证 MLX output == llama output
❌ 不验证 KV layout identical
❌ 不验证 internal cache structure identical
❌ 不验证 token id identical
❌ 不进入 Palace / Security
```

验证范围：
```text
✓ Identity continuity
✓ Position continuity
✓ Anchor validity
✓ Continuation acceptance
```

## §2 单 backend 实验流程

```text
Phase A (Create & Save)
  Create runtime
    ↓
  Generate prefix P
    ↓
  Checkpoint S
    ↓
  Destroy process/runtime

Phase B (Restore & Continue)
  Restore(S)
    ↓
  Apply Δ
    ↓
  Observe continuation
```

## §3 Observation Schema（backend-neutral）

```json
{
  "backend": "mlx",
  "state_id": "...",
  "identity": {
    "same_lineage": true
  },
  "position": {
    "before_destroy": 1200,
    "after_restore": 1200,
    "after_delta": 1234
  },
  "anchor": {
    "before_hash": "...",
    "after_restore_hash": "..."
  },
  "continuation": {
    "accepted": true,
    "path": "extend"
  }
}
```

不记录 backend 私有字段（kvFingerprint 值、safetensors 路径等）。
只记录 closure relation 的 abstract observation。

## §4 四项判据

### C1 Identity

```text
问题：恢复后的状态是不是原来的状态？
PASS：restore(S) → same execution lineage
FAIL：new unrelated session
```

### C2 Position

```text
问题：恢复后计算位置是否连续？
PASS：before=100 → restore=100 → after_Δ=110
FAIL：restore → position=0（全量丢失）
```

### C3 Anchor

```text
问题：恢复状态仍然绑定正确输入语义？
不是要求保存 history 文本，而是验证 same anchor relation。
PASS：same input prefix → same anchor identity
FAIL：restore 后 anchor 指向不相关的语义上下文
```

### C4 Continuation

```text
问题：restore(S) + Δ 是否被 runtime 接受为 continuation？
PASS：extend（warm continuation from restored state）
允许：backend-specific equivalent of extend
FAIL：cold start / rebuild from zero / unrelated context
```

## §5 Failure 分类

```text
CONTINUATION_VALIDATED  closure 保持
CLOSURE_REJECTED        状态无法继续
MAPPING_LIMITED         adapter 无法表达
INCONCLUSIVE            观测不足
```

## §6 最小实验矩阵

| Backend | State | Restore | Δ |
|---|---|---|---|
| MLX | S₀（完整 history checkpoint） | loadSessionCache from checkpoint | Δ₁ |
| llama.cpp | S₀（token prefix state） | restore from backend dict | Δ₁ |

两个 cell 足够——验证 runtime invariant，不是压力测试。

## §7 关键约束：不能偷偷简化

```text
P5 教训：history text 属于 Anchor，不是附属物。

错误做法：
  save KV → restore KV → generate
  （丢失 anchor → 重复 P5-1 rebuild）

正确做法：
  save abstract closure representation（含 anchor）
  restore
  apply Δ
  观察 invariant
```

MLX 侧：checkpoint 必须包含 meta.json（history）+ safetensors（KV）。
llama 侧：Backend dict 中 tokenPrefix 天然包含 anchor（tokenized history）。

## §8 预注册措辞

```text
MLX CONTINUATION_VALIDATED + llama CONTINUATION_VALIDATED:
  "Both MLX and llama.cpp backends independently satisfy the
   continuation invariant: restore(S) + Δ → valid continuation.
   Execution State closure is preserved across runtime
   save/destroy/restore cycles in both implementations."

One VALIDATED, one not:
  "{backend} satisfies the continuation invariant; {other} does not.
   The closure definition may need backend-specific qualification."

Both fail:
  "Neither backend preserves the continuation invariant across
   save/restore. The Execution State closure definition requires
   revision."
```

## §9 Route

```text
P7-R2 Design v1（本文件）
  ↓ Human review
  ↓ Harness implementation
  ↓ Execution
  ↓ Audit
  ↓ L2 re-freeze
  ↓ Security → Palace
```
