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

Execution State Reuse now tests the deeper premise that may make PALACE's future storage/retrieval/reuse loop meaningful.

PALACE is therefore a downstream research/systemization track, not a premise of ES-R1.

## 3. Research sequence

P0 ES-R1 — Representation Loss → Execution State Reuse
  Gate: R1-A / R1-B / R1-C / R1-D

P1 ES-R2 — Backend Takeover
  Prerequisite: ES-R1 sealed

P2 ES-R3 — State Persistence / Lifetime
  Prerequisite: ES-R1-A or a justified R1-B follow-up

P3 ES-R4 — State Retrieval
  Prerequisite: persistence semantics established

P4 ES-R5 — Rematerialization Economics
  Prerequisite: semantic reuse established

PALACE follow-on:
  Storage → Retrieval → State Reuse → Representation Materialization → Continued Execution → State update

Knowledge-base and authority/security research remain queued and are not to be run in parallel with this core sequence unless explicitly reopened.

## 4. Evidence hierarchy

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

## 5. Scientific discipline

1. Do not infer semantic necessity from absence of an API.
2. Do not create a new State object/schema merely to make the experiment succeed.
3. Do not use full-history cold prefill as a disguised State-Reuse path.
4. Do not mutate the real durable store.
5. Every destructive test uses a disposable copy/fixture.
6. Record the first concrete missing seam on failure.
7. Preserve negative results.
8. Do not measure performance before semantic reuse is established.
9. Distinguish observed code fact, runtime observation, inference, and hypothesis.
10. No public publication of sensitive recovery recipes, storage paths, field combinations, isolation bypasses, or procedures that could expose another person's state.

## 6. ES-R1 gate

R1-A STATE-REUSABLE-WITHOUT-FULL-PREFILL
Observed same Execution State survives Representation loss and is actually re-materialized/rebound and continued without complete history/full cold prefill.

R1-B STATE-EXISTS-BUT-NO-REUSE-SEAM
State-relevant semantic information demonstrably remains, but the current runtime has no seam capable of consuming it for reuse. First missing seam must be concrete.

R1-C REPRESENTATION-IS-SEMANTICALLY-REQUIRED
Only permitted if evidence shows the lost Representation contains information that the surviving State cannot reconstruct and that information is semantically required for continuation. Lack of an API alone is insufficient.

R1-D INCONCLUSIVE
Evidence cannot discriminate the hypotheses.

## 7. Current gate

ES-R1: OPEN
Phase A/B: authorized next
Phase C destructive experiment: waiting for Phase A/B fact trace review
ES-R2: BLOCKED
PALACE schema/contract design: NOT STARTED

## 8. Paper-quality evidence to accumulate

For every successful/failing run preserve:
- State identity
- lineage
- logical position
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

The central paper claim, if eventually supported, must be earned experimentally:

> Execution State lifecycle can be longer than Physical Representation lifecycle, enabling representation-independent reuse.

Do not use this as a result before ES-R1 evidence supports it.
