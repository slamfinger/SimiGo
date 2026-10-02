# C-Design — Lifecycle Recovery Experiment for Execution State × Information Space

Date: 2026-10-03  
Status: `C-DESIGN CONFIRMED / HUMAN RE-AUDIT PASS WITH CONDITION`  
Frozen input: `SIMIGO_LAB_C_QUESTION_SPEC_20261003.md`  
Authorization: DESIGN ONLY. No C-Impl, no C-Execute, no code, no
schema migration, no Core modification.

## 1. Design objective

Turn the frozen C-A / C-B / C-C boundary into one fair, repeatable
lifecycle experiment:

```text
S0
  ↓
real external change
  ↓
declared post-change observation
  ↓
termination
  ↓
fresh process cold start
  ↓
continue the same task
  ↓
fixed continuation evaluation
```

The experiment asks what each arm can recover when the only systematic
difference is the persisted semantic carrier.

## 2. Operational arms

### Common Execution State

Every arm may persist minimal Execution State:

```text
task_id
lifecycle_phase
attempt_count
opaque carrier pointers required by the arm
executor/run identity
```

Execution State must not persist entity facts, observations, state values,
change narratives, relation pairs, or derived continuation answers.

### C-A — ES only

```text
allowed:  Execution State persistence
forbidden: Information Space persistence
```

Before termination its checkpoint may say, for example:

```text
task_id        = C-T-001
lifecycle_phase = POST_CHANGE_OBSERVED
next_step      = RESUME_EVALUATION
```

It may not store S0, S1, their values, a change sentence, or a computed
final action.

### C-B — ES + Information, no Relation

C-B has the same Execution State plus four independent Information
records:

```text
I-TASK      neutral task charter
I-S0        complete entity observation at t0
I-S1        complete entity observation at t1
I-PROGRESS  lifecycle progress fact
```

C-B has no RelationStore record and no equivalent relation object.

To keep the contrast clean, this design does not use C-B's permitted
"factual change description" allowance. C-B stores state observations and
task facts only. The subject may infer change at runtime from independent
records.

### C-C — ES + Information + Relation

C-C contains every C-B record plus one persisted Relation:

```text
subject   = I-S1 identity
predicate = observed-change-of
object    = I-S0 identity
```

Relation provenance records the observation event.

## 3. Common task

One logical task is used for all arms:

```text
Task C-T-001:
  Resume after interruption and produce a continuation report for
  entity E. Use only declared persistent carriers. Do not rescan the
  physical entity.
```

The common continuation rule is fixed before execution:

```text
if after.alpha >= 40 and after.mode == "active":
    next_action = REQUEST_HEALTH_CHECK
else:
    next_action = WAIT_FOR_CHANGE
```

The rule is part of the task; expected state values are not supplied to
cold start.
The resulting action token is frozen at design time as
`REQUEST_HEALTH_CHECK`; it is not selected after observing arm outcomes.

## 4. S0 / external change / S1

Physical entity E has exactly two declared states:

```text
S0 = {"entity":"E","alpha":17,"mode":"quiet"}
S1 = {"entity":"E","alpha":42,"mode":"active"}
```

The orchestrator, not ExecutionCore, performs the real external overwrite
and records both file hashes. ExecutionCore never scans or detects the
physical change.

## 5. Termination point

The fixed run order is:

```text
1. start old process
2. declare/observe S0
3. persist according to arm
4. orchestrator overwrites physical E: S0 → S1
5. declare/observe S1
6. persist according to arm
7. flush Execution State checkpoint
8. terminate the process
9. verify process exit
10. start a fresh process
```

Termination occurs after post-change observation but before continuation
evaluation. No arm may precompute and persist the final answer.

## 6. Cold-start protocol

Cold start requires:

```text
new process
empty process memory
no inherited model context / KV
no old ExecutionCore runtime state
no undeclared checkpoint
no old session memory
no harness-injected answer
no experiment-external filesystem scan
```

Fresh process input is limited to:

```text
task_id
arm/carrier configuration
common continuation instruction
```

Allowed reads are exactly:

```text
C-A: Execution State persistence
C-B: Execution State + Information
C-C: Execution State + Information + Relation
```

## 7. Continuation task

After cold start, the subject must emit one continuation report with:

```text
task_id
before_state
after_state
change_statement
next_action
```

Expected semantic shape:

```text
task_id         = C-T-001
before_state    = alpha=17;mode=quiet
after_state     = alpha=42;mode=active
change_statement = E moved from alpha=17;mode=quiet
                   to alpha=42;mode=active
next_action     = REQUEST_HEALTH_CHECK
```

C-B may derive `change_statement` by comparing its independent S0 and S1
Information at runtime. That is allowed; C-B lacks only the persisted
Relation carrier.

## 8. Success / failure criteria

Each component is scored independently:

| ID | Component | PASS condition |
|---|---|---|
| X-1 | Task identity | exact `C-T-001` |
| X-2 | Before-state recovery | exact S0 values |
| X-3 | After-state recovery | exact S1 values |
| X-4 | Change recovery | correct directional S0 → S1 statement |
| X-5 | Next-action recovery | exact `REQUEST_HEALTH_CHECK` |

```text
Full continuation success = X-1 ∧ X-2 ∧ X-3 ∧ X-4 ∧ X-5
Partial recovery = one or more, but not all, components pass
Failure = no useful continuation or missing required components
Invalid run = any forbidden channel was used
```

A forbidden channel makes the run invalid; it is not counted as an
experimental failure of the arm.

### Interpretation rules

X-4 is an observation metric for continuation capability. It is not a
Relation-necessity criterion.

```text
C-B passing X-4 is legal.
It means independent Information was sufficient for directional change
recovery in this task.
It does not mean Relation is unnecessary in general.

C-B failing X-4 is consistent with Relation contributing to recovery,
but does not by itself prove Relation was the only missing mechanism.
```

The primary necessity comparison is:

```text
C-A versus C-B/C: role of persistent Information Space
```

The C-B versus C-C comparison is exploratory for this fixed task. If C-B
passes, the experiment must record that Relation was not necessary for
this continuation; it must not redesign the result into a Relation win.

X-5 is machine-checkable because `REQUEST_HEALTH_CHECK` is frozen before
execution. No post-hoc judgment may replace it with a semantically similar
action.

## 9. Evidence to collect

For every arm:

```text
task and rule definition hash
S0 / S1 source snapshots and hashes
orchestration overwrite log
old process PID and exit proof
post-termination persistence snapshot
fresh process PID and invocation record
scrubbed environment record
carrier-read/fetch trace in causal order
continuation artifact
fixed evaluator result
artifact hash
```

The read trace must precede the continuation artifact.
Forbidden-channel evidence must be auditable from declared invocation,
environment, persistence, and carrier-read records; C-Impl may add
mechanical checks but may not weaken this list.

## 10. Fairness controls

All arms share:

```text
same task id and rule
same initial input
same S0
same real external overwrite
same S1
same observation timing
same termination point
same cold-start protocol
same continuation instruction
same evaluator and expected report shape
```

The only systematic difference is:

```text
C-A: ES
C-B: ES + Information
C-C: ES + Information + Relation
```

## 11. Anti-smuggling checks

C-B fails design conformance if any of these appears before termination:

```text
a RelationStore row or equivalent object
a persisted pair linking I-S0 and I-S1 as change endpoints
a record whose primary content is "S0 changed into S1"
a saved diff/report that already answers the continuation
ES storing S0/S1 values or the final next_action
```

Runtime inference from independent Information is not smuggling.

## 12. Claim boundary

Results apply only to:

```text
this task
this single external transition
this lifecycle slice: termination → restart → cold start
this executor/harness form
these persisted carrier definitions
```

They do not establish universal Agent necessity, universal Memory System
necessity, PALACE schema, transfer recovery, multi-change recovery, or
ExecutionCore physical-change detection.

## 13. Out of scope

```text
C-Impl / C-Execute
transfer lifecycle
multiple/concurrent changes
conflict resolution
ranking/retrieval/taxonomy/activation
PALACE schema or final storage design
database selection
Remote API / Chat / File / Tool integration
Core modification
```

## 14. Design gate result

Human re-audit confirms this document with one implementation-time
condition:

```text
C-Spec   = FROZEN
C-Design = CONFIRMED / CONDITIONAL
C-Impl   = NOT AUTHORIZED
C-Execute = NOT AUTHORIZED
```

The condition is that forbidden-channel evidence must be made really
auditable during C-Impl using declared invocation, environment,
persistence, and carrier-read records. Design acceptance does not claim
that forbidden channels are verified absent; that can be claimed only
after C-Impl audit.

C-Impl remains a separate authorization. When authorized, it must not
change C-A/B/C boundaries, lifecycle slice, X-1…X-5, success criteria,
or claim boundary.
