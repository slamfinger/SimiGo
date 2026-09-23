# SimiGo 2.0 Phase 1 Qwen3-Coder Materialization Results

**Date**: 2026-09-24  
**Status**: EXPERIMENT_COMPLETE / CONTROL_PLANE_ONLY  
**Runtime**: pure Swift Safetensors selective reader; no MLX model execution

## Experiment

```bash
swift run simigo2ctl materialize MODEL_SNAPSHOT \
  --states STATE_A,STATE_B,STATE_AB,STATE_A,STATE_ALL
```

Policy: `Qwen3CoderStatePolicy`; read only newly required layer groups.

## Result

```text
loaded bytes                         = 28,052,549,632
elapsed                              = 6,905.28 ms
average throughput                   = 3,874.28 MiB/s
```

| State | Newly loaded groups | Bytes | Elapsed ms | Throughput MiB/s |
| --- | --- | ---: | ---: | ---: |
| STATE_A | CORE_NON_SWITCH, SWITCH_MLP_L00_15 | 6,309,277,696 | 1019.23 | 5903.50 |
| STATE_B | SWITCH_MLP_L16_31 | 5,435,817,984 | 1043.34 | 4968.68 |
| STATE_AB | SWITCH_MLP_L00_15 | 5,435,817,984 | 1308.65 | 3961.34 |
| STATE_A | none | 0 | 0 | 0 |
| STATE_ALL | SWITCH_MLP_L16_31, SWITCH_MLP_L32_47 | 10,871,635,968 | 3534.07 | 2933.73 |

## Interpretation

Selective Safetensors materialization by execution-state works at group granularity
without decoding tensors or entering MLX internals. The run demonstrates real
positional reads from the actual Qwen3-Coder checkpoint.

This is not yet real model inference. It also does not prove MLX Swift LM can treat
these groups as independently swappable modules during execution.

Machine-readable output:
`simigo2-experimental/results/qwen3-coder-materialization.json`
