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
