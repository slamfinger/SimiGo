# ES-R1 Phase C Results — Representation Loss Boundary & Seam Discovery

日期：2026-09-30  
状态：`PHASE_C_COMPLETE / R1-B CANDIDATE FROZEN / C-4 NOT EXECUTED（human 裁定）`  
裁定依据：human Phase C 裁定（C-0 冻结 / C-1 边界 / C-3 discovery；C-2 禁止；
C-4 暂缓；无 seam 则冻结 R1-B candidate + first missing seam，不得自行补）  
快照：`/tmp/simigo-palace1-e1/esr1/c0-c1-snapshot.json`；真实 `~/.simigo`
READ-ONLY（204 项未动）

## C-0 — Fixture freeze（integrity snapshot）

```text
execution_identity = default/5401315f-faa7-4984-9639-fccef06ae188/main
lineage            = forkPoint ABSENT；durable lineage = storageKey 寻址
                     （product lineage records = 进程内 O 层）
logical position   = 17（history.count 代理，A2）
history            = 17 条，canonical SHA 已冻结
representation     = cacheSHA256(5ce9dcb…) + generation(c1185f0a…)
environment        = 产品 dc12a0c / Lab（本 commit 时点）/ Nail-Qwen3.6
checkpoint/prefix  = 真实 store 204 项；池 24 对（含本会话 17/17 快照，
                     E2 发现——登记为隐蔽表示）
```

## C-1 — Representation Loss Boundary

```text
before : safetensors(713,859,116 B) + meta.json(43,641 B)
removed: safetensors（副本内）
kept   : meta.json——removal 后 SHA 与冻结值一致（完整性验证通过）
remaining（fixture 内）: identity/history/generation/modelId 全在 meta
```

### C1.1 隐蔽表示登记（防「假删除」）

```text
H-1  真实 ~/.simigo/branch-checkpoints/…safetensors（原始件，fixture 外，
     READ-ONLY）——任何指向真实 store 的 runtime 调用都会找到它
H-2  真实 ~/.simigo/prefix-pool think:1 命名空间 17/17 快照（E2 发现，
     fixture 外）——pool-enabled 运行会从这里恢复
H-3  E1 mutation 副本（同为无 safetensors，不构成隐藏表示）
排除机制（若未来 C-4 获批）：SIMIGO_PREFIX_POOL=0 排除 H-2；loader 指向
fixture 目录排除 H-1；fresh 实例排除 live session
```

## C-2 — 未执行（human 禁止；E1-R1 已覆盖该结果，无新信息）

## C-3 — State→Representation seam discovery（穷举结果）

全部表示生产/接收入口（product + Lab，file:line）：

| # | 入口 | 输入类别 | S→R'？ |
|---|---|---|---|
| 1 | NativeMLX:1653-1655 loadSessionCache | 既有 P（safetensors）→R | 否（P→R） |
| 2 | NativeMLX:737 pool-hit ChatSession | 既有 P（pool 快照）→R | 否（P→R） |
| 3 | NativeMLX:785 cold ChatSession(history:) | **完整 history 文本**→P（full prefill） | 否（history→P；即 R2 recovery path，human 判非 Reuse） |
| 4 | NativeMLX:1521/:1195 saveCache/export | live session（P）→P | 否（P→P） |
| 5 | Lab coordinator:186 → backend.deriveRepresentation | 父 Representation→child R | 否（P→P） |
| 6 | PrefixSnapshotStore:226 load | 既有 P（pool artifact） | 否（P→R） |
| 7 | MLXPrefixRecomputeExecutor / LLAMA executor | 既有 P（token prefix）→计算 | 否（P→compute） |

**判定：不存在任何「State（无 history）→ 新 Representation」入口。**
唯一的两类表示来源 = 既有 P 或完整 history 文本。

## First Missing Seam（按 human §12 格式）

```text
State identified        ✓ storageKey 寻址 + meta 语义载体在场（C-1 remaining）
position identified     ✓ history.count = 17（代理；无独立字段——A2）
lineage identified      ✓ storageKey root；forkPoint ABSENT（E0）
new binding             ✓ 结构性支持（Lab registry N-bindings；product 无
                          绑定对象——binding 即 live session 本身）
??? FIRST MISSING SEAM
   = 「state（不含 history 文本）→ 表示物化」入口不存在：
     系统中没有任何代码路径能从 {identity, position, continuation-marker}
     产生 R'——因为 per-token KV 的唯一来源是 history 文本（full prefill）
     或既有 P 本身；不存在独立的「continuation marker → 表示」压缩物
     （A3 已证：系统内无独立 continuation marker）
```

## R1-B Candidate 冻结（终判归 human；A-form vs B-form 证据分离）

**A-form 证据（State 独立存在 + 无消费 seam）**：

```text
✔ Lab 契约层存在 State 的抽象形状（handle 五字段，零 MLX，三 backend
  验证）——「State 应当独立于表示」在契约层有实例
✔ meta.json 携带 semantic continuation carrier（R2n/E3 实证），且在
  表示删除后完好（C-1）
✔ 无任何 S→R' 入口（C-3 穷举）——「Runtime 无法消费」成立
```

**B-form 证据（所谓 State 其实只有 history）**：

```text
✔ 产品层不存在 State object（ManagedSession 无 identity/position/
  continuation 字段——A2/A3）；continuation 唯一载体 = history 末端
  （delta 契约）；除 history 文本外无独立 continuation marker
✔ 表示的物理可重建性完全依赖 history 文本重处理（full prefill）——
  「不含 history 的 State」在产品层没有可操作的含义
```

**冻结陈述**：

```text
R1-B CANDIDATE（非终判）：在产品实现层，State 与 history 当前不可区分
（B-form 事实成立）；在契约抽象层，State 独立于 history 的形状存在但
无产品实例（A-form 形状成立）。A/B 的最终裁定 = 「position/continuation
marker 是否应当、以及如何成为表示物化的充分输入」——这是下一 gate 的
研究问题，不是本实验能单方裁决的事实。
```

## 产物对照（human §13）

```text
① FACT TRACE     = Phase A+B 文档（46058bf）+ 本文 §C-3
② REPRESENTATION_LOSS = 本文 C-0/C-1 + 快照 JSON
③ REUSE TRACE    = 未产出（C-4 未执行——无 seam 可执行）
④ GATE RESULT    = R1-B CANDIDATE（冻结；终判归 human）
```

## Non-claims

```text
✔ C-2 未执行；C-4 未执行；未自行补 seam；未加 API/StateStore/schema
✔ 真实 ~/.simigo READ-ONLY（204 未动）；fixture 操作全部可逆副本
✔ 未把 R1-B 写成终判；A/B-form 证据分离呈交
✔ structural gap（Contract 五元 vs ManagedSession 无五字段）登记为观察，
  不解释为架构错误（human 纪律）
```
