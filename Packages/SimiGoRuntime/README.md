# SimiGoRuntime

SimiGo 的独立 Swift runtime package，提供 Execution / Runtime Contract 与 Runtime / Backend 实现，供 macOS App 集成和源码构建使用。

## 范围

- 承载运行时协议、执行状态及 backend 实现。
- 不包含 App UI、模型权重、Research / Experiment 文档或研究专用 harness。
- 不单独代表完整 SimiGo 产品；App 生命周期、HTTP API、配置和发行行为仍由仓库主 App 工程定义。
- package 编译通过不等于真实模型、backend conformance 或安装版 E2E 验收。

## 构建与测试

从仓库根目录执行：

```bash
swift test --package-path Packages/SimiGoRuntime
```

App-hosted XCTest 应使用仓库隔离入口：

```bash
tools/run_isolated_tests.sh --tag <name>
```

不要把 package tests 等同于 App / 真模型验收，也不要直接对 App TEST_HOST 运行未隔离测试。

## 来源

初始公开快照来自 SimiGo-Lab `25e1a790c841f48d0f3fddc762dcbff3c6d7c72a`。该提交仅记录 package 来源，不表示当前实现仍与该快照相同。许可：Apache-2.0。
