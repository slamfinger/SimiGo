# Track D — Information / Relation / Execution Core

本目录当前承载 Information Runtime 的最小 Swift 核心，不再是早期
Adaptive Memory 占位描述。

## 模块

```text
InformationCore  Information / InformationStore / SQLiteStore
RelationCore     Relation / RelationStore / RelationMinter
ExecutionCore    ExecutionScope 与 observed-change 组合
```

## 状态

```text
Phase 0 semantic surface = FROZEN
Phase 1 InformationCore  = IMPLEMENTED / ACCEPTED / CLOSED
Phase 2 RelationCore     = IMPLEMENTED / ACCEPTED / CLOSED
ExecutionCore            = implemented with boundary tests
完整 Information Space   = NOT CLAIMED
完整 MemPalace Runtime   = NOT CLAIMED
```

## 验证

```sh
swift test
```
