# Local Closure Candidate Reducibility Map

Date: 2026-10-04  
Status: `STATIC ANALYSIS SEALED / NO EXECUTION / NO REDUCIBILITY CLAIM`

## 1. Scope

This record maps likely reduction relations among the TC-A candidate units:

```text
U1 = raw model residue;
U2 = semantic register;
U3 = service baseline facts;
U4 = service-pair compatibility facts;
U5 = provenance / execution context.
```

It does not execute B0/B1/B2, modify InformationCore, add a bridge, or declare
any unit irreducible.

## 2. Observed decomposition

Execution A's exact final answer was a JSON string literal containing escaped
JSON text. After one JSON decode it became a JSON string; after a second JSON
decode it became the compatibility-register object.

```text
U1 exact bytes
      ↓ JSON string decode
U2t register text
      ↓ JSON object decode
U2o register object
      ↓ projection
U3 service baseline facts
U4 service-pair compatibility facts
```

U5 is not produced by this representation chain alone. It concerns producer,
Execution A identity, source identities, tool calls, phase, Runtime evidence,
and task-carrier binding.

## 3. Reduction arrows

| Arrow | Static reading |
|---|---|
| `U1 → U2t` | Information-preserving JSON string decode. |
| `U2t → U2o` | Information-preserving JSON object decode. |
| `U2o → U3` | Direct projection of service baseline facts. |
| `U2o → U4` | Direct projection of service-pair compatibility facts. |
| `U3 + U4 → U2o` | Semantic reconstruction is possible if register version, service order, pair order, and issue details are preserved. |
| `U2o → U2t'` | Semantic re-serialization is possible, but not exact byte recovery. |
| `U2t' → U1'` | Equivalent string-literal wrapping is possible, but not exact byte recovery. |
| `U1 → U5` | Weak/partial. Exact U1 does not carry producer, run identity, Runtime trace, source hashes, or task-carrier binding. |
| `U5 → U1/U2` | Weak/partial. Provenance can locate or validate residue only if it includes or points to the residue artifact; it does not semantically entail the compatibility register. |

## 4. Reversibility reading

```text
U1 → U2t → U2o
```

is semantically reversible in the forward direction.

```text
U2o → U2t' → U1'
```

can produce an equivalent residue, but not the exact original bytes unless the
same serialization, escaping, key ordering, whitespace, and outer string-literal
conventions are frozen.

Therefore:

```text
U1 is not semantically independent of U2;
but exact U1 is not recoverable from U2 alone.
```

## 5. Register decomposition reading

```text
U2o → U3 + U4
```

is a natural decomposition.

```text
U3 + U4 → U2o
```

can reconstruct the register only if these are also preserved or supplied:

```text
register version;
service ordering;
pair ordering;
issue explanations;
the convention that these facts belong to one compatibility register.
```

If only bare compatibility booleans are kept, the semantic register is not fully
recovered.

## 6. Likely reductions

```text
U1 is probably representation-reducible to U2 at the semantic layer.
U2 is probably aggregation-reducible to U3 + U4 at the decision/fact layer.
Exact U1 is not reducible to U2 because serialization details are lost.
U2 exact issue wording is not reducible to bare U3 + U4 booleans.
```

These remain static hypotheses, not executed irreducibility results.

## 7. Likely independent candidates

```text
U3 appears independent of U4:
  service baseline status does not by itself entail pair compatibility.

U4 appears independent of U3:
  pair compatibility does not by itself entail each service's baseline status.

U5 contains an independent provenance/context candidate:
  producer, Execution A identity, source identities, tool-call sequence,
  Runtime evidence, and task-carrier binding are not derivable from the
  compatibility register alone.
```

## 8. Possible minimal candidates

The static map suggests three future candidates, not conclusions:

```text
M1  service baseline facts;
M2  service-pair compatibility facts;
M3  provenance / source / execution binding.
```

The whole register may be only one aggregation or representation of
`M1 + M2`, with `M3` remaining a separate historical-binding candidate.

## 9. High-value future arrows

If later authorized, the sharpest discriminative arrows would be:

```text
A1  U1 versus U2 representation substitution;
A2  whole register versus U3 + U4 decomposition;
A3  issue wording versus bare compatibility booleans;
A4  with provenance versus without provenance;
A5  same U3 + U4 but changed release constraints.
```

These would test representation, aggregation, explanation, provenance, and task
projection separately.

## 10. Boundary

No unit is declared irreducible. No B0/B1/B2 condition is authorized. No
InformationCore, RelationCore, RuntimeMemory, search, projection, or bridge
mechanism is designed.
