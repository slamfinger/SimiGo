# Phase 0 — SimiGo 产品仓原生契约集成（验证里程碑）

分支 localb-b3-closure-20261016 @ de362ef4（本地领先公开 main，未以 main 覆盖）。
起始工作树干净；本轮改动均可归因于本次集成；未 commit / 未 push。

## 事实（本 Mac 实际执行）
1. 原生声明式结果契约引擎从 Lab 逐字节移植入产品 MLX-free 目标
   `Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/NativeDeclarativeResultContract.swift`
   （sha256 `4a6cef…` 与 Lab 源完全一致 → K2 已对齐生产 digest 方向被原样继承，未重写）。
2. 新增产品级 pre-settlement 权威 `SimiGoSettlementAuthority.swift`：委派 native gate，
   无 Python fallback，拒绝即抛、绝不返回 payload、不做 I/O。
3. Package.swift 增 `SimiGoRuntimeContractTests` 测试目标（仅依赖 Contract，不触 MLX）。
4. `swift test`（本 Mac）：26/26 通过（21 引擎 + 5 权威），含 digest 生产方向向量
   `2b1a5d9f…`、嵌套非 ASCII `09ad9fd2…`、未知约束 `equals_binding_segment` 反事实拒绝。
5. `xcodebuild -scheme SimiGoRuntimeContract` Debug：BUILD SUCCEEDED。
6. `xcodebuild -scheme SimiGo`（app 目标，含 MLX）Debug：BUILD SUCCEEDED，0 编译错误；
   `SimiGo/App/ExecutionStateGraph.swift` 携新 `settleValidatedResult` 在生产 app 目标编译通过。
7. `ExecutionStateGraphStore.settleValidatedResult(...)`：先跑 native 权威，通过后才
   `mutate`/`persist`；拒绝则抛出且不写任何记录（fail-closed，无双写、无 Python 回退）。
   `settlements` 字段可选，向后兼容旧 JSON 图加载。

## 结论（可追溯）
原生 gate 已成为产品仓真实生产结算路径的 pre-settlement 权威，并在本 Mac 上通过
package 测试（26/26）+ 产品 Contract 目标 xcodebuild + 完整 app 目标 xcodebuild 编译验证。
这是"产品仓实际集成证据"，与 K2 的"Lab 研究证据"分列。

## 边界（不夸大）
- 本轮未在 app 目标运行 UI 级 settle 端到端测试（需模拟器/真机交互）；权威在
  MLX-free 包目标以 26 单测证明，store 接线以完整 app 编译证明；运行时端到端演练留待 Phase 5/6。
- 36 例跨语言 native/Python parity 与 H/I/J 回归属 Lab 载体（`execution-information-loop/`），
  本轮未在产品仓重跑；产品继承同一 byte-exact 引擎与其内嵌 digest 向量，跨语言 parity 的
  Python 侧证据沿用 K2（issue_count=0），不在产品仓重复声称。
- digest_equals_binding 的产品真实模型链执行未在本轮演示（与 K2 口径一致：K0 用 concat）。

## 工作树改动（归因）
```
 M Packages/SimiGoRuntime/Package.swift        (+4  test target)
 M SimiGo/App/ExecutionStateGraph.swift        (+53 settleValidatedResult + SettlementReceipt)
?? Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/NativeDeclarativeResultContract.swift
?? Packages/SimiGoRuntime/Sources/SimiGoRuntimeContract/SimiGoSettlementAuthority.swift
?? Packages/SimiGoRuntime/Tests/SimiGoRuntimeContractTests/
?? Packages/SimiGoRuntime/Package.resolved      (swift build/test 生成的解析锁定，非手改)
```
证据文件：00_protection_protocol.txt、01_xcodebuild_SimiGo_app.log、02_swifttest_native_engine.log
