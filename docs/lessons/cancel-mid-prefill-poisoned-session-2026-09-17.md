# cancel-mid-prefill 毒 session 楔死：cancelCommitSkip 之外的第二条取消不变量（2026-09-17 晚）

**日期：** 2026-09-17 19:01–20:43
**模型：** peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX（阶段一）→ peculiar-ragdoll/Cyber-Tiel-Coder-35B-A3B-MLX-oQ4e（19:15 换模后，阶段二/三）
**引擎：** v1.4（HEAD 4612179 + release 构建），真机长时运行
**定性：** 结构性 P0 候选（观察窗口 5.1 内实证事故；窗口纪律=入册不动工）

## 背景

取消家族的第二起事故。第一起（2026-09-13，已修 39ff354）：mlx 流取消不抛错 →
空 assistant 提交进 history → 重试 count=false → 冷预填死循环。`cancelCommitSkip`
修复的是「取消不得产生有效 history 提交」。本次暴露的是**同一条取消路径上的
第二个不变量缺口**：取消不得留下仍可被复用的半初始化 session。

## 现象

19:44:43 起连续 10 个请求（4d8769 → 9f57b4 → 34b572 → 0b8d18 → 6364b4 →
df9ae1 → eaec57 → 0c81f9 → 2c7bcb），每个请求同一形态：

```text
prefillStep=2048 est=3570 reuse=true     ← prefix 命中，进入复用
（此后 300 秒零输出：无 prefill 进度行、无 chunk、无 session= 收尾行）
[CANCEL] 客户端超时取消
cancelCommitSkip history=49 rawEv=0 rawB=0 emitB=0
RELEASED reason=cancelled_by_client
→ 客户端重试 → 再次命中同一 session → 循环
```

持续 50 分钟无自愈。20:43:29 idleSuspend 触发 `sessions.removeAll()`，楔死解除——
这条自愈路径本身就是根因的旁证。

## 证据链

### 触发前提：客户端重写历史 + 巨型冷预填跑不赢客户端超时

- 19:01–19:37 反复出现 `prefixMismatch index=46 role=user`（下午同会话族为
  index=13，同一家族随历史增长稳定漂移），每轮触发 70–80k 全量冷预填。
- swap 压力下（swapUsed 峰值 7582MB）预填速度 tps≈12，单次 promptTime
  459.5s / 570.8s，结构性跑不赢客户端 ~300s 超时 → 预填必被中途取消。
- 19:23:25 `TOOL_RESULT ... tc=8b64c7 tool=- anomaly=unknown_tc`：客户端回传的
  tool_call id 在治理表中不存在——**客户端重试时重新生成了 tool_call id**，
  这是历史被重写（prefixMismatch 稳定复现）的直接物证。

### A/B 对照：毒只存在于「被取消的那个 session 对象」

```text
A 组（19:26:55）baba09 预填中被 cancel
   → c9d284 reuseMiss count=false → 新建 session → 预填正常（进度行流畅）
   ⇒ fresh session 始终健康

B 组（19:37:47）3ab4a2 预填 54108/76119 被 cancel
   → 28929e 同毫秒进 gate，新建 session（est=17569），预填 6.4 分钟无进度行，
     cancel 时 partial 账本冻结在 3570 tok（≈9 tok/s）
   → 4d8769 reuse=true est=3570（命中 28929e 遗留 session）→ 零输出挂死
   ⇒ 复用「被 cancel 打断过的 session」必挂死
```

### 楔死闭环的三个构成条件

1. **reuse 失败路径立即注册**（NativeMLX.swift:544）：新 ChatSession 当场写入
   `sessions[storageKey]`，history=incoming.dropLast()，此时预填尚未开始。
2. **cancelCommitSkip 只挡 history 提交**：`managed.history` 不更新（正确），
   但 dict 中该 session 对象原样存活，内部执行状态已被 cancel 打断。
3. **重试 payload 稳定后 prefix 必命中**：客户端停止重写后，每次重试 =
   上次 incoming + 1 条消息 → `isPrefix` 通过 → 复用毒 session → 挂死。
   cancelCommitSkip 又保证毒 session 永不被替换。

`cacheStatus()` 对毒 session 正常返回（est=3570 冻结值）而 `streamDetails` 零事件——
对象存活、元数据可达、生成管线不可用。

## 根因

`cancelCommitSkip` 建立的不变量是「取消不得提交半成品 history」；
本次证明还需要第二条：**本轮新建、prefill 未成功完成即被取消的 session，
不得继续作为可复用 session 存活。**

当前状态机实际形态：

```text
REGISTERED（预填前）→ CANCEL → REGISTERED + 内部状态被打断 → 仍可被 reuse
```

即「session 对象存在于 dict」被当成了「session 可复用」。二者在取消路径上不等价。

## 未定谱（不与根因混记）

19:37:47 的 cancel 与下一请求进 gate 同毫秒，此后连 fresh session 预填也降至
~9 tok/s，孤儿 GPU eval 与新 eval 并发是候选放大器（与 qwen3_5_moe 编译死锁
家族同源）。但 19:26:55 同型转换未卡构成反例，**并发退化仅作观察项记录，
不作根因结论**。

另：下午 17:54 r=513d15（s=06f438）同样在冷预填中被取消，但后续请求换了
session key，毒 session 未被命中——与「毒只在同 key 复用时显形」一致。

## 处理方式

- 事故当晚引擎经 idleSuspend 自愈（sessions.removeAll 清场）；客户端侧避免对着
  楔死会话无退避重试——每次重试都在为毒 session 续命。
- 同晚用户批准提前动工（窗口纪律让位于结构性 P0）：cancelCommitSkip 路径补
  第二条取消不变量——本轮新建（`reusedSession=false`）且零流事件（`rawEv=0`）
  即被取消的 session，从池中逐出并 `clear()`（trace `poisonedSessionEvict`）。
  逐出后下一请求新建 session 走健康路径，毒链闭环被斩断。
- 边界记录：`rawEv=0` 是当前版本的诊断辅助判据，显式 readiness 状态
  （ABSENT/READY/RUNNING/INVALID）留待 session 生命周期协议；复用路径
  （`reusedSession=true`）中途取消是否同样致毒**未观测到**，按最小切口暂不逐出，
  若未来出现复用路径挂死样本再收紧条件。
- **真机验证通过（2026-09-17 21:52 新二进制上线后，自然实验）**：当晚两次
  cancel-mid-prefill（`rawEv=0`）均正确触发逐出，且毒 session 未再入池：
  - 21:55 `cancelCommitSkip session=ee23b8/main history=77 rawEv=0` →
    `poisonedSessionEvict`；
  - 21:56 `cancelCommitSkip session=033a22/main history=15 rawEv=0` →
    `poisonedSessionEvict` → 同 key 下一请求 **`reuse=false`** 新建 session →
    69.2s 冷预填后**正常完成**（`rawEv=85 emitB=343`）。
  与事故夜同型触发（baba09 式预填中取消）形成前后对照：修复前下一请求
  `reuse=true` 挂死×10（50 分钟），修复后逐出 + 健康重建。代价侧：逐出后
  下一请求重付全量冷预填（本例 69s），是正确的代价，替代项是无限挂死。

## 后续观察（2026-09-17 深夜，22:04–00:26）：复用路径「重建×超时」竞速循环——非生命周期问题

修复上线后同晚还出现了一个表面相似、定性不同的循环：会话 ee23b8/main（~50-65k
暖缓存）连续 8+ 轮 `reuse=true` → 官方引擎全量重渲 **39613 tok**（40–110 tok/s，
swap 6.2GB 下需 6–16 分钟）→ 客户端 ~10.5 分钟超时取消 → 重试从零再建 → 无进展
2h22m，直至 idleSuspend。与楔死的鉴别点：**prefill 进度行全程流动**（17272/39613
→34544/39613→下一轮又从 17272 起），不是硬挂死。

关键鉴别实验（同窗对照）：

- 6ea2a2/main（~18k 小会话）22:23:28 同型取消（reusedSession=true、rawEv=0）→
  下一请求 `mode=rebuild cacheEff=0.00` → **80.2s 重建 19171 tok → 正常完成**。
- ee23b8/main 同型取消 → 同样的 rebuild 路径，但 39613 tok 在 swap 下永远跑不赢
  客户端超时。

由此**以数据关闭开放项**：「reusedSession=true 中途取消是否同毒」——不同毒。
复用路径零事件取消的后续是官方 rebuild，机制本身健康；小会话验证重建可完成，
大会话败给超时是**容量问题**（P2 Admission/上下文预算的直接实证），不需要新的
生命周期不变量。lifecycle 修复行为全程正确：该触发时触发（21:55/21:56 两次），
该静默时静默（复用路径 6+ 次零事件取消均未误触发逐出）。

新增上游观察项：37404b 轮（22:03:55）在**无任何 cancel 参与**的情况下——会话
22:02:41 刚以 49827 tok 冷重建成功并正常提交——官方引擎即拒绝 extend 选择全量
重渲，且重渲总量 39613 **小于**账本 49827。渲染/账本分歧的精确算术需官方账本
细节，属 qwen3_5 GDN 渲染分叉家族（[[qwen35-hybrid-cache-rebuild]]）；「SimiGo
reuse=true × 官方 rebuild」的层间错位是遥测上的已知盲区，非本地可修。

## 长期方向（未动工）

`rawEv == 0` 不应长期充当「session 无效」的唯一依据（telemetry 自身可能不完备）。
正式形态是显式 session readiness——`sessions[key]` 隐含 READY 语义，新注册
session 在首个成功流事件（或 prefill 完成）前不进入可复用池：

```text
ABSENT / READY / RUNNING / INVALID
而非 exists → reusable
```

这与 Branch-Fork 生产协议（created/active/selected/deleted）是同一层抽象：
**session/branch 生命周期已是生产协议，不再是一个缓存字典。**

## 影响范围

- 触发条件：reuse 失败 → 新建 session → 预填中被取消 → 后续请求 prefix 命中该 key。
  上下文越大、客户端超时越短、机器越接近内存饱和，越容易进入。
- 不涉及 fork 路径本身（fork 证据链不受本次影响）；index=13/46 前缀语义问题与
  fork telemetry 问题保持独立优先级。
- 关联决策：BRANCH_FORK_PROTOCOL_DRAFT.md（生命周期抽象层共享）。

## 是否需要 ADR

需要。最小修复已落地（当晚，用户批准提前动工）；session validity invariant
（READY 门禁）作为 cancel 清理协议的第二条不变量、与 39ff354「取消不提交」
并列的正式 ADR，待窗口期满评审后入册。
