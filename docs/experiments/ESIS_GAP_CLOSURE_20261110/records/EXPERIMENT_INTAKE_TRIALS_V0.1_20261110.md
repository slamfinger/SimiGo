# intake paired trials V0.1：第二/第三 intake 过消费判据

日期：2026-11-10
装置：`tools/baseline/intake_driver.py` v1（复用 baseline_driver 的 spawn/http/退出对账；
新增 MCP 调用器与外部轮次 CLI 动词 `ext-turn`——与 app 的 ExternalTurnSink.write
同一函数组 recordExternalTurn/recordExternalResponse/verifyExternalTurn）
运行产物：`runs/intake-trials-20261110/`（ledger `74f735c2…`、summary、manifest、
实验库快照 `2e88096a…`、server-s3.log）
产品基线：HEAD `29217b0`，二进制同 carrier 验收（`4398b5aa…`）
加载：1 次（global_load_ledger，purpose=intake-trials）；静默窗豁免同 carrier 验收

## 为什么做

论文 §6.7 自报："Both intakes are implemented; neither has been run through the
paired trials. What is untested here is therefore a cross-model reading, not the
path." —— 缺的是 cross-model reading：外部声明身份的结算被本机零调用消费。

## 第二 intake（cross-model reading）——读数

外部 agent 保留自己的云端 API，只向产品**声明**身份并调用结算工具：

| # | 步骤 | 读数 |
|---|---|---|
| 1 | MCP `simigo_es_begin`（model=`ext-cloud/declared-model-alpha`，tokenizer=`ext-tokenizer-alpha`） | state `91959DE8…`；**reusable_answer=null**（语义未漂移，装置硬门） |
| 2 | MCP `simigo_es_settle`（同声明身份 + output + idempotency_key） | 结算 `520E3AF2…`；**产品模型调用 0 次**（声明身份是 provenance 不是 verification） |
| 3 | 声明复用契约（contract_cli declare，与 paired trials 同路径） | DECLARED |
| 4 | C' 臂：显式消费该结算（allow_recompute=false） | **outcome=consumed、model_calls=0**、consumer ES `es-2dbf6b6e…` + 派生结算（相对 intake 前账本新物 1/1）、返回值经 get-value 准入读路径**相等**、0.016s |
| 5 | R' 控制臂：本地真模型（Qwen3-30B）对不同 demand 重新生成 | 89 chunks、answer_reuse 缺席——**跨模型对照**：外部声明结算被零调用消费的同时，本地模型的重执行照常发生 |

## 第三 intake（外部轮次，无结算）——读数

| # | 步骤 | 读数 |
|---|---|---|
| 1 | `ext-turn`（sink 同函数组：recordExternalTurn/Response + verify） | chat_messages +2（user/assistant，`turn_state=committed`、`source_kind=external`、`source_provider=qoder`、声明模型在档） |
| 2 | intake 自身账本增量 | **settlements Δ=0、execution_states Δ=0、settlement_consumptions Δ=0** —— "我们没执行过的调用没有执行状态"实测成立 |
| 3 | resolve（includeChat=1，同查询） | hits=2（外部轮次被检索命中）、新 demand `16eaf41d…`、reused=false |

## 结论

1. **cross-model reading 闭合**：一个从未在本机执行的模型调用，其结算结果经同一
   准入路径被零调用消费、值相等、consumer 标识全为新物。声明身份不参与消费资格
   的验证（provenance），消费判据对生产者身份不敏感——同时本地模型重执行不受影响。
2. **第三 intake 的无结算纪律实测成立**，且外部轮次 committed 后具备检索资格
   （检索结算是 resolve 自己写的，与 intake 无关——两件事在账本上分得开）。

## 装置教训（记入，供复现者避开）

- 首轮 `resolve` 未带 `--chat 1`（includeChat 缺省 false）→ 外部轮次零命中——
  是装置口径错误，不是检索资格缺失。已修并换新库重跑（旧库弃用）。
- MCP 端点免 initialize 握手，直接 tools/call 即可（生产载体探针验证）。
- `simigo_es_begin` 的 `reusable_answer` 恒 null 语义在装置里作为硬门断言。

## 本记录不主张的事

- n=1；第二 intake 的"外部 agent"由驱动模拟（真实云端 agent 的声明行为、
  幂等重试形态未测）。
- 第三 intake 只验 sink 落点函数组，未测采集器 transcript 解析（Qoder 格式
  解析→CandidateDelivery 的前置链路不在本轮）。
- 时延 contaminated（并行生产实例），不作区间引用。
- 消费 demand 为 exact-repeat、显式 opt-in；自动复用路径不在本轮。

## 复现

```
cd ~/Documents/Codex/2026-11-07/b1-i-1-i-1-2026/work/ES-IS-research
python3 -I tools/baseline/intake_driver.py --binary <SimiGo 二进制> \
  --model-snapshot <Qwen3 快照> --model-id mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit \
  --home /tmp/esis-intake/home --cache-root /tmp/esis-intake/cache \
  --graph-store /tmp/esis-intake/graph --db-path /tmp/esis-intake/home/simigo.sqlite3 \
  --contract-cli <turn-cli 路径> --out-dir runs/intake-trials-20261110 \
  --repo ~/Documents/SimiGo-new-root
```

`INTAKE-DONE` 前任何 `BASELINE-STOP` 都是硬停。
