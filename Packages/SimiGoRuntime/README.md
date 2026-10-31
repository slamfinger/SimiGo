# SimiGoRuntime

Public Apache-2.0 Swift package used by the SimiGo app.

- SimiGoRuntimeContract: Execution State, Runtime and Information Space contracts.
- SimiGo2Experimental: MLX-backed runtime implementation.

Qoder transcript collection is isolated in the MLX-free
[SimiGoCollection package](../SimiGoCollection/README.md), so its package tests
do not build the MLX dependency chain.

This package contains runtime code only; research documents, experiment
executables and model weights are maintained separately.
