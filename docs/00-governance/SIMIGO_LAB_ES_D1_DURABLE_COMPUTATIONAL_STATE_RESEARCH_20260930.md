# SimiGo-Lab — Architecture State → Durable Computational State Research Track

Date: 2026-09-30
Status: RESEARCH DESIGN / OPEN
Track ID: ES-D1
Parent line: Execution State Reuse
Predecessor: ES-R1 (SEALED — R1-B FINAL)
Branch: research/es-reuse-program-20260930

## 1. Why this track exists

ES-R1 established a bounded negative result:
- the Execution State five-field shape exists at the architecture/contract layer;
- durable storage preserves an identity/addressing carrier and semantic history;
- durable instances of independent position, continuation, and lineage were not found;
- no existing State → new Representation seam was found;
- therefore the current system does not contain an independently durable computational State that can serve as a re-materialization input.

The next research question is therefore not “how do we add a State object?”

It is:
> Under what empirically observable conditions does an architectural Execution State abstraction become an independently held, durable computational state?

This track must remain experimental. It must not assume that a particular schema, object, database record, or API is the answer.

## 2. Core question

### Q-DCS-1

Can the existing system expose, through an already-existing lifecycle event or carrier, a representation-independent computational state whose identity, position/continuation semantics, and lineage survive beyond the Physical Representation lifecycle?

If not, what exact information/lifecycle transition is missing?

## 3. Competing hypotheses

### H-D1 — Existing-state emergence
The current system already contains an event, record, or object whose lifecycle can be shown to outlive a Physical Representation and whose contents are sufficient to identify a computational continuation independently of that Representation.

### H-D2 — Contract-only remains true
The current system has no such independent carrier. Execution State remains an architectural abstraction assembled from transient/runtime observations and durable semantic history.

### H-D3 — Partial state emergence
Some independent state survives Representation loss, but one or more essential dimensions (for example lineage, position, continuation, or recovery authority) remain derived or representation-dependent.

### H-D4 — Inconclusive
The evidence cannot discriminate the above without introducing a new state mechanism.

## 4. Research discipline

1. No production State object.
2. No new production State schema.
3. No new production State → Representation API.
4. Do not retrofit existing metadata merely to make it qualify as State.
5. Do not infer “State exists” from the Contract shape alone.
6. Do not infer “State does not exist” merely because no obvious object is named State.
7. An authoritative carrier must be distinguished from a value that can be reconstructed from other information.
8. Lifetime independence must be demonstrated across the relevant lifecycle boundary.
9. Preserve negative and partial results.
10. Research fixtures may be used for observation only; they must not become a disguised production implementation.
11. Real durable data remains read-only; destructive work uses disposable copies.
12. Sensitive recovery mechanisms remain internal and are not published.

## 5. Research sequence

### Phase F — Lifecycle/Event Census

Inventory already-existing lifecycle events that could naturally create or preserve computational state:
- successful execution/turn commit
- fork
- checkpoint commit
- restore
- representation detach/release
- process restart
- session eviction
- backend binding changes
- lineage recording
- durable metadata commit

For each event, record:
- inputs
- outputs
- authoritative carrier
- lifecycle start/end
- dependency on Physical Representation
- dependency on History
- cross-process survival
- whether the value is authoritative or derived

No code changes.

### Phase G — Authority/Lifetime Discrimination

For every candidate carrier found in Phase F:
1. identify the source of truth;
2. remove/expire the Representation in a disposable fixture where safe;
3. observe whether the candidate remains;
4. restart the process where applicable;
5. determine whether the candidate can still identify the same computation without reconstructing it from the lost Representation.

The experiment is about existence and lifecycle, not reuse performance.

### Phase H — State Sufficiency Boundary

Only if Phase F/G finds a genuinely independent carrier:

Determine which state dimensions are actually sufficient to describe a continuation point.

Do not create a new State schema.

Instead, use existing carrier values and controlled perturbations to establish:
- necessary information
- redundant information
- derived information
- representation-dependent information
- history-dependent information

A successful result must show an experimentally observed distinction between “state carried independently” and “state reconstructed from history/representation.”

### Phase I — Formation Condition

If F–H produce evidence for independent state, derive the minimum observed lifecycle condition that caused it to exist.

If they do not, record the concrete barrier:

`semantic information exists → no independent authority/lifetime transition`

Do not solve the barrier in this track.

## 6. Gate definitions

### DCS-A — INDEPENDENT-DURABLE-STATE-OBSERVED

An existing carrier is experimentally shown to:
- survive beyond the relevant Representation lifecycle;
- retain an authoritative computational identity;
- retain or authoritatively reference continuation position;
- retain lineage/provenance where lineage is claimed;
- remain valid across process lifetime where persistence is claimed;
- not require the lost Representation as its source of truth.

### DCS-B — CONTRACT-ONLY-CONFIRMED

No existing carrier satisfies the above. The architecture abstraction remains real and useful, but no independent durable computational state exists in the current implementation.

### DCS-C — PARTIAL-STATE

Some dimensions have independent lifetime while others remain derived or representation-dependent.

### DCS-D — INCONCLUSIVE

Evidence cannot discriminate without introducing a new mechanism.

## 7. Important distinction

This track must keep three propositions separate:

A. “The system can describe a State.”

B. “The system stores information from which a State can be reconstructed.”

C. “The system holds an independent State.”

ES-R1 demonstrated evidence for A and B, but not C.

This track exists specifically to investigate C.

## 8. Expected scientific value

A positive result would identify an already-existing transition from transient computation to durable computational state.

A negative result would sharpen the architectural finding:

> Current LLM runtimes may persist semantic history and physical representations without persisting the computational state between them as an independent asset.

Either result is publishable evidence only after independent replication and bounded claims.

No claim about universal AI inference architecture may be made from this track alone.

## 9. Immediate authorization

AUTHORIZED:
- Phase F lifecycle/event census
- read-only source-of-truth tracing
- existing durable artifact inspection
- disposable-fixture observation where no production state is modified

NOT AUTHORIZED:
- production code changes
- State object/schema creation
- new persistence mechanism
- State → Representation implementation
- C-4 reopening
- performance measurement

Exit condition:

> Stop after Phase F and submit the candidate-carrier inventory plus the first concrete authority/lifetime ambiguity. The research architect decides whether Phase G is authorized.