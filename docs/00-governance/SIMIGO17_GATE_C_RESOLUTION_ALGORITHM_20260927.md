# Gate C — Deterministic Resolution Algorithm & Mapping — Definition Draft

**Date**: 2026-09-27 · **Status**: DEFINITION_DRAFT / AWAITING_REVIEW
(no implementation code)
**Adopted rulings**: RR contract PASSED; `resolve()` = pure observation,
never materialization (Gate C forbidden zone); artifact-state judgment
(NOT pool registration): `Pool registration ≠ Representation existence`;
canonical key direction: `ExecutionID → Binding → AgentExecutionKey`,
never reverse (a reverse index requires its own explicit ruling).

---

## C.1 The three registries and the resolver

```text
BindingRegistry      semantic owner of bindings (canonical key:
                     ExecutionID; NO AgentExecutionKey reverse index)
  query: currentBinding(E) -> Binding?          [B-R2: ≤1 active, max gen]
SessionRegistry      runtime truth (owned by the runtime, not the
                     coordinator's identity semantics)
  query: liveSession(AgentExecutionKey) -> LiveSession?
RepresentationResolver
  query: artifactAvailable(RepresentationRef) -> Bool
  = verifiable ARTIFACT state: snapshot file exists AND sidecar decodes
    AND claims self-consistent — read-only checks ONLY.
    NOT pool registration; NOT pool.admit (admit mutates LRU recency —
    it belongs to the materialize DECISION, forbidden inside resolve).
```

## C.2 The deterministic algorithm (total, read-only)

```text
resolve(E: ExecutionID) -> ResolutionState:
  b = BindingRegistry.currentBinding(E)
  if b == nil                                   return UNBOUND
  s = SessionRegistry.liveSession(b.runtimeAddress)
  if s != nil && s.holdsMaterialization(b.ref)  return ATTACHED_LIVE
  if RepresentationResolver.available(b.ref)    return REATTACHABLE
  return                                        REMATERIALIZATION_REQUIRED
```

`s.holdsMaterialization(b.ref)`: the live session demonstrably embodies
the bound snapshot (v1: the session's recorded current binding —
generation match; deeper KV introspection explicitly out of scope).

## C.3 Four states → existing machinery

```text
UNBOUND                       no Binding row        → fresh cold path
ATTACHED_LIVE                 sessions dict holds ManagedSession at
                              b.runtimeAddress (current generation)
                              → same-session reuse (cacheEff=1.00)
REATTACHABLE                  DiskPrefixArtifact present + sidecar
                              verifies (or checkpoint snapshot exists)
                              → poolBind / loadSessionCache
REMATERIALIZATION_REQUIRED    no artifact → mode=cold full prefill;
                              Binding stays active + recompute obligation
```

## C.4 Side-effect-free guarantees (RR-I2 enforcement)

```text
resolve may touch ONLY: BindingRegistry.read · SessionRegistry.read ·
file existence/attribute checks
resolve FORBIDDEN: pool.admit (LRU mutation) · pool.export ·
loadPromptCacheSnapshot (multi-GB materialization) · ChatSession
construction · any coordinator mutation
materialization is a separate DECISION taken after resolution —
`resolve ≠ materialize` enforced at the call-graph level
```

## C.5 Transition table (non-linear, contract owners per RR-I3)

```text
UNBOUND → (bound)                    materialize/bind operation
ATTACHED_LIVE → REATTACHABLE         runtime key gone / process exit
ATTACHED_LIVE → (runtime key CHANGED)  new Binding generation (B-R1),
                                       old row superseded
REATTACHABLE → ATTACHED_LIVE         materialize decision (load)
REATTACHABLE → REMATERIALIZATION_REQUIRED   artifact eviction (P2 onEvict)
REMATERIALIZATION_REQUIRED → REATTACHABLE   replay/regenerate/export
                                            (a NEW artifact appears —
                                            materialize decision)
any → UNBOUND                        ONLY explicit detach/discard op
```

## C.6 Registered hazards

```text
- live-session coverage check (s.holdsMaterialization) v1 = generation
  match on the recorded binding; token-chain introspection deferred
- pool.admit's recency mutation means resolution CANNOT reuse pool.admit
  as its availability probe — availability has its own read-only path
- AgentExecutionKey reverse index: absent; needed only if a future
  feature must find "all executions on this Key" — separate ruling
```
