# Agent-Runs 导入排除清单

来源：`/Users/mr.simi/SimiGo-Agent-Runs`（快照于 2026-10-26），源目录已整体归档至 `research/_artifacts/SimiGo-Agent-Runs/`。
纳入规则：证据报告、证据 JSON、驱动脚本、源码补丁、清单与校验文件；单文件上限 50 MiB。
本清单由导入脚本生成；被排除项保留在本地归档 `research/_artifacts/SimiGo-Agent-Runs/`（gitignored），未删除、未修改。

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
| `simigo-product-integration-20261023` | 48 | 27.8 MiB |
| `simigo-rc1-20261023` | 125 | 75.0 MiB |
| `simigo-rc1-gate-closure-20261023` | 57 | 245.1 MiB |
| `simigo-rc1-repo-closure-20261023` | 24 | 12.2 MiB |
| `simigo-rc1-tools-vendoring-20261023` | 1 | 6.3 KiB |
| `simigo-runtime-contract-tests-20261024` | 15 | 4.5 MiB |
| `simigo-v2.2.0rc1-admission-increment-20261026` | 117 | 21.7 MiB |
| `simigo-v2.2.0rc1-layer-forward-calls-20261024` | 388 | 126.5 MiB |
| `simigo-v2.2.0rc1-local-acceptance-20261024` | 394 | 47.5 MiB |
| `simigo-v2.2.0rc1-os-page-return-20261024` | 42 | 9.9 MiB |
| `simigo-v2.2.0rc1-service-http-20261024` | 148 | 19.0 MiB |

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

## 单文件超限（> 50 MiB，保留原路径索引）

| 批次 | 文件 | 体积 |
| --- | --- | ---: |

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

- `noninterference_*.json`（9–26 MiB）是隔离性门证据的大快照，已随本批纳入。
- `derived/`、`run2/`、`scratch/`、`checkouts/`、`SourcePackages/` 为可再生成的构建/依赖产物。
- `envtest-root*/`、`envtest-final/` 含测试运行期 SQLite 与本地环境，属运行态数据。
- 完整还原需以本地归档 `research/_artifacts/SimiGo-Agent-Runs/` 为准；本清单给出被排除项的相对路径与体积。
