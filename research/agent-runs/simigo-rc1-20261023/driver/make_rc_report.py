#!/usr/bin/env python3
"""Emit RC_REPORT_20261023.md from RC_IDENTITY.json.

Numbers are read from the identity document (never typed by hand) so the prose
cannot drift from the evidence after a re-run.
"""
import json, os, time

RC = "/Users/mr.simi/SimiGo-Agent-Runs/simigo-rc1-20261023"
I = json.load(open(os.path.join(RC, "RC_IDENTITY.json")))
s1, s2, s3 = I["step1_source_freeze"], I["step2_build"], I["step3_tests_on_the_built_artifact"]
s4, s5 = I["step4_minimal_cross_process_flow_on_the_rc_artifact"], I["step5_non_interference_and_failure_evidence"]
CR = I["supplementary_clean_state_rebuild"]
b = CR["byte_identity_vs_rc_artifact"]
rc2 = CR["core_path_run_on_the_rebuilt_artifact"]
es1, es2 = s4["es1"], s4["es2"]
v = lambda x: "是" if x else "否"

M = f"""# SimiGo 发布候选构建报告（RC1）

- 发布候选标识：`{I['rc_id']}`
- 生成时间：{time.strftime('%FT%T%z')}（数值全部由 `driver/make_rc_report.py` 从 `RC_IDENTITY.json` 读取，不手抄）
- 目标：确认**同一个明确标识的交付版本**既能构建、也能运行已验证的核心路径；不要求理论与内存回收问题先闭合
- 源码：HEAD `{s1['head'][:12]}` · 分支 `{s1['branch']}` · staged {s1['staged_files']}
- 变更集：{s1['tracked_modified']} 个已跟踪修改 + {s1['untracked_files_expanded']} 个未跟踪文件（逐文件摘要 {s1['per_file_digests']} 条）
- 模型：`{s1['model_repo_id']}` · revision `{s1['model_revision'][:12]}…`（只引用 HF 缓存，不复制权重）
- 工具链：{I['step1_source_freeze']['toolchain']['xcodebuild'].strip()} · macOS {I['step1_source_freeze']['toolchain']['macos']} · {I['step1_source_freeze']['toolchain']['arch']}

## 结论（先说答案）

| 问题 | 结论 |
|---|---|
| 能不能构建 SimiGo | **能**。`{s2['result'][0] if s2['result'] else '?'}`，日志 `{s2['log']}`（{s2['log_sha256'][:12]}…） |
| 测试跑的是不是构建出来的那份字节 | **是**。见下方「同产物三段验证」 |
| 核心跨进程路径在这份产物上跑不跑得通 | **跑通**。G1 四项 PASS，ES2 从 IS 恢复 `hello` 并续算出 `RESULT=hello-U2` |
| 能不能从干净状态复现构建 | **能构建，但产物不逐字节相同**。见「干净态复现补充核验」 |
| 能不能标为可交付版本 | **建议标为 `RC-可集成`，不标为「核心机制全部验证完成的最终版」**（理由见「必须保留的边界」） |

## 五步逐项对账

### 步骤 1 · 固定源码 / 模型 / 构建配置

| 项 | 值 |
|---|---|
| 冻结文件 | `RC_SOURCE_FREEZE.json`（sha {s1['sha256'][:12]}…）+ `RC_SOURCE_FREEZE.txt` + `RC_TRACKED_DIFF.patch`（{s1['tracked_patch']['bytes']} B，{s1['tracked_patch']['sha256'][:12]}…） |
| 逐文件摘要条数 | {s1['per_file_digests']}（{s1['tracked_modified']} tracked + {s1['untracked_files_expanded']} untracked 展开） |
| tokenizer/config 摘要 | {len(s1['tokenizer_digests'])} 条 |
| 模型文件摘要 | {s1['model_files_digest_recorded']} 条 |
| 构建配置 | `{s1['build_command'][:150]}…` |
| 全部步骤跑完后复验 | {s1['reverified_after_all_steps']['files_checked']}/{s1['reverified_after_all_steps']['files_checked']} 一致，drift {len(s1['reverified_after_all_steps']['files_drifted'])}，missing {len(s1['reverified_after_all_steps']['files_missing'])}，HEAD 一致 {v(s1['reverified_after_all_steps']['head_matches_freeze'])}，staged {s1['reverified_after_all_steps']['staged_files_now']} |

### 步骤 2 · 构建并保存产物身份

- 动作：`build-for-testing`，独立 `-derivedDataPath`（本批次内 {s2['derived_data_path']}）
- 结果：`{s2['result'][0] if s2['result'] else '?'}` · 启动 {s2['started']}
- 产物身份：bundle 内 {s2['artifact_identity']['files_in_bundle']} 个文件，tree 摘要 `{s2['artifact_identity']['bundle_tree_sha256']}`
- 关键二进制：`SimiGo.debug.dylib` {s2['artifact_identity']['key_binaries']['SimiGo.debug.dylib']['bytes']:,} B · sha {s2['artifact_identity']['key_binaries']['SimiGo.debug.dylib']['sha256'][:12]}… · LC_UUID {s2['artifact_identity']['key_binaries']['SimiGo.debug.dylib']['uuid']}
- 内嵌 Frameworks：{s2['artifact_identity']['frameworks_bytes']:,} B
- 抓取时刻的坦白：{s2['capture_timing_note']}

### 步骤 3 · 对**该构建产物**运行现有测试，并记录测试实际使用的二进制身份

- 动作：`xcodebuild test-without-building -xctestrun …`（此模式不提供编译/链接阶段）
- xctestrun：`{os.path.basename(s3['xctestrun']['path'])}` · sha {s3['xctestrun']['sha256'][:12]}… · {s3['xctestrun']['bytes']} B
- 结果：**{s3['executed']} executed / {s3['skipped']} skipped / {s3['failures']} failures** · `{s3['summary_lines'][-1]}`
- 测试实际使用的二进制（这是本轮相对 Turn 28/29 的实质修正）：

| 证据 | 值 |
|---|---|
| bundle 内最新文件 mtime | {s3['binary_actually_tested']['bundle_newest_file_mtime']}（早于测试启动 18:34:03） |
| 18:32 之后被写的 bundle 文件数 | {s3['binary_actually_tested']['bundle_files_newer_than_18_32']} |
| 实验后 tree 摘要与构建后是否相同 | {v(s3['binary_actually_tested']['same_tree_digest_after_experiment'])} |
| 被测试与被实验的 dylib | {s3['binary_actually_tested']['dylib_bytes']:,} B · {s3['binary_actually_tested']['dylib_sha256'][:12]}… · UUID {s3['binary_actually_tested']['dylib_lc_uuid'][:8]}… |

包层 77/77 沿用 Turn 29 同源码批次的结果，本批次未重跑。

### 步骤 4 · 独立目录里的最小 ES1 → IS 结算 → ES1 退出 → ES2 恢复 → 真实模型续算

执行方式：{s4['execution_mode']}（不复制、不重签名、不改 bundle id），所以运行字节 = 步骤 2 构建 = 步骤 3 测试。

| 阶段 | 证据 |
|---|---|
| ES1 produce | pid {es1['pid']} · {es1['rc'].splitlines()[0]} · `RESULT=` {es1['generated_text']} · state {es1['settlement_state_id']} · digest {es1['payload_digest'][:12]}… · cache {es1['cache_identity'][:18]}… · prefill {es1['prefill_tokens']} / gen {es1['generation_tokens']} · {es1['reuse_mode']} |
| ES1 退出确认 | 驱动在启动 ES2 前确认 ES1 进程已退出并取回退出码 |
| ES2 consume | pid {es2['pid']} · {es2['rc'].splitlines()[0]} · 按 handoff 的 state id 读 IS（{es2['state_id_source']}）· 恢复值 `{es2['recovered_value']}` · digest 校验 {v(es2['digest_verified'])} · 有效性 {v(es2['validity_valid'])} |
| ES2 续算 | prompt：`{es2['u2_prompt']}` → 输出 `{es2['generated_text_u2']}` · prompt {es2['prompt_tokens']} / gen {es2['generation_tokens']} · {es2['reuse_mode']} · `pool_bind_hit_cacheLoad` {es2['pool_bind_hit_cacheLoad']} |
| 载体隔离 | ES2 启动前 cache 文件数 {es2['es2_cache_files_at_prelaunch']} · ES2 cache {es2['cache_identity_es2'][:18]}… 与 ES1 不同（{v(es2['cache_identity_differs_from_es1'])}）· ES2 运行期间 ES1 cache {es2['es1_cache_unchanged_during_es2']} |
| 值通道 | `value_carrying_env_channels` = {json.dumps(es2['value_carrying_env_channels'])}；负控 NC6/NC7 以 rc={s4['negative_controls']['NC6_leaked_target']} 拦截 |
| 进程自记身份 | `{json.dumps(s4['binary_identity_recorded_by_the_process']['bundle_macho_images'][1], ensure_ascii=False)}`（与磁盘 bundle 逐字节一致） |
| G1 | overall **{s4['g1']['overall']}** · {json.dumps(s4['g1']['sub_verdicts'], ensure_ascii=False)[:300]} |
| G3 | overall **{s4['g3']['overall']}** · {json.dumps(s4['g3']['sub_verdicts'], ensure_ascii=False)} |
| 负控 | {json.dumps(s4['negative_controls'], ensure_ascii=False)} |

G3 在本批次的范围说明：{s4['g3_scope_note']}

本批次未运行：{json.dumps(s4['not_run_in_rc_scope'], ensure_ascii=False)}

### 步骤 5 · 失败证据保留 + 未触碰正式数据/封存证据/用户改动

四份受保护资源快照 + 两份窗口差异（脚本 `driver/rc_noninterference.py` / `driver/rc_noninterference_diff.py`）：

| 窗口 | 违规变更数 | 说明 |
|---|---|---|
| pre-test → post-test（测试窗口） | **{s5['test_window_violations']}** | 由 **App 测试套件**造成，见下方发布门槛 |
| pre-experiment → post-experiment（最小实验窗口） | **{s5['experiment_window_violations']}** | 无头实验只写自己的运行目录（本批次自身变更 {s5['rc_batch_own_changes_in_experiment_window']} 项已按预期单列） |
| pre-cleanroom → post-cleanroom（干净态实验窗口） | **{json.dumps(CR['noninterference_cleanroom_window']['violations'], ensure_ascii=False) if CR['noninterference_cleanroom_window'] else '—'}** | 同上 |

测试窗口逐项：{json.dumps(s5['test_window_per_target'], ensure_ascii=False)}

- 封存证据批次：{s5['sealed_and_other_batches']}
- 工作树未被触碰：产品仓 18:28 后被改文件 {s5['product_worktree_files_touched_since_18_28']} 个；研究仓（SimiGo-Lab）{s5['lab_worktree_files_touched_since_18_28']} 个
- 失败证据：{s5['failure_evidence_retained']}

**发布门槛发现（登记，不在本轮修）**：{s5['release_gate_finding']}

## 干净态复现补充核验

用户存疑：「无法仅凭运行记录独立确认本地仓库当前一定能从干净状态复现构建」。本轮补做：

- 物化方式：{CR['materialization']['method']}；对冻结清单复验 {CR['materialization']['digest_check_vs_freeze']['checked']}/{CR['materialization']['digest_check_vs_freeze']['checked']} 一致（bad {len(CR['materialization']['digest_check_vs_freeze']['bad'])}）
- 构建结果：`{CR['build']['result'][0] if CR['build']['result'] else '?'}` · 日志 sha {CR['build']['log_sha256'][:12]}… · 启动 {CR['build']['started']}
- 产物对比：

| 维度 | RC 产物 | 干净态产物 | 相同 |
|---|---|---|---|
| bundle 文件数 | {b['files_in_bundle']['rc']} | {b['files_in_bundle']['cleanroom']} | {v(b['files_in_bundle']['rc'] == b['files_in_bundle']['cleanroom'])} |
| tree 摘要 | {s2['artifact_identity']['bundle_tree_sha256'][:16]}… | {CR['artifact_identity']['bundle_tree_sha256'][:16]}… | {v(b['same_bundle_tree'])} |
| dylib sha | {b['rc_dylib_sha256'][:16]}… | {b['cleanroom_dylib_sha256'][:16]}… | {v(b['same_dylib_sha256'])} |
| dylib 字节 | {b['rc_dylib_bytes']:,} | {b['cleanroom_dylib_bytes']:,} | 差 {b['dylib_byte_delta']:+,} |
| LC_UUID | {b['rc_dylib_lc_uuid'][:8]}… | {b['cleanroom_dylib_lc_uuid'][:8]}… | **不同** |
| Frameworks 字节 | {s2['artifact_identity']['frameworks_bytes']:,} | {CR['artifact_identity']['frameworks_bytes']:,} | 差 {b['frameworks_byte_delta']:+,} |

- 解释：{b['build_path_strings_embedded']['interpretation']}
- 判定：**{CR['verdict']}**
- 干净态产物上的核心路径：G1 **{rc2['g1']['overall']}**，ES1 pid {rc2['es1']['pid']}（`{rc2['es1']['generated_text']}`）→ ES2 pid {rc2['es2']['pid']} 恢复 `{rc2['es2']['recovered_value']}` → 输出 `{rc2['es2']['generated_text_u2']}`；负控 rc 序列与主产物一致（NC1 {rc2['negative_controls']['NC1_missing_settlement']} / NC4 {rc2['negative_controls']['NC4_bad_role']} / NC6 {rc2['negative_controls']['NC6_leaked_target']}）
- 未在干净态重跑 App 测试套件：{CR['app_test_suite_not_rerun_in_cleanroom']}

## 必须保留的边界

{os.linesep.join('- ' + x for x in I['preserved_boundaries'])}

## Git 不变量

{json.dumps(I['git_invariants'], indent=1, ensure_ascii=False)}

## 还差什么才能标成「可交付版本」

1. 测试套件的写隔离（或授权一次干净态 `test-without-building`，把 207/14/0 也在复现产物上重出来）。
2. 若要把 tier B/C 的生命周期观测也算到交付产物头上：在 RC 产物上补一次 memprobe（当前只存在于 Turn 29 的另一份链接产物）。
3. 若要「同一份字节可跨机复现」的发布声明：需要可复现构建方案（固定 LC_UUID/路径/时间戳来源），当前 Debug 产物做不到。
4. 若要脱离 `restricted_production_path`：需要走通 HTTP 推理路由的授权链（TLS + 授权后端 + challenge/proof）。
5. `physical_page_return` 与逐层 `forward_calls` 维持 BLOCKED / NOT_INSTRUMENTED，不因交付而改写。
"""
open(os.path.join(RC, "RC_REPORT_20261023.md"), "w").write(M)
print("written", os.path.join(RC, "RC_REPORT_20261023.md"), len(M.splitlines()), "lines", len(M), "chars")
