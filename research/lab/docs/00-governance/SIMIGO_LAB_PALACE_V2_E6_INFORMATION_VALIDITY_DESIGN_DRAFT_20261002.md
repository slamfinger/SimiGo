# PALACE V2 E6 — Information Validity Observation Design Draft

日期：2026-10-02  
状态：`DRAFT / FREEZE-PENDING-HUMAN（仅设计；无执行授权）`  
Gate：`PALACE_V2_E6_INFORMATION_VALIDITY（observation only）`  
授权来源：human 确认（RQ-OQB-1 后顺序裁定——E6 Design Entry；E6
问题用 human 措辞，低于版本管理一层抽象）  
上游锚点：OQ-B 结果（OB-4「工作记录 vs 世界当前状态独立性」）·
RQ-OQB-1（噪声 = 工具特有，原生路径单点语义变化）· RQ-D3（最新
判据遗留）· RQ-OQB-3（发现记录过期检测）  
性质：participant design draft——冻结审查通过并获执行授权后方实验

## 0. §0 并发核验（执行前须重跑）

```text
设计登记基线 = 本文件入库 commit；执行前重跑 git fetch + 树净核验
```

## 1. Research Question（human 措辞，冻结）

> **当信息空间中的原始内容发生变化时，PALACE 如何知道当前工作所
> 依据的信息是否仍然有效？**

术语纪律（human 裁定）：

```text
❌ 不称「版本管理」——证据只证明「当前世界状态与过去工作状态
   可能脱钩」，未证明需要版本树/revision graph/bi-temporal model
❌ 不设计「自动判断过期」机制——那是设计机制
✅ 观察的是后者：「PALACE 必须能够让 Agent 发现『我现在继续
   工作的依据发生了变化』」——这是工程观察
```

## 2. 观察子问题（human 五问，冻结）

```text
V-1  当前原始内容发生变化（场景构造，见 §4）
V-2  PALACE 能否发现变化？
V-3  能否识别「当前工作曾依据过什么」？
V-4  能否判断过去发现是否仍可使用？
V-5  如果不能判断，系统会怎样处理？（最后一项 = 最有价值的
     可能观察点）
```

## 3. E6 与 OQ-B 的关系（推进点，非重复）

```text
OQ-B 已答：单 cell 漂移的可检测性（OB-2）+ 记录 vs 现实矛盾
           可检测性（OB-4）+ 旧值零痕迹（OB-3）
E6 推进点：观察对象从「一个已发现 cell」升级为「一组工作依据
           （发现集）」：
           · 部分依据失效 + 部分依据仍有效时，能否区分？
           · 非单点结论（比较类/综合类依据）失效时如何表现？
           · V-5：不能判断的依据，工作过程如何处置？
```

## 4. 场景构造（隔离沙箱，L0 真实原件零触碰）

```text
W1 工作会话（建立「工作依据集」）：
   v1 = A 族工作副本（同 OQ-B：
   2秦沈项目标后预算明细表-1.15局会议修改后.xlsx）
   预登记发现集（以实际 cell 抽样落盘为准）：
     D-rec-1  附表1!F8 = 450.29（袋装水泥 市场询价）
     D-rec-2  表1-汇总表 抽样数值（执行时落盘具体 cell 与值）
     D-rec-3  比较类结论（例：「F8 价格与 附表3 混合料价格
              处于不同量级」类陈述——绑定多个 cell 的结论）
     D-rec-4  综合类陈述（例：「该表结构含 汇总+清单+取定
              三层」——绑定全簿结构的陈述）
     （每条记录附「依据粒度」自标：cell / 多 cell / 全簿）
漂移事件（两次独立漂移，之间各自重进）：
     DRIFT-1  修改 F8（450.29→450.30）——仅 D-rec-1 应失效
     DRIFT-2  修改 汇总表 一个数值 cell——仅 D-rec-2 应失效
     （预登记预期；偏离即溯源）
重新进入（每次漂移后）：对 D-rec-1..4 逐条判定
     仍有效 / 已失效 / 无法判定
```

## 5. 观察格 ↔ 子问题映射

| 观察格 | 对应 | 内容 |
|---|---|---|
| OB-V2a | V-2 | DRIFT 后五字段/内容层变化能否发现（OQ-B 已证可检测——本格复验于发现集语境） |
| OB-V3 | V-3 | 逐条 D-rec 能否被重新定位到其依据 cell/范围（依据粒度自标的实测） |
| OB-V4 | V-4 | 逐条判定：仍有效 / 已失效 / 无法判定——**区分能力**是本实验核心（DRIFT-1 后 D-rec-2 应仍有效：能否得出该区分？） |
| OB-V5 | V-5 | 无法判定条目的工作处置：挂起？标记？忽略？重算？——原样记录，不预定义机制 |

## 6. Evidence Grade 与判读纪律

```text
Observation = 每条 D-rec 的判定结果与依据（重读值/比对/无法定位）
Inference   = 「PALACE 需要 X 能力」级结论须替代解释排除
Open        = 无法判定条目的语义解释（只登记现象）
预期纪律    = DRIFT-1/DRIFT-2 的失效范围为预登记预期，
             偏离即溯源（沿 OQ-B 先例）
```

## 7. Prohibitions（逐字冻结）

```text
❌ 版本树 / revision graph / bi-temporal model 设计
❌ 自动过期检测机制设计
❌ Knowledge Base / Information Object / Relation / Provenance
   Schema / Dynamic Index Schema / PALACE State Schema 定义
❌ L0 真实原件写入（沙箱副本操作）
❌ 性能基准 / 批量变更
❌ 修改 SimiGo 冻结契约（ES 相关表述仅作研究方向登记）
❌ Gate① / V1 复活（再激活条件不变）
```

## 8. Gate Sequence

```text
本设计草案 → human 冻结审查 → 执行授权
           → W1 建立与发现集落盘（human 可见）
           → DRIFT-1 → 重进判定 → DRIFT-2 → 重进判定
           → 结果门（V-1…V-5 逐项事实 + H-G1-01/02 + E6/V1
             材料流向）→ human 判读
```

当前无执行授权。
