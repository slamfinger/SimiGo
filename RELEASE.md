# 当前发布记录：SimiGo v2.2.7 (3)

本文是**当前**可下载产物的身份与安装形态记录。发布说明正文在
[docs/releases/RELEASE_NOTES_v2.2.7-3.md](docs/releases/RELEASE_NOTES_v2.2.7-3.md)，
产品能力见该文件与 [v2.2.7 说明](docs/releases/RELEASE_NOTES_v2.2.7.md)。

历史候选构建的身份记录已移到
[docs/releases/HISTORICAL_CANDIDATE_v2.2.4-34.md](docs/releases/HISTORICAL_CANDIDATE_v2.2.4-34.md)，
不再代表当前产物。

## 产物身份

| 项 | 值 |
| --- | --- |
| Release | [SimiGo v2.2.7 (3)](https://github.com/slamfinger/SimiGo/releases/tag/v2.2.7-3)（Latest） |
| tag | `v2.2.7-3` → 提交 `eac5b29` |
| 文件 | `SimiGo-v2.2.7-3-871be00c.dmg` |
| 大小 | 24,094,374 bytes |
| DMG SHA-256 | `9134a9edcb2136c231f033395b1dd7e9636207d41061e8c9d81ba60a7c949adf` |
| 可执行文件 SHA-256 | `871be00c4e96a770ba0c2efed36225adc41d3a4fc1a5d4cb3dce12abb24b4f31` |
| 版本字段 | `MARKETING_VERSION = 2.2.7`，`CURRENT_PROJECT_VERSION = 3` |
| 签名 | ad-hoc，未公证。首次打开需在「系统设置 → 隐私与安全性」放行 |
| 平台 | Apple Silicon，macOS 26.4 及以上 |

上一个发布「SimiGo v2.2.7 (2)」（tag `v2.2.7-2` / `2b954a3`）保留原样，不再是最新版；
更早的「SimiGo v2.2.7 (1)」（tag `v2.2.7` / `9365371`）同样保留。

## 安装形态

打开 DMG，把 `SimiGo.app` 拖入 `Applications`。首次运行进入向导：建立外部工作目录、
检测或按锁定版本构建 llama.cpp、写入默认配置。

覆盖安装会重新进入首启向导，但不动 `~/.simigo` 下的库与配置——升级不重置信息空间。
DMG 内 `SimiGo.app` 共 19 个文件，不含任何 sqlite / jsonl / log。

## 这一版是什么

与 2.2.7 (2) 能力面相同，把「失败要显形」落到四条路径：归属欠账到点自醒（30 秒监视器、
退避到 30 分钟、队列清空即停表）；房间管理查询失败不再伪装成「没有变化」；目录盘点与
根身份不满足即拒；managed 快照、chat / Responses 的持久化读取与结算失败一律报错。
细节与**未证明的边界**在 [发布说明](docs/releases/RELEASE_NOTES_v2.2.7-3.md) 里，不在本文复述。

## 本版未包含

- Developer ID 签名与公证：本机没有相应凭据，发布件是 ad-hoc 签名，离线可分发的
  免 Gatekeeper 安装未做。
- 安装版端到端复验：没有把该 DMG 装进 `/Applications` 跑首启向导与真实请求。
- 监视器 30 秒的真实节奏与退避的墙钟行为：只在契约层用注入时间验证，没有真机长时间观察。
