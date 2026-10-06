# ES Continuation Sufficiency Probe — v0.1 Design

> **Status:** DESIGN V0.1 DELIVERED FOR HUMAN REVIEW — EXPERIMENT NOT AUTHORIZED
> **Date:** 2026-10-06
> **Human ruling recorded by this design:** Stage Transition ACCEPTED; Probe DESIGN ONLY AUTHORIZED.
> **Design input:** `PALACE_INFORMATION_SPACE_FOUNDATION_POST_CCVS01_STAGE_TRANSITION_REVIEW_PROPOSAL_20261006.md` at `21932fe`
> **Carrier substrate if later authorized:** accepted U-A surface only, held fixed
> **Primary boundary:** test Information Space continuity support, not LLM/Agent autonomy.

## 1. Authorization and governance boundary

This document is design-only. It authorizes no implementation, fixture run,
database creation, migration, benchmark, MCP call, MemPalace call, embedding
run, remote API call, or experiment execution.

The governance order is:

```text
Human stage-transition ruling
  → Probe v0.1 design
  → Human / independent design review
  → decide whether an execution gate is needed
  → separate experiment authorization, only if approved
```

The earlier `ES Continuation Sufficiency Design Gate` remains only a proposed
governance concept. This document does not create a formal new Gate.

## 2. Research question

After an Execution State is interrupted, does Information Space already
contain the minimal lawful information relations needed to reconstruct enough
context and determine the registered continuation boundary?

The question is not:

```text
Can an LLM or Agent finish the task?
```

The question is:

```text
Can Information Space supply a lawful continuation closure that lets an
Execution State resume without guessing?
```

## 3. Hypothesis

The core hypothesis is **Information Closure for Continuation**:

```text
An interrupted Execution State can recover to a continuation-ready condition
using only existing, lawfully provenanced Information Space records: the
task objective, input references, decisions, artifact references, boundary
state, and continuation pointer.
```

Formally, for the positive case:

```text
E1 ≡ sufficient(E0, continuation)
```

where `E1` is reconstructed only from Information Space and supports C1 +
C2 below. The hypothesis does **not** require:

```text
LLM(E1) can complete the task
```

## 4. Continuation layers

The Human ruling separates continuation into three layers:

```text
C1  Reconstruction
    Can a fresh process reconstruct the correct Execution Context from
    Information Space?

C2  Continuation Determination
    Can the pre-registered continuation boundary / next-action pointer be
    recovered and validated without inventing a new action?

C3  Action Execution
    Is the next action actually performed?
```

The probe's necessary success condition is **C1 + C2 only**.

C3 is at most an observation item and contributes nothing to PASS. A design
or later run must not interpret task completion as probe success.

## 5. Execution State minimal representation

`E0` is a conceptual Execution State before interruption. Its durable probe
trace is a bounded set of Information Space records and relations.

The candidate minimal closure is:

```text
objective
  what task was being performed

input references
  lawful references to required inputs

decisions / work records
  relevant decisions and completed work boundaries

artifact references
  lawful references to produced or consumed artifacts

boundary state
  what was complete, incomplete, invariant, or explicitly out of scope

continuation pointer
  pre-registered next-action boundary, not an open-ended instruction

provenance
  actor / source provenance for each record

revision
  carrier revision / current-versus-historical visibility
```

Actor identity may appear as provenance subject only. This design creates no
`AgentInformation`, `AgentRelation`, `AgentStore`, or Agent semantic entity.

## 6. Information Space minimal requirements

If later executed, the fixed Information Space surface must support:

```text
IR-1  resolve a named Information reference to its registered record
IR-2  preserve provenance for each required record
IR-3  distinguish current revision from historical revision
IR-4  relate task / work records to objective, input, artifact, and boundary
IR-5  represent a continuation pointer as a resolvable relation
IR-6  make absence, ambiguity, provenance deficiency, or revision conflict
      observable as a typed reconstruction failure
IR-7  prevent silent promotion of guessed or unprovenanced text into
      required context
```

These are probe-local requirements, not changes to InformationCore,
RelationCore, UA v1.0, the U-A Manifest, or any Frozen Contract.

## 7. Positive continuation case

The positive case begins only after the full `E0` closure has been durably
registered and acknowledged.

```text
Positive setup
  E0 = complete closure:
      objective
      + resolvable input references
      + decisions / work records
      + artifact references
      + boundary state
      + one unambiguous continuation pointer
      + provenance and revisions

Positive interruption
  all in-process execution memory is discarded

Positive reconstruction
  a fresh process uses only lawful Information Space resolution

Positive expected result
  C1 = reconstructed context is complete and provenance-valid
  C2 = the registered continuation boundary is recovered exactly
```

C2 must produce a deterministic continuation decision:

```text
CONTINUE_CERTAIN
pointer    = registered continuation pointer
boundary   = registered continuation boundary
```

It must not choose, invent, rank, or semantically infer a different action.

## 8. Negative / ambiguous case

The negative control is mandatory and may be more important than the positive
case.

```text
Negative setup
  start from a closure with one registered deficiency:
      unresolved reference,
      ambiguous reference,
      insufficient provenance,
      missing continuation pointer,
      conflicting revision, or
      absent boundary state

Negative required result
  typed insufficiency is observable

Negative continuation decision
  BLOCK_INSUFFICIENT
```

The negative case must not continue as if certain. A system that can always
"guess" a continuation has failed the probe even if its answer looks useful.

## 9. Interruption boundary

All interruptions occur after the `E0` closure is durably committed and
acknowledged. The probe does not re-test U-A crash transaction semantics.

If later authorized, use at least:

```text
I-1  clean pause / process stop
I-2  adverse process loss after durable E0 acknowledgement
```

The reconstruction process must start without access to prior conversation
memory, prior in-memory state, private agent notes, or side-channel hints.

## 10. Reconstruction procedure

The eventual procedure must be mechanical and auditable:

```text
R1  Start a fresh reconstruction process.
R2  Read only the registered continuation-pointer entry point.
R3  Resolve the exact references reachable through the pre-registered
    relation graph.
R4  Record every resolved Information id, revision, locator, and provenance.
R5  Build a Reconstruction Manifest containing:
      objective
      input references
      decisions / work records
      artifact references
      boundary state
      continuation decision
R6  Emit C1 and C2 status independently.
R7  For the negative case, emit a typed BLOCK_INSUFFICIENT result.
```

Free-form search, semantic ranking, embeddings, and model-generated context
are not lawful inputs to C1 or C2.

## 11. Continuation predicate

For the positive case:

```text
C1 = PASS iff
     every required E0 slot is represented
     and each reference resolves
     and provenance is sufficient
     and revision visibility is correct
     and boundary state is complete enough to evaluate continuation

C2 = PASS iff
     the continuation pointer resolves to exactly one registered boundary
     and the decision is CONTINUE_CERTAIN
     and no unregistered alternative action is selected
```

For the negative case:

```text
C1/C2 = PASS iff
     the specific deficiency is observed as a typed insufficiency
     and the decision is BLOCK_INSUFFICIENT
```

The positive and negative controls are both mandatory for overall PASS.

## 12. PASS / FAIL / INDETERMINATE

Research verdicts are:

```text
PASS
  positive case: C1 PASS and C2 PASS
  negative case: typed deficiency observed and BLOCK_INSUFFICIENT

FAIL
  positive case: a required closure slot cannot be reconstructed or the
                 continuation boundary cannot be determined lawfully
  or negative case: insufficient information is treated as CONTINUE_CERTAIN

INDETERMINATE
  carrier precondition fails,
  fixture or harness defect is found,
  evidence is incomplete,
  or the run violates this design
```

Run validity is separate from research verdict. A run may be
`VALID` but `FAIL`, or `INVALID` and therefore `INDETERMINATE`.

## 13. Evidence requirements

If later authorized, each run must preserve:

```text
EV-1   pre-registered E0 closure definition
EV-2   expected continuation boundary and expected negative result
EV-3   interruption type and durable-acknowledgement boundary
EV-4   all resolved Information ids, revisions, locators, provenance
EV-5   unresolved or ambiguous references with typed reasons
EV-6   Reconstruction Manifest
EV-7   C1 status
EV-8   C2 status and continuation decision
EV-9   carrier conformance/precondition result
EV-10  raw logs sufficient to audit the reconstruction path
```

Evidence must show the information path, not merely a final narrative.

## 14. Failure taxonomy

```text
FT-01  missing required slot
FT-02  unresolved reference
FT-03  ambiguous reference
FT-04  insufficient provenance
FT-05  revision conflict or wrong historical visibility
FT-06  missing / ambiguous / conflicting continuation pointer
FT-07  incomplete boundary state
FT-08  required relation between task and artifact absent
FT-09  unlawful inference used to fill context
FT-10  negative case falsely reports CONTINUE_CERTAIN
FT-11  carrier precondition failure
FT-12  harness / protocol defect
```

`FT-01..FT-10` are candidate Information Space insufficiency findings when
the carrier precondition is valid. `FT-11..FT-12` are not Information Space
failures.

## 15. What would prove Information Space insufficiency

Information Space insufficiency is proven only when all are true:

```text
1.  the accepted U-A carrier precondition is valid;
2.  the E0 closure definition was pre-registered;
3.  the interruption boundary was observed;
4.  reconstruction used only lawful Information Space resolution;
5.  a required closure slot or relation is absent, ambiguous, unprovenanced,
    revision-conflicted, or otherwise not mechanically decidable;
6.  the failure is recorded with typed evidence; and
7.  the same evidence explains why the result is not a harness defect.
```

A positive-path FAIL is evidence of insufficiency under the registered
minimal closure. It does not prove that every possible Information Space
design is insufficient.

## 16. What must not be interpreted as success

The following do not prove Information Space continuation sufficiency:

```text
N-01  an LLM completes the task
N-02  C3 action execution succeeds
N-03  retrieval returns plausible text
N-04  a model guesses a missing slot and the result looks correct
N-05  semantic ranking finds useful material
N-06  performance is good
N-07  MemPalace or another backend is capable
N-08  the positive case passes while the negative case falsely continues
N-09  one task lineage is generalized into a universal law
N-10  context appears useful but lacks provenance or revision validity
```

In particular, any success obtained by silently adding missing information,
using side-channel memory, or relaxing the negative control is invalid.

## 17. Boundary with U-A and UA v1.0

If later authorized, the probe may use the accepted U-A implementation as a
fixed substrate.

This design does **not**:

```text
modify U-A code
modify the U-A Manifest v1.1
modify UA v1.0
modify PB v1.2
modify any Frozen Contract
mutate InformationCore or RelationCore
change carrier semantics
reopen U-A correctness
select a backend
authorize migration
```

UA v1.0 and existing frozen semantics are cited, not redefined. Any apparent
conflict is resolved in favor of the frozen artifacts.

## 18. Confounder exclusions

The design explicitly excludes these confounds from the verdict:

```text
LLM intelligence or prompting skill
agent autonomy
retrieval quality
embedding quality
semantic ranking
backend performance
database throughput
MCP integration
remote API availability
tool breadth
conversational memory
private model state
```

The probe is valid only when continuation depends on the registered
information closure, not on model ability to guess what was missing.

## 19. Deliverable status

Probe v0.1 is ready for Human independent design review.

Recommended review decision:

```text
ACCEPT DESIGN            only if C1+C2, closure, and negative control are
                         sufficiently decidable
REVISE DESIGN            if any confound can still affect C1/C2
REJECT DESIGN            if it becomes an agent-capability or retrieval test
```

No execution authorization is requested by this document.
