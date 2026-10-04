# Local Closure Task Carrier Candidates

Date: 2026-10-04  
Status: `CANDIDATES REVIEWED / TC-A SELECTED / INSTRUCTION PACKAGE FROZEN / EXECUTION NOT AUTHORIZED`

## 1. Scope

This record only defines and selects a Minimal Observable Local Task Carrier
for the registered Local Execution → Candidate Information → Fresh Execution
charter.

It does not:

```text
define prompts;
create task files;
select Candidate Information;
define Stored Information content;
authorize Execution A or B;
modify InformationCore, RelationCore, RuntimeMemory, or SimiGo Runtime.
```

## 2. Existing tool boundary

The carrier must remain inside the already-proven Local SimiGo Agent/tool
surface:

```text
SimiGo HTTPServer → NativeMLX;
Chat Completions tool calling;
external harness tool execution;
read-only workspace file access.
```

The only tool used by these candidates is the already-proven `read_file`
shape:

```text
name     = read_file
argument = path
behavior = read a UTF-8 text file inside the task workspace
executor = external harness
```

The fixed Local route is required:

```text
SimiGo source commit = 82b57f6
```

## 3. Carrier requirements

A valid carrier must satisfy:

```text
1. Phase A performs real work:
   observation → judgment → derived working result;
   not a file copy or verbatim restatement.

2. Phase relation is natural:
   A completes stage one;
   its residue is needed for stage two;
   B does not merely reread the same files.

3. B dependency is objective:
   without A's residue, B lacks a necessary premise;
   with Stored Information, B can enter stage two.

4. Scale is minimal:
   few local files;
   few tool calls;
   few model turns;
   complete request/response/tool trace can be preserved.

5. Verification is possible:
   expected relations or decisions can be checked without adding
   Information semantics.
```

## 4. Candidate TC-A — Configuration compatibility audit → Release gate

### Phase A

A reads a small service configuration set and a platform baseline, then
derives a compatibility register.

Natural work:

```text
service-to-service compatibility;
version conflicts;
missing required fields;
port or flag conflicts.
```

Natural stop: A produces the compatibility register and does not propose a
deployment.

### Phase B

B receives a separate release request and deployment constraints. B may use
only the Stored Information identity to obtain A's compatibility register.
B then produces:

```text
release decision;
allowed deployment order;
blocked-service reasons.
```

Without A's residue, B cannot determine pair-level compatibility or blocked
services.

### Notes

```text
tool calls        = read_file only;
source reread by B = forbidden;
judgment type      = deterministic compatibility checking;
database-CRUD shape = absent;
scale              = minimal.
```

## 5. Candidate TC-B — Threshold triage → Maintenance dispatch

### Phase A

A reads device readings and threshold definitions, then derives:

```text
anomalous readings;
severity levels;
affected components.
```

Natural stop: A produces the anomaly triage and does not dispatch work.

### Phase B

B receives a dispatch constraint, such as one available maintenance visit.
Using only Stored Information, B produces:

```text
priority order;
selected affected component;
reason for deferred components.
```

Without A's residue, B cannot rank affected components.

### Notes

```text
tool calls        = read_file only;
source reread by B = forbidden;
judgment type      = threshold comparison and severity ordering;
database-CRUD shape = absent;
scale              = minimal, but severity wording needs careful pinning.
```

## 6. Candidate TC-C — Ledger discrepancy audit → Reconciliation plan

### Phase A

A reads an order ledger and payment ledger, then derives:

```text
missing payments;
duplicate payments;
amount mismatches;
unmatched identifiers.
```

Natural stop: A produces the discrepancy register and does not propose
customer responses.

### Phase B

B receives a reconciliation policy, such as contact-before-adjustment. Using
only Stored Information, B produces per-discrepancy next actions.

Without A's residue, B cannot know which discrepancies require action.

### Notes

```text
tool calls        = read_file only;
source reread by B = forbidden;
judgment type      = identifier and amount comparison;
database-CRUD shape = mostly absent, but reconciliation wording can drift
                      toward storage semantics;
scale              = slightly larger than TC-A.
```

## 7. Selection matrix

| Criterion | TC-A | TC-B | TC-C |
|---|---:|---:|---:|
| uses only proven `read_file` | yes | yes | yes |
| Phase A performs judgment, not copying | strong | strong | strong |
| natural A → B relation | strong | strong | adequate |
| B objectively needs A residue | strong | strong | strong |
| small and fully observable | strong | adequate | adequate |
| deterministic checking | strong | adequate | adequate |
| avoids database-CRUD shape | strong | strong | adequate |

## 8. Decision

Selected:

```text
TC-A — Configuration compatibility audit → Release gate
```

Reason: TC-A has the cleanest objective dependency, the smallest fully
observable file set, deterministic checking, and no database-CRUD shape.

## 9. Authorization state

```text
Carrier candidates          = REVIEWED
Selected carrier            = TC-A
Prompt / task package       = FROZEN
Observer selection rules    = FROZEN
Expected register           = RUNNER-SIDE ONLY
InformationCore store       = NOT AUTHORIZED
Execution A / B             = NOT AUTHORIZED
Schema / Runtime change     = NOT AUTHORIZED
```
