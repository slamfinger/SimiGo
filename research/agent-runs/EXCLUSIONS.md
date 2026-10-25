# Agent-Runs 导入排除清单

来源：`/Users/mr.simi/SimiGo-Agent-Runs`（快照于 2026-10-26）。
纳入规则：证据报告、证据 JSON、驱动脚本、源码补丁、清单与校验文件；单文件上限 2 MiB。
本清单由导入脚本生成；被排除项仍保留在源目录原位，未删除、未修改。

## 各批次纳入量

| 批次 | 文件数 | 体积 |
| --- | ---: | ---: |
| `es-is-declarative-result-contract-20261023j` | 462 | 12.2 MiB |
| `es-is-detached-continuation-20261022f` | 228 | 5.2 MiB |
| `es-is-multihop-continuation-20261022g` | 47 | 2.2 MiB |
| `es-is-native-result-contract-20261023k` | 54 | 1.9 MiB |
| `es-is-native-result-contract-20261023k2` | 34 | 310.9 KiB |
| `es-is-selective-invalidation-20261022h` | 221 | 5.4 MiB |
| `es-is-semantic-sufficiency-20261022i` | 415 | 12.0 MiB |
| `handoff-causality-20261022b` | 175 | 2.3 MiB |
| `handoff-causality-20261022c` | 73 | 2.0 MiB |
| `handoff-causality-20261022d` | 64 | 3.4 MiB |
| `probe-keychain-scope` | 4 | 23.8 KiB |
| `revised-task-20261023` | 2 | 43.3 KiB |
| `settlement-provenance-20261022e` | 286 | 4.0 MiB |
| `simigo-product-integration-20261023` | 42 | 2.4 MiB |
| `simigo-rc1-20261023` | 118 | 1.2 MiB |
| `simigo-rc1-gate-closure-20261023` | 46 | 1.8 MiB |
| `simigo-rc1-repo-closure-20261023` | 21 | 562.3 KiB |
| `simigo-rc1-tools-vendoring-20261023` | 1 | 6.3 KiB |
| `simigo-runtime-contract-tests-20261024` | 13 | 125.9 KiB |
| `simigo-v2.2.0rc1-admission-increment-20261026` | 111 | 3.8 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | 346 | 8.3 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | 374 | 3.8 MiB |
| `simigo-v2.2.0rc1-os-page-return-20261024` | 39 | 513.5 KiB |
| `simigo-v2.2.0rc1-service-http-20261024` | 142 | 2.3 MiB |

## 整目录排除（构建产物、App、运行时环境）

| 批次 | 目录 | 文件数 | 体积 |
| --- | --- | ---: | ---: |
| `simigo-product-integration-20261023` | `g1g3-run/` | 942 | 2.3 GiB |
| `simigo-product-integration-20261023` | `l3-driver/` | 10693 | 444.5 MiB |
| `simigo-product-integration-20261023` | `phase6-package/` | 20 | 262.5 MiB |
| `simigo-rc1-20261023` | `derived/` | 28764 | 2.2 GiB |
| `simigo-rc1-gate-closure-20261023` | `memprobe/` | 172 | 31.4 MiB |
| `simigo-rc1-tools-vendoring-20261023` | `products/` | 394 | 750.3 MiB |
| `simigo-runtime-contract-tests-20261024` | `run2/` | 22279 | 1.4 GiB |
| `simigo-runtime-contract-tests-20261024` | `scratch/` | 21833 | 1.4 GiB |
| `simigo-runtime-contract-tests-20261024` | `src/` | 436 | 6.5 MiB |
| `simigo-v2.2.0rc1-admission-increment-20261026` | `envtest-final/` | 13 | 221.7 KiB |
| `simigo-v2.2.0rc1-admission-increment-20261026` | `envtest-root/` | 3 | 36.0 KiB |
| `simigo-v2.2.0rc1-admission-increment-20261026` | `envtest-root2/` | 3922 | 171.9 MiB |
| `simigo-v2.2.0rc1-admission-increment-20261026` | `install/` | 20 | 104.2 MiB |
| `simigo-v2.2.0rc1-admission-increment-20261026` | `install_v2/` | 20 | 104.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `install/` | 20 | 103.4 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `install_v5/` | 20 | 103.4 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `install/` | 40 | 265.9 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `round3_archive/` | 170 | 167.8 MiB |
| `simigo-v2.2.0rc1-service-http-20261024` | `install/` | 20 | 103.2 MiB |

## 特殊排除：密钥/凭据材料

按内容模式命中私钥/云凭据模式的文件：**0** 个（未纳入）。

另按路径排除 `probe-keychain-scope/` 的 `key.pem`、`id.p12`、`cert.pem`、`probe.keychain-db` 等密钥材料；所有 `*.keychain-db`、`*.p12`、`*.pem`、`*.sqlite3*` 一律不入仓。

## 单文件超限（> 2 MiB，保留原路径索引）

| 批次 | 文件 | 体积 |
| --- | --- | ---: |
| `simigo-rc1-gate-closure-20261023` | `noninterference_post-iso-run4.json` | 25.8 MiB |
| `simigo-rc1-gate-closure-20261023` | `noninterference_post-iso-tests3.json` | 25.7 MiB |
| `simigo-rc1-gate-closure-20261023` | `noninterference_pre-iso-run4.json` | 25.7 MiB |
| `simigo-rc1-gate-closure-20261023` | `noninterference_pre-iso-tests3.json` | 25.6 MiB |
| `simigo-rc1-gate-closure-20261023` | `noninterference_pre-iso-tests2.json` | 25.0 MiB |
| `simigo-rc1-gate-closure-20261023` | `noninterference_post-iso-tests.json` | 25.0 MiB |
| `simigo-rc1-gate-closure-20261023` | `noninterference_post-mp2.json` | 18.2 MiB |
| `simigo-rc1-gate-closure-20261023` | `noninterference_pre-mp2.json` | 18.2 MiB |
| `simigo-rc1-gate-closure-20261023` | `noninterference_post-memprobe.json` | 18.2 MiB |
| `simigo-rc1-gate-closure-20261023` | `noninterference_pre-memprobe.json` | 18.2 MiB |
| `simigo-rc1-gate-closure-20261023` | `noninterference_diff_iso-test-window.json` | 17.8 MiB |
| `simigo-rc1-20261023` | `noninterference_post-cleanroom-experiment.json` | 16.0 MiB |
| `simigo-rc1-20261023` | `noninterference_pre-cleanroom-experiment.json` | 16.0 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `MANIFEST_SHA256.txt` | 14.1 MiB |
| `simigo-rc1-20261023` | `noninterference_post-experiment.json` | 9.4 MiB |
| `simigo-rc1-20261023` | `noninterference_pre-experiment.json` | 9.4 MiB |
| `simigo-rc1-20261023` | `noninterference_post-test.json` | 9.4 MiB |
| `simigo-rc1-20261023` | `noninterference_pre-test.json` | 9.3 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `evidence/round2/MANIFEST_SHA256.txt` | 8.7 MiB |
| `simigo-product-integration-20261023` | `phase0/01_xcodebuild_SimiGo_app.log` | 6.9 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_walked_shot_b.png` | 4.9 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_walked_shot.png` | 4.9 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_walk4_shot.png` | 4.8 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_walk4_shot_b.png` | 4.8 MiB |
| `simigo-v2.2.0rc1-admission-increment-20261026` | `build_test.log` | 4.8 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `logs/buildtest_v5.log` | 4.7 MiB |
| `simigo-rc1-repo-closure-20261023` | `build_clean2.log` | 4.6 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `logs/build_for_testing.log` | 4.6 MiB |
| `simigo-rc1-repo-closure-20261023` | `build_clean.log` | 4.6 MiB |
| `simigo-v2.2.0rc1-admission-increment-20261026` | `build_debug.log` | 4.4 MiB |
| `simigo-rc1-20261023` | `build_for_testing.log` | 4.2 MiB |
| `simigo-v2.2.0rc1-service-http-20261024` | `logs/build_for_testing_r5.log` | 4.1 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `logs/build_v5.log` | 4.0 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `logs/build.log` | 4.0 MiB |
| `simigo-v2.2.0rc1-service-http-20261024` | `logs/build_release.log` | 3.9 MiB |
| `simigo-product-integration-20261023` | `apptarget_fullrun_20261023.log` | 3.9 MiB |
| `simigo-product-integration-20261023` | `apptarget_adopt_tests_20261023.log` | 3.7 MiB |
| `simigo-product-integration-20261023` | `apptarget_fullrun_turn28_20261023.log` | 3.6 MiB |
| `simigo-product-integration-20261023` | `app_tests_turn29_final.log` | 3.6 MiB |
| `simigo-product-integration-20261023` | `g1g3-plan-turn23/app-test-headless-eval.log` | 3.6 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/os_page_return_raw_os5b.json` | 3.3 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/os_page_return_raw_os5.json` | 3.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/os_page_return_raw_os5c.json` | 3.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/os_page_return_raw.json` | 3.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/os_page_return_raw_os4.json` | 3.2 MiB |
| `simigo-v2.2.0rc1-os-page-return-20261024` | `evidence/os_page_return_raw.json` | 3.2 MiB |
| `simigo-v2.2.0rc1-os-page-return-20261024` | `evidence/os_page_return_raw_os3.json` | 3.2 MiB |
| `simigo-v2.2.0rc1-os-page-return-20261024` | `evidence/os_page_return_raw_os2.json` | 3.1 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/os_page_return_raw_os6a.json` | 2.8 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/os_page_return_raw_os6c.json` | 2.8 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/os_page_return_raw_os6b.json` | 2.8 MiB |
| `simigo-rc1-repo-closure-20261023` | `verify_20261023/snapshot_post_replay.json` | 2.4 MiB |
| `simigo-v2.2.0rc1-admission-increment-20261026` | `run_json/run_isolated_eb1/snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-admission-increment-20261026` | `run_json/run_isolated_eb1/snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-admission-increment-20261026` | `run_json/run_isolated_ai1/snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-admission-increment-20261026` | `run_json/run_isolated_ai1/snapshot_pre.json` | 2.2 MiB |
| `simigo-runtime-contract-tests-20261024` | `post_snapshot.json` | 2.2 MiB |
| `simigo-runtime-contract-tests-20261024` | `pre_snapshot.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_walked_snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_walk1_snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_walk2_snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_walk3_snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_walk4_snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_walked_snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `evidence/round2/noninterference_post_m4.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_gui1_snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_gui3_snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_gui4_snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_gui5_snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_walk1_snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_walk2_snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_walk3_snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_walk4_snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gate_g2_snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_gui1_snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_gui3_snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_gui4_snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gui_gui5_snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `evidence/noninterference_bracket_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `evidence/round2/noninterference_bracket_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-service-http-20261024` | `evidence/gate_installed_r2/snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `evidence/gate_g2_snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `evidence/noninterference_bracket_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `evidence/round2/noninterference_bracket_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-service-http-20261024` | `evidence/gate_installed_r2/snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `evidence/round2/noninterference_pre_m4.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `run_json/run_isolated_lf1/snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `run_json/run_isolated_lf2/snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `run_json/run_isolated_lf3/snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `run_json/round1_snapshot/snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `run_json/run_isolated_m1d_round2/snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `run_json/run_isolated_lf1/snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `run_json/run_isolated_lf2/snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | `run_json/run_isolated_lf3/snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `evidence/noninterference_post_m4.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `run_json/round1_snapshot/noninterference_post_m4.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `run_json/round1_snapshot/snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `run_json/run_isolated_m1d_round2/snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `run_json/run_isolated_r3/snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `run_json/run_isolated_r3_partial_signer_leak/snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `run_json/run_isolated_r4/snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-service-http-20261024` | `run_json/run_isolated_r5/snapshot_post.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `evidence/noninterference_pre_m4.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `run_json/round1_snapshot/noninterference_pre_m4.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `run_json/run_isolated_r3/snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `run_json/run_isolated_r3_partial_signer_leak/snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | `run_json/run_isolated_r4/snapshot_pre.json` | 2.2 MiB |
| `simigo-v2.2.0rc1-service-http-20261024` | `run_json/run_isolated_r5/snapshot_pre.json` | 2.2 MiB |

## 按扩展名排除（非证据格式）

| 扩展名 | 文件数 |
| --- | ---: |
| `.sqlite` | 287 |
| `.bin` | 144 |
| `.safetensors` | 70 |
| `<none>` | 65 |
| `.lock` | 16 |
| `.migrated-2026-10-23t12-05-38z` | 1 |

## 说明

- `noninterference_*.json`（9–26 MiB）是隔离性门证据的大快照；其判定结论、diff 摘要与 REPORT 已纳入。
- `derived/`、`run2/`、`scratch/`、`checkouts/`、`SourcePackages/` 为可再生成的构建/依赖产物。
- `envtest-root*/`、`envtest-final/` 含测试运行期 SQLite 与本地环境，属运行态数据。
- 完整还原需以源目录为准；本清单给出被排除项的原路径与体积。
