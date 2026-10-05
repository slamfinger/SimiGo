# C08 — PRQ-ISF-01 Minimal Decodable Probe Design

## Research State Capsule

```text
Research Object          = Minimal Decodable Probe Design
Status                   = ACCEPTED / CLOSED BY HUMAN REVIEW
Design delivery          = 7b9d167
Human review             = 8fad97b
Last verified            = 2026-10-06 @ 14de9fd
Capsule lineage          = Core Sufficiency route → accepted probe design
```

## Research Question

What is the smallest mechanically decodable probe that can test whether
`IS-MCI-01..08` are sufficient for `PRQ-ISF-01` without a semantic oracle?

## What was established

```text
Abstract IS Port limited to:
  put/get blob, node, edge, provenance, pin, mutation event.

Mechanical decoder with no semantic repair.
Frozen I-1 resolve handoff.
Registered fixture:
  root + child canonical records;
  result / used / surface / continues edges;
  provenance, pins, succession event.

Scenario matrix SC-00..SC-12 covers baseline integrity, mutation, absence,
identity failure, edge loss/flattening, provenance separation, historical pin,
lineage cycle, optional absence, and forbidden semantic rescue.
```

## Evidence

```text
docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_PRQ_ISF_01_PROBE_DESIGN_20261005.md
Human review: 8fad97b
```

## Bounding

Design only. No implementation, carrier selection, backend integration,
experiment execution, or contract change.

## What it does NOT prove

```text
That a candidate carrier can satisfy IS-MCI.
That PALACE or any backend is viable.
That the design implementation will pass.
That success would generalize beyond the registered fixture and mutation class.
```

## Dependencies

- Frozen I-1 resolve semantics.
- Accepted IS-MCI obligations.
- Core Sufficiency route boundary.

## Constraints

```text
Abstract IS Port is probe observation vocabulary, not a future API.
No semantic repair, summary, ranking, inference, or implicit reconstruction.
No carrier-specific privileged access.
```

## Current unresolved seam

Whether an independent carrier can satisfy the registered scenarios.

## Next legal transition

Separate implementation / execution authorization.

## Source documents / commit

```text
Source: docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_PRQ_ISF_01_PROBE_DESIGN_20261005.md
Design delivery commit: 7b9d167
Human acceptance commit: 8fad97b
Last verified at: 14de9fd
```

## Claim → source mapping

| Claim | Source | Commit |
|---|---|---|
| Role separation | Probe design §2 | 7b9d167 |
| Minimal fixture | Probe design §3 | 7b9d167 |
| Decoder contract | Probe design §4 | 7b9d167 |
| Scenario matrix SC-00..SC-12 | Probe design §6 | 7b9d167 |
| SUCCESS / FAILURE / INDETERMINATE | Probe design §8 | 7b9d167 |
