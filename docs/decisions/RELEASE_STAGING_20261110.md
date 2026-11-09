# 2.2.6(37) 发布自证记录（2026-11-10）

**性质**：本轮发版前的门禁处置登记。记录的都是我这台机器上跑出来的读数，
不是推断；每条都写明"已证"与"未证"。

## 1. 产物与源码的对应关系（原先缺的那条链）

02:02 打出的 `SimiGo-v2.2.6-37-fa230358.dmg` 找不到构建目录：DerivedData 里只有
前一天的 Release（`ce3512ff`）与一颗 Debug（`af90f934`），那颗 build 目录已随临时
worktree 一起清掉。本轮在 `build/release-v2.1` 用当前 HEAD 重编，得到的二进制
sha256 前八位正是 `fa230358`——同一路径、同一份源码、同一颗字节。产物与源码的
对应关系由此成立，不再靠时间推断。

## 2. 覆盖面：Release 一直是带覆盖率插桩的

`xcodebuild -showBuildSettings` 解析出 `ENABLE_CODE_COVERAGE = YES`、
`CLANG_COVERAGE_MAPPING = YES`（项目文件与 scheme 里都没有这两项，是构建环境给的）。
后果两条：

- 二进制 121,407,584 字节，比不带插桩时大 45 MB；
- 每个函数的覆盖记录名是 `___profc_<#filePath>:<函数>`，把
  `~/Documents/SimiGo-new-root/...` 的绝对家目录形式原样写进
  `__llvm_prf_names`：实测家目录前缀与用户名各 38,312 处。

处置：Release 用 `ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO` 重编，
二进制降到 76,064,256 字节，路径串降到 2,958 处（只剩 Swift 的 `#filePath`）。
插桩关闭不改变语义，只去掉计数器与覆盖表。

## 3. 残余路径串：等长擦除，不碰指令

剩下的 2,958 处落在 `__TEXT,__cstring`（抽样核对：偏移 34,116,005 起的那批确实
在 `__TEXT,__cstring`，不在 `__text`）。文本级清洗救不了 Mach-O：变长替换会让
`__cstring` 之后的偏移与代码签名一起作废。

处置：`tools/redact_binary_paths.py` 做等长替换（家目录前缀 → `/build/`，用户名 →
等长填充），文件长度不变，替换后重新 adhoc 签名。这个步骤已经写进
`tools/make_release_dmg.sh`（`--no-backup`，副本不落进 staging），名字里的
`EXE8` 也改成擦除之后再算——文件名必须描述真正发出去的那颗二进制。

## 4. staging 门：两条判定，一条已知偏离

- **`SimiGo.app` 目录（真正要发布的字节）**：`release_staging_audit.py` → **PASS**
  （19 个文件，raw + 容器解码 + 规则集）。
- **整个 DMG 卷**：**FAIL**，唯一命中 `symlink in staging directory: Applications`。

这条不是缺陷而是设计：`Applications` 是安装器的拖放目标，软链接指向审计没读过的
字节，规则因此 fail-closed。**本记录不改规则**，只登记偏离：整卷审计的结论对
`SimiGo.app` 与 `安装SimiGo.app` 有效，对那个软链接的指向目标无效（它不发布任何
字节，只是 `ln -s /Applications`）。若将来要整卷通过，需要 owner 决定是否给该
软链接开白名单——那是改审计契约，不在这份记录的处置范围内。

## 5. 另外两道门（现值）

- `release_manifest.py`：重 derive 后 **PASS** —— 598 input(s)、58 exclusion
  record(s)、656 candidate(s) 全部记账，无目录通配，逐条 hash 对树。
- `release_artifact_audit.py`（仓库隐私）：**PASS** —— 654 个 tracked 文件，
  不可判定容器 0。此前红的两份文档（`EXPERIMENT_ARMS_V0.1_20261108.md`、
  `RUNTIME_FORM_V0.1_20261108.md`）里的绝对家目录路径已改成 `~/` 形式。

## 6. 本轮产物

| 项 | 值 |
|---|---|
| DMG | `SimiGo-v2.2.6-37-f4a85c02.dmg`，23,693,227 B，sha256 `ea19707f14a57cb106f0…` |
| 可执行文件 | `SimiGo.app/Contents/MacOS/SimiGo`，76,064,256 B，sha256 前八位 `f4a85c02` |
| 版本 | CFBundleShortVersionString 2.2.6 / CFBundleVersion 37 |
| 签名 | adhoc（`Signature=adhoc`，`TeamIdentifier=not set`），未公证 |
| 结构校验 | `hdiutil verify` → VALID；`codesign --verify --deep --strict` → 通过 |
| 载荷审计 | `SimiGo.app` → PASS；整卷仅 `Applications` 软链接一处 |

## 7. 未证（不要当成已证）

- 没有跑 app 层测试（`SimiGoTests` 只证编译），`swift test --package-path
  Packages/SimiGoRuntime` 本轮也没重跑（最后一次 305 绿在 T5 之后）。
- 没有在装好的 Release 版上跑冒烟（首启向导、引擎自举、MCP 12 工具）；当前 8000
  端口上跑的是 Debug 版。
- 擦除只做结构核对（长度不变、命中清零、偏移落在 `__cstring`、签名重验通过），
  没有做逐指令比对；改变的是字符串内容，理论上 `#filePath` 若被逻辑使用会产生
  行为差异——本仓库目前没有这种用法，但这是推理，不是验证。
- 未公证，用户首次打开仍需绕过 Gatekeeper。
