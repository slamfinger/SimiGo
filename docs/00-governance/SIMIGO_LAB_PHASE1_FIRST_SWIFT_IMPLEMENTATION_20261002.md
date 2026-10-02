# Phase 1 首批 Swift 文件实现记录

Date: 2026-10-02  
Gate: `IMPLEMENTATION GATE OPEN`（human 授权）  
Status: `3 FILES IMPLEMENTED / BUILD CLEAN / SMOKE ALL PASS / SWIFT FILES = 3`

## 1. 交付物

```text
trackD-memory/Sources/InformationCore/Information.swift        // A1–A5 语义类型
trackD-memory/Sources/InformationCore/InformationStore.swift   // B1–B3 最小生命周期
trackD-memory/Sources/InformationCore/SQLiteStore.swift        // C1–C3 物理持久化 + 机制侧铸造
Package.swift                                                  // target + product 接线（无新依赖）
```

落位 = memory 轨道（trackD-memory）；单模块 `InformationCore`；
依赖 = 仅系统框架（Foundation/CryptoKit/SQLite3），零第三方。

## 2. 实现内决策（均在已裁定空间内，如 human 不认可可重开 Gate）

| 决策 | 依据 |
|---|---|
| 单 target 三文件（边界=文件，非模块拆分） | 裁定只钉三边界；拆模块属实现自由 |
| `store` throws（storage failure）/ `fetch` throws + nil（absence） | B3 要求 not found ≠ failure，故 fetch 保留 throws 表达失败、nil 只表 absence |
| `PhysicalFiling(wing:room:)` 作为 SQLiteStore init 可选配置 | C2：filing 物理列可写、Information 类型零携带 |
| minting 输入 = content + source + chunkIndex（length-prefixed SHA-256 截 24，v3 同型防碰撞模式） | A2′ 形成链「事实内容+必要形成上下文」；配方藏于机制层 |
| 日期 ISO-8601 字符串直存直取 | verbatim 精神：Core 不做日期规范化 |
| `INSERT OR IGNORE` 实现 B2 幂等 | 重复 identity = 成功 no-op |

## 3. 实现问题 ≠ 语义问题（Gate 纪律执行记录）

构建与冒烟中共修复 3 个纯实现 bug，**零语义改动**：

1. `Information.swift` 缺 `import Foundation`（编译错）
2. `StorageError` payload `Int32` 两处多余 `Int()` 包装（编译错）
3. `fetch` 误用「DONE 后 errcode==OK」检查致 absence 抛错——改为
   标准模式 ROW→返回 / DONE→nil / 其他→throw（B3 语义不变，
   修复后 absence 正确返回 nil）

## 4. 冒烟验证（同源码临时包，全 PASS）

```text
PASS A2′ mint deterministic   （同事实重复铸造 = 同 identity）
PASS B3 absence = nil         （未命中非异常）
PASS C3 verbatim roundtrip    （content/identity/provenance/temporal 全保真）
PASS B2 idempotent no-op      （重复 store 后行数仍 = 1，事实未变）
C2 filing 物理列              （wing/room 落库 = 秦沈-标后预算/表2单位验证，
                                不回流 Information 语义）
```

负空间复核：交付面无 Relation/Activation/Diary/ExecutionState/
checkpoint/ack/Layer0-1/taxonomy/MCP/检索排序的任何类型、协议、
占位或扩展点；`Information` 无 wing/room/recipeVersion。

## 5. Gate 状态

```text
IMPLEMENTATION GATE = 首批三文件完成（BUILD CLEAN / SMOKE ALL PASS）
下一道门 = human 验收（或指出实现决策需重开项）
Phase 0 = FROZEN / Phase 1 = 边界+API 已闭 / T4 = BLOCKED
Git = 本地提交，不推送
```
