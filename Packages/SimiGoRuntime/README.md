# SimiGoRuntime

Standalone Apache-2.0 runtime package consumed by the public SimiGo app. It
contains the Execution/Runtime Contract and the MLX-backed experimental
runtime implementation.

## Products

- `SimiGoRuntimeContract` — execution and information-space runtime contracts.
- `SimiGo2Experimental` — MLX-backed experimental runtime implementation.

The Qoder transcript collection bridge lives in the separate MLX-free
[`Packages/SimiGoCollection`](../SimiGoCollection/README.md) package so that
its tests never compile the MLX dependency chain.

## Package boundary

This package deliberately excludes research documents, experiment executables,
model weights, and research-only harnesses.
