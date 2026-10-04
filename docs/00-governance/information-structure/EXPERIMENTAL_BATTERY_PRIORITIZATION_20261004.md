# Experimental Battery Prioritization

Date: 2026-10-04  
Status: `SCHEDULING / DEPENDENCY MAP / ROUND-1 SELECTION FROZEN / PROMPT INSTANTIATION AND RUNTIME NOT AUTHORIZED`

## 1. Source

`docs/00-governance/information-structure/reduction-design-20261004.json`  
SHA-256: `076824f1e0f295fffee95d4388e60b31168e5e4f9318f6434f09c95205a44625`

## 2. Scheduling rule

Select the smallest dependency-aware first battery with the highest information gain. Do not run all seventeen designs.

## 3. Round-1 selection — frozen

```text
R-D2   representation form substitution
R-D5   explanation / decision separation
R-D1A  structured aggregation probe
R-D3   delete M2.b while retaining M1.b
R-D4   M1 level factorial with M2.b fixed
R-D8   source validity / staleness probe
R-D9   tool evidence probe
```

`R-D1` is split into `R-D1A` and `R-D1B`; only `R-D1A` enters round 1. `R-D1B` waits for `R-D5` and `R-D1A`.

This freezes battery selection only. It does **not** authorize condition prompts, runtime requests, adjudication, Observer, or store.

## 4. Round-1 sequence

| Stage | Conditions | Parallel | Reason |
|---|---|---|---|
| 1A | `R-D2`, `R-D5`, `R-D8`, `R-D9` | yes | Low-dependency foundational controls. |
| 1B | `R-D3`, `R-D4` | yes | Semantic-core factorial after representation and explanation controls are known. |
| 1C | `R-D1A` | no | Aggregation probe after explanation policy is fixed and representation baseline is known. |

## 5. Candidate reach

| Battery | Canonical group | Candidate atoms | Reading |
|---|---|---:|---|
| `R-D2` | `representation_form` | 68 | MAXIMUM_CANDIDATE_REACH_NOT_RESOLUTION |
| `R-D5` | `issue_explanation` | 50 | MAXIMUM_CANDIDATE_REACH_NOT_RESOLUTION |
| `R-D1A` | `persistence_aggregation` | 16 | MAXIMUM_CANDIDATE_REACH_NOT_RESOLUTION |
| `R-D3/R-D4` | `baseline_decision` | 26 | MAXIMUM_CANDIDATE_REACH_NOT_RESOLUTION |
| `R-D3/R-D4` | `pair_decision` | 24 | MAXIMUM_CANDIDATE_REACH_NOT_RESOLUTION |
| `R-D8` | `provenance_integrity` | 94 | PARTIAL_REACH_ONLY_HASH_AND_SOURCE_ATOMS |
| `R-D9` | `tool_evidence` | 23 | MAXIMUM_CANDIDATE_REACH_NOT_RESOLUTION |
| **Upper bound** | — | **301** | Touch is not resolution. |

## 6. Dependency / resolution map

| ID | Round | Hard dependencies | Soft dependencies | Can be deconfounded/resolved by | Status |
|---|---|---|---|---|---|
| `R-D1` | — | — | `R-D2`, `R-D5` | — | SPLIT_INTO_CHILD_DESIGNS |
| `R-D10` | 2 | — | `R-D2` | `R-D2` | DEFERRED_HIGH_VALUE |
| `R-D11` | 2 | `R-D10` | `R-D2` | `R-D10`, `R-D2` | DEFERRED_DEPENDENCY_GATE |
| `R-D12` | 2 | `R-D10`, `R-D11` | `R-D2` | `R-D10`, `R-D11`, `R-D2` | DEFERRED_DEPENDENCY_GATE |
| `R-D13` | 3 | `R-D12` | `R-D2` | `R-D12`, `R-D2` | DEFERRED_DEPENDENCY_GATE |
| `R-D14` | 3 | `R-D12` | `R-D3`, `R-D4`, `R-D13` | `R-D12`, `R-D13`, `R-D3`, `R-D4` | DEFERRED_DEPENDENCY_GATE |
| `R-D15` | 2 | `R-D4`, `R-D5` | `R-D2` | `R-D4`, `R-D5`, `R-D2` | DEFERRED_HIGH_VALUE |
| `R-D16` | 3 | `R-D15`, `R-D4`, `R-D5` | `R-D2` | `R-D15`, `R-D4`, `R-D5`, `R-D2` | DEFERRED_DEPENDENCY_GATE |
| `R-D17` | 3 | `R-D2`, `R-D4`, `R-D5` | `R-D8`, `R-D9` | `R-D2`, `R-D4`, `R-D5`, `R-D8`, `R-D9` | DEFERRED_DEPENDENCY_GATE |
| `R-D1A` | 1 | `R-D5` | `R-D2` | `R-D5`, `R-D2` | SELECTED_FROZEN |
| `R-D1B` | 2 | `R-D5`, `R-D1A` | `R-D2` | `R-D5`, `R-D1A` | DEFERRED_DEPENDENCY_GATE |
| `R-D2` | 1 | — | — | — | SELECTED_FROZEN |
| `R-D3` | 1 | — | `R-D2`, `R-D5`, `R-D4` | `R-D4`, `R-D2`, `R-D5` | SELECTED_FROZEN |
| `R-D4` | 1 | — | `R-D2`, `R-D5`, `R-D3` | `R-D3`, `R-D2`, `R-D5` | SELECTED_FROZEN |
| `R-D5` | 1 | — | `R-D2` | — | SELECTED_FROZEN |
| `R-D6` | 3 | — | `R-D14`, `R-D4` | `R-D14`, `R-D4` | DEFERRED_LOW_DEPENDENCY_PRIORITY |
| `R-D7` | 3 | `R-D8`, `R-D9` | `R-D10` | `R-D8`, `R-D9`, `R-D10` | DEFERRED_DEPENDENCY_GATE |
| `R-D8` | 1 | — | `R-D2` | — | SELECTED_FROZEN |
| `R-D9` | 1 | — | `R-D2` | — | SELECTED_FROZEN |

## 7. Round-1 resolution rules

### Representation — `R-D2`

If forms are equivalent, representation-only variants become packaging candidates. If they differ, representation is load-bearing.

### Explanation — `R-D5`

If no continuation loss, issue explanations become candidate-reducible and R-D1 is deconfounded. If continuation loss, explanations are load-bearing.

### Aggregation — `R-D1A`

If whole register equals structured facts, register packaging is not an independent semantic core. If not, aggregation is a distinct boundary.

### Semantic core — `R-D3` + `R-D4`

The factorial can yield: both required; M2.b sufficient; M1.b sufficient; neither required; or only the conjunction sufficient. Every reading is bounded to the current frame.

### Provenance — `R-D8` + `R-D9`

If tested provenance has no effect, it remains validity/audit structure. If it changes adoption or continuation, provenance enters the Information-relevant core for this frame.

## 8. Deferred groups

```text
Round 2: R-D10, R-D11, R-D12, R-D15, R-D1B;
Round 3: R-D13, R-D14, R-D16, R-D17, R-D6, R-D7;
Conditional: broad M3 only after R-D8/R-D9 component effects are known.
```

## 9. Boundary

```text
prompt instantiation             = NOT AUTHORIZED;
runtime execution               = NOT RUN;
Observer                         = NOT RUN;
InformationCore store            = NOT RUN;
schema/API change                = NOT MADE;
minimal structure claim          = NOT MADE;
irreducibility claim             = NOT MADE.
```
