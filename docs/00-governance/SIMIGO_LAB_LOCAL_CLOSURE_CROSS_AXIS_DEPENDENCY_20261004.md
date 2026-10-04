# Local Closure Cross-Axis Dependency Analysis

Date: 2026-10-04  
Status: `REGISTERED / ANALYTICAL HYPOTHESES ONLY / NO STRUCTURAL DECISION / NO EXECUTION`

## 1. Purpose

The registered stage decomposition exposed eleven observational axes. The next
question is not to add another axis, but to ask:

```text
Which axes are independent?
Which axes are different views of one underlying structure?
Which axes are prerequisites for others?
Which axes may be derived, projected, or otherwise dissolved?
```

This record does not decide that any axis is minimal, irreducible, redundant,
or mergeable. It only registers dependency hypotheses for later discriminative
experiments.

## 2. Working labels

Analytical labels, not implementation names:

```text
R  = Residue
Rp = Representation
Pu = Persistence unit
Id = Identity
Lo = Locator / selection
Re = Retrieval
Sr = Semantic reconstruction
Tp = Task projection
Ad = Adoption
Be = Behavioral effect
Co = Continuation
```

## 3. First separation: structure versus relation

A provisional boundary is:

```text
Possible persistent “things”:
  Representation
  Persistence unit
  Identity

Possible relations / processes:
  Locator
  Retrieval
  Semantic reconstruction
  Task projection
  Adoption
  Behavioral effect
  Continuation
```

This boundary is analytical only. It must not become an implementation rule.

For example:

```text
Locator may become a view of Identity;
Retrieval may become Locator + Persistence-unit operation;
Projection may be a relation between Information and current Execution;
Adoption may be an Execution-to-Information use relation, not Information content.
```

Therefore the deeper question is:

```text
Which items must be saved,
and which items are relations produced when a later Execution uses saved structure?
```

## 4. Existence versus usability

The chain:

```text
stored
      ↓
locatable
      ↓
fetched
      ↓
reconstructed
      ↓
used
      ↓
behavior changed
      ↓
next phase completed
```

must remain decomposed.

For each structure, ask:

```text
Is it merely necessary for a later stage,
or is it an independent research object?
```

Example:

```text
stable Identity without Locator
      → B may still be unable to discover it.
```

If so, Locator has independent structural meaning. This cannot be decided by
concept alone.

## 5. Irreducibility question

The working irreducibility question is:

```text
Remove structure X.
Can the remaining structure restore the same cross-Execution capability?
```

If yes, X may be derivable or redundant. If no, X may have independent
structural meaning.

However, non-recovery does not immediately prove a minimal Information atom.
Later analysis must separate:

```text
accidental dependence on current task;
dependence caused by current representation;
missing alternative recovery structure;
insufficient B capability.
```

Thus irreducibility requires competing explanations and later discriminative
experiments.

## 6. Dependency hypotheses

### D1 — Representation ↔ Persistence unit

Hypothesis: distinct.

```text
Representation answers “in what form does it exist?”
Persistence unit answers “what exists as one addressable whole?”
```

A representation may constrain possible persistence units, but one persistence
unit may contain multiple representations, and one semantic structure may be
represented at different granularities.

They collapse only if exactly one representation maps one-to-one onto exactly
one persistence unit.

### D2 — Identity ↔ Representation

Hypothesis: currently coupled, conceptually unresolved.

The existing `InformationID` is derived from content, source, and chunk data.
Therefore, in the current implementation, changing representation can change
identity.

The open question is whether identity should be:

```text
content-derived;
provenance-derived;
semantic-structure-derived;
execution-derived;
or relationally assigned.
```

No decision is made.

### D3 — Identity ↔ Locator

Hypothesis: distinct in concept, currently conflated by implementation.

The current InformationCore can fetch only by explicit identity and has no
search or discovery. Therefore identity is currently also the only locator.

Conceptually, however:

```text
Identity answers “what is this?”
Locator answers “how can this be found?”
```

A stable identity may still be undiscoverable by B. If so, Locator has
independent structural meaning.

### D4 — Locator ↔ Retrieval

Hypothesis: prerequisite relation, not identity.

Locator selects what may be fetched. Retrieval determines what shape is
returned.

Locator becomes redundant only if a later system can discover and retrieve
relevant Information natively. That is not current behavior.

### D5 — Retrieval ↔ Semantic reconstruction

Hypothesis: distinct.

Retrieval returns stored representation. Semantic reconstruction requires type,
scope, provenance, temporal validity, and task context.

A successful fetch can still fail semantic reconstruction.

### D6 — Semantic reconstruction ↔ Task projection

Hypothesis: distinct.

Semantic reconstruction restores what Execution A meant. Task projection
selects and transforms the relevant parts for B's current release-gate
constraints.

The same compatibility register may be reconstructed correctly but projected
differently by different tasks.

### D7 — Task projection ↔ Adoption

Hypothesis: distinct.

Projection places material into B's available working context. Adoption
requires observable dependence in B's reasoning or output.

No projection may imply no adoption, but adoption without behavioral change is
possible.

### D8 — Adoption ↔ Behavioral effect / Continuation

Hypothesis: distinct.

Adoption is inferred from observable dependence. Behavior is the resulting
output. Continuation is next-phase completion.

Possible separations:

```text
adopted but no behavior change;
behavior change without adoption;
continuation through an alternate path;
same output reached through different continuation.
```

These must be recorded separately.

## 6.1 Candidate irreducibility qualification protocol

A capability loss after removing `X` does not immediately make `X`
irreducible. Before granting even the weaker title “candidate irreducible”,
the runner and analyst must test or explicitly register the following
alternative explanations:

```text
1. Representation limitation:
   another representation of X might make the remaining structure sufficient.

2. InformationCore capability limitation:
   another existing or permitted InformationCore operation might recover
   the capability without changing schema.

3. B-capability limitation:
   a more capable fresh B might recover the capability from the remaining
   structure.

4. Genuine absence:
   after these alternatives are excluded, the loss remains attributable
   to the removal of X.
```

The required search order is therefore:

```text
remove X
      ↓
capability disappears
      ↓
search for an alternative representation of X
      ↓
search for an alternative locator/access path
      ↓
search for a derivation of X from other structures
      ↓
exclude current representation limitations
      ↓
exclude current InformationCore capability limitations
      ↓
exclude current B-capability limitations
      ↓
only now: candidate irreducible
```

This protocol is stronger than ordinary database field-redundancy analysis.
The question is not whether two stored fields look duplicated, but whether the
structures they carry can be recovered from one another.

Analysts must distinguish:

```text
duplicated content;
duplicated representation;
shared reference;
independent semantic structure.
```

These are not the same thing.

### D9 — Residue ↔ Representation

Hypothesis: source relation, not identity.

Residue is what Execution naturally left. Representation is a selected form of
some residue. Natural residue already has a representation, but a stored
representation is a second-order selection by Observer or Runtime.

### D10 — Continuation is an outcome relation

Continuation is not a persisted structure. It is an outcome relation meaning:

```text
B completed the next phase in a way made possible, affected,
or constrained by prior residue / Information.
```

Path changes, identical outputs, and alternate recoveries must all be recorded.

## 7. Candidate independent structures

Not selected. Only registered as later discriminative candidates:

```text
exact raw residue representation;
semantic compatibility register;
service baseline facts;
pairwise compatibility facts;
source / execution provenance binding;
phase or completion marker;
task-projection dependency;
locator / selection dependency.
```

A possible omitted cross-axis candidate is provenance / source binding. It is
not added as a twelfth axis until dependency analysis shows it cannot be
represented by Identity, Representation, Persistence unit, or Execution
provenance.

## 8. Candidate collapse hypotheses

These require experiments, not conceptual resolution:

```text
H-C1 Identity and Locator collapse in the current fetch-only InformationCore.
H-C2 Representation and Persistence unit collapse for one atomic register.
H-C3 Retrieval and Semantic reconstruction collapse when Information is self-describing.
H-C4 Projection and Adoption collapse when the task explicitly instructs use.
```

If confirmed, they describe task-local couplings unless shown general.

## 9. Draft irreducibility test shape

No execution is authorized. A later test would compare matched B conditions:

```text
complete available residue;
minus candidate structure X;
alternative representation of X;
alternative locator for X;
same release request and constraints;
fresh context;
NativeMLX cache isolation.
```

Each run records:

```text
located;
fetched;
parsed;
semantic-referenced;
adopted;
behavioral;
continuation.
```

Reading:

```text
absence recoverable by another structure → X possibly redundant;
absence not recoverable → X possibly independent;
recovery requires added information or labor → representation-dependent;
B capability ambiguity → inconclusive.
```

## 10. Non-goals

```text
No B0/B1/B2 execution.
No InformationCore change.
No schema change.
No RuntimeMemory.
No RelationCore integration.
No search/list/query implementation.
No bridge implementation.
No declaration that the eleven axes are minimal.
No declaration that any dependency hypothesis is proven.
```
