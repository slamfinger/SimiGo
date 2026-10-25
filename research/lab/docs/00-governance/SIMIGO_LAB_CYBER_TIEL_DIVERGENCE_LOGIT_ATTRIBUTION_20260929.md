# SimiGo Lab Cyber-Tiel Divergence Logit Attribution — 2026-09-29

## Result

```text
LOGIT_ATTRIBUTION = PASS_WITH_BOUNDARY / THREE_DIVERGENCE_CASES
TOP1_AGREEMENT = 0/3
ALL_ALT_IN_OTHER_TOP2 = 3/3
```

登记：

```text
CYBER_TIEL_DIVERGENCE_TEACHER_FORCED_TOPK_PASS
NEAR_BOUNDARY_TOP1_DIVERGENCE_OBSERVED
NO_GROSS_TOPK_DISSOCIATION_OBSERVED
```

这不是 quantization equivalence claim，也不是所有 prompt/所有位置 logits equality。

## Question

对 Matrix V2 的三个 mismatch cases：

```text
P6 cjk
P11 docstring
P12 risk
```

在首个 token divergence前 teacher-force共同 generated prefix，然后分别观察
MLX和 llama-server的 next-token top-k/logprob，判断分歧是 gross numeric
dissociation还是 near-boundary selection flip。

## Protocol

```text
Phase 1 MLX only
  decode Matrix V2 compare artifact
  对每个 mismatch计算 common generated prefix
  teacher-force prompt IDs + common prefix
  计算全词表 log-softmax下的 top-16 tokens/logprobs
  写 immutable record并退出

Phase 2 LLAMA only
  读取 Phase 1 record
  对同一 teacher-forced prefix提交 /completion
  n_probs = 16
  比较 top token、candidate rank和 logprob
```

源 Matrix V2 compare SHA-256：

```text
6e86c2c560a3994afa0b47bbd0513ed4d0ee7a4a4c34093b9751f6f47313409a
```

## Resource

```text
Phase1 MLX steady swap delta   = 0 bytes
Phase2 LLAMA steady swap delta = 0 bytes
gate                           = 768 MiB
```

两个 backend仍严格顺序运行，不同时驻留。

## Attribution

| Case | Common prefix | MLX top1 | LLAMA top1 | MLX alt logprob in LLAMA | LLAMA alt logprob in MLX |
| --- | ---: | --- | --- | ---: | ---: |
| P6 cjk | 8 generated tokens | `99978` / 访问 | `101729` / 请求 | rank 1, `-1.702165` | rank 1, `-1.960619` |
| P11 docstring | 0 generated tokens | `71093` / ``` | `12237` / `"""` | rank 2, `-2.315562` | rank 1, `-1.130531` |
| P12 risk | 8 generated tokens | `506` / ` at` | `678` / ` your` | rank 1, `-1.790678` | rank 1, `-1.081104` |

LLAMA top1 logprobs：

```text
P6  请求  = -0.849757
P11  """  = -0.481986
P12  your = -0.324732
```

MLX top1 logprobs：

```text
P6  访问 = -0.335619
P11 ```  = -0.880531
P12  at  = -0.456104
```

## Finding

1. `top1 agreement = 0/3`，说明三个 mismatch都不是随机 suffix差异，而是在
   next-token decision boundary就选择了不同 token。
2. 但 MLX top1都出现在 LLAMA top2内，LLAMA top1也都出现在 MLX top2内；因此
   没有 gross top-k dissociation。
3. 分歧更像 quantization/runtime numeric drift导致 close-logprob candidates
   的 rank flip。
4. P11还叠加 formatting policy差异：MLX偏好 code fence，LLAMA偏好直接 docstring；
   这解释了后续 output长度差异。
5. 不能将 3-case结果推广为所有 divergence都是 near-boundary flip。

## Validation

```text
Swift tests = 157 PASS / 0 FAIL
```

## Artifacts

```text
simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-logit-record.json
simigo2-experimental/results/backend-conformance/cross-backend-cyber-tiel-logit-compare.json
```

Record SHA-256：

```text
e60a67da603d23d366c4f765e454bade27997ac288a36b86eb61ff274d3f01fd
```

实现：

```text
CrossBackendLogitProbe.runRecord
CrossBackendLogitProbe.runCompare
CLI: cross-backend-logit-record / cross-backend-logit-compare
```

## Boundary

结果限定 named-source Cyber-Tiel MLX oQ4e与 MTP UD-Q4_K_XL GGUF variants、
Matrix V2中的 P6/P11/P12、teacher-forced first-divergence prefixes、top-16
logprob observation和 canonical LLAMA profile。不同 quantization、MTP机制、
tokenizer-file lineage和 sampling/runtime implementations保持为 confound。

## Non-claims

```text
❌ quantization equivalence
❌ full logits equality
❌ all mismatches都是 near-boundary flip
❌ MTP机制已定位
❌ tokenizer lineage已证明
❌ same-checkpoint closure
```

## Next

1. 对更多 mismatch prompts重复 teacher-forced top-k attribution。
2. 报告 margin distribution而非只记录首个 divergence。
3. 用 logits/top-k drift量建立 named-source acceptance boundary。
