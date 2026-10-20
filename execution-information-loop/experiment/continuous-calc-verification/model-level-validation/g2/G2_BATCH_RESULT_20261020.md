# G2 批次结果（2026-10-20）

**终态：`PASS`** · run `20261020T082124Z` · 9 次模型启动 / 6 次负对照进程 / 总进程 15 / 0 次重试

本记录只描述一次执行。`PASS` 是本轮证据的裁定，不是通用模型能力、生产授权或 G1 的延伸。

## 1. 运行身份

| 项 | 值 |
| --- | --- |
| 授权 | `G2-BATCH-AUTH-20261020-01`，`docs/01-questions/G2_BATCH_AUTHORIZATION_20261020.md`，`sha256 d7b6dc234b142756a7fbd9159ae150fa02fa8e275397f1d26f53d2578c0126b2` |
| 预注册 | `docs/01-questions/G2_PREREGISTRATION_20261020.md`（`FROZEN`） |
| Manifest | `g2/manifest/G2_MANIFEST.json`，`sha256 fd5146968f01a8b2014a288519dbec022af2abb533c3b38613fce5b622798ec0` |
| Token | `G2_AUTHORIZATION.token`，内容绑定上述 manifest 摘要；启动前原子重命名为 `AUTHORIZATION.consumed` |
| Token 摘要 | `fb25a6048faf4bbf…`（`AUTHORIZATION_CONSUMPTION.json`） |
| 冻结载荷 revision | `064a2a85`（`source_revision_at_freeze`） |
| 运行 revision | `45554f4c`（只多出 manifest + token 提交） |
| Runner | `run_batch.py` v1，`sha256 6cd580cda4235e50…` |
| Gate / Checker | `carrier_gate.py a791de301283f21d…` / `checker.py bc453515789a432d…` |
| Host 产物 | `G2Host 9eee4bc394a2f25d…`（Swift 6.4 release） |
| 模型目录 | `g2/artifact-model-qwen3-coder-30b-a3b-instruct-4bit-6e302ea6`，17 个普通文件，0 符号链接 |
| 预算 | 计划 9 / 上限 9 次模型启动，0 重试；负对照 ≤ 6；进程总上限 15 |
| 窗口 | `2026-10-20T08:21:24Z` → `08:23:31Z`（127 s） |

Preflight 在启动前逐项通过：17/17 文件匹配 binding，聚合 `4c1bd7596b948086…`，预测
`weights_digest = d1f01c0cdb…`，fixtures 摘要与 manifest 一致，工作树干净。

## 2. 执行事实

| Fixture | Arm | pid / pgid | 耗时 | 提示 tokens | completion | exit |
| --- | --- | --- | --- | --- | --- | --- |
| fixture-1 | A continuous | 51227 / 51227 | 18.42 s | 448 | 37 | 0 |
| fixture-1 | B phase 1 | 51607 / 51607 | 12.98 s | 448 | 37 | -15（SIGTERM） |
| fixture-1 | B phase 2 | 51614 / 51614 | 12.61 s | 72 | 23 | 0 |
| fixture-2 | A continuous | 51623 / 51623 | 14.62 s | 524 | 36 | 0 |
| fixture-2 | B phase 1 | 51635 / 51635 | 13.86 s | 524 | 36 | -15（SIGTERM） |
| fixture-2 | B phase 2 | 51783 / 51783 | 13.00 s | 71 | 23 | 0 |
| fixture-3 | A continuous | 52089 / 52089 | 14.63 s | 437 | 35 | 0 |
| fixture-3 | B phase 1 | 52095 / 52095 | 13.60 s | 437 | 35 | -15（SIGTERM） |
| fixture-3 | B phase 2 | 52104 / 52104 | 12.87 s | 70 | 22 | 0 |

每个进程的 `identity_check.json` 均为 `all_match: true`：`weights d1f01c0c…`、
`tokenizer 9bada7c8…`、`combined bb0b2711…`，与 P0-A2 `20261020T075257Z` 一致。

Phase 1 生命周期（三例相同）：`SIGTERM` → pid `ESRCH`、进程组 `ESRCH`；phase-1 store 在上报
前为空（`inventory = []`，目录摘要 `e3b0c442…` 即空集），随后 `chmod 000`，phase 2 期间
`os.listdir` 抛 `PermissionError`，phase 2 结束后恢复 `755` 且摘要不变。

Phase 2 隔离（三例相同）：新 pid / 新 pgid / 新 store base；namespace
`chat-cross-session-v1-bb0b2711451cbabc…`；hook `calls = 1`、`hits = 0`、
`matched_token_counts = []`；`rescan_registered_artifacts = 0`，`inventory_before/after = []`。

## 3. 裁定

| 主张 | 行数/ fixture | fixture-1 | fixture-2 | fixture-3 | 批次 |
| --- | --- | --- | --- | --- | --- |
| **G2-A** 旧 KV 不可达 | 15 | PASS | PASS | PASS | **PASS** |
| **G2-B** IS 恢复 | 17 | PASS | PASS | PASS | **PASS** |
| **G2-C** 真实模型续算 | 7 | PASS | PASS | PASS | **PASS** |

G2-A：`phase1_host_terminated`、`phase1_esrch`、`phase1_group_empty`、`phase2_new_pid`、
`phase2_new_pgid`、`phase2_store_base_distinct`、`phase1_store_empty`、
`phase1_store_unreadable_during_phase2`、`phase2_hook_calls_positive`、
`phase2_hook_hits_zero`、`phase2_no_phase1_prefix_match`、`phase2_store_still_empty`、
`phase1_store_digest_unchanged`、`canary_absent_from_r1`、`canary_absent_from_phase2`。

G2-B：`phase1_settled`、`restore_decision_restored`、`restored_object_id_equal`、
`restored_source_version_equal`、`restored_dependency_closure_equal`、
`restored_validity_basis_equal`、`c_missing_refused`、`c_missing_code`、
`c_missing_copy_unchanged`、`c_missing_no_model_load`、`c_tampered_refused`、
`c_tampered_code`、`c_tampered_copy_unchanged`、`c_tampered_no_model_load`、
`settlement_object_id_unchanged`、`no_u1_compute_in_phase2`、`no_new_settlement_in_phase2`。

G2-C：`phase1_u1_parsed`、`phase2_u2_generated`、`u2_checker_pass`、
`u2_contains_transfer_secret`、`r1_matches_phase1`、`u1_not_reexecuted_in_phase2`、
`s1_absent_from_phase2`。

## 4. 逐 fixture 语义结果

| Fixture | 结算 R1 | A / B1 的 R1 摘要 | Phase-2 U2 输出 | Checker |
| --- | --- | --- | --- | --- |
| fixture-1 | secret `d44be450e46a`，site `Lisbon`，checksum `2c146785` | 相同，`3f034c72…` | `ANSWER=d44be450e46a-2c146785` | PASS |
| fixture-2 | secret `366bf64a4722`，site `Harbor`，checksum `c1d64b2d` | 相同，`350f51aa…` | `ANSWER=366bf64a4722-c1d64b2d` | PASS |
| fixture-3 | secret `e7727062f318`，site `Quarry`，checksum `0ae90cda` | 相同，`5c1f23f3…` | `ANSWER=e7727062f318-0ae90cda` | PASS |

Phase-2 提示词只有 70–72 tokens（R1 加下游指令），phase-1 提示词为 437–524 tokens。U2 中的
secret 只存在于 S1 与从 carrier 恢复的 R1 中，而 phase-2 输入不含 S1；`s1_marker` 与
`context_canary` 在 phase-2 证据中扫描为 0 命中，canary 也不在 R1 中。

## 5. 负对照

| Fixture | 变体 | 决定 | 冻结码 | 模型加载 | 副本摘要（拒绝前后） | gate 检查行 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 / 2 / 3 | C-missing | REFUSED | `SETTLEMENT_MISSING` | false | 不变 | 2（schema → index 缺失） |
| 1 / 2 / 3 | C-tampered | REFUSED | `OBJECT_DIGEST_MISMATCH` | false | 不变 | 6（content address 不匹配） |

两份副本各自来自 canonical carrier 的独立字节复制；canonical 文件不被负对照触碰。

## 6. 独立复核

父进程用 `python3 batch/run_batch.py --verify-only <run>` 重算全部 claim 行、phase-2
hook/identity/store、launch exit、负对照拒绝与预算：

```text
terminal_state_recorded = PASS
verdict_agrees           = true
problems                 = []
fixtures_recomputed      = 3 x (G2-A PASS, G2-B PASS, G2-C PASS)
```

输出保存在 `g2/G2_BATCH_REVERIFICATION_20261020.json`。

## 7. 必须明示的记录差异

1. **manifest 草案在冻结前被替换。** 第一版草案 `sha256 81a78e7e…` 的键结构与 runner 的
   preflight 读取不一致（草案用扁平 `build`/`runner` 键，runner 读 `executables`/`backend`
   对象）。preflight 在 token 被消费、任何子进程启动之前拒绝，因此没有任何模型启动计入它。
   最终 manifest `fd514696…` 在 `freeze_history` 里记录了这一替代；被替换的草案从未提交、
   从未被消费。
2. **`verification.json` 的 `canonical_carrier.unchanged_after_negative_controls_and_phase2`
   = false 是设计内的追加，不是完整性失败。** phase 2 按预注册向 canonical carrier 追加两条
   `execution_state` 索引（`…-u2-restored`、`…-u2-advanced`），这就是它的合法写入；同期
   settlement 的 `object_id` 不变，settlement 依赖历史长度 `1 → 1`，两项均作为 claim 行通过。
   两个负对照副本在拒绝前后 sqlite 摘要逐字节不变。该布尔字段按字面同时覆盖“负对照”和
   “phase 2”，因此为 false；它不参与裁定。该字段不能替代独立复核：settlement 身份、依赖历史
   与追加集合已由 §9 的只读审计器直接从载体字节重算。
3. **证据布局。** manifest 与 evidence 放在 `g2/manifest/`、`g2/evidence/`（预注册 §12 的
   路径），runner/host/gate/checker/fixtures 代码在 `g2/batch/`。`g2/evidence/20261020T082124Z/`
   共 98 个文件，原始 `host.log` 未被 `*.log` 忽略规则吞掉。
4. **Arm A 的 checker 结果只作为基线证据。** 预注册门是 phase-2 的 U2；A 的 checker 不参与
   停止或裁定。

## 8. 非声明（与预注册 §10 一致）

1. 不是物理擦除证明：未测 RAM 残留、swap 或 page cache；G2-A 只主张可达性。
2. 不是 token 级 KV 复用证明：预填 R1 是新工作，已被记录，不当作重做 U1。
3. 不是通用模型能力主张：三个合成 fixture + 冻结 checker。
4. 不是生产授权：无部署、无流量、无 signer 移动、无 R27 变化。
5. 不是 G1 证据：G1 保持 `CLOSED`，本批不重读也不扩展它。
6. 峰值内存未测；`EngineModelIdentity` 的符号链接读取缺陷（A3）未修复；tokenizer 摘要跨目录
   可复现性只是被报告（同一目录内一致），未被证明。

## 9. 独立评审与结算不变量复核（2026-10-20）

### 9.1 评审裁定及其范围

独立评审接受本轮结果：三个主张在三个合成 fixture、冻结的 A2 模型副本与冻结 MLX 执行路径内
裁定为 `PASS`，且分别对应不同证据类型，而非仅凭进程退出码。评审同时明确：这是
**摘要级评审**，未逐行检查本文件、复核 JSON 或 98 个原始证据文件，也不冒充完整原件审计。

### 9.2 评审指出的复核缺口

评审要求：不能因为 `canonical_carrier…=false` “不参与裁定”就把它忽略；正式复核必须确认
独立复核器确实检查 settlement 不变量，没有用宽泛例外掩盖额外写入。

核对结论：**该缺口当时真实存在。** `run_batch.py --verify-only` 只从 `verification.json`
已记录的 `checks` 重新推导 claim 行，从未重新打开载体；`settlement_object_id_unchanged` 与
`no_new_settlement_in_phase2` 是执行体自报的布尔值，属于被复核对象自证。

### 9.3 补强的只读审计

新增 `g2/batch/audit_settlement_invariants.py`，对每个 fixture 直接打开
`B1/carrier/g2.sqlite` 与两个负对照副本（`mode=ro&immutable=1`），
**不读取** `terminal.json` / `verification.json`，从字节重算 32 项，三个 fixture 全部通过：

| 不变量 | 重算内容 |
| --- | --- |
| settlement 身份 | 索引行唯一；`sha256(bytes)` 等于对象地址；`byte_size` 等于实际长度 |
| settlement 载荷 | `EINFO-SETTLEMENT-V1` / `SETTLED` / `item_id=u1-result`；R1 重算摘要自洽且与 phase-1 `r1.json` 一致 |
| 身份跨记录一致 | 载体字节中的 `object_id` == `carrier_phase1.json` == `restore_gate.json` |
| 依赖历史 | `settlement:u1-result` 恰好 1 条、revision 1、`content_address` 指向该对象；重算长度 1 == 记录的 `1 → 1` |
| 来源稳定 | `item:u1-result` 与 `item:s1-source` 当前对象地址分别等于 settlement basis 与 phase-1 记录；S1 摘要等于 fixture |
| 追加集合 | settlement 之后的索引行恰好 3 条且全部为 `execution_state:`（1 条 phase-1 + 2 条 phase-2）；没有新增 `settlement:` / `item:` / `demand:` |
| 状态链 | `u1-settled → u2-restored → u2-advanced`；两个 phase-2 状态的 `result_digest` 由恢复身份、U2 答案与 checker 结果重算 |
| 负对照副本 | 当前文件摘要 == gate 记录的 before == after；`C_missing` 无 settlement 索引/依赖；`C_tampered` 字节摘要 != 地址且 `byte_size` 自洽 |
| U2 结果 | `ANSWER` 单行；secret 等于 settlement 中的 R1；checksum 等于 `sha256(site)[:8]` 重算值 |
| 信息边界 | U2 提示包含恢复的 R1；phase-2 文件中没有 S1 正文或 canary |

命令与输出：

```text
python3 batch/audit_settlement_invariants.py evidence/20261020T082124Z --probe \
  -o G2_SETTLEMENT_INVARIANT_AUDIT_20261020.json
all_pass = true; discrimination_probe.all_detected = true
```

### 9.4 审计器的判别性

一个从不说“不”的复核器没有意义。审计器在临时副本上逐个注入违规并验证能否捕获，
三个 fixture × 三种注入共 9 项，全部被预期检查捕获：

| 注入 | 预期失败检查 |
| --- | --- |
| 为 settlement 追加 revision 2 | `settlement_dependency_single_revision`（同时 `settlement_history_length_one`） |
| 追加一条 `item:u2-answer` 索引 | `no_settlement_item_or_demand_appends`（同时 `post_settlement_appends_are_states_only`） |
| 篡改 settlement 对象字节 | `settlement_bytes_match_address` |

探针在 `G2_SETTLEMENT_INVARIANT_AUDIT_20261020.json` 的 `discrimination_probe` 中留有
逐项记录。临时副本会使 gate 记录中的绝对路径检查（`*_copy_is_not_canonical`）失败，
这是探针环境的预期副作用，已在记录中单列并排除。

### 9.5 边界

这是对**已存证据**的事后只读审计，不重跑实验、不重新生成模型输出，也不把摘要级评审
升级为对 98 个文件的逐行审计。它补上的是评审指出的那一个缺口：settlement 身份与依赖历史
现在有独立于执行体布尔值的字节级重算。
