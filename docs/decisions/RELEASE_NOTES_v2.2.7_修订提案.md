# RELEASE_NOTES_v2.2.7.md 修订提案（局域网 / API 段落）

> 用途：替换或插入到 `docs/releases/RELEASE_NOTES_v2.2.7.md`。只动网络与凭证相关的三处，其余章节未改。
> 依据：`InferenceNodeCfg.swift`、`HTTPServer.swift`（bind/监听/路由权限/证明校验）、`LOCALBHostBootstrap.swift`、`LOCALBRegistryStore.swift`、`LOCALBPairingCoordinator.swift`、`docs/decisions/TRUST_BOUNDARY_SINGLE_USER_VS_MULTI_USER_20261112.md`。

---

## A. 替换 §4.6 里「本地 HTTP」这一条

- **本地 HTTP**（默认 8000）：默认只绑定回环 `127.0.0.1`，仅本机可访问。
- 路由：`/health`、`/v1/models`、`/v1/chat/completions`、`/v1/completions`、`/v1/responses`、
  `/v1/branches/{fork,list,delete}`、
  `/v1/simigo/{env,roots,search,is/{status,settlement,dependency,file,object,reconcile}}`、`/mcp`。
  未列出的路由一律拒绝（fail-closed）。
- 每条路由有固定权限：推理 → `P-INFERENCE`；检索、根目录、`/mcp` → `P-SRS-WRITE`；
  结算 / 依赖 / 对象 / 状态读 → `P-INFO-READ`；分支三条 → `P-BRANCH-CONTROL`。
- 回环明文连接对 `P-INFERENCE` / `P-INFO-READ` / `P-SRS-WRITE` 免签名证明，响应带
  `unprotected-by-LOCALB`。`P-BRANCH-CONTROL` 不在此列：分支操作在任何传输上都要走完整的
  challenge → 签名 → 消费流程。

## B. 新增 §4.6.1 局域网模式与调用凭证

- **开关**：菜单可切「局域网」模式，生效后绑定 `0.0.0.0`，并通过 Bonjour（`_http._tcp`）广播服务名。
- **传输**：非回环连接上的明文一律被拒（在监听层拒绝，不是策略层放行后再拦）；必须走 TLS。
  明文连接不具备任何配对 / 证明资格。
- **凭证**：受保护路由的请求必须携带
  `x-simigo-localb-client-key-id`、`x-simigo-localb-challenge`（32 字节）、
  `x-simigo-localb-proof-v2`（64 字节签名）。服务端先确认传输是 TLS，再查客户端公钥注册表，
  最后按路由权限表裁决；权限从不取自请求头、查询参数或 JSON 字段。
- **注册表**：客户端公钥的登记是追加式账本（`.localb-registry.events`）加一份离线 checkpoint
  （`~/.simigo/localb/trusted-checkpoint.json`）；可登记、可改状态（`ACTIVE` / `REVOKED`），
  凭证带过期与 TLS SPKI 钉。
- **本版的实际范围**：产品路径目前只登记宿主自举生成的那一把客户端键（`LOCALBHostBootstrap`，
  generation 1），首次激活还需要在库外记录 checkpoint。**给第二台设备发证需要往注册表追加一把
  新公钥，本版没有对应入口。** 因此局域网 API 当前的可用范围是「持有这份已登记密钥材料的客户端」。
- **信任前提**：单机、单人、局域网可信。开放局域网等于把你的信息空间对能证明身份的那台机器
  开放可读（`P-INFO-READ`）与可写（`P-SRS-WRITE`）。放不放、放给谁，由你决定并自担。

## C. §七 已知限制 增补两条

- 局域网模式下，为第二台设备登记客户端公钥没有产品入口；本版只登记宿主自举那一把键。
- 局域网模式未做端到端验证（TLS 握手、Bonjour 发现、签名证明消费）；本机回环路径不受影响。

## D. 一句话口径（可用于部署 / 安全说明）

> 默认只监听本机。需要给局域网内其他设备用时切「局域网」模式：它绑定 `0.0.0.0`、广播服务名、
> 强制 TLS，明文在非回环被拒；调用方必须持有已登记的客户端公钥并完成签名证明。放谁进来由你
> 决定，也由你承担。
