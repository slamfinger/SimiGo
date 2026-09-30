# SimiGo-Lab — Execution State Reuse Research Master Record

Date: 2026-09-30
Status: RESEARCH PROGRAM / PAPER-GRADE EVIDENCE CONTROL
Track: Execution State Reuse
Branch: research/es-reuse-program-20260930

## 1. Research intent

This track asks whether an Execution State can outlive a particular Physical Representation and later be re-materialized, rebound, and reused for continued computation.

Primary question:

> When Physical Representation disappears, can an existing Execution State still be identified, recovered, re-materialized, and continued without complete history replay and full cold prefill?

This is a hypothesis, not an established result.

## 2. Why this track is separate from PALACE-1

PALACE-1 established an observed lifecycle distinction between durable semantic information and replaceable physical acceleration representations. It is SEALED/PARKED.

Execution State Reuse tested the deeper premise that may make PALACE's future storage/retrieval/reuse loop meaningful.

PALACE is therefore a downstream research/systemization track, not a premise of ES-R1.

## 3. Research sequence

P0 ES-R1 — Representation Loss → Execution State Reuse
  Status: SEALED
  Verdict: R1-B FINAL / CONTRACT-ONLY
  Finding: Execution State five-field shape exists as an architectural abstraction, but no independently durable runtime State exists that can serve as a Representation re-materialization input.

P1 ES-D1 — Architecture State → Durable Computational State
  Status: OPEN / NEXT GATE
  Question: Under what empirically observable conditions does the architectural State abstraction become an independently held, durable computational state?
  Immediate phase: F — Lifecycle/Event Census
  C-4 remains permanently locked for ES-R1.

P2 ES-R2 — Backend Takeover
  Status: BLOCKED
  Prerequisite: a justified durable computational State semantics, or an explicitly reopened research basis.

P3 ES-R3 — State Persistence / Lifetime
  Status: DEFERRED
  Note: ES-D1 now precedes this line; persistence cannot be studied as an independent State property before an independent State carrier is established.

P4 ES-R4 — State Retrieval
  Status: DEFERRED
  Prerequisite: persistence semantics established.

P5 ES-R5 — Rematerialization Economics
  Status: DEFERRED
  Prerequisite: semantic reuse established.

PALACE follow-on:
  Storage → Retrieval → State Reuse → Representation Materialization → Continued Execution → State update

Knowledge-base and authority/security research remain queued and are not to be run in parallel with this core sequence unless explicitly reopened.

## 4. ES-R1 sealed evidence

### Established
- Phase A/B/C-0/C-1/C-3: PASS.
- PB1 deterministic continuation baseline: CONFIRMED.
- Representation-loss boundary: established on disposable fixture.
- Exhaustive audited Representation production/reception entrances: no State-without-History consumer found.
- First missing seam: State identity/position/continuation → new Representation materialization.
- Gate D: D-B CONTRACT-ONLY.
- Durable layer retains identity/addressing and history semantic payload.
- Durable independent position, continuation, and lineage authorities were not found.

### Not established
- R1-A.
- Representation-independent semantic reuse.
- Universal statement that cold prefill is computationally necessary.
- Any new State schema or implementation.

## 5. Evidence hierarchy

L0 Raw Evidence
- immutable raw test output
- execution traces
- environment/version information
- artifact hashes
- timestamps
- exact failure messages
- benchmark inputs/outputs

L1 Research Record
- experiment design
- actual procedure
- deviations
- anomalies
- first missing seam
- result

L2 Evidence Synthesis
- observed facts
- bounded inferences
- unresolved questions
- prohibited conclusions

L3 Paper Material
- figures
- tables
- narrative
- claims
- related-work comparisons

L0 must never be rewritten to make later interpretation cleaner.

## 6. Scientific discipline

1. Do not infer semantic necessity from absence of an API.
2. Do not create a new State object/schema merely to make an experiment succeed.
3. Do not use full-history cold prefill as a disguised State-Reuse path.
4. Do not mutate the real durable store.
5. Every destructive test uses a disposable copy/fixture.
6. Record the first concrete missing seam on failure.
7. Preserve negative results.
8. Do not measure performance before semantic reuse is established.
9. Distinguish observed code fact, runtime observation, inference, and hypothesis.
10. No public publication of sensitive recovery recipes, storage paths, field combinations, isolation bypasses, or procedures that could expose another person's state.
11. Do not retrofit an existing field merely to make it qualify as State.
12. Distinguish “State can be described,” “State can be reconstructed,” and “State is independently held.”

## 7. ES-D1 immediate gate

AUTHORIZED:
- Phase F lifecycle/event census.
- Read-only source-of-truth tracing.
- Existing durable artifact inspection.
- Disposable-fixture observation where no production state is modified.

NOT AUTHORIZED:
- production code changes.
- State object/schema creation.
- new persistence mechanism.
- State → Representation implementation.
- reopening ES-R1 C-4.
- performance measurement.

Exit:
> Stop after Phase F and submit the candidate-carrier inventory plus the first concrete authority/lifetime ambiguity. The research architect decides whether Phase G is authorized.

## 8. Paper-quality evidence

For future State research preserve:
- State identity, if independently carried
- lineage authority
- logical position authority
- continuation authority
- Representation identity/type
- runtime binding identity
- model/backend identity
- whether full history was read
- whether full prefill occurred
- token/work processed during rematerialization
- materialization/rebind trace
- continuation result
- exact failure boundary, if any
- artifact hashes and environment fingerprint
- repetition count

The original ES-R1 paper claim remains a hypothesis:

> Execution State lifecycle can be longer than Physical Representation lifecycle, enabling representation-independent reuse.

Do not use this as a result unless later evidence earns it.
