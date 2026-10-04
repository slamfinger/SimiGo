# Information Structure Coverage Matrix

Date: 2026-10-04  
Status: `LAYER-1 INVENTORY COMPLETE / BREADTH-FIRST DISCIPLINE ACTIVE / NEW PROBES NOT AUTHORIZED`

## 1. Purpose

This matrix maps the current TC-A Information-structure layer before further
local reduction. It is an evidence-coverage map, not an architecture, schema,
minimality proof, or claim that the listed distinctions are final.

The M1.b branch is consequently demoted from mainline reduction to a local
microscope result.

## 2. Anti-collapse discipline

After more than one local reduction layer, the study must pause and perform a
global coverage check:

```text
local finding;
local reduction;
pause;
global coverage check;
choose breadth or depth by gap map.
```

A layer is not "finished" because one promising node has produced many
interesting results. The next layer may open only after every same-layer object
has at least an inventory entry, evidence status, and explicit gap decision.

## 3. Status legend

```text
REGISTERED_ONLY    = analytical distinction exists; no real intervention;
OBSERVED/FIXED     = present in real evidence but not independently varied;
PARTIAL            = some controlled evidence exists but is narrow or confounded;
CONTROLLED         = isolated, adjudicated intervention in a bounded frame;
STATIC_ONLY        = static decomposition without continuation intervention;
EXCLUDED_UNTESTED  = deliberately omitted from current continuation tests;
HALTED_PARTIAL     = execution began but was intentionally stopped.
```

## 4. Layer-1 inventory count

```text
analytical axes              = 11;
candidate units              = 5;
M1 subfields                 = 5;
M2 subfields                 = 4;
M3 subfields                 = 7;
total inventoried rows       = 32.
```

Status counts:

```text
CONTROLLED         = 2;
PARTIAL            = 7;
OBSERVED/FIXED     = 5;
REGISTERED_ONLY    = 5;
STATIC_ONLY        = 1;
EXCLUDED_UNTESTED  = 12;
HALTED_PARTIAL     = 0 rows at axis level; one extra condition-level branch.
```

The counts measure inventory coverage, not semantic importance.

## 5. Analytical-axis coverage

| Axis | Object | Current status | Evidence / gap |
|---|---|---|---|
| 0 | Residue | OBSERVED/FIXED | Execution A final answer, tool calls, and traces are preserved; natural residue was not itself supplied as an intervention arm. |
| 1 | Representation | PARTIAL | R-A1, S-B2, and S-B2R show representation effects, but only in direct-inline JSON-family variants. |
| 2 | Persistence unit | REGISTERED_ONLY | Whole register, single fact, pair fact, and event granularities are registered; direct-inline bypassed persistence. |
| 3 | Identity | REGISTERED_ONLY | Identity distinctions are registered; S-B direct-inline had no Stored Information identity intervention. |
| 4 | Locator / selection | REGISTERED_ONLY | Original B0/B1/B2 locator panel remains unexecuted. |
| 5 | Retrieval | REGISTERED_ONLY | Fetch shape and retrieval absence were bypassed by direct inline. |
| 6 | Semantic reconstruction | REGISTERED_ONLY | Prompts already supplied reduced decision semantics; no reconstruction probe ran. |
| 7 | Task projection | PARTIAL | The release request was fixed; only residue content varied, so projection was not independently shifted. |
| 8 | Adoption | PARTIAL | Semantic-referenced versus adopted was adjudicated, but no irrelevant-content counterfactual ran. |
| 9 | Behavioral effect | PARTIAL | Decision/order/blocker effects were observed, but no complete behavioral-effect isolation panel exists. |
| 10 | Continuation | CONTROLLED | Narrow TC-A continuation was repeatedly adjudicated, but the result is task/prompt/model bounded. |

## 6. Candidate-unit coverage

| Unit | Object | Current status | Evidence / gap |
|---|---|---|---|
| U1 | Exact raw residue | OBSERVED/FIXED | Exact A bytes are sealed, but R-A1 prevented Observer selection and exact raw bytes were not supplied to B. |
| U2 | Decoded semantic register | STATIC_ONLY | Static U1→U2→U3/U4 mapping exists; the whole decoded register was not used as a direct-inline B condition. |
| U3 | Service baseline facts | PARTIAL | M1.b has many controls; M1.a/c/d/e do not. |
| U4 | Pair compatibility facts | PARTIAL | M2.b pair decisions were present in S-B1 variants, but M2 was not independently deleted while M1 remained fixed. |
| U5 | Provenance / execution binding | EXCLUDED_UNTESTED | M3 was intentionally excluded from every S-B continuation condition. |

## 7. M1 subfield coverage

| Field | Object | Current status | Evidence / gap |
|---|---|---|---|
| M1.a | Service-id set | OBSERVED/FIXED | IDs appear in prompts and outputs, but the set was never independently varied. |
| M1.b | Baseline predicates | CONTROLLED | Deletion, representation control, semantic-role controls, and three single-function fields were tested; pair combinations were halted. |
| M1.c | Baseline issue statements | EXCLUDED_UNTESTED | Issue wording was removed from all direct-inline conditions and never reintroduced. |
| M1.d | Source-file binding | EXCLUDED_UNTESTED | No source binding entered a B condition. |
| M1.e | Audit scope | OBSERVED/FIXED | The platform-baseline audit scope remains implicit in the fixed task, not varied. |

## 8. M2 subfield coverage

| Field | Object | Current status | Evidence / gap |
|---|---|---|---|
| M2.a | Pair-id set | OBSERVED/FIXED | The same three unordered pairs were always supplied. |
| M2.b | Pair compatibility decisions | PARTIAL | Present in S-B1 variants and adopted in many outputs, but never independently deleted while M1.b remained fixed. |
| M2.c | Pair issue causes | EXCLUDED_UNTESTED | Pair causes were removed from all direct-inline residue. |
| M2.d | Source / audit binding | EXCLUDED_UNTESTED | Pair-level audit binding was not tested. |

## 9. M3 subfield coverage

| Field | Object | Current status | Evidence / gap |
|---|---|---|---|
| M3.a | Execution A run identity | EXCLUDED_UNTESTED | Never supplied to B. |
| M3.b | Producer / backend binding | EXCLUDED_UNTESTED | Never supplied to B. |
| M3.c | Task-carrier binding | EXCLUDED_UNTESTED | Never supplied to B. |
| M3.d | Source-set binding | EXCLUDED_UNTESTED | Source hashes were never supplied to B. |
| M3.e | Result binding | EXCLUDED_UNTESTED | Result hash was never supplied to B. |
| M3.f | Tool evidence | EXCLUDED_UNTESTED | Four `read_file` calls were never supplied to B. |
| M3.g | Temporal / Runtime evidence | EXCLUDED_UNTESTED | Lifecycle/cache evidence stayed runner-side. |

## 10. Cross-axis dependency coverage

| Dependency | Current status | Reading |
|---|---|---|
| D1 Representation ↔ Persistence unit | REGISTERED_ONLY | No persistence-unit intervention. |
| D2 Identity ↔ Representation | REGISTERED_ONLY | No identity intervention. |
| D3 Identity ↔ Locator | REGISTERED_ONLY | No locator intervention. |
| D4 Locator ↔ Retrieval | REGISTERED_ONLY | No retrieval intervention. |
| D5 Retrieval ↔ Semantic reconstruction | REGISTERED_ONLY | No reconstruction probe. |
| D6 Semantic reconstruction ↔ Task projection | REGISTERED_ONLY | Projection request stayed fixed. |
| D7 Task projection ↔ Adoption | PARTIAL | Adoption changed with residue, but projection rules did not. |
| D8 Adoption ↔ Behavioral effect / Continuation | PARTIAL | Adoption and continuation were adjudicated together, not fully separated. |
| D9 Residue ↔ Representation | PARTIAL | Strongest current evidence, but limited to JSON-family inline variants. |
| D10 Continuation as outcome relation | CONTROLLED | Used consistently as the bounded adjudication outcome. |

## 11. Current breadth conclusion

The exercised region is concentrated here:

```text
Representation + Adoption + Behavioral effect + Continuation
      ↓
U3/M1.b and U4/M2.b
      ↓
F fields under M1.b
```

The untouched or barely touched region includes:

```text
Persistence unit;
Identity;
Locator / selection;
Retrieval;
Semantic reconstruction;
Independent task projection;
U1 exact-residue delivery;
U2 whole-register delivery;
U4 deletion with M1 fixed;
all M3 subfields;
all pair-level cause/binding fields.
```

Therefore the evidence does not support a claim that Information decomposition is
converging. It supports only a narrow claim about M1.b in the current TC-A frame.

## 12. Layer rule

Before any next deeper layer:

```text
1. complete the same-layer inventory;
2. give every row a coverage status;
3. normalize each row's semantic function;
4. choose breadth probes so uncovered rows receive same-level treatment;
5. compare horizontally;
6. only then authorize the next nested layer.
```

Steps 1 is complete by this matrix. Steps 2-6 are design work and require
separate authorization for execution.

## 13. Boundary

```text
Observer                 = NOT AUTHORIZED;
InformationCore store    = NOT AUTHORIZED;
Runtime/schema/API       = NOT CHANGED;
M1.b deeper execution    = HALTED;
new continuation probes  = NOT AUTHORIZED;
minimality claim         = NOT MADE.
```
