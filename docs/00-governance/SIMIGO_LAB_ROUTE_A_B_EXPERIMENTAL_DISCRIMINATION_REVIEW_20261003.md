# Route A vs Route B Experimental Discrimination Review

Date: 2026-10-03  
Status: `REVIEW SEALED / ROUTE A DEFERRED / ROUTE B DEFERRED`  
Evidence anchor: `R-C1 #4 = CLOSED / VALID / EVIDENCE PRESERVED`  
Scope: research discrimination only. No implementation, experiment authorization,
C-Spec, C-Design, Core, PALACE, or evaluator change.

## 1. D1 — Explanations excluded by R-C1 #4

R-C1 #4 validly established:

```text
C-A  Execution State only
    → X-1 PASS; X-2…X-5 FAIL

C-B  Execution State + Persistent Information
    → X-1…X-5 PASS

C-C  Execution State + Information + Relation
    → X-1…X-5 PASS
```

Therefore the following explanation is excluded for this task / harness /
lifecycle slice:

```text
Execution State alone is sufficient for full continuation.
```

R-C1 #4 does not exclude:

```text
Relation has an independent continuation role.
Information sufficiency generalizes beyond this task.
```

## 2. D2 — Remaining competing explanations

Two explanations remain open:

### Hypothesis I — Information sufficiency

```text
Execution State + sufficient Persistent Information
    → Continuation
```

Under this explanation, Relation is only one way to organize Information and
may have no irreducible continuation role.

### Hypothesis II — Relation-dependent adoption

```text
Execution State + Persistent Information
+ an irreducible Relation relation
    → lawful Continuation
```

Under this explanation, some continuations cannot be judged from independent
facts alone; lawful adoption requires a Relation between settled results.

## 3. D3 — Route A discrimination target

Route A is an `INFORMATION-COMPLEXITY PROBE`.

It tests whether the O1 Information dependency remains observable when
continuation depends on a larger history of settled facts:

```text
Past execution
    → multiple settled facts
    → Persistent Information
    → fresh Execution State
    → Continuation
```

Possible outcomes:

```text
Information-only PASS
  strengthens the bounded Information-dependency observation.

Information-only FAIL
  inconclusive without further decomposition.
```

A Route A failure cannot by itself distinguish:

```text
insufficient Information content
insufficient Information organization
need for Relation
missing Execution State dimension
```

## 4. D4 — Route B discrimination target

Route B is a `RELATION-DISCRIMINATION PROBE`.

It directly tests whether a continuation can require a Relation that cannot be
replaced by independent Information facts.

Target contrast:

```text
C-B = Information present, Relation absent
C-C = Information present, Relation present

Continuation lawfully requires Relation(S1, S0)
```

The ideal discriminating outcome would be:

```text
C-B = FAIL
C-C = PASS
```

Only that pattern can move `O2` from:

```text
Relation additional capability = NOT OBSERVED
```

toward:

```text
Relation-dependent continuation = OBSERVED
```

## 5. D5 — Route B confounders

The primary confounder is Information equivalence.

Route B must not merely withhold Relation from C-B. The C-B Information set must
be equivalence-tested so that it contains the same substantive facts needed to
describe the states, while lacking only the Relation carrier / adoption
condition.

Required controls:

```text
same task
same state snapshots
same lifecycle
same physical overwrite evidence
same continuation question
same evaluator
same forbidden-channel checks
same fresh-process separation

C-B Information may contain S0 and S1 facts.
C-B must not contain a Relation carrier / adoption condition.
C-C contains the same Information plus Relation.
```

If C-B is artificially impoverished, the result cannot distinguish Relation
necessity from information deprivation.

## 6. D6 — What would count as real discrimination

A valid Route B discrimination requires:

```text
1. Information-equivalence audit passes.
2. C-B = FAIL or incomplete for the Relation-requiring judgment.
3. C-C = PASS using the Relation carrier.
4. C-C carrier read trace proves Relation → endpoint Information use.
5. No fallback to independent S0/S1 pointers in C-C.
6. No semantic substitution or answer injection.
7. Lifecycle, physical overwrite, and evidence separation remain valid.
```

Then the bounded conclusion may be:

```text
Relation-dependent continuation = OBSERVED
```

still limited to the task, harness, lifecycle slice, and Information-equivalence
definition.

## 7. D7 — What would remain inconclusive

The following outcomes would not prove Relation necessity:

```text
C-B PASS and C-C PASS:
  Relation additional capability remains NOT OBSERVED.

C-B FAIL and C-C FAIL:
  task may be impossible or under-specified.

C-B FAIL and C-C PASS without equivalence audit:
  Relation benefit cannot be separated from Information deprivation.

Any fallback, semantic substitution, or runtime repair:
  execution becomes INVALID / INCONCLUSIVE.
```

## 8. D8 — Route status

```text
Route A = DEFERRED / INFORMATION-COMPLEXITY PROBE
Route B = DEFERRED / RELATION-DISCRIMINATION PROBE
Selected route = NONE
Next gate = separate experimental-design review for the selected route
```

No route may be implemented or executed without a new design, audit, and human
authorization.

## 9. Current unresolved question

```text
Is Relation an independent continuation requirement,
or can all required continuation semantics be represented
as Persistent Information alone?
```

This is the precise unknown left by R-C1 #4.
