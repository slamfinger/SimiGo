# E1/E2 组成性、载体独立性、intake paired trials（2026-11-10）

本目录保存 2026-11-10 针对论文 `PAPER_S6_DRAFT_V0.1_20261108` 自报缺口所做的四臂实验：
记录正文、驱动与装置源码、账本。证据库（`*.sqlite3`）与构建产物不入仓，靠账本与哈希定位。

状态：**已执行**（单次运行，n=1）。本目录不复制结论以外的内容，读数以记录正文为准。

## 四份记录

| 记录 | 臂 | 主读数 | 论文落点 |
|---|---|---|---|
| [载体独立性真验收](records/EXPERIMENT_CARRIER_INDEPENDENCE_V0.1_20261110.md) | A | SIGKILL → 冷启动 → 消费：`consumed / model_calls=0 / 值相等 / 双新物`；控制臂 134 chunks | §6.7「同一进程内取得消费证据」缺口闭合 |
| [intake paired trials](records/EXPERIMENT_INTAKE_TRIALS_V0.1_20261110.md) | B | 第二 intake 声明外部身份、产品零调用、被零调用消费；第三 intake `settlements/states/consumptions Δ=0`，resolve 命中 2 | §6.7 cross-model reading 缺口闭合 |
| [图会不会长 + 锚点重算](records/READINGS_GRAPH_AND_ANCHORS_20261110.md) | C / D | 边 143 → 189（information-demand 161 / citation 21 / settlement-consumption 7），密度 ≈2.8%；9 个 file:line 锚点 8 个语义成立、1 个文件更名 | 支撑「图在长」；锚点基线 `29217b0` |
| [E1/E2 产品路径重跑](records/EXPERIMENT_E1E2_PRODUCT_PATH_V0.1_20261110.md) | E1/E2 | `E1=epsilon / EDGES=2 / POS=fired / E2=gamma / SHARED_BOOKS=none` | 修掉 run-b 的 BLIND（stage 路径 edges=0） |

## 证据完整性（2026-11-10 核对）

- 载体实验二进制：`sha256 4398b5aa15a24261d28057dd64ddec90fb2d960018846f56089d182007d85fc5`，与 `ledgers/carrier/manifest.json` 一致。
  原在 `~/Library/Developer/Xcode/DerivedData/SimiGo-ekwkooivsotoisflwmxlxxlxswom/...`（该目录 2026-11-10 整体清空）。
  **已留档**：`~/Documents/SimiGo-archive-20261105/evidence-binaries/carrier-4398b5aa/SimiGo.app`（121 M，副本哈希复核一致，见该目录 README）。
  重建同基线源码不保证同哈希，这份副本是唯一的同哈希实例。
- 实验库：`runs/*/simigo.sqlite3` 未入仓，账本逐行含步骤与读数，可回查。
- 账本与 manifest 里的本机绝对路径已按仓规脱敏为 `~`（只替换路径前缀，未动任何读数、时间戳或哈希字段）。
  因此仓内账本文件的 sha256 与记录正文里写的原件哈希不同；原件哈希见各记录头部的账本行。

## 目录

```
records/                 四份记录正文
rig/compose_probe/       E1/E2 装置：预注册仪器 compose_probe.py + 产品路径驱动 + turn-cli 包
rig/baseline/            A/B 驱动：baseline_driver.py / carrier_driver.py / intake_driver.py + contract CLI
ledgers/                 compose_probe 账本、carrier/intake 的 ledger/summary/manifest/load 账
```

## 复现

装置按原样从 `work/` 拷入，路径参数化；**不要**改 `compose_probe.py` 的 Probe/classify 语义——
那是预注册仪器，改了就换了一份实验。

```
# E1/E2（无模型）
cd rig/compose_probe/product_rig && swift build
cd .. && python3 -I compose_probe.py --self-check          # 期望 SELFCHECK PASS
python3 -I compose_probe_product.py --cli product_rig/.build/debug/turn-cli

# A / B（需模型与产品二进制，见各自记录「复现」节）
python3 -I rig/baseline/carrier_driver.py ... --out-dir <新目录> --repo <产品仓>
python3 -I rig/baseline/intake_driver.py  ...
```

断言即判据：分类器给 `BLIND`/`void`、驱动给 `BASELINE-STOP` 时是装置红灯，不是产品读数。

## 本目录不主张的事

- 全部臂 **n=1**（单结算、单轮消费、单 intake），不构成样本，不与 11 对行为试验或 P2 Run A 读数合并。
- 时延读数全部 `contaminated`（并行生产实例，用户 2026-11-10 裁定静默窗豁免）；`[READY]` 间隔是 HTTP 面就绪，不是权重驻留证明。
- 「KV 随进程释放」是进程死亡推论 + RSS 归零观测，未做逐层 KV 内部取证；KV 绑定有 schema 载体（`settlement_bindings`），当时装置按表名过滤没读到行，见记录末尾勘误（2026-11-12）。
- 消费走的是 `exact-repeat` + 显式 opt-in 路径；**自动**答案复用不在本轮。
- 第二 intake 的「外部 agent」由驱动模拟，真实云端 agent 的声明与幂等重试形态未测；第三 intake 只验 sink 落点，未测 transcript 解析前置链路。
- C 是两时点差（11-09 vs 11-10），无逐时点采样；密度 2.8% 只证增长，不证拓扑化。
- D 只覆盖论文附录 9 个锚点，基线 `29217b0`；当前主线已前进（`1bff8c7`），引用前需重取行号。

## 仍未闭合

- 论文 §6.6 最后一处：**llama.cpp 双载体端到端**（wired 未 exercised）。
- P2 主链 Run B 仍 **NO-GO**（`docs/upstream/P2_CONFIG_RECORD_20261105.md` §5.28），本轮未重开。
- 本轮 3 次模型加载是否计入全实验上限，属治理裁定，未自行定案。

## 会漂的数

`information_items` / `dependency_edges` / `information_demands` / 结算三表都是活数。引用时必须带时刻或重取
（例：C 记录写 items 6738，同日上午实测已 6750）。
