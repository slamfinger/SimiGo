# Finding: Simplification is an architectural correction when upstream semantics are sufficient

**Status:** Evidence-backed finding  
**Date:** 2026-09-22  
**Evidence window:** 2026-09-09 to 2026-09-12

## Finding

The 2026-09 simplification line provides evidence that removing parallel runtime authorities is preferable to preserving experimental abstractions merely because they once solved a local problem.

The decisive criterion was not code volume. It was whether the official MLX/MLXLMCommon APIs already supplied the required semantics.

## Evidence

The post-audit deletion record documents rejection of:

- `AdmissionReservationLedger`;
- experimental `BatchSequence / BatchedDecodeScheduler / InferenceModelCapabilities`;
- parallel Physical KV continuation state;
- parallel cancellation/commit authority;
- audit-only state seams.

The same record states that production behavior should be expressible through official model/session/generation/cache APIs when those APIs already provide the required semantics.

## Interpretation

This is evidence for an architectural method:

> First establish the upstream semantic source of truth; only introduce local authority after an explicit upstream gap is demonstrated.

It is not evidence that all custom code is undesirable. Application-level concerns such as HTTP/OpenAI mapping and service management remain legitimate local responsibilities.

## Traceability

- Audit record: `docs/audit/POST_AUDIT_DELETION_RECORD_2026-09-11.md`
- Lesson: `docs/lessons/AUDIT_SIMPLIFY_MIGRATION_LESSONS_2026-09-12.md`
- Architecture: `README_base.md`, §5 and §13
