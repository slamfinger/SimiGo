# SimiGo Lab RQ2 Qwen4Exp Read-Only Candidate Audit — 2026-09-29

## Decision

继续维持：

```text
RQ2 = PARTIAL / BLOCKED_BY_QWEN4EXP_MODEL_ARTIFACT
```

本轮只对 Qwen4Exp 相关候选做远程 metadata / manifest / README 只读审计。
没有下载任何模型，没有执行 runtime load，也没有修改 Lab 执行器。

## Fit boundary

本机约束是 32GB physical RAM。Lab oversized gate 当前使用 `30,720MiB`
作为实验上限。磁盘可用空间不是 fit 条件；候选体积、加载时的 runtime
overhead 和系统保留内存都不能用磁盘剩余空间替代。

## Candidates rejected

| Candidate | Verified / reported size | Architecture | Decision | Reject reason |
| --- | ---: | --- | --- | --- |
| `Jab1718/qwen3.8-flash-coder-26gb-gguf` | `42,620,341,120 bytes` ≈ `39.69 GiB` / `42.62 GB` | `qwen4exp` | REJECT | 超过 32GB host fit；名称中的 “26gb” 不是仓库总模型体积。 |
| `ISTA-DASLab/Qwen3.8-Flash-Next-GSQ-RCO-Coder-GGUF` | `116,514,464,640 bytes` ≈ `108.54 GiB` / `116.51 GB` | `qwen4exp` | REJECT | 远超 32GB host fit。 |
| `AnonimousA/Qwen3.8-Flash-Next-REAP-320-GGUF` | Q3 shards ≈ `64.21 GiB`; Q2 shards ≈ `57.27 GiB` | `qwen4exp` | REJECT | 所有 observed quantizations 远超 32GB host fit。 |
| `sh0wie/Qwen3.8-Flash-Next-REAP-288-GGUF` | README: Q4 `78GB`, Q5 `87GB`, Q8 `116GB`; HF total `124,068,144,000 bytes` ≈ `115.54 GiB` | `qwen4exp` | REJECT | 所有 documented quants 远超 32GB host fit。 |
| `sh0wie/Qwen3.8-Flash-Next-REAP-288-MLX-4bit` | External guide reports `73.5GB`; config reports `Qwen4ExpForConditionalGeneration`, `model_type: qwen4_exp` | `qwen4_exp` | REJECT | 远超 32GB host fit。 |

原候选 `sh0wie/Qwen3.8-Flash-Next-REAP` 返回 404；实际对象已收窄为
`sh0wie/Qwen3.8-Flash-Next-REAP-288-GGUF` 和
`sh0wie/Qwen3.8-Flash-Next-REAP-288-MLX-4bit`。

## Artifact boundary

所有 reject 的候选都属于 Qwen4Exp family 的 pruned / subnet /
expert-pruned substrate，不能标记为完整 Qwen4Exp closure。当前没有可用且
32GB-fit 的 full Qwen4Exp artifact。

本次审计只覆盖远程 manifest、metadata、README 和可见 config 字段。它不验证
tensor completeness、tokenizer completeness、runtime load、Execution State
semantics、内存峰值或推理质量。

## Non-claims

不能 claim：

```text
Qwen4Exp 已验证
pruned / subnet / expert-pruned Qwen4Exp 可替代 full Qwen4Exp closure
体积小于磁盘可用空间即为可加载
远程 metadata 审计等于 runtime compatibility
```

## Next gates requiring user decision

RQ2 当前等待用户选择：

1. 用户提供完整 Qwen4Exp checkpoint 或明确外部模型路径。
2. 授权继续搜索更低 bit-width / 更强剪枝候选；若命中，只能登记为
   `QWEN4EXP_FAMILY_PRUNED_SUBSTRATE`，不能 claim full Qwen4Exp closure。
3. 将 pruned Qwen4Exp-family 作为独立研究线。
4. 暂停 RQ2，优先推进 RQ3 Execution State-side work。
