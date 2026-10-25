# ES-T3 Gate B Results — Component Necessity Perturbation Matrix

> **ARCHIVED** 2026-10-20 · line: 通用治理 / 其他 · original: docs/00-governance/SIMIGO_LAB_EST3_GATEB_RESULTS_20260930.md
> Evidence status: unchanged (content frozen; moved only)


日期：2026-09-30  
状态：`GATE_B_COMPLETE / VERDICT = B-3 (ATTENTION NECESSARY, (1,3,8192) GROUP REPLACEABLE/UNUSED-IN-THIS-PATH) / AWAITING SECOND-LAYER`  
唯一问题：**GDN 与 Attention KV 中，是否存在某一组件是后续计算不可替代
的计算结果（或存在可安全丢弃/重算的一侧）？**  
执行：四 case 扰动副本（header/数据层手术，b0 字节一致/b1 摘除
(1,3,8192) 组/b2 摘除 (1,2,31712,256) 组/b3 零化 (1,3,8192) 组），
统一 probe（「继续执行。」greedy 32）逐 case loadSessionCache+generate；
零 durable 写入（204 前后核验）；观测已落库。

## 1. 矩阵结果（实测逐字）

| Case | load | continuation position | 下一 token | 与 B0 一致性 |
|---|---|---|---|---|
| B0 完整 | OK（position 17） | 17 | 55 字符：「你是想继续查看其他目录吗？…」（≡PB1 O1） | baseline |
| B1 摘除 (1,3,8192) 组 | **FAIL**：`KVCacheError "Corrupt prompt cache: cache 0 has non-contiguous array indices"` | 未建立 | 未产生 | N/A |
| B2 摘除 (1,2,31712,256) 组 | OK（position 17） | 17 | **0 字符（空响应）** | **DIFFERS** |
| B3 零化 (1,3,8192) 内容 | OK（position 17） | 17 | 55 字符，**与 B0 逐字相同** | **IDENTICAL** |

## 2. 裁定（按预注册锁定判定）

```text
B-1 双组件均必要        = PARTIAL REJECTED：attention KV 必要（B2 空响应）；
                          (1,3,8192) 组内容不必要（B3 恒等）
B-2 GDN 必要/ATT 可替   = REJECTED（B2 证明 attention 必要；B3 证明
                          (1,3,8192) 内容零贡献）
B-3 ATT 必要/(1,3,8192) 可替代 = CONFIRMED
  —— attention KV 是 computation-critical 组件（B2 摧毁 continuation）；
  —— (1,3,8192) 组内容对本次 continuation 零影响（B3 恒等）
B-4 双方可缺失/重建     = PARTIAL：(1,3,8192) 组可零化（B3）；attention
  KV 可由 transcript 重算（R2n 先证）但重算后是否等价未测（Gate D 域）
```

## 3. B3 异常（本 gate 最重要发现）——两候选解释，均未证

b3 把 30 个 (1,3,8192) 张量**全部零化**（30 个线性层的递归态内容归零、
结构完整），continuation 却与完整基线**逐字一致**。两种解释：

```text
解释 (a)【restore 缺失路径】：loadPromptCacheSnapshot→ChatSession 的
  恢复链可能根本未将 LMOutput.State 的线性层分量挂载到 MambaCache
  ——线性层 cache 全部以 fresh 状态参与本轮及此前所有 probe
  （含 Phase B/PB1）⇒ (1,3,8192) 组是 write-only 工件
解释 (b)【forward 不敏感】：分量被挂载但该 probe 的 continuation
  对其零化不敏感
```

两解释均可检验（vendor 恢复链源码追踪 / 更长 probe 差分），归下一
gate。**无论何者成立，operative continuation carrier 的定位都收敛到
attention KV（位置比例分量）——fixed-size (1,3,8192) 组在本配置下
不是 operative carrier。**

附带：b1 的 load 失败错误（non-contiguous array indices）本身证明
loader 对 (1,3,8192) 组的【结构性】校验存在（摘除即拒），而【内容】
零化无影响（b3）——结构必要性与内容必要性在该组上分离。

## 4. 三层框架的更新（Gate G 三层 → 运行时实证）

```text
知识（transcript）           → durable ✓（E0）；驱动 H→R' ✓（R2n）
计算状态（attention KV 位置比例分量）→ durable ✓、operative ✓（B2 反证）
可执行状态的另一半（线性层分量）→ durable ✓ 但 operative ✗（B3 恒等）
固定尺寸 (1,3,8192) 组       → write-only / 结构性必要、内容性不必要
```

## 5. Non-claims

```text
✔ 结论限于本样本（5401315f/Qwen3-Next/Nail）+ 本 probe + greedy
✔ 「(1,3,8192) 内容零影响」= 本次 continuation 的观测；非「该组无用」
  普适判定（候选解释 a/b 未裁决）
✔ 未做 Gate C/D；未引入完整 History；真实 store 204 核验不变
✔ B1 load 失败错误原文已记录（non-contiguous indices）——结构校验证据
```
