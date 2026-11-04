# Documentation map

This directory contains current contracts, evidence records, and historical research. A document's presence here does not make it current implementation guidance or an authorization to change code.

## Start here

- [Agent access contract](AGENT-ACCESS.md) — supported local OpenAI-compatible entry and explicit MCP lifecycle integration; includes current evidence limits.
- [Architecture](architecture/) — current external-turn contract plus historical runtime / upstream design references.
- [Decisions](decisions/README.md) — accepted decisions, proposals, and superseded direction records, separated by status.
- [Open problems](knowledge/open-problems/README.md) — current product issues that still require evidence or closure.
- [Knowledge](knowledge/README.md) — evidence-derived findings, principles, invariants, and open problems.
- [Historical audits](audit/README.md), [experiments](experiments/README.md), and [benchmarks](benchmarks/README.md) — dated review, experiment, and measurement records.
- [Lessons](lessons/README.md) — incidents, regressions, and engineering lessons.
- [Research archive](research/README.md) — historical research questions and synthesis, not current product status.
- [Evolution history](evolution/README.md) and [history](history/) — architecture transitions and integration snapshots.
- [Release history](releases/) — historical release notes and freeze records. Current distribution status is in the repository-root [README](../README.md) and [RELEASE.md](../RELEASE.md).

## Evidence and archive rules

- `audit/`, `experiments/`, `benchmarks/`, and `lessons/` preserve dated evidence. Read each record's scope and limitations; do not infer current product behavior from an old audit.
- The loose files directly under `docs/` are historical audit, beta, or reference snapshots. They are retained for traceability, not as current product instructions.
- Historical records are not rewritten to match current code. Correct current-state navigation and known issues in the relevant indexes instead.
- When a claim depends on current behavior, verify it against the current source, tests, and the matching real-machine evidence. Package tests, app tests, installed builds, and real-model carrier tests are distinct evidence levels.
