# simigo-v2.2.0rc1-admission-increment-20261026 — admission increment 独立候选构建

生成于 2026-10-26。执行 RESEARCH_STATE.md 2026-10-25 层登记的下一步：
**admission increment 作为独立新候选 build（带 identity record），保留 RC1 `83a880…` 候选及其证据**。

## 1. 结论

| 事项 | 判定 | 依据 |
| --- | --- | --- |
| 候选构建 | **BUILD SUCCEEDED**（Release，cleanroom） | `build_release.log` |
| 新候选身份 | exe `05164812c2bf901285c8d7cc5351c03d4ff92c08eb49f9f284d89e761c3d7ce4`、bundle 树 `e8983cdd…`（19 文件）、`installed_equals_built=true`、2.2.0 (26)、codesign rc=0 | `evidence/install_identity_admission_candidate.json` |
| 源码冻结 | HEAD `c97f016`（分支 `codex/nativemlx-continuation-settlement-adapter-20261025`），树 **干净**（0 dirty）——RC1 的 13 文件 dirty 集已作为 `342c7ec` 提交入树 | cleanroom `git status` = 0 |
| App 套件（隔离） | **270 / 14 skip / 0 失败**，exit 0，真实用户状态写入 0，隔离根新鲜 | `run_isolated_ai1/isolation_run_ai1.json`（对照 RC1 批次 208：套件随 admission/continuation 增量增长 62 项且全绿） |
| Service/HTTP 门（新候选上实跑） | **5/5 PASS**（S1 授权 200 / S2 无效 proof 拒绝 / S3 生成 / S4 无效 proof 不生成 / S5 缺激活在生成前拒绝） | `evidence/gate_ai/service_http_gate_verdict.json` |
| Keychain 非干预 | 2035 → 2035（0 增 0 删） | `evidence/keychain_ai_{pre,post}.json` |
| RC1 保留 | exe `83a88048…` 候选及其全部批次目录**未触碰**（本批次全部为新目录） | 目录对照 |

**一句话**：状态层 10-25 登记的"admission increment 独立候选 build + identity record"已落地：
admission→生成→native result contract→IS settlement 链路（提交 `2b244d2`→`7846539`→`03efedf`→`19c99e2`→`b5ce3b8`→`6757414`/`bf04049`/`671fe36`/`edbcc7a`/`74f03d4`/`c97f016`）现在有了自己的候选二进制与门证据；RC1 `83a880…` 原样保留。

## 2. 被构建对象（身份锚定）

| 项 | 值 |
| --- | --- |
| 源码 HEAD | `c97f016`（cleanroom clone，detached；**不含**所有权会话的任何在途未提交工作） |
| 分支 | `codex/nativemlx-continuation-settlement-adapter-20261025`（ahead 8 的全部提交在内） |
| 基线 | RC1 冻结基线 `f18d65f`（`localb-b3-closure-20261016`）之上的连续提交线 |
| 增量内容 | continuation admission 接线、settlement 响应契约 v0.1、原生适配器接线、原子结算、契约强制、ESIS 原子修复（即登记的 `output → native result contract → IS settlement` 边） |
| 模型 | 未绑定（本批次为模型无关门；模型门沿用各轮既有证据） |

## 3. 边界（honest limits）

- 本批次**不**更新 `simigo-v2.2.0rc1-local-acceptance-20261024/acceptance_report.json` 的任何门记录
  （沿用 os-page-return 轮的同一规则：批次的门记录由各批次自持，汇总判定待 owner）。
- RC1 的三个 BLOCKED 门（install_and_operate / product_service_http / per_layer_forward_calls）
  与 GUI 前置条件**在本批次中原样未动**——本批次不声称闭合它们。
- `spctl rc=3`（Gatekeeper 拒绝本地未公证 RC）为环境约束记录，非构建失败（同 RC1 批次口径）。
- 所有权会话的在途未提交工作（detached-fork/rotating 线）**不在本候选内**——它未提交、未冻结。

## 4. 复现命令

```
git clone <产品仓> cleanroom/repo && cd cleanroom/repo && git checkout c97f016
xcodebuild build -project SimiGo.xcodeproj -scheme SimiGo -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath <batch>/build/Build
cp -R <batch>/build/Build/Build/Products/Release/SimiGo.app <batch>/install/SimiGo.app
python3 driver/make_install_identity.py --app <batch>/install/SimiGo.app \
  --built <batch>/build/Build/Build/Products/Release/SimiGo.app \
  --out <batch>/evidence/install_identity_admission_candidate.json
xcodebuild build-for-testing … -derivedDataPath <batch>/build/test   # 见 build_test.log
tools/run_isolated_tests.sh --app <batch>/build/test/Build/Products/Debug/SimiGo.app \
  --tag ai1 --evidence-dir <batch>/run_isolated_ai1
python3 driver/run_service_http_gate.py --evidence-dir evidence/gate_ai \
  --roots-prefix ai --port-base 8600 --app <batch>/install/SimiGo.app \
  --build-product <batch>/build/Build/Build/Products/Release/SimiGo.app
python3 driver/verify_service_http_gate.py \
  --source evidence/gate_ai/service_http_gate_installed.json \
  --out evidence/gate_ai/service_http_gate_verdict.json
python3 driver/make_evidence_index.py && python3 driver/make_manifest.py . && sh driver/verify_manifest.sh
```
