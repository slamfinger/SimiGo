# GGUF D6：KV 主动失效后从 IS 恢复（V0.1）

日期：2026-11-10
装置：`SimiGoTests/GGUFContinuationD6InvalidationTests.swift`（隔离根，真 `llama-server`）
提交：`346beda`（"D6 四臂补正控与重启重试；真机 4/4 通过"）

**证据形态先说清**：本记录由该提交的信息与测试源码的断言整理，**没有**随仓的
`xcodebuild` 原始日志或账本。读数按提交信息原样转写，不补推、不扩样。

## 问题

llama-server 自己持有前缀 KV cells，产品侧 GGUF runtime 不导出代表，结算也不声明
KV 绑定。那么当上游 KV 被主动失效、甚至引擎重启之后，下一轮还能不能靠**已结算的
IS 记录**继续，而不是靠旧缓存继续？

## 四条臂

每条臂都先做正控（父提示确实占用了 slot，`n_prompt_tokens > 0`），再让 KV 失效，
然后发一个带 `previous_es_state_id` 的续接请求；每条臂同时有负控（幽灵锚被 422
`INPUT_ADMISSION_REFUSED` 拒绝，且不写结算、不推进会话）。

| 臂 | 失效方式 |
|---|---|
| A | `POST /slots/{id}?action=erase`（保留默认 host cache；erase 返回 `n_erased`，同提示重放 `cached_tokens=0`） |
| B | 引擎 sleep，下一次请求时 wake（`--cache-ram 0`） |
| C | 无 RAM prompt cache，父 slot 被覆盖后擦除（`--cache-ram 0`） |
| D | 同一个 `ManagedGGUFRuntime` stop 后重新 start；重启前确认端口已释放、重启后确认 slot 表全零 |

## 读数

- `Executed 4 tests, 0 skipped, 0 failures`，23 秒；四臂分别 5.6 / 5.6 / 3.9 / 6.8 秒。
- 真实用户态写入 0（隔离根）。
- 每条臂的续接请求都：`cached_tokens=0`、`input_tokens>0`、`output_tokens>0`，即
  **真的调用了模型且没有旧 KV 贡献**；回答里的数字只可能来自 IS 准入取回的值
  （客户端这一轮不带任何数字）。
- 子结算的 payload 摘要与父结算相等；子 ES 的 parent 指向父 ES；父结算没有被重写。

## 两条产品发现（本轮实测，仍开着）

1. **能结算的续接只能复述准入取回的值。** 续接结算施加的契约是
   `referenceResultContractJSON`（`SimiGo/App/ExecutionStateGraph.swift:408`）：
   `^RESULT=(.+)$` 加一条 `equals_binding`，把 content 钉在 `next_input` 上，而
   `next_input` 正是 `ISAdmission.admit` 用取回值铸出来的。实测 `ANSWER=<值+1>`
   能跑到引擎、流完 40 字节，仍被 422 `NATIVE_RESULT_CONTRACT_REJECTED /
   PRODUCER_RESULT_FIELD_MISSING` 拒掉。这是产品想要“续接＝复述”，还是该给派生值
   另配一条契约，未定。
2. **失效不沿续接链传播。** `settleContinuationResult` 经
   `recordNativeSettlementWithIdentity` 提交，不接受 `declaredDependencies`；实测
   子结算的 `upstreamDependencyClosure` 不含父结算，`is_dependency_entries` 只有
   子自己的 demand 行。父被失效时，子不会跟着失效；这条链上唯一的血缘是 ES 的
   parent 边。已固化成表征断言（测试文件 `:437-439`）。

附带发现：子 ES 行的 `next_input` 在库里是 NULL，值只进内存投影
（`ExecutionStateGraph.swift:574-586`），所以“取回值确实落盘”的可查证据是结算
payload 摘要，不是该列。

## 本记录不主张的事

- 单次模型加载、`--parallel 1`、单 checkpoint、单引擎构建（erase 语义 pin 在
  b11720），不构成样本。
- 只覆盖 D6 四条臂走的那一条续接路径；MLX 侧与 `settlement_consumption` 路径本轮未测。
- 没有原始日志：复跑得到的是新读数，不能与本轮逐项对账。
- 这是**带模型调用的 continuation**，不是零调用消费。

## 复现

```
tools/run_isolated_tests.sh \
  --app <.../Build/Products/Debug/SimiGo.app> \
  --gguf-model <绝对路径 .gguf> \
  --gguf-bin <绝对路径 llama-server> \
  --only-testing SimiGoTests/GGUFContinuationD6InvalidationTests \
  --expected-cases 4
```

`--expected-cases 4` 是判据：缺 GGUF 两条路径时四臂全部 `XCTSkip`，而“全跳过”
在默认口径下仍可能退出 0。脚本还会对隔离根之外的用户态写入做前后 diff。

## 2026-11-16 补：原始日志**明示排除**（owner 裁定，`ANOMALY_LEDGER_V0.1_20261116.md` A-11）

上面 :7-8「没有随仓的 `xcodebuild` 原始日志或账本」是**自陈缺口**；本段把它变成**明示裁定**：
D6 的原始日志**不入仓**（owner 2026-11-16）。这与「忘了存」不同——排除是被写下来的决定，
同仓 `MAINLINE_CORRECTIONS_V0.1_20261116.md` 末段对 arm C 原始日志的处置是同一类（账本 A-12，合规样例）。
原文一字未改，本段只并列现值。

**本件 :31 那遍（11-10）读数的出处**：提交 `346beda`（11-10 15:16）信息里的「真机读数」段，
逐字为 `Executed 4 tests, 0 skipped, 0 failures，23 秒` / `四臂分别 5.6 / 5.6 / 3.9 / 6.8 秒`。
**该轮原始 xctest 日志盘上已无**（本窗核过 `build/*.log` 全清单，最早的相关件是 11-12 的 `build/d6_run.log`）。

**盘上现存的两遍，都不是 :31 那一遍**（记下以免日后被误当成它的原始日志；两遍同样按裁定不入仓）：

| 遍 | 承载物 | 合计 | 四臂（秒） | 是否入仓 |
|---|---|---|---|---|
| 11-10（本件 :31） | **无原始日志**，只有 `346beda` 提交信息转写 | 23 秒 | 5.6 / 5.6 / 3.9 / 6.8 | — |
| 11-12 06:08 | `build/d6_run.log`（50,919 B，隔离目录 `build/test-isolation/20261111T220759Z/Test-d6.xcresult`） | `Executed 4 tests, with 0 failures in 23.476 s` | 6.934 / 5.912 / 4.277 / 6.353 | **否**（`.gitignore:6` = `build/`） |
| 11-16 04:54（run2） | `ES-IS-research/evidence/gguf-real-machine-20261116/run2_test_cases.txt`（5,544 B，sha256 `86a327c8226a9d05717bdb22f609655bb82612f115586b6df5d3ca4eb65d8db4`） | `Executed 4 tests, with 0 failures in 24.497 s` | 5.348 / 5.711 / 4.785 / 8.652 | **是**（在研究仓，tracked） |

即：三遍 D6 里**只有 11-16 那遍有随仓的逐用例原始行**；它的完整 xcodebuild 输出（68,204 B）
按该 evidence 包 `MANIFEST.md`「排除（未承载）」段的明示条款留在 gitignored 目录、会随清理丢失。

**更正一处账面口径**：`build/bft-gguf-real-20261116.log`（88,491 B）是 **build-for-testing 的构建日志**
（尾行 `** TEST BUILD SUCCEEDED **`，`grep -c -i d6` → **0**），**不含任何用例执行行**。
账本 A-11/A-17 里把它称作 run2 的「原始日志」不准确，以本段为准（账本按只追加规则另行更正）。

**引擎口径提醒**：本件 :59-60 说 erase 语义 pin 在 b11720，而 `346beda` 自陈的引擎是
`llama.cpp @ 0878f7c，0.7.0-dev build 1`，run2 用的自管二进制 `~/.simigo/bin/llama-server --version`
报同一串（账本 **A-13，未闭合**：版本串错、build 号对自管二进制不成立）。重跑前先确认引擎，
不要把 :59-60 当成已核事实。

**排除的代价（明示，owner 已接受）**：:31 的读数永远只能靠提交信息转写，第三方无法用原始日志逐行核对；
能核对的路径只有重跑（下面「复现」节 + `--expected-cases 4` 判据），而重跑得到的是**新读数**，
不能与本轮逐项对账（:62 原句仍有效）。
