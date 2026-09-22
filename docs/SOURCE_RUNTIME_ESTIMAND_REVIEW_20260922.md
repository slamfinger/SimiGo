# STEP ④ Estimand Review — 2026-09-22

**Artifact under review:** `docs/SOURCE_RUNTIME_ESTIMAND_DEFINITION_v0.1.md`  
**Review role:** external methodological review  
**Scope:** STEP ④ only

## Review result

**RETURN FOR REVISION**

The draft correctly avoids performance-first framing and keeps candidate unit
families open, but its proposed estimand is not yet sufficiently identified.

## Findings

### E-01 — RUBS currently embeds the existence property

The definition of `U*(M,W,O)` says it is the set of candidates "having the
target structural properties". Those properties include independent residency
and migration semantics.

That wording is already close to the criterion that STEP ⑤ is supposed to
define.

**Required revision:** define the estimand as the runtime-observable boundary
structure itself, without filtering candidates by whether they already satisfy
the future existence criterion.

### E-02 — B(u) mixes target quantity and validation relations

`B(u)=<A_u,R_u,C_u,I_u>` contains semantic relations whose observability and
qualification have not yet been established.

In particular, `R_u`, `C_u`, and `I_u` risk becoming hidden existence
criteria.

**Required revision:** separate the estimand's target representation from the
future predicates used to judge whether that representation constitutes a
Model Unit.

### E-03 — "stable", "independent", and "distinguishable" are latent criteria

The prose uses "稳定", "独立", and "可区分" as descriptive properties. These
are legitimate research concepts, but at STEP ④ they must not silently acquire
thresholds or pass/fail meaning.

**Required revision:** explicitly mark them as target concepts whose operational
definitions belong to STEP ⑤–⑦.

### E-04 — Population is still intentionally open, which is acceptable

The model/workload/observation domains are not yet numerically or concretely
registered.

This is not a failure of STEP ④ itself, provided the estimand remains
conditional on those domains and does not pretend to support a broader
population.

## Review conclusion

The draft has the correct direction but should be revised before STEP ④ can
receive PASS.

No STEP ⑤ work is authorized by this review.

No state-file update is warranted.

No measurement or implementation is authorized.
