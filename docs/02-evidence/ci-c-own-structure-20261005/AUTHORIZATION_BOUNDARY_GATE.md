# Authorization Boundary Gate

Date: 2026-10-05  
Status: `BRAKE_FROZEN · QUESTION_REGISTERED · NO_NEW_RUN · NO_846_MAPPING`

## 1. Current candidate

After the A/C/N discrimination, the stable expression is no longer:

```text
K2 + K3
```

or:

```text
K3 atom
```

The current candidate is:

> **Authorized Relational Executable Structure**

Abbreviation here: `ARES`.

The evidence supports this separation:

```text
K3_DELETED
K1/K2 still present
        ↓
C4 absent

K3_PRECOMPUTED_F
explicit K3 absent, higher-level result present
        ↓
C4 preserved
```

So the recurring requirement is the **function**, not a particular representation.

## 2. New brake question

Before further decomposition, separate:

```text
R = relational executable admissibility function
A = authorization / admissibility boundary
C4 = continuation decision
```

The question is no longer:

> “Is K1 or K2 necessary?”

It is:

> **Is authorization external to the Information structure, or part of the executable structure that makes continuation possible?**

## 3. Three competing readings

### H-A1: Authorization is external evaluation policy

```text
R independently produces C4.
A only decides whether humans accept the path.
```

Prediction: an unauthorized but semantically sufficient path is execution-equivalent; only audit status changes.

### H-A2: Authorization is a parameter to R

```text
A selects which inferences, sources, or precomputed results R may consume.
R then produces C4.
```

Prediction: the same R and components can yield different C4 when A changes.

### H-A3: Authorization is constitutive

```text
A is part of the executable Information structure.
Without A, R is not an authorized admissibility function.
```

Prediction: removing or mutating A changes the execution class, not merely an audit label.

## 4. Why this matters

The A/C/N experiment already produced a methodological rule:

```text
surface correctness ≠ authorized continuation
```

A model can infer a missing relation and produce the right order. That does not mean the
missing Information was present. It means the model recovered the surface result by an
unauthorized path.

Therefore, future minimization cannot ask only:

> “Was the final answer correct?”

It must ask:

> “Could this continuation be produced inside the authorized Information boundary?”

Otherwise model priors, task priors, and pattern completion will silently restore missing
structure.

## 5. Minimal future discrimination design

Do not run yet. Register only.

| Arm | R | A | Precomputed F | Question |
|---|---:|---:|---:|---|
| `A+R` | present | authorized | absent | baseline executable function |
| `A+no-R` | absent | authorized | absent | reconfirm R necessity |
| `no-A+R` | present | unauthorized/speculative | absent | can authorized R become policy-failing when A changes? |
| `A+trusted-F` | absent or archival | authorized | trusted | precomputed function preserves C4 |
| `no-A+untrusted-F` | absent or archival | unauthorized | same F content, untrusted | does identical F content survive only when A changes? |

Key comparison:

```text
A + trusted F
versus
no-A + untrusted F with identical F content
```

If only audit wording differs, `A` is probably external policy.  
If execution class changes, `A` is part of the functional structure.

## 6. Boundary

No new model run.  
No K1/K2 decomposition.  
No Observer.  
No InformationCore write.  
No 846 mapping, merge, deletion, or rewrite.  
No claim that ARES is a general Information Core.
