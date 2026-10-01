# P7-G0: Adapter Capability Audit

日期：2026-10-01  
状态：`AUDIT COMPLETE / AWAITING HUMAN REVIEW`  
方法：代码级审查（LLAMAServerExecutionStateAdapter 294 行 + Backend 90 行 + Executor）  
纪律：纯观测——不扩展 adapter，不修改 backend 语义

---

## §0 Audit rules

```text
允许：expose evidence（观测层扩展）
禁止：create missing state relation（语义层扩展）

分类：
  native     = adapter/backend 原生提供
  derived    = 可从 native 数据推导
  unavailable = 当前无法表达
```

## §1 Per-relation capability

### Identity

```yaml
native:
  - ExecutionID (opaque, Sendable)         # coordinator-owned
  - openModelIdentity (String?, /props)    # model path from server

derived:
  - model semantics: openModelIdentity → same GGUF file?
    (NOT equivalent to MLX modelId which references safetensors)
  - conversation lineage: createExecution(同一 ID, 同一初始 text)
    + continueTurn(同一 user turns) → lineage 可重建

unavailable:
  - kvFingerprint equivalent (config binding)
    MLX: kvFingerprint = String(describing: KVCacheSettings)
    llama: no config fingerprint exposure

capability: PARTIAL (native core present, config binding missing)
```

### Position

```yaml
native:
  - ExecutionPosition (Int64)              # coordinator-owned
  - boundPositions [ExecutionID: ExecutionPosition]  # backend dict
  - tokenPrefix [Int]                      # count = position proxy

derived:
  - tokenPrefix.count ↔ processedTokenCount (MLX equivalent)
  - position advance = prefix + new tokens → new count

unavailable:
  (none — Position fully supported)

capability: FULL (native)
```

### Semantic Anchor

```yaml
native:
  - ExecutionContinuation.nextInput (String)  # last user text
  - tokenPrefix [Int]                          # tokens from tokenizeText(history)
    → prefix IS the anchor (token sequence encodes semantic context)

derived:
  - anchor equivalence: same initial text + same turn sequence
    → same tokenPrefix (if same tokenizer) → same semantic context
  - anchor comparison: prefix[0..N] equality check

unavailable:
  - explicit history[] JSON array (MLX SessionCacheMetadata.history)
    llama adapter does not store parsed history separately
    history is implicit in the token prefix

capability: PARTIAL (native via token prefix, no explicit history array)
```

### Continuation

```yaml
native:
  - ExecutionContinuation (nextInput, continuationID)
  - prefix extend mechanism (prompt + generated → advancedPrefix)
  - isPrefix semantics inherent in token prefix structure

derived:
  - continuation validity: new tokens extend existing prefix
    (structurally guaranteed — prefix is always a prefix)

unavailable:
  - multi-level reuse policy (MLX PromptCacheReusePolicy:
    extend/rewind/rebuild/exact-n1 — llama adapter only extends)

capability: FULL (native, simpler policy than MLX)
```

## §2 Capability matrix

```text
┌──────────────┬──────────┬───────────┬────────────────────────────┐
│ Relation     │ MLX      │ llama.cpp │ Mapping feasible?          │
├──────────────┼──────────┼───────────┼────────────────────────────┤
│ Identity     │ FULL     │ PARTIAL   │ YES (core present)         │
│ Position     │ FULL     │ FULL      │ YES                        │
│ Anchor       │ FULL     │ PARTIAL   │ YES (token prefix as anchor)│
│ Continuation │ FULL     │ FULL      │ YES                        │
└──────────────┴──────────┴───────────┴────────────────────────────┘
```

## §3 Mapping feasibility

```text
Identity mapping:
  MLX modelId ↔ llama openModelIdentity
  (different file formats = carrier difference, not closure difference)
  MLX kvFingerprint → NO llama equivalent → VALIDATION_REJECTED for
  this sub-component, or test without config fingerprint

Position mapping:
  MLX processedTokenCount ↔ llama tokenPrefix.count
  Both represent "how many tokens have been processed"

Anchor mapping:
  MLX explicit history[] + rendered prompt
    ↔ llama implicit tokenPrefix (tokenized history)
  Different representation, same semantic function:
  "this computation corresponds to this conversation context"

Continuation mapping:
  MLX isPrefix + multi-level policy
    ↔ llama prefix extend (single-level)
  Different policy complexity, same structural invariant:
  "new input extends existing computation state"
```

## §4 Conclusion

```text
P7-G0 audit result: ALL FOUR RELATIONS have at least a partial
native expression in the llama.cpp adapter. No relation is
completely unavailable.

Identity and Anchor are PARTIAL (missing config fingerprint /
explicit history array respectively). These gaps are carrier-level
differences, not closure-level impossibilities.

P7 execution can proceed with the following scope adjustment:
  Identity: test with ExecutionID + modelIdentity (skip kvFingerprint)
  Anchor: test via token prefix equivalence (not explicit history)
```
