# SimiGo Lab Cyber-Tiel MLX E5 and Cross-Backend Token Observation — 2026-09-29

## Results

```text
E5_CYBER_TIEL_MLX = PASS / QWEN35MOE_REAL_RUNTIME_SCENARIO
CROSSBACKEND_TOKEN_OBSERVATION = PASS_WITH_BOUNDARY / SEQUENTIAL_TWO_PHASE
MLX_LLAMA_GREEDY_TOKEN_IDENTITY = 3/3 PROMPTS
RESOURCE_SWAP_DELTA = 0 BYTES IN BOTH PHASES
```

登记：

```text
CYBER_TIEL_QWEN35MOE_E5_PASS
CYBER_TIEL_MLX_RECORD_PHASE_PASS
CYBER_TIEL_LLAMA_COMPARE_PHASE_PASS
NAMED_SOURCE_GREEDY_TOKEN_IDENTITY_OBSERVED
RESOURCE_ISOLATED_SEQUENTIAL_BACKEND_OBSERVATION_PASS
```

## Artifact identity

| Side | Artifact | Runtime / model type |
| --- | --- | --- |
| MLX | `peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e` snapshot `b867c9da...` | MLXLLM `Qwen35MoEModel`, `qwen3_5_moe` |
| GGUF | `peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-GGUF-MTP-UD-Q4_K_XL` | llama-server canonical mitigated profile |

两者按 repo/model 名称视为 named-source Cyber-Tiel variants；不是 byte-identical
checkpoint，也不是 same-checkpoint closure。MLX 为 oQ4e quantization，GGUF 为
UD-Q4_K_XL quantization，执行引擎也不同。

## E5 Cyber-Tiel MLX

协议：

```text
G1.9-E5.SCENARIO.V2
max tokens = 12
```

六项 identity assertions全部 PASS：

| Check | Result |
| --- | --- |
| `FORK_DIVERGENCE` | PASS |
| `CHILD_DETERMINISM_THROUGH_RESOURCE_CYCLE` | PASS |
| `PARENT_NON_INTERFERENCE` | PASS |
| `PARENT_IDENTITY_STABLE` | PASS |
| `CHILD_LINEAGE_TRACEABLE` | PASS |
| `RESIDENCY_INV1` | PASS |

child在 evict → rematerialize → restore 后继续生成 token-identical；parent在
child discard后继续生成与 pre-fork reference一致。residency replay identical。

Artifact：

```text
simigo2-experimental/results/e5-execution-state/cyber-tiel-coder-35b.json
```

## Two-phase cross-backend token observation

前一版 combined probe曾因同时驻留 MLX与 llama-server进入大量 swap，已废弃。
正式 protocol拆成两个 process interval：

```text
Phase 1 MLX only
  render checkpoint chat-template prompt IDs
  run greedy generation
  write immutable record
  exit

Phase 2 llama only
  read Phase 1 record
  submit identical prompt token IDs
  run greedy generation
  compare token IDs
```

配置：

```text
max tokens       = 12
seed             = 42
llama profile    = canonical mitigated ubatch8 / parallel4 / cache disabled
swap delta limit = 512 MiB
```

### Phase 1 — MLX only

```text
status               = PASS_WITH_BOUNDARY
model type           = Qwen35MoEModel
prompt token counts  = P1 197 / P2 197 / P3 195
generated lengths    = P1 2 / P2 12 / P3 11
max swap delta       = 0 bytes
peak MLX bytes       = 21,103,830,324
peak footprint       = 21,308,833,344 bytes
```

P1/P3遇到 EOS；P2用满 12-token budget。所有 generations nonempty and bounded。

### Phase 2 — llama only

```text
status               = PASS_WITH_BOUNDARY
record SHA-256       = 28a7c919c41a874c4eae49ca894104b55747e3cffbc978773eeae24d3a0215f0
max swap delta       = 0 bytes
output identity      = 3/3
```

| Prompt | Prompt tokens | MLX generated | LLAMA generated | Token identity |
| --- | ---: | ---: | ---: | --- |
| P1 `Return exactly one word: ping` | 197 | `[9694,248046]` | `[9694,248046]` | PASS |
| P2 `Count from one to twelve.` | 197 | `12` tokens | `12` tokens | PASS |
| P3 `Name five colors.` | 195 | `11` tokens | `11` tokens | PASS |

 decoded text也一致：

```text
P1 = ping
P2 = 1, 2, 3, 4, 
P3 = Red, blue, green, yellow, purple.
```

## Validation

```text
Swift tests = 157 PASS / 0 FAIL
```

## Artifacts

```text
simigo2-experimental/results/e5-execution-state/cyber-tiel-coder-35b.json
simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-mlx-record.json
simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-token-compare.json
```

实现：

```text
UIBranchSessions-style E5 scenario
CrossBackendTokenProbe.runRecord
CrossBackendTokenProbe.runCompare
CLI: cross-backend-token-record / cross-backend-token-compare
```

## Boundary

结果限定 named-source Cyber-Tiel MLX/GGUF variants、three short prompts、greedy
decode、12-token budget、observed 197/197/195-token prefixes、canonical LLAMA
profile、MLX oQ4e quantization、GGUF UD-Q4_K_XL quantization和本机。两个 backend
顺序运行，未同时驻留。

这是 observed token identity，不是：

```text
❌ same-checkpoint closure
❌ tokenizer-file identity proof
❌ quantization equivalence
❌ all-prompt semantic equivalence
❌ performance equivalence
❌ Execution State universal closure
```

GGUF 是 MTP artifact；本实验不拆解 MTP draft/verify机制。token identity只在
actual greedy output层观察。

## Next

1. 用更多 prompt families、longer prefixes和 rejection/decoding cases扩展
   named-source token identity matrix。
2. 用 GGUF metadata extractor与 MLX checkpoint manifest建立 tokenizer/model
   lineage audit。
3. 只有同一 checkpoint bytes或可证明等价转换时，才可重开
   same-checkpoint cross-backend closure。
