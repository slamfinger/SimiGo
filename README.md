# SimiGo-Lab — SimiGo 2.0 预研实验室

**性质**：预研实验仓（research lab）。装的是**未验证的实验与探针**，
不是产品代码，不构成任何版本承诺。

**产品仓**：`github.com/slamfinger/SimiGo`（1.x 线；与本仓严格分离）。

**当前状态真源**：`docs/RESEARCH_STATE.md`。本 README 仅提供工作区导览，
不得替代当前状态、endpoint 或 closure 文档。

## 当前研究门

截至 2026-09-22：

- Phase: **Definition / Opening**
- STEP ③: **PASS**
- STEP ④ estimand: **NOT STARTED**
- RQ ID: **未分配**
- 当前允许动作：STEP ④ estimand 定义、历史资产只读盘点
- 当前禁止动作：runtime implementation / harness construction /
  data collection / performance measurement

因此，目录中仍存在的实验计划、历史结果和未来占位，不代表当前已经获准
执行。

## 已完成 / 已封存研究线

| 目录 / 资产 | 状态 | 说明 |
|---|---|---|
| `trackB-execution-state/` | **CLOSED / FROZEN** | Track B Closure v4；仅在原测试边界内建立生命周期语义证据，不证明通用性能、估计器鲁棒性或 Residency |
| `trackE-residency/` | **CLOSED / 归档** | Track E / nodes-out 已完成其注册研究链；后续问题必须重新定义，不由旧记录自动开启 |
| `trackD-memory/` | NOT STARTED | 独立研究方向，未因架构文档存在而获准启动 |
| `exp06-roofline/` | 已预注册、**未执行** | 计划资产保留；实际测量须等待当前门合法解锁 |
| `trackA-kernel/` | 条件 / 未启动 | 受 exp06 开关判据约束 |
| `runtime2-skeleton/` | NOTE-ONLY / FUTURE | 多设备执行层占位，不实现、不立项 |

## 档案体系

完整档案入口：

`docs/ARCHIVE_INDEX.md`

当前链：

```
Question
  → Evidence
  → Finding
  → Decision
  → Architecture
  → Closure
  → History / Provenance
  → Research Memory
```

其中：

- `docs/03-findings/`：已登记的限定性发现；
- `docs/04-decisions/`：已登记裁定；
- `docs/05-architecture/`：研究约束形成的架构后果与不变量；
- `docs/06-closure/`：关闭、封存、冻结及合法出口；
- `docs/07-history/`：历史资产与 provenance；
- `docs/08-research-memory/`：候选思想和长期研究记忆。

## 边界规则

1. 实验室代码永不直接进入 1.x 发布路径。
2. 历史 FROZEN / SEALED / CLOSED 资产不得因归档重构而被重新解释。
3. 预测、计划、观察、Finding、Decision 和 Closure 必须保持语义分离。
4. 目录结构不能替代研究门禁。
5. SimiGo-Lab 2.0 research line 与 SimiGo 1.x product line 严格分离。

历史实验目录继续保留其原始位置；档案重构采用索引和映射优先，不进行
破坏性迁移。
