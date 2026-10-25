# Gate A — RepresentationRef Identity Contract — Definition

**Date**: 2026-09-27 · **Status**: PASSED (reviewer, with two
definition-level corrections applied — see §7; this document is FINAL
for Gate A)
**Ruling being executed**: IDENT-1 gate ③ opened; order is
`RepresentationRef identity contract → Binding contract → runtime
resolution → FORK-3`; **no implementation code this gate**.
**Red line**: `Execution identity ≠ physical representation identity`;
`RepresentationRef` contains no ExecutionID.

---

## 0. The three identities (layered, never merged)

```text
ExecutionID         "我是谁"          logical identity of an Execution State
AgentExecutionKey   "运行时在哪里"     runtime addressing of Session/Branch
RepresentationRef   "绑定哪份表示"     content/physical identity of a Representation
```

Chain: `ExecutionID —binding→ AgentExecutionKey —owns/materializes→
RepresentationRef → Physical Representation`. Neither
`ExecutionID == AgentExecutionKey` nor `ExecutionID == RepresentationRef`
is permitted. Today's code has ② working, ① duplicated (two ExecutionID
types), ③④⑦ absent (IDENT-1 closure list, §4).

## 1. RepresentationRef — field-by-field ruling

The question per item: **identity** (participates in equality) /
**metadata** (carried, never compared) / **compatibility check**
(verified at use time, not part of the hash).

| item | ruling | rationale (code facts) |
|---|---|---|
| `kind` | **IDENTITY** | discriminates semantics: `prefixSnapshot` vs `checkpoint` vs `residentKV` vs (future) `sharedCOW`. A prefix snapshot covering [0..T] and a full checkpoint are different representations even over identical content. Today: implicit (pool = prefixSnapshot only) — becomes explicit. |
| `modelIdentity` | **IDENTITY** | today `modelName(from: path)` (checkpoint dir). Conservative by construction: dtype/quantization/architecture differences = different dirs = different identity. No finer model-internal granularity for v1. |
| `kvLayoutIdentity` | **IDENTITY** | today `kvFingerprint` (kvSettings description → kvCachePlan). Quantized/rotating class changes are inside kvSettings → covered. Guards Arrow-5 against cross-plan seeding. |
| `renderIdentity` | **IDENTITY** | v1: ONE inseparable field = template + thinking semantics + tokenizer/render version. Rationale: the goal is a stable Representation identity now, not a render contract decomposed into independently evolving components. **Invariant added (reviewer)**: renderIdentity MUST be generated canonically and deterministically — today's `\|think:` string-join hack must never be exposed as the RepresentationRef format; migration = render semantics → canonical renderIdentity → Ref, so the hack can disappear without changing Ref semantics. |
| `contentHash` | **IDENTITY (core)** | chain hash over the address space's content stream (token ids for token-level; message stream for message-level). THE discriminator: same → same Ref, different → different Ref. |
| `boundLength` | **IDENTITY** | the Representation's covered **logical token-prefix boundary** — NOT a session position. "A snapshot covering [0..T]" ≠ one covering [0..T']; without length in identity, a Binding cannot tell what a Ref actually covers, and FORK-3's `Ref X @ 2048 → Child continues from 2048` has no anchor. Today: `tokenCount`. |
| `backendIdentity` | **IDENTITY (v1 constant)** | today always `mlx` (the daily pool has no GGUF artifacts). Field exists so a future second backend cannot collide. |
| ExecutionID | **FORBIDDEN** | red line. Parent and Child MUST be able to hold the same Ref (FORK-3 foundation). |
| artifact location | **metadata** | storage implementation; Ref ≠ concrete store (a Ref may be realized as pool snapshot, checkpoint, or future COW segment). |
| createdAt / byte size / lastUse / source session | **metadata** | lifecycle and telemetry inputs (pool LRU, GC) — never identity. |
| dtype / quantization details | **compatibility via modelIdentity** | same checkpoint ⇒ same dtype; re-quantization = different dir = different identity. No separate field for v1. |
| residency / memory pressure | **NEVER identity** | policy layer. Belongs to pool eviction + (FORK-3) binding constraints. |
| live context position of a session | **compatibility via Binding** | expressed by Binding.boundPosition == Ref.boundLength (invariant ⑦), NOT inside the Ref — the Ref is what many executions bind at possibly different positions. |

## 2. Invariants

```text
R-I1  determinism   identical (kind, modelIdentity, kvLayoutIdentity,
                    renderIdentity, contentHash, boundLength) ⇒
                    identical RepresentationRef — derivable, not minted
R-I2  discrimination  any difference in an identity field ⇒ different Ref
R-I3  no execution identity inside a Ref (sharing-safe: Parent ⊨ X,
                    Child ⊨ X simultaneously legal)
R-I4  storage independence   a Ref does not equal its artifact; one Ref
                    may be realized by different stores over time
R-I5  binding boundary consistency (⑦), FINAL WORDING:
                    Binding.boundPositionAtBind == Ref.boundLength
                    — bind-TIME coverage consistency only. It is
                    explicitly NOT `Execution.currentPosition ==
                    Ref.boundLength`: an Execution at currentPosition
                    3072 bound to Ref X @ 2048 is a LEGAL state (it
                    continued computing past the materialized base).
                    Ref.boundLength ≠ Execution.currentPosition — the
                    latter belongs to Binding/Execution State.
```

## 3. Gap table — migration assessment (wording per reviewer)

NOT "existing artifacts already carry four formal identity fields" —
consistent with F5, **RepresentationRef does not exist today**. The
accurate statement: existing artifacts (namespace + entry + kvFingerprint
+ tokenCount + hash) can be DERIVED INTO the new RepresentationRef; Gate
A's value is formalizing today's implicit identity conditions.

```text
today (pool namespace + entry)          contract field
  modelID                          →    modelIdentity            ✓
  kvFingerprint                    →    kvLayoutIdentity         ✓
  "|think:" suffix (product hack)  →    renderIdentity           promote
  (implicit: pool == snapshots)    →    kind                     promote
  tokenCount / messageStreamCount  →    boundLength              ✓
  PrefixChain.hash                 →    contentHash              ✓
  (absent)                         →    backendIdentity          add (constant "mlx")
  sidecar: createdAt/source/paths  →    metadata                 unchanged
```

Migration is small: the contract makes today's implicit identity
explicit; no stored artifact becomes invalid (fields are derivable from
existing claims).

## 4. IDENT-1 closure checklist (ruling's ⑦ items, current state)

```text
① Canonical Execution Identity        ⚠️  two ExecutionID types (F1)
② Runtime Address                     ✅  AgentExecutionKey
③ Representation Identity             ❌ → THIS gate defines it
④ Explicit Binding                    ❌ → Gate B (next)
⑤ Runtime Resolution                  ✅  existing addressing
⑥ Representation Resolution           ⚠️  pool artifact admission
⑦ Binding consistency                 ❌ → R-I5 (enforced at Gate B)
```

## 5. Gates C/D (registered, not open)

- **Gate C**: Binding Registry ≠ PrefixPool. Pool = representation
  lifecycle/discovery/reuse facility; Registry = Execution↔Ref
  relationship. Never merge.
- **Gate D**: `Pool eviction(X)` with bindings outstanding on X is NOT
  an unbind. Constraint (FORK-3 scope): binding exists ⇒ pool eviction
  either cannot invalidate the required physical representation, or the
  binding survives with `rematerialization required`. Decided by this
  contract family — never by LRU accident.

## 6. Review questions (Gate A specific)

1. `renderIdentity`: single field or split (template vs tokenizer
   version)? v1 proposes single.
2. `boundLength` inside identity vs as a Binding field — v1 keeps it in
   the Ref (a snapshot IS length-scoped) and REQUIRES Binding.
   boundPosition == Ref.boundLength (R-I5). Alternative considered and
   rejected: length-free Refs (would let one Ref serve many lengths —
   breaks snapshot determinism).
3. Backend constant: fold into modelIdentity instead of its own field?
   v1 keeps it separate (cross-backend collision impossibility by
   construction).

---

## 7. Reviewer verdict — 2026-09-27 — PASS

Two definition-level corrections applied above (renderIdentity
canonical-generation invariant; R-I5 bind-time wording + the legal
divergence example). backendIdentity as an independent field approved
(modelIdentity answers "which model"; backendIdentity answers "who
interprets/produces this representation" — same model across mlx/CUDA/
others must not be collapsed). Final field table as reviewed:

```text
RepresentationRef
  kind                 Identity
  modelIdentity        Identity
  kvLayoutIdentity     Identity
  renderIdentity       Identity   (canonical, deterministic generation)
  contentHash          Identity
  boundLength          Identity   (logical token-prefix boundary)
  backendIdentity      Identity
  ExecutionID          FORBIDDEN
  artifact location    Metadata
  timestamp/size/source Metadata
  residency            NEVER identity
  memory pressure      NEVER identity
  Execution position   Binding state

R-I1 Deterministic · R-I2 Distinguishable · R-I3 No Execution Identity ·
R-I4 Storage-independent · R-I5 Binding.boundPositionAtBind ==
Ref.boundLength (bind-time consistency)
```

Gate A CLOSED-PASSED → **Gate B OPEN: Binding contract**. Gate B first
principle (reviewer): **Binding is a RELATION, not an attribute of
RepresentationRef** — one Representation bound by multiple Execution
States must be type-level legal; `RepresentationRef { executionID }` is
forbidden.
