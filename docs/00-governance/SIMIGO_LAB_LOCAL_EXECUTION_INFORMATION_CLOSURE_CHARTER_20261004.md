# Local Execution → Candidate Information → Fresh Execution Charter

Date: 2026-10-04  
Status: `REGISTERED / HUMAN REVIEW PASSED WITH CACHE-ISOLATION AMENDMENT / TASK CARRIER NOT DEFINED / EXECUTION NOT AUTHORIZED`

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

## 4.2 Observation and interpretation table

Before execution, the only permitted reading plan is to separate what is
observed from what is concluded.

| Phase | Observed object | Record only |
|---|---|---|
| A | Residue | What Execution A naturally left. |
| Candidate | Observer action | What was selected, why it can fit the existing Information boundary, and what was not selected. |
| Store | InformationCore | Whether `store()` succeeded and what identity returned. |
| B | Fresh SimiGo + NativeMLX | Whether B fetched the explicit identity and what was fetched. |
| B-use | Agent behavior | Whether B actually used the fetched content. |
| Outcome | Task behavior | Whether an observable continuation difference appeared. |

These boundaries must remain separate:

```text
B fetched successfully
      ≠
B used the Information
      ≠
B obtained a continuation effect
```

No phase may be reported as a later phase without direct behavioral evidence.

## 4.3 Experimental invariants

The following invariants must remain true from Execution A through Execution B.

```text
Backend                     = SimiGo HTTPServer → NativeMLX
Execution B context         = fresh
Information boundary        = existing InformationCore only
Information schema          = unchanged
RelationCore                = not invoked
RuntimeMemory               = not added
Search / list / query       = absent
Automatic Information formation = absent
Residue mutation            = forbidden
A → B transcript transfer   = forbidden
A → B summary transfer      = forbidden
A → B result transfer       = forbidden
Stored identity provenance  = real successful InformationCore.store()
```

A → B NativeMLX execution-state transfer is also forbidden:

```text
A → B KV/cache reuse              = forbidden
A → B prefix-pool reuse           = forbidden
A → B session-state reuse         = forbidden
A → B backend-process inheritance = forbidden
```

Unique Agent/Session/Branch headers are not sufficient to establish B
freshness. The same NativeMLX process may retain or reuse prefix state even
when HTTP headers differ.

Between Execution A and Execution B, the runner must isolate inference state
by one of these observable methods:

```text
stop and reload NativeMLX;
use a fresh isolated backend process;
or clear/evict all relevant cache and prefix-pool entries with recorded
before/after evidence.
```

The B trace must show a cold execution path with no inherited A cache bind,
prefix hit, checkpoint load, or execution-state reuse. Stored Information is
the only permitted cross-execution carrier in this charter.

## 4.4 Human charter review — 2026-10-04

Review result:

```text
PASSED WITH CACHE-ISOLATION AMENDMENT
```

Reviewed items:

```text
1. Experiment object locked.
   A and B must use SimiGo HTTPServer → NativeMLX.
   The external harness may execute tools but must not perform model
   inference. Cloud is forbidden.

2. Causal chain must have independent evidence.
   Residue → Candidate → store → identity → fresh B → fetch → use →
   outcome may not be inferred across stages.

3. Observer remains observer only.
   No summary, rewrite, added facts, new schema, Agent decision replacement,
   or promotion of Runtime trace/cache into Information.

4. B freshness includes Runtime state, not only HTTP freshness.
   New Agent/Session/Branch IDs are insufficient.
   A transcript, summary, result, hidden harness state, and inherited
   NativeMLX cache/prefix state are all forbidden.

5. Interpretation thresholds remain strict.
   fetch ≠ use ≠ continuation ≠ continuation gain.
```

The review adds no mechanism. It only strengthens isolation.

The observer may select and package already-produced Residue, but must not
rewrite, interpret into a new schema, summarize, or invent content. If any
invariant cannot be maintained, the run must stop and be classified as an
invariant violation rather than a closure failure.

## 5. Execution A

The first closure run must use a **Minimal Observable Local Task Carrier**,
not the full Qinshen task.

The carrier is valid only if:

```text
it operates on a small, finite set of real local files;
every source file is hashed before Execution A;
Execution A genuinely requires a read-only tool to inspect those files;
Execution A naturally leaves a nonempty work product or decision residue;
Execution B has a next-phase task that objectively requires that residue;
all requests, tool calls, tool results, and file reads are observable;
the task is small enough for complete artifact preservation.
```

The task must not be a superficial “read the file you just read” probe. It
must produce actual work residue whose loss would force B to redo inspection
or derivation.

The task carrier is still not defined. After separate authorization to define
it, the task should be derived backward from the existing SimiGo Agent/tool
surface:

```text
what SimiGo + NativeMLX can already observe;
what an external harness can already execute;
what small real local files can create genuine work pressure;
what next-phase result objectively depends on A's residue.
```

Do not invent a task solely to make Information formation look successful.

Qinshen remains the later complex real-task carrier. It is intentionally
deferred until this minimal observable closure has been tested.

Required conditions:

```text
fresh context;
start from a copy of Information₀;
Local MLX via SimiGo HTTPServer;
real local sources may be read;
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
the next-phase Minimal Observable Local Task;
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
real Minimal Observable Local Task work product;
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

## 7.1 Separable readings and failure isolation

The probe must not report a single undifferentiated pass/fail. Each boundary
below may fail independently and must be preserved as a separate reading.

```text
R-A0  No suitable residue
      Execution A produced no material that can form Candidate Information
      under the existing Information boundary.

R-A1  Representation failure
      Candidate Information existed as work residue, but the existing
      Information model could not represent it without schema change.

R-A2  Store failure
      Candidate Information was representable, but InformationCore.store()
      failed.

R-B0  Identity unavailability
      Stored Information existed, but B did not receive or use its identity.
      This is expected unless the observer explicitly supplies it.

R-B1  Fetch failure
      B received the identity but fetch failed or returned absence.

R-B2  Fetch without use
      B fetched Stored Information but did not use its content in work.

R-B3  Use without continuation gain
      B used Stored Information and completed or attempted the task, but no
      observable continuation advantage was recorded.

R-B4  Continuation evidence
      B used Stored Information and avoided redoing part of A's work,
      or otherwise demonstrated a qualitative continuation effect.
```

For this minimal charter, continuation gain is observational, not a
performance benchmark. Record only directly observable facts:

```text
whether B fetched Stored Information;
whether B quoted, transformed, or relied on its content;
whether B reopened raw sources already covered by Stored Information;
whether B repeated A's queries or calculations;
whether B completed, partially completed, or blocked;
why any reopened or repeated action was necessary.
```

If no control run exists, `continuation gain = NOT ASSESSED`; do not infer a
quantitative speedup or quality improvement.

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
Charter                    = REGISTERED / HUMAN REVIEW PASSED
Local MLX availability     = confirmed separately
Task carrier               = NOT DEFINED
Execution A                = NOT AUTHORIZED
Observer residue selection = NOT AUTHORIZED
InformationCore store      = NOT AUTHORIZED
Execution B                = NOT AUTHORIZED
Schema / Contract change   = NOT AUTHORIZED
RelationCore use           = NOT AUTHORIZED
```
