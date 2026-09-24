# Representation Capture Feasibility Audit v0.1

## Scope

This audit determines whether the current SimiGo 2.0 Experimental Swift/MLX path already exposes a stable intermediate representation observation point without modifying MLX internals.

This document does not define a new SimiGo architecture and does not promote any representation object to formal theory.

## Current execution path

The current real-runtime path is:

model directory
→ LLMModelFactory.shared.loadContainer(...)
→ ModelContainer.perform
→ context.model(input, cache: nil)
→ logits
→ token selection

The current ChatTemplateGeneration.generate observes only model output logits and decoded tokens.

The current group gates observe model parameters, group tensor membership, parameter replacement/rematerialization, memory snapshots, and output identity. They do not observe a per-layer hidden-state sequence.

## Audit result

### A. Direct representation capture from the existing public experiment path

NOT ESTABLISHED.

The current code does not expose a generic API of the form h_i(x) = output of decoder layer i. The model call returns the model-level output used by generation. No layer-indexed intermediate representation is currently captured by the experiment harness.

### B. Parameter inventory as representation

REJECTED.

Safetensors tensor inventory identifies parameter storage, not runtime activations.

Therefore: parameter group ≠ representation, and parameter byte counts cannot be used as D-REP.

### C. Group ablation as representation capture

REJECTED.

Ablation provides an intervention effect and therefore belongs to D-ABL, not D-REP. It can answer whether removing G_i changes f(x); it cannot by itself answer what representation h_i(x) G_i produced.

### D. Model output as layer representation

REJECTED.

Final logits are a terminal model output, not a layer-indexed representation.

### E. Instrumenting model forward

OPEN / LOCAL EXPERIMENT REQUIRED.

A local instrumentation branch may be able to expose intermediate activations by wrapping or modifying the model layer execution path. That is a different experiment boundary from the current no-internals-modification runtime gate.

Such instrumentation must be explicitly labeled experimental and must not be mixed into the residency benchmark.

## Consequence for G1

G1.9 Representation Capture is not yet implementation-ready on the current public harness.

The correct next gate is G1.9-A Representation Observation Probe with two candidate routes:

1. Public-API route: identify an existing MLX Swift module/layer traversal API that permits observation without altering model semantics; if found, use it.
2. Instrumentation route: create a separate local experimental instrumentation branch; capture selected layer/group activations; compare baseline output identity before and after instrumentation; record instrumentation overhead; never treat instrumentation results as equivalent to the production runtime path.

## Required first observable

Do not capture every token/layer tensor for the pilot.

The first target should be a compact observation H_i(x) for selected group boundary i, with metadata:

- sampleID
- groupID / layer index
- token position policy
- tensor shape
- dtype
- aggregation rule
- activation checksum
- capture runtime
- baseline output identity

The aggregation rule must be frozen before category comparison.

## Evidence boundary

Representation capture can support L1 representation association. It does not establish causal demand, predictive demand, useful residency policy, or architecture-level generality.

## Current decision

G1.9 = BLOCKED_PENDING_LOCAL_API_AUDIT

Do not implement a fake representation collector from parameter tensors, final logits, or ablation scores.

The next local task is to determine whether the installed MLX Swift version exposes a safe intermediate-layer observation point. If not, create a deliberately isolated instrumentation experiment rather than modifying the existing residency harness.
