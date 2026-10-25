# SimiGo Lab Named-Source Lineage Audit — 2026-09-29

## Result

```text
LINEAGE_AUDIT = PASS_WITH_BOUNDARY / TOKENIZER_SUBSTRATE_AND_DECLARED_LINEAGE
BASE_VOCAB = 248044 / 248044 EXACT
ADDED_TOKENS = 26 / 26 EXACT
MERGES = 247587 / 247587 EXACT
CHAT_TEMPLATE = EXACT
SOURCE_LINEAGE_CHAIN = PASS
CHECKPOINT_IDENTITY = OPEN / WEIGHT_BYTES_NOT_COMPARED
```

登记：

```text
CYBER_TIEL_GGUF_MLX_TOKENIZER_SUBSTRATE_EXACT
CYBER_TIEL_SOURCE_LINEAGE_CHAIN_MATCH
CYBER_TIEL_PUBLICATION_ALIAS_CORRECTION
SAME_CHECKPOINT_CLOSURE_STILL_OPEN
```

## Important terminology correction

路径/发布名中的 **CyberTiel** 是 publication/build alias，不是独立 base source。
Audit 后的准确 lineage chain是：

```text
Ornith 1.5 35B A3B
  → huihui-ai/Huihui-Ornith-1.5-35B-A3B-abliterated
  → CyberTiel MLX oQ4e / CyberTiel GGUF UD-Q4_K_XL
```

因此此前 profile/report中的 “named-source Cyber-Tiel variants”必须理解为
**shared Ornith/Huihui lineage下的 CyberTiel publication pair**，不能理解为
same-checkpoint identity。

## Artifacts audited

| Side | Artifact |
| --- | --- |
| GGUF | `peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-GGUF-MTP` `UD-Q4_K_XL` |
| MLX | `peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e` snapshot `b867c9da...` |

## Declared lineage chain

### GGUF metadata

```text
general.name       = Huihui Ornith 1.5 35B A3B Abliterated
general.basename   = Huihui-Ornith-1.5
general.finetune   = abliterated
base model name    = Ornith 1.5 35B A3B
base organization  = Ornith Ai
base URL           = https://huggingface.co/ornith-ai/Ornith-1.5-35B-A3B
architecture       = qwen35moe
```

### MLX declaration

```text
architecture = qwen3_5_moe / Qwen3_5MoeForConditionalGeneration
README base  = huihui-ai/Huihui-Ornith-1.5-35B-A3B-abliterated
```

normalized architecture匹配；README base与 GGUF substrate/upstream形成同一
lineage chain。`SOURCE_LINEAGE_CHAIN_MATCH = PASS`。

## Tokenizer substrate

| Item | GGUF | MLX | Result |
| --- | ---: | ---: | --- |
| Base vocab | 248044 | 248044 | EXACT |
| Added tokens | first 26 after base | 26 | EXACT |
| BPE merges | 247587 | 247587 | EXACT |
| Chat template | metadata template | `chat_template.jinja` | EXACT |
| Tokenizer model | `gpt2` | `BPE` | compatible |

Mismatch counts：

```text
base vocab mismatch = 0
added token mismatch = 0
merge mismatch = 0
```

## Matrix vocabulary boundary

GGUF total tokens为 248320，比 MLX shared tokenizer多 250个：

```text
control tokens = 7
padding tokens = 243
```

这些 extra tokens从 ID `248070`开始。Matrix V2实际使用的最大 token ID为
`248069`，因此 **all Matrix V2 prompt/generated IDs lie inside the shared
tokenizer substrate**。

```text
used unique token IDs = 294
max used token ID     = 248069
shared vocab limit    = 248070
outside shared vocab  = 0
```

## Checkpoint identity

本 audit没有比较 weight bytes、tensor values、dequantized tensors或 numerical
equivalence。因此：

```text
CHECKPOINT_IDENTITY = OPEN / WEIGHT_BYTES_NOT_COMPARED
```

Tokenizer exact不等于 checkpoint same；MLX oQ4e和 GGUF UD-Q4_K_XL仍是不同
quantization payload。

## Validation

```text
script syntax               = PASS
artifact JSON assertions    = PASS
```

## Artifacts

```text
simigo2-experimental/scripts/named_source_lineage_audit.py
simigo2-experimental/results/backend-conformance/named-source-cyber-tiel-lineage-audit.json
```

Audit source compare anchor：

```text
SHA-256 = 6e86c2c560a3994afa0b47bbd0513ed4d0ee7a4a4c34093b9751f6f47313409a
```

## Boundary

结果限定当前 local GGUF/MLX snapshots、GGUF V3 metadata、MLX tokenizer/config/
README/chat template和 Matrix V2 used token IDs。不建立 same-checkpoint
closure、dequantized weight equality、runtime equivalence、performance
equivalence或 cross-architecture Qwen4Exp closure。

## Non-claims

```text
❌ same checkpoint bytes
❌ dequantized weight equality
❌ full tokenizer implementation equivalence
❌ GGUF MTP root cause已定位
❌ profile升级为 cross-checkpoint closure
```

## Next

1. 若要重开 same-checkpoint研究，需比较 source safetensors与 GGUF tensor
   dequantized values，而不是只比较 metadata。
2. 新 prompt set必须复跑本 lineage audit，特别是 extra-token boundary。
3. Named-source profile V1继续限定为 shared Ornith/Huihui tokenizer substrate；
   不得解释为 checkpoint closure。
