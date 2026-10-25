# Local Closure Axis Reduction and Observational Refinement

Date: 2026-10-04  
Status: `REGISTERED / ANALYTICAL REFINEMENT ONLY / NO EXECUTION / NO STRUCTURAL DECISION`

## 1. Purpose

The registered stage decomposition is observational, not architectural. Its
eleven axes are analytical knives, not eleven Runtime layers.

The current task is to continue asking whether each axis can be reduced,
merged, split, or reclassified. No reduction or irreducibility claim is made
here.

## 2. Core discipline

Two evidence lines must proceed together:

```text
Evidence chain:
  preserves what actually happened.

Structural decomposition:
  continues asking which distinctions are necessary.
```

The current axes are not frozen as architecture. They are frozen only as
differences that must remain observable until experiment discriminates them.

## 3. Reduction questions by axis

### Identity

```text
Same with respect to what?
In what scope are two residues the same?
What may change while identity remains stable?
What change forces a new identity?
Who or what is authorized to judge identity?
```

Candidate distinctions:

```text
object identity;
fact identity;
observation identity;
execution identity;
representation identity;
temporal state identity.
```

### Persistence unit

```text
What can exist independently?
What must exist as a group?
Can a Relation exist meaningfully after separation from its Object?
Is Provenance part of the content or an external association?
If one part is removed, does the remainder remain meaningful?
```

Candidate distinctions:

```text
atomic fact;
composite register;
audit event;
provenance attachment;
execution-local cache/evidence.
```

### Locator / selection

```text
What constraints can discover relevant material?
Is discovery deterministic or behavioral?
Is a locator unique?
Is it stable across context?
Who may create, expose, or withhold it?
```

Candidate distinctions:

```text
task locator;
sequence locator;
state locator;
source locator;
object/relation locator;
explicit identity locator.
```

### Retrieval

```text
Is one unit retrieved or a set?
Must relations be preserved during retrieval?
Is retrieval complete, projected, or partial?
What does retrieval absence mean?
What does retrieval failure mean?
```

Candidate distinctions:

```text
single-object retrieval;
set retrieval;
relation-preserving retrieval;
projection-time retrieval;
provenance-only retrieval.
```

### Semantic reconstruction

```text
What type/scope/time validity is required?
What source lineage is required?
What task context is required?
How much ambiguity is allowed?
What missing context makes reconstruction impossible?
```

Candidate distinctions:

```text
representation reconstruction;
semantic reconstruction;
task reconstruction;
provenance reconstruction.
```

### Task projection

```text
What selection rule is relevant?
How are facts, relations, and provenance combined?
How do current constraints alter the projection?
What is the working-context representation?
When is a fact irrelevant rather than missing?
```

Candidate distinctions:

```text
ready-to-use Information;
stable semantic material requiring projection;
task-local working context;
hybrid form discovered only by experiment.
```

### Adoption

```text
What observable behavior counts as adoption?
How is mere mention distinguished from causal use?
Does the result constrain a decision?
Does it eliminate an option?
Does it create a dependency?
```

Candidate distinctions:

```text
mention;
reference;
constraint;
decision dependency;
counterfactual dependency.
```

### Behavioral effect

```text
What output change is evidence of effect?
What counts as direct versus indirect effect?
Can a path change still be continuation?
Can identical output hide different continuation?
```

Candidate distinctions:

```text
decision change;
order change;
blocking change;
explanation change;
unchanged output with changed justification.
```

### Continuation

```text
Does B know A occurred?
Did B receive an A result?
Does B depend on that result?
If part is removed, can B still complete?
If B completes through another path, is that continuation?
What is the smallest observable continuation criterion?
```

Candidate distinctions:

```text
awareness;
possession;
dependence;
lawful adoption;
task completion;
continuation gain.
```

## 4. Classification questions

Each future observation should also be classified along:

```text
Execution-local versus cross-Execution;
Runtime substrate versus semantic Information;
representation versus semantic structure;
independently addressable versus context-dependent;
necessary versus convenient;
stable versus ephemeral;
directly observable versus inferred;
irreducible versus reducible.
```

No classification is decided here.

## 5. Non-goals

```text
No execution.
No B0/B1/B2 authorization.
No schema.
No API.
No RuntimeMemory.
No RelationCore integration.
No search/list/query implementation.
No automatic formation/projection.
No claim that the eleven axes are minimal.
No claim that any axis is irreducible.
```
