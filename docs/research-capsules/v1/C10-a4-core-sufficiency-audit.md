# C10 — A4 Core Sufficiency Audit

## Research State Capsule

```text
Research Object          = InformationCore / RelationCore Sufficiency Audit
Status                   = DELIVERED / ACCEPTED / CLOSED
Audit delivery           = 7e7c68b
Human acceptance         = 1064b05
Last verified            = 2026-10-06 @ 14de9fd
Capsule lineage          = A4 conceptual study → Human findings → reduction study → Core audit
```

## Research Question

For the currently registered PRQ-ISF-01 task domain, do existing
InformationCore / RelationCore / Store semantics suffice to express the required
continuation graph?

## What was established

```text
For the UTF-8 / text-bounded PRQ-ISF-01 task domain:
  InformationCore + RelationCore + Store boundary are sufficient to express
  the required continuation graph semantics.

No new Store primitive is required.
No carrier semantic layer is required for the current PRQ domain.

Higher-layer-only obligations:
  canonical CR mapping;
  historical pin resolution;
  succession semantics;
  lineage traversal / cycle validation;
  Frozen failure-family mapping.

Conditional finding:
  Information.content is String / UTF-8 text.
  Arbitrary non-Unicode byte fidelity would be an actual semantic gap.
```

Human ruling explicitly bounded the text domain to the current PRQ-ISF-01 task
domain; it is not a global or permanent InformationCore boundary.

## Evidence

```text
docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_CORE_SUFFICIENCY_AUDIT_20261005.md
Delivery: 7e7c68b
Acceptance: 1064b05
Source files:
  trackD-memory/Sources/InformationCore/Information.swift
  trackD-memory/Sources/InformationCore/InformationStore.swift
  trackD-memory/Sources/InformationCore/SQLiteStore.swift
  trackD-memory/Sources/RelationCore/Relation.swift
  trackD-memory/Sources/RelationCore/RelationStore.swift
  trackD-memory/Sources/InformationIntegration/SQLiteRelationStore.swift
  trackD-memory/Sources/InformationIntegration/UpperLayer.swift
```

## Bounding

Read-only semantic / contract / implementation audit. No implementation, backend
selection, MemPalace mutation, probe execution, experiment, or contract change.

## What it does NOT prove

```text
That arbitrary byte fidelity is represented.
That InformationCore is complete Information Space.
That every backend implements the semantics.
That higher-layer continuation semantics are implemented.
That universal minimality is proven.
```

## Dependencies

- A4 Reduction / Ownership Study.
- Existing InformationCore / RelationCore / Store boundary.
- Current PRQ-ISF-01 task-domain boundary.

## Constraints

```text
No silent widening of Information.content.
No new Store primitive without separate ruling.
No carrier semantic layer without separate ruling.
No backend substitution without separate authorization.
```

## Current unresolved seam

Higher-layer continuation semantics and the conditional byte-fidelity boundary.

## Next legal transition

Higher-Layer Continuation Graph Semantics — Scope & Research Question Charter.

## Source documents / commit

| Claim | Source | Commit |
|---|---|---|
| UTF-8/text-bounded sufficiency | Core Sufficiency Audit §6 | 7e7c68b |
| Higher-layer-only obligations | Core Sufficiency Audit §4 | 7e7c68b |
| Conditional byte gap | Core Sufficiency Audit §4/§5 | 7e7c68b |
| Human acceptance | Route decision §14 | 1064b05 |
