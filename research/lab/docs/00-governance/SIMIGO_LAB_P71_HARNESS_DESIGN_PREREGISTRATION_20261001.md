# P7-1 — Phase-2 Harness Design / Pre-registration（M1 + M2）

日期：2026-10-01
状态：`DESIGN FROZEN / PRE-REGISTERED / EXECUTION AWAITING SEPARATE
HUMAN AUTHORIZATION`
任务令：human 2026-10-01（授权进入设计门；设计只负责把「什么算
通过、什么算失败、失败属于哪一层、如何记录」在实验前冻结；
**M1/M2 设计阶段不得偷偷产生实验结论**；设计完成后仍需单独授权
才能执行）
上游：P7-0 冻结（4fbefaa）+ human 设计门输入（dc21426）
纪律：零执行、零产品仓变更、零结论。

---

## 1. 组件清单（全部已提交可用，零新建依赖）

```text
simigo2-experimental/Sources/SimiGo2Experimental/（Lab 仓，已提交）
  · LLAMAServerExecutionStateExecutor  props()/tokenizeText()/complete()
  · LLAMAServerExecutionStateBackend   boundPrefix()/captureRepresentation()/
                                       restoreRepresentation()
  · LLAMAServerPrefixPayload           token-prefix 载荷
  · （MLX 参照实现 MLXExecutionStateBackend 同包在案，Phase-1 锚）
harness 测试文件 = 产品仓 SimiGoTests/ 工作区未提交文件（本战役既定
  纪律），经 sibling-clone 解析 Lab 包（P7-R2-A 同路径）；执行时源码
  归档 Lab 仓（SHA 入 R0 metadata）
R0 仪器 = ReplicationAuditRunner（本战役既定六件套）
```

## 2. M1 — Model Identity Binding（冻结）

### 2.1 CheckpointData v2 schema

```json
{
  "schemaVersion": 2,
  "executionID": "...",
  "position": 0,
  "continuationNextInput": "...",
  "continuationID": "...",
  "tokenPrefix": [/* token IDs */],
  "anchorHash": "sha256(token ids, P7-R2-A 同法)",
  "modelIdentity": {
    "modelPath": "llama-server /props 实报路径",
    "modelHash": "SHA256(GGUF 文件全字节)"
  }
}
```

### 2.2 绑定与验证规则

- Phase A checkpoint 写入时计算 modelHash（全文件 SHA256，21GB 级
  一次性成本可接受）；
- Phase B restore **前**强制核对：J-I1 = `executor.props().modelPath
  == checkpoint.modelIdentity.modelPath`；J-I2 = 重算 SHA256 ==
  `checkpoint.modelIdentity.modelHash`；
- **任一失败 ⇒ 基点身份未建立 ⇒ I 维持 PARTIAL ⇒ overall
  INCONCLUSIVE（永不 FAIL）**；全部通过 ⇒ I 在结果文档升格
  NATIVE-EXPRESSED（升级是结果陈述，非设计假设）。

## 3. M2 — Fork / Divergence Cell（冻结）

### 3.1 分叉树（human 图逐字实现）

```text
Phase A（form，进程 1）：
  S₀ = tokenize(initialText) → create(pos 0) → continue(turn1)
     → real generate(32, seed 42) → continue(gen) → capture
     → checkpoint v2 落盘（pos N = tokenPrefix 计数，anchorHash_A0）

Phase B（fork，进程 2，全新 backend+coordinator 栈）：
  restore S₀ payload 两次 → 两个独立执行（lineage root = S₀）：
  ├─ Parent：attach T → continue ΔP → bind T+ΔP → real generate
  │          → bind T+ΔP+genP → 记 parentCheckpoint
  └─ Child： attach T（独立 attach）→ continue ΔC → bind T+ΔC
             → real generate → bind T+ΔC+genC → 记 childCheckpoint
  判据 J-A1/J-A2/J-A3 + J-C + J-PN（见 §5）

Phase C（restore-to-N + 续算，进程 3）：
  restore childCheckpoint → J-I/J-P 复核 → continue ΔR → real
  generate → J-C4 锚定判读
Phase D（parent non-pollution，进程 4）：
  重放 parent 生成（同 T+ΔP，seed 42）→ 与 Phase B parent 输出
  逐字比对 + parent payload 内容 SHA 恒等
```

### 3.2 冻结常量（S₀ 沿用 P7-R2-A 原文；Δ 预注册）

```text
initialText = "I am organizing desktop files into a folder called
              ReferenceFiles containing project management documents."
turn1       = "What folder did I create?"
ΔP (parent) = "What is the name of the folder mentioned?"
ΔC (child)  = "Summarize the purpose of the folder mentioned."
ΔR (restore 后续算) = "What was this folder for again?"
锚定实体表（J-C4 用，均为 S₀ 内容词、不含探针词）：
  ["ReferenceFiles", "project management"]
生成参数 = predictionTokens 32 / seed 42 / greedy（P7-R2-A 同）
anchorHash 算法 = SHA256(token IDs comma-joined)（P7-R2-A 同法）
```

## 4. R0 仪器与隔离（冻结）

- 每 invocation 独立 `results/replication-p71/{runUUID}/` 六件套；
  4 个独立 xcodebuild 进程；工作区 `/tmp/simigo-p7-1`（全新）
- 递归内容见证（F-3 修复版）施于 checkpoint 目录；`cached_tokens`
  若 executor 可取则逐 generate 记 R0 遥测事件（**只记录不判定**；
  不可取则记 N/A，不为遥测改契约）
- metadata：harness SHA + modelIdentity + server props + commit
  （产品仓 dc12a0c+dirty 标注）+ configHash

## 5. Cell → 判据主表（冻结；判读机械套用）

| Cell | 判据 | 失败路由（P7-0 §5 三分） |
|---|---|---|
| C1 Identity (M1) | J-I1 modelPath 相等；J-I2 modelHash 相等 | 任一失败 ⇒ 身份未建立 ⇒ **overall INCONCLUSIVE**（非 FAIL）；transport 异常 ⇒ implementation |
| C2 Position | J-P1 restore pos == checkpoint pos；J-P2 append 后 pos == N+\|Δ\| | transport ⇒ implementation；机械正常但错 ⇒ **closure（INV-P）** |
| C3 Anchor (M2) | **J-A1 anchor(child@fork) == anchor(parent@fork) == anchorHash_A0**；J-A2 两支 divergent（anchorHash 不等）；J-A3 functional（alt-Δ 改变 hash，P7-R2-A 同法） | J-A1 败 ⇒ **closure（INV-A）**（除非 implementation）；J-A2 败 ⇒ 先查 implementation（tokenizer 塌缩）再 closure |
| C4 Continuation | J-C1 prefix_is_extension；J-C2 position advanced；J-C3 无 cold fallback；**J-C4 锚定=输出 containsAny(实体表)** | 机械正常但败 ⇒ **closure（INV-C）** |
| C5 Parent non-pollution | J-PN1 重放输出与 Phase B parent 逐字相同；J-PN2 parent payload SHA 恒等 | 可最小复现 ⇒ implementation（server cache 级）；持续 ⇒ **closure（INV-A 泄漏）** |

## 6. Overall 判读规则（冻结；引用 P7-0 §6）

```text
全 cell PASS 且 J-I1/I2 PASS
  ⇒ CONTINUATION_VALIDATED_CROSSBACKEND
    ⇒ Claim F 升 bounded cross-backend claim（措辞=P7-0 §6 原文，
      禁止「都通过⇒backend-independent」）；I 升格 NATIVE-EXPRESSED
任一 identity 失败 ⇒ INCONCLUSIVE（不计正反）
implementation 故障 ⇒ 修复重跑，不计入 closure 评价
任一 closure 失败（INV-P/A/C）⇒ overall FAIL = 有效重大结果
  （OP-6-1 在该 backend 对上否定性回答，定位到关系级）
```

## 7. 执行前置条件（执行门核对项，本档不执行）

- llama-server 运行于 127.0.0.1:8080，载入 Cyber-Tiel GGUF
  （P7-R2-A 同模型；GGUF hash 由 M1 首算入册）
- 端口空闲；磁盘空间；产品仓 sibling-clone 解析 Lab 包
- harness 文件落产品仓工作区（不 commit）+ 执行时归档 Lab 仓

## 8. Pre-registration 声明

本档在实验前冻结全部判据/cell/失败路由/输出格式；**不产生、不暗示
任何实验结论**。执行须单独 human 授权；判读将由独立 adjudication
invocation 机械套用 §5–§6；判据零修改条款继承本战役宪法（失败=
有效结果，不得改判据重试）。
