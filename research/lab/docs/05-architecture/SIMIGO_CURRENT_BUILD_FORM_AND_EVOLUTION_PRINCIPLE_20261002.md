# SimiGo 当前构建形态与后续演化原则

**日期：2026-10-02**  
**状态：研究方向登记 / 非实现承诺**

## 1. 当前判断

SimiGo 当前阶段的核心目标，不是继续预先设计完整的未来系统，而是把已经形成的 **Execution State** 与正在形成的 **Information** 两个基本语义真正做实。

当前应构建的基本形态：

```
Agent
  ↓
Execution
  ↓
Execution State
  ↓
Execution–Information 共同语义层
  ↓
Information
  ↓
现实世界
```

其中：

- **Execution State** 负责一次执行的连续、分叉、恢复以及可持久化的执行状态。
- **Information** 负责环境中可被不同 Execution / Agent 复用的内容及其关系。
- **Agent** 是进入该环境执行的参与者，而不是环境本身。
- **现实世界**提供真实的数据、资源、约束、变化、错误与不可预期性。

当前阶段不应把未来可能出现的更多层次、机制或标准提前固化为架构要求。

## 2. Information 目前仍是待建立的语义层

需要严格区分：

- SimiGo 的 Execution State 已基本形成；
- MemPalace 已经存在数据库及 Memory 结构，并已完成 T1/T2/T3 等行为实验；
- **SimiGo 尚未接入 MemPalace；**
- 因此当前还不能宣称已经存在一个由 SimiGo 驱动的独立 Information Space。

现阶段的实验只能说明 MemPalace 现有数据库结构已经表现出部分可共享 Information 的行为基础。

下一步需要通过架构裁剪，把现有 MemPalace 的数据库 / Memory 实现逐步映射到 Information 语义，并最终让 SimiGo Execution State 与 Information 建立真实连接。

## 3. MCP 的位置：最终被消解，而不是保留为内部层

MemPalace 后续计划进行一次真正的 Swift 重写。

这里的“Swift 化”不是：

```
Swift MCP → Python MCP → Python implementation
```

也不是：

```
Swift Core + MCP
```

目标是直接把现有 MCP 所承载的能力重新实现为原生 Swift 的 Information 语义。

重写完成后，内部架构不再存在 MCP 这一抽象：

```
Agent
  ↓
SimiGo Execution
  ↓
Information
  ↓
MemPalace
  ↓
Physical Persistence
```

MCP 只是历史上的外部接口形态。它不应成为 Agent 对 Information 的认知边界，也不应成为 SimiGo 内部架构的一层。

最终 Agent 不应思考“调用哪个 MCP tool”，而是在 Execution 中进入并操作 Information。

因此，MemPalace Swift 重写的目标不是机械搬运原 MCP tool 列表，而是从原有实现中抽取真正必要的 Information 能力，形成精干的原生 Swift 实现。

## 4. 当前最重要的语义边界

下一阶段首先需要裁清 **私有记忆与共享 Information 的边界**。

基本判断：

- 为了让某个 Execution 能够继续运行、恢复或定位自身上下文而保存的信息，属于 **Execution continuity / 私有层**。
- 一旦某项内容已经成为可被后续不同 Execution 复用的事实、材料、结论或关系，它才具有 **共享 Information** 属性。
- 私有记忆可以保存继续执行所需的 pointer、状态和局部上下文，但不能因为存在 pointer 就把整个私有记忆等同于 Information Space。
- Execution 在真实任务中读取、引用、产生、修改和关联 Information 的行为，应成为关系形成的重要来源，而不是由 Palace 事后凭相似度臆造完整语义关系。

因此可以暂时采用：

```
Execution
   ├── private continuity
   │      └── 为了继续执行
   │
   └── shared Information
          └── 为了被环境中的其他 Execution 复用
```

这只是当前研究边界，不提前规定最终数据库 schema。

## 5. 当前阶段的架构原则：停止替未来设计

SimiGo 在 Execution State 基本形成之后，研究重点发生变化。

此前可以通过实验主动验证某个预设机制是否成立；而进入 Information 阶段后，不应继续无限向前预设系统最终会长成什么样。

原则是：

> **先把 Execution State 和 Information 两个基本语义做实，把 Agent 放进去，然后让现实来碰撞。**

未来可能出现新的抽象、新的关系模型、新的持久化机制、新的协作机制，甚至可能出现目前完全没有预想到的系统边界。

这些不应在当前阶段凭空设计成架构承诺。

更合适的演化路径是：

```
Information
     ↕
Execution
     ↕
Physical World
     ↓
真实任务 / 真实约束 / 真实失败
     ↓
暴露新的问题
     ↓
形成新的必要抽象
```

也就是说：

> **未来架构应由现实运行反向塑造，而不是由当前概念向未来无限外推。**

## 6. 当前阶段的实际路线

当前路线收敛为：

1. 完成私有—共享边界的架构讨论；
2. 继续利用 MemPalace 现有数据库结构验证 Information 的必要语义；
3. 对 MemPalace 进行真正的原生 Swift 重写，不夹带 Python 实现；
4. 在重写过程中消解 MCP 抽象，使能力直接落到 Information；
5. 再建立 SimiGo Execution State ↔ Information 的真实连接；
6. 之后再让真实 Agent / 真实任务进入这个环境；
7. 不预设后期最终架构，让现实碰撞产生下一阶段问题。

### 核心表述

> **SimiGo 当前应该构建成一个让 Agent 通过 Execution State 进入 Information、并与现实世界发生持续交互的运行环境。**
>
> **Execution State 与 Information 是当前应真正做实的基本语义；更后期会如何发展，不提前规定，让现实去碰撞。**
