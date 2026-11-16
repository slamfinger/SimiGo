# 待适配的 GGUF 续接测试设计（设计存档，**不在构建目标内**）

来源：两个一次性抢救目录，2026-11-10 核实后从其中取出唯一副本，原目录已删除。

| 文件 | 行数 | 原路径 | 覆盖 |
|---|---|---|---|
| `GGUFContinuationESISTests.swift` | 749 | `~/Documents/simigo-untracked-20261105/SimiGoTests/` | GGUF 续接路径 I2–I5 的无模型回归（真 store + 真 GGUF 结算适配器） |
| `GGUFContinuationD6InvalidationTests.swift` | 577 | 同上 | D6：上游 KV 被主动失效后，下一轮从已结算的 IS 记录恢复 |
| `GGUFContinuationE1RealModelE2ETests.swift` | 373 | 同上 | E1：引擎进程死亡，SimiGo 与 ES/IS 权威存活 |
| `GGUFContinuationE2CrossProcessTests.swift` | 448 | 同上 | E2：两轮之间 SimiGo 自身重启 |
| `GGUFBranchLedgerTests.swift` | 335 | `~/SimiGo-pre-rewrite-archive-20261105/untracked-rescue-20261105/main/SimiGoTests/` | Phase 1 逻辑 ES 连续性：账本与运行时面（fork 点、转写副本、拒绝路径、不声称共享 KV/prefill） |
| `GGUFBranchContinuityRealModelE2ETests.swift` | 566 | 同上 | Phase 1 真 llama.cpp 引擎上的连续性（stub 只能证明接线） |

## 为什么放在这里而不是测试目标

这六个文件**对当前 API 不成立**：`SlotActivity` 已并入 `ManagedGGUFRuntime+SlotActivity.swift`，
契约类型统一去掉了 `SimiGo` 前缀，`BranchGenerationGuardUnsupported` 等符号已不存在。
直接加入 `SimiGoTests` 会让构建失败。它们现在的价值是**设计意图的代码形态**，不是可执行测试。

同样从抢救目录里剔除、未收进本目录的（已核实为仓库超集或已失效）：

- `SimiGo/Model/GGUFModelIdentity.swift` + 其测试 —— 仓库已有（#131 合并）
- `SlotActivity.swift` / `ManagedGGUFRuntime+SlotActivity.swift` / `SlotActivityTests.swift` —— 仓库版本更新（11-09）
- `MLXDeleteFailClosedTests.swift` —— 依赖符号已不存在，其意图由 `BranchLifecycleError.branchUnknown` 承担

## 与已执行实验的关系

- E1/E2 的**意图**（进程死亡后从 IS 恢复、跨进程交接）已由本目录上一层的载体独立性实验
  （SIGKILL → 冷启动 → 零调用消费）以更直接的形式覆盖；这里是**测试形态**的原始设计，非证据。
- D6（KV 主动失效 / sleep-wake / RAM cache absent / runtime restart）与两个 Branch Phase 1 文件
  **没有任何已执行实验或文档替代**。

## 使用规矩

- 不得加入任何构建目标；不得把这些文件的存在读成"该能力已测"。
- 若要复活：按当前 API 逐个适配、单独开分支、跑通才算数；不要整文件复制。
- 本目录不构成任何读数的证据链。

## 2026-11-16 更新（owner 裁定：D6 一件同步，见 `ANOMALY_LEDGER_V0.1_20261116.md` A-10）

本目录的 `GGUFContinuationD6InvalidationTests.swift` **已与活体件逐字节同步**；其余五件未动。

- **正本 = 活体件** `SimiGoTests/GGUFContinuationD6InvalidationTests.swift`（646 行，sha256 `50a12605…`，
  在 HEAD 测试目标内，env 门 `SIMIGO_GGUF_E2E_MODEL` / `SIMIGO_GGUF_E2E_BIN`）。本目录那一份是**镜像**。
- 同步前本目录副本 = 577 行 sha256 `44a54fff…`（即上表 D6 行记的值），与活体件差 346 行变更
  （`diff | grep -c '^[<>]'` = 346；`diff | wc -l` = 460）。**照它复现会得到另一件测试**，这正是要同步的原因。
- 同步前的 577 行**可取回**：`git show 893dab6:docs/experiments/ESIS_GAP_CLOSURE_20261110/pending-tests/GGUFContinuationD6InvalidationTests.swift`
  （该件自 `893dab6`（11-10）入仓后到本次同步前未再改动，HEAD 版与之同 sha256）。

三条连带更正（按「不回改原文、只加 dated 段」，上面各行原样保留）：

1. 上表 D6 行的 **577 是同步前的历史值**；现值以 `wc -l` 现取为准。
2. 「D6 …**没有任何已执行实验或文档替代**」这句**已过期**：D6 现有已执行记录
   `docs/experiments/GGUF_D6_KV_INVALIDATION_20261110/README.md`（11-10 四臂真机 `Executed 4, 0 failures`）
   与 `ES-IS-research/docs/research/REAL_MACHINE_GGUF_ARM_20261116.md`（11-16 run2：19 executed / 0 skipped /
   0 failures，D6 四臂 4/4，被测二进制含 R-16/R-17），且活体件在 HEAD 测试目标内可跑。
3. 其余五件仍是「对当前 API 不成立」的设计存档，本 README 的「为什么放在这里」「使用规矩」两节对它们**原样有效**；
   镜像件同样**不得加入构建目标**（它与活体件内容相同，构建只认 `SimiGoTests/` 那一份）。

**同步没有消除漂移风险，只是把它归零了一次**：活体件再改，镜像就会再次落后。漂移检查（两值应相等）：

```sh
shasum -a 256 SimiGoTests/GGUFContinuationD6InvalidationTests.swift \
  docs/experiments/ESIS_GAP_CLOSURE_20261110/pending-tests/GGUFContinuationD6InvalidationTests.swift
```

R-E（归档副本不得代替活体件）继续适用：复现请跑活体件，不要跑镜像。
