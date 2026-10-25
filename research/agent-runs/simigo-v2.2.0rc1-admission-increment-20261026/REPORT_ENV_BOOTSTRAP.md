# simigo-v2.2.0rc1-admission-increment-20261026 — 补充批次：方案 A + 生成环境自举（env-bootstrap）

生成于 2026-10-26 深夜。承接同批次目录的 admission increment 候选与真实域启动失败根因报告
（`ROOT_CAUSE_REALDOMAIN_START_FAILURE.md`），本补充批次完成 owner 裁定的方案 A 与
"从头建立完整生成环境"的落地。全部工作在 cleanroom 分支 `env-bootstrap-20261026`
（基线 = admission increment HEAD `c97f016`），7 个提交，候选可执行
`c4c2f80da1ba765727dc568c63b10b19ca1889a5573e83795a41f12c52794ca9`（2.2.0(26)）。

## 1. 结论

| 事项 | 判定 | 依据 |
| --- | --- | --- |
| 方案 A：LOCALB 身份迁出登录钥匙串 | **DONE**（`30beaa5`） | transport + signer 默认落 `<managed>/localb/*.keychain-db`（0600）；生产/隔离根统一 |
| 条目级 ACL（跨构建访问） | **DONE**（`e1a2e42`） | 全部 4 个创建点带 `SecAccess(trustedApps=[any])`；**跨签名实测**：Debug 构建读 Release 建的库 → `operational`、无交互 |
| 云 API key 迁出登录钥匙串 | **DONE**（`bd988c9`） | `<managed>/cloud/api-key`（0600 文件）；登录钥匙串零读写；operator 重贴一次 key |
| 一键生成环境自举 | **DONE**（`5e9b002`+`2df9e2d`） | `SIMIGO_ENV_BOOTSTRAP=1`：目录树→llama.cpp（版本锁）→hf→空白数据库→工作目录注册→（opt-in）LOCALB 仪式；JSON 报告 |
| 真实域恢复 | **DONE** | `~/.simigo` 全绿（manifest 锁定/llama 短路/hf 在位/DB existing 未动/LOCALB operational） |
| LOCALBCore 套件 | **41/41**（含测试卫生修复 `6f6bf35`：测试身份不再落真实域） | `swift test` exit 0 |
| App 隔离套件 | 273/14/1 → 失败项为并行构建负载下的 D3 计时断言，空闲重跑通过 | `run_isolated_eb1` + 单测重跑记录 |

## 2. env-bootstrap 用法（本轮交付的核心接口）

```
# 完整生成环境（全新安装或干净根）：
SIMIGO_ENV_BOOTSTRAP=1 [SIMIGO_WORKROOT=/abs/path] [SIMIGO_ENV_BOOTSTRAP_LOCALB=1] \
  [SIMIGO_ENV_BOOTSTRAP_REPORT=/path/report.json] SimiGo.app/Contents/MacOS/SimiGo
# SIMIGO_HOME 重定向一切（测试/实验）；不设 = 真实 ~/.simigo。
```

报告字段：`engine_manifest`（锁定 `0878f7c3…` = 用户环境已验证提交；operator 清单优先且不覆盖）、
`llama_cpp`（已装二进制短路——缓存清理后/离线重跑不再强制重新 clone）、`hf`（adopt→brew 安装→
`bin/hf`；无 brew 报 manual_required）、`database`（新根建空库 schema 3 + roots 注册；**已有库永不重置**）、
`localb`/`localb_ceremony`（resolveOperational 状态；opt-in 同进程 prepare→activate 仪式）。

数据库接口：`SimiGoESISDatabase(url:createIfNeeded:)` + `runMigrations()` + `upsertRoot` +
新增 `listRoots(category:)`（`f40db9c`）；工作目录 = roots 表（category `work`，locator `path`），
文件永不复制进 managed root（SimiGoPaths 禁止 work/models 子目录的设计不变）。

## 3. 真实域钥匙串事件线（全部有证据，最终态零弹窗）

1. 登录钥匙串旧生产条目（10-16 B3 dev 创建，签名 ACL）→ 每个新构建 error 59（-25293 AUTH_DENIED）。
2. 方案 A 后首弹窗：文件库条目默认 ACL 仍绑创建构建签名 → "输入 transport-identity 钥匙串密码"。
3. `e1a2e42` any-app ACL + operator 一次"始终允许" → **跨签名读取无交互**（实测 operational）。
4. 登录钥匙串清理：key/cert 类 2764 条已删（含生产旧私钥/证书）；tests/headless 泄漏 generic
   ~238 服务名 ACL 损坏无法程序化删除（GUI 亦不可）——已无任何进程读取它们，为无害死数据。
5. `CloudKeychain` 是最后一个登录域读点 → 文件域化（`bd988c9`）；现 App/SimiGoRuntime 生产代码
   登录钥匙串访问点为 **0**（grep 审计）。

## 4. Honest limits

- signer 私钥仍居 Keychain 文件库（仅靠 any-app ACL 免交互）；下一步可迁纯文件 0600
  （signer 无需 SecIdentity 合成），已登记未实施。
- App 隔离套件的 D3 性能断言需空闲环境（本轮并行构建导致一次计时失败，空闲复测通过）。
- RC1 的三个 BLOCKED 门与 GUI 验收仍属 RC1 线，本批次不声称闭合。
- 本分支未推送远端；合并与 RC 编号（rc2?）由 owner 决定。

## 5. 提交清单（cleanroom `env-bootstrap-20261026`）

```
e1a2e42 fix(localb): any-application ACL on items in the managed keychain files
bd988c9 fix(cloud): store the cloud API key in the managed root, not the login Keychain
2df9e2d feat(system): LOCALB first-run ceremony in env-bootstrap + build short-circuits
6f6bf35 test(localb): keep test identities out of the real managed keychain store
5e9b002 feat(system): one-shot generation-environment bootstrap
f40db9c feat(esis): read API for registered roots
30beaa5 fix(localb): scope production identity keychains to the managed file store
```
