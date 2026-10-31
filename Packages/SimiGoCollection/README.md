# SimiGoCollection

独立的 **MLX-free** Swift package：只读采集 Qoder transcript，并把重建出的候选事件和读取游标持久化。它不承担 IS 导入或 settlement。

## 数据流

~~~text
Qoder transcript tree (read-only)
        ↓
Scanner → Tailer → Turn Accumulator
        ↓
SQLite inbox (candidate + cursor transaction)
        ↓
optional sink (at-least-once)
~~~

App 当前使用 collection-only 模式：候选保留在 inbox，不配置 sink、不标记 delivery，也不写 Information Space。

## 配置

| 环境变量 | 未设置时 | 显式设置但无效时 |
|---|---|---|
| QODER_PROJECTS_DIR | ~/.qoder-cn/projects | 空值、相对路径、已存在的非目录路径均使 collector 不可用 |
| SIMIGO_HOME | ~/.simigo | 空值、相对路径、已存在的非目录路径均使 collector 不可用 |

Collector 状态目录为 $SIMIGO_HOME/collectors/qoder。显式无效配置不会回退到真实用户目录，也不会创建 inbox 或 lease。

## 恢复与交付语义

- Runner 在单一串行队列轮询；独占 lease 防止多个进程覆盖同一游标。
- 候选和 cursor 在一个 SQLite 事务中提交；重启时从持久化的 open-turn anchor 重建未完成 turn。
- 已损坏或不可读的状态不会被静默重置；需要显式 quarantine。
- Sink 只在持久化提交后调用。若 sink 已接受但 delivery 标记尚未提交，重启后可能按同一稳定 key 重发，因此语义是 **at-least-once，不是 exactly-once**。
- payload digest 不匹配时停止交付并 fail-closed。

## 测试

~~~bash
swift test --package-path Packages/SimiGoCollection --filter SimiGoCollectionTests

# App XCTest 必须通过隔离 harness
tools/run_isolated_tests.sh --tag <name>
~~~

隔离 harness 将 SIMIGO_HOME、cache、state graph 和 QODER_PROJECTS_DIR 指向每次新建的隔离根，并审计真实用户状态是否发生变化。不要直接对 App 的 TEST_HOST 运行未隔离测试。

## 边界

Collector 的分类结果是来源候选，不是 IS 的结算资格。当前 slice 不写 IS，不执行 RULED_ALLOW/WA，也不激活 frozen C-policy。下游导入与 settlement 是单独的产品实现和授权边界。
