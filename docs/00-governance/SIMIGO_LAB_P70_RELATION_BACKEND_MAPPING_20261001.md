# P7-0 — Relation-to-Backend Mapping + Continuation Invariant Criteria（冻结）

日期：2026-10-01
状态：`P7-0 FROZEN / EXPERIMENTS NOT EXECUTED / harness 设计另设门`
任务令：human 2026-10-01（**Phase-2 = 路线 B Cross-backend Validation**
确定；当前不执行实验、不改产品仓；先冻结 P7-0 relation-to-backend
mapping + invariant 判据，然后才进入实际运行）
严格目标（human 原文）：验证 candidate `{I,P,A,C}` relation closure
是否能够**脱离 MLX，在 llama.cpp backend 上表达，并保持同一
continuation invariant**。不是重新证明 llama.cpp 已经能 fork/restore，
也不是 artifact portability 测试——Phase-2 要填的是 **Claim F 的
evidence gap**。

---

## 1. 入口链（冻结）

```text
Phase-1 MLX Runtime Evidence Consolidated
        │
        ▼
candidate {I,P,A,C}
        │
        ▼ B Cross-backend Validation
        ├── MLX（Phase-1 参照值在案）
        └── llama.cpp
                ▼
        same abstract closure
                ▼
        same continuation invariant
```

## 2. 现状事实基础（llama 侧资产盘点，P7-R2-A harness 本地对象恢复）

P7-R2-A（Palace1P7R2LlamaRealTests @ 70081e5）llama 侧既有原语：

- `LLAMAServerExecutionStateBackend/Executor` + `LLAMAServerPrefixPayload`
  （SimiGo2Experimental 模块，本地对象可恢复）
- checkpoint = JSON {executionID, position, continuationNextInput,
  continuationID, **tokenPrefix: [Int]**, anchorHash}
- **关键事实（决定映射分级）**：llama 侧 representation = **token-ID
  前缀数组**，KV 物化发生在 llama-server 请求内部（服务端 prompt
  cache，harness 未记录 cached_tokens）；checkpoint **无 model
  identity 绑定**（server model 隐式）；anchor = token-ID 级哈希
  （与 MLX 的 transcript 级 anchorHex **不同形同功能**）；lineage
  仅 root，**无 fork/divergence cell**
- 已过判据：C1 identity/C2 position/C3 anchor hash_equal+functional/
  C4 prefix_is_extension+cold_fallback=false（真实 llama-server
  tokenize+generate，seed=42）

## 3. Relation-to-Backend Mapping（冻结；本档核心）

| 关系 | MLX 表达（Phase-1 锚） | llama.cpp 候选表达（现有资产） | 映射状态 | 反走后门守则（human 四问对应） |
|---|---|---|---|---|
| **I Identity** | storageKey/modelId/kvFingerprint/ExecutionID（checkpoint 身份） | ExecutionID 字符串 + lineage root（checkpoint 已载）；**server props.modelPath 未入 checkpoint** | **PARTIAL**——ExecutionID 契约内原生；**model-identity 绑定缺失（P7-0-M1，harness 可补：checkpoint 增 modelPath/GGUF hash + restore 时核对 server 实载模型）** | 不把「同一个模型文件/同一个 server」误当成 identity——identity=执行身份绑定，须显式核对 |
| **P Position** | processedTokenCount ↔ ledger 对齐；restore pos == checkpoint pos（17/16 实证） | position Int64 = tokenPrefix.count；restore pos == checkpoint pos（C2 PASS） | **NATIVE**（token 计数语义） | 不以 KV/artifact 相同作为充分条件——position 必须被**功能性验证**（续算落点行为一致），非字节恒等 |
| **A Anchor** | anchorHex=canonicalized transcript 尾哈希（文本级） | anchorHash=SHA256(token IDs)（token 级）；C3 hash_equal+functional | **EXPRESSED-DIFFERENT-FORM**（功能同：N 处内容绑定；形式 backend-native）；**fork/divergence cell 缺失（P7-0-M2，实验必补）** | child divergence 后能否定位共同状态点——现 harness 未检验，列为 Phase-2 必答 cell |
| **C Continuation** | continuation{nextInput,continuationID}+前缀延接契约；cacheHit/extend 路径 | checkpoint 内同构 continuation + tokenPrefix append + 真实 complete(seed=42)；C4 位置前进+严格前缀扩展+无 cold fallback | **NATIVE-IN-CONTRACT**；KV 复用语义不同层（llama 服务端内部）——**不变量按关系语义层表述（D7），KV 复用（usage.cached_tokens）只作描述性遥测，不作不变量** | S₀→fork→restore→append same Δ→future computation continues 必须表现与 MLX **同一语义不变量**（形式见 §4），而非同 token 输出 |

**设计时点结论：零关系 MISSING**——I 的缺口（M1）与 A 的缺口（M2）
均为 harness 可补项，非表达不可能 ⇒ Phase-2 实验可设计。

## 4. Continuation Invariant 判据（INV-XB，冻结；两 backend 同形式）

判读形式沿用 C1–C4 骨架，**不变量是关系语义级的，跨 backend 同形式
不同 token 输出**（两 backend 模型不同，文本不要求一致；backend 内
greedy+固定 seed 要求重跑稳定）：

```text
INV-I  restore 后 identity == checkpoint identity，
       且 checkpoint 所录 model 绑定 == server 实载模型（M1 补后）
INV-P  restore 后 position == checkpoint position N；
       append Δ 后续算落点与 N+|Δ| 一致（功能验证）
INV-A  restore 后 anchor hash == checkpoint anchor hash 且 functional
       （不同 Δ → 不同 anchor）；fork cell：child 在 fork 点的
       anchor == parent 在 N 的 anchor（divergence 定位共同状态点）
INV-C  append(Δ) 被接受为严格前缀扩展；restore 后生成表现为
       S₀ 语境内的锚定续算（对 Δ 的回答在上下文内，非冷启动形态）；
       无 cold fallback；KV 复用只记录不判定
```

## 5. 失败三分分类（冻结；human 要求的区分）

```text
relation mapping failure     某关系在设计时点无 llama 表达（映射行
                             MISSING 且无可构造表达）⇒ Claim F 缺口
                             定位于映射层；该关系不进入运行
        ≠
backend implementation failure  表达存在但 adapter/transport/harness
                             行为故障（restore 抛错/server 错误/
                             tokenizer 失配）⇒ 修复实现后重跑；
                             不计入 closure 评价
        ≠
closure/invariant failure    表达存在且机械正常，但 INV-XB 不成立
                             （identity 对而续算冷启动/anchor 对而
                             divergence 定位失败）⇒ OP-6-1 在该
                             backend 对上否定性回答 = 重大有效结果：
                             closure 在受测范围内是 MLX-bound
```

观测路由预注册：restore/transport 层异常 → implementation 类；
映射表 MISSING/PARTIAL 且无构造 → mapping 类；全机械正常而
INV-XB 判据失败 → closure 类。**禁止把 implementation 故障记成
closure 失败，反之亦然。**

## 6. 判读预注册

- **SUCCESS** = 四关系全部有表达（M1/M2 补齐后）+ INV-XB 在全部
  预注册 cells（含 fork/divergence cell）于 llama.cpp 成立，MLX 侧
  参照值在案 ⇒ Claim F 升格为 **bounded cross-backend claim**，
  措辞严格为：
  > 「MLX 与 llama.cpp 均能以各自 backend-native representation
  > 表达同一 candidate relation closure，并在 restore 后保持相同
  > 的 continuation invariant。」
  **禁止写成**「两者都通过 ⇒ ES backend-independent」。
- **PARTIAL** = 某关系 MISSING ⇒ Claim F 维持 NOT YET，缺口按映射
  表精确定位。
- **closure failure**（§5 第三类）= 有效重大结果，Claim F 记负但
  定位到关系级。
- 全程 R0 仪器化（runUUID/单调钟/隔离工件目录）——继承本战役既定
  规范。

## 7. 环境常量（R0-6 预登记）

llama-server binary hash + 版本、GGUF model hash、seed=42（greedy
等价）、端口、tokenize/complete 端点；MLX 侧参照=Nail-Qwen3.6
@31a0106（Phase-1 锚）。模型不同 ⇒ 文本输出不可比，只有不变量
可比（§4 已钉）。

## 8. Non-claims 与下一步

- 本档不执行实验、不改产品仓、不重证 llama fork/restore 存在性、
  不做 artifact portability、不做 G-δ。
- 下一步 = Phase-2 实验 harness 设计门（含 M1 checkpoint 补 model
  绑定 + M2 fork/divergence cell 设计），设计 → human 授权 → 执行
  → R0 登记 → 判读按 §6。
- MLX 侧参照值取自 Phase-1 在案产物，不重跑。
