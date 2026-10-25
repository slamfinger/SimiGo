# CI-C Decomposition Plan

Status: `DECOMPOSITION_CANDIDATE_SELECTED · OWN_STRUCTURE_ONLY · NO_846_MAPPING`

## 1. Phenomenon

CI-C is not “two strings happen to coexist.”  
CI-C is:

> Two or more information components enter a relation; that relation produces a function which neither component produces alone.

In TC-A this appears as:

```text
individual compatibility predicate
        +
pair coexistence relation
        ↓
admissible deployment order / blocked list
```

## 2. Controlled Round-1 evidence

| Arms | Individual predicate A | Pair relation B | Result |
|---|---:|---:|---|
| A only | present | absent | FAIL |
| B only | absent | present | FAIL |
| A + B | present | present | PASS |

Refinement:

```text
gamma-specific A + B = PASS
full alpha/beta/gamma A + B = PASS
```

So the necessary A is context-bounded to the blocker predicate, not necessarily the full individual-compatibility list.

## 3. Cross-model / cross-sample recurrence

The phenomenon is required in 4/4 samples:

| Sample | Relation formed by the task |
|---|---|
| S1 | individual eligibility × pair compatibility × order |
| S2 | versioned claim × source location × authority choice |
| S3 | header × physical units × formula dimension |
| S4 | row × column × arithmetic relation |

In the usable A/C matrix:

```text
attempted        = 8/8
adequately formed = 6/8
A failures       = S1 formed but misapplied; S3 weak relation
```

Thus CI-C is a priority decomposition candidate, not a confirmed full cross-model invariant.

## 4. Own-structure decomposition

### C1 — Component A

An independently supplied component.

TC-A example:

```text
gamma is not individually baseline-compatible
```

Question: is the full component necessary, or only a discriminating predicate?

### C2 — Component B

A relation over components.

TC-A example:

```text
alpha ↔ beta  = allow
alpha ↔ gamma = block
beta ↔ gamma  = block
```

Question: does B add a function beyond listing A-type facts?

### C3 — The relation itself

The join structure:

```text
service-id → individual predicate
service-pair → coexistence predicate
candidate-order → admissibility
```

Question: is the relation load-bearing, or only a packaging of C1/C2?

### C4 — Combined function

The emergent task function:

```text
select admissible ordered continuation
while preserving blocked/incompatible boundary
```

Question: does C4 disappear when C3 is removed even if C1/C2 remain?

## 5. Verification design, not execution

Minimal tests should delete or substitute one part at a time:

```text
C1 only
C2 only
C1 + C2 without C3
C1 + C2 + C3
C3 substituted by precomputed C4
```

A CI-C own-structure claim survives only if the relational join changes the observable function, not merely the wording.

## 6. Boundary

No 846 atom is opened, mapped, merged, or deleted.  
No full cross-model stability claim is made.  
No minimal Information Core is declared.
