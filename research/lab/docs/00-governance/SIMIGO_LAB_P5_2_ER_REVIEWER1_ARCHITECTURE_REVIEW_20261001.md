# P5-2-ER Reviewer-1: Architecture / Systems Boundary Review

日期：2026-10-01  
Role：Architecture / Systems Boundary Reviewer  
审查对象：`SIMIGO_LAB_P5_2_DEPENDENCY_CLOSURE_OPENING_DRAFT_20261001.md`  
方法：remove-one-relation 概念检验 + Contract v1.0 对照 + MLX 代码证据

---

## Closure Analysis

```yaml
closure:
  identity:
    necessary: YES
    evidence: code-fact
    evidence_detail: >
      NativeMLX performLoad L1617-1631: guard modelId == currentModelId
      else throw; guard checkpointGeneration nonempty else throw;
      guard cacheSHA256 match else throw. generateUsingChatSession L686:
      kvFingerprint match required for session reuse. Missing any of
      these → restore fails or session replaced.
    failure_mode: >
      Without modelId: restore succeeds but the KV tensors are computed
      by a different model — semantics undefined, output garbage.
      Without kvFingerprint: session reuse gate fails (reuseMiss) →
      cold path, full re-prefill — continuation silently degrades.
      Without storageKey: session not found in pool → cannot generate.
    carrier_vs_definition: >
      Identity is NOT a carrier property. Two byte-identical KV files
      with different modelIds represent different Execution States.
      Identity is a relation between the carrier and its computation
      context. This is D-level in Contract v1.0 (storageKey) and
      R-level (modelId, kvFingerprint).

  position:
    necessary: YES
    evidence: code-fact
    evidence_detail: >
      ChatSession.swift L1160-1179: ledgerBootstrapPending checks
      processedTokenCount vs promptTokenIds.count. L1203-1205:
      mainCacheIsAligned = kvCache.processedTokenCount == cachedTokenIds.count.
      When mismatch → PromptCacheReusePolicy returns .rebuild → KV discarded.
      P5-1 trace: 31712 ≠ 212 → rebuild confirmed.
    failure_mode: >
      Without processedTokenCount: framework cannot determine cache
      position → cannot decide extend vs rebuild → treats as cold.
      Without ExecutionPosition (Contract D): logical timeline lost —
      fork/branch/discard semantics collapse.
      Without cachedTokens: ledger empty → alignment fails → rebuild.
    position_type: anchored location (NOT a plain counter)
    position_evidence: >
      Position is anchored three ways: (1) physical offset in cache,
      (2) semantic position on the logical timeline, (3) ledger mapping
      token IDs to cache rows. All three must be consistent for
      continuation. P5-1 showed that breaking any one triggers rebuild.

  semantic_anchor:
    necessary: YES
    evidence: code-fact
    evidence_detail: >
      ChatSession.swift L1166-1175: the ledgerBootstrapPending check
      requires promptTokenIds.count >= kvCache.processedTokenCount.
      The rendered prompt (from history text + delta) IS the anchor.
      Without sufficient prompt tokens, the bootstrap invalidates the
      ledger → rebuild. History text is the alignment proof, not the
      content carrier per se.
    anchor_role: alignment proof (NOT content carrier)
    anchor_evidence: >
      P5-1 showed that when history text is stripped (prompt = 212 tokens
      but cache = 31712 tokens), the cache is rejected — even though the
      KV tensors are intact. The framework does not "use" the history
      content for generation; it uses the tokenized prompt to VERIFY
      that the cache position is explainable. The content matters only
      to the extent that its tokenization length must cover the cache
      offset.
    failure_mode: >
      Without alignment anchor: state exists but cannot be interpreted
      → rebuild. Without semantic content match: state can be aligned
      but points to the wrong context → output diverges from expectation
      (P5-3 ablation axis A tests this).
    open_minimum_form: >
      The minimum anchor may be shorter than full history text.
      Candidate B (token count + content hash) or Candidate C
      (position-only) are possible if the framework can accept
      non-text alignment. This is an empirical question (P5-3 axis A).

  continuation:
    necessary: YES
    evidence: code-fact
    evidence_detail: >
      Contract v1.0 §1.1: ExecutionContinuation (nextInput /
      continuationID) is D — required for the state to be an Execution
      State rather than a snapshot. NativeMLX generateUsingChatSession
      L684-686: isPrefix check determines whether incoming messages
      can extend from the existing session. Without continuation,
      the state is inert data.
    failure_mode: >
      Without continuation relation: state is a snapshot (data at rest).
      It has no defined "what can happen next" — fork/branch/continue
      semantics are undefined. P4 proved that the continuation topology
      (S₀ → A, S₀ → B) is the core value proposition.
    in_state_or_capability: >
      Continuation is IN-STATE (part of the Execution State definition),
      not merely a capability. Evidence: Contract SC-2 defines the
      minimal durable object as including continuation.nextInput.
      However, the acceptance rule (isPrefix) and generation path
      (extend/rebuild/rewind) are R-level implementation details.
      The distinction: WHAT can continue (D) vs HOW it continues (R).

carrier:
  kv: instantiation medium, NOT closure member
  cache: implementation detail, backend-specific
  database: storage choice, NOT authorized
  model_specific_format: carrier, replaceable
  carrier_vs_closure_boundary: >
    Closure = {Identity, Position, Anchor, Continuation}
    Carrier = any physical medium that can hold the closure relations.
    Closure is instantiated BY a carrier, never EQUAL to a carrier.
    P5-1 proves this: the KV carrier was intact but the closure was
    broken (anchor misaligned) → the state was not usable. Carrier
    alone is insufficient.
```

## Minimality Assessment

```yaml
minimality:
  remove_identity: FAIL
    # state attribution collapses → cannot distinguish executions
  remove_position: FAIL
    # continuation point lost → cannot extend or fork
  remove_anchor: FAIL
    # state uninterpretable → rebuild discards computation
  remove_continuation: FAIL
    # state degrades to snapshot → no future semantics

  minimal_closure_confirmed: YES (conceptually, pending ablation)
  evidence_grade: code-fact for MLX; architecture-level for Contract
  caveat: >
    Minimality is confirmed at the DEFINITION level. Whether all four
    are empirically necessary on a specific backend requires P5-3
    ablation. The conceptual argument is: removing any one breaks a
    different invariant (attribution / continuation point /
    interpretability / future semantics), and no subset of the
    remaining three can substitute for the removed one.

  missing_member: NONE identified
  non_member: Carrier confirmed as NOT a closure member
```

## Contract Consistency Check

| Draft claim | Contract v1.0 | Consistent? | Notes |
|---|---|---|---|
| Identity includes model/config binding | Contract covers execution binding (SC-1) | extended | Draft extends Contract |
| Position = physical + semantic + ledger | Contract defines ExecutionPosition as D | complementary | Physical/ledger are R-level bridges |
| Anchor includes backward-facing (history) | Contract covers forward (nextInput = D) | extends | Backward anchor is OP-P5-5 |
| Continuation acceptance rule D or R | Contract defines nextInput as D | split | WHAT = D, HOW = R (OP-P5-4) |
| Carrier ≠ Closure | Contract P = representation | consistent | P5-1 empirically confirms |

## Overclaim check

| Potential overclaim | Status | Reason |
|---|---|---|
| Execution State = KV | NOT MADE | Draft separates Carrier from Closure (§5.3) |
| Minimality is proven | QUALIFIED | Conceptually argued, empirically requires P5-3 |
| History text is unnecessary | NOT MADE | Minimum form is OPEN (§3.5) |
| Backend-independent | QUALIFIED | Relations backend-independent, instantiation backend-specific |

## Reviewer-1 verdict

```yaml
verdict: PASS-WITH-QUALIFICATIONS

qualifications:
  - Minimality conceptually argued, empirically unproven (P5-3 required)
  - Semantic Anchor minimum form unresolved (OP-P5-3)
  - Backward anchor (history) D/R status unresolved (OP-P5-5)
  - Continuation acceptance rule layer unresolved (OP-P5-4)

carrier_confusion_detected: NONE
overclaim_detected: NONE
evidence_level_appropriate: YES
```
