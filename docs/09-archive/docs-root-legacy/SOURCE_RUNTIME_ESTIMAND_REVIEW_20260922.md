# STEP ④ Estimand Review — 2026-09-22

**Artifact under review:** `docs/SOURCE_RUNTIME_ESTIMAND_DEFINITION_v0.1.md`  
**Review role:** external methodological review  
**Scope:** STEP ④ only

## Review history

### Review 1 — RETURN FOR REVISION

The first draft embedded the future existence property in `U*(M,W,O)`
and allowed `B(u)` to function as a hidden validation criterion.

Required correction was to separate the target estimand from the future
existence criterion.

### Review 2 — PASS WITH SCOPE LIMIT

The revised draft changes the target to:

[
mathcal{B}(M,W,O)
]

the runtime boundary structure conditional on the model, workload, and
observation domains.

A boundary (b) is no longer defined as an object that already satisfies
independent residency / migration semantics. Those properties are retained
as structural dimensions to be described and are explicitly excluded from
being pass/fail criteria at STEP ④.

The revised draft also explicitly separates:

[
	ext{Estimand} ightarrow 	ext{Existence Criterion}
]

and prohibits treating the mere observation of a boundary as proof that a
Model Unit exists.

## Review checks

| Check | Result |
|---|---|
| Estimand distinct from STEP ⑤ existence criterion | PASS |
| No implicit positive/negative existence threshold | PASS |
| Candidate unit family remains open | PASS |
| Performance metric not substituted for C1 target | PASS |
| Population/domain claims remain conditional | PASS |
| Implementation/API/harness not embedded in estimand | PASS |
| Historical Track B/E results not promoted to runtime observations | PASS |
| Measurement authorization created | NO |
| STEP ⑤ authorization created | NO |

## Scope limitation

This PASS means only that the revised artifact is acceptable as a **STEP ④
estimand definition**.

It does not establish:

- that any Model Unit exists;
- an existence criterion;
- an insufficiency criterion;
- discriminating power;
- measurement worth;
- a valid harness or experiment;
- an RQ registration;
- any runtime result.

## Gate disposition

**STEP ④ estimand definition: PASS — pending explicit repository registration.**

The authoritative research state remains unchanged until registration is
explicitly performed.

**No STEP ⑤ work is authorized by this review.**

**No measurement or implementation is authorized.**
