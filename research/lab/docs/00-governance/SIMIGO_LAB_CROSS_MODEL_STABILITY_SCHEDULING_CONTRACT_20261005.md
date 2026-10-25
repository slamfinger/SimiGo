# Cross-Model Stability Scheduling Contract

Date: 2026-10-05<br>
Status: `STATIC SCHEDULING CONTRACT FROZEN / FORMAL RUNTIME NOT AUTHORIZED`

## 1. Purpose

This contract freezes the first cross-model × cross-sample scheduling layer.
It governs only observable stability scheduling. It does **not** authorize model execution, semantic normalization, stability scoring, vertical decomposition, or mapping into any existing reduction framework.

The controlling rule is:

```text
observe whether phenomena are stable;
only then decompose stable phenomena.
```

## 2. Relation to existing material

The current cross-model freeze defines:

```text
4 samples;
4 models;
16 planned cells.
```

Four raw Model-A outputs already exist. They are retained only as
`PILOT_RAW_ONLY`. Their runner records state that runtime isolation was not
enforced, so they cannot be used as formal stability evidence and must be rerun
under the formal isolation contract if this battery is later authorized.

Round 1 evidence is also a separate evidence stream. It may motivate attention,
but it does not enter the cell schedule and does not label any scheduled cell.

## 3. Frozen observation indicators

Only observable indicators are scheduled:

```text
O1 task / continuation outcome;
O2 key-decision presence;
O3 required-information presence;
O4 information-relation formation;
O5 representation-sensitivity;
O6 implementation-path variation.
```

No internal model state, hidden understanding, or reduction-framework label is
scheduled.

## 4. Frozen judgment standards

The three standards are distinct:

```text
J1 same_output
   = exact or canonical output equality;

J2 same_decision
   = required high-level decision(s) match;

J3 same_functional_behavior
   = the observable outcome satisfies the sample contract,
     preserves required constraints and relations,
     and produces the required downstream effect.
```

`J3` is the primary cross-model stability criterion.

`J1` and `J2` are recorded as auxiliary observations. A model must not be judged
unstable solely because its wording, ordering, formatting, or implementation path
differs.

`semantic-referenced`, `adopted`, and hidden understanding are not part of this
static scheduling layer.

## 5. Frozen isolation standard

Every formal cell must independently record:

```text
I1 fresh execution/session;
I2 model identity and endpoint identity;
I3 sample hash / frozen prompt hash;
I4 no inherited cache or prefix reuse;
I5 model/runtime reload or equivalent fresh-process isolation;
I6 start/finish evidence;
I7 no concurrent backend workload;
I8 no Round-1 residue or transcript;
I9 no other cell's prompt, output, or runtime state.
```

If any required item is absent, the cell is:

```text
PILOT_ONLY_NOT_FORMAL.
```

Unique session IDs and similar model names are not sufficient isolation proof.

## 6. Frozen cell schedule

All 16 cells are scheduled as observable cells. None is authorized for runtime
by this contract.

| Sample | Model A | Model B | Model C | Model D |
|---|---|---|---|---|
| S1 | PILOT_ONLY / REQUIRES FORMAL RERUN | PLANNED / NOT RUN | PLANNED / NOT RUN | PLANNED / NOT RUN |
| S2 | PILOT_ONLY / REQUIRES FORMAL RERUN | PLANNED / NOT RUN | PLANNED / NOT RUN | PLANNED / NOT RUN |
| S3 | PILOT_ONLY / REQUIRES FORMAL RERUN | PLANNED / NOT RUN | PLANNED / NOT RUN | PLANNED / NOT RUN |
| S4 | PILOT_ONLY / REQUIRES FORMAL RERUN | PLANNED / NOT RUN | PLANNED / NOT RUN | PLANNED / NOT RUN |

No cell has formal stability status in this contract.

## 7. Required pre-execution gate

Before any formal cell runs, a separate runner-audit artifact must prove:

```text
G1 all 16 cells and statuses match this contract;
G2 every sample and model identity/hash is unchanged;
G3 prompts render deterministically from frozen inputs;
G4 the isolation record schema covers I1–I9;
G5 no reduction-framework labels enter scheduling or raw capture;
G6 the runner aborts on missing isolation evidence;
G7 existing Model-A outputs are segregated as pilot-only.
```

Runtime remains unauthorized until that runner-audit artifact is reviewed and a
separate execution authorization is issued.

## 8. Stability gate

After formal cells are later executed and observed, cells may be labeled only as:

```text
STABLE_FUNCTIONAL;
DECISION_STABLE_ONLY;
OUTPUT_STABLE_ONLY;
UNSTABLE;
NOT_OBSERVABLE;
PILOT_ONLY_NOT_FORMAL.
```

A stable invariant candidate exists only when the same `J3` reading recurs
across the preregistered sample/model scope.

If no stable invariant candidate appears, vertical decomposition is forbidden.
The permitted responses are:

```text
add preregistered samples;
add preregistered models;
improve observable indicators;
redesign the task contract;
or abandon the proposed phenomenon.
```

## 9. Forbidden in this layer

```text
runtime execution without separate authorization;
semantic normalization;
stability scoring;
vertical decomposition;
mapping into any existing reduction inventory;
using Round 1 evidence to label cross-model cells;
treating pilot raw output as formal evidence;
inferring hidden model understanding;
modifying frozen samples, models, or prompts during scheduling.
```

## 10. Boundary

```text
Observer                 = NOT AUTHORIZED;
InformationCore store    = NOT AUTHORIZED;
schema/API change        = NOT AUTHORIZED;
RuntimeMemory            = NOT AUTHORIZED;
bridge implementation    = NOT AUTHORIZED;
formal model execution   = NOT AUTHORIZED;
minimal structure claim  = NOT MADE;
irreducibility claim     = NOT MADE.
```
