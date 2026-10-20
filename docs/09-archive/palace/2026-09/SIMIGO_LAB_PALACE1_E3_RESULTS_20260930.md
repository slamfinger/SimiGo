# PALACE-1 E3 Results — Meta-Only Continuation Ladder

> **ARCHIVED** 2026-10-20 · line: PALACE / Integrated ES · original: docs/00-governance/SIMIGO_LAB_PALACE1_E3_RESULTS_20260930.md
> Evidence status: unchanged (content frozen; moved only)


日期：2026-09-30  
状态：`E3 COMPLETE / AWAITING SECOND-LAYER`  
设计（预登记 PE-1…PE-4）：`SIMIGO_LAB_PALACE1_E3_DESIGN_20260930.md`  
执行：`Palace1E3MetaOnlyLadderTests.swift`（加法式）；66s；TEST SUCCEEDED；
隔离配方同 R2n——**零 durable 写入（204 前后核验）、池缺席、restore 关**；
原始 `~/.simigo` 未动。

## 1. 预登记对照（4/4 CONFIRMED，零偏离）

| 级 | history 输入 | msgs | 响应（逐字） | 锚定 | 判定 |
|---|---|---:|---|---|---|
| C-0 | 全 17 条 | 18 | 「这个会话在查看桌面文件结构，逐步浏览了"参考文件"目录下的"项目部管理制度汇编"内容。」 | **ANCHORED:桌面,参考文件,项目部,管理制度** | PE-1 ✓ |
| C-1 | 0–15（去尾 assistant） | 17 | 「这个会话在查看桌面"参考文件/4.项目部管理制度汇编"目录下的秦沈高速项目经管部管理制度文件结构。」 | **ANCHORED:桌面,参考文件,项目部,管理制度,秦沈** | PE-2 ✓ |
| C-2 | 0–4（主题缺席） | 6 | 「根据当前会话的 MEMORY.md 索引，此前主要在做 **VBA→C dylib 迁移**…以及 **codex-chatgpt 双向桥接**的部署验证」 | UNANCHORED | PE-3 ✓ |
| C-3 | 仅 system | 2 | 「::code-comment{title="Session Context"…This is the initial turn of a new session. No prior work has been performed…}」 | UNANCHORED | PE-4 ✓ |

## 2. 定位结论（human 的核心问题：continuation-bearing 信息住在哪一段）

```text
C-0/C-1：主题在上下文 → grounding 完整（连「秦沈」细节级锚都在）
C-2：主题从上下文消失 → grounding 消失
C-3：仅 persona → 无 grounding
⇒ continuation-bearing 语义住在【会话正文（含 tool 执行历史的交换体）】，
  不住在 system persona、不在寻址/保护/兼容字段。
```

## 3. E3 最重要发现：语义缺席的失败模式是「虚构」而非「拒绝」

C-2 是整条证据链最锋利的一个观测：

> 主题从上下文中消失后，模型**没有拒答、没有报错**，而是从 system
> persona 的先验里**虚构了一个貌似合理、完全错误**的会话概述
> （VBA→C dylib / codex-chatgpt——与本会话毫无关系）。

含义（PALACE 视角，candidate 纪律）：

```text
① durable continuation carrier 若缺失语义正文，失败模式不是
   fail-closed，而是「自信的虚构」（confabulation）——比 E1-R1 的
   文件缺失 fail-closed 危险得多，因为它无法被调用方察觉
② 这从反面完成了 history 必要性的第三种证明：
   不是「有它行为改变」（R2n），而是「无它则产出错误语义」
③ 与 Contract 的 fail-closed 政策（RB-4/RB-6/RB-7：歧义与失配
   禁止静默处理）形成呼应——语义层的 fail-closed 当前【不存在】，
   语义缺席 = 静默虚构。这是未来 PALACE 语义设计必须面对的工程事实
   （登记为发现，不在本轮设计任何机制）
```

## 4. 全链证据地图（E0 → E1 → E1.5 → R2n → E2 → E3）

```text
物理层    E0    checkpoint = 表示(4.7GB) + 七类字段混合体(44KB)
恢复层    E1    R0 识别自足；R1 restore 依赖表示（fail-closed ×3）；
                R2 能力 = cold-start 一等分支
验收层    E1.5  字段角色：storageKey 字段值=informational；history 无
                完整性门；generation=presence；SHA=表示字节；modelId=兼容
必要层    R2n   history 扰动/删除 → continuation 改变/指代崩塌
对照层    E2    Prefix Pool = 可替换性能表示（缺席不失语义；在场 17/17 命中）
定位层    E3    continuation-bearing 语义住在会话正文；persona 零贡献；
                语义缺席 → 虚构（非拒绝）
```

## 5. Non-claims

```text
✔ 单样本、单 probe、贪心——定位结论为存在性/位置性，非普适
✔ 未宣称 meta-only = State；未设计 PALACE schema；未提任何机制修复
✔ 虚构发现（C-2）登记为工程事实，不升级为产品缺陷判定
✔ 零 durable 写入；原始 204 项核验不变
```
