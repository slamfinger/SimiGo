# Representation Consistency Boundary — Cross-Backend Evidence Unit

> **ARCHIVED** 2026-10-20 · line: 通用治理 / 其他 · original: docs/00-governance/SIMIGO_LAB_REPRESENTATION_CONSISTENCY_CROSS_BACKEND_EVIDENCE_UNIT_20261004.md
> Evidence status: unchanged (content frozen; moved only)


Date: 2026-10-04  
Status: `SEALED / EVIDENCE UNIT / CROSS-BACKEND REPLICATION PASS / BOUNDED`  
Scope: MLX prefix-recompute slice and llama-server full-prefix slice only.

## 1. Evidence-unit question

This unit consolidates two already-executed experiments. It does not create a
new experiment, revise the Execution State Contract, add integrity machinery,
or generalize to other representations.

The consolidated observable relationship is:

```text
same Execution ID
same logical position
same representation position
same representation length
different representation content
    ↓
existing binding / position checks do not reject the content mutation
    ↓
real backend execution occurs
    ↓
stable observable output divergence
```

## 2. Replication registry

| Replication | Backend | Code commit | Evidence commit | Raw evidence |
| --- | --- | --- | --- | --- |
| 1 | MLX prefix-recompute | `3b1d4353d63b1350fbbd7d343137cc2410e65937` | `bf968c8` | `docs/02-evidence/repconsistency-boundary-20261004/` |
| 2 | llama-server full-prefix | `716ff1d3e37af93a4fce413e1b2d5d1d1c72e73b` | `0fe4a2d` | `docs/02-evidence/llama-representation-consistency-20261004/` |

## 3. Replication 1 — MLX

Model slice:

```text
Nail-Qwen3.6-35B-A3B-MLX
snapshot 31a0106483c94e9fbb0a6d3360ff122d47377058
model type = Qwen35MoEModel
```

### Position boundary

C1 and C3 used representation position `999` while logical position remained
`0`.

```text
coordinator binding       = accepted
backend execution         = rejected before MLX loop
detection layer           = MLXExecutionStateBackend.boundPrefix(for:)
error                     = representationPositionMismatch(bound=999, logical=0)
real MLX execution        = NO
logical position advanced = NO
```

This position-rejection observation is MLX-slice evidence. The minimal llama
replication did not run C1/C3.

### Content mutation

Fixed conditions:

```text
Execution ID            = repconsistency-single
logical position        = 0
representation position = 0
representation length   = 10 tokens
content mutation        = token index 8: 9017 -> 9018
generation              = greedy argMax, cache nil, seed 42, max 12
```

C0:

```text
real MLX execution = YES
token IDs          = [271,248068,271,248069,271,27775,383,279,1928,3766,11,488]
text prefix        = "...Based on the information provided, you"
position           = 0 -> 1
```

C2:

```text
C2.rep1 token IDs = [271,248068,198,8160,579,264,7047,1817,25,271,16,13]
C2.rep2 token IDs = C2.rep1
C2.rep3 token IDs = C2.rep1

C2.rep1/2/3 != C0
real MLX execution = YES
logical position   = 0 -> 1
```

## 4. Replication 2 — llama-server

Model slice:

```text
Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
llama.cpp server 0.5.0-dev build 11284 commit 25747b08
```

Fixed conditions:

```text
Execution ID            = llama-repconsistency-single
logical position        = 0
representation position = 0
representation length   = 10 tokens
content mutation        = token index 8: 9017 -> 9018
generation              = llama-server greedy completion, temperature 0,
                          seed 42, prediction tokens 12
```

C0:

```text
backend binding accepted = YES
real llama execution     = YES
token IDs                = [198,760,2313,6025,16699,10492,5435,2313,6044,9017,13,198]
text                     = "\nThe project directory ReferenceFiles contains project management documents.\n"
logical position         = 0 -> 1
```

C2:

```text
C2.rep1 token IDs = [198,760,2313,6025,16699,10492,5435,2313,6044,9018,13,198]
C2.rep2 token IDs = C2.rep1
C2.rep3 token IDs = C2.rep1

C2.rep1/2/3 != C0
backend binding accepted = YES
real llama execution     = YES
logical position         = 0 -> 1
```

The minimal llama experiment did not run position mismatch cells. Therefore no
llama position-boundary claim is made by this evidence unit.

## 5. Sealed wording

The evidence unit supports only this bounded statement:

> **Representation Consistency Boundary：在 MLX prefix-recompute 与
> llama-server full-prefix 两个 backend 的受控实验中，position mismatch 可被
> 现有 backend boundary 拒绝，而同位置、同长度的 content mutation 可穿过现有
> 检查并进入真实执行，稳定造成 observable output divergence；该关系目前已完成
> cross-backend replication，但尚未外推至其他 representation、backend 或完整
> Execution State integrity 理论。**

More precisely:

```text
content-mutation acceptance/output divergence:
  replicated on MLX and llama-server.

position-mismatch rejection:
  observed directly in the MLX C1/C3 slice.
  not tested by the minimal llama C0/C2 replication.
```

## 6. Non-claims

```text
不主张完整 Execution State integrity 理论；
不主张 I/P/A/C 数学最小性或不必要性；
不主张该行为 backend-independent；
不主张 KV-cache、persistent restore、并发、采样或生产 pipeline 同行为；
不主张 semantic correctness 或输出质量；
不授权新增 hash / anchor / provenance / consistency gate；
不重开 Execution State Contract；
不把 information.sqlite 缺行直接等同于“Information 缺失”。
```

## 7. Raw evidence registry

```text
MLX result JSON
docs/02-evidence/repconsistency-boundary-20261004/result.json

MLX result governance
docs/00-governance/SIMIGO_LAB_REPCONSISTENCY_BOUNDARY_RESULT_20261004.md

llama result JSON
docs/02-evidence/llama-representation-consistency-20261004/result.json

llama result governance
docs/00-governance/SIMIGO_LAB_LLAMA_REPCONSISTENCY_RESULT_20261004.md

llama server runtime log
docs/02-evidence/llama-representation-consistency-20261004/server.log
```

## 8. Closure effect

```text
Representation Consistency Boundary Evidence Unit = SEALED
Third-backend expansion                           = NOT AUTHORIZED BY THIS UNIT
Contract revision                                 = NOT AUTHORIZED BY THIS UNIT
Integrity mechanism implementation                = NOT AUTHORIZED BY THIS UNIT
Next research direction                           = HUMAN DECISION
```
