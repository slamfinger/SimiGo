# Local Closure M-Candidate Reduction Worksheet

Date: 2026-10-04  
Status: `STATIC REDUCTION WORKSHEET / NO EXECUTION / NO MINIMALITY CLAIM`  
Baseline: candidate map at `3a46e0e`

## 1. Scope

This worksheet decomposes the three current candidates:

```text
M1 = service baseline facts;
M2 = service-pair compatibility facts;
M3 = provenance / execution binding.
```

It does not define a new schema, API, mechanism, or final Information structure.
It does not run Observer, store Candidate Information, or start Execution B.

## 2. Current candidate graph

```text
M1  baseline facts
M2  pair compatibility facts
      ↓
current release-gate continuation

M3  provenance / execution binding
      ↓
accountability, reproducibility, validity checking
```

The current narrow continuation hypothesis is:

```text
M1 + M2
      ↓
B release-gate decision
```

The broader accountable hypothesis is:

```text
M1 + M2 + M3
      ↓
B release-gate decision
      +
historical binding / auditability
```

## 3. M1 decomposition

M1 currently contains these observable parts:

```text
M1.a service-id set:
     alpha, beta, gamma;

M1.b baseline predicates:
     alpha  = baseline-compatible;
     beta   = baseline-compatible;
     gamma  = not baseline-compatible;

M1.c baseline issue statements:
     gamma lacks true metrics_v2;
     gamma schema_version is within limit but flag check fails;

M1.d source-file binding:
     which configuration files and baseline produced these facts;

M1.e audit scope:
     compatibility against the given platform baseline.
```

## 4. M2 decomposition

M2 currently contains:

```text
M2.a pair-id set:
     alpha ↔ beta;
     alpha ↔ gamma;
     beta ↔ gamma;

M2.b pair compatibility predicates:
     alpha ↔ beta  = compatible;
     alpha ↔ gamma = incompatible;
     beta ↔ gamma  = incompatible;

M2.c pair issue causes/statements:
     gamma baseline issue where relevant;
     API version mismatch;
     port conflict;

M2.d source/audit binding:
     which configuration set and audit produced these pair judgments.
```

## 5. M3 decomposition

M3 currently contains:

```text
M3.a Execution A run identity:
     20261004-152303;

M3.b producer/backend binding:
     SimiGo HTTPServer → NativeMLX;
     peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX;

M3.c task-carrier binding:
     TC-A configuration compatibility audit;

M3.d source-set binding:
     hashes of platform baseline and three service configs;

M3.e result binding:
     hash of Execution A final answer;

M3.f tool evidence:
     four read_file calls and their outputs;

M3.g temporal/Runtime evidence:
     run time and Runtime lifecycle/cache observations.
```

## 6. Deletion / replacement tests

### T-M1-all — delete all of M1, retain M2

Likely effect:

```text
B may still know that gamma has incompatible pairs;
B may still avoid some gamma coexistence;
B loses the specific fact that gamma itself is not baseline-compatible;
B cannot distinguish baseline failure from API/port mismatch.
```

Current-task reading:

```text
release order alpha → beta may survive;
blocking gamma may survive through pair incompatibility;
baseline-specific blocking explanation is lost.
```

This tests whether M1 is necessary beyond M2.

### T-M1-gamma — delete only gamma baseline fact

Likely effect:

```text
B can still see gamma-involving pair incompatibilities;
B may still block gamma;
B loses the narrow reason “gamma is not baseline-compatible”.
```

Current-task reading:

```text
deployment decision may survive;
baseline-specific explanation is lost.
```

This separates decision sufficiency from explanation sufficiency.

### T-M1-alpha-beta — delete alpha/beta baseline facts, retain gamma

Likely effect:

```text
current release decision may survive;
future reasoning about why alpha and beta are individually acceptable is lost.
```

This separates current-task sufficiency from broader audit value.

### T-M1-recompute — replace M1 with source configs and recomputation

Effect:

```text
B may recover baseline facts,
but only by redoing an A-like compatibility audit.
```

This is not mere Information projection. It converts continuation into
recomputation.

### T-M1-assert — replace M1 with “gamma is blocked”

Effect:

```text
may suffice for this narrow release task;
does not preserve the general baseline-audit structure.
```

This would test task-local shortcut value, not Information minimality.

### T-M2-all — delete all of M2, retain M1

Likely effect:

```text
B knows gamma is not baseline-compatible;
B does not know whether alpha and beta can coexist;
B may overblock alpha/beta or fail to justify the release order.
```

Current-task reading:

```text
safe alpha → beta deployment is not supported by M1 alone.
```

### T-M2-pair-decision — retain only pair decisions, delete issue causes

Likely effect:

```text
B can still decide:
alpha ↔ beta allowed;
gamma incompatible with both;
B loses why those pair judgments hold.
```

Current-task reading:

```text
decision survives;
audit explanation does not.
```

### T-M2-recompute — replace M2 with source configs and recomputation

Effect:

```text
B may recover pair compatibility,
but only by redoing an A-like derivation.
```

Again, this is recomputation, not simple projection.

### T-M3-all — delete all of M3, retain M1 + M2

Likely effect:

```text
B may still complete the narrow release-gate decision;
the result loses historical binding:
who produced it,
in which Execution,
from which source hashes,
with what tool evidence.
```

Current-task reading:

```text
semantic continuation may survive;
accountability and reproducibility do not.
```

This is the key test separating semantic sufficiency from provenance necessity.

### T-M3-execution-identity — delete only Execution A identity

Likely effect:

```text
narrow release decision may survive;
the result can no longer be tied to a specific Execution A.
```

This separates task continuation from historical attribution.

### T-M3-source-hashes — delete source-set hashes

Likely effect:

```text
current decision may survive;
B cannot detect whether the audited configuration later changed.
```

This separates immediate continuation from stale-Information detection.

### T-M3-tool-evidence — delete read_file evidence

Likely effect:

```text
current decision may survive;
verification that A actually inspected the sources is lost.
```

This separates task output from execution-process evidence.

### T-M3-result-hash — delete final-answer/result hash

Likely effect:

```text
current decision may survive;
integrity verification of the fetched residue is lost.
```

### T-M3-backend-model — delete backend/model binding

Likely effect:

```text
current decision may survive;
reproduction and backend-specific trust reasoning are lost.
```

### T-M3-task-carrier — delete TC-A scope binding

Likely effect:

```text
facts remain syntactically readable;
B cannot know they were produced for this compatibility-audit scope.
```

### T-M3-trusted-assert — replace M3 with “this came from a trusted A”

Effect:

```text
may support continuation;
removes the ability to independently check source, execution, and result
binding.
```

This tests trust-shortcut value, not provenance minimality.

## 7. Provisional current-task core

For the narrow TC-A release-gate task, the smallest currently visible semantic
core hypothesis is:

```text
M2 pair decisions:
    alpha ↔ beta compatible;
    gamma pairs incompatible;

plus

M1 gamma baseline fact:
    gamma is not baseline-compatible.
```

This core can support:

```text
allow alpha and beta to proceed together;
block gamma;
explain gamma blocking by baseline and/or pair incompatibility.
```

It probably does not require:

```text
alpha/beta baseline facts;
detailed issue wording;
Execution A identity;
tool-call evidence;
Runtime trace;
backend/model binding.
```

Those may still be necessary for audit, reproducibility, trust, stale-state
detection, or broader future tasks.

## 8. Provisional durable-audit core

For a broader durable-audit hypothesis, the current visible core is larger:

```text
M1 full baseline predicates and source binding;
M2 full pair predicates, issue causes, and source binding;
M3 source hashes, result hash, Execution A identity,
   backend/model binding, tool evidence, task-carrier scope.
```

This is not declared minimal. It is the smallest currently visible set needed to
preserve not only the release decision but also:

```text
why the decision holds;
which sources produced it;
which Execution produced it;
whether it remains valid.
```

## 9. Reduction questions carried forward

```text
Can M1 be derived from source configs by B without redoing an A-like audit?
Can M2 be derived from source configs by B without redoing an A-like audit?
Can M1 gamma be derived from M2 gamma-pair incompatibilities?
Can M2 be reconstructed from M1 plus deployment rules?
Can current-task success survive deletion of all M3?
Can durable auditability survive deletion of parts of M3?
Which M3 parts are provenance, which are trust shortcuts,
and which are stale-state detection?
```

## 10. First B compression amendment

The provisional `M2.b + M1.b(gamma)` core is downgraded to a candidate
hypothesis. Because the current B task already asks B to allow alpha/beta and
block gamma, smaller decision-only residue may complete the same task.

The first B panel is therefore narrowed to:

```text
S-B0 no prior A residue;
S-B1 M1.b(gamma) + M2.b(pair decisions);
S-B2 decision-only compression.
```

See:

```text
docs/00-governance/SIMIGO_LAB_LOCAL_CLOSURE_FIRST_B_COMPRESSION_PANEL_20261004.md
```

No field, group, or binding is declared irreducible. No S-B0/S-B1/S-B2
condition is authorized. No Observer repair, store, or Execution B is performed.
