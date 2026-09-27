# SimiGo 2.0 Experimental — Local Layer Demand Protocol v0.1

Status: LOCAL EXECUTION PROTOCOL  
Prerequisite: LAYER_DEMAND_EXPERIMENT_SPEC_v0.1.md

## 1. Purpose

This protocol defines the first local experiment only.

It does not attempt to prove predictive loading. It produces the raw observations needed to decide whether Layer/Group Demand is a stable experimental phenomenon.

## 2. Fixed first target

Use one stable, already validated checkpoint/runtime combination first.

Preferred target:

- Qwen3-Coder-30B-A3B-Instruct-4bit
- the same local checkpoint used by the existing MLX residency benchmark
- the same Apple Silicon machine
- the same MLX/runtime stack

Do not broaden the model set until the first target has a clean baseline.

## 3. Experimental groups

Start with the existing validated groups:

CORE_NON_SWITCH
SWITCH_MLP_L00_15
SWITCH_MLP_L16_31
SWITCH_MLP_L32_47

The first experiment must not change group boundaries.

## 4. Dataset v0

Create a controlled prompt set with seven input-side labels:

CODE
MATH
GEOGRAPHY
ASTRONOMY
LITERATURE
ENGINEERING
GENERAL

Recommended first size:

100 prompts / category = 700 prompts.

This is a pilot, not the final corpus.

Each category should contain multiple task forms and multiple phrasings.

Recommended task-form mixture:

direct question
explanation
comparison
reasoning
calculation
generation

Keep prompts short/medium/long reasonably balanced across categories.

## 5. Sample metadata

Every prompt receives a stable ID.

Minimum metadata:

sample_id
category
task_form
length_bucket
prompt_hash
prompt_text
dataset_version

The raw prompt must be retained locally even if the result export later omits it.

## 6. Baseline run

For every sample:

1. load the unchanged model;
2. run the baseline path;
3. record the declared baseline metric;
4. record runtime metadata;
5. verify that repeated baseline runs are consistent enough for the chosen metric.

Do not start ablation until baseline behavior is valid.

## 7. Representation run

For each sample:

1. execute the model through the controlled capture path;
2. collect the representation associated with each experimental layer/group;
3. save only the agreed representation summary at first if raw tensors are too large;
4. record layer/group identity and capture point;
5. never infer semantic meaning from the representation during collection.

The first output is raw observation, not a conclusion.

## 8. Ablation run

For each sample and each optional group:

baseline
→ ablate one group
→ execute
→ measure
→ restore group
→ verify baseline restoration

Never ablate multiple groups in the first pass.

The first intervention matrix is therefore:

700 samples × 3 optional groups = 2100 ablation cases

plus baseline cases.

If the complete run is too expensive, execute a smaller pilot first while preserving category balance.

## 9. Ablation metrics

The first implementation should record at least one numerical output-level metric and one task-level metric where available.

Candidate numerical metric:

logit/probability divergence

Candidate task metric:

answer change / correctness

The exact metric must be frozen before comparing categories.

Do not select the metric after looking at which result looks strongest.

## 10. Restoration check

Every intervention must pass:

baseline
→ ablation
→ restore
→ baseline'

and verify:

baseline' ≈ baseline

according to the declared tolerance.

If restoration fails, the affected experiment batch is invalid until the cause is resolved.

## 11. Randomization / ordering

Where practical:

- randomize sample order;
- avoid running all prompts from one category in one uninterrupted block;
- record the actual execution order.

This helps distinguish category effects from thermal, memory, cache, or temporal effects.

## 12. Repetition

The pilot should repeat a subset of prompts.

Recommended:

10–20 prompts / category × 2 or more runs

The purpose is not statistical perfection; it is to detect obvious non-repeatability before scaling the dataset.

## 13. Required raw result

Each observation should be exportable in a machine-readable row containing at least:

experiment_id
sample_id
category
task_form
model_id
checkpoint_hash
group_id
baseline_metric
ablation_metric
demand_metric
runtime
hardware
timestamp

Do not export only category averages.

## 14. First analysis order

Analysis must follow this order:

### A. Integrity

- missing records;
- duplicate IDs;
- failed restores;
- baseline drift;
- runtime errors.

### B. Distribution

Inspect raw demand distributions per group.

### C. Category association

Compare groups across categories.

### D. Within-category variation

Check whether a category is internally coherent.

### E. Null comparison

Use a declared label permutation/randomization baseline.

### F. Repeatability

Compare repeated samples/runs.

### G. Effect size

Report magnitude, not only statistical significance.

No predictor is trained before A–G are complete.

## 15. Stop conditions

Stop the experiment and fix infrastructure if:

- baseline is not repeatable;
- group restoration is unreliable;
- group identity is ambiguous;
- metrics are undefined for a substantial fraction of samples;
- results depend on an undocumented runtime condition.

Do not interpret infrastructure failure as a scientific negative result.

## 16. Scientific stop conditions

Stop before predictor development if:

- group effects are indistinguishable from the declared null baseline;
- effects are highly unstable across repeated prompts;
- category effects disappear under balanced controls;
- the measured signal is dominated by prompt length/task form.

A negative result is a valid result.

## 17. What this protocol must not conclude

This first local run cannot establish:

- "knowledge is stored in layer X";
- "layer X is the code layer";
- "layer X should always be resident";
- "predictive loading works";
- "user preferences can identify useful layers";
- "SimiGo has a new general architecture".

Those require later gates.

## 18. Handoff

After the local pilot, export the raw result package and bring it back for analysis.

The next decision is determined by the data:

stable signal
    → proceed to demand structure analysis

weak signal
    → refine measurement / controls

no signal
    → test group granularity or terminate the hypothesis

Only after a stable pre-execution signal is demonstrated should a predictor be designed.
