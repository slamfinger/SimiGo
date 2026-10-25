# PALACE-1 E3 Design — Meta-Only Continuation Ladder

> **ARCHIVED** 2026-10-20 · line: PALACE / Integrated ES · original: docs/00-governance/SIMIGO_LAB_PALACE1_E3_DESIGN_20260930.md
> Evidence status: unchanged (content frozen; moved only)


日期：2026-09-30  
状态：`E3 DESIGN FROZEN / EXECUTION APPROVED (human: "下一刀就应该是 E3")`  
唯一问题：拿掉 safetensors 与 Prefix Pool 后，**只留 metadata**，continuation
还能做什么——以及 continuation-bearing 信息究竟住在 meta/history 的哪一段。  
不扩展成 PALACE schema 设计；不做 State 终判。

## 1. Case C 的操作化

```text
Case A（E1-R1）  history + caller-key + KV   → native restore（KV 缺失 fail-closed）
Case B（R2n）    history + caller-key        → cold reconstruction（KV/pool 缺席仍继续）
Case C（E3）     meta only，内部分解阶梯      → grounding 住在哪一段？
```

Case B 已被 R2n 覆盖（history 源就是 meta.json；checkpoint/pool 缺席）。
E3 的新内容 = **把 meta.history 截断成阶梯**，用「这个会话此前在做什么？」
probe 测 referential grounding 在哪一级消失。

## 2. 阶梯（样本 = E1 baseline meta；会话内容锚极强：桌面文件/参考文件/
项目部管理制度汇编/秦沈项目）

| 级 | history 输入 | msgs | 语义内容 |
|---|---|---|---|
| C-0 | 全部 17 条 | 18 | 完整会话（对照） |
| C-1 | 0–15（去尾条 assistant） | 17 | 主题完整、位置回退 |
| C-2 | 0–4（system + 提醒 + 「你好」交换） | 6 | **会话主题尚未出现** |
| C-3 | 0（仅 system） | 2 | 纯 persona 基线 |

Probe（逐级相同）：「PALACE-1 E3 probe: 这个会话此前在做什么？用一句话
概括。」贪心（temperature 0），maxTokens 64，独立 sessionId 强制 cold
分支。

## 3. 预登记（机械可断言；偏离 = 发现）

```text
PE-1  C-0 ANCHORED（响应含会话锚词：桌面/参考文件/项目部/管理制度/秦沈/文件夹）
PE-2  C-1 ANCHORED（主题完整、仅位置回退）
PE-3  C-2 UNANCHORED（上下文中主题不存在——若 ANCHORED = 重大发现）
PE-4  C-3 UNANCHORED（纯 persona 基线）
全部响应逐字记录；分类 = 锚词机械检测 + 结果文档人工读法
```

## 4. 隔离与纪律

```text
与 R2n 同配方：SIMIGO_PREFIX_POOL=0（env，TEST_RUNNER_ 转发）+
conditionalRestoreEnabled=false（tunable）+ 独立 sessionId → 零 durable
写入（前后 204/24 核验）；零产品代码修改；modelId/权重 = 环境不在 scope。
PENDING 移交：necessity 的普适性（单样本存在性证明）；E3 不回答
「meta-only 是否构成 State」（终判留给 human 与后续 gate）。
```
