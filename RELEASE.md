# 当前发布记录：SimiGo v2.2.7 (2)

本文是**当前**可下载产物的身份与安装形态记录。发布说明正文在
[docs/releases/RELEASE_NOTES_v2.2.7-2.md](docs/releases/RELEASE_NOTES_v2.2.7-2.md)，
产品能力见该文件与 [v2.2.7 说明](docs/releases/RELEASE_NOTES_v2.2.7.md)。

历史候选构建的身份记录已移到
[docs/releases/HISTORICAL_CANDIDATE_v2.2.4-34.md](docs/releases/HISTORICAL_CANDIDATE_v2.2.4-34.md)，
不再代表当前产物。

## 产物身份

| 项 | 值 |
| --- | --- |
| Release | [SimiGo v2.2.7 (2)](https://github.com/slamfinger/SimiGo/releases/tag/v2.2.7-2)（Latest） |
| tag | `v2.2.7-2` → 提交 `2b954a3` |
| 文件 | `SimiGo-v2.2.7-2-0a6b308c.dmg` |
| 大小 | 24,048,893 bytes |
| DMG SHA-256 | `1d136881649b5a781229491a752b48520243ff4003807c049b1a71a7e6e184f0` |
| 可执行文件 SHA-256 | `0a6b308cc0af723f01ee75f3edb7378c386e732a8a40f9f35b5c09553cef3f6e` |
| 版本字段 | `MARKETING_VERSION = 2.2.7`，`CURRENT_PROJECT_VERSION = 2` |
| 签名 | ad-hoc，未公证。首次打开需在「系统设置 → 隐私与安全性」放行 |
| 平台 | Apple Silicon，macOS 26.4 及以上 |

上一个发布「SimiGo v2.2.7 (1)」（tag `v2.2.7` / `9365371`）保留原样，不再是最新版。

## 安装形态

打开 DMG，把 `SimiGo.app` 拖入 `Applications`。首次运行进入向导：建立外部工作目录、
检测或按锁定版本构建 llama.cpp、写入默认配置。

覆盖安装会重新进入首启向导，但不动 `~/.simigo` 下的库与配置——升级不重置信息空间。
DMG 内 `SimiGo.app` 共 19 个文件，不含任何 sqlite / jsonl / log。

## 这一版是什么

与 2.2.7 (1) 能力面相同，补三处「账要说清」的实现：归属写入失败的持久化重试、
缺口第五项（有摘要但无房间归属）、补录回执逐轮留失败原因。细节与**未证明的边界**
在 [发布说明](docs/releases/RELEASE_NOTES_v2.2.7-2.md) 里，不在本文复述。

## 本版未包含

- Developer ID 签名与公证：本机没有相应凭据，发布件是 ad-hoc 签名，离线可分发的
  免 Gatekeeper 安装未做。
- 安装版端到端复验：没有把该 DMG 装进 `/Applications` 跑首启向导与真实请求。
