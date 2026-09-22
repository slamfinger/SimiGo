# Finding: Physical KV ownership converges to official ChatSession

**Status:** Evidence-backed finding  
**Date:** 2026-09-22  
**Evidence window:** 2026-09-11 to 2026-09-12

## Finding

SimiGo's production architecture should treat official `ChatSession` / `PromptCacheReusePolicy` as the authoritative owner of Physical KV token accounting, prefix reconciliation, trim/rebuild decisions, and cache telemetry whenever the upstream API provides those semantics.

SimiGo retains responsibility for logical session continuity, protocol normalization, resource/lifecycle coordination, and observation, but does not maintain a parallel token-level KV protocol.

## Evidence

- `README_base.md` records the v5.0 baseline and states that Physical Token Ledger, exact prefix matching, and trim/rebuild decisions are owned by official `ChatSession`.
- `docs/lessons/AUDIT_SIMPLIFY_MIGRATION_LESSONS_2026-09-12.md` records the distinction between logical session continuity and physical KV reuse, including the observed warm-hit telemetry.
- `docs/audit/POST_AUDIT_DELETION_RECORD_2026-09-11.md` records rejection of parallel custom KV/cancellation/admission layers after the simplification pass.

## Boundary

This finding does not claim that every future upstream implementation is sufficient. If an explicit upstream semantic gap is demonstrated, the gap must be documented and experimentally verified before a local abstraction is introduced.

## Traceability

- Architecture: `README_base.md`, §5–§6
- Lesson: `docs/lessons/AUDIT_SIMPLIFY_MIGRATION_LESSONS_2026-09-12.md`, §2–§3
- Audit record: `docs/audit/POST_AUDIT_DELETION_RECORD_2026-09-11.md`
