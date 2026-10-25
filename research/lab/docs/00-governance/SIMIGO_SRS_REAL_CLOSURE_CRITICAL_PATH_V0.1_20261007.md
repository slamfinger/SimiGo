# SRS Real Closure Critical Path v0.1

> **Status:** ACTIVE RESEARCH CRITICAL PATH V0.1
> **Date:** 2026-10-07
> **Parent direction:** `SIMIGO_RESEARCH_FOCUS_REORIENTATION_20261007.md`
> **Frozen governance basis:** SRS-VAL Design v0.8; Authorization Package v0.6; Manifest Contract v1.0
> **Implementation / fixture / execution / IS mutation:** NOT AUTHORIZED

## 1. Core claim under test

```text
ES₁
  ↓
persistent SRS in Information Space
  ↓
independent ES₂ resolves and validates SRS
  ↓
SRS-VAL = REUSE
  ↓
ES₂ continues using the settled result
  ↓
ES₁'s expensive computation is not repeated
```

Current truth value:

```text
NOT ESTABLISHED
```

## 2. Positive milestones

### SRS-01 — ES₁ produces and settles SRS

```text
STATUS = NOT ESTABLISHED
```

Required meaning:

```text
ES₁ performs real work;
the result/relation/dependencies/provenance are settled;
the settlement satisfies SRS-SEM-01 semantic bindings.
```

### SRS-02 — SRS is persistently materialized in Information Space

```text
STATUS = NOT ESTABLISHED
```

Required meaning:

```text
SRS is not only a local object in ES₁;
it is recoverable from Information Space by an independent consumer.
```

### SRS-03 — independent ES₂ resolves and validates SRS

```text
STATUS = NOT ESTABLISHED
```

Required meaning:

```text
a fresh ES₂ resolves the persisted SRS;
validates identity, dependencies, result, provenance, lifecycle, and freshness;
runs SRS-VAL without importing ES₁ memory or transient state.
```

### SRS-04 — ES₂ legitimately reuses the settled result

```text
STATUS = NOT ESTABLISHED
```

Required meaning:

```text
SRS-VAL returns REUSE;
ES₂ consumes the settled result under its exact bindings;
the continuation is lawful and semantically bounded.
```

### SRS-05 — evidence establishes no silent recomputation

```text
STATUS = NOT ESTABLISHED
```

Required meaning:

```text
external evidence shows ES₁'s expensive computation did not recur;
REUSE branch was actually taken;
observed reads/effects match the declared reuse path.
```

## 3. Negative milestones

### SRS-N1 — dependency mutation

```text
STATUS = REQUIRED TEST
```

Expected:

```text
dependency mutation must produce BLOCK,
or lawful RECOMPUTE only under exact I-14/envelope authorization.
```

### SRS-N2 — relation / semantic binding mutation

```text
STATUS = REQUIRED TEST
```

Expected:

```text
relation or semantic binding mutation must not silently REUSE.
```

### SRS-N3 — freshness / validity failure

```text
STATUS = REQUIRED TEST
```

Expected:

```text
freshness or validity failure must BLOCK,
unless an exact lawful RECOMPUTE path exists.
```

## 4. Milestone dependency

```text
SRS-01
  → SRS-02
  → SRS-03
  → SRS-04
  → SRS-05
```

No milestone may be marked established by analogy, documentation, infrastructure
correctness, or output equality alone.

## 5. Minimum first experiment

The first experiment must remain minimal:

```text
ES₁
  ↓
settled result
  ↓
SRS
  ↓
IS persistence
  ↓
fresh independent ES₂
  ↓
resolve SRS
  ↓
SRS-VAL = REUSE
  ↓
continue
```

Plus at least one negative:

```text
dependency changed → must not REUSE.
```

## 6. Primary evidence requirement

The main proof is not:

```text
ES₂ final output == ES₁ final output.
```

The main proof must establish:

```text
ES₂ consumed the persisted SRS;
SRS identity matched;
dependency bindings matched;
SRS-VAL classified correctly;
REUSE branch was actually taken;
ES₁ expensive computation did not silently recur.
```

## 7. Current permission boundary

```text
Implementation       NOT AUTHORIZED
Fixture preparation  NOT AUTHORIZED
Execution            NOT AUTHORIZED
IS mutation          NOT AUTHORIZED
SimiGo code change   NOT AUTHORIZED
```

These remain separate Human authorization decisions.
