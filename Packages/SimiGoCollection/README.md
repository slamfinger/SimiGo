# SimiGoCollection

独立的 **MLX-free Swift package**：只读采集 Qoder transcript，将增量重建的候选事件与读取游标写入本地 SQLite inbox。

> **当前定位：collection-only。** App 集成默认关闭采集；即使开启，也只写 collector inbox，不配置 sink、不写 ES/IS、不执行 settlement 或复用。采集候选不等于 IS 结算资格，collection → ES/IS 尚无端到端验收。

## 数据流

```text
Qoder transcript (read-only)
  → Scanner / Tailer / Turn Accumulator
  → SQLite inbox (candidate + cursor transaction)
  → optional sink (at-least-once; not enabled by App integration)
```

## App 行为与数据位置

- App 启动不自动采集；设置页「启用 Qoder 采集」显式开启，默认关闭。
- 关闭后停止轮询并释放状态目录 lease；菜单栏仅在开启时显示采集状态。
- transcript 根只读；写入仅限 `$SIMIGO_HOME/collectors/qoder`。
- 默认 `QODER_PROJECTS_DIR=~/.qoder-cn/projects`，`SIMIGO_HOME=~/.simigo`。
- 显式配置为空、相对路径或已存在的非目录路径时 collector 不可用，不回退到真实用户目录，也不创建 inbox / lease。

## 一致性与恢复

- 单一串行轮询队列与独占 lease 防止多个进程覆盖同一游标。
- 候选和 cursor 在同一 SQLite 事务提交；重启时从持久化 open-turn anchor 重建未完成 turn。
- 损坏或不可读状态不会静默重置，需显式 quarantine。
- sink 在持久化提交后调用；若 sink 已接受但 delivery 标记未提交，重启后可能以同一稳定 key 重发：**at-least-once，不是 exactly-once**。
- payload digest 不匹配时停止交付并 fail-closed。

## 测试

```bash
swift test --package-path Packages/SimiGoCollection --filter SimiGoCollectionTests
tools/run_isolated_tests.sh --tag <name>
```

Package tests 使用临时夹具，不读取活跃 transcript。App XCTest 中采集默认关闭，XCTest 宿主不启动 collector。隔离脚本不重写 `QODER_PROJECTS_DIR`，因此不得在 App 测试中显式启用采集；不要直接对 App TEST_HOST 运行未隔离测试。

## 主线整合与历史证据

采集桥于 `b3886bb8` 进入产品主线。包测试、App 构建与冒烟仅证明接入未破坏既有路径，不证明 collection → ES/IS 完整链路。提交构成、候选 tag 与当前 HEAD 的差异、91 条测试及整合历史详见 [Qoder collection integration record](../../docs/history/QODER_COLLECTION_INTEGRATION_20261105.md)。

旧云代理转发已退役；本 package 不恢复该能力。
