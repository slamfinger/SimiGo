# C-6d · KV-free 验收矩阵（测试层）· 2026-10-27

> 本文件是**测试层**读数归档。按 2026-10-27 口径，测试层读数不写入
> `ACCEPTANCE-20261026-BUILD-97043902.md` 的 §3.x 真机节；真机（Release/DMG +
> 真实模型）读数另起 §3.x。测试层通过 ≠ 产品层通过。

## 0. 这轮要回答的问题

「ES/IS 的正确性与语义连续性不得依赖任何持久化 KV Cache」——具体到可验收的动作：
**两个 KV 目录（`prefix-pool`、`branch-checkpoints`）在同一轮里既不可读也不可写时，
已结算结果的消费、跨重启恢复、未结算在途生成的重新执行是否仍然成立，且没有任何
静默重定向到第三个目录。**

## 1. 构建与证据身份（事实）

| 项 | 值 |
| --- | --- |
| 源码 HEAD | `97043902075b67eb1693749fd6ed50421eccf3ba` |
| tracked diff sha256 | `b2a02ce2cfdef9a83d04caaff58463c1d7a7e0fcb922c54b6367b21de3171a36` |
| 未跟踪新文件数 | 27 |
| 测试宿主二进制 sha256 | `87b72302a316c9a10e205ff38566c44e303d6d4f6bbb02d1757f3eca3977ce18`（Debug 每次构建重新签名，二进制不可逐位复现；稳定身份以 HEAD + tracked diff 为准） |
| 测试宿主 mtime | 2026-10-27 13:56:01 |
| 构建 | Debug，`-enableCodeCoverage NO build-for-testing`，产物 `/tmp/simigo-c4-build` |
| KV-free xctestrun sha256 | `47d20bd882e3c1dc5a8757e56947d70d7d05fb6419025c33670c65de83ed8725` |
| switches-on 探针 xctestrun sha256 | `1d6ec40a9f3aacb1f67b78402205de22a7e6ae64f88ea87078f5d78bb7039408` |
| 隔离根 | `/tmp/simigo-kvfree-20261027-135633/iso` |
| 被阻塞的 cache 根 | `/tmp/simigo-kvfree-20261027-135633/blocker/cache`（`blocker` 是普通文件） |

## 2. 前提如何被强制（事实）

`tools/make_isolated_xctestrun.py`（只执行，未修改）先注入三个隔离根，随后对生成的
xctestrun 追加环境变量（该文件在 `/tmp`，非仓库文件）：

- 配置 A（KV-free 产品配置）：
  `SIMIGO_PREFIX_POOL=0`、`SIMIGO_BRANCH_CHECKPOINTS=0`、
  `SIMIGO_CACHE_ROOT=<blocker>/cache`、`SIMIGO_KV_FREE_MATRIX=1`
- 配置 B（对照：开关保持默认，根仍阻塞）：`SIMIGO_CACHE_ROOT=<blocker>/cache`、
  `SIMIGO_KV_BLOCKED_ONLY=1`

`blocker` 是**普通文件**，因此 `<blocker>/cache/prefix-pool` 与
`<blocker>/cache/branch-checkpoints` 同时不可创建（ENOTDIR）、不可列目录。
测试在 `setUp` 与每个断言点重新自检这条前提（`assertKVUnavailable`）：
两个根解析到被阻塞根之下、均不存在、列目录抛错、创建抛错，且隔离 home 下没有出现
同名目录。**开关只是配置，前提是路径本身不可用**——两者都被断言。

## 3. 结果（事实）

### 3.1 配置 A：两个开关关闭 + 两个根阻塞

| 用例 | 结果 | 断言要点 |
| --- | --- | --- |
| `testPremiseBothKVRootsAreSimultaneouslyUnavailable` | PASS | 开关均为 false；两根本身不可读/不可写；`defaultBranchCheckpointStore()` 未创建目录 |
| `testK1SettledResultIsConsumedWithZeroModelCallsWhileKVUnavailable` | PASS | 首次结算 `modelCalls=1 / settlementsWritten=1`；同键重放 `modelCalls=0 / settlementsWritten=0`，内容=首次结算值；账本行数不变 |
| `testK2SettledResultRecoversAfterRestartWithoutKV` | PASS | 新连接（重启等价）读回结算与快照，`final.verify(against: declared)` 通过；重放 0 次模型调用、内容不变 |
| `testK3InterruptedGenerationIsNeverSettledAndReexecutesFromAnchor` | PASS | 中断尝试：账本行数不变、锚点结算不变；重跑 1 次模型调用、写入 1 条结算、子状态 position=2；中断产出的部分文本未进入重跑 prompt |
| `testSwitchOnWithBlockedRootsDegradesWithoutRedirecting` | SKIP | 属于配置 B |

合计：`Executed 5 tests, 1 skipped, 0 failures`（`/tmp/simigo-c6d-kvfree.log`）。

KV 文件读数：每个断言点两根本身都不存在；隔离 home 下未出现 `prefix-pool` /
`branch-checkpoints` 目录。被阻塞根之下不可能落下任何文件——一旦落下，下一次
`fileExists` 断言即失败。真实 `~/.simigo` **故意不断言**（它本来就存有 operator 自己的
KV；重定向到那里会先被本条路径断言拦下），本轮全程未向其写入。

### 3.2 配置 B：开关保持默认 + 两个根阻塞（无静默重定向对照）

`testSwitchOnWithBlockedRootsDegradesWithoutRedirecting` PASS：
`prefixPoolEnabled`、`branchCheckpointsEnabled` 均为 true；`defaultBranchCheckpointStore()`
解析到被阻塞根之下且**未创建目录**；`NativeMLXPrefixPool.shared.admit(...)` 返回 nil
（miss，不崩溃、不重定向）；两个根此后仍不存在。

合计：`Executed 5 tests, 4 skipped, 0 failures`（`/tmp/simigo-c6d-kvblocked.log`）。

### 3.3 回归：C-6 归属套件（干净隔离根）

`ManagedContinuationAdapterTests`(7) + `ResponsesManagedContinuationHTTPTests`(11) +
`ResponsesSettlementConsumptionHTTPTests`(10) + `ISKVBindAuthorityTests`(5) +
`KVFreeContinuityTests`(5，未注入标记→正确 skip)：
`Executed 38 tests, 5 skipped, 0 failures`（`/tmp/simigo-c4-c6.log`）。

## 4. 结论

1. **测试层**：在两个 KV 根同时不可读、不可写的条件下，已结算结果的消费（K1）、
   跨连接/重启的恢复（K2）、中断后的重新执行（K3）全部由 ES/IS 承载，模型调用数、
   结算写入数、KV 目录落盘三者被分别断言。
2. 开关关闭时**没有任何** KV 目录被创建、读取或写入；开关保持默认而根不可用时，
   池与 checkpoint 存储均优雅 miss，**没有**重定向到隔离 home 或真实 home。
3. 关闭持久化不是「把写失败变成功」：`performSave` / `performLoad` 在关闭时抛出具名
   错误（`branch checkpoints are disabled (SIMIGO_BRANCH_CHECKPOINTS=0)`），
   `suspendIfIdle` 不再因脏会话拒绝挂起，脏会话随挂起释放；未结算的在途生成不是有效
   结果，恢复交给 ES/IS 的已结算锚点与重新执行。

## 5. 未执行 / 不构成证据的部分

- **引擎层 KV 文件 IO 计数**：测试层不加载模型，`NativeMLX` 的 save/load 路径未被
  真实生成驱动；「零 KV 文件写入」在测试层由「目录不存在 + 流程成功 + 无回退目录」
  间接证明，直接的写入计数需真机。
- **真实 `suspendIfIdle` 路径**：需要已加载模型与空闲窗口，测试层无法触发。
- **真实进程重启**：K2 用「新数据库连接」等价模拟；真进程重启需安装版。
- **Release / DMG / 安装版 / 真实模型**：全部未执行（第二层验收）。
- 全量套件（326 用例）中另有 6 个真实模型/E2E 用例失败：
  `ExternalAdoptionInferenceE2ETests`（需外部端点）、
  `GovernedContinuationKVRestoreRealModelE2ETests`（需 `SIMIGO_A11_HANDOFF`、固定端口
  18473、真实模型）与已知启动缺陷 #30（测试 bundle 消失 → Could not launch）。
  这些不属于 C-6 的度量集合；且配置默认时本次新增的每处开关判断都是恒真分支，
  行为与改动前逐字节等价。

## 6. 复跑命令

```sh
ROOT=/tmp/simigo-kvfree-$(date +%Y%m%d-%H%M%S); mkdir -p "$ROOT/iso"
printf 'kv-free blocker\n' > "$ROOT/blocker"
python3 tools/make_isolated_xctestrun.py \
  --app /tmp/simigo-c4-build/Build/Products/Debug/SimiGo.app \
  --isolation-root "$ROOT/iso" \
  --base-xctestrun /tmp/simigo-c4-build/Build/Products/SimiGo_SimiGo_macosx27.0-arm64.xctestrun \
  --out /tmp/simigo-c4-build/Build/Products/xctestrun_kvfree.xctestrun
# 再向该 xctestrun 的 EnvironmentVariables 追加：
#   SIMIGO_CACHE_ROOT=$ROOT/blocker/cache
#   SIMIGO_PREFIX_POOL=0  SIMIGO_BRANCH_CHECKPOINTS=0  SIMIGO_KV_FREE_MATRIX=1
xcodebuild test-without-building \
  -xctestrun /tmp/simigo-c4-build/Build/Products/xctestrun_kvfree.xctestrun \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:SimiGoTests/KVFreeContinuityTests
```

## 7. 阶段 2 收官复跑（2026-10-27 14:37–14:55，全新隔离根）

> 本节的日志与 xctestrun 原始件保存在 `c6d-stage2-logs-20261027/`，清单见该目录
> `SHA256SUMS.txt`。本节只追加，不改写 §3 的读数。

### 7.1 事实：五套件回归（全新根 `/tmp/simigo-final-iso-20261027-143714`）

`ManagedContinuationAdapterTests`、`ResponsesManagedContinuationHTTPTests`、
`ResponsesSettlementConsumptionHTTPTests`、`ResponsesContinuationHTTPIntegrationTests`、
`ISKVBindAuthorityTests` 同进程执行：

```
Executed 48 tests, with 3 failures (0 unexpected) in 27.873 seconds
```

失败的 3 条全部在 `ResponsesContinuationHTTPIntegrationTests`：

| 行 | 用例 | 断言原文 |
|---|---|---|
| 484 | `testAdmissionWithoutSettleStaysOnTheClientBranch` | `("2") is not equal to ("1") — admission alone must not create an ES row` |
| 696 | `testNativeContractRejectionIs422AndWritesNothing` | `("49") is not equal to ("28") — a contract rejection must add no identity binding row` |
| 740 | `testSettlementWriteFailureIs500WithNoPartialCommit` | `("73") is not equal to ("52") — identity + constraint bindings must all roll back` |

### 7.2 事实：这三条失败全部来自 IS 侧写入，不是本 delta 的回归

同一次构建上做的三个对照：

1. **三条单独跑**（全新根 `/tmp/simigo-diag-20261027-144532`，`xctestrun_diag`）：
   `testNative…` 与 `testSettlementWriteFailure…` **通过**，只有
   `testAdmissionWithoutSettle…` 失败（`2` vs `1`）——即已知的 14/15 红灯。
2. **整类单独跑**（复用 7.1 的根，`xctestrun_final`）：
   `Executed 15 tests, with 1 failure` —— 只有已知那条。
3. **数据库取证**（7.1 的根）：两条“新增”失败各自多出的正是 **21 行**
   `settlement_bindings`，全部 `name='content'`，属于 3 个
   `settlement_id` 以 `is-retrieval:` 开头、`contract_version='simigo.is-retrieval/v1'`
   的 IS 检索结算（每次命中 21 个文件 → 21 条 `content` 绑定，由
   `linkSettlementToExternalFile` 写入）。已知那条多出的 1 行 `execution_states`
   是 `chat-e323b95a-…`（position 0，`next_input='plain answer, no contract'`），
   即已记录的「IS 写 chat-* 行导致计数差 1」。

**结论**：两条“新”失败是**全表计数器 + IS 检索结算**在套件顺序下的产物——前面的
续跑/消费套件写入新结算后，IS 候选集变化使检索缓存 miss，下一次请求在断言窗口内
落下一条 `is-retrieval` 结算；断言把 IS 的 `content` 绑定也算进“续跑结算的绑定行”。
它们在单类/单例运行中即消失。本 delta 只改 `RuntimeTuning` 与 `NativeMLX` 的
checkpoint 守卫，且默认配置下每处守卫都是恒真分支，与 IS 检索路径无交集。
判据不放宽，读数按原样保留。

### 7.3 事实：KV-free 两配置在最终隔离根上复跑（`/tmp/simigo-final-kv-20261027-145323`）

- 配置 A（`SIMIGO_PREFIX_POOL=0` + `SIMIGO_BRANCH_CHECKPOINTS=0`，
  `SIMIGO_CACHE_ROOT=$ROOT/blocker/cache`，`blocker` 是普通文件）：
  `Executed 5 tests, with 1 test skipped and 0 failures`——K1/K2/K3 与前提用例全绿，
  `testSwitchOnWithBlockedRoots…` 按标记跳过。
- 配置 B（开关保持默认 + 两个根阻塞）：`Executed 5 tests, with 4 tests skipped and
  0 failures`——无重定向对照通过。
- 运行后盘点：`$ROOT` 下只有 `blocker`（文件）与 `iso/`，**没有**生成
  `prefix-pool` 或 `branch-checkpoints`；真实 `~/.simigo`（8.2G）及其两个 KV 目录
  mtime 仍为 10-26 19:06 / 10-27 03:47 / 04:19，均早于本轮运行，未被触碰。

### 7.4 未执行（与 §5 相同，不因本节而改变）

引擎层 KV 文件 IO 计数、真实 `suspendIfIdle`、真实进程重启、Release/DMG 安装版 +
真实模型，以及全量 326 用例中的真实模型/抢端口/#30 启动故障——仍属第二层验收，
留待阶段 3。
