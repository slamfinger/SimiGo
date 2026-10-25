# C07 — PALACE / Information Space Foundation Route Decision

## Research State Capsule

```text
Research Object          = Carrier Path A / PALACE Information Space Foundation route
Status                   = ACCEPTED / LATER REFRAMED BY CORE SUFFICIENCY AUDIT
Route decision commit    = f4e2ba6
Carrier selection commit = 0e822ac
Last verified            = 2026-10-06 @ 14de9fd
Capsule lineage          = PRQ-ISF-01 chain → Carrier Path A → later Core Sufficiency reframe
```

## Research Question

Should an independent candidate carrier enter the frozen PRQ-ISF-01 probe, and
what route should follow the probe-control result?

## What was established

```text
Carrier Path A selected.
MemPalace local file-backed core selected as first independent candidate.
Read-only feasibility audit later classified IS-MCI as
  DIRECT 1 / ADAPTER 2 / GAP 5.
MemPalace as-is = NO-GO as direct PRQ-ISF-01 semantic carrier.
Thin adapter = NOT FEASIBLE.
```

Human reframe:

```text
This NO-GO is narrow.
It does not exclude MemPalace as migration source, future persistence backend,
or backend-control candidate behind Core/Store.
```

## Evidence

```text
docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_ROUTE_DECISION_20261005.md
docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_CARRIER_PATH_DECISION_20261005.md
docs/02-evidence/es-is-20261005/MEMPALACE_ISMCI_ADAPTER_FEASIBILITY_AUDIT_20261005.md
docs/02-evidence/es-is-20261005/PALACE_INFORMATION_SPACE_FOUNDATION_CORE_SUFFICIENCY_AUDIT_20261005.md
```

## Bounding

Candidate selection and feasibility audit only. No integration, implementation,
probe execution against MemPalace, backend selection, or contract change.

## What it does NOT prove

```text
That MemPalace is universally unsuitable.
That MemPalace cannot be a backend or migration target.
That another carrier is better.
That a composite carrier is approved.
That the Information Space Foundation route is closed.
```

## Dependencies

- PRQ-ISF-01 accepted probe design.
- Frozen ES↔IS contracts.
- InformationCore / RelationCore / Store boundary.

## Constraints

```text
No MemPalace mutation.
No adapter implementation.
No carrier integration.
No backend substitution.
No contract change.
No new experiment without explicit authorization.
```

## Current unresolved seam

Whether a later composite or backend route can preserve MemPalace value while
satisfying PRQ semantics behind the Core/Store boundary.

## Next legal transition

Core Sufficiency Audit, then Higher-Layer Continuation Semantics scope charter.

## Source documents / commit

| Document | Commit |
|---|---|
| Route decision | f4e2ba6 |
| Carrier path decision | 0e822ac |
| MemPalace feasibility audit | 1540cae |
| Core Sufficiency reframe/audit | 1064b05 / 7e7c68b |
