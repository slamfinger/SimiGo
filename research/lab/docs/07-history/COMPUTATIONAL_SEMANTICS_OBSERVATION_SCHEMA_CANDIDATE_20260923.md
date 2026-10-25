# Computational Semantics Observation Schema Candidate

**Date**: 2026-09-23  
**Status**: OBSERVATION_SCHEMA_CANDIDATE_REGISTERED / FORMALIZATION_OPEN  
**Nature**: empirical observation schema; not an Architecture 2.0 formal definition or R-INTERNAL gate

## 1. Purpose

Three external probes—Qwen3-Coder under SimiGo 1.7, Gemma 4, and
Muse-Glimmer—show that the former single word `Declaration` hides several
distinct failure surfaces. This record registers a candidate observation schema
for future Computational Semantics probes.

It does **not** promote the schema to an Architecture 2.0 formal definition, a
new semantic object, or a selected research route.

## 2. Candidate observation layers

```text
C0  Checkpoint Declaration
C1  Runtime Family Declaration
C2  Runtime Type-Routing
C3  Instantiation
C4  Execution
C5  Semantic Consistency
```

The first three layers were previously often collapsed into `Declaration`.
Muse-Glimmer shows why they must be separated: a checkpoint can declare a
concrete architecture even when the runtime family/type-routing surface does not
route that declaration to an instantiable object.

## 3. Status enum for probe records

For empirical records, each layer may use:

```text
PASS | PARTIAL | FAIL | NOT_REACHED | OPEN
```

`OPEN` is appropriate when the layer has not been formally specified or has not
been sufficiently tested. This enum is observational only; it does not define
mathematical truth predicates.

## 4. Probe coverage

| Probe | C0 Checkpoint Declaration | C1 Runtime Family | C2 Type-Routing | C3 Instantiation | C4 Execution | C5 Semantic Consistency |
| --- | --- | --- | --- | --- | --- | --- |
| Qwen3-Coder / SimiGo 1.7 | PASS | PASS | PASS | PASS | PASS | OPEN |
| Gemma 4 | PASS: `gemma4_unified` | PASS: unified route exists | PASS | PARTIAL: text-only load succeeds; unified load fails | FAIL: high-level generation fails | OPEN |
| Muse-Glimmer text tower | PASS: `muse_glimmer_text` | PARTIAL: runtime family is `muse_glimmer` | FAIL: no route for `_text` | NOT_REACHED | NOT_REACHED | OPEN |

These three cases provide minimal fracture coverage:

1. **Positive control**: Qwen3-Coder passes through routing, instantiation, and
   execution under SimiGo 1.7.
2. **Post-routing executable boundary**: Gemma 4 reaches object construction but
   fails at executable semantics.
3. **Pre-instantiation routing boundary**: Muse-Glimmer fails before object
   construction because the checkpoint declaration is not routed to the runtime
   family.

## 5. Interpretive boundary

The probes support this distinction:

```text
Declared Architecture
  ≠ Runtime Family Declaration
  ≠ Runtime Type-Routing
  ≠ Instantiable Object
  ≠ Executable Object
  ≠ Semantically Consistent Object
```

They do **not** support a general claim about all Gemma, Qwen, MoE, dense, or
MLX models. The records are probe-specific.

## 6. Relation to Architecture 2.0

The probes suggest two different questions:

```text
Structural Semantics:
  What is the model?

Computational Semantics:
  How does an external declaration become a routed, instantiable,
  executable, and semantically consistent object?
```

Architecture 2.0 may eventually need the second question as part of its formal
boundary, but this record leaves that decision open.

## 7. Boundaries

This record does not declare `(P1,θ1)`, an instance family, R-INTERNAL-20, a new
R-INTERNAL object, R_ORACLE, Δ/gap, FinLoss, NECT, an executable interface, a
harness, or an experiment. It does not select `COMPUTATIONAL_SEMANTICS` as the
next research route. It only registers a candidate schema for recording future
external observations.
