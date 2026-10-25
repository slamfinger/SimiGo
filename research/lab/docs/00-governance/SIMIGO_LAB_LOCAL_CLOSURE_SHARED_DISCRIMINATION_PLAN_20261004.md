# TC-A Shared Discrimination Plan

Date: 2026-10-04  
Status: `REGISTERED / SHARED DISCRIMINATION PLAN ONLY / CONDITION INSTANTIATION NOT AUTHORIZED / EXECUTION NOT AUTHORIZED`

## 1. Purpose

This plan compresses dependency hypotheses D1–D10 into a small set of shared
discriminating interventions. It does not select U1–U5, define Information,
instantiate B0/B1/B2, modify InformationCore, add RuntimeMemory or
RelationCore, or implement projection.

The question is:

```text
Which few interventions can separate the largest number of
closure-dependency hypotheses without smuggling in an answer?
```

## 2. Fixed frame

All future interventions, if authorized, must preserve:

```text
carrier             = TC-A configuration audit → release gate;
backend             = SimiGo HTTPServer → NativeMLX;
route fix           = SimiGo source commit 82b57f6;
model               = peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX;
fresh B context     = required;
A → B transcript/summary/result transfer = forbidden;
NativeMLX cache/prefix isolation = required;
InformationCore     = existing store/fetch boundary unchanged;
schema              = unchanged;
RelationCore        = not invoked;
RuntimeMemory       = not added;
search/list/query   = absent;
automatic projection = absent.
```

## 3. Shared interventions

These are analytical interventions, not authorized executions.

### I-R — Representation substitution

Keep the semantic register meaning stable while changing its representation:

```text
L1 raw model residue / JSON string literal;
L2 unwrapped JSON text;
L3 parsed object rendered back to stable text.
```

Discriminates:

```text
D1  Representation ↔ Persistence unit;
D2  Identity ↔ Representation;
D5  Retrieval ↔ Semantic reconstruction;
part of U1 versus U2.
```

Key question:

```text
Does continuation depend on the semantic register,
or on one incidental representation?
```

### I-L — Locator / access manipulation

Keep Candidate Information fixed while changing only access:

```text
no identity;
non-A sentinel identity;
correct Stored Information identity.
```

Discriminates:

```text
D3  Identity ↔ Locator;
D4  Locator ↔ Retrieval;
semantic sufficiency versus discoverability.
```

Key question:

```text
Is failure caused by missing semantic structure,
or by missing access to otherwise sufficient structure?
```

### I-P — Persistence-unit decomposition

Keep the same audit semantics while changing persistence granularity:

```text
whole compatibility register;
service baseline facts only;
pair compatibility facts only;
facts + pair facts;
facts + relations/provenance, if later justified.
```

Discriminates:

```text
D1  Representation ↔ Persistence unit;
whether register-like, fact-like, relation-like,
or combined structure is needed;
part of U2 / U3 / U4.
```

Key question:

```text
Is the sustainable unit the whole audit,
individual facts, pairwise relations, or a combination?
```

### I-S — Reconstruction probe

After fetch but before the release decision, ask B to reconstruct the relevant
register without opening source files.

Discriminates:

```text
D5  Retrieval ↔ Semantic reconstruction;
D6  Semantic reconstruction ↔ Task projection;
fetched versus parsed versus semantically reconstructed.
```

Key question:

```text
Can B reconstruct audit semantics from Stored Information,
independent of immediately solving the release task?
```

### I-T — Task projection shift

Keep Stored Information fixed while changing only the release request or
constraints.

Examples for later design, not selected:

```text
different candidate service set;
different deployment constraints;
different blocked-service policy;
different ordering requirement.
```

Discriminates:

```text
D6  Semantic reconstruction ↔ Task projection;
D7  Task projection ↔ Adoption;
ready-to-use Information versus stable semantic material
requiring task-specific projection.
```

Key question:

```text
Is Stored Information already task-ready,
or must each task project it into a new working context?
```

### I-A — Adoption counterfactual

Include material that is present but irrelevant to the current release
decision.

Discriminates:

```text
D7  Task projection ↔ Adoption;
D8  Adoption ↔ Behavioral effect;
mere fetch versus actual adoption.
```

Key question:

```text
Does B distinguish relevant Stored Information from merely fetched
Information?
```

## 4. High-yield ordering

If later authorized, the first analytical ordering would be:

```text
1. B0 negative control;
2. correct-locator condition;
3. locator deletion / sentinel substitution;
4. representation substitution;
5. persistence-unit decomposition;
6. reconstruction probe;
7. task projection shift;
8. adoption counterfactual.
```

This is not an execution authorization. It is a priority ordering for future
condition design.

## 5. Interpretation discipline

Each intervention must preserve separate readings:

```text
located;
fetched;
parsed;
semantic-referenced;
adopted;
behavioral;
continuation;
gain.
```

No single success may be reported as:

```text
Information works
```

without stating which layer changed.

## 6. Candidate conclusions that would matter

Examples of meaningful outcomes:

```text
B2 succeeds only with L3, not L1
      → continuation depends on representation.

B2 succeeds with correct identity but fails without it
      → Locator is not merely Identity.

Whole register succeeds but separate facts fail
      → persistence unit is register-like.

Separate facts succeed and whole register adds nothing
      → register-like persistence is redundant.

Reconstruction fails despite successful fetch
      → Retrieval and Semantic reconstruction are distinct.

Changed release constraints alter B's use of the same register
      → Task projection is independent of Storage.

Irrelevant Stored Information is fetched but not adopted
      → fetch and Adoption are distinct.
```

All outcomes, including surprising ones, are valid.

## 7. Non-goals

```text
No selection among U1…U5;
no Information schema;
no InformationCore API change;
no RuntimeMemory;
no RelationCore integration;
no search/list/query implementation;
no automatic projection;
no bridge implementation;
no prompt or task-file creation;
no B0/B1/B2 execution.
```
