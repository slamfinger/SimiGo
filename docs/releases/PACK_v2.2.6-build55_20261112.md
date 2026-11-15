# SimiGo v2.2.6 (build 55) 打包记录

**性质**：本轮打包与本机验证的读数，不是推断。每条写明已证/未证。

## 产物

| 项 | 值 |
| --- | --- |
| DMG | `SimiGo-v2.2.6-55-2a059aeb.dmg` |
| 大小 | 23,902,813 bytes |
| DMG SHA-256 | `1c7b7abd94f57913f8c198bab42d462897c92237ec44dc7b44e29701efb74c49` |
| 版本 | CFBundleShortVersionString 2.2.6 / CFBundleVersion 55 |
| DMG 内可执行文件 SHA-256 前八位 | `2a059aeb`（擦除路径并重签后计算，与文件名一致） |
| 构建产物可执行文件 SHA-256 | `12d9c6651dda07637caed1c28cb1515c831e14c4f38c0ed4c5a6d495bc55b324`（未擦除，未进 DMG） |
| 签名 | adhoc（flags=0x10002 adhoc,runtime，TeamIdentifier 未设置），未公证 |

## 源码身份

- 分支 `main`，提交 `8c40a6f9`（含 #171 / #181 / #184）
- 版本 bump 提交 `2fcb3d0 chore(build): build 55`（54 → 55；MARKETING_VERSION 仍 2.2.6）
- 构建：`xcodebuild -scheme SimiGo -configuration Release -derivedDataPath build/release-v2.1 ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO build` → BUILD SUCCEEDED

## 已验证

- `hdiutil verify` → VALID（CRC32 4D0456A0）
- 挂载后 `codesign --verify --deep --strict SimiGo.app` → 通过
- DMG 内含 `SimiGo.app`、`Applications` 软链接、`安装SimiGo.app`
- `redact_binary_paths.py`：leftover forbidden literals: none
- 迁移演练 `tools/migration_drill.sh --new build/release-v2.1/.../SimiGo.app`（全程副本库，未碰 `~/.simigo/simigo.sqlite3`）：全部判据通过
  - 旧包(54)打开副本：停在 schema 35，7 张表行数 7629|3156|37903|6|3448|9915|1408 不变
  - 新包(55)打开：升到 schema 36，行数不变
  - 旧包再开 36 库：拒绝，`migration head 36 != declared 35`
  - 副本 `pragma table_info(settlements)` 尾部出现 `result_contract_id`(11)、`result_contract_digest`(12)
- 演练副本已删除

## 未证

- 安装前：真库仍是 schema 35（21:38 读数）
- 未公证；首次打开需绕过 Gatekeeper

## 安装后核对（21:44 安装，21:46 读数）

| 项 | 结果 |
| --- | --- |
| `/Applications/SimiGo.app` 版本 | 2.2.6 (55) |
| 真库 `schema_migrations` 最高版本 | **36**（35 于 816094374 写入，36 于 816183848 写入） |
| `pragma table_info(settlements)` | 新增 `result_contract_id`(11)、`result_contract_digest`(12) |
| `pragma integrity_check` | ok |
| 行数（迁移前副本 → 真库） | chat_messages 7629→7631、turn_digests 3156→3157、is_objects 37903→37904、spaces 6、space_turns 3448、keywords 9915→9916、settlements 1408（增量为安装后本轮对话写入，无丢失） |
| 迁移前备份 | `~/.simigo/simigo.zip`（内含 21:22 的库）：版本 35、无新列、integrity ok，可回滚 |
| `bootstrap-report.json` | `migrate-schema` ok（schemaVersion=36）；`reconcile-roots` **failed**，issueCount=1 |

### reconcile-roots 失败的原因（已定位）

两个注册工作根在副本库上复现，抛的都是
`settleWorkRootContents: maxTotalBytesRead exceeded (67108864)`：

| 根 | 文件数 | 总字节 | 按每文件 ≤256 KB 尾部读的读取预算 |
| --- | --- | --- | --- |
| ~/Desktop/参考文件 | 1332 | 2.0 GB | 153 MB |
| ~/Desktop/26.秦沈项目 | 3077 | 17.6 GB | 446 MB |

启动阶段每根 64 MiB 的累计读取上限是既有设计（`Bootstrap` 调
`reconcileRegisteredRoots(minAgeSeconds: 600)`，走默认 `maxTotalBytesRead`），
不是 v36 迁移引入的回归；迁移本身（加列、版本自增、完整性检查）全部通过。
两个根自 2026-11-04 之后就没有再成功扫描过（`roots.last_scanned_at` 停在
815858758），说明超限在先、迁移在后。

未处置：未改上限、未拆分根、未降级该步状态。属设计决策，留给 owner。

---

# build 56：按方案 1 放宽根扫描预算

## 改动

| 文件 | 改动 |
| --- | --- |
| `ESISDatabase.swift` | 新增 `rootScanReadBudget = 4_096 × 256 KB = 1 GiB`；`reconcileRegisteredRoots` 增加 `maxTotalBytesRead` 参数，默认取该预算并透传给 `settleWorkRootContents` |
| `Bootstrap.swift` | `run(...)` 增加 `maxRootReadBytes`（默认同上预算），`index-work` 与 `reconcile-roots` 两处都使用 |
| `BootstrapTests.swift` | 新增：68.6 MB 的根（>旧 64 MiB 上限）在默认预算下 reconcile 为 ok；预算压到 1 字节时仍报 `failedRoots=1` |

提交：`2f82100`（修复）、`057b502`（build 56）。
`swift test`（SimiGoRuntime，含新增用例）：**397 通过，0 失败**。

## 产物

| 项 | 值 |
| --- | --- |
| DMG | `SimiGo-v2.2.6-56-ec82a386.dmg` |
| 大小 | 23,904,022 B |
| DMG SHA-256 | `f2840c6c47ec20803647051256b0de97b30ddf2ee9dd3c425ddf074aae62d1f2` |
| 版本 | 2.2.6 (56) |
| DMG 内二进制 sha256 前八位 | `ec82a386` |
| 结构校验 | `hdiutil verify` VALID；挂载后 `codesign --verify --deep --strict` 通过 |

## 已验证（副本库上的真实启动）

真库 `.backup` 到 `SIMIGO_HOME` 副本，用 build 56 二进制启动一次（不碰真库），
读 `manifests/bootstrap-report.json`：

```
schemaVersion=36  issueCount=0
reconcile-roots  ok  roots=2 settled=2 fresh=0 missing=0 unlocatable=0
                     scanned=3249 changed=0 removed=30 invalidated=0
```

两个桌面根（2.0 GB / 17.6 GB）本次都核对成功；`removed=30` 是副本里
`external_files` 记录的 30 个源文件已不在磁盘上，按预期标为 removed。
临时副本与运行实例均已清理。

## 未证

- 未测放宽后的启动耗时（本例 3249 个文件的核对在 5 秒内完成报告写入，
  但没有做冷启动计时对比）
- 未公证

## 装上 56 之后的真机读数（22:16–22:18）

- `/Applications/SimiGo.app` = 2.2.6 (56)，进程在跑，8000 是 MLX 模型服务
- `~/.simigo/manifests/bootstrap-report.json`（22:16:47）：
  `schemaVersion=36`、**`issueCount=0`**、`reconcile-roots ok`
  （`roots=2 settled=0 fresh=2`——两个根在 10 分钟内已扫过，按设计跳过）
- `roots.last_scanned_at` 两条都刷新到 22:15:39/22:15:40；
  `external_files` 的 `last_seen_at` 也在同一刻刷新
- 当场强制核对（MCP `simigo_is_reconcile`，跳过 fresh 窗口）：
  `root_count=2 settled_roots=2 failed_roots=0 scanned=3249 reused=285
  changed=0 removed=0`，1.6 秒返回
- `settlements` 仍 1408 行，`result_contract_id` 仍全 NULL（没有新结算）
