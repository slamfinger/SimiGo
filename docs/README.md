# Documentation map

This directory contains current contracts, evidence records, and historical research. A document's presence here does not make it current implementation guidance or an authorization to change code.

## Start here

- [Agent access contract](AGENT-ACCESS.md) — supported local OpenAI-compatible entry and explicit MCP lifecycle integration; includes current evidence limits.
- [IS external-turn contract](architecture/IS_EXTERNAL_TURN_CONTRACT_20261030.md) — retained data contract and historical client evidence; not a current cloud-provider path.
- [Historical runtime / MLX designs](architecture/EXECUTION_RUNTIME_DESIGN_V16.md) and [MLX roadmap snapshot](architecture/MLX_LM_REFERENCE_AND_EXPERIMENTAL_ROADMAP_20260918.md) — archived references, not current implementation plans.
- [Decisions](decisions/README.md) — accepted decisions, proposals, and superseded direction records, separated by status.
- [Open problems](knowledge/open-problems/README.md) — current product issues that still require evidence or closure.
- [Knowledge](knowledge/README.md) — evidence-derived findings, principles, invariants, and open problems.
- [Historical audits](audit/README.md), [experiments](experiments/README.md), and [benchmarks](benchmarks/README.md) — dated review, experiment, and measurement records.
- [Lessons](lessons/README.md) — incidents, regressions, and engineering lessons.
- [Research archive](research/README.md) — historical research questions and synthesis, not current product status.
- [Evolution history](evolution/README.md) — architecture transitions.
- [History: V5 baseline](history/CORE_ARCHITECTURE_BASELINE_V5_20260912.md) and [transcript collection integration](history/COLLECTION_INTEGRATION_20261105.md) — dated snapshots.
- [Release history](releases/README.md) — historical release notes and freeze records. Current distribution status is in the repository-root [README](../README.md) and [RELEASE.md](../RELEASE.md).

## Evidence and archive rules

- `audit/`, `experiments/`, `benchmarks/`, and `lessons/` preserve dated evidence. Read each record's scope and limitations; do not infer current product behavior from an old audit.
- The loose files directly under `docs/` are a mixed set: `AGENT-ACCESS.md` is current integration guidance; `README.md` is this navigation map; `ARCHIVE_AUDIT_PUBLIC_CURATION_20260927.md`, `AUDIT_BASELINE_20260928.md`, `RELEASE_v2.0.0-beta.md`, and `V2.1_REFERENCE_APP_ARCHITECTURE.md` are historical audit, beta, or reference snapshots. Do not treat the historical files as current product instructions.
- Historical records are not rewritten to match current code. Correct current-state navigation and known issues in the relevant indexes instead.
- When a claim depends on current behavior, verify it against the current source, tests, and the matching real-machine evidence. Package tests, app tests, installed builds, and real-model carrier tests are distinct evidence levels.
