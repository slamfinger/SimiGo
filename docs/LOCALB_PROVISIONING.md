# LOCALB 生产激活（Provisioning）流程

状态：随 PR #14 闭合（2026-10-16）。设计事实：激活要求**外部记录的
checkpoint 与注册表头字节相等**（`LOCALBHostBootstrap.activateInitialSetup`
的常量时间比对）——外部记录本身就是信任锚，因此激活不自动接线进普通
启动，而是走本流程的产品自带运维入口。

## 入口

app 二进制上的启动参数模式（UI 启动前同步执行后退出）：

```bash
APP=SimiGo.app/Contents/MacOS/SimiGo

# 1) 首跑仪式：创建钥匙串签名密钥、TLS 传输身份、注册表谱系第一代；
#    输出待记录的 checkpoint JSON（不落 operational 状态）。
$APP --localb-prepare

# 2) 操作者把输出 JSON 记录到 SimiGo 之外的受信任位置（密码管理器/
#    运维台账），再回填激活：
$APP --localb-activate <recorded.json>

# 3) 可重复核查（随时）：
$APP --localb-status
#    → activated lineage=… sequence=… signer=… spki=…  （已激活）
#    → not-activated                                    （未激活）
```

激活成功后，`~/.simigo/localb/trusted-checkpoint.json` 落盘（原子写、
文件保护）；此后每次启动 `LOCALBHostRuntime.applyDefault` 自动把传输
身份与请求授权接上（operational 态）。未激活时保护路由 fail-closed。

## 失败语义（fail-closed）

- `--localb-activate` 的记录与注册表头不一致（篡改/过期/错谱系）→
  报错退出，**不落盘**；
- 已有非空注册表目录再跑 `--localb-prepare` → `registryAlreadyInitialized`
  （既有文件不静默当首跑；恢复需显式处理）；
- 普通启动对「损坏的 checkpoint 文件」报错，不回退成未激活态。

## 可重复验证

- 机器形态：`SimiGoTests/LOCALBProvisioningWiringTests`（临时目录内
  完整跑 prepare→activate→落盘→resolveOperational，含篡改拒绝）。
- 手工形态：`--localb-status` 在激活前后各跑一次。

## 边界

- 本流程管理 host 侧激活；客户端配对（pairing）由配对流程另行处理。
- 钥匙串与传输身份的生命周期规则见 `LOCALBHostBootstrap`（普通启动
  只 loadExisting，绝不创建/轮换）。
