# Local Execution → Candidate Information → Fresh Execution Charter

Date: 2026-10-04  
Status: `REGISTERED / OBSERVATIONAL CHARTER / EXECUTION NOT AUTHORIZED`

## 1. Purpose and terminology boundary

The next experiment is not Cloud adaptation and not a new Execution State
mechanism. It is a minimal observational probe:

```text
Information₀
      ↓
Local MLX Execution A through SimiGo
      ↓
observe real work residue
      ↓
observer selects Candidate Information
      ↓
existing InformationCore.store()
      ↓
Stored Information identity
      ↓
fresh Execution B
      ↓
does B use Stored Information without A's context?
```

`Information₁` is not an experimental premise. It may be used only as a
post-run designation if Stored Information actually exists and a later
reading judges it to be the first formed successor to Information₀.

Three terms are deliberately separated:

```text
Residue
= everything naturally left by Execution A:
  transcript, tool calls, tool results, final answer,
  trace, cache events, opened sources, intermediate files.

Candidate Information
= residue selected by the observer as possibly satisfying
  the existing Information formation boundary.

Stored Information
= Candidate Information only after an existing
  InformationCore.store() succeeds and returns an identity.
```

No tool result, final answer, transcript, trace, or cache event is assumed
to be Information merely because it exists.

## 2. Causal scope correction

Three earlier observations must remain scoped:

```text
Qinshen Execution 001 / 002
= external Agent + Information Space
= valid evidence that external work residue was not stored in InformationCore

Local MLX smoke
= SimiGo HTTPServer → NativeMLX
= valid evidence of observable inference lifecycle and cache

Cloud ZAI smoke
= SimiGo HTTPServer → RemoteOpenAIBackend → external inference
= valid evidence that Cloud can forward and call tools
```

Cloud did not expose NativeMLX prefill, decode, KV/cache, checkpoint, fork,
or resource-control substrate. Therefore Cloud's unchanged Information
database is not evidence about a Local Execution → Information break.
Likewise, Qinshen Execution 001/002 did not traverse SimiGo's local
inference Execution State.

The untested path is precisely:

```text
Local SimiGo-controlled inference execution
      ↓
work residue
      ↓
existing InformationCore
      ↓
fresh Execution
```

## 3. Required backend

Execution A and B must use:

```text
SimiGo HTTPServer → NativeMLX
```

The route fix must be present:

```text
SimiGo source commit = 82b57f6
fix                  = guard both Chat Completions remote patterns
```

Cloud is out of scope for this experiment.

## 3.1 Research-layer separation

Three questions must remain separate.

### Level 1 — Technical route

The only question authorized for this charter is:

```text
When a controllable Local Execution State and a persistent
Information Space are combined, does their intersection enable
continuation capability that neither provides alone?
```

Current evidence establishes only the two separate halves:

```text
Local MLX through SimiGo can expose inference execution state.
InformationCore can persist and fetch explicitly identified Information.
```

It does not yet establish their intersection.

### Level 2 — Cloud provider adoption

Whether a cloud provider can adopt this route is a separate boundary
question. The current ZAI-compatible API exposes request/response and tool
calling, but not the local inference substrate. Therefore it cannot be used
to refute Level 1.

Future cloud adoption would require a provider boundary that exposes enough
Execution State control or an explicitly agreed hybrid substrate. That is
not part of this charter.

### Level 3 — Product and commercial concerns

Questions such as Information ownership, privacy, tenant isolation, trust,
migration, compliance, provider selection, and cost are deferred. They may
later become deployment constraints, but they must not be used to reject or
reshape the Level 1 technical experiment.

## 4. InformationCore boundary

Use only the existing frozen boundary:

```bash
t4ctl store --db <path> --file <path>
t4ctl fetch --db <path> --identity <id> --out <path>
```

Equivalent direct use of `InformationCore.store()` / `fetch(by:)` is allowed,
but no new method, schema, query API, embedding, summary, relation, or bridge
may be added.

The current public InformationCore surface has no search, list, ranking, or
semantic retrieval. Therefore this first closure tests **explicit identity
inheritance**, not autonomous finding. Any inability to discover Information
without an identity must be recorded as a separate retrieval gap.

## 4.1 Capability / observer / missing-capability boundary

The experiment must distinguish three disjoint sets.

### Existing capabilities

```text
SimiGo HTTPServer → NativeMLX execution;
Agent / tool loop through Chat Completions;
Runtime lifecycle and cache observation;
tool-call and tool-result governance;
external harness ownership of transcript and tool results;
InformationCore.store() for already-formed Information;
InformationCore.fetch(by identity);
immutable first-write-wins SQLite persistence;
ExecutionScope formation and observation in fresh processes.
```

### Observer actions

These are not Runtime capabilities. They may be used only after Execution A
stops and only if separately authorized.

```text
preserve Execution A raw artifacts;
inventory natural residue;
select Candidate Information without inventing content;
package Candidate Information for t4ctl.store();
invoke existing InformationCore.store();
record the resulting Stored Information identity;
give only that identity to Execution B;
record Execution B fetches and behavior.
```

The observer may select and package residue, but must not invent, summarize
into a new schema, add semantics, or silently convert Runtime state into
Information.

### Missing native capabilities

These capabilities are not currently present and must not be assumed:

```text
Execution or Runtime emits semantic Information to InformationCore;
harness naturally forms Information from tool results or final answers;
Information identity is discoverable without an external identity;
InformationCore supports search, list, ranking, or query;
fresh Agent naturally sees relevant Information;
ExecutionCache or ExecutionStateGraph is itself an Information Store.
```

Therefore the present charter can test only an **observer-mediated identity
closure**. It cannot test a native
`Execution → InformationCore → Agent` closure until such a path is later
observed or deliberately defined.

## 5. Execution A

Execution A must use the Qinshen real task and Local MLX through SimiGo.

Required conditions:

```text
fresh context;
start from a copy of Information₀;
Local MLX via SimiGo HTTPServer;
real physical sources may be read;
read-only access to Information₀ is allowed;
no write to the sealed Information₀;
no automatic Information write-back;
no preselected Information schema.
```

Execution A must produce a real work product. Preserve the complete raw
result, tool calls, tool results, queries, opened sources, uncertainties,
anomalies, unresolved questions, Runtime lifecycle, and cache observations.

After Execution A stops, the observer must inspect the actual residue and ask:

```text
If this residue disappeared, what would Execution B have to redo?
```

The observer may then select actual produced material and store it through
the existing `t4ctl store` boundary. The observer must record why each stored
item was selected, its Stored Information identity, and what was deliberately
not stored.

## 6. Execution B

Execution B must be a fresh context.

It may receive only:

```text
the next-phase Qinshen task;
the Stored Information identity;
a fetch tool backed by existing InformationCore;
necessary read-only tools for the next-phase work.
```

It must not receive:

```text
Execution A's prompt;
Execution A's transcript;
Execution A's final answer;
Execution A's summary;
selected source paths or extracted facts outside Stored Information;
the observer's selection rationale.
```

The B task must actually require A's work product. A superficial request such
as “read the file you just read” is invalid.

## 7. Gates

### G-A — Execution A → Candidate Information → Store

Pass requires:

```text
Local MLX execution through SimiGo;
real Qinshen work product;
actual residue identified after execution;
stored through existing InformationCore without schema change;
Stored Information identity recorded;
raw residue and selection rationale preserved.
```

Read this gate as observer-mediated. Passing it does not prove that SimiGo
Execution natively produced Information.

### G-B — Stored Information → Fresh Execution

Pass requires:

```text
fresh B context;
fetch of the explicit Stored Information identity through existing boundary;
B demonstrably uses fetched content;
B completes the next-phase task without A's transcript or summary;
all fetch records and output artifacts preserved.
```

If B cannot proceed, preserve:

```text
what was stored;
what B fetched;
what B still lacked;
whether B reopened raw sources;
which existing boundary first blocked continuation.
```

### G-C — Relation observation only

Do not invoke RelationCore preemptively. Record a relation need only if B's
actual behavior shows that it has relevant Information but cannot express or
use the connection between them.

## 8. Non-goals

```text
No Cloud Execution State work.
No third backend.
No new Information schema.
No automatic write-back.
No ExecutionInformationBridge.
No summary, embedding, vector store, or knowledge graph.
No RelationCore integration.
No PALACE, MemPalace, IPAC, Contract, or Gate change.
No rewrite of sealed Information₀.
```

## 9. Intended evidence

The minimum evidence unit is:

```text
LOCAL_EXECUTION_INFORMATION_CLOSURE_EVIDENCE
```

It must contain:

```text
Information₀ copy hash;
Execution A request/response artifacts;
Local Runtime lifecycle and cache trace;
Execution A raw work product;
post-A residue inventory;
selection rationale;
Stored Information identity and content hash;
t4ctl store/fetch records;
Execution B fresh-context proof;
Execution B fetch and output artifacts;
before/after StateGraph and Information database hashes;
explicit statement of which gate passed or failed.
```

## 10. Authorization state

```text
Charter                    = REGISTERED
Local MLX availability     = confirmed separately
Execution A                = NOT AUTHORIZED
Observer residue selection = NOT AUTHORIZED
InformationCore store      = NOT AUTHORIZED
Execution B                = NOT AUTHORIZED
Schema / Contract change   = NOT AUTHORIZED
RelationCore use           = NOT AUTHORIZED
```
