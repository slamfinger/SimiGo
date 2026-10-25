# P4 Sample-3 Replication Results（G-β）— 2026-10-01

日期：2026-10-01
状态：`EXECUTED / 判读as-produced FAIL → 按预注册映射改判 INCONCLUSIVE
（F-6 harness 判定逻辑-映射不一致已登记）/ 科学承载项 J1..J4+J6 全 PASS
（含全战役首次真换序 J4）/ AWAITING HUMAN SECOND LAYER`
任务令：human 2026-10-01（G-β：同 protocol、同判据、独立 sample，
禁新增变量）
性质：P4 注册协议在第二模型维度上的复制执行。零判据修改。

---

## 1. Sample-3 定义

- **模型维度独立样本**：Qwen3-Coder-30B-A3B-Instruct-4bit
  （@6e302ea6，注册 RUNTIME_POSITIVE_CONTROL）——与基模型
  Nail-Qwen3.6（GDN 混合注意力族）不同架构族（标准注意力 MoE）
- **冻结脚本（先冻结后形成）**：新主题「咖啡店开业准备」8 轮用户
  轮；实体集 {咖啡店, 磨豆机, 5月20日, 菜单, 试营业}；Δ 输入按
  S2 结构同构预注册（dA1 概括型/dA2 演化/dB1 抽取型/dB2 溯源）；
  全部冻结事件先于一切计算写入 events.jsonl
- 会话 `p4-sample3-9d2e41`；S₀′′ 由系统自身路径形成（pos 16）；
  greedy（temperature=0/maxTokens=128/tools=nil）；隔离配方同 P4

## 2. 执行（4 个独立 xcodebuild 进程，17:36–17:40 +0800）

| # | invocation | runUUID | 时长 |
|---|---|---|---|
| 1 | S3Form | audit-20261001-3F2D3BC1 | 36.3s |
| 2 | S3Run1（A 先） | audit-20261001-BD7E1260 | 95.6s |
| 3 | S3Run2（**B 先，真换序**） | audit-20261001-6728547C | 93.5s |
| 4 | S3Adjudicate | audit-20261001-906BBA17 | 0.08s |

## 3. 机械判读与 F-6 改判

### 3.1 as-produced（工件原样留存）

```text
J1_identity              PASS
J2_divergence            PASS
J3_anchoring             PASS
J4_order_independence    PASS（真换序）
J5_isolation_counts      PASS（204→204 / 2→2）
J5_isolation_content_sha CHANGED（pool 项；checkpoints 内容级 SAME）
J6_evolution             PASS
verdict（代码产出）       = FAIL   ← allSatisfy 把唯一非 PASS 项
                                   lump 成 FAIL
```

### 3.2 F-6 登记：判定逻辑与预注册映射不一致

harness 预注册头部明确「**J5 失败 ⇒ INCONCLUSIVE**」（J2/J3/J4/J6
失败才 ⇒ FAIL），且同 harness 的 judgment_note 自述 pool 内容变更
「recorded, not judged」——但判定代码的 `allSatisfy` 把唯一的
J5 内容见证非 PASS 项归入了 FAIL。**代码违反其自身预注册映射**。

### 3.3 按预注册映射的改判（非改判据——套用冻结规则）

变更分解（工件数据）：checkpoints 内容 SHA 前后恒等（**真零写入**）；
pool 内容变更 = F-2 已登记的常态 runtime shard 导出（本战役所有
运行窗口均有，含全部原跑）。唯一非 PASS 项属 J5 → 按冻结映射：

> **Sample-3 终判 = INCONCLUSIVE**
> （J1/J2/J3/J4/J6 全 PASS + J5 counts PASS + J5 内容见证变更
> 归 F-2 仪器语义；FAIL-as-produced 原样留存于
> audit-20261001-906BBA17/judgment.json）

## 4. 科学结果（全战役新事实）

1. **模型维度复制成功（承载项全过）**：在第二架构族上，J1 身份
   8/8、J2 发散、J3 锚定（A-t1 概括命中开业规划主题；B-t1 抽取出
   真实实体『咖啡机』『5月20日』）、J6 独立演化全部成立。
2. **全战役首次真换序 J4（F-5 修复落地）**：Run2 进程内 B 先 A 后，
   4 个分支轮输出跨独立进程**逐字恒等**——顺序置换独立性首次获得
   直接检验，且是在不同模型上。原 P4/P5-1 的 J4 读法限定为跨进程
   重复确定性（G-α F-5）。
3. 输出形态备注（描述性）：B-t1 抽取型输出为多实体列表（128 tokens
   顶格），与 S1/S2 的单词抽取形态不同——模型风格差异，J3 判据
   （containsAny 实体）不受影响。
4. P4 命题的模型维度 coverage gap **实质性收窄**：两样本类（同模型
   S1/S2′）之外，第三样本（异架构模型新会话）承载判据同判。

## 5. 边界与诚实登记

- 判读 as-produced FAIL 原样留存；改判依据=冻结映射+数据分解，
  全程在案可复核（F-6 为 harness 缺陷登记，非判据修改）
- J5 内容见证（递归哈希，F-3 修复后首次启用）把 F-2 常态导出从
  「计数不可见」变为「可见但已归因」——见证升级的实现代价如实
  登记
- 模型维度仍非普遍性证明（一个第二模型 ≠ 所有模型）；跨 backend
  （llama）不在本轮
- R0 六件套全 PASS；monotonic 全真；harness 源归档 Lab 仓

## 6. 产物索引

- 工件：`docs/02-evidence/p4-sample3-20261001/audit-*/`
- Harness：`docs/02-evidence/p4-sample3-20261001/harness/`
  （P4Sample3ReplicationAudit.swift）

**收束措辞（预注册框架内）**：Sample-3 在承载判据（J1..J4、J6）上
复制成功并将顺序独立性升级为真换序检验；终判按冻结 J5 映射记为
INCONCLUSIVE（仪器语义），不升格为 PASS。G-β 实质达成；终验收归
human。
