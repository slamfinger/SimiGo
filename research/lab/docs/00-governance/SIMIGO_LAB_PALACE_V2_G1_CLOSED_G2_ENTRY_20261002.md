# PALACE V2 — E6 验收 / G1 收束 / G2 设计入口登记

日期：2026-10-02  
状态：`E6 CLOSED / G1 CLOSED / G2 DESIGN ENTRY OPEN`  
Registration authority：explicit human ruling（本会话裁定逐字登记）  
性质：gate 裁定登记——不产生 PALACE Schema，不预写 G2 具体 RQ

## 1. E6 验收（human 裁定表）

| 项目 | 裁定 |
|---|---|
| V-1 场景 | **PASS** |
| V-2 变化发现 | **PASS** |
| V-3 依据重定位 | **PASS** |
| V-4 部分失效区分 | **PASS — 两次独立漂移均成立** |
| V-5 无法/异常判定处置 | **PASS — 高价值观察** |
| E6 RQ | **ANSWERED FOR THIS EXPERIMENT** |
| E6 | **CLOSED** |
| 新 Schema / 版本模型 | **未授权** |

V-4 证据（比 OQ-B 更强）：DRIFT-1 后 D1✗ D2✓ D3✓ D4✓；DRIFT-2 后
D1✗ D2✗ D3✓ D4✓——**工作依据不是一个整体，它可以出现部分失效**
(观察事实；不因此定义「依据对象」或「版本对象」)。

## 2. V-5 两个案例的提升登记（human 归纳）

### 案例一（最高价值发现）

```text
记录 ≠ 当前现实
        ├── 世界真的发生变化
        └── 记录本身存在缺陷
（无溯源时二者产生完全相同的表面信号：重读 → 当前值 ≠ 登记值 → ???）
```

登记的 bounded evidence：

> **发现依据发生偏离之后，还必须能够回溯「偏离究竟来自世界还是
> 来自记录」。**

（无新 Schema——只知道：没有溯源，系统无法可靠解释这个冲突。）

### 案例二

```text
whole-book 粒度登记 vs 单数值实际变化
结构仍然相同 ≠ 依据内容仍然有效
⇒ 依据粒度本身会影响有效性判断
```

案例一 + 案例二组合逼出的两个底层工程事实：

```text
依据有效性
    ↑
    ├── 依据定位精度（案例二）
    └── 依据记录可信度 / 可溯源性（案例一）
```

（比直接设计 revision graph 有价值得多。）

## 3. H 状态更新

```text
H-G1-01 = SUPPORTED — strengthened exploratory evidence
          （发现集直接参与 DRIFT-2 精确定位）
H-G1-02 = UNVERIFIED + strengthened state-dependency signal
          （两类证据：①旧依据可能只存在于工作记录；
            ②V-5 案例一的正确处置需 W1 记录 + L0 双源对照）
「继续工作时，仅有当前 L0 不一定足够」——距「Execution State
是 PALACE 必需机制」还差一步，这一步交给 G2
```

## 4. G1 收束（CLOSE / 不扩 Corpus）

```text
G1
├── G1 Main Probe       PASS
├── OQ-B                CLOSED
├── E6                  CLOSED
└── H-G1-02             UNVERIFIED（+strengthened signal）
Corpus 扩大与 CJK PDF 复测 = 不做（对核心问题边际收益下降）
```

G1 收束时的证据总账（四条结构性事实）：

```text
① 文件名 ≠ 内容拓扑
② 同名 ≠ 同一信息
③ 时间 ≠ 当前状态（数字漂移 + 公式态/数值态）
④ 信息探索具有路径依赖 + 世界变化后过去工作状态可能无法从
   当前 L0 恢复（OQ-B/E6）
```

## 5. G2 设计入口（方向登记，不预写 RQ）

研究对象推进：

```text
G1：「原始信息发生变化以后怎么办？」
        ↓
G2：「一个正在进行的跨文件工作，如何持续利用已经发现的信息，
     并继续向下一步推进？」
```

依据：G1 已证「发现 → 后续工作」不是完全无状态的；E6 已证
「过去依据 → 现实变化 → 部分失效 → 继续工作需要重新判断」。
G2 最值得验证 = **已有发现能否真正成为下一次工作的起点**
（首次进入第 3 层：分析/对比/汇总）。

禁止带入 G2：

```text
❌ 信息对象 / 关系 / 知识图谱 / Provenance Schema /
   PALACE State Schema 预定义
——让跨文件真实工作继续把下一层抽象逼出来
```

## 6. Gate state

```text
PALACE V2
├── G0  Memory Backend Survey       CLOSED
├── G1  Real Corpus Work            CLOSED
│     ├── OQ-B Drift                CLOSED
│     └── E6 Information Validity   CLOSED
│            │
│            ▼
├── G2  DESIGN ENTRY OPEN
│     （方向 = 跨文件信息工作：analysis / comparison / synthesis；
│       具体设计草案待起草 → human 冻结 → 执行）
└── G3  Durable Information         LOCKED
```
