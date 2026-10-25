# ES-R2 Gate B Results — State Survival

> **ARCHIVED** 2026-10-20 · line: 通用治理 / 其他 · original: docs/00-governance/SIMIGO_LAB_ESR2_GATE_B_RESULTS_20260930.md
> Evidence status: unchanged (content frozen; moved only)


日期：2026-09-30  
状态：`GATE_B_COMPLETE / STATE-SURVIVES CONFIRMED / GATES C-D LOCKED（待授权）`  
唯一问题：**Representation 消失 + 进程死亡后，Tier-1 State（{storageKey,
position: 17, continuation-anchor: tail(17)}）是否作为独立 authoritative
information 存活——而非从 P 或完整 History 重新推导？**  
执行：双真实进程（SideA 6.5s：restore 活态（P+H）→ formation boundary
形成 Tier-1 carrier（严格三标量，排除 history 内容/modelId/generation/
SHA/P 引用）→ 写入 Gate B 空间 → P-loss 布置（meta+carrier，无
safetensors）→ 退出；SideB 0.002s 全新进程：仅凭 carrier 检验）  
观测：`gateB-observations.jsonl`（已落库）；真实 store 204 项未动

## 1. 实测记录（SideB，全新进程，P-loss 空间）

```text
空间内容        = meta.json + state-carrier.json（无任何 .safetensors
                  ——P loss 为真，断言校验通过）
identity        = default/5401315f-faa7-4984-9639-fccef06ae188/main
                  → SURVIVED（与进程 A formation record 逐字匹配；
                  非重建、非派生）
position        = 17 → SURVIVED as authoritative assertion
                  （直接读自 carrier 字段；未 reload P、未重数 history）
anchor          = afterMessageIndex=17, tailSHA256=825ec6e1…
                  → SURVIVED as authoritative assertion（无 transcript
                  在手即可读出）
consistency     = carrier anchor == 幸存 transcript 尾哈希
                  （一致性标注——authority 仍在 carrier，meta 只是
                  相互印证的剩余载荷）
model 兼容       = 由 meta.json（剩余载荷）携带——不属 Tier-1 carrier
```

## 2. 裁定

```text
STATE-SURVIVES CONFIRMED（对应预注册链：R2-A 已由 Gate A 裁定 +
  本 gate 确认存活层）
⇒ Tier-1 State（{identity, position, continuation-anchor} 三标量）
  以独立 authoritative 记录的形式，跨 Representation loss + 进程死亡
  存活——验证过程零 P reload、零 history 重读、零 runtime 上下文。
```

**H-B1/H-B2 的实证推进**：ES-R1 终审遗留的 H-B1/H-B2 不可区分问题，
在本 gate 的受控条件下被打破——**当一个 formation boundary 真正捕获
三标量时，产生的记录确实具有独立于 P 与 runtime 的生命周期**
（H-B1 在「形成被显式执行」的前提下成立）；而部署 corpus 从未形成该
carrier（Gate D）的事实不变——即 H-B2 描述的是「未显式形成」的现状，
两者不再矛盾：**capability 存在（本 gate），formation 未发生（Gate D）**。

## 3. Tier-1/Tier-2 边界的实证可见性

SideB 同时暴露了 Tier-1 的精确边界（不做价值判断）：

```text
carrier 能断言 continuation（"after 17, tail=825ec6e1…"），
但断言的【验证】与【执行】仍需上下文（transcript 或表示）——
检查 anchor 时我们对 meta 尾做了一次一致性印证（authority 仍在
carrier，meta 仅为互证）；而「从 anchor 出发继续计算」需要 Tier-2
压缩载体（Gate A：观察宇宙内不存在）。
⇒ State 存在性（Gate B ✓）与 State 可操作性（Gate C 待解）的边界
  第一次被运行时实验同时可见。
```

## 4. Control 引用（不重跑）

```text
无 State carrier 的对照路径 = E1-R1（restore 缺 P fail-closed ×3）+
R2n（meta.history → cold reconstruction 语义有效）——系统行为已登记。
本轮零重复执行。
```

## 5. Non-claims

```text
✔ carrier 三标量极简（10 项排除清单全程遵守：无 history 内容/modelId/
  generation/SHA/P 引用/新 reader/C-4/性能/跨 backend）
✔ SURVIVED 指记录作为独立权威断言存活；其【执行】能力不在本 gate
  范围（Gate C/D 锁定待授权）
✔ 单样本；真实 store 204 项核验不变
```
