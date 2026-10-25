# C04 — I-1 Persistence / Resolve

## Research State Capsule

```text
Research Object          = IPAC Persistence / Resolve Conceptual Design v0.3
Status                   = FROZEN
Semantic authority       = main/2b2e2ef
Research branch mirror   = 76825ad
Last verified            = 2026-10-06 @ 14de9fd
Capsule lineage          = C03 → I-1 v0.1 → reviews → v0.3 freeze
```

## Research Question

Can Information Space persist enough continuation structure for a future
Execution to reconstruct a Continuation Basis?

## What was established

```text
CR ≠ R1.
CR_ref is the resolve handle.
CR identity hashes result, pinned used set, surface, and parent CR_ref.
Provenance is outside identity.
resolve(CR_ref) produces R2, R2-with-violations, or UNRESOLVABLE.
R2 is NOT an Execution State.
V-1..V-5 define identity, referability, content, lineage, surface, and
formation checks.
Failure families include CR-ID-MISMATCH, C-REF-NOT-FOUND, I-NF, I-MISMATCH,
A-SUB, A-NF, A-CYCLE, P-VIOLATION, FORM-DRIFT.
```

## Evidence

```text
docs/02-evidence/es-is-20261005/IPAC_PERSISTENCE_RESOLVE_CONCEPTUAL_DESIGN_V0.3.md
Frozen authority: main/2b2e2ef
```

## Bounding

Conceptual design only. R2 is a Continuation Basis, not an Execution State.
Instantiation completeness is deferred to I-1c.

## What it does NOT prove

```text
That R2 is complete for logical continuity outside D_RS.
That R2 suffices to produce S2.
That IPAC is minimal.
That PALACE is committed.
That implementation or experiment is authorized.
```

## Dependencies

- I-1 follows the Core Reference Scenario.
- I-1c must answer instantiate completeness.
- I-1d must answer runtime realization and verification.

## Constraints

```text
τ2 is externally supplied; resolve does not infer the future.
Edge vocabulary frozen at three.
No PALACE commitment.
No implementation or experiment.
```

## Current unresolved seam

Instantiate completeness, later addressed by I-1c.

## Next legal transition

I-1c Instantiate Completeness.

## Source documents / commit

```text
Source: docs/02-evidence/es-is-20261005/IPAC_PERSISTENCE_RESOLVE_CONCEPTUAL_DESIGN_V0.3.md
Semantic authority commit: main/2b2e2ef
Research mirror commit: 76825ad
Last verified at: 14de9fd
```

## Claim → source mapping

| Claim | Source | Commit |
|---|---|---|
| CR identity fields and canonical order | I-1 §2.1 | main/2b2e2ef |
| R2 is not Execution State | I-1 §3.3 | main/2b2e2ef |
| V-1..V-5 suite | I-1 §3.4 | main/2b2e2ef |
| τ2 externally supplied | I-1 T2 input boundary | main/2b2e2ef |
