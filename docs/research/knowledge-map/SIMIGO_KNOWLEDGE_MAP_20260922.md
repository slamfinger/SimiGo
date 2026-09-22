# SimiGo-Lab Knowledge Map — 2026-09-22

本图只登记已有证据支持的关系。未验证的关系明确标为 Hypothesis，不把目录结构当成研究结论。

## Known

### K1 — Official ChatSession owns physical KV semantics
Evidence:
- `docs/experiments/OFFICIAL_CAPABILITY_MATRIX.md`
- `docs/lessons/AUDIT_SIMPLIFY_MIGRATION_LESSONS_2026-09-12.md`
- `docs/audit/POST_AUDIT_DELETION_RECORD_2026-09-11.md`

### K2 — Current MLX public API lacks sequence-identity prefix sharing
Evidence:
- `docs/experiments/EXECUTION_FORK_F0_PROBE_RESULTS_20260919.md`
- public API/source inspection at pinned MLX / MLXLMCommon versions

### K3 — Execution Fork F0 reached a bounded negative result
The current public API does not expose a way to derive an independently executable child execution state while sharing the common prefix without paying the known full-copy/file-roundtrip costs.

### K4 — Official capability completion is an active evolution direction
Evidence:
- `docs/experiments/OFFICIAL_CAPABILITY_MATRIX.md`

## Unknown

- U1: Whether future MLX / MLXLMCommon releases will expose sequence identity or equivalent prefix-sharing semantics.
- U2: Whether a future upstream API can provide shared-prefix execution without SimiGo introducing a second physical KV authority.
- U3: The exact performance boundary at which such an upstream capability would materially change SimiGo's Execution Plane design.

## Hypotheses

- H1: If upstream exposes sequence identity + shared-prefix semantics, a minimal ExecutionState / sequence layer may become justified.
- H2: Until then, application-level emulation of true shared-prefix execution is more likely to recreate a second physical-state authority than to preserve SimiGo's Core boundary.

These remain hypotheses; they are not Core invariants.

## Independent Knowledge Channels

The current map recognizes candidate channels, but does not yet declare them statistically or epistemically independent.

- C1 — Official API/source audit: what upstream publicly exposes.
- C2 — SimiGo production/runtime evidence: what the integrated system actually does.
- C3 — Controlled execution experiment: what F0 empirically demonstrates on real hardware.
- C4 — Historical architectural audit: what simplification/deletion review demonstrated about local authority.

Independence requires a separate assessment; different document names are not enough.

## Cross-channel Findings

### X1 — The boundary is constrained from both sides

C1/C3 constrain what upstream can currently express; C2/C4 constrain what SimiGo should own locally.

The combination supports the current v5.0 boundary, but this synthesis does not prove that C1–C4 are fully independent channels.

## Traceability

See `docs/research/participants/PARTICIPANT_INDEPENDENCE_20260922.md`.
