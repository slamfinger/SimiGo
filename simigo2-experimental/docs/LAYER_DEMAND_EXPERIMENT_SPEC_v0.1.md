# SimiGo 2.0 Experimental — Layer Demand Research Specification v0.1

Status: EXPERIMENTAL / PRE-OBSERVATION  
Scope: Layer/group demand discovery only  
A2.0 status: FROZEN / UNAFFECTED

## 1. Research question

The current experimental question is:

> For a fixed model and input, do different layer-groups exhibit stable, repeatable, input-dependent demand signals that can later be predicted before full execution?

The experiment does **not** assume that knowledge is partitioned by layer, and does not assume that a layer corresponds to a semantic category such as code, mathematics, geography, literature, or astronomy.

The first objective is to determine whether an observable structure exists at all.

## 2. Research boundary

This phase studies:

```
input
  ↓
representation / intervention
  ↓
group-level demand signal
  ↓
repeatability / predictability
```

It does not yet implement:

- predictive loading;
- user-preference weighting;
- future-state probabilities;
- layer skipping;
- reduced Transformer computation;
- a general SimiGo architecture;
- any modification to A2.0.

The existing execution-state/residency experiment remains an independent engineering baseline.

## 3. Terminology

### 3.1 Input

A controlled prompt or task instance supplied to the model.

Denote it by:

[
x
]

### 3.2 Representation

A model-internal activation or representation associated with a layer or layer-group during execution.

Denote:

[
H_i(x)
]

Representation evidence can establish correlation or information availability, but by itself does not establish causal necessity.

### 3.3 Group

A reproducible parameter/compute partition used by the experimental harness.

A group is an engineering unit, not automatically a semantic unit.

Examples in the current Qwen3-Coder experiment:

```
CORE_NON_SWITCH
SWITCH_MLP_L00_15
SWITCH_MLP_L16_31
SWITCH_MLP_L32_47
```

### 3.4 Demand signal

A measured quantity intended to characterize the importance or dependency of group (G_i) for input (x).

At this stage demand is deliberately **not** defined as a probability.

Candidate demand families are kept separate.

## 4. Demand evidence families

### D-REP: representation association

A probe evaluates whether (H_i(x)) contains information predictive of an input/task attribute.

[
D^{rep}_i(x)
]

This supports statements such as:

> The representation at group/layer (i) is associated with the measured task attribute.

It does not support:

> Group (i) is responsible for that knowledge.

### D-ABL: intervention sensitivity

Remove, replace, or otherwise ablate group (G_i), then compare the resulting behavior with the baseline.

[
D^{abl}_i(x)
=
Dist(f(x), f_{-G_i}(x))
]

Possible distance measures include:

- logit divergence;
- probability divergence;
- loss delta;
- answer-level change;
- task accuracy delta.

The exact metric must be declared by each experiment.

D-ABL is stronger evidence of functional dependence than D-REP, but still depends on the intervention being well controlled.

### D-EXEC: execution demand

A future experiment may measure whether a group is actually required or accessed by a computation path.

[
D^{exec}_i(x)
]

This is the most directly relevant quantity for predictive residency, but it is not assumed to be available in the current complete-generation MLX path.

## 5. Evidence ladder

Claims must not exceed the strongest available evidence.

| Level | Evidence | Permitted conclusion |
|---|---|---|
| L0 | no signal | no established structure |
| L1 | representation association | representation/task association |
| L2 | controlled ablation effect | functional sensitivity to group intervention |
| L3 | repeated/cross-template stability | repeatable group-demand pattern |
| L4 | pre-execution prediction | demand is predictable from input-side information |
| L5 | runtime intervention benefit | prediction improves residency/runtime outcome |

A semantic statement such as "group G is the code layer" is not permitted from L1 alone.

## 6. Controlled input design

The initial dataset should use input-side categories only as experimental labels.

Suggested categories:

- CODE
- MATH
- GEOGRAPHY
- ASTRONOMY
- LITERATURE
- ENGINEERING
- GENERAL

These labels are not hypotheses about model-internal layer semantics.

Each category should vary independently across:

- task form;
- difficulty;
- prompt length;
- wording/template;
- concrete subject matter.

At minimum, task forms should include several of:

- direct question;
- explanation;
- comparison;
- reasoning;
- calculation;
- generation.

## 7. Control variables

The following must be recorded and, where practical, balanced:

- model/checkpoint identity;
- checkpoint hash;
- tokenizer/runtime version;
- MLX version;
- hardware;
- prompt length;
- output-token limit;
- prompt template;
- task form;
- category;
- random seed where applicable;
- group definition;
- experiment timestamp.

Prompt length and task form must not be allowed to become hidden proxies for category.

## 8. Null hypothesis

The initial null hypothesis is:

[
H_0:
	ext{group demand has no stable relationship with the chosen input-side category/task labels}
]

A category/group association must be compared against an appropriate null baseline, such as label permutation or another declared randomization procedure.

A visually interesting heatmap is not sufficient evidence.

## 9. Stability

A candidate demand pattern must be tested across independent or held-out prompt subsets.

A pattern should not be treated as structural merely because it appears in one hand-selected prompt set.

At minimum compare:

```
same category / different wording
same category / different task form
same task / different subject
held-out prompts
repeated runs
```

The first stability question is:

> Does the same group-demand pattern recur when the exact wording changes?

## 10. Representation versus demand

The experiment must preserve this distinction:

```
representation ≠ demand
demand ≠ residency
residency ≠ computation
```

A representation probe may show that information is encoded at a layer without showing that the layer is necessary.

An ablation effect may show functional sensitivity without proving a clean semantic specialization.

A residency policy is an engineering response to an observed or predicted demand signal; it is not itself evidence that the signal exists.

## 11. Group granularity

The first experiments should use the currently validated group boundaries rather than immediately optimizing group size.

If no stable signal is found, possible explanations include:

1. no meaningful group-demand structure exists;
2. the chosen groups are too coarse;
3. the chosen groups are too heterogeneous;
4. the measured demand metric is inadequate;
5. the task dataset is confounded.

Changing group granularity is therefore a later diagnostic step, not an automatic rescue mechanism.

## 12. Required first data product

The first major experimental artifact should be a prompt-by-group demand matrix:

[
M_{x,i}=D_i(x)
]

Conceptually:

```
                 G0       G1       G2       G3
prompt-001      ...      ...      ...      ...
prompt-002      ...      ...      ...      ...
prompt-003      ...      ...      ...      ...
...
```

The matrix should retain raw observations and metadata rather than only aggregated category averages.

## 13. Experimental gates

### G0 — theory boundary

This specification exists and the experiment does not alter A2.0.

### G1 — harness validity

The same model/checkpoint can be loaded, measured, intervened on, and restored without corrupting the baseline.

### G2 — baseline repeatability

The baseline output/measurement is repeatable under the declared runtime conditions.

### G3 — representation observability

Layer/group representation measurements can be collected reproducibly.

### G4 — intervention validity

Group ablation/replacement can be performed and restored, with baseline recovery verified.

### G5 — demand structure

A non-trivial group-demand pattern survives controlled repetition and null-model checks.

### G6 — predictability

A demand signal can be predicted from information available before full execution, with held-out evaluation.

### G7 — predictive residency

Only after G6 may predictive preload be implemented and compared with ALL_RESIDENT and REACTIVE baselines.

### G8 — runtime effect

Only after G7 may any end-to-end residency/runtime benefit be evaluated.

Failure at a gate does not authorize automatic promotion to the next gate.

## 14. Local-only boundary

The following must be executed on the user's local Apple Silicon/MLX environment:

- real checkpoint loading;
- real activation/representation capture;
- real parameter/group intervention;
- real model restoration;
- complete dataset execution;
- memory and runtime measurement.

Repository inspection, experiment schema, analysis code, statistical analysis, and result interpretation can be prepared independently.

Local measurements cannot be replaced by GitHub inspection or simulator output.

## 15. Next implementation step

The next engineering step is limited to experimental infrastructure:

1. experiment manifest schema;
2. sample metadata schema;
3. representation-capture interface;
4. ablation-result schema;
5. raw prompt-by-group result format;
6. validation/restore checks.

Do **not** implement a predictor or predictive preload policy yet.

## 16. Interpretation rule

The strongest acceptable conclusion is always the strongest conclusion directly supported by the current evidence.

In particular:

```
"correlated"
≠ "causal"

"causal sensitivity"
≠ "predictable"

"predictable"
≠ "worth preloading"

"worth preloading"
≠ "runtime benefit"
```

The purpose of this experiment is to discover whether the missing arrows can be established one at a time.

## 17. Relationship to existing execution-state work

The current execution-state experiment remains:

```
external execution label
→ desired resident groups
→ retain/release
→ next transition
```

The new research asks whether a future input-side signal can eventually precede that policy:

```
input
→ demand estimate
→ residency decision
→ execution
→ observed state
```

This is an extension of the experimental route, not a modification of the frozen A2.0 theory.


## 18. Workload-context extension recorded 2026-09-24

The research scope is broadened by `docs/WORKLOAD_CONTEXT_RESIDENCY_PLAN_v0.1.md`.

The existing input-dependent pilot remains valid, but it is no longer treated as the sole representative workload. A second experimental branch covers DOCUMENT, COMPUTER_OPERATION, and AGENTIC_MULTI_TURN workloads, with execution-context metadata and temporal-locality measurements.

The existing `CORE_NON_SWITCH` grouping is not promoted to a scientifically established Core Resident Set. Core/Working-Set/Cold classifications remain empirical residency hypotheses.

The intended chain is now:

```
workload/input + execution context
→ group demand
→ temporal locality
→ predictability
→ residency intervention
→ runtime trade-off
→ architecture decision only if evidence warrants it
```

No predictive loader, probability model, new formal state object, or architecture is introduced by this extension.
