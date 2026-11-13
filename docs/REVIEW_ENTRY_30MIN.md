# 30 分钟外部入口（骨架草稿）

**Status**: 已从 README「研究与工程文档」节链接（公开 scrutiny 入口，owner 授权 2026-11-14）。英文终审稿见 [REVIEW_ENTRY_30MIN_EN.md](REVIEW_ENTRY_30MIN_EN.md)，对外发布需 owner 签核。主动外发（如向上游投递）仍须逐次单独授权，本链接不构成该授权。
**性质**: 服务**外部 scrutiny**（公开材料可被任何人读、跑、质疑），不是「邀请正式独立审查」——本项目当前无条件发起正式审查流程，本入口只降低外部判断的门槛。
**语言**: 本稿中文；对外发布前需英文终审（受众第一优先 vLLM / SGLang / llama.cpp 生态）。
**纪律**: 本入口不声称产品成熟度、不声称普遍适用性；所有读数带范围，n=1 如实标注。

---

## 0. 这篇入口解决什么

外部评价指出：156 篇 markdown 是档案库，不是入口；缺一篇「读三样、跑一条最小链、30 分钟给判断」的路径。本骨架就是那篇路径的组件装配图。其余 156 篇降为附录，经 [docs/README.md](README.md) 导航。

**给外部读者的承诺**：30 分钟内你能形成自己的判断——这个问题是否清晰、边界是否诚实、能否复现、与已有技术是否重叠。四种结果（无新意 / 互补 / 复现成功 / 不采用）都有效；否定性结论欢迎。

---

## 1. 读三样（约 20 分钟）

### ① 语义定义（约 7 分钟）——判断「区分是否有判别力」

- [B0 术语表](upstream/B0_ESIS_GLOSSARY_20261105.md)：15 术语正反定义 + 三大语义边界（ES≠Snapshot≠Carrier；Settlement / Settled Result / Settlement Record 三分；Carrier Independence 分语义层原则与实现层命题）。ACCEPTED 冻结。
- [B1 最小形式化](upstream/B1_ESIS_MINIMAL_FORMALIZATION_20261105.md)：骨架 `ES_n ──Settlement──▶ IS ──Admission──▶ ES_{n+1}`；R1–R6；**Settled(ρ) 与 Recoverable(ρ,ctx,t) 两谓词分离**。关系骨架，不是已证明的完整形式系统；OQ-1/3/8 显式 OPEN。
- 术语正本（实现侧用词）：[TERMINOLOGY_V0.1](research/es-is/TERMINOLOGY_V0.1_20261109.md)。

**读后问自己**：`Settled ≠ Recoverable`、`Refuse ≠ 重执行`、依赖闭包失效只波及闭包——这几条是换皮还是有判别力的区分？

### ② 证据边界（约 7 分钟）——判断「边界是否诚实」

- [研究地图](research/es-is/ESIS_RESEARCH_MAP_V0.1_20261108.md)：每个论题 → 代码锚点 → 测试 → 读数 → 缺口（G1–G6）。四命题 P1–P4。
- [未关闭问题](knowledge/open-problems/README.md)：每条带「边界」小节，主动写明未证明什么。
- [实验索引](experiments/README.md) 阅读原则：实验通过只支持其明确范围；文件名/目录不同 ≠ 独立证据；历史实验不自动代表当前能力。

**读后问自己**：作者是否主动缩小了自己结论的适用范围？n=1、时延污染、单路径覆盖是否如实标注？

### ③ 如何复现一条最小链（约 6 分钟读）——判断「能否复现」

- [P2 四阶段实验方案](upstream/P2_EXPERIMENT_PLAN_20261105.md)：真实模型结算 → 释放旧 KV → IS 恢复 → 新 ES 续推。方案 G1 CONDITIONAL PASS；**方案成立 ≠ 实验通过**；公开可复刻主链 Run 尚未跑（硬前置，关键实验不得晚于研究说明）。
- 已执行的旁证（n=1）：[ESIS gap closure 四臂](experiments/ESIS_GAP_CLOSURE_20261110/README.md)（载体独立性 SIGKILL→冷启动→零调用消费）、[C2 Session Readiness 矩阵结果](experiments/C2_SESSION_READINESS_MATRIX_RESULTS_20261113.md)（H1 弱形式 supported，C/F 记 N/A-this-build）。

**读后问自己**：这条链的验收条件是否可检验？哪些读数已存在、哪些仍缺？

---

## 2. 跑一条最小链（动手，分三层；前置条件已核验）

最小链不是单一装置，而是三层，门槛与证明力逐层递增。**对外正文必须分层呈现，不得把低门槛层的通过冒充高门槛层的结论。**

### 层 0 · 探针自检（零构建 / 零模型，已实跑核验）

```bash
python3 docs/experiments/ESIS_GAP_CLOSURE_20261110/rig/compose_probe/compose_probe.py --self-check
```

- **前置**：仅 python3 标准库（argparse/json/os/shutil/sqlite3/subprocess/sys/tempfile），无第三方依赖、无模型、无 App 构建、无运行实例。临时目录自包含。
- **核验读数（2026-11-14，本仓干净路径实跑）**：`EXIT=0`，末行 `SELFCHECK PASS`；四组态（epsilon+delta / beta+gamma / epsilon+alpha / blind）分类全部按预期红绿。
- **它证明什么**：探针自身的读数与分类逻辑可红可绿——含证伪臂：`blind`（控制文件变更后仍返回值）→ 阳性对照未响 → `E2: void`，探针拒绝把看不见撤回的跑法计为通过。
- **它不证明什么（关键边界）**：self-check 用 **stub CLI**，验证的是**探针**，不是 SimiGo 真实系统行为。不得据此声称「ES/IS 组成性已在真实系统验证」。这是 30 分钟入口里唯一零门槛可复现的工件，定位是「让外部读者亲手确认这套判据会自我证伪」，不是产品演示。

### 层 1 · 组成性正式跑（需构建 contract CLI，仍无模型）

```bash
python3 .../compose_probe/compose_probe.py --cli <contract-cli 二进制路径> [--work DIR]
```

- **前置**：Swift 工具链（macOS Xcode CLT）构建 contract CLI——源在 `rig/baseline/contract_cli{,_v2}.swift` 与 `rig/compose_probe/product_rig/`（Swift package `turn-cli`）。**仍不加载模型、不需整机 App。**
- **它证明什么**：E1（同一需求两权威 → 一份判定？epsilon/beta）、E2（跨空间撤回靠边还是重算？delta/gamma/alpha）对真实 contract CLI 的组成性读数。
- **状态**：装置存在、self-check 已绿；正式 `--cli` 跑需先构建 CLI，本稿未在本窗实跑该层。

### 层 2 · 载体独立性全链 / C2 矩阵（重前置，非 30 分钟干净 checkout）

- 载体臂 `rig/baseline/carrier_driver.py`：SIGKILL 杀进程 → 冷启动 → 显式消费，预期 `consumed / model_calls=0 / 新对象 / 值相等`。
- C2 驱动 `experiments/C2_SESSION_READINESS_MATRIX_RESULTS_20261113_evidence/c2_driver_20261113.py`：`POST 127.0.0.1:8000/v1/chat/completions` + `X-SimiGo-Agent` + 读 `~/.simigo/logs/native_mlx_trace.log`。
- **前置（缺一不可）**：已构建产品 App + 用户自备本地模型权重 + 运行中实例 + 隔离 `SIMIGO_HOME`/`SIMIGO_CACHE_ROOT`/端口/实验 DB。carrier 臂时延读数受并行生产实例污染（`contaminated=true`），结构断言不受影响。
- **结论**：这一层**不是**干净 checkout 30 分钟可跑的演示。把全链打包成零构建可复现工件，是 P2 硬前置下的**未竟工作**，不在本入口承诺之内。

**诚实范围（必须写进对外正文）**：
- 层 0 已实跑核验（stub，证伪臂有效）；层 1 装置就绪未在本窗实跑；层 2 重前置、非 30 分钟演示。**零构建的全链 30 分钟演示目前不存在。**
- 旁证均 n=1（单机 / 单 build / 单模型 / 单日）；时延读数受内存压力污染，不作稳态性能声明。
- 证据库 `*.sqlite3` 与构建产物**不入仓**，靠账本 + 哈希定位；同哈希二进制副本唯一，重建源码不保证同哈希。
- 跨引擎只有值能过，KV 表示不可移植；单侧读数不外推为统一 conformance。
- 层 1/2 需 Apple Silicon macOS + Xcode + 用户自备模型权重（本仓不分发）；层 0 仅需 python3。

---

## 3. 给出判断（约 5 分钟）

对照 [路线文档 §5 相关工作四项对照](upstream/DEEPSEEK_ES_IS_SEMANTIC_ROUTE_20261105.md)（hypothesis 状态，逐系统六问核查未完成前不得断言现有系统「不具备」某能力）：

| 对照系统 | 它们做什么 | ES/IS 声称的不同 |
|---|---|---|
| vLLM prefix caching / LMCache / CacheGen / CacheBlend | 复用计算结果 | 不定义「结算与有效性」的权威；ES/IS 以结算账本决定何时可信复用、何时必须重执行 |
| checkpoint / durable execution | 保存状态 / 恢复执行 | （待逐系统六问核查，不预设结论） |

**判断清单**：问题是否足够清晰具体？边界是否诚实？最小链能否复现？与已有技术重叠还是互补？哪条适用场景不成立？——否定性结论与复现成功同等有效。

---

## 4. 附录与导航

其余 156 篇文档是研究档案，不是必读。需要深入时经 [docs/README.md](README.md) 的 Start here 与证据/归档规则进入。冻结契约与权威实现 > B0/B1 冻结件 > 配置记录 > 计划 > 路线文档；回改下层不改上层。

---

## 5. 待 owner 裁定 / 补全

1. ~~最小链候选 A/B 的干净 checkout 可跑性核验~~ **已核验（2026-11-14）**：层 0 `compose_probe.py --self-check` 零构建零模型实跑 `SELFCHECK PASS`（stub，证伪臂有效）；层 1 需构建 contract CLI（无模型），装置就绪未实跑；层 2 重前置、非 30 分钟演示。零构建全链演示不存在，打包为 P2 未竟工作。
2. 对外英文终审稿。
3. ~~是否从 README「研究与工程文档」节链接本入口~~ **已链接（2026-11-14，owner 授权）**；主动外发仍逐次单独授权。
4. 相关工作六问核查（P3）完成前，§3 对照表保持 hypothesis 标注，不升格为断言。