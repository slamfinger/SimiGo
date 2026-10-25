# Phase 1 API Gate CLOSED — A2′ 裁定封存

Date: 2026-10-02  
Status: `BOUNDARY CLOSED / API CLOSED / SWIFT FILES = 0`  
Chain: BOUNDARY CLOSED → API RULING 11/12 → **A2′ 选项一** → API CLOSED

## 1. A2′ 正式裁定（human 逐字要点）

> **`InformationID` 在 `Information` 形成时成立；ID 的计算机制
> 位于 Core 之外，由机制侧铸造器产生。**

形成链（裁定定稿）：

```text
事实内容 + 必要形成上下文
          ↓
    mechanism-side minter
          ↓
    InformationID
          ↓
    immutable Information
          ↓
    InformationStore.store(Information)
```

明确否决形态：无身份草稿 → SQLiteStore 生成 ID → Information
（避免为 API 方便向 Core 偷渡第二种语义对象）。

## 2. 三点裁定理由（逐字要点）

1. **A1+A2 语义闭合**：Information 一旦形成即完整不可变值
   （identity/content/provenance/temporal 四位齐），无 Draft
2. **B2 自然成立**：store 收到的对象已具 identity ⇒
   already-exists? yes → no-op/confirm；no → persist；
   **store 不决定 Information 是谁，只保存并确认幂等**
3. **C4 事实/机制双层保持干净**：`InformationID` = Information
   的语义事实；SHA-256/v3/normalize/encoding/recipe/minter =
   生成机制。「ID 属于 Information；ID 怎么算属于机制」

## 3. 服务树事实与 recipe 遗留问题的处置

- 服务树「ID 在写入路径现算」事实**保留**，但不升级为 Core
  语义：**机制计算发生在哪里 ≠ Information identity 语义上
  何时成立**——两者不矛盾
- recipe 版本化/跨 recipe 身份等价性 = **登记为机制侧遗留
  问题**，不进 Phase 1 Core API；`Information` 不得携带
  `recipeVersion`（防机制泄漏回语义层）；跨 recipe 迁移成为
  实际问题时再单独研究 identity equivalence / migration semantics

## 4. Phase 1 完整最小语义面（API CLOSED 定稿）

```text
Information
    identity: InformationID（opaque）
    content
    provenance（producedAt/producedBy 必选；source/sourceTime/
                position/extractionMode 可选）
    temporal（ContentDate? = date + source 成对）

InformationStore
    store(Information)                       // 幂等：重复 identity = no-op 确认
    fetch(by: InformationID) -> Information? // absence = nil 非异常

SQLiteStore
    persistence implementation
    + mechanism-side identity minting
    + physical filing metadata（wing/room，非语义属性）
```

负空间完整保持（零接口/零占位）：Relation ❌ Activation ❌
Diary ❌ ExecutionState ❌ checkpoint ❌ ack ❌ Layer0/1 ❌
taxonomy ❌ MCP ❌ retrieval ❌ ranking ❌

## 5. 下一道 Gate

> **API → 首批 Swift 文件**

研究节点性质转变（human 判词）：从这一刻开始，Swift 不再是
在「探索 Information 是什么」，而是在**实现已经裁定完成的
Information 语义**。

Gate 开启 = human 授权；开启前 Swift files 保持 0。
实现期纪律：Finding-1 审计教训继续适用；T4 = BLOCKED。
