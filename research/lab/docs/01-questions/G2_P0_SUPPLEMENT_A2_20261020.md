# G2 P0 补充记录：A2 执行条件（2026-10-20）

**状态：`FROZEN — EXECUTION NOT AUTHORIZED`**

本记录只定义"下一次 P0 在什么条件下跑"，不授权它。副本可加载之前，仍须一份**新的、显式的一次性 P0 授权**；2026-10-20 那份已消费，不重新打开。

## 1. 本记录的地位

- 版本化的 P0 补充记录，附属于已冻结的 `G2_PREREGISTRATION_20261020.md`，不修改其正文。
- 不修改 `SIMIGO-G2-MODEL-BINDING-V1` 的任何一行：17 个路径、字节数、逐文件摘要与聚合摘要全部照旧。
- 不把 A2 说成修复。副本是实验层面的规避，`EngineModelIdentity.compute` 仍不支持 Hugging Face 的符号链接布局（A3 是独立工程门）。
- 机器可读形式：`docs/01-questions/G2_P0_A2_EXECUTION_CONDITION_20261020.json`（`condition_id = G2-P0-A2-20261020`），本文件是它的说明。

## 2. 前序 P0 的处置

| 项 | 处置 |
| --- | --- |
| run `20261020T072607Z` | 保留，不覆盖、不改判、不追认 |
| 终态 | `FAIL`（`weights_digest_matches_binding`） |
| 授权消费记录 | `AUTHORIZATION.consumed` 保留原样 |
| 缺失的 `launch.json` | 不补造；`RUN_VERIFICATION.json` 已记 `launch_record_present: false` |
| 退出码 | 未捕获，不追填 |
| 结论边界 | 加载可行性的正面证据，不构成身份通过 |

原失败揭示的身份缺口是真实的：源目录上引擎算出 `e3b0c442…`（空串摘要），namespace 退化为模型无关常量 `188a16c5…`。第二次启动不能改变这个发现，也不需要用来承认它。

## 3. 变更的执行条件

| 项 | 值 |
| --- | --- |
| `model_dir` | `…/g2/artifact-model-qwen3-coder-30b-a3b-instruct-4bit-6e302ea6` |
| 目录形态 | 17 个条目，全部普通文件，0 个符号链接 |
| 内容聚合 | `4c1bd7596b9480864ca7c5ac949fbb051c47b182b853a8219c80a171b22f6678`（与 binding 相同） |
| `modelID` 分量 | `artifact-model-qwen3-coder-30b-a3b-instruct-4bit-6e302ea6`（源目录该分量为 revision `6e302ea6…`） |
| 预算 | 1 次模型启动 / 0 次重试 / 2 次进程内生成 |
| 物化依据 | `g2/a2-materialization-20261020/MATERIALIZATION_RECORD_20261020.md`（`sha256 e62afb74…`）及其 `materialization_check.json`（`sha256 bfbd15a4…`） |
| runner | `g2/p0/run_p0.py` **v2**，`--model-dir` 必须与 `--condition` 同时给出 |

换目录本身就是新的执行条件：身份计算的输入形态变了，`modelID` 变了，元数据栅栏的取值也变了。内容相同不等于条件相同。

## 4. 未变更项

- 17 个相对路径、逐文件字节数与 SHA-256；
- `path / bytes / sha256` 聚合规则与聚合值；
- 三个后端 pin（mlx-swift / mlx-swift-lm / swift-transformers）；
- 提示词、`max_tokens = 16`、`prefill stride = 256`、greedy；
- 探针的七项检查与 `PASS` / `FAIL` / `INCONCLUSIVE` 判定规则；
- 一次性授权、证据写一次、终态只由子进程写、父进程只做独立复核。

## 5. 启动前必须同时成立

1. 一份**新的显式 P0 授权**入库，且写明预算 1/0/2 与禁止项。
2. runner 为 v2，`build.json` 记录 `runner.version`、runner 自身 `sha256`、`argv` 与实际使用的 condition `sha256`。
3. `--condition` 与 `--model-dir` 的声明一致，condition 的聚合与文件数与 binding 相符，condition 状态为 `FROZEN`。
4. 目标目录无任何符号链接条目（runner 会拒绝）。
5. 制品逐行核验与聚合复算通过，`predicted_engine_weights_digest` 仍为 `d1f01c0c…`。

任一条不成立即不启动；不满足条件的启动不算"消耗了一次"，而是根本不发生。

## 6. 终态规则

判定规则与主预注册一致，本记录不新增任何通过条件。补充两条明确预期：

- 若副本上引擎仍返回 `e3b0c442…`，那是**新的 FAIL**，如实记录后返回修订，不得重试、不得换目录再试。
- 若 weights 摘要匹配而 tokenizer 摘要与离线预测值 `9bada7c8…` 不同，不因此判失败：tokenizer 摘要依赖枚举顺序，不是可独立复算的门槛，按实际记录。

## 7. 禁止项

- 不加载副本，直到第 5 节全部成立；
- 不重跑、不改判、不补造前序 P0 的任何记录；
- 不签发 G2 批次 manifest，不运行 U1/U2，不建夹具，不开 arm；
- 不修改冻结预注册正文、binding 行、G1 `CLOSED`、Frozen Contracts、Carrier、signer；
- 不推送本地提交。

## 8. 本记录不授权什么

不授权任何模型启动；不授权 G2 批次；不证明副本能加载；不证明引擎为副本计算出的身份会匹配；不构成 G2-A / G2-B / G2-C 的任何结论；不关闭 A3。

## 9. 引用

- `docs/01-questions/G2_PREREGISTRATION_20261020.md`（FROZEN）
- `docs/01-questions/G2_MODEL_BINDING_20261020.json`（`SIMIGO-G2-MODEL-BINDING-V1`）
- `docs/01-questions/G2_P0_AUTHORIZATION_20261020.md`（已消费）
- `docs/01-questions/G2_P0_A2_EXECUTION_CONDITION_20261020.json`（FROZEN，本记录的机器可读形式）
- `…/g2/P0_RESULT_20261020.md`（FAIL 结论与根因）
- `…/g2/a2-materialization-20261020/MATERIALIZATION_RECORD_20261020.md`（离线物化验证）
- `docs/RESEARCH_STATE.md`（唯一状态权威）
