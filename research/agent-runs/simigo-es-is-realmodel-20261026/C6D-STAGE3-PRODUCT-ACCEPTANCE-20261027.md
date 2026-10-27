# C-6d · 阶段 3：Release / 安装版 / 真实模型 KV-free 验收（2026-10-27）

> 本文只记录**第二层（产品层）**验收的身份、环境与读数。测试层读数在
> `C6D-KVFREE-TESTLAYER-20261027.md`（§7 为阶段 2 收官复跑），两者不混写。
> 状态：**K1 / K2 / K3 三案读数已全部取得**（§9–§12），缓存目录已按「只移动、不删除」恢复（§14.1）。

## 1. 源码身份（事实）

| 项 | 值 |
|---|---|
| HEAD | `97043902075b67eb1693749fd6ed50421eccf3ba` |
| `git diff \| shasum -a 256` | `b2a02ce2cfdef9a83d04caaff58463c1d7a7e0fcb922c54b6367b21de3171a36` |
| `git status --porcelain` 行数 | 53 |
| 提交 / 推送 / 合并 | **无**（未执行，按裁定） |

## 2. 构建产物身份（事实）

| 项 | 值 |
|---|---|
| 构建命令 | `xcodebuild -project SimiGo.xcodeproj -scheme SimiGo -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/simigo_rel CODE_SIGN_IDENTITY=- build` |
| 构建结果 | `** BUILD SUCCEEDED **`（日志 `/tmp/simigo-release-build.log`） |
| Release 二进制 | `/tmp/simigo_rel/Build/Products/Release/SimiGo.app/Contents/MacOS/SimiGo` |
| 二进制 SHA-256 | `9ba486976d56de2b8614c2cb8537e2253955084e438a18c428838913a53c1a30` |
| Bundle 大小 | 104 MB（单文件 Release，无 `SimiGo.debug.dylib`） |
| 版本 | `CFBundleShortVersionString=2.2.0`，`CFBundleVersion=29` |
| 签名 | `Signature=adhoc`，`flags=0x10002(adhoc,runtime)`，`Identifier=SwiftUI.SimiGo`，无 TeamIdentifier |
| Gatekeeper | `spctl -a -vv` → **rejected**（adhoc 期望内；非公证构建） |
| DMG | `SimiGo-v2.2.0-29-9ba48697.dmg`（33,379,095 B，`hdiutil verify` VALID） |
| DMG SHA-256 | `eb952b556543b8456919bdddd6b1e59b50a499292886652b689325b0a4f22700` |
| DMG 内载荷 | `SimiGo.app/Contents/MacOS/SimiGo` SHA-256 = `9ba48697…c1a30`（与构建产物一致） |

说明：构建时先误加了 `-enableCodeCoverage NO`，`xcodebuild: error: The flag
-enableCodeCoverage is only supported when testing`；去掉该参数后重建成功。

## 3. 安装前基线（事实，已保留）

| 项 | 安装前 |
|---|---|
| `/Applications/SimiGo.app` | 存在，2.2.0 (29)，248 MB，mtime 10-27 05:35 |
| 其二进制 SHA-256 | `927d4555469efdf4a6c2a92055eb5e7cdaebc3fa6a4a6f9263ba565cf34e7720` |
| 签名 | `Signature=adhoc`，`Identifier=SwiftUI.SimiGo` |
| 运行中的进程 | **无**（`pgrep -fl SimiGo` 空） |
| 监听端口 | **无**（`lsof … -sTCP:LISTEN` 无 SimiGo；8000 端口空） |
| 基线副本 | `/tmp/simigo-stage3-20261027-150733/SimiGo-installed-baseline.app`（248 MB，二进制哈希同上） |
| 真实 `~/.simigo` | 8.2 GB；`prefix-pool` mtime 10-26 19:06、`branch-checkpoints` mtime 10-27 04:19、根目录 03:47（**全程未写**） |

## 4. 安装结果（事实）

- 挂载 DMG（`-readonly`，载荷哈希见 §2）→ `rm -rf /Applications/SimiGo.app` →
  `ditto <DMG>/SimiGo.app /Applications/SimiGo.app` → 卸载 DMG。
- 安装后：`/Applications/SimiGo.app` 二进制 SHA-256 = `9ba48697…c1a30`，
  `Identifier=SwiftUI.SimiGo`，`Signature=adhoc`，bundle 时间 15:02。
- 安装由当前用户完成（`/Applications` 为 `root:admin drwxrwxr-x`，无需 sudo；
  与旧版「DMG 安装器把 App 变成 root 所有」的路径不同，本次安装后属主仍是当前用户）。

## 5. 隔离运行根（事实）

`/tmp/simigo-stage3-20261027-150733/run/`

| 用途 | 路径 |
|---|---|
| `SIMIGO_HOME` | `…/run/home`（新建；仅复制了 `bin/`、`build/`、`manifests/engine-recipes.json`，并预置 `manifests/first-run-done.json` 跳过向导） |
| `SIMIGO_CACHE_ROOT` | `…/run/cache`（空目录，K1 首段真实生成用；随后会被阻塞） |
| `SIMIGO_STATE_GRAPH_STORE` | `…/run/state-graph/reference-graph-v1.json` |
| 独立数据库 | `…/run/home/simigo.sqlite3`（由 App 首次启动创建，**不是**真实库） |
| 模型权重 | 只读复用 `~/Library/Caches/huggingface` 下既有快照（`SelectedModelPath`），本次不复制、不改写 |

`~/.simigo`（真实库与两个 KV 目录）不在任何注入路径上。

## 6. 启动尝试（事实 + 结论）

- 以 `env SIMIGO_HOME=… SIMIGO_CACHE_ROOT=… SIMIGO_STATE_GRAPH_STORE=… /Applications/SimiGo.app/Contents/MacOS/SimiGo`
  直接执行：进程能创建，但 **数秒内自行退出**，`app.log` 为空，
  `~/Library/Logs/DiagnosticReports` 无新条目，`log show --predicate 'process == "SimiGo"'` 无输出。
- **结论**：本 agent shell 不具备可用的 GUI/Aqua 会话上下文，应用在 `NSApplication`
  启动阶段即正常退出；这不是产品缺陷，也不是崩溃。
- **推论**：服务启动必须由操作者在真实 GUI 会话中完成（与既有事实
  「HTTP 服务须用户手动启动」「新签名首启可能触发钥匙串 ACL 弹窗」一致）。

## 7. K1 / K2 / K3 执行协议（待执行）

前置：操作者在 Terminal 用 §5 的隔离环境启动 App，并在菜单栏点「启动服务」
（监听 `127.0.0.1:8000`，模型为 `SelectedEngine=llama.cpp` +
`LLaMModelPath` 指向的既有 GGUF 快照，只读）。

- **K1 结算消费**：真实模型生成并结算一条（记 `req-` 标签、墙钟、结算 ID）→ 把
  `…/run/cache/prefix-pool` 与 `…/run/cache/branch-checkpoints` 同时替换为普通文件
  （读 ENOTDIR、写 ENOTDIR）→ 新 ES 用 `settlement_consumption` 消费该结算，
  必须命中正确值且 `model_calls=0`、无新增模型生成结算行（允许派生/消费账行）。
- **K2 暂停恢复**：真实生成产生有效结算 → 触发 suspend、释放会话与模型 → 结束并
  重启 App 进程 → 恢复后经 ES/IS 取回结算值；若需继续生成，从有效逻辑锚点冷启动；
  恢复过程中不得依赖任何 KV 读写（两目录保持阻塞，前后盘点文件数不变）。
- **K3 中断重执行**：在 G 阶段中断真实模型调用 → 确认无有效结算、无孤儿状态、
  部分输出未进入下一次输入 → 重启后从最近合格锚点重执行 → 恰好一条有效结算；
  记录模型调用次数、结算写入次数、输入快照与恢复来源。

判据仍按裁定：**不以「结束后目录为空」替代证据**；以「两目录被阻塞 + 前后文件盘点
+ DB 计数（model_calls / 结算行 / 状态行）+ 逐字 HTTP 读数」共同构成证据。若后续
确需引擎级 KV IO 计数，只在隔离验收构建中加只读观测，不改生产路径语义。

## 8. 当前状态

- 已完成：阶段 1（证据身份与干净树重建）、阶段 2（全新隔离根回归 + 两配置 KV-free
  复跑，见测试层文档 §7）、阶段 3 的构建 / DMG / 签名 / 安装 / 基线 / 隔离根准备。
- **未完成**：K1/K2/K3 真实模型读数（阻塞于人工启动服务）。
- 未触碰：真实数据库、两个真实 KV 目录、两个真实库残留测试根
  （`work-00000000903bb636` / `work-0000000059acde6e`）、`7.VBA代码及实例`。
- #28 仍 pending；#30（测试 bundle 消失）仍 pending；无提交 / 推送 / 合并。

## 9. K1 真机读数（安装版 Release + 真实模型，隔离运行根）

探针：`/tmp/simigo-stage3-20261027-150733/k1_probe.py`（请求形状、trace 括号与目录
盘点逻辑逐字复用 B-7 探针 `b7-20261027-0338/b7_probe.py`，只改环境路径与阻塞技术）。
证据副本：`c6d-stage3-k1-20261027/`（`SHA256SUMS.txt`：results `b226c359…83731`、
probe `0a11ac90…c479e`、log `999b42ce…b8373`）。nonce `20261027-154642`。

### 9.1 事实

身份（窗口开始时读取）：pid `65911`，可执行文件
`9ba486976d56de2b8614c2cb8537e2253955084e438a18c428838913a53c1a30`，源码 HEAD
`97043902075b67eb1693749fd6ed50421eccf3ba`，模型 `peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX`，
环境三元组 `SIMIGO_HOME=/tmp/…/run/home`、`SIMIGO_CACHE_ROOT=/tmp/…/run/cache`、
`SIMIGO_STATE_GRAPH_STORE=/tmp/…/run/state-graph/reference-graph-v1.json`。
起始计数（隔离库）：`settlements=0 execution_states=0 settlement_bindings=0
settlement_consumptions=0 checkpoints=0 retrieval_settlements=0 is_objects=2`。

1. 工作根经产品原生入口注册：`POST /v1/simigo/roots` → 200
   `{"root_id":"work-000000004154195b","content_settle":{"scanned":2,"reused":2}}`。
2. 真实模型生成并结算一次：`POST /v1/chat/completions`
   （`session_id=k1-source-20261027-154642`，`max_tokens=96`）→ 200，18.720 s，
   输出 `K1-SETTLED-20261027-154642`；结算行
   `CD4DD747-417A-438C-9090-F639065E6B75` / `chat-184f3580-…`，
   `payload_digest_ok=true`，digest `5326b241835c8216…290b4`。
   该窗口 trace 逐字（节选）：

   ```
   15:46:48.203 [MLX] poolRescan entries=0
   15:46:48.204 [MLX] prefillStep=2048 est=32 reuse=false
   15:46:55.936 [MLX] prefill 238/238
   15:47:01.140 [MLX] poolExport messages=3 refHash=f99c3491371a6184
   15:47:01.180 [MLX] cacheSave session=154642/main history=3
   15:47:01.185 [MLX] session=154642/main … ttft=12105ms cacheHitTokens=0 …
   ```

   即：源生成窗口内引擎确实发生 KV 读写（`poolExport`/`cacheSave`），探针的
   生成行计数为 3。
3. 复用契约经产品原生 API 声明（scratch 工具 `build/b7/tools/declare-contract`，
   只调用 `declareSettlementReuseContract`，无手写 SQL）：
   demand digest == declaration digest == `260ffc4df103de1291e2e3042aced1d8…64fc`。
4. 阻塞两个 KV 载体（15:47:03 前完成）：把 `<run>/run/cache` 整体移到
   `isolation-cache/cache`，原位写一个普通文件（sha256
   `737f30a8725b344f1aabb234c12aadfb5f7986f9a923f3709ae5a8c4a0245989`）。
   探针在窗口开始与结束各独立探测一次，两路径四次全部：
   `listdir → NotADirectoryError(20, 'Not a directory')`，
   `makedirs → NotADirectoryError(20, 'Not a directory')`。
   阻塞期间的三个消费请求 trace 逐字：

   ```
   15:47:03.704 [PROTOCOL] arrive r=9ed7dc endpoint=responses …
   15:47:03.738 [LC] RELEASED r=9ed7dc s=respon reason=completed
   15:47:04.590 [PROTOCOL] arrive r=a61bf2 endpoint=responses …
   15:47:04.616 [LC] RELEASED r=a61bf2 … reason=settlement_consumption_refused
   ```

   消费窗口 195 字节，零 `[MLX]` 引擎行、零 KV 行；请求耗时 0.037 s / 0.035 s。
5. 消费读数（逐字关键字段）：`outcome=consumed`、`derived_settlement=true`、
   `model_calls=0`、`store=false`、`usage.input_tokens=0 output_tokens=0
   total_tokens=0 cached_tokens=0`、正文 `K1-SETTLED-20261027-154642`
   （与结算值逐字相等）、`consumer_es_state_id=es-96f924aa-…`、
   `consumer_settlement_id=C49392D7-…`。第二次请求同构，
   `A6335682-…` / `es-8c24a6eb-…`。
6. 拒绝控制（不存在的结算 id）：422
   `Settlement consumption refused: settlement … declared no reuse contract;
   it is not consumable`，`error_kind=SETTLEMENT_CONSUMPTION_REFUSED`，
   `reason_code=contract_undeclared`，零生成行 —— 证明阻塞期间准入链仍然在工作，
   而不是整条路径被跳过。
7. 三类计数（阻塞窗口内，逐项独立）：
   - 模型调用：响应字段 `model_calls=0`（两次）；落库列
     `settlement_consumptions.model_calls` = `0, 0`（合计 0）。
   - 结算写入：新增 2 行，`validation_status` 均为 `DERIVED_CONSUMPTION`，
     `contract_version=simigo.result-contract/v1`，`state_id=es-*`；
     **没有任何新的模型生成结算行**（源结算 `CD4DD747` 在阻塞之前）。
     计数增量：`settlements+2 execution_states+2 settlement_bindings+4
     settlement_consumptions+2 checkpoints+0 retrieval_settlements+0 is_objects+2`。
   - KV 文件 IO：阻塞期间 `prefix-pool`、`branch-checkpoints` 均不存在也造不出
     （四次 ENOTDIR）；在 `<run>` 全树与真实 `~/.simigo` 扫描同名节点，
     运行树内 0 处，真实家目录只有原有的两个目录本身。
8. 灵敏度对照（解除阻塞后，同一进程、同一探针）：一次真实生成
   （`session_id=k1-control-…`，1.572 s）后，`<run>/run/cache` 恢复为目录并出现
   `prefix-pool` 4 个文件 145,526,888 B（含 2 个 `.safetensors`）与
   `branch-checkpoints` 4 个文件；随后 K1 全部 KV 写入合计 139 MB + 139 MB。
   即：同一构建、同一盘点函数在允许写时会立刻出现大批 KV 文件——
   「阻塞期间 0 文件」是真实负例，不是探针不敏感。
9. 真实用户数据：`~/.simigo/prefix-pool`（mtime 10-26 19:06:22，1 项）、
   `~/.simigo/branch-checkpoints`（10-27 04:19:18，44 项）、
   `~/.simigo/simigo.sqlite3`（15:26:42）在窗口前后逐项相等。
   `isolation-cache` 中的原目录按「只移动、不删除」在结尾恢复。

判定：17/17 检查通过（`summary.failures=[]`）。

### 9.2 结论（仅 K1 范围）

安装版 Release 构建（`9ba4869…`，v2.2.0/29）在真实模型下，当
`prefix-pool` 与 `branch-checkpoints` 同时既不可读也不可写时，新 ES 仍能经
`/v1/responses` 的 `settlement_consumption` 取回指定结算的正确值，
`model_calls=0` 且响应 usage 全零，账本里只有派生/消费行、没有任何新的模型生成
结算行；准入拒绝链在阻塞期间仍然生效；没有任何 KV 被静默重定向到别处。

### 9.3 假设与限制

- 阻塞窗口约 2 s（15:47:03.0–15:47:04.9），源生成的 `poolExport` 在窗口前、
  对照生成的 `poolExport` 在窗口后，两次都在窗口外：单凭「窗口内 0 文件」不足以
  证明，因此本例以四次独立 ENOTDIR 读写探测 + `model_calls=0` 落库列 +
  trace 零引擎行 + 解除后同构建立即产出 278 MB KV 作为组合证据。
- 引擎级 KV IO 计数器仍不存在；本轮没有新增生产路径观测点，只用文件系统盘点与
  既有 trace 标签（`poolExport`/`cacheSave`/`poolRescan`）。
- 「同一进程内消费」不覆盖「跨进程重启后消费」，后者由 K2 承担。

## 10. K2 真机读数 · 阶段 A（生成 → 阻塞 → 空闲挂起）

探针 `k2_probe.py --phase a`（`--phase b` 在进程重启后跑）。nonce
`20261027-155850`；证据 `c6d-stage3-k2-20261027/`（results
`8021321055667344…494776`、trace `dea6a65b…90e2`、log `e460faf8…0a5f`）。

### 10.1 事实

1. 同一进程（pid `65911`，可执行 `9ba4869…`，源码 HEAD `9704390…`，模型
   `peculiar-ragdoll/Nail-Qwen3.6-35B-A3B-MLX`）真实生成并结算一次：
   `session_id=k2-source-20261027-155850` → 200 / 17.595 s，
   结算 `85D17085-C3C1-4C49-9882-759B60DE3C66` / `chat-a47f7deb-…`，
   `payload_digest_ok=true`，值 `k2-SETTLED-20261027-155850`。
   引擎侧同窗逐字：`poolExport messages=3 refHash=9f7fc14debed5d1f`、
   `cacheSave session=155850/main history=3`、
   `… mode=cold promptTokens=595 …`（生成行 3、KV 行 4）。
2. 复用契约经原生 `declareSettlementReuseContract` 声明，demand==declaration
   digest `40f19c4abf50ce54…`。
3. 15:59:10 把 `<run>/run/cache` 整体移入
   `isolation-cache/K2-155910/cache`（425 MB，原有 KV 全部保留、未删除），
   原位写普通文件（sha `737f30a8…45989`）。此后每 10 s 独立探测一次读写，
   两路径在 15:59:20 → 16:03:41 共 28 次采样全部
   `listdir=NotADirectoryError(20)` / `makedirs=NotADirectoryError(20)`，
   `prefix_pool_present=false`、`branch_checkpoints_present=false` 无一例外。
4. 空闲挂起确实发生：trace 自阻塞点起**逐字只有一行**
   `16:03:37.238 [LIFECYCLE] suspend_done`（距最后活动 269 s）。
   即：会话的最新逻辑提交仍是 dirty、而 branch-checkpoints 目录不可写时，
   生产构建仍然完成了 suspend，没有把「写不下去」变成「拒绝挂起」，
   也没有任何 `cacheSave`/checkpoint 写入成功行。
5. 资源释放读数：suspend 前该进程 footprint 约 21.6 GB（`afterLoad
   active=19781MB`）；`suspend_done` 后同一 pid 的 RSS 为 192,016 KB（约 188 MB），
   系统 PhysMem used 9.6 GB。模型驻留内存已释放。
6. 阻塞期间的账本增量（阶段 A 全程，含源生成与契约声明）：
   `settlements+2 execution_states+1 settlement_bindings+2
   settlement_consumptions+0 settlement_reuse_contracts+1 checkpoints+0
   retrieval_settlements+1 is_objects+5 chat_messages+2
   chat_execution_links+1 information_demands+1 information_advancements+1`；
   其中 `checkpoints` 表（逻辑检查点索引）增量为 0。
7. 真实用户数据逐项不变（`~/.simigo/prefix-pool` 10-26 19:06:22/1 项、
   `~/.simigo/branch-checkpoints` 10-27 04:19:18/44 项、
   `~/.simigo/simigo.sqlite3` 15:26:42）。

### 10.2 结论（阶段 A 范围）

在安装版 Release 构建 + 真实模型下，`prefix-pool` 与 `branch-checkpoints`
同时不可读、不可写时：真实生成照常完成并结算；空闲挂起照常发生并释放模型内存；
挂起过程没有产生任何 KV 落盘，也没有因写不下去而拒绝挂起。
这一条正面支持 C-6c 的裁定意图（脏会话不阻塞 suspend）。

### 10.3 待办

阶段 B 需要人工「退出并重启 App」（服务只能由用户在 GUI 会话里启动）。
重启后由 `k2_probe.py --phase b` 读取：产品 IS 面取回结算值、
`settlement_consumption` 零模型调用取回同值、同会话续跑必须冷启动而非 KV 恢复；
全程保持两目录阻塞，并在结束时按「只移动、不删除」恢复缓存目录。

## 11. K2 真机读数 · 阶段 B（进程终止并重启后，经 ES/IS 恢复）

`k2_probe.py --phase b`，pid 由 `65911` 变为 `72481`（17:17:43 启动，17:20:23 模型就绪）。
两目录自 15:59:10 起全程保持阻塞，重启后 `run/cache` 仍是同一普通文件
（70 B，sha `737f30a8…45989`，mtime 15:59:10）。

### 11.1 事实

1. 产品 IS 面读回结算：`GET /v1/simigo/is/settlement?id=85D17085-…` → 200，
   `validity=valid`、`validation_status=VALID`、
   `payload="{\"content\":\"k2-SETTLED-20261027-155850\"}"`、
   `payload_sha256=df468a3b2cc340d9…f892`（与阶段 A 记录的 digest 相同）、
   `bindings` 含 `producer.model_identity` / `producer.tokenizer_identity`、
   `dependencies` 指向 `is-retrieval:f33b1093…`。该窗口零 `[MLX]` 生成行。
2. 零模型调用消费：`POST /v1/responses` + `settlement_consumption` → 200 / 0.033 s，
   `outcome=consumed`、`model_calls=0`、`derived_settlement=true`、
   正文 = `k2-SETTLED-20261027-155850`、`consumer_es_state_id=es-fa1fe546-…`、
   `consumer_settlement_id=109943C4-…`、canonical digest `40f19c4abf50ce54…` 一致。
   trace 逐字：仅 `arrive` + `RELEASED reason=completed`，零引擎 KV 行。
   落库 `settlement_consumptions.model_calls=0`。
3. 同会话续跑（新进程、无内存会话、无持久 KV）：
   `POST /v1/chat/completions session_id=k2-source-20261027-155850` → 200 / 1.386 s，
   返回 `K2-CONTINUED-20261027-155850`（正确接上上一行），逐字 trace：

   ```
   17:20:58.026 [MLX] reuseMiss count=false fp=true prefix=false history=3 incoming=2
   17:20:58.712 [MLX] prefill 529/529
   17:20:59.396 [MLX] poolExportFailed err=… Code=512 "The file “cache” couldn’t be saved
                     in the folder “run”." NSFilePath=/tmp/…/run/cache
                     NSUnderlyingError=… Code=20 "Not a directory"
   17:20:59.396 [MLX] action=checkpointFailed key=155850/main err=同上
   17:20:59.396 [MLX] session=155850/main messages=2 exec=c78c24 history=3 delta=1
                     reuse=false ttft=748ms cacheHitTokens=0 cacheEff=0.00 mode=cold
                     promptTokens=529 …
   17:20:59.399 [LC] RELEASED r=a52bf2 s=k2-sou reason=completed
   ```

   要点：`history=3`（历史从 ES/IS 侧重新喂入）、`mode=cold`、`cacheHitTokens=0`、
   `reuseMiss … prefix=false`；两次 KV 写入尝试（prefix 导出、branch checkpoint）
   **都留下了失败行**，且请求仍正常完成并结算
   （新增 `3C8852A8-…` / `chat-95406a6c-…`，`validation_status=VALID`）。
   窗口内成功型 KV 行（`cacheLoad` / `poolBind` / `poolRescan entries=` /
   `checkpointSaved` / `poolExport messages=` 无 Failed）为 0 条。
4. 阻塞与旁路检查：阶段 B 起止各一次独立探测，两路径均
   `NotADirectoryError(20)`（读、写）；`run/cache` 保持普通文件；
   全树扫描在运行树内未发现任何 `prefix-pool` / `branch-checkpoints` 节点；
   真实 `~/.simigo/prefix-pool`、`branch-checkpoints`、`simigo.sqlite3` 前后逐项相等。
5. 账本增量（阶段 B 全程）：`settlements+3 execution_states+2
   settlement_bindings+4 settlement_consumptions+1 retrieval_settlements+1
   is_objects+3 chat_messages+2 information_demands+1 information_advancements+2`，
   **`checkpoints+0`**（逻辑检查点索引无新增）。

### 11.2 判据实现的两处修正（不放宽判据）

- 原 `is_read_returns_settled_value` 读的是响应顶层 `content` 字段，而产品把结算
  载荷放在 `payload` 的 JSON 字符串里；改为解析 `payload.content` 后与阶段 A 的
  结算值逐字比较。原始响应体完整保留在 results 文件中。
- 原 `continuation_no_kv_restore_lines` 把「出现 checkpoint 字样」判为失败，
  而真机出现的是 `action=checkpointFailed`（写失败）；判据收紧为
  「窗口内不得出现任何**成功型** KV 读写行，且所有 KV 相关行必须是失败行」，
  并新增 `continuation_kv_attempt_lines_all_failed`、
  `continuation_kv_write_attempts_present`、`continuation_cache_hit_tokens_zero`、
  `continuation_mode_cold` 四项正向检查。
- 修正只重算判据，不重发请求、不改任何原始读数：
  `results-K2b-20261027-155850-reevaluated.json`；
  首次尝试的断言异常文件另存为 `k2b-first-attempt-assertion-error.json`。
  复评结果 **22/22 通过，failures=[]**。

### 11.3 结论（K2 范围）

真实模型生成并结算后终止进程、重启 App，且 `prefix-pool` 与
`branch-checkpoints` 在整个过程中既不可读也不可写时：安装版仍能经产品 IS 面读回
结算值、经 `settlement_consumption` 以 `model_calls=0` 取回同值，并让同一会话的
续跑从 ES/IS 逻辑锚点冷启动完成并结算；KV 写入尝试全部失败且被如实记录，
没有变成执行失败，也没有被静默重定向。

## 12. K3 真机读数 · 阶段 A（G 阶段中断）

`k3_probe.py --phase a`，pid `72481`，会话 `k3-source-20261027-172339`，
两目录仍处阻塞（`block_enforced_at_end=true`）。

### 12.1 事实

1. 合格锚点：真实生成并结算 `3FD020EE-561B-4297-AAD2-7633AC60F98E`
   / `chat-fd19d64a-…`，值 `k3-SETTLED-20261027-172339`，`payload_digest_ok=true`。
2. 中断：同一会话发起流式生成（要求逐行输出 `INT-A01…INT-A30`，
   `max_tokens=400`），收到 8 个 SSE 增量（11 字符 `INT-A01-202`）后用
   `SO_LINGER(1,0)` 硬关连接（RST）。1.862 s 内完成，逐字 trace：

   ```
   17:23:46.057 [MLX] prefill 1182/1182
   17:23:46.323 [PROTOCOL] peerClosed r=7d89e4
   17:23:46.323 [CANCEL] r=req-7d89e426
   17:23:46.323 [MLX] cancelCommitSkip session=172339/main history=1 rawEv=8 rawB=11 emitB=11
   17:23:46.323 [LC] STATE_TRANSITION … RUNNING to=CANCELLING
   17:23:46.324 [LC] STATE_TRANSITION … DRAINING to=RELEASING
   17:23:46.324 [LC] RELEASED r=7d89e4 s=k3-sou reason=cancelled_by_client
   ```

   `cancelCommitSkip` 是引擎自己的判定：未完成的 8 个增量 / 11 字节不提交。
3. 无有效结算：中断后即时与 +3 s 两次读取账本，
   `validation_status=VALID` 的行只有此前已结算的 7 条
   （K1 源/对照、K2 源/两次续跑、K3a 中止残余项、K3a 锚点），
   中断那一轮**没有产生任何结算行**；`checkpoints+0`、
   `settlement_consumptions+0`。整段增量
   `settlements+3 execution_states+1 chat_messages+3 retrieval_settlements+2
   is_objects+7 information_demands+2 information_advancements+1`
   全部归因于锚点生成与 IS 检索，而非中断输出。
4. 部分输出未进入会话记录：该会话 `chat_messages` 只有 3 行
   （锚点 user、锚点 assistant、中断 user），
   其内容对象逐字为 `只输出这一行，不要解释：k3-SETTLED-…`、
   `k3-SETTLED-20261027-172339`、
   `请逐行输出编号序列 INT-A01-… 到 INT-A30-…`；
   **没有任何 assistant 行携带 `INT-A01-202` 这段残片**。
5. KV 面：中断窗口内零 KV 成功行（`kv_lines=[]`，只有 prefill 两行生成记录）；
   窗口末两次探测仍是 `NotADirectoryError(20)`；运行树内无同名节点。
6. 探针自身的一次失败已如实保留：首次 `--phase a` 在记录阶段因 JSON 无法序列化
   BLOB 而崩溃（`TypeError: Object of type bytes is not JSON serializable`），
   该次已发出的请求在库里留下锚点 `F50752CB-…`（`chat-8fc8914a-…`）与一条
   中断 user 行、同样没有 assistant 残片行；修复只在探针的序列化里加 bytes 解码，
   不改任何判据，随后按同一探针重跑得到本节读数。

### 12.2 待办

阶段 B 需要第二次人工重启：重启后按同一会话重发被中断的需求，
必须从最近合格锚点重执行并恰好产生一条 `VALID` 结算；
判据包括新输入快照内不含残片、`cacheHitTokens` / KV 成功行为 0、
模型调用次数与结算写入次数逐项计数，结束时按「只移动、不删除」恢复缓存目录。

### 12.3 K3 阶段 B（第一次重启后，pid 74450）：核心成立，两处探针缺陷导致 2 项红

进程与阻塞面：pid 74450（17:36:33 起，env 三件套正确，17:36:48 `[READY]`），
`run/cache` 仍是 70 B 普通文件（sha `737f30a8…45989`），加载即出现
`[STORAGE] branchRetentionFailed err=The file “cache” couldn’t be saved in the folder “run”.`，
读写探测仍为 `NotADirectoryError(20)`。

重执行窗口 `rerun-from-anchor`（同会话 `k3-source-20261027-172339`、同需求、17:38:06→17:38:29，200，22.523 s）逐字行：

```
[MLX] prefillStep=2048 est=427 reuse=false
[MLX] prefill 1267/1267
[MLX] poolExportFailed err=… Not a directory …
[MLX] action=checkpointFailed key=172339/main err=The file “cache” couldn’t be saved in the folder “run”.
[MLX] session=172339/main messages=2 exec=c0e920 history=3 delta=1 reuse=false ttft=11230ms cacheHitTokens=0 cacheEff=0.00 mode=cold promptTokens=1267 promptTime=11.1s tps=35.5 rawEv=400 rawB=459 emitB=459
[LC] RELEASED r=f0739a s=k3-sou reason=completed
```

账本增量（三张计数器分列）：`settlements +2`（1 条 `VALID` `29B566C3-F9F6-4AB5-8048-D407AE6443E8`
（state `chat-fd569524-…`）+ 1 条 `IS_RETRIEVAL`）、`settlement_consumptions +0`、
`checkpoints +0`、`execution_states +1`、`chat_messages +2`、`is_objects +4`、
`information_demands +1`、`information_advancements +1`；KV 文件写入 0，目录内无新节点，无重定向。
12 项判定 10 通过，失败 2 项均属探针实现：

1. `rerun_complete_sequence`：请求由探针给了 `max_tokens=400`，而 30 行需约 600+ token；
   输出为 `INT-A01-…` 至 `INT-A19-…` 加一个断在 `INT` 的第 20 行，`rawEv=400` 正好撞满预算。
   属探针预算不足，判据本身未改。
2. `partial_never_entered_new_input`：残片 `INT-A01-202` 是合法编号项 `INT-A01-<nonce>` 的**严格前缀**，
   任何子串包含式判定都必然假阳。已把该判据改成三条更强的形式：
   残片不等于任何已存消息内容、从输入文本中剔除全部合法编号项后残片不出现、
   且引擎自报的 `history=` 与重执行前已存消息行数相等。

同时到手的正证：新执行输入为 `history=3`（锚点 user、锚点 assistant、被中断的 user），
`mode=cold cacheHitTokens=0`，无 `cacheLoad`/`poolBind`/`checkpointRestored` 成功行，
恰有一条新 `VALID` 结算——即第一次 b 窗口已满足 K3 的重执行核心，只是序列完整性受探针预算遮蔽。

### 12.4 修正复跑 `--phase b2`（同一探针，仅预算与残片判据修正；16/17）

全新会话 `k3-source-20261027-174333`：锚点 `1A990589-82D6-4E26-ADCC-79B648D87212`
（值 `k3-SETTLED-20261027-174333`）→ 流式硬断 8 个增量，残片 `INT-A01-202` →
中断后 `new_valid_rows_from_interrupt=[]` → 同会话同需求以 `max_tokens=1200` 重执行
（200，19.282 s）。

- `rerun_items_in_output = 30/30`：**完整 30 行序列成立**。
- `exactly_one_new_valid_settlement = true`：`DAB3D7F6-C812-462E-B9E7-165B5BCC9E5D`
  （state `chat-e7ef75ff-…`，`VALID`）+ 1 条 `IS_RETRIEVAL`。
- `partial_never_entered_new_input = true`（三条更强判据全通过），`rerun_history = "3"`
  与重执行前已存 3 行相等。
- KV 面：`rerun_no_kv_restore_lines = true`、`rerun_cache_hit_tokens_zero = true`、
  目录零新节点、无重定向、真实 `~/.simigo` 前后相等。
- 账本增量：`settlements +5`、`chat_messages +5`、`settlement_consumptions +0`、`checkpoints +0`。

唯一未通过项 `rerun_mode_cold = false`，逐字读数给出原因：

```
[MLX] session=174333/main messages=2 exec=0fbd51 history=3 delta=1 reuse=true ttft=1647ms cacheTokens=1499 cacheHitTokens=0 mode=rebuild promptTokens=1575 promptTime=1.6s tps=35.7 rawEv=629 rawB=719 emitB=719
[MLX] poolTokenExportFailed count=2 first=2048 last=2205 err=… Not a directory …
```

`b2` 的中断与重执行落在**同一进程**（74450）内，因此引擎复用了进程内 KV 缓冲并以
`mode=rebuild` 重建（`cacheTokens=1499`），但 `cacheHitTokens=0`、磁盘快照导出失败
（`poolExportFailed` / `poolTokenExportFailed` / `checkpointFailed`）。
结论：把断言写成 `mode=cold` 这个**标签**过窄；K3 要证的是「不依赖持久化 KV」，
正确判据是 `cacheHitTokens=0` + 零条 KV 读取/恢复成功行 + 零 KV 文件写入。
进程内 KV 属可随进程消亡的工作内存，与用户的 KV 裁定不冲突（裁定只禁止持久化 KV 成为前提）。

### 12.5 全周期窗口 `--phase c`（中断半程，同进程 74450，7/7 全通过）

会话 `k3-source-20261027-174605`，锚点 `44D692B6-1846-468C-93E5-8E7542B16DF0`
（值 `k3-SETTLED-20261027-174605`，200 / 2.273 s）。流式硬断 8 个增量，残片 `INT-A01-202`；
中断后 `new_valid_rows_from_interrupt=[]`，`settlement_consumptions +0`、`checkpoints +0`，
`settlements +3`（锚点生成与 IS 检索）；阻塞面全程成立、目录零新节点、真实 `~/.simigo` 前后相等。

阶段 `c2` 待第三次人工重启后执行：新进程内以 `max_tokens=1200` 重发同一需求，
判据为完整 30 行、恰一条新 `VALID`、`cacheHitTokens=0`、零 KV 成功行、
`history=` 与重启前已存行数相等、残片三条判据通过、`mode` 读数如实记录不作假设。

### 12.6 全周期窗口下半程 `--phase c2`（第三次人工重启后，pid 76140，15/15 全通过）

身份：旧进程 74450 → 新进程 76140（17:47:32 起，env 三件套正确，17:47:43 `[READY]`）；
`run/cache` 仍是那个 70 B 普通文件（sha `737f30a8…45989`），读写探测仍 `NotADirectoryError(20)`。
被中断的需求在**新进程内**重发（`rerun-after-restart-adequate-budget`，同会话
`k3-source-20261027-174605`、同 prompt、`max_tokens=1200`，17:48:05→17:48:29，200，23.251 s）：

```
[MLX] sessionClientSplit key=174605/main#33caca5f note=system-prompt client shard
[MLX] prefillStep=2048 est=614 reuse=false
[MLX] prefill 1885/1885
[MLX] poolExportFailed err=Error Domain=NSCocoaErrorDomain Code=512 "The file “cache” couldn’t be saved in the folder “run”." … Code=20 "Not a directory"
[MLX] poolTokenExportFailed count=2 first=2048 last=2515 err=… "Not a directory"
[MLX] action=checkpointFailed key=174605/main err=The file “cache” couldn’t be saved in the folder “run”.
[MLX] session=174605/main messages=2 exec=0a467f history=3 delta=1 reuse=false ttft=5514ms cacheHitTokens=0 cacheEff=0.00 mode=cold promptTokens=1885 promptTime=5.4s tps=35.5 rawEv=629 rawB=719 emitB=719
[LC] RELEASED r=eca7b1 s=k3-sou reason=completed
```

判据逐项（15/15）：

| 判据 | 读数 |
|---|---|
| `process_restarted` | 74450 → 76140，单实例 |
| `rerun_200` / `rerun_model_work_recorded` | 200 / 23.251 s；`prefill 1885/1885`、`ttft=5514ms`、`tps=35.5` |
| `rerun_complete_sequence` | 输出 719 B，首行 `INT-A01-20261027-174605`、末行 `INT-A30-20261027-174605`，30/30，`finish_reason=stop` |
| `exactly_one_new_valid_settlement` | 新行 2 条：`3B308189-8EB3-4018-A5D2-CCA5AE0CA3CB`（`VALID`，state `chat-09963382-…`）+ 1 条 `IS_RETRIEVAL` |
| 恢复来源 | `reuse=false`、`mode=cold`、`cacheHitTokens=0`、`history=3` 恰等于重启前已存 3 行（锚点 user/assistant + 被中断 user） |
| KV 读 / 恢复 | `rerun_no_kv_success_lines`：零条 `cacheLoad`/`poolBind`/`poolRescan entries=`/`checkpointSaved`/`checkpointRestored`/`poolExport messages=`/`cacheSave` 成功行 |
| KV 写尝试 | `rerun_kv_write_attempts_all_failed`：`poolExportFailed` + `poolTokenExportFailed count=2` + `action=checkpointFailed`，全部 `NotADirectoryError(20)` |
| 残片不混入 | `partial_never_entered_new_input`：残片 `INT-A01-202` 不等于任何已存消息内容；剔除全部合法编号项后残片不出现；assistant 侧仅锚点值一行 |
| KV 目录 | `prefix-pool`/`branch-checkpoints` 节点均不存在；运行树内无重定向 KV 文件 |
| 真实数据 | `real_home_before == real_home_after`（`~/.simigo/prefix-pool`、`branch-checkpoints` 未被触碰） |
| 阻塞成立 | 起止两端均 `enforced`（读写双向 `NotADirectoryError`） |

账本增量（三张计数器分列）：`settlements +2`、`settlement_consumptions +0`、`checkpoints +0`、
`execution_states +1`、`settlement_bindings +2`、`chat_messages +2`、`is_objects +4`、
`retrieval_settlements +1`、`information_demands +1`、`information_advancements +1`；
模型生成 1 次（重执行本身），KV 文件 I/O 写入尝试 3 次全失败、落盘 0 字节。

### 12.7 K3 结论

事实链完整：G 阶段被 RST 硬断的真实生成（8 个增量 / `cancelCommitSkip`）**不构成有效结算**
（`new_valid_rows_from_interrupt=[]`、残片从未进入任何消息对象）；进程终止并重启后，
同一需求从最近合格锚点冷启动重执行，产生**恰好一条** `VALID` 结算，
且整个重执行路径上持久化 KV 既读不到也写不下。未完成输出没有混入新执行。

## 13. 第二次重启过程中的一条真实观测（阻塞态 ≠ 开关关闭）

### 13.1 事实

1. `run/home/logs/native_mlx_trace.log` 在 K3 阶段 A 之后连续三条空闲挂起尝试被拒：

```
[2026-10-27 17:28:11.673] [LIFECYCLE] suspend_blocked_dirtyCheckpoint key=172339/main err=The file “cache” couldn’t be saved in the folder “run”.
[2026-10-27 17:28:41.804] [LIFECYCLE] suspend_blocked_dirtyCheckpoint key=172339/main err=The file “cache” couldn’t be saved in the folder “run”.
[2026-10-27 17:29:12.286] [LIFECYCLE] suspend_blocked_dirtyCheckpoint key=172339/main err=The file “cache” couldn’t be saved in the folder “run”.
```

2. 直到人工停止服务才释放：`17:29:39 beforeUnload active=20199MB` → `17:29:41 settled active=0MB … footprint=161MB`、`NativeMLX stopped`。
3. 同一被阻塞的缓存路径下，阶段 K2a 结束后的 `16:03:37` 曾出现 `[LIFECYCLE] suspend_done`，即**并非阻塞态一律无法挂起**；差别在于会话是否携带未落盘的脏 checkpoint。
4. K3 的脏态来源可追溯到 `17:23:42` 该会话完成轮的写入失败：
   `[MLX] poolExportFailed … NotADirectoryError`、`[MLX] action=checkpointFailed key=172339/main`。

### 13.2 结论

- 「缓存路径被阻塞（读写 ENOTDIR）」与「`SIMIGO_BRANCH_CHECKPOINTS=0`」不是同一状态：
  开关为默认 ON 而路径不可写时，产品保留原有语义——脏会话反复重试写入、拒绝挂起、模型常驻约 20 GB。
- 本轮 K1/K2/K3 的「无 KV 依赖」读数均在此语义下取得：ES/IS 消费、暂停后恢复、中断后重执行都不依赖 KV 写入成功；
  代价是**资源释放**要等到人工停止服务，属可观测的次优行为而非正确性缺陷。

### 13.3 假设与限制

- 假设：若把 `SIMIGO_BRANCH_CHECKPOINTS=0` 作为产品默认，脏会话应被直接释放而非反复重试；
  该行为已由用户在授权项 (1) 中规定，但本轮未在产品层验证（本轮刻意不改默认开关值，
  以保持与已安装 Release 的真实语义一致）。是否据此调整默认值仍属**待裁定**，本轮不做代码改动。

## 14. 环境收尾（事实）

- 恢复手段：`python3 k2_probe.py --unblock`。脚本先校验 `run/cache` 仍是普通文件且
  sha256 与 `block-state.json` 记录的 `737f30a8…45989` 一致，再把
  `isolation-cache/K2-155910/cache` **移动**回 `run/cache`。
  用户侧 KV 数据全程只移动、未删除；被删掉的只有探针自己创建的 70 B 标记文件，
  且在删除前已完成摘要校验，标记原文与摘要保留在 `stage3_common.BLOCK_MARKER`、
  本文 §9 与 `block-state.json.restored.json` 中。
- 恢复后：`run/cache` 为目录，`prefix-pool` 6 个文件 / 222,580,888 B
  （listing sha256 `be88cdf62c68172d6ffe662ae5de0b909c94c44a0fc97fedaa8f3f838b9bb479`），
  `branch-checkpoints` 约 212 MB；`isolation-cache/K2-155910` 留下空目录，未删。
  `block-state.json` 改名为 `block-state.json.restored.json`（含 `restored_at`、
  `restored_original=true`、恢复后目录快照）。
- 真实用户数据收尾核验（与安装前基线一致）：`~/.simigo/prefix-pool` mtime
  10-26 19:06:22 / 1 项，`~/.simigo/branch-checkpoints` mtime 10-27 04:19:18 / 44 项；
  本轮所有读写探测、K1/K2/K3 三次重启均未写入真实根。
- 进程收尾：验收结束时安装版实例为 pid 76140（第三次重启拉起，仍在运行），
  8000 端口监听正常；未由本代理自动清理任何用户数据。
- 证据归档（产品仓 `research/agent-runs/simigo-es-is-realmodel-20261026/`）：
  `c6d-stage3-k1-20261027/`、`c6d-stage3-k2-20261027/`、`c6d-stage3-k3-20261027/`
  （探针源码、逐案 results JSON、运行日志、账本快照、恢复记录，各带 `SHA256SUMS.txt`）。

## 15. 阶段 4：产品层裁定建议

### 15.1 事实

| 案 | 覆盖的生命周期环节 | 结果 |
|---|---|---|
| K1 | 结算消费（新 ES 消费已命名结算） | 17/17 通过；`model_calls=0`、`derived_settlement=true`、usage 全零、无新生成结算行；含灵敏度对照（解除阻塞后同一探针能看见生成行与 KV 写入） |
| K2 | 暂停 → 释放 → 进程终止并重启 → 经 ES/IS 恢复 | 阶段 A（真实生成 + `suspend_done`）+ 阶段 B 22/22（两处判据实现修正见 §11.2，原始读数未改）；续跑窗口 `poolExportFailed` + `action=checkpointFailed` 与 `mode=cold cacheHitTokens=0` 同行出现 |
| K3 | G 阶段真实调用被 RST 中断 → 重启 → 从最近合格锚点重执行 | 全周期窗口 `c`(7/7) + `c2`(15/15)：中断不构成有效结算、残片从未落库、重启后 30/30 完整序列、恰一条新 `VALID`、`reuse=false mode=cold cacheHitTokens=0`、KV 写尝试 3 次全失败、零 KV 恢复成功行 |

三案的 KV 面证据均为**读写双向**同时失效（`NotADirectoryError(20)`）且每个采样点独立复探，
不以「结束后目录为空」作为唯一证据。

### 15.2 结论（可升级的表述）

在这一份具体构建（HEAD `9704390…`、二进制 `9ba48697…c1a30`、DMG `eb952b55…2700`）
与这一套真机环境（安装版 Release + 真实 MLX 模型 + 隔离运行根）上，
**已证明 SimiGo 在 `prefix-pool` 与 `branch-checkpoints` 都无法读写时，仍能完成
结算消费、暂停恢复、中断后重执行三类环节**；该结论不再只是「测试层支持」。
按用户的升级口径，本轮满足「三案全通过」的前置条件。

限定：本轮**不**裁定默认关闭持久化。`SIMIGO_BRANCH_CHECKPOINTS` 仍为默认 ON，
本轮验收恰恰是在默认 ON 且路径被阻塞的语义下取得的。

### 15.3 假设与未执行清单

- U1：本轮用「路径阻塞」模拟 KV 不可用，不等于 `SIMIGO_BRANCH_CHECKPOINTS=0`
  的开关语义（开关关闭时应完全不创建/不读/不写/不恢复）。开关语义目前只有测试层读数；
  产品层开关关闭态的复跑**未执行**。
- U2：默认值是否改为关闭持久化 —— 属 owner 裁定，未做代码改动。
- U3：§13 记录的「脏会话 + 路径不可写 → 反复拒绝挂起、模型常驻约 20 GB」是否要修
  （即写失败时是否应释放会话而非重试）—— 属 owner 裁定，未做代码改动。
- U4：单模型（35B-A3B MLX）、单机 32 GB、单构建身份；换构建需按「同一源码 ≠ 同一个二进制」
  重新取证。
- U5：K3 的支持窗口（§12.3/§12.4）里两处判据缺陷已在文中逐字保留并说明修正方式；
   canonical 读数为 §12.5/§12.6，未用支持窗口替代。

### 15.4 GO / NO-GO

- C 阶段：按用户口径**停止扩展**设计与功能范围，已完成代码保留在隔离环境，不再前推。
- 阶段 B：保持 **GO**（真机读数已在先期 §3.x 与本文档 K1 中一致）。
- 任务 #28、#30：仍为待办，本轮未触碰。
- 提交 / 推送 / 合并：**未执行**（按裁定）。
