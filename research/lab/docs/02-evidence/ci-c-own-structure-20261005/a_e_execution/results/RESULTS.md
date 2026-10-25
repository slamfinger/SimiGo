# A_epistemic / A_execution 8-Cell Results

Date: 2026-10-05
Status: `RUN_COMPLETE · NO_846_MAPPING · NO_INFORMATIONCORE_WRITE`
Run root: `a_e_execution/runs/20261005-093200-a-e-execution`

## Matrix

| Arm | Model | E | X | F visible | adoption | C4 emitted | Matches expected |
|---|---|---|---|---|---|---|---|
| 1 | C | E+ | X+ | true | true | true | ✅ |
| 2 | C | E+ | X- | true | true | false | ✅ |
| 3 | C | E- | X+ | true | false | false | ✅ |
| 4 | C | E- | X- | true | false | false | ✅ |
| 5 | N | E+ | X+ | true | true | true | ✅ |
| 6 | N | E+ | X- | true | true | false | ✅ |
| 7 | N | E- | X+ | true | false | false | ✅ |
| 8 | N | E- | X- | true | false | false | ✅ |

## Primary result label

```text
ORDERED_SEPARATION_SUPPORTED
```

All 8 cells (4 arms × 2 models) match the expected ordered-layer signature. The critical separation cell `E+X-` shows adoption succeeds while C4 is withheld in both C and N. The critical bypass/leak cell `E-X+` shows execution path open but F not adopted and C4 not emitted in both C and N.

## Per-model first-divergence layers

| Model | E+ vs E- at fixed X+ | X+ vs X- at fixed E+ |
|---|---|---|
| C | first divergence at L2 (adoption) | first divergence at L4/L5 (execution gate → emission) |
| N | first divergence at L2 (adoption) | first divergence at L4/L5 (execution gate → emission) |

## Observations

### C vs N minor difference at E-X+

Model C reports `execution_gate.status = "ELIGIBLE"` (no premises adopted; path technically eligible but empty).
Model N reports `execution_gate.status = "INELIGIBLE"` (interprets eligibility as requiring adopted premises; none exist).
This does not affect the primary comparison at L2 (adoption) or L5 (C4 emission). Both models correctly show adoption = false and C4 not emitted.

### Provenance

No cell in either model declared `used_model_prior = true` or `used_visible_but_nonadopted_F = true` in a way that contradicts the emitted behavior. In `E-` cells, both models correctly declared F visible but not adopted, and C4 was not emitted.

## Interpretation

The behavioral matrix supports:

```text
A_epistemic
    ↓
A_execution
```

as behaviorally separable and ordered in the tested prompt-only frame. This is not a proof of the philosophical two-layer model; it is a falsifiable behavioral contrast that both C and N replicate.

## Adjudication

Per the frozen adjudication matrix (§9 of the design document), the result is:

```text
ORDERED_SEPARATION_SUPPORTED
```

because C and N both match the four expected signatures across all 8 cells.
