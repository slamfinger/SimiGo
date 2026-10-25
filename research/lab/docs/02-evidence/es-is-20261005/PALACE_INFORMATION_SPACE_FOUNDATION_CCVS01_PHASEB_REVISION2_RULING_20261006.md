# CCVS-01 Phase B — Human Revision Ruling 2 (R4-Only)

Date: 2026-10-06  
Type: `HUMAN RULING / L2 AUTHORITATIVE`  
Subject: Review of CCVS-01-PB v1.1  
Ruling: `B — NARROW REVISION / R4 STATISTICAL DEFINITIONS ONLY`

## Ruling content

Human accepted the v1.1 protocol constants as protocol constants:

```text
2x non-regression line               = ACCEPT
high >= 500 / medium >= 100 minima   = ACCEPT
P50 >= 10 / P95 >= 20 / P99 >= 100   = ACCEPT
invalid budget = 2x                  = ACCEPT, with invalid definition added
quiescence < 20%                     = ACCEPT, with "consecutive" clarified
```

One remaining statistical ambiguity must be closed before freeze: the
conflict between median-of-runs aggregation and pooled P99 validity.

Mandatory fixes (R4.2):

```text
1. Percentiles are computed independently within each valid run.
2. Observation minimums for P50/P95/P99 are PER RUN, not pooled.
3. Candidate-level metrics are the median of valid run-level metrics.
4. INVALID can be triggered only by predefined protocol/environment
   violations; poor performance results must never constitute invalid.
   (Examples of valid invalid causes: background interference, resource
   observer failure, fixture corruption, carrier crash outside a designated
   F-point, quiescence violation, instrumentation failure.)
5. Quiescence is three consecutive 5-second windows and is a run admission
   condition, not a performance metric.
6. Pooled P99 may remain only as a clearly-labelled supplemental diagnostic,
   never mixed with the primary candidate metric chain.
```

Expected ruling after this fix: `CCVS-01-PB v1.2 = ACCEPT / FROZEN`, while
keeping:

```text
Phase C = NOT AUTHORIZED
backend = NOT SELECTED
benchmark = NOT EXECUTED
ES <-> IS higher-layer opening = CLOSED
```

This is the final statistical-semantics closure, not a protocol redesign.
