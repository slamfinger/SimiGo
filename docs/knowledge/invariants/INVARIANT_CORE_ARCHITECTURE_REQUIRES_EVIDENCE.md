# Invariant: Core architecture requires evidence

**Status:** Core invariant  
**Current baseline:** v5.0 Core Architecture Baseline

## Statement

An implementation experience becomes a core architectural invariant only after testing, real-device verification, and sustained evidence demonstrate that it is a necessary condition of architectural correctness.

A bug fix, benchmark optimum, version-specific parameter, or temporary workaround is not automatically an invariant.

## Evidence

The v5.0 architecture defines an explicit promotion path:

`Engineering problem → Lesson → Experiment/Test → Benchmark/Evidence → ADR → long-term necessity → Core Invariant`

It also explicitly excludes one-off bugs, model-specific compatibility code, version-specific thresholds, scheduler algorithms, trace fields, benchmark-optimal parameters, and temporary upstream workarounds from the core architecture.

## Consequence

The Core Architecture should become smaller and more stable as evidence accumulates, not grow with every experiment.

## Traceability

- `README_base.md`, §12–§13
- `docs/experiments/README.md`
- `docs/decisions/README.md`
