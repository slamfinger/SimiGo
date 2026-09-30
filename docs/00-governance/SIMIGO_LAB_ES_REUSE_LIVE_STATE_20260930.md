# SimiGo-Lab — Execution State Reuse Live Research State

Updated: 2026-09-30
Branch: research/es-reuse-program-20260930
Status: ACTIVE / ES-R1 OPEN

## Current gate

ES-R1 Phase A/B is the only authorized work.

Current question:
Can an existing Execution State survive loss of a Physical Representation and later be reused without complete history replay and full cold prefill?

## Completed

- Research program registered.
- ES-R1 experiment design registered.
- Cross-session context capsule registered.
- Local-agent protocol registered.
- PALACE-1 E0-E3 remains SEALED/PARKED.

## Current authorization

DO:
- read-only source tracing;
- map State/Representation boundaries;
- establish disposable fixture and baseline;
- capture raw evidence.

DO NOT:
- delete anything from the real durable store;
- add a new durable State schema/object;
- redesign production APIs;
- optimize performance;
- start ES-R2;
- design PALACE storage/retrieval schema.

## Required next handoff

Local agent must return a Phase A/B evidence packet containing:
1. exact commit;
2. identity/lineage/position trace;
3. continuation dependency trace;
4. RepresentationRef and BindingRegistry trace;
5. materialization/restore entry points;
6. D/R/P/O/T classification;
7. OBSERVED/INFERRED/UNKNOWN status;
8. baseline probe evidence;
9. disposable representation-loss boundary;
10. safety/integrity verification;
11. first potential missing seam;
12. deviations and raw evidence locations.

## Gate rule

No Phase C authorization until the research architect reviews the packet.

Possible ES-R1 terminal outcomes:
- R1-A STATE-REUSABLE-WITHOUT-FULL-PREFILL
- R1-B STATE-EXISTS-BUT-NO-REUSE-SEAM
- R1-C REPRESENTATION-IS-SEMANTICALLY-REQUIRED
- R1-D INCONCLUSIVE

## Cross-session recovery

A new session must read:
1. this file;
2. SIMIGO_LAB_ES_REUSE_CONTEXT_CAPSULE_20260930.md;
3. SIMIGO_LAB_ES_REUSE_RESEARCH_MASTER_20260930.md;
4. current ES-R1 experiment design;
5. latest Research Record/raw evidence;
6. current branch/commit.

Then reconstruct causal context before giving technical instructions.

This file is a live snapshot, not raw evidence. It may be updated after each reviewed gate.
