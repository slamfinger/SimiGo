# 载体独立性真验收 V0.1：SIGKILL → 冷启动 → 消费

日期：2026-11-10
装置：`tools/baseline/carrier_driver.py` v1（复用 baseline_driver 的 DB/http/退出对账；
自管 spawn，静默窗豁免见下）
运行产物：`runs/carrier-independence-20261110/`（ledger.jsonl / manifest.json /
summary.json / server-s1.log / server-s2.log / global_load_ledger.jsonl）
产品基线：HEAD `29217b0`（工作树净）；二进制 DerivedData Release，
sha256 `4398b5aa15a24261d28057dd64ddec90fb2d960018846f56089d182007d85fc5`
模型：`mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit`（快照 `6e302ea6…`），
加载 2 次（global_load_ledger seq 1/2，purpose=carrier-independence）
实验库：`/tmp/esis-carrier/home/simigo.sqlite3`（全新，生产库 sha 前后恒等）

## 为什么做

论文 §6.7 自报：现有消费证据（11 对 paired trials、E2E）都在**同一服务器进程**内
取得——"释放旧进程与 KV → 冷启动 → 消费"没有直接读数。本验收把"进程死"作为
显式事件插在 S0（真实生成结算）与 C 臂（消费）之间。

## 静默窗豁免（偏离声明，用户裁定 2026-11-10）

用户选择"保留实例并行跑"：生产 SimiGo 实例（IS 载体，PID 20844，闲置挂起态
RSS≈166MB、未挂大模型，用户确认）全程并行。隔离论证：独立 SIMIGO_HOME /
SIMIGO_CACHE_ROOT / 端口（8321）/ 实验库；生产库 sha256 前后对账恒等。
**后果标记**：全部时延读数记 contaminated=true，不作区间引用；结构断言
（consumed / model_calls=0 / 新物 / 值相等）不依赖时延，不受影响。

## 步骤与读数

| # | 步骤 | 读数 |
|---|---|---|
| 1 | 会话 1 spawn → [READY] → PUT roots + reconcile | root `work-000000004991ef4b`，首请求门 0.03s |
| 2 | S0 真实生成（chat，max_tokens 256） | 7.828s（contaminated），结算 `15BA56DE…` / state `chat-d7b43f19…` |
| 3 | 声明复用契约 | DECLARED |
| 4 | 载体在场证据 | RSS 1.83GB；`state/runtime.json`：backend=MLX Native、in_flight=1、RUNNING；**KV/carrier 绑定类表：schema 中不存在**（论文"零 KV 绑定"的现行形态：连表都没有） |
| 5 | **SIGKILL**（非优雅退出） | pid 44022 死亡、graceful=False、端口 8321 释放 |
| 6 | 会话 2 spawn（同一实验库，全新进程） | 新 pid 44049；[READY]；root 幂等重注册 |
| 7 | C 臂：显式消费杀前结算（allow_recompute=false） | **outcome=consumed、model_calls=0**、consumer ES `es-a557c956…` + 派生结算 `5CD75C36…`（DERIVED_CONSUMPTION，均相对杀前账本新物）、返回值经 get-value 准入读路径比对**相等**、耗时 0.022s |
| 8 | 回库补验消费账 | `settlement_consumptions` 1 行（source=15BA56DE、consumer_state=es-a557c956、**model_calls=0**）+ `dependency_edges` kind=`settlement-consumption` 1 行 |
| 9 | R 控制臂：冷启动服务器对不同 demand 真生成 | 134 chunks、answer_reuse 缺席（零调用不是服务器死） |
| 10 | 优雅退出 + 对账 | 生产库 sha 恒等、端口释放 |

## 结论

1. **冷启动消费成立**：结算跨进程死亡存活（SQLite 提交 + 对象存储），全新进程经
   同一准入路径零调用取回相等值，消费判据五件套（consumed / model_calls=0 /
   新 consumer ES / 新 DERIVED_CONSUMPTION 结算 / 消费账行+边）全部相对杀前
   账本为真。论文 §6.7 "release old process and KV → cold start → consumption"
   的缺口闭合。
2. **载体的形态读数**：载体在场的可观测面 = 进程 RSS + `state/runtime.json` 的
   backend/in_flight/lifecycle；KV 绑定在现行 schema 无对应表（不是零行，是
   零表——表述应从"零 KV 绑定行"收紧为"KV 绑定无 schema 载体"）。
3. **SIGKILL 是安全的死亡方式**：WAL 已提交帧在新进程打开时恢复，无手工修复。

## 本记录不主张的事

- **n=1**：单结算、单轮消费；不构成样本，不与 11 对试验合并。
- 时延全部 contaminated（并行生产实例 + 首请求惰性加载），[READY] 6s/3.5s 是
  HTTP 面就绪不是权重驻留的证明——权重在首请求时才进内存（S0 生成 7.8s 含加载）。
- "KV 随进程释放"是 OS 进程死亡的直接推论 + RSS 归零观测，未做逐层 KV 内部取证。
- 消费账行的 `new_consumption_rows=0` 是 v1 装置的跨表 rowid 比较器口径错误
  （已修：各表 rowid 序列独立，新物基线必须取本表杀前最大值）；修正读数以
  回库直查为准（上表第 8 行）。
- 消费的 demand 是 exact-repeat 类、C 臂显式 opt-in；自动答案复用路径不在本轮。

## 复现

```
cd ~/Documents/Codex/2026-11-07/b1-i-1-i-1-2026/work/ES-IS-research
python3 -I tools/baseline/carrier_driver.py --binary <SimiGo 二进制> \
  --model-snapshot <Qwen3 快照> --model-id mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit \
  --home /tmp/esis-carrier/home --cache-root /tmp/esis-carrier/cache \
  --graph-store /tmp/esis-carrier/graph --db-path /tmp/esis-carrier/home/simigo.sqlite3 \
  --work-dir /tmp/esis-carrier/work --contract-cli <turn-cli 路径> \
  --out-dir runs/carrier-independence-20261110 --repo ~/Documents/SimiGo-new-root
```

断言失败即实验失败；`CARRIER-DONE` 前任何 `BASELINE-STOP` 都是硬停。
