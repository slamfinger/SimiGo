# R1 — Historical Evidence Review: IPAC / IAC / P

Date: 2026-10-03  
Status: `R1 COMPLETE / HISTORICAL REVIEW SEALED / NO NEW THEORY / NO EXPERIMENT`  
Authorized question:

```text
What did prior IPAC / IAC minimality research actually establish,
what did it not establish, and what was the precise historical meaning of
“P may be carried / compensated by A”?
```

This review reopens prior records as historical evidence only. It does not
create a new IPAC definition, does not alter R-C1 #4, and does not authorize
Route A/B/C or any experiment.

## 1. Sources reviewed

```text
SIMIGO_LAB_IPAC_MINIMALITY_CRITERIA_20261001.md
SIMIGO_LAB_GDELTA_DESIGN_PREREGISTRATION_20261001.md
SIMIGO_LAB_GDELTA_EXECUTION_RESULTS_20261001.md
SIMIGO_LAB_GDELTAR_FORMALIZATION_GATE_20261002.md
SIMIGO_LAB_EXECUTION_STATE_CONTRACT_V1_AMENDED_20261002.md
SIMIGO_LAB_P5_4_MINIMAL_REDUCTION_DESIGN_20261001.md
```

## 2. What was actually established

### 2.1 Candidate semantic closure

Prior formalization used:

```text
ES_semantic = { I, P, A, C }
```

with role decomposition:

```text
I: carrier/model binding, source distinguishability, payload integrity
P: continuation-point assertion, boundary-integrity detection, progress ledger
A: content binding between history text and tokenization
C: lawful continuation relation for this state
```

### 2.2 G-δ / G-δR result

```text
I = necessity evidence under tested conditions
A = irreducible / necessity evidence under tested conditions
C = irreducible / necessity evidence under tested conditions
P = semantic member retained, but representation-dependent
```

Carrier-specific detail:

```text
R_llama full-prefix token-array:
  P-2 boundary-integrity detection was compensable via A.
  P-1 continuation-point assertion was not derivable.
  P-3 progress ledger had no independent criterion.

R_MLX KV carrier:
  P-1 and P-2 were required / not compensable via A.
```

Therefore, the historical phrase:

```text
P may be carried / compensated by A
```

must be narrowed to:

```text
In the tested full-prefix anchor representation, A compensated P-2
boundary-integrity detection.
```

It does **not** mean:

```text
P was redundant;
P-1 or P-3 was compensated;
P’s whole continuation role was representable by A;
P is globally reducible to A across representations.
```

### 2.3 I/A/C status

Historical evidence supported necessity for I/A/C under tested conditions, but
did **not** establish mathematical minimality, backend-independent minimality,
or a complete role taxonomy.

The later formal wording became representation-aware:

```text
Irreducibility is a (relation, representation) property.
```

## 3. What was not established

```text
1. {I,P,A,C} as a mathematically minimal set.
2. Backend-independent minimality.
3. That P is globally redundant.
4. That P is wholly representable by A.
5. That A can satisfy P-1 / P-3 in all representations.
6. That I/A/C are the final semantic primitives.
7. A complete Role(X) taxonomy for every relation.
8. The full set of continuation-invariant-required functions.
9. Sufficiency of registered Rules_R for all future representations.
```

## 4. R1 answer to the P question

```text
P1 = P redundant
    NOT ESTABLISHED
    Rejected as a general historical reading.

P2 = P semantics representable by A
    PARTIAL / CARRIER-SPECIFIC
    Only P-2 was compensable by A in the tested full-prefix representation.

P3 = P continuation role satisfiable by A
    NOT ESTABLISHED AS A WHOLE
    Only P-2 was carrier-specifically compensable; P-1/P-3 were not.

P4 = Historical evidence insufficient for a global decision
    YES
    Prior evidence supports only a representation-aware, bounded reading.
```

## 5. R1 conclusion

```text
Historical evidence establishes necessity evidence for I/A/C and
carrier-dependent compensation for part of P.

It does not establish IPAC minimality, IPAC semantics, or a global
Information-only sufficiency claim.

R1 = COMPLETE
R2 remains blocked pending explicit Human instruction.
```
