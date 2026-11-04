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

App 集成使用 collection-only 模式：候选保留在 inbox，不配置 sink、不标记 delivery，也不写 Information Space。

## 产品入口

App 启动时不会自动采集。采集由设置页的「启用 Qoder 采集」开关显式开启，默认关闭；关闭后立即停止轮询并释放状态目录租约。菜单栏只在开启时显示采集状态，点击可回到设置页。

采集只读扫描 transcript 根，写入位置仅限 `$SIMIGO_HOME/collectors/qoder`。它不导入历史、不写 ES/IS、不做结算或复用。

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

包测试只使用临时夹具目录，不读取活跃 transcript。App XCTest 中采集默认关闭（`QoderCollectionEnabled` 缺省非 `1`），且 `startIfEnabled` 在 XCTest 宿主下直接返回。现行隔离入口 `tools/run_isolated_tests.sh` 只重写 `SIMIGO_HOME`、`SIMIGO_CACHE_ROOT`、`SIMIGO_STATE_GRAPH_STORE` 三个根，**不重写** `QODER_PROJECTS_DIR`；因此不得在 App 测试中显式启用采集。手工骨架 `tools/harness/` 已于 2026-10-30 退役，由 `SimiGoTests` 的 HTTP 套件承接。不要直接对 App 的 TEST_HOST 运行未隔离测试。

## 边界

Collector 的分类结果是来源候选，不是 IS 的结算资格。当前 slice 不写 IS，不执行 RULED_ALLOW/WA，也不激活 frozen C-policy。下游导入与 settlement 是单独的产品实现和授权边界。

## 主线整合身份与证据边界

采集桥进入发布主线的提交是 **`b3886bb8`**（`feat(collection): link the Qoder transcript bridge as an opt-in read-only collector`），
24 个文件 / 6,292 行新增：本包 17 个文件（Sources 8 + Tests 7，另 `Package.swift` 与 `README.md`）、App 接线 6 个文件
（`project.pbxproj`、`App/Config.swift`、`App/MenuApp.swift`、`App/QoderCollectionLifecycle.swift`、
`App/Settings.swift`、`App/StatusBarCoordinator.swift`）、CI 工作流 1 个。
随后 `d53782e6` 只重算发布清单（`release-inputs-v2.2.x.json`、`release-exclusions-v2.2.x.json`，
+78/−6），不含产品代码。

记录时 HEAD 为 `61bf1990`；其前的 `556ae91b`（删除三份逐字节重复的 retry 报告）与 `61bf1990`
本身都是**档案治理提交，不是采集桥提交**，不得用来指代本包整合。该 HEAD 尚未推送；本地 tag
`v2.2.4` → `e21d8f7b` 比 HEAD 落后 17 个提交、**不含本包**，既有 DMG 不能代表当前源码，须从含
`b3886bb8` 的最终 HEAD 重建。

**证据边界：** 包的 91 条测试全绿、App 构建与冒烟只证明「新接入的包不破坏既有路径」；
`Qoder → QoderCollection → 受控生命周期 → ES/IS` 的完整运行时链路**尚未端到端验证**。

| 能力 | 当前状态 |
| --- | --- |
| 只读采集、增量重建、持久 inbox | 已整合，本包测试覆盖 |
| 独占 lease、重启恢复 | 已整合，本包测试覆盖 |
| App 生命周期、菜单与开关 | 已整合；默认关闭，XCTest 宿主不启动 |
| 外部 IS 结算判据（PR #19） | 已吸收（`ccf6ac8a`），随后云代理退役（`a7e297c9`） |
| 旧云代理转发 | 已按后续架构退役，不随本包恢复 |
| 采集候选 → IS 受控消费 | **未接入**：collection-only，不写 IS/ES，不启用 RULED_ALLOW/WA/C-policy |

本包在 App 中是 collection-only（不配置 sink、不写 IS/ES），下游受控消费要另立实现与验收。
