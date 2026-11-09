# SimiGoCollection

独立的 **MLX-free Swift package**：只读采集 Qoder transcript，将增量重建的候选事件与读取游标写入本地 SQLite inbox。

> **当前定位：采集 → 外部轮次合同。** App 集成默认关闭采集；开启后，sink 把轮次按
> IS 外部轮次合同（`recordExternalTurn` / `recordExternalResponse` / `verifyExternalTurn`）
> 写入权威库。本 package 自身仍不依赖 Runtime：sink 在 App 侧
> （`SimiGo/App/ExternalTurnSink.swift`）。包测试只证明采集与 inbox 语义；
> 「真实 transcript → 检索命中」的整链安装版读数尚未取得。

## 数据流

```text
Qoder transcript (read-only)
  → Scanner / Tailer / Turn Accumulator
  → SQLite inbox (candidate + cursor transaction)
  → sink (at-least-once) → IS 外部轮次合同（App 侧实现）
```

## App 行为与数据位置

- App 启动不自动采集，也不在启动时重跑导入；设置页的采集桥显式触发。
- 采集是**一次性导入**：把选定目录里**已有**的会话读进来（`readExisting`），扫到不再读出字节就结束并释放 lease。之后的会话由 agent 自己走 MCP 进 IS，不靠这里持续 tail。
- 策略切换会让旧游标作废并从 0 重读；重复候选由 inbox 键吸收，重跑同一次导入不追加行。
- 每轮按「答案完整 + 问答绑定成立」判检索资格：`eligible`、压缩后按文件顺序绑定的两类、排队命令 → `committed`（可检索）；被打断 / 未绑定 / agent 自造的续跑·通知·回调 → `recorded`（入库不检索）；子代理 / 侧链 → `internal`（只留审计）。
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

采集桥于 `b3886bb8` 进入产品主线。包测试、App 构建与冒烟仅证明接入未破坏既有路径，不证明 collection → ES/IS 完整链路。提交构成、候选 tag 与当前 HEAD 的差异、91 条测试及整合历史详见 [collection integration record](../../docs/history/COLLECTION_INTEGRATION_20261105.md)。

旧云代理转发已退役；本 package 不恢复该能力。
