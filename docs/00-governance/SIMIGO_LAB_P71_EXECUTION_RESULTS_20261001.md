# P7-1 Execution Results — Cross-backend fork/restore/continue

日期：2026-10-01
状态：`EXECUTED / MECHANICAL VERDICT: CONTINUATION_VALIDATED_CROSSBACKEND
（五 cell 全 PASS）/ AWAITING HUMAN SECOND LAYER`
任务令：human 2026-10-01（授权执行 P7-1 @ 9319b40；严格按预注册，
判据/cell/失败路由零修改；执行目标=忠实执行冻结判据，让结果决定
Claim F 下一状态，不提前给解释性结论）
上游：P7-0 冻结（4fbefaa）+ P7-1 设计预注册（9319b40）

---

## 1. 执行记录（5 个独立 xcodebuild 进程，19:17–19:22 +0800）

| # | invocation | runUUID | 时长 |
|---|---|---|---|
| 1 | PhaseAForm | audit-20261001-5340FE99 | 26.6s（含 GGUF 全字节 SHA256） |
| 2 | PhaseBFork | audit-20261001-67D87B20 | 28.1s（含 GGUF 重哈希核对） |
| 3 | PhaseCRestore | audit-20261001-95E010A2 | 24.5s（含 GGUF 重哈希核对） |
| 4 | PhaseDPollution | audit-20261001-6BEE5FAE | 5.2s |
| 5 | Adjudicate | audit-20261001-EC02BCE8 | 0.07s |

- 执行前置：llama-server 由本战役启动于 127.0.0.1:8080（binary
  `/Users/mr.simi/.simigo/bin/llama-server`，GGUF snapshot d835c87a，
  ~15s 就绪）
- 全部目录 git=dc12a0c + dirty=True（harness 未提交，既定纪律）；
  events.jsonl 单调钟全真；r0_verify 五目录全 PASS
- **执行过程记录（诚实登记）**：首次运行在**编译阶段**即失败
  （`ExecutionID` 在产品仓遥测定义与 SimiGoRuntimeContract 契约定义
  之间歧义）——属 harness 构建期修正（typealias 消歧），发生在任何
  实验数据产生之前，冻结设计零改动；不构成 implementation failure
  运行记录，按规则 10 透明登记

## 2. M1 — Model Identity Binding（I 关系）

```text
checkpoint v2 modelIdentity：
  modelPath = …/Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf
  modelHash = 0bbcf3cc9be4c976bad20e641baf629d…（GGUF 全字节 SHA256）
J-I1（modelPath 相等）：fork PASS / restore PASS（restore 前强制核对）
J-I2（modelHash 重算相等）：fork PASS / restore PASS
⇒ 按冻结规则 §2.2：I 关系升格 = NATIVE-EXPRESSED（结果陈述）
```

## 3. M2 — Fork / Divergence（A 关系）+ 全 cell 判读

| Cell | 判据 | 结果 |
|---|---|---|
| C1 Identity | J-I1/J-I2（fork+restore 双程） | **PASS** |
| C2 Position | J-P1 restore pos==checkpoint pos（且 prefix 计数恒等）；J-P2 两支 append 精确落地（pos+1 且 prefix+\|Δ\| tokens） | **PASS** |
| C3 Anchor | J-A1 **anchor(child@fork)==anchor(parent@fork)==anchorHash_A0**；J-A2 分叉为真；J-A3 functional | **PASS** |
| C4 Continuation | J-C1 prefix_is_extension；J-C2 位置前进；J-C3 无 cold fallback；J-C4 锚定（containsAny 实体表） | **PASS** |
| C5 Parent non-pollution | J-PN1 重放逐字相同；J-PN2 parent payload SHA 恒等 | **PASS** |

机械判读（audit-20261001-EC02BCE8/judgment.json）：
**overall = CONTINUATION_VALIDATED_CROSSBACKEND**。

锚定输出样例（J-C4）：

```text
restore 后续算（ΔR = "What was this folder for again?"）输出：
"The folder is called \"ReferenceFiles\" and it contains project
 management documents." …
```

## 4. 判定（严格按 P7-0 §6 / P7-1 §6 措辞）

> **MLX 与 llama.cpp 均能以各自 backend-native representation 表达
> 同一 candidate relation closure，并在 restore 后保持相同的
> continuation invariant。**

- Claim F 状态：由 **NOT YET** 进入 **bounded cross-backend claim
  （有实验支持）**——边界保留：两个 backend ≠ 所有 backend；llama
  侧=token-prefix 表达+服务端 KV（usage 遥测未进判据）；本实验不
  使用、也不允许使用「backend-independent」裸表述
- I 关系：PARTIAL → NATIVE-EXPRESSED（M1 补齐后实测通过）
- A 关系：DIFFERENT-FORM → 实验上可判定且判定成立（fork anchor
  相等 + 分叉真实 + parent 不被污染）
- 失败三分：本轮零 implementation failure 运行、零 mapping failure
  （M1/M2 补齐即通过）、零 closure failure

## 5. 边界与诚实登记

- J-P2 操作化注记：契约 position=continuation 计数（P7-R2-A 力学），
  冻结式「pos==N+|Δ|」在实现中同时落在两处——position 恰 +1/
  continuation 且 prefix 恰 +|Δ| tokens（两读法均 PASS，无歧义残留）
- GGUF 全字节哈希在 A/B/C 三程独立计算（21GB×3），成本换真实性
- S₀/ΔP/ΔC/ΔR 为英文短会话（P7-R2-A 冻结常量沿用）；Token 级
  anchor 的 MLX 侧对应物为 transcript 级 anchorHex——同功能不同形
  （P7-0 已钉，不构成新的等值宣称）
- 产品仓零 commit（HEAD dc12a0c，harness 工作区未提交 + 执行时
  归档 Lab 仓）
- 编译期消歧（ExecutionID）如实登记于 §1

## 6. 产物索引

- 工件：`docs/02-evidence/p71-crossbackend-20261001/audit-*/`
  （5 目录全量：metadata/events.jsonl/r0_verify/summary/judgment）
- Harness 源：`docs/02-evidence/p71-crossbackend-20261001/harness/`
- 工作区：`/tmp/simigo-p7-1/`（checkpoint v2 三件在本机）

**终判待 human second layer。本结果文档不使用预注册边界外的任何
结论性措辞。**
