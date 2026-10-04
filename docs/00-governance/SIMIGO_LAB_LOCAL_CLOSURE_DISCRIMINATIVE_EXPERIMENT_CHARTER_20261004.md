# TC-A Discriminative Continuation Study Charter

Date: 2026-10-04  
Status: `REGISTERED / OBSERVATIONAL DESIGN FROZEN / CONDITION INSTANTIATION NOT AUTHORIZED / EXECUTION NOT AUTHORIZED`

## 1. Purpose

This charter registers the next discriminative study only. It does not
implement a bridge, select a final Information representation, modify
InformationCore, add RelationCore, add RuntimeMemory, add search, or authorize
execution.

The research question is:

```text
Which TC-A residue structures are necessary for fresh Execution B to
complete the release-gate continuation?
```

This charter does not presuppose the answer. It also does not treat
`Information₁` as an experimental premise.

## 2. Fixed experimental frame

Every condition must preserve:

```text
carrier                   = TC-A configuration compatibility audit → release gate;
backend                   = SimiGo HTTPServer → NativeMLX;
route fix                 = SimiGo source commit 82b57f6;
model                     = peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX;
release request/constraints = identical across conditions;
generation configuration  = identical across conditions;
Execution A               = already completed and preserved;
Execution B               = fresh context;
NativeMLX cache isolation = required between every B condition;
InformationCore           = existing frozen store/fetch boundary unchanged;
schema                    = unchanged;
RelationCore              = not invoked;
RuntimeMemory             = not added;
search/list/query          = absent;
automatic Information formation = absent;
automatic projection       = absent;
bridge implementation      = absent.
```

The frozen TC-A package remains:

```text
docs/02-evidence/local-execution-information-closure/task-carrier-tc-a/
runner manifest SHA-256 =
23ac9d20ba6f43d19ac539347364b31ddd030f6bd4e96131e6f25f65225314d9
```

## 3. Variable layers

Three layers are separated. They must not be collapsed.

### Layer A — Residue representation

This layer asks what part of Execution A's residue is carried forward.

Candidate families may later be derived from the sealed TC-A residue analysis,
for example:

```text
raw model residue;
unwrapped compatibility register;
service baseline facts;
pairwise compatibility facts;
audit provenance / execution context;
combinations exposed by later analysis.
```

No candidate is selected by this charter. These labels are not an Information
schema.

### Layer B — Access condition

This layer asks whether B can locate and fetch the carried residue.

The current InformationCore has no discovery mechanism. Therefore locator is
not a sixth residue structure and must not be silently merged into Layer A.

Operational access variants must be explicit:

```text
no locator;
non-A sentinel locator;
correct Stored Information locator.
```

### Layer C — Working transformation

This layer asks whether B can transform fetched material into a release-gate
working context.

No automatic projection may be added. Any observed projection must be behavior
of the fresh B execution under the frozen prompt and tool boundary.

## 4. Semantic sufficiency versus discoverability

A failed condition must not be interpreted directly as semantic insufficiency.

For example, if a candidate is present but no locator is supplied, failure may
mean:

```text
the residue lacks semantic content;
or
B could not discover the residue;
or
B could not fetch it;
or
B could not project it into the release task.
```

Therefore, the first panel must separate:

```text
semantic sufficiency;
discoverability;
fetchability;
usability.
```

## 5. First minimal panel

The first panel uses one Candidate Structure selected in a later
condition-instantiation step. It does not select U1…U5 now.

For that selected candidate `Csel`, the minimal conditions are:

### B0 — Negative control

```text
same release request and constraints;
same fresh context and cache isolation;
same fetch tool surface;
no relevant Stored Information;
fetch uses an explicit non-A sentinel identity or the pre-registered
no-information variant.
```

Purpose: record what B can do without A's residue.

### B1 — Candidate present, locator absent

```text
Candidate Structure Csel is present in the Information copy;
B receives the same release request and constraints;
B does not receive the correct Stored Information identity;
the fetch tool surface remains present where possible.
```

Purpose: separate inaccessible candidate from no candidate.

### B2 — Candidate present, explicit locator

```text
Candidate Structure Csel is present in the Information copy;
B receives the correct Stored Information identity;
B may fetch it through the existing InformationCore boundary.
```

Purpose: observe fetch, use, behavioral change, and continuation when both
candidate and locator exist.

No higher-order matrix is authorized until B0/B1/B2 readings are preserved.

## 6. Observation chain

Every condition must record the full chain separately:

| Layer | Operational observation |
|---|---|
| Located | Whether the correct identity was supplied or discovered. Current InformationCore has no discovery, so supplied identity is the only permitted form. |
| Fetched | Whether `t4ctl fetch` returned the Stored Information successfully. |
| Parsed | Whether the fetched bytes were accepted as the frozen representation. This is boundary parsing, not a claim about internal model state. |
| Semantic reference | Whether B's observable output or intermediate text references the compatibility fields needed by the task. |
| Adopted | Whether those fields logically enter B's release decision, deployment order, or blocker reasons. |
| Behavioral | Whether B's release output differs from B0 beyond formatting. |
| Continuation | Whether B completes the release-gate phase. |
| Gain | Whether the difference relative to B0 is attributable to Stored Information plus locator. |

Strict invariants:

```text
located ≠ fetched;
fetched ≠ parsed;
parsed ≠ understood/semantic-referenced;
semantic-referenced ≠ adopted;
adopted ≠ behavioral;
behavioral ≠ continuation;
continuation ≠ gain.
```

`understood` is never inferred from hidden model state. It is recorded only
through observable task references or transformations.

## 7. Interpretation rules

A positive B2 result supports only:

```text
in this TC-A task domain, this Candidate Structure plus explicit locator
was followed by observable continuation behavior not present in B0.
```

It does not prove:

```text
the Candidate Structure is minimal;
the Candidate Structure is the correct Information representation;
locator is unnecessary;
RelationCore is necessary or unnecessary;
InformationCore explains all Agent memory;
the result generalizes beyond TC-A.
```

A B1 failure with a B2 success supports:

```text
locator/access was necessary in the tested frame.
```

A B0 success means the task does not require A's residue for the tested
observable outcome. It does not disprove all Information value.

A B1 and B2 failure after successful fetch shifts focus to representation or
projection.

No minimal structure is claimed until later ablation separates candidate,
locator, and projection.

## 8. Required evidence per condition

Each condition must preserve:

```text
fresh-context proof;
NativeMLX isolation proof;
exact B prompt;
tool surface declaration;
identity or no-identity declaration;
all requests/responses;
all fetch records and outputs;
all final answers;
Runtime lifecycle/cache trace;
database copy hash before/after;
condition label;
ordering label.
```

The panel must also preserve:

```text
condition derivation;
Candidate Structure definition;
retained/deleted field map;
B0 baseline behavior;
per-condition observation chain;
cross-condition comparison;
explicit uncertainty.
```

## 9. Non-goals

```text
No InformationCore API change.
No schema change.
No RelationCore integration.
No RuntimeMemory implementation.
No search/list/query implementation.
No automatic Information formation.
No automatic projection.
No bridge implementation.
No U1…U5 selection.
No Cloud work.
No Execution A retry.
No repair of the R-A1 residue.
```

## 10. Authorization state

```text
Charter                      = REGISTERED
Condition instantiation      = NOT AUTHORIZED
Prompt instantiation          = NOT AUTHORIZED
Task file creation            = NOT AUTHORIZED
Observer transformation rules = NOT AUTHORIZED
Execution B0/B1/B2            = NOT AUTHORIZED
InformationCore store         = NOT AUTHORIZED
Schema / Runtime change       = NOT AUTHORIZED
```
*** Update File: docs/RESEARCH_STATE.md
@@
 详细分析已封存于
 `SIMIGO_LAB_LOCAL_CLOSURE_TC_A_RESIDUE_STRUCTURAL_ANALYSIS_20261004.md`。
+
+2026-10-04 discriminative continuation charter：下一阶段登记为
+**TC-A Discriminative Continuation Study**，但条件实例化与执行均未授权。
+研究问题是 TC-A residue 中哪些结构是 fresh Execution B 完成 release-gate
+continuation 的必要条件。变量分三层：A residue representation、B access
+condition、C working transformation；locator 不许混入 residue structure。
+第一轮最小面板只设 B0 negative control、B1 candidate-present/locator-absent、
+B2 candidate-present/explicit-locator；不选择 U1–U5，不定义 Information
+schema，不实现 RelationCore/RuntimeMemory/search/automatic projection/bridge。
+观察链必须分开 located、fetched、parsed、semantic-referenced、adopted、
+behavioral、continuation、gain；禁止把 fetch 成功等同于使用或增益。
+正面 B2 只支持 task-domain-bounded 的可观察 continuation，不证明最小结构或
+正确 Information 表示。
*** End Patch
