# SimiGo Research Direction: Execution-State-Driven Information-Space Closed Loop

> **Status:** ACTIVE RESEARCH DIRECTION / DESIGN AND REVIEW ONLY  
> **Date:** 2026-10-09  
> **Direction ID:** `SIMIGO-RESEARCH-DIRECTION-ES-IS-CLOSED-LOOP-001`  
> **Canonical base:** `6a928980b6c502a0919fac002bdf6b27b58ffad8`  
> **Architecture review:** `SIMIGO-ARCH-REVIEW-ES-IS-CLOSED-LOOP-001`

## 1. Canonical direction

The active research direction is:

```text
Specify and review the minimum Execution-State-driven closed loop in which:

1 Execution State derives continuation demand and dependencies;
2 Information Space carries source information, computation results, and
  settled reusable results;
3 physical persistence supports later restoration and reuse;
4 valid settled results are reused without recomputation;
5 missing, stale, ambiguous, invalid, or dependency-changed information is
  selectively recomputed;
6 new settlements are written back for later continuation.
```

## 2. Primary research question

```text
In the inherently coupled Execution State / Information Space system, can
Execution State correctly derive its continuation demand, Information Space
preserve and expose the required source/settled information, physical
persistence support later reuse, and incremental continuation avoid recomputing
valid settled results?
```

## 3. Required future design objects

The next design work should be organized around five bounded specifications:

```text
1 ES continuation-demand semantics;
2 Information-Space record and settlement-state model;
3 source/version/provenance and dependency bindings;
4 persistence/reuse/invalidation transition semantics;
5 minimal closed-loop architecture specification.
```

No implementation, experiment, canonical mutation, PALACE mutation, or campaign
is authorized by this direction.

## 4. Required non-functional boundary

Any future specification must preserve:

```text
no EXPECTED-vector leakage into causal materialization;
explicit unresolved, stale, ambiguous, and invalid states;
write-once or otherwise auditable settlement evidence;
D-001 and D-002 evidence immutability;
no Decision Core mutation without separate authorization;
no PALACE mutation without separate authorization;
no automatic campaign authorization.
```

## 5. Relationship to prior objects

```text
D-001 = CLOSED / BOUNDED PASS / structured-input decision harness only;
D-002 = FAIL / STOP / real PALACE consumption bridge unproven;
Instrumentation v1.6 = DELIVERED FOR HUMAN REVIEW / DEPRIORITIZED;
PIR = CLOSED / VALIDATION DEFERRED;
E9 / EXP-004 = NOT AUTHORIZED.
```

Prior records remain immutable. This direction does not reopen them.

## 6. Next lawful object

The next lawful deliverable is:

```text
Execution–Information Closed-Loop Research Specification / Authorization
Package v1.0
```

for Human review. It must remain design-only until separately authorized.

## 7. Decision requested

Human review of this direction is implicit in the current ruling. The next
review should decide:

```text
ACCEPT the closed-loop specification proposal;
REVISE its scope;
REJECT this research direction.
```
