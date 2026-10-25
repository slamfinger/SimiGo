# G1.9-C Measured Execution Trace Collection — Design, Pre-Run Audit, Results — 2026-09-25

Status: G19C_COLLECTION_PASS / GROUP_RESOLUTION_LOCALITY_DEGENERATE
Protocol: G1.9-C.COLLECT.V1 (registered workload traces × scenario prompts, one measured collection per model)
Boundary: ISOLATED_INSTRUMENTATION / LAYER_ENTERED_ONLY / OBSERVER_PASSIVE / DECLARED_LINE_IS_SCENARIO / MEASURED_LINE_IS_OBSERVATION / NOT_DEMAND / NOT_PREDICTION / EXPERT_DEMAND_NOT_INSTRUMENTED

ID note: the collection phase is registered as G1.9-C because G1.9-B is
already occupied (Instrumentation Identity Probe). It realizes the review's
"G1.9-B Measured Execution Trace Collection" task under the next free
identifier.

## Design (pre-run audit)

The pilot-validated passive observer is connected to the registered workload
traces. Two lines are kept separate by construction and by field:

```text
declared line : WorkloadTrace → state → declared optional groups
                (scenario declaration registered with the catalog)
measured line : Input (operation prompt) → MeasuredExecutionTrace
                (observed layerEntered events only)
```

No field asserts `state = measured demand`; the report keeps
`declaredOptionalGroupIDs` and `measuredGroupIDs` as distinct record fields
(unit-tested).

Protocol elements registered before the run:

1. **Scenario prompt registry.** One concrete input per workload operation
   (25 operations across T1–T4), declared, not measured demand; coverage of
   every catalog step is unit-tested.
2. **Identity sentinel.** Each collection run starts with a control-prompt
   baseline generation, installs the observer, and repeats the generation
   instrumented; collection proceeds only if token sequences are identical.
   All five models passed the sentinel.
3. **Registered architectural expectation.** At layer/group resolution every
   forward pass executes every decoder-layer group (registered since Gate 5
   as "generation requires all decoder-layer groups; policy controls idle
   retention"). The collection exists to convert that expectation into a
   measured fact and to quantify the declared/measured divergence.
4. **Model matrix unchanged** (pilot's five models; no expansion).

## Results — five models × four workloads (125 operations measured)

Preamble identity: 5/5 PASS. All 25 steps collected per model.

### C1–C4 on the measured line

```text
C1 recurrence         all transitions non-empty (degenerate: sets are full)
C2 transition locality  |M_t ∩ M_{t+1}| / |M_{t+1}| = 1.0 at every
                        transition, every workload, every model
C3 temporal stability   lag-1/2/3 overlap ratios = 1.0 (degenerate)
C4 working-set breadth  |M_t| = 3 (full optional set) at 100% of steps,
                        every workload, every model
```

### Declared vs measured divergence

```text
declared ⊆ measured            holds at 125/125 steps
measured \ declared non-empty  at 22/25 steps per model — exactly the steps
                               whose declared state is not STATE_ALL
                               (T3: 8 of 9; T4: 3 of 5; T1/T2: all)
```

## Measured conclusion

At Layer/Group resolution, measured execution shows **no differential
locality**: the measured working set is the full group set at every step of
every workload on every model. The declared differential demand structure
(STATE_A vs STATE_AB vs STATE_ALL) has **no counterpart in measured
execution** — declared sets are always contained in the measured full set,
and the measured set exceeds the declared set precisely where the scenario
declared a proper subset.

This converts three earlier assumptions into measured facts:

1. The Gate 5 boundary ("every complete generation requires all
   decoder-layer groups; the policy controls idle retention, not semantic
   layer skipping") now holds as measured execution evidence across five
   models and four workload shapes.
2. The declared workload traces remain scenario declarations; their
   differential structure is not an execution fact at this resolution.
3. The reload reductions measured earlier are real intervention effects of
   the retention policy responding to declared scenarios (idle-retention
   economics), not exploitation of measured execution locality.

## Consequences for the research chain

```text
Measured Execution → Temporal Locality → Intervention Value → Predictor?
```

- **Temporal locality at group resolution: measured DEGENERATE.** There is
  no differential execution signal at this resolution for a Predictor to
  predict — execution is uniform. `PREDICTOR_STOP_GATE_NO_GO` is now
  confirmed by measurement, not only by source-legitimacy argument.
- **Intervention value** remains registered as an idle-retention economics
  result under declared scenarios (reload −16.7–55% vs naive); it does not
  rest on measured execution locality.
- **Where differential execution could live** is now localized below group
  resolution (per-token routing / expert activation; the trace's ×8 top-k
  shape hint was already removed from the observation schema). Observing it
  means instrumenting Router/Expert — explicitly NOT authorized. Opening
  that resolution is a new authorization decision, not a continuation.

No new runtime capability, no predictor, no async I/O, no production MLX
modification, and no general-architecture claim follows from this phase.
A2.0 remains FROZEN/TERMINAL.

## Artifacts

```text
simigo2-experimental/results/g19-collect/{qwen3-coder-30b,nail-qwen36-35b,
  cyber-tiel-35b,gemma4-12b-coder,muse-glimmer-30b}.json
simigo2-experimental/results/g19-collect/analysis/measured-locality.json
simigo2-experimental/scripts/analyze_measured_locality.py
```
