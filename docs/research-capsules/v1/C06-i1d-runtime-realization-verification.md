# C06 — I-1d Runtime Realization / Verification

## Research State Capsule

```text
Research Object          = Instantiate Runtime Realization & Verification v0.3
Status                   = FROZEN
Semantic authority       = branch registration/1832676
Last verified            = 2026-10-06 @ 14de9fd
Capsule lineage          = I-1 + I-1c → I-1d v0.1 → reviews → v0.3 freeze
```

## Research Question

How can the Frozen Instantiate Contract obtain an executable, auditable runtime
realization without silently changing the Frozen semantics?

## What was established

```text
Frozen Instantiate Contract IC-1..IC-7
        ↕
Runtime Instantiate Record IR
        ↕
Mechanical Verification Surface VV-1..VV-7
        ↕
Disposition + Lifecycle

Creation point = successful materialization.
Precondition gate must pass before VV applicability.
VV tiers = VERIFIED / COVENANTED / FAILED.
POST-CREATION-ANOMALY is lifecycle, not a fourth disposition.
Failure taxonomy includes PRECONDITION-BLOCK, CREATE-BLOCK,
POLICY-BLOCK, PROCEED-WITH-ANNOTATION, DECLARED-ALTERNATIVE.
Anti-drift guarantee detects missing mapping, weakened verification,
changed failure semantics, and undeclared decision inputs.
```

## Evidence

```text
docs/02-evidence/es-is-20261005/IPAC_INSTANTIATE_RUNTIME_REALIZATION_VERIFICATION_CONCEPTUAL_DESIGN_V0.3.md
Frozen authority: branch registration/1832676
```

## Bounding

Conceptual design only. It does not prove absence of arbitrary hidden code,
idempotence, carrier viability, or empirical sufficiency.

## What it does NOT prove

```text
That a runtime implementation exists or is correct.
That PALACE or any backend is viable.
That COVENANTED checks verify anything.
That mapping coverage proves absence of hidden semantic logic.
That G-1..G-4 have been executed.
```

## Dependencies

- I-1 Persistence / Resolve.
- I-1c Instantiate Completeness.
- Subsequent Implementation Gate and G-1..G-4.

## Constraints

```text
No substrate/backend selection.
No carrier choice.
No storage-format binding.
No implementation or experiment.
No semantic judgment in the Verification Surface.
```

## Current unresolved seam

At freeze, runtime realization had not been implemented. Later G-1..G-4
addressed that authorized slice.

## Next legal transition

Implementation Gate, then G-1..G-4 in fixed order.

## Source documents / commit

```text
Source: docs/02-evidence/es-is-20261005/IPAC_INSTANTIATE_RUNTIME_REALIZATION_VERIFICATION_CONCEPTUAL_DESIGN_V0.3.md
Semantic authority commit: branch registration/1832676
Last verified at: 14de9fd
```

## Claim → source mapping

| Claim | Source | Commit |
|---|---|---|
| Contract ↔ IR ↔ VV mapping | I-1d §1 | branch/1832676 |
| Creation point at materialize success | I-1d §2 | branch/1832676 |
| VV-1..VV-7 tiers | I-1d §3 | branch/1832676 |
| Disposition + lifecycle taxonomy | I-1d §4 | branch/1832676 |
| Hidden-code universal negative not claimed | I-1d §5 | branch/1832676 |
