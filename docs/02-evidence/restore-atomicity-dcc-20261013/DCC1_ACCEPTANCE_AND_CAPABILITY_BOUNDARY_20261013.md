# DCC-1 验收与能力边界记录

- 日期：2026-10-13
- 裁定：ACCEPT_DCC1_IMPLEMENTATION / ACCEPT_DCC1_PROCESS_CRASH_RECOVERY / **DCC2 = NOT AUTHORIZED**
- 验收对象：`d9dc33cb`（分支 `codex/restore-recovery-coverage`；谱系 `dbcd9330` 恢复覆盖 → `d0994cbf` 单 execution 边界 → `6c7368d2` DCC-0 设计包 → `b313b431` DCC-1 实现 → `d9dc33cb` REVISE 修复）
- 本记录的性质：**归档已实现与已验证的内容及其能力边界**。不将 DCC-1 扩写为 Restore Atomicity 整体证明。

---

## 1. 已实现的契约（DCC-1 = Tier 1）

### 1.1 基线记录格式

每个引擎会话一个目录 `sessions/<sessionUUID>/`，内含：

- `baseline.json` — 规范记录（sortedKeys JSON）：
  `formatVersion`（当前 1；未知版本一律判无效）、`sessionUUID`（会话代际，**固定 execution ID "S" 不充当代际**）、`executionID`、`weightsIdentity`、`tokenizerIdentity`、`position`、`continuationNextInput`、`continuationID`、`prefixTokens`（足以确定性重建 bootstrap 状态的规范 token 前缀）。
- `baseline.sha256` — payload 字节级 SHA-256（十六进制）。
- 根目录 `current.json` 指针 — `{formatVersion, sessionUUID, retired}`；**指针写入 = 提交边界**：指针命名某会话后该会话才可恢复；`retired=true` 墓碑使会话不可恢复（有序拆除的第一步）。

### 1.2 身份计算（内容级绑定）

- 加载器核查结论：`PerTensorSafetensorsReader` 为 index+seek 读取器，**不提供不可变版本身份**——因此采用内容摘要，而非路径+大小清单。
- `weightsIdentity` = 每个 `.safetensors` 的**流式全文件 SHA-256**（1 MiB 块），清单行 = `path:size:contentDigest`（排序后联合摘要）。绑定**内容**，不绑定路径与大小。
- `tokenizerIdentity` = tokenizer/config 类小文件（≤8 MiB）的内容联合摘要。
- 成本：基线提交与恢复校验各 **O(模型字节)**（硬件 SHA，秒级/GB；1 MiB 块读取，不整文件驻留内存）。这是当前无可信加载器身份时的诚实默认；未来若出现经验证的不可变加载器身份可替换之。
- 验证：同路径、同大小、内容 `AAAA`→`AAAB` 的原地替换，恢复判 identity mismatch → 冷启动（`testWeightContentSwapSameSizeRejectedAtRecovery`）。

### 1.3 写入协议与提交阶段语义（全部可达阶段均有确定语义）

写入序列：临时文件 → 文件 F_FULLFSYNC → 原子 rename → 父目录 F_FULLFSYNC。

| 可达失败阶段 | 提交语义 |
| --- | --- |
| 临时文件创建 / 文件同步 / rename 失败（任何阶段） | **确定未提交**（目标从未被替换） |
| payload 阶段 rename 后目录同步失败 | **确定未提交**（序列中止于指针之前；孤儿文件恢复不可达） |
| digest 阶段同上 | **确定未提交**（同上） |
| **指针阶段 rename 后目录同步失败** | **已提交（带 caveat）**：rename 已发布提交，报"未提交"会与恢复行为矛盾。重试一次同步后接受。**限定语义（必须保留的原话级理解）：此路径=「逻辑提交已经发布，但掉电持久性未获证明」；代码与文档不得暗示持久性已经确认** |

数据丢失语义（Tier 1 定义并测试锁定）：restore 与逐轮执行**保持内存态**；崩溃后恢复只落在最近持久基线，从不落在崩溃前的活位置。

### 1.4 有序退休与替换边界

`newSession` 在任何拆除之前先持久退休指针（墓碑）。退休失败 → 整个 newSession fail-closed，活会话原样可重试（拆除零发生，测试锁定）。崩溃永远不可能把已丢弃会话伪装成可恢复；**有序拆除之后恢复按设计不可用**（指针已退休）——恢复只属于崩溃场景（指针未退休）。基线替换 = 新会话把指针提交到新代际，恢复恒解析当前代际。

### 1.5 恢复入口

`recoverDurableSession()`：校验链 = 指针可读且未退休 → payload/digest 存在 → 校验和 → 可解码 → formatVersion → 代际绑定 → weights/tokenizer 身份。**任一失败走定义冷启动**；成功则按基线重建四组件（幂等重绑定 + bootstrap Ledger 条目，其成功附加同时是 I-L3 物理重建证明）。基线提交失败的会话降级 `.absent` 继续运行，**永不虚报持久能力**。

---

## 2. 进程级崩溃证据（SIGKILL，spawn-self 模式）

| 崩溃时点 | 重启后验证结果（真实恢复调用，非退出码） |
| --- | --- |
| 基线+指针提交后 | `recovered`，sessionUUID 与崩溃前一致，position=基线位 |
| 指针退休（有序拆除）后 | `coldStart`（不复活已丢弃会话） |
| 撕裂 payload（截断+指针在册） | `coldStart`（校验和门） |
| **payload 已同步、digest/指针未写** | `coldStart`（不完整基线不作有效会话） |
| **payload+digest 已同步、指针未提交** | `coldStart`（未发布基线不恢复） |

对照单元证据：payload/digest/指针三阶段目录同步失败注入 → 语义逐一吻合 §1.3 表。

---

## 3. 能力边界（明确不声明的内容）

1. **掉电与系统崩溃持久性 = NOT VERIFIED。** F_FULLFSYNC 是 Apple 平台强同步的尽力形式；无掉电测试手段。指针"已提交（带 caveat）"路径尤其只证明逻辑发布，不证明掉电存活。
2. **持久介质故障 = NOT VERIFIED。** 记录校验和使损坏可检测并降级冷启动，但不承诺介质故障下的数据存活。
3. **DCC-2（restore INTENT/回滚协议）= NOT AUTHORIZED，未实现。** 崩溃发生于 restore/逐轮执行期间时，会话回退到基线（已文档化的数据丢失语义）——这不是 DCC-2 的崩溃中恢复能力。
4. **Restore Atomicity 整体 = NOT CLOSED；跨组件事务原子性 = NOT ESTABLISHED。** DCC-1 验收不升级这两项。
5. 单 execution 引擎边界不变（多 execution = UNSUPPORTED BY DESIGN）；Frozen Contract 不变。
6. 稳定性观察项：DCC-1 首次全量曾出现一次未复现的"1 unexpected"失败；此后连续多遍全量（含 279/3/0 ×4）全净，保留观察。

---

## 4. 测试账本

- DCC-1 套件 24/24：存储协议 12（往返/损坏/未知版本/代际错配/身份错配/**内容替换**/撕裂/缺席与退休/不可写根 + **payload/digest/指针三阶段目录同步注入**）；引擎集成 7（提交/退休/恢复重建/代际替换 crash-analog/失败不虚报/退休 fail-closed/身份冷启动）；进程级 5（提交后/退休后/撕裂/**payload 中途/digest 中途**）。
- 全量回归：279 executed / 3 skipped / 0 failures，连续两遍；完整未过滤日志 `/tmp/simigo-dcc1-full-test-log-101001.txt`、`-second.txt`（稳定性观察指令项）。

---

## 5. 收口声明

DCC-1 就此收口：**进程级崩溃恢复 = TESTED；掉电与介质故障持久性 = NOT VERIFIED**。实现保持现状，不为增加提交而扩张。未来若研究 DCC-2，须另行评估其恢复协议与 Ledger marker 去重前置条件，并独立授权。
