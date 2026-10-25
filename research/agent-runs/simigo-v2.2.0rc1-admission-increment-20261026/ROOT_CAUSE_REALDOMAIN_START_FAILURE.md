# v2.2.0 候选真实域启动失败根因报告 — LOCALBStatus error 59

日期：2026-10-26 01:37（用户报告）/ 01:5x（根因定位）
现象：新候选（exe `05164812…`，cleanroom @ `c97f016`）真实域启动，模型加载前失败：
`启动失败: The operation couldn't be completed. (LOCALBCore.LOCALBStatus error 59.)`

## 1. error 59 的身份

`LOCALBStatus` 为 String-rawValue enum，桥接 NSError 时 code = case 序号。
逐 case 计数：index 59 = **`transportIdentityMismatch`**（`LOCALB_TRANSPORT_IDENTITY_MISMATCH`）。

## 2. 实际抛出分支（不是"错配"，是"拒绝"）

`LOCALBTransportIdentityStore.verifyDeliveryChain`（`…Store.swift:617-623`）：
`SecKeyCopyPublicKey(secKey)` 失败 → `transportIdentityMismatch`。

独立只读探针（`/tmp/localb_identity_probe.swift` + `acl_probe.swift`，真实域、零写入）实测：

| 步骤 | 结果 |
| --- | --- |
| index 读取（`com.simigo.localb-transport-identity`） | **OK**：generation=1、keyTag 97B、cert DER 363B |
| 私钥查找（kSecClassKey + tag） | **OK**（status=0，条目存在） |
| `SecKeyCopyPublicKey` | **FAIL：OSStatus -25293 `CSSMERR_CSP_OPERATION_AUTH_DENIED`** |
| 私钥导出 | 同 -25293（ACL 拒绝） |
| （参照）`SecIdentityCreateWithCertificate` | 本进程 OK（不影响结论：失败点在更早的公钥读取） |

## 3. 根因链（每步有证据）

1. **2026-10-16 14:23:56Z**（keychain `cdat`），B3-closure 期的某个 dev/adhoc 构建在**真实登录 keychain** 创建了生产 transport identity（generation=1），私钥条目 ACL 绑定**创建者二进制的 code signature**。
2. 342c7ec 的 scoped 文件 keychain 只作用于**隔离根**（`SIMIGO_HOME`）；生产默认路径（`keychainPath == nil`）仍走登录 keychain（`resolveKeychain` 直接 return nil 旁路，代码语义确认）。
3. RC 线全部验证均在隔离根完成（service-http 门、isolated suite、os-page-return…）——**真实域首启从未被任何 RC 候选执行过**（RC1 GUI 门 BLOCKED 的直接后果）。
4. 任何与创建者**不同签名**的二进制（每个 adhoc 重签构建：83a880、05164812、未来的 RC2/RC3…）在真实域执行 `SecKeyCopyPublicKey` 都会被 ACL 以 -25293 拒绝 → fail-closed error 59。**这是结构性缺口，不是 admission increment 的回归**（该提交线不触碰 LOCALB）。

## 4. 附带发现（独立卫生问题）

真实登录 keychain 存在 **~3609 条 `com.simigo.*` 测试泄漏条目**（`com.simigo.tests.localb-transport.<UUID>#tls#key/cert`、`com.simigo.headless.g1g3.rc1/rc2.*` 等多批），累计自历次单测/headless 轮在真实域运行。泄漏面大，建议纳入清理项（独立于本根因）。

## 5. 修复方向（owner 裁定项；未实施）

- **A（推荐候选）**：把 342c7ec 已有的 scoped 文件 keychain 机制推广到生产默认路径——identity 存用户域文件库（0600），摆脱登录 keychain per-signature ACL；安全性等价论证与实现先例都在仓内。改动集中、有测试。
- **B**：创建时用 `SecAccess` 放宽到 any-app —— 弱化边界，不推荐。
- **C**：operator 管理入口增加真实域 identity 重建子命令（删旧建新）——每次换构建都需重做，治标。
- **D（用户即时恢复，破坏性、自行决定）**：删除真实域 4 条生产 identity 条目后重启，`loadOrCreate` 将重建且 ACL 归属当前二进制：
  ```
  security delete-generic-password -s "com.simigo.localb-transport-identity" ~/Library/Keychains/login.keychain-db
  # 及对应 #tls-identity-v1#key#g1#aef2663f2… 私钥 / #cert… 证书两条（可用 Keychain Access 检索 "localb-transport" 删除）
  ```
  注意：旧版生产 App（v2.1.x）不使用 LOCALB，不受删除影响。

## 6. 证据文件

- 探针源码与输出：`/tmp/localb_identity_probe.swift`、`/tmp/acl_probe.swift`（真实域只读）
- keychain 快照命令输出（本报告 §2/§4）
- 候选身份：`simigo-v2.2.0rc1-admission-increment-20261026/evidence/install_identity_admission_candidate.json`
- 隔离根对照（新候选 identity 链路正常）：`…20261026/evidence/gate_ai/service_http_gate_verdict.json`（S1 授权 200 = 隔离根下建立+TLS 全通）
