# P5-2-ER Reviewer-2: Security / Capability Boundary Review

日期：2026-10-01  
Role：Security / Capability Boundary Reviewer  
审查对象：P5-2 Draft §8 Capability Risk + P5-2-0 dependency map  
纪律：不预设"Execution State 一定危险"；只审查"如果该能力存在，边界在哪里"

---

## B1: State Possession → Capability

```yaml
question: >
  Does possessing an Execution State equal possessing the capability
  to continue the computation it represents?

analysis:
  scenario_A_no_just_material:
    description: >
      State is only recovery material — you still need the original
      model, the runtime, the correct configuration, and valid identity
      to resume computation. Possession alone is insufficient.
    evidence: >
      P5-1 showed that even with the KV carrier intact, continuation
      failed because the closure (identity + position + anchor +
      continuation) was broken. The carrier alone does not confer
      capability.

  scenario_B_partial_needs_identity:
    description: >
      State + identity credentials (model access, config match,
      storage key) = continuation capability. Without the identity
      credentials, the state is inert.
    evidence: >
      performLoad checks modelId, checkpointGeneration, cacheSHA256.
      generateUsingChatSession checks kvFingerprint and isPrefix.
      Failure of any → throw or silent degradation. Identity is the
      gate that turns material into capability.

  scenario_C_yes_full_capability:
    description: >
      If an adversary has the complete closure (State + identity +
      compatible backend), they CAN resume computation without the
      original user's involvement.
    evidence: >
      P4 proved the topology works. The continuation relation defines
      what CAN happen next. Having the complete closure means having
      the future computation semantics.

verdict: PARTIAL
possession_equals_capability: "conditionally — requires identity + compatible backend + closure completeness"
capability_boundary: >
  Possession of the State alone (KV bytes) is NOT sufficient.
  Possession of the complete closure (State + identity + anchor +
  continuation contract) on a compatible backend IS sufficient for
  continuation capability. The security boundary is therefore the
  closure completeness, not the data size.
risk_assessment: >
  KV tensors without identity/model/config are large binary blobs —
  low direct risk. KV tensors WITH their metadata sidecar (which
  carries modelId, kvFingerprint, checkpointGeneration, history) are
  a capability package. The .meta.json file is the security-sensitive
  component, not the .safetensors file alone.
```

---

## B2: State Leakage — What Actually Leaks?

```yaml
question: >
  If Execution State is leaked, what is lost?

layers:
  user_privacy:
    content: conversation history text
    location: meta.json → SessionCacheMetadata.history
    risk: HIGH — full conversation transcript in plaintext JSON
    note: >
      The history array in meta.json contains the complete conversation
      in JSONValue format. This is user-generated content, directly
      readable. Leakage of meta.json alone (without KV) still exposes
      the conversation.

  model_state:
    content: KV cache tensors (attention keys/values per layer)
    location: safetensors binary file
    risk: MEDIUM-LOW — not directly readable as text, but
      reconstruction attacks exist in literature
    note: >
      KV cache can potentially be inverted to recover approximate
      token representations (published attacks on LLM KV extraction).
      Risk increases with model capability and cache length.

  tool_authority:
    content: tool call history, pending tool states
    location: meta.json → history[].tool_calls
    risk: MEDIUM — reveals what tools the session used and how,
      but does NOT confer tool execution capability by itself
    note: >
      Tool authority is enforced by the runtime, not by the state.
      The state records what tools were called, but calling tools
      requires an active runtime with tool configuration.

  environment_binding:
    content: storageKey (agentId/sessionId/branchId), modelId,
      kvFingerprint
    location: meta.json header fields
    risk: LOW — reveals system architecture but not credentials
    note: >
      Knowing the storage key structure does not grant access.
      It informs an attacker about the system's identity scheme.

verdict:
  highest_risk_item: meta.json (user privacy — full conversation text)
  capability_leak_risk: >
    The PAIR (meta.json + safetensors) leaks both the conversation
    content AND the computation state. Individually, meta.json is a
    privacy leak; the pair is a capability leak.
  mitigation_priority: >
    1. Encrypt meta.json (privacy — highest urgency)
    2. Encrypt or access-control safetensors (capability — second)
    3. Separate identity credentials from state files (reduces
       possession→capability shortcut)
```

---

## B3: State Delegation

```yaml
question: >
  If Agent A's Execution State is transferred to Agent B, what does
  B inherit?

distinction_required:
  context_transfer: >
    B receives the conversation history and computation state.
    B can continue the conversation as if it were A (semantic continuity).
    This is a CONTEXT transfer.

  authority_transfer: >
    B gains the ability to execute tool calls, access resources,
    and take actions that A's session was authorized for.
    This is an AUTHORITY transfer.

  key_difference: >
    Context transfer is about knowledge/state.
    Authority transfer is about permission/capability.
    Current MLX implementation: the state carries context but NOT
    authority. Authority is re-established by the runtime's tool
    configuration when B's session starts.

current_implementation_status:
  context_transfer: YES — loading the checkpoint gives B the full
    conversation history and KV state. B continues from A's position.
  authority_transfer: NO — tool permissions are configured per-session
    at the runtime level, not persisted in the checkpoint. B must be
    independently authorized.
  hidden_assumptions: PARTIAL — the KV state encodes assumptions from
    A's context (e.g., "we were discussing X"). B may act on these
    assumptions without knowing their origin.

enterprise_risk:
  scenario: >
    Employee A's session is transferred to Employee B (or to a
    service account). B continues the conversation.
  risk: >
    B inherits A's conversational context including potentially
    sensitive information A shared. B does NOT inherit A's file
    access or API permissions, but B's outputs will be shaped by
    A's context. This creates an implicit information channel.
  mitigation: >
    Require explicit consent for state transfer. Log the transfer
    with identity provenance. Consider context sanitization for
    cross-user delegation.

verdict:
  delegation_semantics: "context YES / authority NO / assumptions PARTIAL"
  consent_required: YES (for cross-user state transfer)
  audit_trail_required: YES
  authority_isolation: CURRENTLY SAFE (runtime enforces, state does not carry)
```

---

## B4: State Revocation

```yaml
question: >
  How can an Execution State be invalidated as a computation
  authorization?

current_reality:
  mechanism: NONE — no revocation exists in the current implementation
  reason: >
    Checkpoints are plain files. Possession of the files + access to
    a compatible runtime = computation capability. There is no
    certificate, token, or key that can be revoked independently.

challenge:
  if_state_is_capability:
    then: revocation must prevent computation resumption
    not: merely delete the data (possession may already exist)

proposed_approaches:
  identity_bound_revocation:
    description: >
      Bind the checkpoint to a revocable credential (certificate or
      key). Continuation requires the credential; revoking the
      credential prevents future resumption even if files are copied.
    feasibility: >
      Requires changing the checkpoint format to include a
      cryptographic proof. The current checkpointGeneration UUID
      is not a credential — it is a label.
    cost: MEDIUM — format change + key management infrastructure.

  model_binding_revocation:
    description: >
      The KV cache is model-specific. Revoking access to the model
      weights makes the state unusable. But model weights are rarely
      revoked in practice.
    feasibility: LOW — does not address insider or copy threats.

  lineage_tombstone:
    description: >
      Contract v1.0 SC-2 already includes tombstone closure. A
      tombstone at the coordinator level can mark a lineage as
      discarded. But tombstones are stored in the coordinator —
      if an attacker has the checkpoint files but not the coordinator,
      tombstones are bypassed.
    feasibility: PARTIAL — works within the trusted coordinator,
      does not protect against file-level exfiltration.

verdict:
  revocation_mechanism: DOES NOT EXIST — requires design
  revocation_scope: undefined (no mechanism to define scope)
  revocation_proof: impossible without cryptographic binding
  urgency: >
    MEDIUM for current lab/research context.
    HIGH for any production or multi-user deployment.
    The absence of revocation means that once a checkpoint is
    shared/copied, the computation capability it carries cannot
    be recalled.
```

---

## Reviewer-2 Summary

```yaml
security_review_summary:
  capability_level: EXECUTION-LEVEL (beyond data access, below authority escalation)
  risk_boundary: >
    The closure (State + identity + anchor + continuation) on a
    compatible backend = capability to resume computation.
    The meta.json sidecar is the highest-value security target
    (contains both privacy content and identity credentials).
  revocation_feasible: "not currently — requires cryptographic binding design"
  delegation_semantics: "context transfers, authority does not, assumptions partially transfer"
  possession_equals_capability: "conditionally — requires closure completeness + backend access"

  open_security_questions:
    - Can KV tensors be used to reconstruct conversation content?
    - Should checkpoint format require a revocable credential?
    - Is context sanitization feasible for cross-user delegation?
    - What is the minimum identity binding needed to prevent
      unauthorized continuation?

verdict: PASS-WITH-SECURITY-CONDITIONS

conditions:
  - meta.json must be treated as sensitive (contains plaintext conversation)
  - State transfer between users requires explicit consent + audit trail
  - Revocation mechanism must be designed before production use
  - Security boundary review must be repeated when Execution State
    becomes portable across backends (P6)
```
