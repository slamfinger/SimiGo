# E1/E2 组成性探针：产品路径重跑实测 V0.1

日期：2026-11-10
装置：`work/compose_probe/product_rig/`（临时包，SHA256 main.swift `4c3d5aa6…`、二进制 `9f396393…`）
驱动：`work/compose_probe/compose_probe_product.py`（复用预注册仪器 `compose_probe.py` 的
Probe / facts / classify，零语义改动；预注册自检 `SELFCHECK PASS`，2026-11-10 复跑）
账本：`work/compose_probe/ledger-run-product-20261110.jsonl`（SHA256 `0d765991…`）
证据快照：`work/compose_probe/run-product-20261110/`（s0/s1/s2.sqlite + 两根，s0 `85be3464…`）
产品基线：SimiGo-new-root HEAD `11a5061`（工作树 dirty 仅 SimiGoCollection 采集线 4 文件 +
open-problems README，均与本装置依赖的 SimiGoRuntime 无关）；契约类型已去 `SimiGo` 前缀，
装置以 typealias 适配，v2 CLI 原文未改语义。

## 为什么重跑

run-b（2026-11-08，stage CLI）读数：E1=epsilon、facts.edges=0 → POS=BLIND → E2=void。
stage 路径不写依赖边与文件绑定，撤回机制在那里不可测；那条账本作为仪器阴性对照保留，
不作为产品读数引用。本重跑把每个权威的诞生换成产品生成路径的真实组成：

```
settleWorkRootContents（根索引，产品"文件变了"唯一入口）
→ SimiGoInformationLoop.resolve（检索结算 + settlement_bindings.source_file_id）
→ SimiGoInformationLoop.settleTurn（模型结算 + advancement 依赖边 information-demand）
```

与 HTTP 生成路径同一组函数，无手工装配。准入读数走 `ISAdmission.admit`
（get-value），拒绝是读数不是崩溃。

## 步骤与读数

场景：三空间（S0/S1/S2 三个独立 sqlite）；共享根 R=`doc.txt`（"alpha V1"）、控制根 R2=`other.txt`（"gamma C1"）。
查询词与文件内容有意重叠（P1 教训：无命中路径不写绑定，撤回不可测）。

| # | 步骤 | 读数 |
|---|---|---|
| 1 | e1.stage_A：S0 turn(request=req-e1, a1, ANSWER-A) | demand `6c9ac3bb…`，hits=1，绑定 3（content+双 producer），依赖边 1 |
| 2 | e1.state_a | admitted，ANSWER-A |
| 3 | e1.stage_B：S0 turn(同 request，a2, ANSWER-B) | demand **`8bac368e…`（不同于 1）**，resolveReused=false，又一组绑定+边 |
| 4 | e1.state_b | admitted，ANSWER-B |
| 5 | setup.s1 / s1c / s2 | S1：a1（共享根）+a3（控制根）；S2：a2（共享根）；pre 读数全放行 |
| 6 | facts(S1) | **edges=2**（run-b 为 0），bindings=6，binding_names 含 content |
| 7 | 改控制文件 → pos.scan_control | changed=1，**invalidatedSettlements=2**（检索+模型结算同被闭包失效） |
| 8 | pos.after_control_change(a3) | **rc=3 typed refusal `invalidated`** |
| 9 | pos.scope_kept(a1) | **仍 admitted ANSWER-A（撤回分区）** |
| 10 | 改共享文件 → e2.scan_s1 | changed=1，invalidatedSettlements=2 |
| 11 | e2.s1_after(a1) | **rc=3 `invalidated`（被观测者拒）** |
| 12 | e2.s2_after(a2，S2 未 scan) | **仍 admitted ANSWER-B（旁观者服务旧值）** |
| 13 | e2.scan_s2 → e2.s2_rescan(a2) | S2 自己 scan（changed=1，失效 2）→ **rc=3 `invalidated`** |
| 14 | 移走共享文件 → e2b.scan_s1/s2 | 各 removed=1；S1/S2 读数均 rc=3 `invalidated` |

分类器输出（预注册词表，未改语义）：

```
E1:  epsilon——两判定并存，选择权在调用方（无冲突表示）
EDGES: 2
POS: fired——控制臂拒绝且未变更臂仍服务（撤回真被观测到且分区）
E2:  gamma——不对称：被观测者拒，旁观者仍服务旧值
SHARED_BOOKS: none
```

## 结论

1. **run-b 的 BLIND 缺陷被修复**：产品路径写真实边与绑定（edges=2 vs 0），阳性对照
   以预期形态响起（POS=fired），E2 读数可解释。
2. **E2 = gamma + 重算补全**：撤回在 S1 被观测（依赖闭包 → scan 失效 → typed refusal），
   S2 在自己 scan 前仍服务旧值。**跨空间撤回靠重算抵达，不靠边传播**——两空间无任何
   共享写入（SHARED_BOOKS=none；两个读数步 delta 全空，admission 读路径零写入，
   与 RefusalSideEffectTests 的 fail-closed 断言一致）。
3. **撤回的边机制在空间内**：scan 的失效闭包把检索结算与模型结算**一起**判 invalid
   （invalidatedSettlements=2），准入读的是账面 validity（ISAdmission 第 4 步），所以
   拒绝原因一律是 `invalidated`（行本身失效），而非 dependency-invalid——闭包传播
   发生在 scan（写时），不在 admit（读时）。
4. **E1 的产品路径机制与 stage 不同，分类同类（epsilon）**：预注册四类里"同一 demand
   两个权威"在产品路径**不可构造**——demand 基面含 `citableSettlementSummaries`
   （已结算结论本身是信息），第一个权威结算时写的 summary 使第二个同 request 提交
   的基面变大 → 新 demand。两个权威各自成立、都可读、无冲突表示（epsilon 成立），
   但它们从不共享一个 demand：**权威的诞生会改变下一个提交的问题身份**。验证：
   S0 两 demand 均 ADVANCED，A 的 summary（正文 `ANSWER-A`）先于 B 的 resolve 在库。
5. **P1 读数再现**：同 query 不同 request（S1/S2）得到不同 demand、合法结算独立，
   文件层内容对象去重共享；同 request 在"世界未变"时才会复用（本次因基面加入
   summary 而未复用——复用条件是世界未变，不是请求字面相同）。

## 本记录不主张的事

- **单次运行、单机、无模型**：n=1，装置为确定性 CLI 路径；不构成样本，不与 11 对
  行为试验合并。
- 不主张"所有结算都进 demand 基面"：只核实了 settlement summary 一类（file 行与
  chat 由同一 canonical 组成，本轮未单独变异）。
- 不主张跨空间边传播不存在的设计是缺陷或优点：gamma 是读数，不是评判。
- `external_files` 在 rename 后净 +1（旧行未删、新行 `doc.txt.away` 另立）：删除
  策略未溯源，只照抄读数。
- e2b scan 的 invalidatedSettlements=2 是受影响闭包计数（结算早已 invalid，幂等守卫
  下无新 validity 事件——delta 无 settlement_validity_events 行）；不把它读成二次失效。
- 装置头部注释"显式 --request 相同 ⇒ 同一 demand"**已被本轮读数否定**（结论 4），
  注释保留原文供审计，以本节为准。

## 复现

```
cd ~/Documents/Codex/2026-11-07/b1-i-1-i-1-2026/work/compose_probe/product_rig && swift build
cd .. && python3 -I compose_probe.py --self-check          # 预注册仪器 SELFCHECK PASS
python3 -I compose_probe_product.py --cli product_rig/.build/debug/turn-cli
```

断言即分类器：POS 未 fired / E2 不得以预期形态响起时分类器给出 BLIND·void，
那是装置红灯，不是产品读数。
