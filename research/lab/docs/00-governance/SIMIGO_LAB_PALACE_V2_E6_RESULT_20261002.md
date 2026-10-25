# PALACE V2 E6 结果记录 — Information Validity Observation（V-1…V-5）

日期：2026-10-02  
状态：`E6 EXECUTED / RESULT AT HUMAN`  
设计：`SIMIGO_LAB_PALACE_V2_E6_INFORMATION_VALIDITY_DESIGN_DRAFT_
20261002.md`（FROZEN / EXECUTION AUTHORIZED）  
执行设置：隔离沙箱 `.build/e6/`；W1 = L0 直拷工作副本
（1258847B / 14 Sheets / sha `1dd8372a…` 与 L0 一致——完整性已验证）；
漂移由真实 Microsoft Excel 原生执行（AppleScript 驱动，RQ-OQB-1
已证单点表示隔离）；L0 原件全程零触碰

## V-1 — 场景构造（完成）

```text
[O] 工作依据集 D-rec-1..4 落盘（discovery-set.json）：
    D-rec-1 cell 级    附表1!F8 = 450.29（袋装水泥 市场询价）
    D-rec-2 cell 级    表1-汇总表!H5 = 708802383.38782
    D-rec-3 multi-cell 附表1!F9/F10 圆钢 vs 螺纹询价比较结论
    D-rec-4 whole-book 14 Sheets 四层结构陈述
```

## V-2 — 变化发现

```text
[O] DRIFT-1（Excel 改 F8 → 450.3）：五字段全变（sha
    1dd8372a→6431223f，size +18B）——文件级可发现
[O] 内容层：重读 F8 = 450.3 ≠ 450.29 ——cell 级可发现可定位
[O] DRIFT-2（Excel 改 汇总表!H5 → 709000000）：重读 H5 已变
    ——可发现可定位
[O] 对照事实：Excel 纯往返（open→save 零修改）= cell 值零变化
    （仅内部重写 +1KB）——变化信号未被保存路径污染
```

## V-3 — 识别「曾依据过什么」

```text
[O] 每条 D-rec 附依据坐标/粒度自标 → 重进时逐条可重新定位：
    D-rec-1 → 附表1!F8；D-rec-2 → 汇总表!H5；D-rec-3 →
    附表1!F9+F10；D-rec-4 → 全簿结构
[O] 依据粒度自标（cell/multi-cell/whole-book）在判定中发挥了
    实际作用（见 V-5 的 D-rec-4 粒度失配案例）
```

## V-4 — 过去发现是否仍可用的判定（跨两次漂移）

| 判定时点 | D-rec-1 | D-rec-2 | D-rec-3 | D-rec-4 |
|---|---|---|---|---|
| DRIFT-1 后 | **已失效**（450.29→450.3，可检测） | 仍有效 | 仍有效* | 仍有效（结构） |
| DRIFT-2 后 | 已失效（持续） | **已失效**（708802383.39→709000000，可检测定位） | 仍有效* | 仍有效（结构） |

```text
[O] 部分失效区分能力（OB-V4）= True（跨两次漂移均成立）：
    世界只变了一部分时，工作依据集可被逐条区分
[O] *D-rec-3 有一个判定波折（见 V-5 案例一）：DRIFT-1 后
    初判「已变化」，溯源后修正为「记录缺陷」非世界变化
```

## V-5 — 无法判定/误判的处置（两个真实案例）

### 案例一（金质性）：D-rec-3 登记缺陷导致误判「世界变化」

```text
[O] DRIFT-1 后重读 F9/F10 = '=4250/1.13/1000' ≠ 登记记录
    '=4250/1.13/100' → 初判「D-rec-3 已变化」（误判）
[O] 溯源（对照实验）：L0 新鲜副本 = /1000；纯 Excel 往返后仍
    = /1000；L0 sha 未变 → **世界从未变化；是 W1 侦察脚本的
    str(v)[:14] 显示截断把 /1000 截成了 /100**——记录缺陷
    被误判为世界变化
[O] 处置（实际发生）= 发现集追加 corrections 登记（不静默
    改写）+ D-rec-3 按修正记录重判 = 仍有效
[I] 推断（bounded）：「工作记录与现实不符」存在两种根因——
    世界变了 vs 记录本身有缺陷；不溯源则二者不可分。这直接
    支撑 human 判断：有价值的是「让 Agent 发现依据变化」+
    「发现后能溯源」，而非「自动判定过期」
```

### 案例二：D-rec-4 全簿粒度失配

```text
[O] DRIFT-1/2 后：D-rec-4（14 Sheets 结构陈述）按结构判定
    「仍有效」——但同一工作簿的 F8/H5 数值已变
[O] 处置（实际发生）= 全簿粒度记录只能做结构级判定；数值级
    有效性须由 cell 级记录（D-rec-1/2）承担——原粒度无法完全
    判定 ⇒ 粒度拆分（登记为观察，不定义机制）
```

## H / E6-V1 材料流向

```text
H-G1-01（SUPPORTED—exploratory）：D-rec 集使 DRIFT-2 可精确
  定位目标（H5）——发现集改变后续探索与修改的定位方式
H-G1-02（UNVERIFIED+signal）：V-5 案例一的根本处置依赖
  「W1 记录 + L0 重导」双源对照——工作过程对记录的依赖再度
  出现；必要性证明仍缺
E6/V1：OB-3 式「旧值仅存于工作记录」形态再现（450.29、
  708802383.38782 现仅存于发现集记录）——bi-temporal 克制
  裁定继续适用，登记为参考观察
```

## 生成的新问题

```text
RQ-E6-1  「记录缺陷 vs 世界变化」的区分规程（本实验 = 人工
         溯源；Agent 工作中的自动化溯源形态 = 未决）
RQ-E6-2  依据粒度自标的标准化（cell/multi-cell/whole-book 之外
         是否需要更多档位）
RQ-E6-3  DRIFT 后未失效依据的「隐性失效」可能（跨文件引用、
         口径依赖——Corpus-1 中 A↔D 数字映射未建，此处无法
         观测，留 G2）
```

## Gate state

```text
E6 = EXECUTED / V-1…V-5 全部观察完成 / RESULT AT HUMAN
待裁定 = E6 验收 + V-5 案例定性 + 下一步方向（G1 全面收束 /
        G2 设计入口 / RQ-OQB-1 类复测扩展）
本记录不构成：PALACE 设计 / schema / version·lineage·provenance
机制命名
```
