# 历史候选记录：SimiGo v2.2.4 (build 34)

> **历史快照，不是当前 Release 页面或下载指南。** 本文保留 2026-11-05 前后记录的本地候选产物身份与当时验证事实。不要从本文推断当前 main 的产物身份、当前可下载状态或正式发行状态。当前发行入口只应由根目录 README 中明确列出的 GitHub Release 提供。

状态：当时的本地 Release 候选，未推送、未公开发布。本机没有 Developer ID Application 证书与公证凭据，本 DMG 为 **ad-hoc 签名，未做 notarization**；正式签名与公证必须在项目受控的 macOS 发布环境完成，并以那里产出的 DMG 哈希为准。

> **产物与当前源码树的边界：** 下列 DMG / 本地 tag 对应提交 `e21d8f7b`，是一个固定候选快照，不代表仓库当前 `main` 的完整源码。后续进入主线的 Qoder transcript collection bridge（`b3886bb8`）不在该候选 tag / DMG 中。该 bridge 在当前源码中的状态、测试与未验收链路见 [SimiGoCollection README](Packages/SimiGoCollection/README.md)。因此此处验证只对该 build 34 快照成立，不构成当前 main 的完整产品验收，也不能作为 collection → ES/IS 端到端链路已包含或通过的证据。

## 产物身份（仅供历史追溯）

| 项 | 值 |
| --- | --- |
| 文件 | `SimiGo-v2.2.4-34-6a3b24de.dmg` |
| 大小 | 33,771,620 bytes |
| DMG SHA-256 | `a9d0594fca66464fe3027db510e5c7a12b6645f659cc55b79ac5b01b9910a152` |
| 可执行文件 SHA-256 | `6a3b24dedac51348cb2f9a71f665eff32706838de3d7c25349bc67a356ee80a8` |
| Bundle | `SwiftUI.SimiGo` 2.2.4 (34) |
| 签名 | `flags=0x10002(adhoc,runtime)`，TeamIdentifier 未设置 |

当时候选安装操作记录：打开 DMG 按安装器提示覆盖安装，需要管理员权限；安装器会清除首次运行标记，重新进入首启向导。此段不构成当前安装建议。

## 源码身份

- 分支：`release-candidate/v2.2.4-build34`
- 提交：`e21d8f7b`（本地 tag `v2.2.4`，未推送）
- 版本字段：`MARKETING_VERSION = 2.2.4`，`CURRENT_PROJECT_VERSION = 34`

## 当时记录的变更

1. 云端代理退役：删除 API 云端入口与转发实现；新增无模型的信息空间 HTTP 宿主，`/health` 报告 `simigo-information-space`，`/mcp` 与 IS 读写路由可用，推理路由拒绝。
2. 生命周期自动化：App 启动即拉起信息空间宿主；启动 MLX / llama.cpp 自动接管 8000；停止模型自动回落到宿主。菜单与设置只保留状态显示，不再有独立的“启动 / 停止信息空间服务”入口。
3. 状态显示修正：仅宿主运行时不再把已选 backend 标成“运行中”；宿主常驻不再阻止选择模型。
4. 协议与运行时修复：外部回答按已证语义结算（不依赖流结束）；断连孤儿可见排队重试；SQLite 初始化锁竞争不再误报为损坏；Release 构建不再注入 base entitlements。
5. 测试隔离：LOCALB 夹具与传输前提显式化，八条 schema head 断言校正。

## 当时验证范围

- Debug 与 Release 构建均以状态码 0 结束。
- 安装后启动 App：8000 由信息空间宿主监听，`/v1/models` 返回 `simigo-information-space`。
- 启动真实 GGUF（`LiquidAI/LFM2.5-24B-A2B-GGUF`）：8000 改由模型服务监听，`/v1/models` 返回该模型；菜单显示“运行中 (llama.cpp)”，设置显示“LLaMA.cpp 运行中”。
- 停止模型：`llama-server` 进程退出，8000 自动回落到宿主，菜单恢复“运行中 (信息空间服务)”，选择模型恢复可用。

## 当时未包含

Developer ID 签名、公证与 Apple 公证存根。本机不具备所需凭据，正式发布须在发布环境重做签名、公证，并重新记录 DMG 哈希后另行发布。
